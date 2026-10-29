"""Enumerate the first edge 32x32 proposal's original 8x8 logical domains."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'task/muscl_gpu_efficiency/验收/t02_static_v1'

def main():
    OUT.mkdir(parents=True,exist_ok=False)
    cells=set(); tiles={}; shared_indices=set(); conflicts=[]
    for gy in range(8):
        for gx in range(8):
            group_indices=set()
            for ly in range(32):
                for lx in range(32):
                    q=(gx*32+lx,gy*32+ly)
                    tile=(gx*4+lx//8,gy*4+ly//8)
                    lane=(ly%8)*8+lx%8
                    block=(ly//8)*4+lx//8
                    shared=block*64+lane
                    if q in cells or shared in group_indices:conflicts.append((gx,gy,lx,ly))
                    cells.add(q);group_indices.add(shared);shared_indices.add(shared)
                    tiles.setdefault(tile,{})[lane]=q
            assert group_indices==set(range(1024))
    assert not conflicts and len(cells)==65536 and len(tiles)==1024
    assert all(set(lanes)==set(range(64)) for lanes in tiles.values())
    assert all(q==(tile[0]*8+lane%8,tile[1]*8+lane//8)
               for tile,lanes in tiles.items() for lane,q in lanes.items())
    # Compare the ordered source expression of every max output, rather than
    # comparing random floats and overlooking NaN or signed-zero behavior.
    old=list(range(64)); new=[list(range(64)) for _ in range(16)]
    for stride in (32,16,8,4,2,1):
        for lane in range(stride):old[lane]=('max',old[lane],old[lane+stride])
        for block in range(16):
            for lane in range(stride):new[block][lane]=('max',new[block][lane],new[block][lane+stride])
    assert all(v[0]==old[0] for v in new)
    result={'pass':True,'kind':'static_integer_mapping_and_expression_tree',
            'original_groups':[32,32,1],'candidate_groups':[8,8,1],
            'original_threads':[8,8,1],'candidate_threads':[32,32,1],
            'invocations':len(cells),'logical_tiles':len(tiles),
            'logical_lanes_per_tile':64,'logical_tiles_per_physical_group':16,
            'shared_float_indices':len(shared_indices),'shared_bytes':8192,
            'reduction_order_equal':True,'conflicts':conflicts,
            'limitations':['No shader compiled or GPU pipeline created.',
                          'Does not prove physical register use, occupancy, execution speed or byte equality.',
                          'Only the planned integer mapping and unchanged max expression are enumerated.']}
    (OUT/'coverage.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))

if __name__=='__main__':main()
