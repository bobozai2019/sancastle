"""Serial visible migration and affected native lifecycle regression."""
import run_display as runner

runner.CASES = {
    **{"migration_" + key: ("unified_edit_migration_entry_probe.gd", key, True)
       for key in ["main", "test1_geometry"]},
    "native_main": ("unified_edit_gravel_entry_probe.gd", "main", True),
    "native_geometry": ("unified_edit_gravel_entry_probe.gd", "test1_geometry", True)}
runner.EXTRA_PINS = ["tools/unified_edit_pipeline/run_migration.py",
                     "tools/unified_edit_pipeline/bake_legacy_catalog.gd",
                     "tests/integration/unified_edit_migration_entry_probe.gd",
                     "tests/integration/unified_edit_configuration_probe.gd",
                     "scripts/simulation/unified_edit/checkpoint_router.gd",
                     "assets/unified_edit/legacy_source_catalog.variant"]

if __name__ == "__main__":runner.main()
