"""Create immutable identity baseline and isolated runnable copy (no RDC files)."""
import argparse, hashlib, json, shutil, sys, datetime, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[4]
def identity(p):
    p = Path(p).resolve()
    h = hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda: f.read(1048576), b''): h.update(b)
    return {'path':str(p), 'bytes':p.stat().st_size, 'sha256':h.hexdigest()}
def save(p, x): p.write_text(json.dumps(x, ensure_ascii=False, indent=2), encoding='utf8')
def main():
    a=argparse.ArgumentParser(); a.add_argument('--out', required=True); args=a.parse_args()
    out=Path(args.out).resolve(); out.mkdir(parents=True, exist_ok=False)
    sources=[ROOT/'sandcastlegame', Path('D:/game/steam/steamapps/common/Sandcastle Demo')]
    names=['Sandcastle.exe','GameAssembly.dll','UnityPlayer.dll','Sandcastle_Data/il2cpp_data/Metadata/global-metadata.dat']
    rows=[{'root':str(s), 'files':[identity(s/n) for n in names]} for s in sources]
    save(out/'source_manifest.json', {'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'sources':rows, 'equal':all(rows[0]['files'][i]['sha256']==rows[1]['files'][i]['sha256'] for i in range(len(names)))})
    copy=out/'owned_game'; copy.mkdir()
    copied=[]
    for p in sources[0].rglob('*'):
        if p.is_file() and p.suffix.lower()!='.rdc':
            dest=copy/p.relative_to(sources[0]); dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(p,dest); original=identity(p); replica=identity(dest)
            assert original['sha256']==replica['sha256']; copied.append({'source':original,'copy':replica})
    save(out/'copy_manifest.json',copied)
    save(out/'tool_manifest.json', {'python':sys.version,'command':sys.argv,'baseline':identity(__file__)})
    ps="Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Sandcastle|godot|python' } | Select-Object ProcessId,Name,ExecutablePath,CommandLine | ConvertTo-Json -Depth 3"
    (out/'processes_before.json').write_text(subprocess.check_output(['powershell','-NoProfile','-Command',ps],text=True),encoding='utf8')
    print(str(out))
if __name__=='__main__': main()
