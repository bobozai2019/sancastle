extends RefCounted
const Layout=preload("res://scripts/simulation/edit_validation/frame_pipeline/layout.gd")

static func validate(bytes: PackedByteArray, plan: Dictionary) -> Dictionary:
	var decoded:=Layout.validate_receipts(bytes,plan)
	if not decoded.error.is_empty():return decoded
	# not_executed has identities only. Reject even metadata-only mutations;
	# the frozen base validator already checks actual-volume/momentum effects.
	for index in plan.count:
		if decoded.receipts[index].status!=0:continue
		for offset in range(48,128,4):
			if bytes.decode_u32(index*128+offset)!=0:return {"error":"tail_not_executed_bytes","index":index,"offset":offset}
	return decoded
