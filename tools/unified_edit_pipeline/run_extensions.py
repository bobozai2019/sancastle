import run_display as runner

runner.CASES = {name: ("unified_edit_extension_probe.gd", name, False)
                for name in ["fill_base","fill_new","stamp_base","stamp_new","transfer_base","transfer_new"]}
runner.EXTRA_PINS = ["tools/unified_edit_pipeline/run_extensions.py",
                     "tools/unified_edit_pipeline/bake_extension_fixtures.py",
                     "tests/integration/unified_edit_extension_probe.gd"]
if __name__ == "__main__":runner.main()
