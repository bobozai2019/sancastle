"""Index small diagnosis outputs and verify measured production identities."""
import hashlib, json
from pathlib import Path

project=Path(__file__).resolve().parents[2]
root=project/'test_output/edit_stutter_diagnosis'
runs=['short_baseline','short_detailed','dense_drag']
traces={run:json.loads((root/run/'trace.json').read_text(encoding='utf-8')) for run in runs}
signature=traces[runs[0]]['configuration']['profile']
sources=[]
for uri, expected in signature['sources'].items():
    path=project/uri.removeprefix('res://')
    actual=hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
    sources.append({'path':str(path),'expected_sha256':expected,'end_sha256':actual,'equal':expected==actual})
checks={run:{'released':trace['released'],'begin_ticks':[c['begin_tick'] for c in trace['cases']],
             'errors':[c['error'] for c in trace['cases']],
             'signature_equal':trace['configuration']['profile']==signature,
             'origin_sha256':trace['configuration']['origin_sha256']} for run,trace in traces.items()}
verification={'sources':sources,'runs':checks,'all_end_sources_equal':all(r['equal'] for r in sources),
              'origin_identical':len({r['origin_sha256'] for r in checks.values()})==1,
              'scope':'exact file identity; checkpoint reset succeeded but no new independent per-case ten-field readback proof'}
(root/'source_verification.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2),encoding='utf-8')
# Reconstruct the loaded first observer from the recorded tool edit sequence.
# Explicitly not a contemporaneous runtime source export.
text=(root/'short_detailed/probe_source.gd').read_text(encoding='utf-8')
text=text.replace('\t# Restore creates a new solver; timing switches must follow that actual owner.\n\tRenderingServer.call_on_render_thread(_enable_gpu_times)\n\tawait process_frame\n','')
text=text.replace('\tif name=="dig_paused": root.get_texture().get_image().save_png(output.path_join("visible_main.png"))\n','')
text=text.replace('"render_profile_sha256":preview.requested_render_profile_sha256,"effective_compilation":preview.effective_compilation,','')
(root/'short_baseline/probe_source.gd').write_text(text,encoding='utf-8')
files=list(root.rglob('*'))+list((project/'tools/edit_stutter_diagnosis').glob('*.py'))+list((project/'tools/edit_stutter_diagnosis').glob('*.gd'))
files += [project/'docs/search/edit_stutter_diagnosis.md',Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')]
manifest=[]
for path in sorted(set(files)):
    if not path.is_file() or path.name=='manifest.json': continue
    manifest.append({'path':str(path),'size':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                     'source_note':'reconstructed from tool edit sequence' if path==root/'short_baseline/probe_source.gd' else None})
(root/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'end_sources_equal':verification['all_end_sources_equal'],'origin_identical':verification['origin_identical'],
                  'source_count':len(sources),'files':len(manifest),'runs':checks},ensure_ascii=False))
