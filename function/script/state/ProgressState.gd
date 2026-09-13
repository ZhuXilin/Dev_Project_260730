class_name ProgressState
extends RefCounted

# ---- 天数 / 节点 ----
var current_day : int = 1
var current_map_index : int = 0
var visited_nodes : Dictionary = {}
var current_node_key : String = ""
var is_map_mode : bool = false
var resume_node_id : String = ""
var last_selected_node_type : int = -1
var should_advance_day : bool = false

# ---- 地图缓存 / 快照 ----
var cached_map_level_data : MapLevelData = null
var cached_day : int = -1
var current_map_data : MapData = null
var map_snapshot : Dictionary = {}

# ---- 中断状态 ----
var interrupt_state : int = 0   # GameState.InterruptState 的值
var battlefield_data : Dictionary = {}

func reset_progress():
	visited_nodes.clear()
	current_day = 1
	cached_map_level_data = null
	cached_day = -1
	resume_node_id = ""
	should_advance_day = false
	current_map_data = null
	last_selected_node_type = -1
	map_snapshot.clear()

func undo_battle_entry():
	current_node_key = ""
	should_advance_day = false
