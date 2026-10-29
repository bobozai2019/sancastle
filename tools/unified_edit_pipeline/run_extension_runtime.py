import run_display as runner
runner.CASES={'extension_runtime':('unified_edit_extension_runtime_probe.gd','extension_runtime',False)}
runner.EXTRA_PINS=['tools/unified_edit_pipeline/run_extension_runtime.py',
                   'tests/integration/unified_edit_extension_runtime_probe.gd']
if __name__=='__main__':runner.main()
