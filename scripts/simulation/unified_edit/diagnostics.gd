extends RefCounted

# Opt-in bounded CPU timeline. No authority data, scheduling, or GPU waits.
# Assigned before measurement; keep attached until the pipeline has shut down.
const MAX_EVENTS:=200000
var _mutex:=Mutex.new()
var _events: Array[Dictionary]=[]
var _dropped:=0

func mark(event: StringName, key: int=0, detail: Dictionary={}) -> void:
	var row:={"event":event,"key":key,"at_us":Time.get_ticks_usec(),"thread":OS.get_thread_caller_id(),"detail":detail}
	_mutex.lock()
	if _events.size()<MAX_EVENTS:_events.append(row)
	else:_dropped+=1
	_mutex.unlock()

func snapshot() -> Dictionary:
	_mutex.lock()
	var result:={"events":_events.duplicate(true),"dropped":_dropped,"capacity":MAX_EVENTS,"clock":"Time.get_ticks_usec; GPU durations are a separate clock"}
	_mutex.unlock()
	return result
