extends RefCounted

# Both families instantiate the same unified backend. Family follows the actual
# PackedScene identity, never an execution-mode flag or a legacy fallback.
const KEYS=["main","test1_geometry"]
const FORMAL={"main":"res://scenes/main.tscn","test1_geometry":"res://scenes/playable/test1_geometry.tscn"}
const CANDIDATE={"main":"res://scenes/unified_edit/playable/main.tscn","test1_geometry":"res://scenes/unified_edit/playable/test1_geometry.tscn"}

static func family(path: String, key: String) -> String:
	if FORMAL.get(key,"")==path and not path.is_empty():return "formal"
	if CANDIDATE.get(key,"")==path and not path.is_empty():return "candidate"
	return ""

static func scene_path(group: String, key: String) -> String:
	if group=="formal":return FORMAL.get(key,"")
	if group=="candidate":return CANDIDATE.get(key,"")
	return ""
