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

# ---- 单位解锁系统 ----
var unlocked_units: Array[String] = []
var unlock_config: Dictionary = {}

# ---- 道具解锁系统 ----
var item_unlock_config: Dictionary = {}
var item_unlocked_items: Array[String] = []

# ---- 已解锁道具列表（与存档同步） ----
var unlocked_items: Array[String] = []

# ---- 游戏状态标志 ----
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
var current_battle_turn: int = 0   # 单局战斗回合计数
var _last_increment_time: float = 0.0   # 上次递增时间戳（秒）

var pending_save_slot: int = -1   # 用于新建存档时记录槽位

# 地图缓存
var current_map_level_data: MapLevelData = null
var current_map_day: int = -1

# ---- 遗物解锁系统 ----
var unlocked_relics: Array[String] = []

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
	_load_unlock_config()
	_load_item_unlock_config()
	_load_relic_unlock_config()

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

func reset_battle_turn():
	current_battle_turn = 0

func increment_battle_turn():
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_increment_time < 0.05:   # 50ms 内的重复调用视为无效
		print("忽略重复回合递增")
		return
	_last_increment_time = now
	current_battle_turn += 1
	print("回合计数递增: ", current_battle_turn)

# ============================================================
#  单位解锁系统
# ============================================================
func _load_unlock_config():
	var path = "res://content/data/unit_unlock.json"
	if not FileAccess.file_exists(path):
		unlock_config = { "default_unlocked": ["剑士", "枪兵"] }
		var arr: Array[String] = []
		for item in unlock_config["default_unlocked"]:
			if item is String:
				arr.append(item)
		unlocked_units = arr
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)

	if data and data is Dictionary:
		unlock_config = data
		var raw = data.get("default_unlocked", ["剑士", "枪兵"])
		var arr: Array[String] = []
		for item in raw:
			if item is String:
				arr.append(item)
		unlocked_units = arr
	else:
		var arr: Array[String] = ["剑士", "枪兵"]
		unlocked_units = arr

func is_unit_unlocked(unit_name: String) -> bool:
	return unit_name in unlocked_units

func unlock_unit(unit_name: String):
	if unit_name not in unlocked_units:
		unlocked_units.append(unit_name)
		print("单位解锁：", unit_name)

func get_unlocked_units() -> Array[String]:
	return unlocked_units.duplicate()

# ============================================================
#  道具解锁系统
# ============================================================
func _load_item_unlock_config():
	var path = "res://content/data/item_unlock.json"
	var raw_items = []  # 用于存储默认解锁道具ID的原始数组
	if not FileAccess.file_exists(path):
		raw_items = ["iron_sword", "steel_spear", "battle_axe", "longbow", "healing_staff", "fire_spellbook", "wooden_shield"]
	else:
		var file = FileAccess.open(path, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		var data = JSON.parse_string(content)
		if data and data is Dictionary:
			raw_items = data.get("default_unlocked", [])
		else:
			raw_items = ["iron_sword", "steel_spear", "battle_axe", "longbow", "healing_staff", "fire_spellbook", "wooden_shield"]
	
	# 显式转换为 Array[String]
	var arr: Array[String] = []
	for item in raw_items:
		if item is String:
			arr.append(item)
	item_unlocked_items = arr
	
	# 将默认解锁道具加入全局解锁列表
	for item_id in item_unlocked_items:
		if item_id not in unlocked_items:
			unlocked_items.append(item_id)
	print("默认解锁道具已加载：", item_unlocked_items)

func is_item_unlocked(item_id: String) -> bool:
	return item_id in unlocked_items

func unlock_item(item_id: String):
	if item_id not in unlocked_items:
		unlocked_items.append(item_id)
		print("道具解锁：", item_id)

func get_unlocked_items() -> Array[String]:
	return unlocked_items.duplicate()

# ============================================================
#  确认对话框
# ============================================================
func show_confirm(parent: Node, message: String, confirm_text: String = "确定", cancel_text: String = "取消", confirm_cb: Callable = Callable(), cancel_cb: Callable = Callable(), show_cancel: bool = true):
	print("show_confirm 被调用，加载 ConfirmUI")
	var ui = load("res://content/scenes/ui/ConfirmUI.tscn")
	if not ui:
		print("错误：ConfirmUI.tscn 未找到")
		return
	var instance = ui.instantiate()
	print("ConfirmUI 实例化成功")
	parent.add_child(instance)
	instance.show_confirm(message, confirm_text, cancel_text, confirm_cb, cancel_cb, show_cancel)
	print("show_confirm 完成")

func _load_relic_unlock_config():
	var path = "res://content/data/relic_unlock.json"
	if not FileAccess.file_exists(path):
		print("遗物解锁文件不存在，使用空列表")
		unlocked_relics = []
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data and data is Dictionary:
		var raw = data.get("default_unlocked", [])
		var arr: Array[String] = []
		for item in raw:
			if item is String:
				arr.append(item)
		unlocked_relics = arr
		print("加载遗物解锁配置，数量：", unlocked_relics.size())
	else:
		unlocked_relics = []

# ---- 遗物解锁系统（委托给 RelicManager） ----
func is_relic_unlocked(relic_id: String) -> bool:
	return RelicManager.is_relic_unlocked(relic_id)

func unlock_relic(relic_id: String):
	RelicManager.unlock_relic(relic_id)

func get_unlocked_relics() -> Array:
	return RelicManager.get_unlocked_relics()
