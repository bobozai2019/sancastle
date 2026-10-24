extends RefCounted

# Little endian, fixed capacity; all identities stay int64 on both sides.
const VERSION=3
# Exact float32 representation of the existing water kernel's 1 mm cutoff.
const DRY_DEPTH_M=8589935.0/8589934592.0
const VELOCITY_DEPTH_M=5368709.0/1073741824.0
const MAX_POINTS=32
const HEADER_BYTES=128
const INPUT_STRIDE=32
const POINT_STRIDE=64
const CHUNK_OFFSET=HEADER_BYTES+MAX_POINTS*POINT_STRIDE
const INPUT_BYTES=HEADER_BYTES+MAX_POINTS*INPUT_STRIDE
const OUTPUT_BYTES=CHUNK_OFFSET+64*16
const DOMAIN_MIN=-16.0
const DOMAIN_MAX=16.0
const I64_FIELDS={"request_id":8,"owner_token":16,"generation":24,"pose_seq":32}

static func validate(request: Dictionary, domain: String, generation: int) -> StringName:
	var keys:=["request_id","owner_token","generation","pose_seq","domain_id","minimum_state_seq","points","footprints"]
	if request.size()!=keys.size():return &"invalid_request"
	for key in keys:
		if not request.has(key):return &"invalid_request"
	for key in I64_FIELDS:
		if typeof(request.get(key))!=TYPE_INT or request[key]<1:return &"invalid_request"
	if request.generation!=generation:return &"stale_generation"
	if request.get("domain_id")!=domain:return &"invalid_request"
	if typeof(request.get("minimum_state_seq"))!=TYPE_INT or request.minimum_state_seq<0:return &"invalid_request"
	if not request.get("points") is Array or request.points.is_empty() or request.points.size()>MAX_POINTS:return &"invalid_request"
	var ids:={}
	for point in request.points:
		if not point is Dictionary or point.size()!=3:return &"invalid_request"
		for key in ["body_id","point_id"]:
			if typeof(point.get(key))!=TYPE_INT or point[key]<1:return &"invalid_request"
		var id:=[point.body_id,point.point_id]
		if ids.has(id):return &"invalid_request"
		ids[id]=true
		if not point.get("position") is Vector3 or not point.position.is_finite():return &"invalid_request"
		var p: Vector3=point.position
		if absf(p.y)>1e6:return &"invalid_request"
		if p.x<DOMAIN_MIN or p.z<DOMAIN_MIN or p.x>=DOMAIN_MAX or p.z>=DOMAIN_MAX:return &"out_of_domain"
	if not request.get("footprints") is Array or request.footprints.is_empty() or request.footprints.size()>3:return &"invalid_request"
	for rect in request.footprints:
		if not rect is Rect2 or not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x<=0 or rect.size.y<=0:return &"invalid_request"
		if rect.position.x<DOMAIN_MIN or rect.position.y<DOMAIN_MIN or rect.end.x>=DOMAIN_MAX or rect.end.y>=DOMAIN_MAX:return &"out_of_domain"
	return &""

static func chunks(request: Dictionary) -> Array[int]:
	var result: Array[int]=[]
	for rect: Rect2 in request.footprints:
		var low: Vector2i=Vector2i(((rect.position+Vector2(16,16))/4.0).floor())
		var high: Vector2i=Vector2i(((rect.end+Vector2(16,16))/4.0).floor())
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				if not result.has(z*8+x):result.append(z*8+x)
	result.sort();return result

static func encode(request: Dictionary, serial: int) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(INPUT_BYTES);bytes.encode_u32(0,VERSION)
	for key in I64_FIELDS:bytes.encode_s64(I64_FIELDS[key],request[key])
	bytes.encode_s64(40,request.minimum_state_seq);bytes.encode_u32(68,request.points.size());bytes.encode_s64(88,serial)
	var masks:=[0,0]
	for chunk in chunks(request):masks[chunk/32]=int(masks[chunk/32])|(1<<(chunk%32))
	bytes.encode_u32(72,masks[0]);bytes.encode_u32(76,masks[1])
	var hash: PackedByteArray=String(request.domain_id).sha256_text().hex_decode()
	for index in 32:bytes[96+index]=hash[index]
	for index in request.points.size():
		var point: Dictionary=request.points[index];var base: int=HEADER_BYTES+index*INPUT_STRIDE
		bytes.encode_s64(base,point.body_id);bytes.encode_s64(base+8,point.point_id)
		bytes.encode_float(base+16,point.position.x);bytes.encode_float(base+20,point.position.y);bytes.encode_float(base+24,point.position.z)
	return bytes

static func decode(bytes: PackedByteArray, request: Dictionary, serial: int) -> Dictionary:
	var result:={"error":&"readback_failed","raw":bytes.duplicate()}
	if bytes.size()!=OUTPUT_BYTES or bytes.decode_u32(0)!=VERSION or bytes.decode_s64(88)!=serial:return result
	result.schema=VERSION
	for key in I64_FIELDS:
		result[key]=bytes.decode_s64(I64_FIELDS[key])
		if result[key]!=request[key]:return result
	result.domain_id=request.domain_id
	if bytes.slice(96,128)!=String(request.domain_id).sha256_text().hex_decode():return result
	if bytes.decode_u32(68)!=request.points.size() or bytes.decode_u32(80)!=0 or bytes.decode_u32(84)!=0:return result
	var input:=encode(request,serial)
	if bytes.slice(72,80)!=input.slice(72,80):return result
	result.merge({"captured_state_seq":bytes.decode_s64(40),"captured_tick":bytes.decode_s64(48),"captured_revision":bytes.decode_s64(56),"captured_time_s":bytes.decode_float(64),"points":[],"footprint_versions":{},"footprint_change_bounds":{}})
	if result.captured_state_seq<0 or result.captured_tick<0 or result.captured_revision<0 or not is_finite(result.captured_time_s) or result.captured_time_s<0:return result
	var flags:=bytes.decode_u32(4)
	if flags!=0:
		result.error=&"stale_generation" if flags&1 else (&"stale_sample" if flags&2 else &"invalid_sample")
		return result
	for index in request.points.size():
		var base: int=HEADER_BYTES+index*POINT_STRIDE;var point: Dictionary=request.points[index]
		if bytes.decode_s64(base)!=point.body_id or bytes.decode_s64(base+8)!=point.point_id or bytes.decode_u32(base+48)!=1:return result
		var values: Array=[]
		for offset in range(16,48,4):
			var value:=bytes.decode_float(base+offset)
			if not is_finite(value):return result
			values.append(value)
		if values[4]<0:return result
		for offset in [52,56,60]:
			if bytes.decode_u32(base+offset)!=0:return result
		var position:=Vector3(values[0],values[1],values[2])
		var request_base: int=HEADER_BYTES+index*INPUT_STRIDE
		if bytes.slice(base+16,base+28)!=input.slice(request_base+16,request_base+28):return result
		result.points.append({"body_id":point.body_id,"point_id":point.point_id,"sample_position":position,"bed":values[3],"h":values[4],"eta":values[5],"u_xz":Vector2(values[6],values[7]),"valid":true})
	for chunk in chunks(request):
		var base: int=CHUNK_OFFSET+chunk*16
		if bytes.decode_u32(base)!=chunk or bytes.decode_u32(base+4)>0x7f800000:return result
		var version:=bytes.decode_s64(base+8)
		if version<0 or version>result.captured_state_seq:return result
		result.footprint_versions[chunk]=version
		result.footprint_change_bounds[chunk]=bytes.decode_float(base+4) if bytes.decode_u32(base+4)<0x7f800000 else -1.0
	result.error=&"";return result
