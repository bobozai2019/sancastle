"""Create an isolated historical reference copy for paired G8 cost probes.

Archived source bytes always win. Additional immutable resources/import caches
are copied, never linked or edited in the original workspace. Missing references
are indexed rather than replaced with placeholders.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile
ROOT=Path(__file__).resolve().parents[2]
REFERENCE=ROOT/'test_output/unified_edit_pipeline/g0_final_reference_20261018/reference_sources.zip'
EXPECTED='c80d051495eafd39fe7b69d6e4b0ed22f62a474b7658593bb0fc38cf8ff1939a'
TEXT={'.gd','.tscn','.tres','.gdshader','.glsl','.glslinc','.json','.import','.cfg','.godot'}
PATH=re.compile(r'res://[^\s"\'<>]+')
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);args=p.parse_args();out=args.output.resolve()
    assert not out.exists() and not out.is_relative_to(ROOT),'Reference must be fresh and outside the live project'
    assert sha(REFERENCE.read_bytes())==EXPECTED
    out.mkdir(parents=True);index={};missing=set();pending=[]
    def add(name,data,origin):
        destination=(out/name).resolve();assert destination.is_relative_to(out)
        if name in index:return
        destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(data)
        index[name]={'sha256':sha(data),'bytes':len(data),'origin':origin}
        if destination.suffix in TEXT:pending.append(name)
    with zipfile.ZipFile(REFERENCE) as z:
        assert z.testzip() is None
        for name in z.namelist():
            if not name.endswith('/'):add(name,z.read(name),'frozen_g0_archive')
    for name in ['.godot/global_script_class_cache.cfg','.godot/uid_cache.bin','addons/godotiq/godotiq_runtime.gd','addons/godotiq/godotiq_runtime.gd.uid']:
        source=ROOT/name
        if source.is_file():add(name,source.read_bytes(),'current_import_cache_or_explicit_debugger_tooling')
        else:missing.add(name)
    while pending:
        name=pending.pop();source=out/name
        try:text=source.read_text('utf-8-sig')
        except UnicodeError:continue
        targets=[x.removeprefix('res://').rstrip('),;]') for x in PATH.findall(text)]
        # Engine resource imports resolve through the adjacent .import file.
        for target in targets:
            if '..' in Path(target).parts:missing.add(target);continue
            if target not in index:
                original=ROOT/target
                if original.is_file():add(target,original.read_bytes(),'current_dependency_not_in_frozen_archive')
                else:missing.add(target)
            sidecar=ROOT/(target+'.import')
            if sidecar.is_file() and target+'.import' not in index:add(target+'.import',sidecar.read_bytes(),'current_import_descriptor')
    (out/'reference-index.json').write_text(json.dumps({'archive':str(REFERENCE),'archive_sha256':EXPECTED,'files':index,'missing_references':sorted(missing),'scope':'Source-preserving isolated cost reference. Additional dependency/cache identities are explicit; successful boot and actual consumed source/numerical input checks remain required before comparison.'},indent=2),'utf-8')
    for name,item in index.items():assert sha((out/name).read_bytes())==item['sha256']
    print('REFERENCE_COPY',len(index),'files','missing',len(missing),'output',out)
if __name__=='__main__':main()
