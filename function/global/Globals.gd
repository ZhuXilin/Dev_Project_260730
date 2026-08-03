extends Node

# ---- 基准分辨率 ----
const BASE_WIDTH : int = 320
const BASE_HEIGHT : int = 240
const DEFAULT_SCALE : int = 2

# ---- 着色器目标颜色（固定） ----
const TARGET_COLOR_1 = Color(0.1216, 0.2196, 0.9373)
const TARGET_COLOR_2 = Color(1.0, 0.7490, 0.6863)

# ---- 队伍颜色映射 ----
const TEAM_COLORS = {
	0: { "primary": Color(0.1216, 0.2196, 0.9373), "secondary": Color(1.0, 0.7490, 0.6863) },
	1: { "primary": Color(0.8784, 0.0, 0.3725),   "secondary": Color(1.0, 0.6549, 0.7529) }
}

# ---- 灰色状态颜色 ----
const GRAY_COLORS = {
	"primary": Color(0.4980, 0.0431, 0.0),
	"secondary": Color(1.0, 0.6078, 0.2314)
}

# ---- 全局音量 (0.0 ~ 1.0) ----
var music_volume : float = 0.2
var sound_volume : float = 0.2

# ---- 游戏速度偏移量（-2 ~ 4，0 为 1 倍速） ----
var game_speed : int = 0

# ---- 游戏状态标志 ----
var current_map_data : MapData = null
var is_fading : bool = false
var is_performing_action : bool = false
var is_transitioning : bool = false
var is_dialogue_active : bool = false
var is_item_menu_active : bool = false
var is_item_get_popup_active : bool = false
var is_equip_menu_active : bool = false
var is_weapon_select_active : bool = false
var is_item_action_panel_open: bool = false
var suppress_sound: bool = false
var is_map_mode: bool = false
var current_map_node_id: String = ""
var map_node_states: Dictionary = {}  # key: node_id, value: { "visited": bool, "completed": bool }
var is_non_combat_mode: bool = false

# 地图缓存
var current_map_level_data: MapLevelData = null
var current_map_day: int = -1

# ---- 默认道具（游戏启动时加载） ----
var default_items = {
	"potion": 3,
	"antidote": 2,
	"bomb": 1,
	"wooden_shield": 1,
}

# ============================================================
#  生命周期
# ============================================================
func _ready():
	_set_default_window()
	_apply_game_speed()

# ============================================================
#  窗口管理
# ============================================================
func _set_default_window():
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		print("当前为全屏模式，保留全屏设置")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var width = BASE_WIDTH * DEFAULT_SCALE
	var height = BASE_HEIGHT * DEFAULT_SCALE
	DisplayServer.window_set_size(Vector2i(width, height))
	print("默认窗口尺寸已设置为: ", width, "x", height, " (", DEFAULT_SCALE, "倍)")

# ============================================================
#  游戏速度控制（全局键盘上下键调节）
# ============================================================
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		var step = 0
		if event.keycode == KEY_UP:
			step = 1
		elif event.keycode == KEY_DOWN:
			step = -1
		if step != 0:
			set_game_speed(game_speed + step)
			get_viewport().set_input_as_handled()

# 将速度偏移量 (-2..4) 转换为实际 Engine.time_scale
func get_time_scale(speed_val: int) -> float:
	if speed_val >= 0:
		return 1.0 + float(speed_val)          # 0->1, 1->2, 2->3, 3->4, 4->5
	else:
		return 1.0 / (1.0 - float(speed_val))  # -1->0.5, -2->0.333

func _apply_game_speed():
	Engine.time_scale = get_time_scale(game_speed)
	print("游戏速度设置为: ", Engine.time_scale, "x (偏移量: ", game_speed, ")")

func set_game_speed(new_val: int):
	var clamped = clamp(new_val, -2, 4)
	if game_speed == clamped:
		return
	game_speed = clamped
	_apply_game_speed()
	SignalBus.speed_changed.emit(game_speed)

# ============================================================
#  游戏状态重置（供关卡切换调用）
# ============================================================
func reset_all_game_state():
	InputManager.selected_unit = null
	InputManager.interaction_phase = "idle"
	InputManager.current_highlight_cells = {}
	InputManager.attackable_targets = []
	
	TurnManager.all_acted = false
	TurnManager.is_moving = false
	TurnManager.is_ai_moving = false
	TurnManager.clear_ai_state()
	TurnManager.last_player_unit = null
	TurnManager.current_turn_team = 0
	TurnManager.is_game_over = false
	
	UnitManager.clear_all_units()
	
	print("所有游戏状态已重置（保留地图进度）")

# 实例方法（非静态），可直接通过 Globals.get_team_color() 调用
func get_team_color(team_id: int, primary: bool = true) -> Color:
	var colors = TEAM_COLORS.get(team_id, TEAM_COLORS[0])
	return colors["primary"] if primary else colors["secondary"]

func get_gray_color(primary: bool = true) -> Color:
	return GRAY_COLORS["primary"] if primary else GRAY_COLORS["secondary"]
