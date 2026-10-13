extends "res://tests/edit_validation/beach_undo_entry.gd"

var fail_capture_request := 0
var capture_request_count := 0

func _request_beach_capture(texture: RID, callback: Callable) -> Error:
	capture_request_count+=1
	if fail_capture_request>0 and capture_request_count==fail_capture_request: return ERR_UNAVAILABLE
	return super._request_beach_capture(texture,callback)

func _fail(message: String) -> void:
	if fail_capture_request>0 and message=="beach native capture request failed": last_error=message;return
	super._fail(message)
