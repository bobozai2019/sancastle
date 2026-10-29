"""Extract indexed Lit/Plant DXBC from the original LZ4 payload, without version overrides."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/investigation/brush_hit_competitor/deps'))
import UnityPy
from UnityPy.helpers import CompressionHelper


def ident(path):
    return dict(path=str(path), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True, type=Path)
    out = p.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = ROOT / 'sandcastlegame/Sandcastle_Data/sharedassets0.assets'
    report = dict(source=ident(source), tool=ident(Path(__file__).resolve()),
                  command=sys.argv, unitypy=UnityPy.__version__, artifacts=[], programs=[], errors=[])
    def keep(name, data, selector):
        path = out / name
        path.write_bytes(data)
        r = dict(ident(path), selector=selector)
        report['artifacts'].append(r)
        return r
    try:
        env = UnityPy.load(str(source))
        obj = next(o for o in env.objects if o.assets_file.name==source.name and o.path_id==580)
        raw, tree = obj.get_raw_data(), obj.read_typetree()
        assert tree['m_ParsedForm']['m_Name']=='Lit/Plant' and tree['platforms']==[4]
        assert tree['offsets']==[[0]] and len(tree['compressedLengths'][0])==1
        with source.open('rb') as stream:
            stream.seek(obj.byte_start)
            assert stream.read(len(raw))==raw
        keep('object.raw',raw,dict(source=str(source),path_id=580,offset=obj.byte_start,bytes=len(raw)))
        blob = bytes(tree['compressedBlob'])
        assert len(blob)==tree['compressedLengths'][0][0]
        blob_offset=raw.find(blob)
        assert blob_offset>=0
        keep('compressed.lz4',blob,dict(source=str(source),path_id=580,offset_in_object=blob_offset))
        uncompressed = CompressionHelper.decompress_lz4(blob,tree['decompressedLengths'][0][0])
        keep('decompressed.bin',uncompressed,dict(derived_from='compressed.lz4',codec='lz4',bytes=len(uncompressed)))
        count,=struct.unpack_from('<I',uncompressed)
        assert 0<count<100 and 4+12*count<=len(uncompressed)
        entries=[]
        for i in range(count):
            offset,size,segment=struct.unpack_from('<III',uncompressed,4+12*i)
            assert segment==0 and 4+12*count<=offset<offset+size<=len(uncompressed)
            entries.append(dict(index=i,offset=offset,bytes=size,segment=segment))
        report['entries']=entries
        helper=ROOT/'tests/investigation/competitor_transport/analyze_transport.py'
        spec=importlib.util.spec_from_file_location('vegetation_disasm',helper)
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        report['helper']=ident(helper)
        report['d3dcompiler']=ident(Path(os.environ['WINDIR'])/'System32/d3dcompiler_47.dll')
        for si,sub in enumerate(tree['m_ParsedForm']['m_SubShaders']):
            for pi,pa in enumerate(sub['m_Passes']):
                for stage in ('progVertex','progFragment'):
                    for group_index,group in enumerate(pa[stage]['m_PlayerSubPrograms']):
                        for vi,v in enumerate(group):
                            entry=entries[v['m_BlobIndex']]
                            record=uncompressed[entry['offset']:entry['offset']+entry['bytes']]
                            start=record.find(b'DXBC')
                            assert start>=0
                            length,=struct.unpack_from('<I',record,start+24)
                            assert start+length<=len(record)
                            dxbc=record[start:start+length]
                            stem=f"{pa['m_State']['m_Name']}_{stage}_{vi}"
                            selector=dict(path_id=580,subshader=si,pass_index=pi,stage=stage,
                                          group=group_index,variant=vi,blob_index=entry['index'],
                                          offset_in_decompressed=entry['offset']+start,bytes=length)
                            bc=keep(stem+'.dxbc',dxbc,selector)
                            asm=keep(stem+'.asm',module.disassemble(dxbc).encode('utf8'),dict(derived_from=bc['path'],tool='D3DDisassemble'))
                            report['programs'].append(dict(name=stem,bytecode=bc,assembly=asm,
                                parameters=pa[stage]['m_CommonParameters'],name_indices=pa['m_NameIndices'],variant=v))
        report['source_after']=ident(source)
        assert report['source_after']==report['source']
    except Exception as exc:
        report['errors'].append(type(exc).__name__+': '+str(exc))
    report['result']='PASS_STATIC_EXPORT' if not report['errors'] else 'PARTIAL_EXPORT'
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print(json.dumps(dict(result=report['result'],programs=len(report['programs']),errors=report['errors'])))
    return bool(report['errors'])


if __name__=='__main__':
    raise SystemExit(main())
