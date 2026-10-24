"""Serial formal tools, save/close and actual unknown-reader boundaries."""
import run_display as runner

runner.CASES = {**{mode + "_" + key: ("unified_edit_formal_boundary_probe.gd", mode + "_" + key, True)
                   for mode in ["capture", "height", "physics", "recorded"] for key in ["main", "test1_geometry"]},
                **{mode + "_" + key: ("unified_edit_formal_front_probe.gd", mode + "_" + key, True)
                   for mode in ["suite"] for key in ["main", "test1_geometry"]},
                **{mode + "_" + key: ("unified_edit_formal_front_probe.gd", mode + "_" + key, True)
                   for mode in ["save", "close"] for key in ["main", "test1_geometry"]}}
runner.CASES.update({"candidate_" + key: ("unified_edit_formal_candidate_fail_probe.gd", key, True)
                     for key in ["main", "test1_geometry"]})
runner.EXTRA_PINS = ["tools/unified_edit_pipeline/run_formal_boundaries.py",
                     "tests/integration/unified_edit_formal_boundary_probe.gd",
                     "tests/integration/unified_edit_formal_front_probe.gd",
                     "tests/integration/unified_edit_formal_candidate_fail_probe.gd",
                     "tests/integration/unified_edit_front_lifecycle_probe.gd"]

if __name__ == "__main__":runner.main()
