"""Conservative resource graph and fail-closed writer boundary certificate.

Resource references are an upper bound, not a claim that every referenced legacy
method executes. Sensitive method bodies require an explicitly reviewed policy.
No resource name or renamed symbol can grant writer permission.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PREFIX = 'scripts/simulation/unified_edit/'
ROOTS = ['scenes/main.tscn',  'scenes/playable/test1_geometry.tscn',
         'scripts/beach/beach_scene_service.gd', 'assets/unified_edit/extensions/extension_catalog.tres']
TEXT = {'.gd', '.tscn', '.tres', '.glsl', '.gdshader', '.glslinc', '.json', '.godot'}
PATH = re.compile(r'res://[A-Za-z0-9_./-]+\.[A-Za-z0-9]+')
# lexical masking preserves line count and excludes comments/strings from code.
TOKEN = re.compile(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|\#[^\n]*|//[^\n]*|/\*[\s\S]*?\*/')
SENSITIVE = re.compile(r'\b(?:imageStore|atomic\w*|buffer_update|texture_update|texture_create|storage_buffer_create|compute_list_\w+|call_on_render_thread|set_script|callv|load|preload|new|call|call_deferred|Callable|wait_for_task_completion|wait_to_finish|apply_force|apply_impulse|body_test_motion)\s*\(')

def sha(data): return hashlib.sha256(data).hexdigest()

def mask(source):
    return TOKEN.sub(lambda m: ''.join('\n' if c == '\n' else ' ' for c in m[0]), source)

def graph(overrides=None):
    overrides = overrides or {}
    pending = list(ROOTS); sources = {}; edges = []; missing = []
    while pending:
        name = pending.pop()
        if name in sources: continue
        path = ROOT / name
        if not path.is_file(): missing.append(name); continue
        raw = overrides.get(name, path.read_bytes())
        sources[name] = raw
        if path.suffix not in TEXT: continue
        source = raw.decode('utf-8-sig')
        # comments excluded, literal resource identities retained for graph edges.
        for line, text in enumerate(source.splitlines(), 1):
            if text.lstrip().startswith(('#', '//')): continue
            for target in PATH.findall(text):
                target = target.removeprefix('res://')
                if target.startswith(('test_output/', 'user/')): continue
                edges.append({'from': name, 'line': line, 'to': target})
                if target not in sources: pending.append(target)
    return sources, edges, sorted(set(missing))

def methods(source):
    starts = list(re.finditer(r'^(?:static )?func ([A-Za-z_]\w*)\(', source, re.M))
    result = [('declarations', source[:starts[0].start()] if starts else source)]
    for i, item in enumerate(starts):
        result.append((item[1], source[item.start():starts[i+1].start() if i+1<len(starts) else len(source)]))
    return result

def inventory(sources):
    output = {}
    for path, raw in sorted(sources.items()):
        if Path(path).suffix not in {'.gd', '.glsl', '.glslinc'}: continue
        if not (path.startswith((PREFIX,'scripts/props/')) or path in {'scripts/beach/unified_playable_entry.gd','scripts/beach/beach_scene_service.gd'}):continue
        source = raw.decode('utf-8-sig')
        chunks = methods(source) if path.endswith('.gd') else [('shader', source)]
        for method, body in chunks:
            hits = sorted(set(SENSITIVE.findall(mask(body))))
            # Assignments in shaders include SSBO writes, not only imageStore.
            if method == 'shader' and re.search(r'\w+\s*\[[^\]]+\]\s*(?:[+*/-]?=|\+\+|--)', mask(body)):
                hits.append('indexed_shader_assignment')
            if hits:
                output[path+'::'+method] = {'sha256': sha(body.encode()), 'tokens': hits}
    return output

def evaluate(sources, policy):
    checks = []
    def check(name, value): checks.append({'name': name, 'pass': bool(value)})
    current = inventory(sources)
    approved = policy.get('sensitive_methods', {})
    for key, value in current.items():
        check('reviewed_sensitive_method:'+key, key in approved and value['sha256']==approved[key]['sha256'] and bool(approved[key].get('reason')))
    for key in approved: check('reviewed_method_still_present:'+key, key in current)
    for path, raw in sources.items():
        if not path.startswith(PREFIX) or not path.endswith('.gd'): continue
        source = raw.decode('utf-8-sig'); code = mask(source)
        check('no_script_replacement:'+path, not re.search(r'\bset_script\s*\(', code))
        # All literal profile IDs are forbidden in execution core; identity and
        # immutable registry lookup without literal specialization are allowed.
        if Path(path).name not in {'player_input.gd','api_adapter.gd','boundary.gd','checkpoint_codec.gd','visuals.gd'}:
            ids = policy.get('tool_ids', [])
            check('no_tool_literal_specialization:'+path, not any(re.search(r'["\']'+re.escape(item)+r'["\']',source) for item in ids))
        if Path(path).name in {'executor.gd','pipeline.gd','water.gd','water_response.gd','height.gd'}:
            for method,body in methods(source):
                waits=re.findall(r'\b(?:await|wait_for_task_completion|wait_to_finish)\b',mask(body))
                guarded=(path==PREFIX+'height.gd' and method=='physics_consume' and
                         'not WorkerThreadPool.is_task_completed(slot.task):continue' in body and
                         waits==['wait_for_task_completion'])
                check('no_blocking_collision_wait:'+path+'::'+method,not waits or guarded)
    registry = sources[PREFIX+'profile_registry.gd'].decode()
    check('registry_exact_profile_script', 'resource.get_script()!=Profile' in registry)
    check('registry_snapshot_not_callback', 'pending[key]=checked.value.duplicate(true)' in registry)
    profile = sources[PREFIX+'tool_profile.gd'].decode()
    check('template_exact_script', 'shape_resource.get_script()!=Stamp' in profile)
    configuration=sources[PREFIX+'configuration.gd'].decode()
    check('configuration_keys_sort_by_string_content','keys.sort_custom(func(first,second):return String(first)<String(second))' in configuration)
    runtime = sources[PREFIX+'domain_runtime.gd'].decode()
    check('boot_restore_only_pipeline_factories', re.findall(r'\b(\w+)\.new\s*\(',mask(runtime)) == ['Pipeline','Pipeline'])
    prop_service=sources['scripts/props/floating_props_service.gd'].decode()
    check('props_exact_body_and_profile_scripts','row.body.get_script()!=Body' in prop_service and 'row.profile.get_script()!=Profile' in prop_service)
    check('props_collider_envelope_checked','Contact.enclosing_radius(row.body)' in prop_service and 'envelope.radius_m>row.body.footprint_radius_m' in prop_service)
    for path,raw in sources.items():
        if not path.startswith('scripts/props/') or not path.endswith('.gd'):continue
        source=raw.decode('utf-8-sig');code=mask(source)
        check('props_no_backend_or_authority_access:'+path,not re.search(r'\b(?:RenderingServer|RenderingDevice|WorkerThreadPool|executor|primary|spare|water_response|heights_rd|rd)\b|\.(?:fields|native_fields|dispatch|record_tick)\b',code))
        check('props_no_type_literal_specialization:'+path,not any(re.search(r'["\']'+re.escape(item)+r'["\']',source) for item in ['bottle','wood_plank','wood_stick']))
        if path.endswith('floating_prop_profile.gd'):
            check('prop_profile_data_only',all(name in {'declarations','validate','snapshot'} for name,_ in methods(source)) and not re.search(r'\b(?:await|call|callv|Callable|new|load|preload|apply_force)\s*\(',code))
    # Structural source identities for factory/registration/resource gates are
    # reviewed too, so renamed writer APIs cannot bypass token detection.
    for path, value in policy.get('sealed_boundaries', {}).items():
        check('sealed_boundary:'+path, path in sources and sha(sources[path])==value['sha256'] and bool(value.get('reason')))
    for path in sources:
        if Path(path).suffix in {'.gd','.glsl','.glslinc','.tscn','.gdshader'}:
            check('no_unreviewed_executable_resource:'+path,path in policy.get('sealed_boundaries',{}))
        if path.startswith('assets/unified_edit/') and path.endswith('.tres'):
            text=sources[path].decode('utf-8-sig')
            scripts=re.findall(r'type="Script" path="res://([^"]+)"',text)
            check('typed_resource_binding:'+path,len(scripts)==1 and scripts[0] in {PREFIX+'tool_profile.gd',PREFIX+'height_stamp.gd',PREFIX+'profile_catalog.gd'})
        if path.startswith('assets/props/') and path.endswith('.tres'):
            scripts=re.findall(r'type="Script" path="res://([^"]+)"',sources[path].decode('utf-8-sig'))
            check('typed_prop_resource_binding:'+path,scripts==['scripts/props/floating_prop_profile.gd'])
    for path,value in policy.get('startup_tooling_boundaries',{}).items():
        target=ROOT/path
        check('startup_tooling_boundary:'+path,target.is_file() and sha(target.read_bytes())==value['sha256'] and bool(value.get('reason')))
    return checks

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--policy',type=Path);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();sources,edges,missing=graph()
    folder=args.output;folder.mkdir(parents=True,exist_ok=False)
    if not args.policy:
        (folder/'inventory.json').write_text(json.dumps({'sensitive_methods':inventory(sources),'sources':{p:sha(b) for p,b in sources.items()},'edges':edges,'missing':missing},indent=2),'utf-8')
        print('INVENTORY',len(sources),len(edges),len(inventory(sources)),'missing',missing);return
    policy=json.loads(args.policy.read_text('utf-8-sig'))
    checks=evaluate(sources,policy)
    checks.append({'name':'missing_references_match_explicit_nonruntime_evidence', 'pass':set(missing)==set(policy.get('nonruntime_missing_references',{})) and all(policy['nonruntime_missing_references'].values())})
    actual=json.loads((ROOT/policy['actual_nodes_evidence']['path']).read_text('utf-8-sig'))
    checks.append({'name':'actual_packed_scene_nodes_identity', 'pass':actual['pass'] and len(actual['entries'])==2 and sha((ROOT/policy['actual_nodes_evidence']['path']).read_bytes())==policy['actual_nodes_evidence']['sha256'] and all(sha((ROOT/e['path'].removeprefix('res://')).read_bytes())==e['sha256'] for e in actual['entries'])})
    mutants=[
        ('private_writer',PREFIX+'player_input.gd','\nfunc forbidden():\n\trd.texture_update(authority,0,bytes)\n'),
        ('tool_name_branch',PREFIX+'executor.gd','\nfunc forbidden(value):\n\tif value.profile_id==&"wide_fill_v1":return\n'),
        ('legacy_fallback','scripts/beach/beach_scene_service.gd','\nfunc forbidden():return load("res://scripts/beach/async_pipeline_entry.gd").new()\n'),
        ('blocking_collision',PREFIX+'height.gd','\nfunc forbidden():\n\tWorkerThreadPool.wait_for_task_completion(1)\n'),
        ('removed_worker_completion_guard',PREFIX+'height.gd',''),
        ('dynamic_callback',PREFIX+'profile_registry.gd','\nfunc forbidden(resource):resource.call("execute",authority)\n'),
        ('inherited_writer',PREFIX+'tool_profile.gd','\nfunc forbidden():set_script(load("res://scripts/beach/async_pipeline_entry.gd"))\n'),
        ('renamed_writer',PREFIX+'domain_runtime.gd','\nfunc concealed():\n\tvar alias=current.executor\n\talias.record(a,b,c,d,e)\n'),
        ('prop_private_writer','scripts/props/floating_props_service.gd','\nfunc forbidden():\n\truntime.current.executor.record(a,b,c,d,e)\n'),
        ('prop_profile_callback','scripts/props/floating_prop_profile.gd','\nfunc forbidden(owner):owner.call("execute")\n'),
        ('compatibility_bypass',PREFIX+'consumer_checkpoint_sources.gd','\nstatic func forbidden(value):return {"error":&"","checkpoint":value}\n'),
        ('unstable_configuration_key_sort',PREFIX+'configuration.gd',''),
        ('vegetation_private_schedule',PREFIX+'vegetation.gd','\nfunc forbidden():\n\tRenderingServer.call_on_render_thread(Callable())\n'),
        ('vegetation_authority_write','shaders/simulation/vegetation_step_momentum.glsl','\nvoid forbidden(){imageStore(sand,ivec2(0),vec4(1));}\n'),
        ('vegetation_profile_callback','scripts/visual/vegetation_profile.gd','\nfunc forbidden(owner):owner.call("execute")\n'),
    ]
    negatives=[]
    for name,path,addition in mutants:
        changed=sources.copy();changed[path]=sources[path]+addition.encode()
        if name=='removed_worker_completion_guard':changed[path]=changed[path].replace(b'not WorkerThreadPool.is_task_completed(slot.task):continue',b'false:continue')
        if name=='unstable_configuration_key_sort':changed[path]=changed[path].replace(b'keys.sort_custom(func(first,second):return String(first)<String(second))',b'keys.sort()')
        failures=[c['name'] for c in evaluate(changed,policy) if not c['pass']]
        negatives.append({'name':name,'pass':bool(failures),'failures':failures})
    changed=sources.copy();resource='assets/unified_edit/extensions/wide_fill_v1.tres'
    changed[resource]=changed[resource].replace(b'scripts/simulation/unified_edit/tool_profile.gd',b'scripts/beach/async_pipeline_entry.gd')
    failures=[c['name'] for c in evaluate(changed,policy) if not c['pass']]
    negatives.append({'name':'resource_private_writer_binding','pass':bool(failures),'failures':failures})
    changed=sources.copy();resource='assets/props/bottle_profile.tres'
    changed[resource]=changed[resource].replace(b'scripts/props/floating_prop_profile.gd',b'scripts/beach/async_pipeline_entry.gd')
    failures=[c['name'] for c in evaluate(changed,policy) if not c['pass']]
    negatives.append({'name':'prop_resource_writer_binding','pass':bool(failures),'failures':failures})
    checks.extend({'name':'reject_mutant:'+row['name'],'pass':row['pass']} for row in negatives)
    with zipfile.ZipFile(folder/'sources.zip','x',zipfile.ZIP_DEFLATED) as z:
        for path,raw in sorted(sources.items()):z.writestr(path,raw)
        z.write(args.policy,'policy.json');z.write(__file__,'audit_architecture.py')
        for path in policy.get('startup_tooling_boundaries',{}):
            if path not in sources:z.write(ROOT/path,path)
        z.write(ROOT/policy['actual_nodes_evidence']['path'],'evidence/actual_nodes.json')
    with zipfile.ZipFile(folder/'sources.zip') as z:
        assert z.testzip() is None
        assert len(z.namelist())==len(set(z.namelist()))
        assert all(sha(z.read(path))==sha(raw) for path,raw in sources.items())
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'negatives':negatives,'edges':edges,'sources':{p:sha(b) for p,b in sources.items()},'missing':missing,'source_zip_sha256':sha((folder/'sources.zip').read_bytes()),'policy_sha256':sha(args.policy.read_bytes()),'scope':'Conservative resource-reference closure plus sealed reviewed sensitive methods/factories; not an unrestricted language call-graph theorem. Debugger autoload is separately declared development tooling.'}
    (folder/'report.json').write_text(json.dumps(result,indent=2),'utf-8')
    print('ARCHITECTURE',result['pass'],'checks',len(checks),'sources',len(sources),'edges',len(edges))
    print('FAILURES',[x['name'] for x in checks if not x['pass']])
    raise SystemExit(0 if result['pass'] else 1)

if __name__=='__main__':main()
