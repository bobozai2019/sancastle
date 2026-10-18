"""Serial formal entry boot/native lifecycle and family-routing regression."""
import run_display as runner

runner.CASES = {"startup": ("unified_edit_formal_startup_probe.gd", "main", True),
                **{"formal_" + key: ("unified_edit_formal_probe.gd", key, True)
                   for key in ["main", "test1_capture", "test1_backwash", "test1_geometry"]},
                "formal_service": ("unified_edit_formal_service_probe.gd", "main", True),
                "candidate_service": ("unified_edit_scene_service_probe.gd", "main", True)}
runner.EXTRA_PINS = ["tools/unified_edit_pipeline/run_formal.py",
                     "tests/integration/unified_edit_formal_startup_probe.gd",
                     "tests/integration/unified_edit_formal_probe.gd",
                     "tests/integration/unified_edit_formal_service_probe.gd",
                     "tests/integration/unified_edit_scene_service_probe.gd",
                     "scripts/beach/unified_scene_routes.gd"]

if __name__ == "__main__":runner.main()
