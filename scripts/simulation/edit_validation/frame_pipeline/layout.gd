extends RefCounted
const Wire=preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
const MAX_COMMANDS:=64

static func pack(envelopes: Array, limit: int, token: int, revision: int, tick: int) -> Dictionary:
	if limit < 1 or limit > MAX_COMMANDS or envelopes.is_empty() or envelopes.size()>limit:return {"error":"batch_size"}
	if token<0 or revision<0 or tick<0:return {"error":"batch_epoch"}
	var data:=PackedByteArray()
	var previous_id:=-1
	var first_ticket:=-1
	var policy:=-1
	var cell_bits:=-1
	for index in envelopes.size():
		if not envelopes[index] is PackedByteArray:return {"error":"command_type"}
		var bytes: PackedByteArray=envelopes[index]
		if bytes.size()!=128:return {"error":"command_size"}
		if bytes.decode_s64(16)!=token or bytes.decode_s64(24)!=tick or bytes.decode_s64(32)!=revision+index:return {"error":"command_epoch_or_revision"}
		if bytes.decode_s64(8)<=previous_id:return {"error":"command_order"}
		if index==0:first_ticket=bytes.decode_s64(0);policy=bytes.decode_u32(84);cell_bits=bytes.decode_u32(76)
		if first_ticket<0 or bytes.decode_s64(0)!=first_ticket+index:return {"error":"ticket_order"}
		if bytes.decode_u32(84)!=policy or bytes.decode_u32(76)!=cell_bits:return {"error":"incompatible_policy_or_grid"}
		if policy not in [0,1,2,3] or bytes.decode_u32(80)!=256 or bytes.decode_u32(40) not in [0,1] or bytes.decode_u32(44) not in [0,1]:return {"error":"unsupported_command"}
		for offset in [48,52,56,60,64,68,72,76,88,92,104,108]:
			if not is_finite(bytes.decode_float(offset)):return {"error":"nonfinite_command"}
		previous_id=bytes.decode_s64(8);data.append_array(bytes)
	return {"error":"","data":data,"count":envelopes.size(),"generation":token,"input_revision":revision,"tick":tick,
		"batch_id":first_ticket,"policy":policy,"envelopes":envelopes.duplicate(true)}

static func validate_receipts(bytes: PackedByteArray, plan: Dictionary) -> Dictionary:
	if not plan.get("error","").is_empty() or bytes.size()!=int(plan.get("count",0))*128 or bytes.is_empty():return {"error":"receipt_array_size"}
	var revision: int=plan.input_revision
	var stopped:=false
	var accepted:=0
	var rejected_index:=-1
	var receipts:=[]
	var dirty_mask:=[0,0]
	var dirty_rect:=Rect2i()
	for index in plan.count:
		var command: PackedByteArray=plan.envelopes[index]
		var receipt:=Wire.decode_receipt(bytes.slice(index*128,(index+1)*128))
		var expected_input: int=command.decode_s64(32) if stopped else revision
		if not Wire.receipt_matches(receipt,command.decode_s64(0),command.decode_s64(8),plan.generation,expected_input) or receipt.get("applied_tick")!=plan.tick:return {"error":"receipt_identity_or_chain","index":index}
		if stopped:
			if receipt.status!=0 or receipt.output_revision!=revision or receipt.error_code!=0 or receipt.actual_sand_m3!=0.0 or receipt.dirty_mask!=[0,0] or receipt.displaced_water_m3!=0.0 or receipt.retained_water_m3!=0.0 or receipt.impulse_x_m4_s!=0.0 or receipt.impulse_z_m4_s!=0.0:return {"error":"tail_not_executed","index":index}
		elif receipt.status==1:
			accepted+=1;revision=receipt.output_revision
			dirty_mask[0]|=int(receipt.dirty_mask[0]);dirty_mask[1]|=int(receipt.dirty_mask[1])
			if receipt.dirty_rect.has_area():dirty_rect=dirty_rect.merge(receipt.dirty_rect) if dirty_rect.has_area() else receipt.dirty_rect
		elif receipt.status==2 and receipt.output_revision==revision:
			stopped=true;rejected_index=index
		else:return {"error":"receipt_status","index":index}
		receipts.append(receipt)
	return {"error":"","receipts":receipts,"accepted_count":accepted,"rejected_index":rejected_index,
		"output_revision":revision,"dirty_mask":dirty_mask,"dirty_rect":dirty_rect,"not_executed_count":plan.count-accepted-(1 if stopped else 0)}
