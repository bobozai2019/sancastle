extends RefCounted
class_name SandcastleWaterRenderWaveWorkload

## Canonical W08 staging workload. This is separate from the visual profile:
## an interactive scene may select none, one packet, or repeated packets.
const START_TICK := 8
const SPACING_TICKS := 180
const AMPLITUDE_M := 0.18
const DURATION_S := 6.0
const FIRST_SEED := 31
const MAX_PACKETS := 80


static func schedule(preview: Node3D, workload_id: String) -> Dictionary:
	if workload_id not in ["none", "single_packet_v1", "continuous_packets_v1"]:
		return {"ok": false, "code": "invalid_workload", "requests": []}
	if preview == null or not preview.ready_for_ticks or preview.completed_ticks >= START_TICK:
		return {"ok": false, "code": "invalid_start_state", "requests": []}
	var count := 0 if workload_id == "none" else \
		(1 if workload_id == "single_packet_v1" else MAX_PACKETS)
	var requests: Array[Dictionary] = []
	for index in count:
		var request := {"domain_id": preview.shadow_domain.domain_id,
			"generation": preview.generation, "request_id": index + 1,
			"start_tick": START_TICK + index * SPACING_TICKS,
			"profile_id": &"test_packet", "amplitude_m": AMPLITUDE_M,
			"duration_s": DURATION_S, "seed": FIRST_SEED + index * 17}
		var admitted: Dictionary = preview.request_wave(request)
		if not admitted.get("ok", false):
			return {"ok": false, "code": String(admitted.get("code", "rejected")),
				"requests": requests}
		requests.append(request)
	return {"ok": true, "code": "", "requests": requests}
