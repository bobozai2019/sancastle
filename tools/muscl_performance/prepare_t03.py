"""Build the bounded shared-raw-input candidate from the controlled T01 project."""
from pathlib import Path
import difflib
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'test_output/muscl_performance_round2/projects/diagnostic_final'
TARGET=ROOT/'test_output/muscl_performance_round2/projects/t03_shared_v1'
EVIDENCE=ROOT/'task/muscl_performance_round2/验收/t03_prototype'
shutil.copytree(BASE,TARGET)
EVIDENCE.mkdir(parents=True,exist_ok=False)

def change(relative,before,after):
    path=TARGET/relative
    text=path.read_text(encoding='utf-8')
    if text.count(before)!=1:
        raise RuntimeError((relative,'source anchor is not unique'))
    path.write_text(text.replace(before,after),encoding='utf-8',newline='\n')

spatial='shaders/simulation/muscl/muscl_spatial.glslinc'
edge='shaders/simulation/muscl/rk_edge.glsl'
change(spatial,'bool blocked(ivec2 q){return imageLoad(obstacle,q).r>=0.5;}', '''// Only rk_edge opts into raw shared inputs. Validation remains at its original
// consumption sites, so speculative halo loads cannot raise numerical flags.
#ifdef MUSCL_EDGE_SHARED_RAW
shared vec4 cached_state[144];
shared vec2 cached_bed[144];
shared float cached_obstacle[144];
int cache_index(ivec2 q){
 ivec2 local=q-ivec2(gl_WorkGroupID.xy)*8+ivec2(2);
 return local.y*12+local.x;
}
void load_raw_tile(){
 ivec2 origin=ivec2(gl_WorkGroupID.xy)*8-ivec2(2);
 for(uint i=gl_LocalInvocationIndex;i<144u;i+=64u){
  ivec2 q=origin+ivec2(int(i%12u),int(i/12u));
  if(inside(q)){
   cached_state[i]=p.phase==0u?vec4(imageLoad(water_state,q).r,imageLoad(qx_state,q).r,imageLoad(qz_state,q).r,imageLoad(sediment_state,q).r):imageLoad(stage_in,q);
   cached_bed[i]=vec2(imageLoad(rock_state,q).r,imageLoad(sand_state,q).r);
   cached_obstacle[i]=imageLoad(obstacle,q).r;
  }else{cached_state[i]=vec4(0.0);cached_bed[i]=vec2(0.0);cached_obstacle[i]=0.0;}
 }
 barrier();
}
vec4 raw_state_at(ivec2 q){return cached_state[cache_index(q)];}
float raw_bed_at(ivec2 q){vec2 b=cached_bed[cache_index(q)];return b.x+b.y;}
bool blocked(ivec2 q){return cached_obstacle[cache_index(q)]>=0.5;}
#else
vec4 raw_state_at(ivec2 q){return p.phase==0u?vec4(imageLoad(water_state,q).r,imageLoad(qx_state,q).r,imageLoad(qz_state,q).r,imageLoad(sediment_state,q).r):imageLoad(stage_in,q);}
float raw_bed_at(ivec2 q){return imageLoad(rock_state,q).r+imageLoad(sand_state,q).r;}
bool blocked(ivec2 q){return imageLoad(obstacle,q).r>=0.5;}
#endif''')
change(spatial,'vec4 a=p.phase==0u?vec4(imageLoad(water_state,q).r,imageLoad(qx_state,q).r,imageLoad(qz_state,q).r,imageLoad(sediment_state,q).r):imageLoad(stage_in,q);','vec4 a=raw_state_at(q);')
change(spatial,'float bed=imageLoad(rock_state,q).r+imageLoad(sand_state,q).r;','float bed=raw_bed_at(q);')
change(edge,'#include "muscl_spatial.glslinc"','#define MUSCL_EDGE_SHARED_RAW\n#include "muscl_spatial.glslinc"')
change(edge,'void main(){','void main(){\n load_raw_tile();')
diff=[]
identity={}
for relative in [spatial,edge]:
    destination=EVIDENCE/'sources'/relative
    destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(TARGET/relative,destination)
    identity[relative]=hashlib.sha256((TARGET/relative).read_bytes()).hexdigest()
    diff.extend(difflib.unified_diff((BASE/relative).read_text(encoding='utf-8').splitlines(True),
                (TARGET/relative).read_text(encoding='utf-8').splitlines(True),fromfile='a/'+relative,tofile='b/'+relative))
(EVIDENCE/'candidate.diff').write_text(''.join(diff),encoding='utf-8')
(EVIDENCE/'identity.json').write_text(json.dumps({'base_project':str(BASE),'candidate_project':str(TARGET),
 'source_hashes':identity,'shared_raw_bytes':144*(16+8+4),'existing_reduction_bytes':64*4*2,
 'scope':'8x8 group, two-cell halo, raw values only; same math, flags, dispatches and bindings'},indent=2),encoding='utf-8')
print(TARGET)
