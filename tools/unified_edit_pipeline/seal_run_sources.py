"""Preserve the exact pinned source bytes of a terminal immutable probe run."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-archive", type=Path, action="append", default=[])
    parser.add_argument("--allow-failed", action="store_true", help="Archive an immutable failed run without changing its result")
    parser.add_argument("--runner", default="tools/unified_edit_pipeline/run_gpu_contract.ps1", help="Pinned runner whose SHA256 must match the manifest")
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh archive required")
    manifest_path = args.run/"run-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    assert not manifest["drift"]
    assert manifest["pass"] or args.allow_failed
    sources = {p.replace("\\", "/").removeprefix("res://"): h.lower() for p, h in manifest["sources"].items()}
    for relative in ("tools/unified_edit_pipeline/run_gpu_contract.ps1", "tools/unified_edit_pipeline/verify_height.py", "tools/unified_edit_pipeline/verify_water_response.py", "tools/unified_edit_pipeline/verify_views.py", "tools/unified_edit_pipeline/seal_run_sources.py", "tools/unified_edit_pipeline/verify_unit_half.py", "tools/unified_edit_pipeline/verify_initialization.py", "tests/integration/unified_edit_half_probe.gd", "tools/unified_edit_pipeline/verify_suspended.py", "tools/unified_edit_pipeline/audit_gpu_evidence.py", "tools/unified_edit_pipeline/verify_restore.py", "tests/integration/unified_edit_runtime_configuration_probe.gd", "tests/integration/unified_edit_early_lifecycle_probe.gd", "tools/unified_edit_pipeline/verify_early_lifecycle.py", "tools/unified_edit_pipeline/build_g6_restore_component.py", "tools/unified_edit_pipeline/verify_checkpoint.py", "tools/unified_edit_pipeline/native_variant.py", "tools/unified_edit_pipeline/build_g6_capture_component.py"):
        sources[relative] = sha(ROOT/relative)
    sources["tools/unified_edit_pipeline/verify_handoff.py"] = sha(ROOT/"tools/unified_edit_pipeline/verify_handoff.py")
    sources["tools/unified_edit_pipeline/verify_visuals.py"] = sha(ROOT/"tools/unified_edit_pipeline/verify_visuals.py")
    sources["tools/unified_edit_pipeline/verify_boundary.py"] = sha(ROOT/"tools/unified_edit_pipeline/verify_boundary.py")
    sources["tools/unified_edit_pipeline/build_g6_boundary_component.py"] = sha(ROOT/"tools/unified_edit_pipeline/build_g6_boundary_component.py")
    sources["tools/unified_edit_pipeline/build_g6_visual_component.py"] = sha(ROOT/"tools/unified_edit_pipeline/build_g6_visual_component.py")
    sources["tools/unified_edit_pipeline/build_g6_handoff_component.py"] = sha(ROOT/"tools/unified_edit_pipeline/build_g6_handoff_component.py")
    sources[args.runner] = sha(ROOT/args.runner)
    assert sources[args.runner] == manifest["tool_sha256"].lower()
    payloads, recovered = {}, []
    for relative, digest in sources.items():
        path = (ROOT/relative).resolve()
        assert path.is_relative_to(ROOT), relative
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            data = None
            for backup in args.source_archive:
                with zipfile.ZipFile(backup) as archive:
                    if relative in archive.namelist():
                        candidate = archive.read(relative)
                        if hashlib.sha256(candidate).hexdigest() == digest:
                            data = candidate;recovered.append({"source": relative, "archive": str(backup), "archive_sha256": sha(backup)});break
        assert data is not None and hashlib.sha256(data).hexdigest() == digest, relative
        payloads[relative] = data
    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for relative in sorted(sources):
            archive.writestr(relative, payloads[relative])
        archive.write(manifest_path, "evidence/run-manifest.json")
        archive.writestr("evidence/source-index.json", json.dumps(sources, indent=2))
    with zipfile.ZipFile(args.output) as archive:
        assert archive.testzip() is None
        assert all(hashlib.sha256(archive.read(p)).hexdigest() == digest for p, digest in sources.items())
    print(json.dumps({"pass": True, "path": str(args.output.resolve()), "sha256": sha(args.output), "files": len(sources), "run_manifest_sha256": sha(manifest_path), "recovered_exact_archived_members": recovered}))


if __name__ == "__main__":
    main()
