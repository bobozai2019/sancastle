"""Serial visible front-end tool and lifecycle cases."""
import run_display as runner

runner.CASES = {**{"suite_" + key: ("unified_edit_front_lifecycle_probe.gd", "suite_" + key, True)
                   for key in ["main", "test1_capture", "test1_backwash", "test1_geometry"]},
                **{mode + "_" + key: ("unified_edit_front_lifecycle_probe.gd", mode + "_" + key, True)
                   for mode in ["save", "close"] for key in ["main", "test1_geometry"]}}
runner.CASES["pointer"] = ("unified_edit_pointer_probe.gd", "main", True)
runner.EXTRA_PINS = ["tools/unified_edit_pipeline/run_front_lifecycle.py",
                     "tests/integration/unified_edit_front_lifecycle_probe.gd"]

if __name__ == "__main__":runner.main()
