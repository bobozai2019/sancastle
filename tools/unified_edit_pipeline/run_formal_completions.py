import run_display as runner

runner.CASES = {"completion_" + key: ("unified_edit_formal_completion_probe.gd", key, True)
                for key in ["main", "test1_geometry"]}
runner.EXTRA_PINS = ["tools/unified_edit_pipeline/run_formal_completions.py",
                     "tests/integration/unified_edit_formal_completion_probe.gd"]

if __name__ == "__main__":runner.main()
