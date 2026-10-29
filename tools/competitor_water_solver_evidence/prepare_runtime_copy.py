"""Hash-verify an owned program copy without starting it or copying user saves."""
import argparse
import json
import shutil
from pathlib import Path
from evidence_contract import identity

ROOT=Path('D:/godot/project/sandcastle')
EXPECTED='147030ecf9527a25250238120364eb761390b99688b1812c4ea555b3b04e56a0'


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--game-output',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();out=args.output;game=args.game_output;source=ROOT/'sandcastlegame'
    for path in [out,game]:
        if not path.is_absolute() or not str(path).isascii() or path.exists():raise ValueError('New absolute ASCII directories required')
    expected_work=(ROOT/'task/competitor_water_solver_evidence/work').resolve()
    if not game.resolve().is_relative_to(expected_work):raise ValueError('Owned game must remain inside task work')
    if identity(source/'GameAssembly.dll')['sha256']!=EXPECTED:raise ValueError('SOURCE_VERSION_MISMATCH')
    paths=[p for p in sorted(source.rglob('*')) if p.is_file() and p.suffix.lower()!='.rdc']
    for path in source.rglob('*'):
        if path.is_symlink() or path.is_junction():raise ValueError('SOURCE_REPARSE_POINT_NOT_SUPPORTED')
    out.mkdir(parents=True,exist_ok=False);game.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs']:(out/name).mkdir()
    rows=[]
    for path in paths:
        target=game/path.relative_to(source);target.parent.mkdir(parents=True,exist_ok=True)
        before=identity(path);shutil.copy2(path,target);copied=identity(target);after=identity(path)
        if before!=after or before['sha256']!=copied['sha256']:raise ValueError('SOURCE_OR_COPY_CHANGED:'+str(path))
        rows.append(dict(source=before,copy=copied,source_after=after))
    for name in ['prepare_runtime_copy.py','evidence_contract.py']:shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    shutil.copyfile(Path(__file__).with_name('runtime')/'isolation_guard.js',out/'sources/isolation_guard.js')
    manifest=dict(schema_version='1.0',run_id=out.name,operation_status='complete',verification_status='passed',
        source_root=str(source),owned_root=str(game),copy_manifest=rows,gameassembly_sha256=EXPECTED,
        game_started=False,user_data_copied=False,
        limitations=['Program copy alone is not user-data isolation',
                     'Helper isolation probe does not yet prove application startup/child-process or all persistence APIs',
                     'Run with verified process-local isolation and audit actual writes before accepting T05-G01'],
        errors=[],artifacts=[identity(p) for p in out.rglob('*') if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(dict(files=len(rows),bytes=sum(r['copy']['size_bytes'] for r in rows),owned_root=str(game),game_started=False)),flush=True)


if __name__=='__main__':main()
