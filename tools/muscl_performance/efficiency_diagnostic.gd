extends RefCounted

# All mutable fields and RD operations belong to the render thread. Snapshots
# are copied before the next tick, and asynchronous callbacks marshal back to
# that thread. Close never waits and never frees an in-flight staging buffer.
const SNAPSHOT_BYTES:=2256 # original 2240 + sampled pre-edge retry cache 16
const QUEUE_CAPACITY:=4
const MAX_SAMPLES:=1024
const MAX_MARKS_PER_FRAME:=64
var rd: RenderingDevice
var retry_cache_source:=RID()
var enabled:=false
var stride:=8
var selected_slot_override:=-1
var _ticks:=0
var _sample_serial:=0
var _slots: Array[Dictionary]=[]
var _rows: Array[Dictionary]=[]
var _cpu_ticks: Array[Dictionary]=[]
var _cpu_dropped:=0
var _closing:=false
var _frame:=-1
var _budget:=0
var _current: Dictionary={}
var _open_label:=""
var _span_serial:=0
var _open_cpu:=0
var _tick_cpu:=0
var _mark_count:=0
var dropped:={"queue":0,"budget":0,"capacity":0,"copy":0,"registration":0,"readback":0,"closed":0,"markers":0}

func initialize(device: RenderingDevice) -> bool:
	if rd!=null:return false
	rd=device
	for i in QUEUE_CAPACITY:
		var rid:=rd.storage_buffer_create(SNAPSHOT_BYTES)
		if not rid.is_valid():close();return false
		_slots.append({"rid":rid,"busy":false})
	return true

func begin_tick(standard: bool, requested_dt: float) -> bool:
	if not enabled or _closing or rd==null:return false
	_ticks+=1
	if _ticks%stride!=0:return false
	var serial:=_sample_serial;_sample_serial+=1
	if _rows.size()+pending()>=MAX_SAMPLES:dropped.capacity+=1;return false
	var frame:=Engine.get_frames_drawn()
	if frame!=_frame:_frame=frame;_budget=0
	if _budget+MAX_MARKS_PER_FRAME>MAX_MARKS_PER_FRAME:dropped.budget+=1;return false
	var free:=-1
	for i in _slots.size():
		if not _slots[i].busy and _slots[i].rid.is_valid():free=i;break
	if free<0:dropped.queue+=1;return false
	_budget+=MAX_MARKS_PER_FRAME;_slots[free].busy=true
	_current={"record_seq":_ticks,"sample_id":serial,"slot":serial%64 if selected_slot_override<0 else selected_slot_override,"staging_slot":free,"standard_cached":standard,"requested_dt":requested_dt,"cpu_spans":[],"spans":[],"record_frame":frame}
	_tick_cpu=Time.get_ticks_usec();_span_serial=0;_open_label="";_mark_count=0
	stamp("tick_start")
	return true

func stamp(suffix: String) -> void:
	# Recorder descriptor layout currently needs <= 62 markers, including whole
	# tick and grouped initial validation. Refuse excess diagnostic marks only.
	if _mark_count>=MAX_MARKS_PER_FRAME:dropped.markers+=1;return
	rd.capture_timestamp("m2_%d_%s"%[_current.sample_id,suffix]);_mark_count+=1

func pass_begin(label: String, candidate: int, rk_phase: int) -> void:
	var name:=""
	if candidate==int(_current.slot):name=label+"_p"+str(rk_phase)
	elif candidate<0:name="initial" if label in ["decision_0","edge","decision_7","boundary"] else label
	if name==_open_label:return
	finish_span()
	if name.is_empty():return
	_open_label=name;_open_cpu=Time.get_ticks_usec()
	if label=="edge" and candidate==int(_current.slot) and rk_phase==0:
		_current.retry_copy_ok=retry_cache_source.is_valid() and rd.buffer_copy(retry_cache_source,_slots[int(_current.staging_slot)].rid,0,2240,16)==OK
	_current.spans.append({"ordinal":_span_serial,"stage":name,"candidate_slot":candidate,"rk_phase":rk_phase})
	stamp("s%d_start"%_span_serial)

func finish_span() -> void:
	if _open_label.is_empty():return
	stamp("s%d_end"%_span_serial)
	_current.cpu_spans.append({"ordinal":_span_serial,"start_us":_open_cpu,"end_us":Time.get_ticks_usec()})
	_span_serial+=1;_open_label=""

func end_tick(decision: RID, audit: RID, control: RID) -> void:
	finish_span();stamp("tick_end")
	_current.cpu_start_us=_tick_cpu;_current.cpu_end_us=Time.get_ticks_usec();_current.mark_count=_mark_count
	var slot: int=_current.staging_slot
	var target: RID=_slots[slot].rid
	var row:=_current;_current={}
	if rd.buffer_copy(decision,target,0,0,64)!=OK or rd.buffer_copy(audit,target,0,64,2048)!=OK or rd.buffer_copy(control,target,0,2112,128)!=OK:
		dropped.copy+=1;_slots[slot].busy=false;return
	# Exactly one readback per sampled tick, never a CPU/GPU wait.
	var error:=rd.buffer_get_data_async(target,_readback.bind(row),0,SNAPSHOT_BYTES)
	if error!=OK:dropped.registration+=1;_slots[slot].busy=false

func _readback(bytes: PackedByteArray, row: Dictionary) -> void:
	RenderingServer.call_on_render_thread(_receive.bind(bytes,row))

func _receive(bytes: PackedByteArray, row: Dictionary) -> void:
	var slot: int=row.staging_slot
	if bytes.size()!=SNAPSHOT_BYTES:dropped.readback+=1
	elif _closing:dropped.closed+=1
	else:
		row.retry_before_edge_hex=bytes.slice(2240,2256).hex_encode() if row.get("retry_copy_ok",false) else ""
		row.decision_hex=bytes.slice(0,64).hex_encode();row.audit_hex=bytes.slice(64,2112).hex_encode();row.control_hex=bytes.slice(2112,2240).hex_encode()
		row.generation=bytes.decode_s64(2120);row.state_seq_before_seal=bytes.decode_s64(2128)
		row.sim_tick=bytes.decode_s64(2136);row.advanced_time_s=bytes.decode_float(2144)
		row.actual_dt=bytes.decode_float(2148);row.control_flags=bytes.decode_u32(2116)
		row.accepted_count=bytes.decode_u32(4);row.rejected_count=bytes.decode_u32(40);row.status=bytes.decode_u32(16)
		row.invalid_slots=64-row.accepted_count-row.rejected_count if row.control_flags==0 and row.status!=2 else null
		_rows.append(row)
	_slots[slot].busy=false
	if _closing:free_slot(slot)

func pending() -> int:
	var count:=0
	for slot in _slots:
		if slot.busy:count+=1
	return count

func record_cpu(start_us: int, end_us: int, sampled: bool) -> void:
	if _cpu_ticks.size()>=4096:_cpu_dropped+=1;return
	_cpu_ticks.append({"record_seq":_ticks,"start_us":start_us,"end_us":end_us,"sampled":sampled})

func snapshot() -> Dictionary:
	return {"samples":_rows.duplicate(true),"cpu_ticks":_cpu_ticks.duplicate(true),"cpu_ticks_dropped":_cpu_dropped,"dropped":dropped.duplicate(),"pending":pending(),"sample_attempts":_sample_serial,"recorded_ticks":_ticks,"queue_capacity":QUEUE_CAPACITY,"max_samples":MAX_SAMPLES,"snapshot_bytes":SNAPSHOT_BYTES,"staging_bytes":QUEUE_CAPACITY*SNAPSHOT_BYTES,"stride":stride,"max_extra_marks_per_frame":MAX_MARKS_PER_FRAME}

func free_slot(index: int) -> void:
	if _slots[index].rid.is_valid():rd.free_rid(_slots[index].rid);_slots[index].rid=RID()

func close() -> void:
	enabled=false;_closing=true
	for i in _slots.size():
		if not _slots[i].busy:free_slot(i)
