"""Index exact Ground instructions and captured constants; read-only inputs."""
import json, hashlib, struct, sys
import numpy as np
from pathlib import Path
from analyze_transport import disassemble
out=Path(sys.argv[1]).resolve()
helper=Path(__file__).with_name('analyze_transport.py')
ns={'__name__':'ground_hex_helper'}
exec(helper.read_text().replace('hr = fn(src, len(raw), 0, None,', 'hr = fn(src, len(raw), 0x80 | 0x20, None,'),ns)
manifest=json.loads((out/'manifest.json').read_text())
raw=(out/'replay/cb0.raw').read_bytes()
constants=[]
exports=[]
for row in manifest['index']:
    b=(out/(row['name']+'.dxbc')).read_bytes()
    assert hashlib.sha256(b).hexdigest()==row['sha256']
    p=out/(row['name']+'_hex.txt')
    p.write_text(ns['disassemble'](b),encoding='utf-8')
    exports.append(dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),source_sha256=row['sha256'],flags='0x80|0x20'))
    if row['name']=='HeightIntegration_0':
        for cb in row['constant_buffers']:
            for param in cb['params']:
                fmt='<'+('i' if param['type']==1 else 'f')*param['colCount']
                constants.append(dict(name=param['name'],offset=param['offset'],values=struct.unpack_from(fmt,raw,param['offset'])))
w=np.fromfile(out/'replay/readonly_0.raw',dtype='<u4').reshape(256,512,4)
codes=w[:,:,3]>>28
z,x=np.nonzero(codes)
unique,counts=np.unique(codes,return_counts=True)
mask_summary=dict(field='water uint3 bits28..31; same field consumed as sea forcing alpha by Water.UpdateAmount',
    nonzero_x=[int(x.min()),int(x.max())],nonzero_z=[int(z.min()),int(z.max())],
    codes={str(int(u)):int(c) for u,c in zip(unique,counts)},numpy=np.__version__,selection='test1 E1478 t0 post-event water snapshot')
report=dict(constants=constants,exports=exports,mask_summary=mask_summary,script=str(Path(__file__).resolve()),script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    helper=str(helper.resolve()),helper_sha256=hashlib.sha256(helper.read_bytes()).hexdigest(),
    command='python '+str(Path(__file__).resolve())+' '+str(out),scope='test1 E1478 effective constants; DXBC exact hex immediates with instruction numbering; no original source claim')
(out/'analysis.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(constants))
