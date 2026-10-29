"""Derived OBJ and three-panel preview from sealed runtime API copies."""
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent/'plot_deps'))
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
def main():
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--snapshot-ids',nargs='+');p.add_argument('--before-label',default='Before');p.add_argument('--after-label',default='After snapshot');p.add_argument('--change-label',default='Height change; cause unisolated');a=p.parse_args();root=Path(a.run).resolve();index=[json.loads(l) for l in (root/'raw_index.jsonl').read_text().splitlines()];snapshots=[root/(id+'.json') for id in a.snapshot_ids] if a.snapshot_ids else sorted(root.glob('snapshot_*.json'),key=lambda p:int(p.stem.split('_')[-1]));data=[]
    for f in snapshots:
        s=json.loads(f.read_text());raw={x['payload_kind']:x['raw']['path'] for x in index if x['snapshot_id']==s['snapshot_id']};v=np.fromfile(raw['vertices'],dtype='<f4').reshape(-1,3);tri=np.concatenate([np.fromfile(raw['indices_'+str(sm['index'])],dtype='<i4').reshape(-1,3)+sm['base_vertex'] for sm in s['submeshes']]);data.append((s,v,tri))
    assert len(data)==2;out=root/'derived';out.mkdir(exist_ok=True);fig=plt.figure(figsize=(13,4.3));lo=min(v[:,1].min() for _,v,_ in data);hi=max(v[:,1].max() for _,v,_ in data)
    for i,(s,v,tri) in enumerate(data):
        ax=fig.add_subplot(1,3,i+1,projection='3d');ax.plot_trisurf(v[:,0],v[:,2],v[:,1],triangles=tri,cmap='YlOrBr',vmin=lo,vmax=hi,linewidth=.2,edgecolor='#725c40');ax.set_zlim(lo,hi);ax.view_init(35,-65);ax.set(title=a.before_label if i==0 else a.after_label,xlabel='local x',ylabel='local z',zlabel='local y')
    a0,v0,tri=data[0];a1,v1,_=data[1];assert np.array_equal(v0[:,[0,2]],v1[:,[0,2]]);dy=v1[:,1]-v0[:,1];ax=fig.add_subplot(1,3,3);lim=max(abs(dy.min()),abs(dy.max()),1e-12);art=ax.tripcolor(v0[:,0],v0[:,2],tri,dy,shading='gouraud',cmap='RdBu_r',vmin=-lim,vmax=lim);ax.set(title=a.change_label,xlabel='local x',ylabel='local z',aspect='equal');ax.title.set_fontsize(11);fig.colorbar(art,ax=ax,label='Unity scene units',pad=.08);fig.suptitle(f'Actual MeshCollider.sharedMesh API copies — {len(v0)} vertices / {len(tri)} triangles');fig.tight_layout();fig.savefig(out/'mesh_pair.png',dpi=160);plt.close(fig);print(str(out/'mesh_pair.png'))
if __name__=='__main__':main()
