"""The shared serial runner with explicit preview cases and source pins."""
import run_display as runner

runner.CASES = {"snapshot": ("unified_edit_snapshot_preview_probe.gd", "snapshot", False),
                **{"entry_" + key: ("unified_edit_live_preview_probe.gd", key, True)
                   for key in ["main", "test1_capture", "test1_backwash", "test1_geometry"]},
                "views_core": ("unified_edit_views_probe.gd", "views_core", False),
                "views_fatal": ("unified_edit_views_probe.gd", "views_fatal", False),
                "handoff_preview": ("unified_edit_handoff_probe.gd", "handoff_preview", False),
                "handoff_detach": ("unified_edit_handoff_probe.gd", "handoff_detach", False),
                "pointer": ("unified_edit_pointer_probe.gd", "main", True)}
runner.EXTRA_PINS = ["tools/unified_edit_pipeline/run_preview.py",
                     "tests/integration/unified_edit_snapshot_preview_probe.gd",
                     "tests/integration/unified_edit_live_preview_probe.gd",
                     "tests/integration/unified_edit_views_probe.gd",
                     "tests/integration/unified_edit_height_probe.gd",
                     "tests/integration/unified_edit_suspended_probe.gd"]

if __name__ == "__main__":runner.main()
