extends PanelContainer

## Informational HUD only. Read completed timestamp results without GPU waits.
const REFRESH_US := 500000
const STAGES := ["boundary", "water", "sediment", "material", "foam", "audit", "edit", "collision"]
const STAGE_LABELS := ["边界 / CFL", "水流更新", "侵蚀 / 沉积", "湿润 / 沙坡", "白沫更新", "统计 / 审计", "挖填沙", "碰撞打包"]

@onready var beach = get_parent().get_parent()
@onready var summary: Label = $Margin/Rows/Summary
@onready var cpu: Label = $Margin/Rows/Cpu
@onready var render_time: Label = $Margin/Rows/RenderTime
@onready var simulation: Label = $Margin/Rows/Simulation
@onready var stage_names: Label = $Margin/Rows/Stages/Names
@onready var stage_values: Label = $Margin/Rows/Stages/Values
@onready var collision: Label = $Margin/Rows/Collision
@onready var state: Label = $Margin/Rows/State
@onready var sample_toggle: CheckButton = $Margin/Rows/Header/Sampling

var sampling := false
var collect_pending := false
var sample_epoch := 0
var sample_generation := -1
var seen_frame := -1 # Render-thread use only.
var saved_solver
var saved_proxy
var saved_solver_flag := false
var saved_proxy_flag := false
var window_start_us := 0
var window_frames := 0
var window_tick := 0
var frame_ms_sum := 0.0
var frame_ms_max := 0.0
var process_ms_sum := 0.0
var physics_ms_sum := 0.0
var render_cpu_sum := 0.0
var render_gpu_sum := 0.0
var stage_sums := {}
var stage_counts := {}
var last_stages := {}
var accepted_frames := 0
var last_capture_frame := -1
var snapshot := {}
var hud_visible := true

func _ready() -> void:
	stage_names.text = "\n".join(STAGE_LABELS)
	_reset_window(Time.get_ticks_usec())
	_refresh()

func _on_sampling_toggled(_enabled: bool) -> void:
	get_viewport().gui_release_focus()
	_sync_sampling()

func _sync_sampling() -> void:
	visible = not beach.hide_hud
	if visible != hud_visible:
		hud_visible = visible
		_reset_window(Time.get_ticks_usec())
	var enabled: bool = visible and sample_toggle.button_pressed and beach.ready_for_ticks and not beach.closing and not beach.shutdown_requested and beach.last_error.is_empty()
	var generation_changed: bool = sample_generation != beach.generation
	if generation_changed:
		sample_generation = beach.generation
		last_stages.clear()
		accepted_frames = 0
		last_capture_frame = -1
		_reset_window(Time.get_ticks_usec())
	if enabled == sampling and not generation_changed:
		return
	sampling = enabled
	sample_epoch += 1
	stage_sums.clear()
	stage_counts.clear()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), enabled)
	RenderingServer.call_on_render_thread(_configure_render.bind(enabled))

func _configure_render(enabled: bool) -> void:
	if saved_solver != null:
		saved_solver.profile_passes = saved_solver_flag
		if is_instance_valid(saved_proxy): saved_proxy.profile_passes = saved_proxy_flag
		saved_solver = null
	seen_frame = -1
	if not enabled or beach.closing or beach.solver == null:
		return
	saved_solver = beach.solver
	saved_proxy = beach.collision_proxy
	saved_solver_flag = saved_solver.profile_passes
	saved_proxy_flag = saved_proxy.profile_passes
	saved_solver.profile_passes = true
	saved_proxy.profile_passes = true

func _process(_delta: float) -> void:
	_sync_sampling()
	var now := Time.get_ticks_usec()
	if visible:
		var elapsed_ms := float(now - int(snapshot.get("previous_us", now))) / 1000.0
		snapshot.previous_us = now
		window_frames += 1
		frame_ms_sum += elapsed_ms
		frame_ms_max = maxf(frame_ms_max, elapsed_ms)
		process_ms_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if sampling:
			var viewport_rid := get_viewport().get_viewport_rid()
			render_cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
			render_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
			if not collect_pending:
				collect_pending = true
				RenderingServer.call_on_render_thread(_collect_render.bind(sample_epoch, sample_generation))
	if now - window_start_us >= REFRESH_US:
		_refresh()
		_reset_window(now)

func _collect_render(epoch: int, generation: int) -> void:
	var groups := {}
	var captured := -1
	if not beach.closing and beach.solver != null and beach.solver.rd != null and generation == beach.generation:
		var rd: RenderingDevice = beach.solver.rd
		# Tag the render frame so delayed results from a restored generation
		# cannot enter the new generation's display.
		rd.capture_timestamp("sandcastle_profile_generation_%d" % generation)
		captured = rd.get_captured_timestamps_frame()
		if captured != seen_frame:
			seen_frame = captured
			var starts := {}
			var tagged_generation := false
			var mixed_generation := false
			for i in rd.get_captured_timestamps_count():
				var name := rd.get_captured_timestamp_name(i)
				if name == "sandcastle_profile_generation_%d" % generation:
					tagged_generation = true
				elif name.begins_with("sandcastle_profile_generation_"):
					mixed_generation = true
				if not name.begins_with("sandcastle_") and not name.begins_with("edit_"):
					continue
				var gpu_ns := rd.get_captured_timestamp_gpu_time(i)
				if name.ends_with("_start"):
					starts[name.trim_suffix("_start")] = gpu_ns
				elif name.ends_with("_end"):
					var key := name.trim_suffix("_end")
					if not starts.has(key): continue
					var duration: int = gpu_ns - int(starts[key])
					starts.erase(key)
					var group := _stage_for(key)
					# Godot 4.7 D3D12/Vulkan drivers return nanoseconds, despite
					# the RenderingDevice class reference saying microseconds.
					if duration >= 0 and not group.is_empty():
						groups[group] = float(groups.get(group, 0.0)) + float(duration) / 1000000.0
			if not tagged_generation or mixed_generation: groups.clear()
	call_deferred("_accept_sample", epoch, generation, captured, groups)

static func _stage_for(key: String) -> String:
	if key.begins_with("edit_") or key == "sandcastle_tool": return "edit"
	match key.trim_prefix("sandcastle_"):
		"tide", "cfl": return "boundary"
		"edge", "drain", "update": return "water"
		"sediment": return "sediment"
		"material": return "material"
		"foam": return "foam"
		"gauge", "audit", "sand_audit": return "audit"
		"collision": return "collision"
	return ""

func _accept_sample(epoch: int, generation: int, captured: int, groups: Dictionary) -> void:
	collect_pending = false
	if epoch != sample_epoch or generation != sample_generation or not sampling:
		return
	if not groups.is_empty():
		accepted_frames += 1
		last_capture_frame = captured
	for key in groups:
		stage_sums[key] = float(stage_sums.get(key, 0.0)) + float(groups[key])
		stage_counts[key] = int(stage_counts.get(key, 0)) + 1

func _reset_window(now: int) -> void:
	window_start_us = now
	window_frames = 0
	window_tick = beach.completed_ticks
	frame_ms_sum = 0.0
	frame_ms_max = 0.0
	process_ms_sum = 0.0
	physics_ms_sum = 0.0
	render_cpu_sum = 0.0
	render_gpu_sum = 0.0
	stage_sums.clear()
	stage_counts.clear()
	snapshot.previous_us = now

func _refresh() -> void:
	var now := Time.get_ticks_usec()
	var seconds := float(now - window_start_us) / 1000000.0
	var count := maxi(window_frames, 1)
	var fps := float(window_frames) / seconds if seconds > 0.0 else 0.0
	var ticks_per_s := float(maxi(0, beach.completed_ticks - window_tick)) / seconds if seconds > 0.0 else 0.0
	summary.text = "%.1f FPS  |  帧 %.2f ms  |  峰值 %.2f ms" % [fps, frame_ms_sum / count, frame_ms_max]
	cpu.text = "引擎 CPU %.2f ms  ·  物理 %.2f ms" % [process_ms_sum / count, physics_ms_sum / count]
	render_time.text = "渲染 CPU %.2f ms  ·  GPU %.2f ms" % [render_cpu_sum / count, render_gpu_sum / count] if sampling else "渲染 CPU / GPU：—（采样关闭）"
	simulation.text = "模拟 %.1f tick/s  ·  %.2f×  ·  子步 %d" % [ticks_per_s, ticks_per_s / 30.0, beach.last_substeps]
	var values := PackedStringArray()
	for key in STAGES:
		if stage_counts.has(key):
			last_stages[key] = {"ms":float(stage_sums[key]) / int(stage_counts[key]), "at_us":now}
		if not last_stages.has(key):
			values.append("—")
		else:
			var last: Dictionary = last_stages[key]
			values.append("%.3f%s" % [float(last.ms), " · 上次" if not stage_counts.has(key) else ""])
	stage_values.text = "\n".join(values)
	var proxy = beach.collision_proxy
	collision.text = "碰撞回读 %.2f ms · CPU 替换 %.2f ms（上次）" % [proxy.last_readback_ms, proxy.last_replace_ms] if proxy != null and proxy.completed_batches > 0 else "碰撞回读 / CPU 替换：—"
	var status := "运行" if beach.playing else "暂停 · 保留最后采样"
	if not beach.ready_for_ticks: status = "准备 / 恢复中"
	if not beach.last_error.is_empty(): status = "故障"
	if not sample_toggle.button_pressed: status += " · 分阶段采样关闭"
	state.text = status
	snapshot.merge({"fps":fps,"frame_ms":frame_ms_sum / count,"ticks_per_s":ticks_per_s,"generation":sample_generation,"stages":last_stages.duplicate(true)}, true)

func _exit_tree() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	RenderingServer.call_on_render_thread(_restore_flags.bind(saved_solver, saved_proxy, saved_solver_flag, saved_proxy_flag))

static func _restore_flags(solver, proxy, solver_flag: bool, proxy_flag: bool) -> void:
	if solver != null: solver.profile_passes = solver_flag
	if is_instance_valid(proxy): proxy.profile_passes = proxy_flag
