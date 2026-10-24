extends SceneTree

# Local-only receiver for Godot's built-in debugger profiler protocol.
var server:=TCPServer.new()
var stream: StreamPeerTCP
var packets:=PacketPeerStream.new()
var messages: Array=[]
var output:="res://test_output/parameter_function_profile/messages.json"
var deadline:=0
var finish_at:=0

func _initialize() -> void:
	Engine.max_fps=120
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	packets.input_buffer_max_size=8388608
	if server.listen(16017,"127.0.0.1")!=OK:quit(1);return
	deadline=Time.get_ticks_msec()+180000
	print("FUNCTION_RECEIVER_READY")

func _process(_delta: float) -> bool:
	if stream==null and server.is_connection_available():
		stream=server.take_connection();packets.stream_peer=stream
	if stream!=null:
		stream.poll()
		while packets.get_available_packet_count()>0:
			var message=packets.get_var(false)
			if not message is Array or message.size()!=3:continue
			var name:=str(message[0])
			if name.begins_with("servers:") or name.begins_with("function_probe:") or name=="error":messages.append(message)
			if name=="function_probe:done":finish_at=Time.get_ticks_msec()+1000
	if Time.get_ticks_msec()>deadline or (finish_at>0 and Time.get_ticks_msec()>finish_at):
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var f:=FileAccess.open(output,FileAccess.WRITE)
		f.store_string(JSON.stringify(messages,"",true,true));f.close()
		print("FUNCTION_RECEIVER_SAVED ",messages.size());quit()
	return false
