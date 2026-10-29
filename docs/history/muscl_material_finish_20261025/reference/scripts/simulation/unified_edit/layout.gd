extends RefCounted

const Profile=preload("res://scripts/simulation/unified_edit/tool_profile.gd")

# Single byte-layout authority. GPU shaders consume shader_defines(), never a
# separate hand-maintained offset table. int64 is two uint32 words, low first.
const VERSION:=1
const COMMAND_MAGIC:=0x31444555 # UED1
const RESULT_MAGIC:=0x31524555 # UER1
const BATCH_MAGIC:=0x31424555 # UEB1
const COMPLETION_MAGIC:=0x31434555 # UEC1
const COMMAND_BYTES:=512
const RESULT_BYTES:=384
const HEADER_BYTES:=96
const COMPLETION_BYTES:=96
const CONTROL_BYTES:=128 # Existing completed water-state layout, not a command.
const FATAL_FLAGS_MASK:=63
const MAX_COMMANDS:=64
const WORK_SLOTS:=3
const HEIGHT_SLOTS:=2
const MAX_PROFILES:=64
const MAX_TEMPLATES:=16
const INPUT_BYTES:=HEADER_BYTES+MAX_COMMANDS*COMMAND_BYTES
const OUTPUT_BYTES:=COMPLETION_BYTES+MAX_COMMANDS*RESULT_BYTES
const CELL_BYTES:=64
const REDUCE_BLOCK_BYTES:=128
const REDUCE_BLOCKS:=256
const SUMMARY_BUFFER_BYTES:=(REDUCE_BLOCKS+1)*REDUCE_BLOCK_BYTES
const INT64_MAX:=9223372036854775807
const CONTROL_OPERATION:=0xffffffff
enum ControlKind { NONE, BEGIN, END, CANCEL }
enum Outcome { APPLIED=1, NO_CHANGE=2, REJECTED=3 }
enum Ledger { APPROXIMATE_EXTERNAL, EXACT_EXTERNAL, CONSERVATIVE_TRANSFER, UNCHANGED, TRANSFER_WITH_SINK }
enum CompletionState { COMPLETE=1, FATAL=2 }
enum WorkKind { EDIT, WATER_TICK }
enum ErrorCode { NONE, INVALID_COMMAND, STALE_GENERATION, OUT_OF_DOMAIN, BACKEND_UNAVAILABLE, UNSUPPORTED_PROFILE, UNKNOWN_PROFILE, TEMPLATE_MISMATCH, INVALID_PLACEMENT, BUDGET_EXCEEDED, RECEIVER_CAPACITY, STROKE_BUFFER_FULL, COLLISION_PENDING, STALE_TICK, INVALID_BASELINE, INVALID_RECEIPT, CANDIDATE_INVALID, WATER_CANDIDATE_INVALID, MATERIAL_CANDIDATE_INVALID }
enum CandidateFlag { TOUCHED=1, DONOR=2, LEFT=4, RIGHT=8, INVALID_VALUE=256, INVALID_WATER=512, OBSTACLE=1024, UNSUPPORTED=2048, EMPTY_TEMPLATE=4096 }
const GPU_COMPLETE:=1

const HEADER_U32={"magic":0,"version":4,"stride":8,"command_count":12,"command_stride":16,"result_stride":20,"slot_id":24,"work_kind":28}
const HEADER_I64={"generation":32,"batch_seq":40,"lease_id":48}
const HEADER_HASH={"domain_hash":56}
const COMPLETION_U32={"magic":0,"version":4,"stride":8,"result_count":12,"slot_id":64,"state":68,"error_flags":72,"result_stride":76,"accepted_count":88,"rejected_count":92}
const COMPLETION_I64={"generation":16,"batch_seq":24,"lease_id":32,"state_seq":40,"sim_tick":48,"revision":56}
const COMPLETION_F32={"advanced_time_s":80,"actual_dt":84}

const COMMAND_U32={"magic":0,"version":4,"stride":8,"operation":12,"shape":16,"destination":20,"fields":24,"capabilities":28,"profile_version":80,"water_policy":84,"material_policy":88,"control_kind":92,"volume_sign":288,"height_reference":292,"target_rule":296,"transfer_policy":300,"stroke_policy":304,"template_index":308,"ledger":312,"rect_x":328,"rect_z":332,"rect_w":336,"rect_h":340,"template_width":344,"template_height":348,"template_channels":356,"grid_size":360}
const COMMAND_I64={"command_id":32,"generation":40,"stroke_id":48,"baseline_token":56,"sample_index":64,"sim_tick":72,"seed":320}
const COMMAND_HASH={"domain_hash":96,"effective_hash":128,"template_hash":160}
const COMMAND_F32={"start_x":192,"start_z":196,"end_x":200,"end_z":204,"yaw_rad":208,"scale_xz":212,"radius_m":216,"strength":220,"height_m":224,"bottom_width_m":228,"top_width_m":232,"depth_m":236,"trench_width_m":240,"shoulder_width_m":244,"amount_m3":248,"speed_m_s":252,"datum_y_m":256,"add_budget_m3":260,"transfer_budget_m3":264,"available_m3":268,"cell_size_m":272,"ridge_height_m":276,"legacy_epsilon_m3":280,"dry_depth_m":284,"template_spacing_m":352}
const RESULT_U32={"magic":0,"version":4,"stride":8,"outcome":12,"slot_id":96,"changed_fields":100,"error_code":104,"completion_phase":108,"dirty_low":112,"dirty_high":116,"changed_cells":120,"touched_cells":124,"rect_x":192,"rect_z":196,"rect_w":200,"rect_h":204,"ledger":288,"invalid_flags":292,"coverage_changed":296,"profile_version":312}
const RESULT_I64={"command_id":16,"generation":24,"stroke_id":32,"baseline_token":40,"input_revision":48,"output_revision":56,"applied_tick":64,"state_seq":72,"batch_seq":80,"lease_id":88,"sample_index":304}
const RESULT_HASH={"domain_hash":208,"effective_hash":240}
const RESULT_F32={"added_m3":128,"removed_m3":132,"transferred_m3":136,"left_received_m3":140,"right_received_m3":144,"source_m3":148,"sink_m3":152,"sand_error_m3":156,"eps_sand_m3":160,"eps_transfer_m3":164,"water_error_m3":168,"eps_water_m3":172,"sediment_error_m3":176,"eps_sediment_m3":180,"impulse_x_m4_s":184,"impulse_z_m4_s":188,"displaced_water_m3":272,"retained_water_m3":276,"max_cell_delta_m":280,"absolute_volume_delta_m3":284}
const CELL_WORDS={"old_value":0,"new_value":1,"rock":2,"water":3,"old_compaction":4,"new_compaction":5,"old_tag":6,"old_reference":7,"new_tag":8,"new_reference":9,"baseline":10,"target_height":11,"weight":12,"direction_x":13,"direction_z":14,"flags":15}
const SUMMARY_WORDS={"net_volume":0,"removed":1,"left_received":2,"right_received":3,"sand_ulp_budget":4,"sand_absolute_delta":5,"water_error":6,"water_ulp_budget":7,"water_absolute_delta":8,"sediment_error":9,"sediment_ulp_budget":10,"sediment_absolute_delta":11,"max_delta":12,"changed_cells":13,"touched_cells":14,"water_touched":15,"rect_min_x":16,"rect_min_z":17,"rect_max_x":18,"rect_max_z":19,"dirty_low":20,"dirty_high":21,"invalid_flags":22,"changed_fields":23,"sediment_touched":24,"coverage_changed":25,"material_changed":26,"donor_moved":27,"donor_tagged":28,"donor_compaction_sum":29,"nominal_cut":30,"reserved_zero":31}

static func shader_defines() -> String:
	var source:="// Generated from unified_edit/layout.gd; all *_WORD offsets index uint[].\n"
	var sizes:={"VERSION":VERSION,"COMMAND_MAGIC":COMMAND_MAGIC,"RESULT_MAGIC":RESULT_MAGIC,"BATCH_MAGIC":BATCH_MAGIC,"COMPLETION_MAGIC":COMPLETION_MAGIC,"COMMAND_BYTES":COMMAND_BYTES,"RESULT_BYTES":RESULT_BYTES,"HEADER_BYTES":HEADER_BYTES,"COMPLETION_BYTES":COMPLETION_BYTES,"CONTROL_BYTES":CONTROL_BYTES,"FATAL_FLAGS_MASK":FATAL_FLAGS_MASK,"MAX_COMMANDS":MAX_COMMANDS,"WORK_SLOTS":WORK_SLOTS,"HEIGHT_SLOTS":HEIGHT_SLOTS,"MAX_PROFILES":MAX_PROFILES,"MAX_TEMPLATES":MAX_TEMPLATES,"CELL_WORD_COUNT":CELL_BYTES/4,"SUMMARY_WORD_COUNT":REDUCE_BLOCK_BYTES/4,"SUMMARY_BUFFER_BYTES":SUMMARY_BUFFER_BYTES,"CONTROL_OPERATION":CONTROL_OPERATION}
	for key in sizes:source+="#define UE_"+String(key)+" "+str(int(sizes[key]))+"u\n"
	for pair in [["H",HEADER_U32],["H",HEADER_I64],["H",HEADER_HASH],["DONE",COMPLETION_U32],["DONE",COMPLETION_I64],["DONE",COMPLETION_F32],["C",COMMAND_U32],["C",COMMAND_I64],["C",COMMAND_HASH],["C",COMMAND_F32],["R",RESULT_U32],["R",RESULT_I64],["R",RESULT_HASH],["R",RESULT_F32]]:
		for key in pair[1]:source+="#define UE_"+pair[0]+"_"+String(key).to_upper()+"_WORD "+str(int(pair[1][key])/4)+"u\n"
	for pair in [["CELL",CELL_WORDS],["SUMMARY",SUMMARY_WORDS]]:
		for key in pair[1]:source+="#define UE_"+pair[0]+"_"+String(key).to_upper()+" "+str(pair[1][key])+"u\n"
	for pair in [["CONTROL",ControlKind],["OUTCOME",Outcome],["LEDGER",Ledger],["STATE",CompletionState],["WORK",WorkKind],["ERROR",ErrorCode],["FLAG",CandidateFlag],["OP",Profile.Operation],["SHAPE",Profile.Shape],["DEST",Profile.Destination],["SIGN",Profile.VolumeSign],["HEIGHT",Profile.HeightReference],["TARGET",Profile.TargetRule],["TRANSFER",Profile.TransferPolicy],["MATERIAL",Profile.MaterialPolicy],["STROKE",Profile.StrokePolicy],["FIELD",{"BED":Profile.BED,"SUSPENDED":Profile.SUSPENDED,"MATERIAL":Profile.MATERIAL,"WATER":Profile.WATER,"MOMENTUM":Profile.MOMENTUM,"COVERAGE":Profile.COVERAGE}]]:
		for key in pair[1]:source+="#define UE_"+pair[0]+"_"+String(key)+" "+str(pair[1][key])+"u\n"
	return source

static func description() -> Dictionary:
	return {"family":"unified_edit","version":VERSION,"endianness":"little","int64_transport":"two uint32 low/high words; never float or shaderInt64","positive_int64_max":"9223372036854775807","native_control_bytes":CONTROL_BYTES,"fatal_flags_mask":FATAL_FLAGS_MASK,"command_bytes":COMMAND_BYTES,"result_bytes":RESULT_BYTES,"batch_header_bytes":HEADER_BYTES,"completion_header_bytes":COMPLETION_BYTES,"max_commands":MAX_COMMANDS,"work_slots":WORK_SLOTS,"height_slots":HEIGHT_SLOTS,"max_profiles":MAX_PROFILES,"max_templates":MAX_TEMPLATES,"input_slot_bytes":INPUT_BYTES,"output_slot_bytes":OUTPUT_BYTES,"cell_bytes":CELL_BYTES,"reduction_block_bytes":REDUCE_BLOCK_BYTES,"reduction_blocks":REDUCE_BLOCKS,"summary_buffer_bytes":SUMMARY_BUFFER_BYTES,"command":{"u32":COMMAND_U32,"i64":COMMAND_I64,"f32":COMMAND_F32,"sha256":COMMAND_HASH},"result":{"u32":RESULT_U32,"i64":RESULT_I64,"f32":RESULT_F32,"sha256":RESULT_HASH},"batch_header":{"u32":HEADER_U32,"i64":HEADER_I64,"sha256":HEADER_HASH},"completion_header":{"u32":COMPLETION_U32,"i64":COMPLETION_I64,"f32":COMPLETION_F32},"cell_words":CELL_WORDS,"summary_words":SUMMARY_WORDS,"enums":{"operation":Profile.Operation,"shape":Profile.Shape,"destination":Profile.Destination,"volume_sign":Profile.VolumeSign,"height_reference":Profile.HeightReference,"target_rule":Profile.TargetRule,"transfer_policy":Profile.TransferPolicy,"material_policy":Profile.MaterialPolicy,"stroke_policy":Profile.StrokePolicy,"control_kind":ControlKind,"outcome":Outcome,"ledger":Ledger,"completion_state":CompletionState,"work_kind":WorkKind,"error_code":ErrorCode,"candidate_flag":CandidateFlag}}
