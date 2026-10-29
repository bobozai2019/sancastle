"""Generate explicit packed-state boundary/threshold fixtures (not game snapshots)."""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity

W,H=512,256


def q24(value,span):
    return np.floor(np.clip(np.asarray(value,dtype=np.float64)/span,0,1)*16777215+.5).astype(np.uint32)


def water(amount=.5,bed=.25,vx=0.,vz=0.,nx=128,nz=128,B=17,source=0,sea=0):
    a,b,x,z=[np.broadcast_to(v,(H,W)).copy() for v in [q24(amount,10.1),q24(bed,10.1),q24((np.asarray(vx)+4),8),q24((np.asarray(vz)+4),8)]]
    result=np.zeros((H,W,4),dtype='<u4')
    result[:,:,0]=(x<<16)|np.uint32(nx)|(np.uint32(nz)<<8)
    result[:,:,1]=(z<<8)|(x>>16)
    result[:,:,2]=a|(b<<24)
    result[:,:,3]=(b>>8)|(np.asarray(B,dtype=np.uint32)<<16)|(np.asarray(source,dtype=np.uint32)<<24)|(np.asarray(sea,dtype=np.uint32)<<28)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--only',choices=['wet_dry'],help='Regenerate only the corrected dry/wet case')
    args=parser.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs']:(out/name).mkdir()
    yy,xx=np.mgrid[:H,:W]
    still=water();uniform=water(vx=.125,vz=-.25)
    wetdry=water()
    wetdry[:,:256,2]=(wetdry[:,:256,2]&0xff000000)|np.uint32(83055)
    bedstep=water(bed=np.where(xx<256,.25,.75))
    source=np.zeros((H,W),dtype=np.uint32);source[120:136,248:264]=15
    sea=np.zeros((H,W),dtype=np.uint32);sea[:,496:512]=np.arange(16,dtype=np.uint32)
    boundaries=water(source=source,sea=sea)
    clamp=water(amount=np.take([0.,.049999,.05,.050001,9.999999,10.,10.1],xx%7),vx=np.where(xx%2,3.9,-3.9))
    extremes=water();values=np.asarray([0,1,8388607,8388608,8388609,16777214,16777215],dtype=np.uint32)
    xcode=values[xx%len(values)];zcode=values[yy%len(values)]
    extremes[:,:,0]=(extremes[:,:,0]&65535)|(xcode<<16);extremes[:,:,1]=(zcode<<8)|(xcode>>16)
    extremes[:,:,2]=(extremes[:,:,2]&0xff000000)|values[(xx+yy)%len(values)]
    def Bcase(rise,nx):
        k=rise/.45;velocity=np.clip(-k*(xx-255.5)*(30/512),-3.9,3.9)
        return water(vx=velocity,nx=nx)
    specs=[('still',still,'Static A=.5, bed=.25; nearest 24-bit zero velocity; no source/sea flags'),
           ('uniform_velocity',uniform,'Uniform vx=.125, vz=-.25; standalone fixture, not a wave-speed measurement'),
           ('wet_dry',wetdry,'A code83055 (strictly below visible-water threshold) versus quantized A=.5 across x=256; other fields fixed'),
           ('bed_step',bedstep,'Bed .25 versus .75 across x=256; amount fixed; corresponding sand bed changed'),
           ('domain_flags',boundaries,'Sea weights 0..15 in final 16 columns; source code15 in central square; field consumption stress case'),
           ('clamp_neighborhood',clamp,'A around .05 and 10 plus encoded10.1; alternating bounded edge velocities'),
           ('packed_extremes',extremes,'Explicit 24-bit code extremes and 2^23 rounding neighbors; physical reachability unknown'),
           ('B_rise_below',Bcase(.095,192),'Convergence designed for nominal rise .095 with normal code192'),
           ('B_rise_above',Bcase(.105,192),'Only convergence slope differs from B_rise_below; nominal rise .105'),
           ('B_normal_below',Bcase(.105,191),'Only normal X code differs from B_rise_above:191 versus192')]
    records=[]
    for name,state,description in specs:
        if args.only and name!=args.only:continue
        directory=out/'raw'/name;directory.mkdir()
        state.tofile(directory/'water.bin')
        # Ground layout read by floor: 24-bit height split at u2 bits12..31
        # and u3 bits0..3; low12 obstacle-height code is zero for these fixtures.
        ground_bed=np.where(np.mgrid[:512,:1024][1]<512,.25,.75) if name=='bed_step' else np.full((512,1024),.25)
        code=q24(ground_bed,10.1);ground=np.zeros((512,1024,4),dtype='<u4')
        ground[:,:,2]=(code&0xfffff)<<12;ground[:,:,3]=code>>20;ground.tofile(directory/'sand.bin')
        np.zeros((256,512,2),dtype='<f2').tofile(directory/'obstacle.rg16f')
        np.zeros((512,4),dtype='<u4').tofile(directory/'air.bin')
        record=dict(fixture_id=name,description=description,origin='synthetic controlled input; not original runtime',
            generator_quantization='floor(clamp(real/span,0,1)*(2^24-1)+.5) in binary64 defines fixture bytes; not claimed original GPU encoding implementation',
            seed=None,water=identity(directory/'water.bin'),sand=identity(directory/'sand.bin'),obstacle=identity(directory/'obstacle.rg16f'),air=identity(directory/'air.bin'),
            physical_reachability='unknown; field-format test input',comparison='Independent test case; no inter-case causal inference except named B pairs')
        amount=(state[:,:,2]&0xffffff).astype(np.float64)*10.1/16777215
        record['visible_depth_classification']=dict(dry_cells=int(np.count_nonzero(amount<=.05)),wet_cells=int(np.count_nonzero(amount>.05)))
        if name=='wet_dry' and record['visible_depth_classification']!={'dry_cells':65536,'wet_cells':65536}:
            raise ValueError('Fixture does not contain the declared dry/wet interface')
        if name.startswith('B_'):
            record['B_probe']=dict(x_range=[254,257],y_range=[124,131],expected_code=255 if name=='B_rise_above' else 0,
                scope='Central cells avoid boundaries and minimize in-place neighbor feedback; expectation must be checked against original DXBC')
        records.append(record)
    for name in ['make_controlled_fixtures.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    (out/'manifest.json').write_text(json.dumps(dict(schema_version='1.0',run_id=out.name,operation_status='complete',verification_status='not_evaluated',fixtures=records,
        field_layout=dict(water='512x256 little-endian uint4',sand='1024x512 little-endian uint4',obstacle='512x256 RG16F tightly packed',air='512 uint4 records'),
        evidence_basis='T01 E1484 instructions16-62 define sand height channel; water bit layout from original consumers and producers',
        numeric_budget=None,artifacts=[identity(p) for p in out.rglob('*') if p.is_file()],errors=[]),indent=2),encoding='utf-8')
    print(json.dumps(dict(output=out.as_posix(),fixtures=len(records))))


if __name__=='__main__':main()
