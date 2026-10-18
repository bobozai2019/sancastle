extends PanelContainer

# Read-only bounded window statistics. No alternate solver/readback is created.
var sampling:=true
var samples: Array[float]=[]
var elapsed:=0.0
@onready var beach=get_parent().get_parent()
@onready var rows=$Margin/Rows

func _ready() -> void:
	sampling=rows.get_node("Header/Sampling").button_pressed
	rows.get_node("StageHeading").text="统一流水线 · 当前状态"
	rows.get_node("Stages").get_node("Names").text="排队工作\nGPU在途\n完成态版本\n完成tick\n物理块\n未消费结果"
	rows.get_node("Cpu").text="CPU/GPU阶段成本见专项验收"
	rows.get_node("RenderTime").text="窗口帧统计不等于模拟吞吐"

func _on_sampling_toggled(value: bool) -> void:sampling=value;samples.clear()
func stop_sampling() -> void:sampling=false;samples.clear()

func _process(delta: float) -> void:
	if sampling:
		samples.append(delta*1000.0)
		if samples.size()>120:samples.pop_front()
	elapsed+=delta
	if elapsed<0.25:return
	elapsed=0.0
	var sorted:=samples.duplicate();sorted.sort()
	if sorted.is_empty():rows.get_node("Summary").text="帧统计已暂停"
	else:
		var total:=0.0
		for sample in sorted:total+=sample
		rows.get_node("Summary").text="%.1f FPS · 帧均值 %.2f ms · P95 %.2f ms"%[1000.0/(total/sorted.size()),total/sorted.size(),sorted[mini(sorted.size()-1,int(sorted.size()*0.95))]]
	var runtime=beach.runtime
	if runtime.current==null:rows.get_node("State").text=String(runtime.phase);return
	var pipeline=runtime.current
	rows.get_node("Simulation").text="模拟 %.2f s · %s"%[pipeline.advanced_time_s,"运行" if beach.playing else "暂停"]
	rows.get_node("Stages").get_node("Values").text="%d\n%d\n%d\n%d\n%d / 64\n%d"%[pipeline.pending_count(),pipeline.active_count(),pipeline.completed_state_seq,pipeline.completed_tick,runtime.surfaces[runtime.current_index].applied_revisions.size(),runtime.result_reservations()]
	rows.get_node("Collision").text="generation %d · %s"%[beach.generation,String(runtime.phase)]
	rows.get_node("State").text=beach.action_message
