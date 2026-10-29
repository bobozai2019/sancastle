import run_display as runner

runner.CASES={f'{kind}_{water}_{material}':('unified_edit_extension_features_probe.gd',f'{kind}_{water}_{material}',False)
              for kind,materials in [('fill',[0]),('stamp',[0,1]),('transfer',[2])]
              for water in range(4) for material in materials}
runner.EXTRA_PINS=['tools/unified_edit_pipeline/run_extension_features.py',
                   'tests/integration/unified_edit_extension_probe.gd',
                   'tests/integration/unified_edit_extension_features_probe.gd']
if __name__=='__main__':runner.main()
