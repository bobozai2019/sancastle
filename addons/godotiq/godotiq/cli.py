"""GodotIQ CLI — argument parsing and subcommand dispatch."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def cli_main() -> None:
    """Parse arguments and dispatch to the appropriate handler."""
    # Early exit for --version: avoid any imports that might trigger warnings
    if len(sys.argv) > 1 and sys.argv[1] == "--version":
        from importlib.metadata import PackageNotFoundError
        from importlib.metadata import version as pkg_version

        try:
            ver = pkg_version("godotiq")
        except PackageNotFoundError:
            ver = "0.0.0-dev"
        print(f"godotiq {ver}")
        raise SystemExit(0)

    from godotiq import __version__

    parser = argparse.ArgumentParser(
        prog="godotiq",
        description="GodotIQ — The definitive MCP for AI-assisted Godot development.",
    )
    # Kept for --help display; unreachable due to early exit above
    parser.add_argument(
        "--version", action="version", version=f"godotiq {__version__}"
    )

    subparsers = parser.add_subparsers(dest="command")

    install_parser = subparsers.add_parser(
        "install-addon", help="Copy GodotIQ addon files to a Godot project"
    )
    install_parser.add_argument("path", help="Path to Godot project root")
    install_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would be copied without writing files",
    )

    auth_parser = subparsers.add_parser(
        "auth", help="Inspect or manage Pro license state"
    )
    auth_sub = auth_parser.add_subparsers(dest="auth_command")
    status_parser = auth_sub.add_parser(
        "status",
        help=(
            "Show current license tier, receipt status, bundle status, and "
            "actionable hint when something is wrong. Exits 0 if Pro is "
            "fully usable OR no key is configured; exits 2 if a key is "
            "configured but Pro entitlement is broken."
        ),
    )
    status_parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the raw diagnostic dict as JSON (for scripts).",
    )
    reset_parser = auth_sub.add_parser(
        "reset",
        help=(
            "Clear local Pro license state so the next startup performs a "
            "fresh activation. Does not remove the downloaded bundle cache."
        ),
    )
    reset_parser.add_argument(
        "--yes",
        action="store_true",
        help="Confirm deletion of local license state.",
    )
    reset_parser.add_argument(
        "--json",
        action="store_true",
        help="Emit reset result as JSON.",
    )

    args = parser.parse_args()

    if args.command is None:
        _serve()
    elif args.command == "install-addon":
        install_addon(args.path, dry_run=args.dry_run)
    elif args.command == "auth":
        if args.auth_command == "status":
            raise SystemExit(_auth_status_cmd(json_out=args.json))
        if args.auth_command == "reset":
            raise SystemExit(_auth_reset_cmd(yes=args.yes, json_out=args.json))
        auth_parser.print_help()
        sys.exit(1)
    else:
        parser.print_help()
        sys.exit(1)


def _auth_status_cmd(json_out: bool = False) -> int:
    """Print the license diagnostic. Exit code: 0 if ok, 2 if broken.

    Never prints raw secrets — license-key and dev-key fields are reported
    only as boolean "configured" flags. Reasons and hints are enum-keyed
    strings safe to display.
    """
    import json as _json

    # Lazy imports: cli is loaded for `--version` too, and we want that to
    # stay free of network/license imports.
    from godotiq.license import license_diagnostic
    from godotiq.pro_loader import ensure_pro_bundle

    # Boot the Pro bundle the same way the MCP server does at startup
    # (server.py:_lifespan). Without this, pro_status() returns the
    # module-level default "community" for every Pro user, because the
    # bundle is loaded only inside the running MCP server process — never
    # in this short-lived CLI process. Result: `auth status` reported
    # bundle: community / reason: bundle_unavailable for paying users
    # whose bundle would have loaded fine on the server side.
    # Errors here must NOT propagate: ensure_pro_bundle() already swallows
    # everything internally and falls back to "community" on any failure,
    # so there is no exception to catch — but be defensive in case the
    # contract changes, since auth status must always emit the diagnostic.
    try:
        ensure_pro_bundle()
    except Exception:  # noqa: BLE001 - defensive: diagnostic must always run
        pass

    diag = license_diagnostic()

    if json_out:
        print(_json.dumps(diag, indent=2, sort_keys=True))
    else:
        ok = diag["ok"]
        print(f"tier:         {diag['tier']}")
        print(f"receipt:      {diag['receipt']}")
        print(f"bundle:       {diag['bundle']}")
        print(f"license_key:  {'configured' if diag['license_key_configured'] else 'not set'}")
        if diag["dev_key_configured"]:
            print("dev_mode:     on")
        print(f"status:       {'OK' if ok else 'NOT OK'}")
        if not ok:
            print(f"reason:       {diag.get('reason', '')}")
            print(f"hint:         {diag.get('hint', '')}")
            if diag.get("bundle_error_detail"):
                print(f"bundle error: {diag['bundle_error_detail']}")
            if diag.get("manage"):
                print(f"manage seats: {diag['manage']}")
            if diag.get("upgrade"):
                print(f"upgrade:      {diag['upgrade']}")

    return 0 if diag["ok"] else 2


def _auth_reset_cmd(yes: bool = False, json_out: bool = False) -> int:
    """Clear local license state after explicit confirmation."""
    import json as _json
    import shutil

    from godotiq import license as lic
    from godotiq import paths

    state_dir = paths.license_state_dir()
    if not yes:
        result = {
            "ok": False,
            "state_dir": str(state_dir),
            "error": "confirmation_required",
            "hint": "Re-run with: godotiq auth reset --yes",
        }
        if json_out:
            print(_json.dumps(result, indent=2, sort_keys=True))
        else:
            print(
                f"Refusing to clear license state without --yes.\n"
                f"State directory: {state_dir}\n"
                "Re-run with: godotiq auth reset --yes",
                file=sys.stderr,
            )
        return 1

    removed: list[str] = []
    errors: list[str] = []
    if state_dir.exists():
        for child in sorted(state_dir.iterdir(), key=lambda p: p.name):
            try:
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
                removed.append(child.name)
            except OSError as exc:
                errors.append(f"{child.name}: {exc}")
    state_dir.mkdir(parents=True, exist_ok=True)
    lic._reset_license_cache()

    result = {
        "ok": not errors,
        "state_dir": str(state_dir),
        "removed": removed,
        "removed_count": len(removed),
    }
    if errors:
        result["errors"] = errors

    if json_out:
        print(_json.dumps(result, indent=2, sort_keys=True))
    else:
        if errors:
            print(f"License state reset incomplete: {state_dir}", file=sys.stderr)
            for error in errors:
                print(f"  error: {error}", file=sys.stderr)
        else:
            print(f"License state cleared: {state_dir}")
            print("Restart your MCP client to activate again.")
    return 0 if not errors else 2


def _serve() -> None:
    """Start the MCP server (lazy import to avoid loading all tools for other subcommands)."""
    from godotiq.server import main

    main()


_ADDON_EXTENSIONS = {".gd", ".cfg"}

_MARKER_START = "<!-- GODOTIQ RULES START -->"
_MARKER_END = "<!-- GODOTIQ RULES END -->"

# Convention files for various AI coding assistants.
# Each entry: (relative path from project root, needs_parent_mkdir)
_CONVENTION_FILES: list[tuple[str, bool]] = [
    ("CLAUDE.md", False),
    ("AGENTS.md", False),
    (".cursorrules", False),
    (".windsurfrules", False),
    (".github/copilot-instructions.md", True),
]


def _inject_rules(file_path: Path, rules_content: str) -> str:
    """Inject rules between markers into a file, creating it if needed.

    Returns 'added', 'updated', or 'unchanged'.
    """
    block = f"{_MARKER_START}\n{rules_content}\n{_MARKER_END}\n"

    if file_path.exists():
        existing = file_path.read_text()
        pattern = re.compile(
            re.escape(_MARKER_START) + r".*?" + re.escape(_MARKER_END) + r"\n?",
            re.DOTALL,
        )
        if pattern.search(existing):
            new_content = pattern.sub(block, existing)
            if new_content == existing:
                return "unchanged"
            file_path.write_text(new_content)
            return "updated"
        # File exists but no markers — append
        separator = "" if existing.endswith("\n") else "\n"
        file_path.write_text(existing + separator + "\n" + block)
        return "updated"

    # File does not exist — create
    file_path.write_text(block)
    return "added"


def install_addon(target_dir: str, dry_run: bool = False) -> None:
    """Copy addon files, GODOTIQ_RULES.md, and inject rules into convention files."""
    import shutil

    target = Path(target_dir).expanduser().resolve()
    if not target.is_dir():
        print(f"Error: directory does not exist: {target}", file=sys.stderr)
        sys.exit(1)
    if not (target / "project.godot").exists():
        print(
            f"Error: {target} does not appear to be a Godot project (no project.godot found)",
            file=sys.stderr,
        )
        sys.exit(1)

    # Locate source files
    pkg_dir = Path(__file__).resolve().parent
    addon_src = pkg_dir / "addon"
    rules_src = pkg_dir / "prompts" / "godot_development.md"

    # In editable installs, force-include files aren't in addon/.
    # Fall back to the repo's godot-addon/ directory.
    has_addon_files = (
        addon_src.is_dir()
        and any(f.suffix in _ADDON_EXTENSIONS for f in addon_src.iterdir() if f.is_file())
    )
    if not has_addon_files:
        repo_addon = pkg_dir.parent.parent / "godot-addon" / "addons" / "godotiq"
        if repo_addon.is_dir():
            addon_src = repo_addon

    # Build copy manifest: (source, destination, relative_display_path)
    manifest: list[tuple[Path, Path, str]] = []

    for f in sorted(addon_src.iterdir()):
        if f.suffix in _ADDON_EXTENSIONS:
            dst = target / "addons" / "godotiq" / f.name
            manifest.append((f, dst, f"addons/godotiq/{f.name}"))

    if not manifest:
        print("Error: could not locate addon source files.", file=sys.stderr)
        sys.exit(1)

    if rules_src.exists():
        manifest.append((rules_src, target / "GODOTIQ_RULES.md", "GODOTIQ_RULES.md"))

    # Read rules content for convention files
    rules_content = rules_src.read_text() if rules_src.exists() else ""

    # Dry-run mode
    if dry_run:
        print(f"[dry-run] Would install GodotIQ addon to {target}")
        for _, _, rel in manifest:
            print(f"  would copy: {rel}")
        if rules_content:
            for rel_path, _ in _CONVENTION_FILES:
                print(f"  would inject rules: {rel_path}")
        return

    # Create destination directory
    (target / "addons" / "godotiq").mkdir(parents=True, exist_ok=True)

    # Copy files and report
    print(f"Installing GodotIQ addon to {target} ...")
    added = 0
    updated = 0
    for src, dst, rel in manifest:
        existed = dst.exists()
        shutil.copy2(src, dst)
        status = "updated" if existed else "added"
        if existed:
            updated += 1
        else:
            added += 1
        print(f"  {status:>9s}: {rel}")

    # Inject rules into convention files for AI coding assistants
    if rules_content:
        for rel_path, needs_mkdir in _CONVENTION_FILES:
            conv_file = target / rel_path
            if needs_mkdir:
                conv_file.parent.mkdir(parents=True, exist_ok=True)
            status = _inject_rules(conv_file, rules_content)
            if status == "added":
                added += 1
            elif status == "updated":
                updated += 1
            print(f"  {status:>9s}: {rel_path}")

    print(f"\nDone. {added} files added, {updated} files updated.")
