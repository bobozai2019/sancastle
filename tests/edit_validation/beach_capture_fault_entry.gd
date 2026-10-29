extends "res://tests/edit_validation/beach_recovery_entry.gd"

# Test-only request and payload fault adapter. Real accepted requests retain
# the original asynchronous path; unexpected errors still use production fail.
var capture_requests := 0
var fail_request := false
var corrupt_payload := false
var injected := false
var fault_us := -1

func _request_beach_capture(texture: RID, callback: Callable) -> Error:
	capture_requests+=1
	if fail_request and capture_requests==27:
		injected=true;fault_us=Time.get_ticks_usec();return ERR_UNAVAILABLE
	return super._request_beach_capture(texture,callback)

func _on_checkpoint_field(bytes: PackedByteArray, field: String, revision: int, token: int) -> void:
	if corrupt_payload and field=="raw_sand":
		bytes=bytes.duplicate();bytes.encode_float(0,NAN);injected=true;fault_us=Time.get_ticks_usec()
	super._on_checkpoint_field(bytes,field,revision,token)

func _fail(message: String) -> void:
	if injected and message in ["beach native capture request failed","beach checkpoint validation: invalid_beach_float"]:
		last_error=message;return
	super._fail(message)
