"""Final targeted formal ownership and unchanged visual/migration adapters."""
import run_display as runner

runner.CASES = {**{mode + "_" + key: ("unified_edit_formal_final_lifecycle_probe.gd", mode + "_" + key, True)
                   for mode in ["boot", "restoreclose", "faultrestore", "faultclose", "detach"]
                   for key in ["main", "test1_geometry"]},
                **{mode + "_" + key: (script, key, True)
                   for mode, script in [("preview", "unified_edit_formal_preview_probe.gd"),
                                        ("gravel", "unified_edit_formal_gravel_probe.gd"),
                                        ("migration", "unified_edit_formal_migration_probe.gd")]
                   for key in ["main", "test1_geometry"]}}
runner.EXTRA_PINS = ["tools/unified_edit_pipeline/run_formal_remaining.py",
                     "tests/integration/unified_edit_formal_final_lifecycle_probe.gd",
                     "tests/integration/unified_edit_formal_preview_probe.gd",
                     "tests/integration/unified_edit_formal_gravel_probe.gd",
                     "tests/integration/unified_edit_formal_migration_probe.gd",
                     "tests/integration/unified_edit_live_preview_probe.gd",
                     "tests/integration/unified_edit_migration_entry_probe.gd"]

if __name__ == "__main__":runner.main()
