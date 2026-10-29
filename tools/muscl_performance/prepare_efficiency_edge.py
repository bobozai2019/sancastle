"""Generate a bounded edge workgroup proposal from an immutable runtime ZIP.

Writes source/diff/manifest only. Applying or running a proposal is separate.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import zipfile

RECORDER='scripts/simulation/unified_edit/water_muscl.gd'
EDGE='shaders/simulation/muscl/rk_edge.glsl'
DECIDE='shaders/simulation/muscl/rk_decide.glsl'

def replace(source,before,after):
    if source.count(before)!=1:raise ValueError('nonunique source anchor: '+before)
    return source.replace(before,after)

def build(original,size):
    source=dict(original)
    r=source[RECORDER]
    r=replace(r,'["trial_indirect",768]','["trial_indirect",1536]')
    r=replace(r,'\t_recording.append(stage)\n\nfunc _append_coupled_pass',
        '\tif name=="rk_edge":\n'
        f'\t\tstage.groups=Vector3i({256//size},{256//size},1)\n'
        '\t\tif step>=0:stage.offset=768+step*12\n'
        '\t_recording.append(stage)\n\nfunc _append_coupled_pass')
    # Include expansion happens first. Only this kernel receives a larger
    # declaration; shared spatial input and every other kernel keep 8x8.
    if size==32:
        r=replace(r,'\treturn source\n\nfunc _compile',
            '\tif path.ends_with("/rk_edge.glsl"):\n'
            '\t\tsource=source.replace("layout(local_size_x=8,local_size_y=8) in;","layout(local_size_x=32,local_size_y=32) in;")\n'
            '\treturn source\n\nfunc _compile')
    source[RECORDER]=r
    d=source[DECIDE]
    d=replace(d,' ag[j]=accepted?32u:0u;ag[j+1u]=32u;ag[j+2u]=1u;',
        ' ag[j]=accepted?32u:0u;ag[j+1u]=32u;ag[j+2u]=1u;\n'
        f' tg[192u+j]=is_active?{256//size}u:0u;tg[193u+j]={256//size}u;tg[194u+j]=1u;')
    d=replace(d,'for(uint j=0u;j<192u;j++){tg[j]=0u;ag[j]=0u;}',
        'for(uint j=0u;j<384u;j++)tg[j]=0u;\n'
        '  for(uint j=0u;j<192u;j++)ag[j]=0u;')
    source[DECIDE]=d
    if size==32:
        e=source[EDGE]
        e=replace(e,'shared float sx[64],sz[64];','shared float sx[1024],sz[1024];')
        e=replace(e,'ivec2 q=ivec2(gl_GlobalInvocationID.xy);uint lane=gl_LocalInvocationIndex;',
            'ivec2 q=ivec2(gl_GlobalInvocationID.xy);\n'
            ' uint lane=(gl_LocalInvocationID.y%8u)*8u+gl_LocalInvocationID.x%8u;\n'
            ' uint block=(gl_LocalInvocationID.y/8u)*4u+gl_LocalInvocationID.x/8u;\n'
            ' uint i=block*64u+lane;')
        e=replace(e,'sx[lane]=fx.w;sz[lane]=fz.w;barrier();','sx[i]=fx.w;sz[i]=fz.w;barrier();')
        e=replace(e,'sx[lane]=max(sx[lane],sx[lane+stride]);sz[lane]=max(sz[lane],sz[lane+stride]);',
            'sx[i]=max(sx[i],sx[i+stride]);sz[i]=max(sz[i],sz[i+stride]);')
        e=replace(e,'if(lane==0u)imageStore(speed_tiles,ivec2(gl_WorkGroupID.xy),vec4(sx[0],sz[0],0.0,0.0));',
            'if(lane==0u)imageStore(speed_tiles,q/8,vec4(sx[i],sz[i],0.0,0.0));')
        source[EDGE]=e
    return source

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--size',type=int,choices=(8,32),required=True)
    a=p.parse_args()
    with zipfile.ZipFile(a.archive) as z:
        original={n:z.read(n).decode('utf-8').replace('\r\n','\n') for n in (RECORDER,EDGE,DECIDE)}
        original_bytes={n:z.read(n) for n in original}
    source=build(original,a.size)
    a.output.mkdir(parents=True,exist_ok=False)
    files={};diff=[]
    for n,value in source.items():
        if value==original[n]:continue
        target=a.output/'sources'/n;target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(value,encoding='utf-8',newline='\n')
        files[n]={'base_sha256':hashlib.sha256(original_bytes[n]).hexdigest(),
                  'candidate_sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
        diff+=difflib.unified_diff(original[n].splitlines(True),value.splitlines(True),fromfile='a/'+n,tofile='b/'+n)
    (a.output/'candidate.diff').write_text(''.join(diff),encoding='utf-8')
    manifest={'archive':str(a.archive.resolve()),'archive_sha256':hashlib.sha256(a.archive.read_bytes()).hexdigest(),
              'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'edge_group':[a.size,a.size,1],'edge_dispatch':[256//a.size,256//a.size,1],
              'trial_indirect_original_bytes':768,'trial_indirect_candidate_bytes':1536,
              'private_mapping':'first 768 bytes exact; suffix validated per-slot against prefix, x/y divided by edge_size/8',
              'files':files,'status':'generated_only_uncompiled_unapplied',
              'shared_bytes':8192 if a.size==32 else 512,
              'scope':'edge only, original CFL logical tiles and all non-edge dispatch records unchanged'}
    (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(manifest))

if __name__=='__main__':main()
