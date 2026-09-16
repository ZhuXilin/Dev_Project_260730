extends Node

const BASE_WIDTH : int = 400
const BASE_HEIGHT : int = 240
const DEFAULT_SCALE : int = 2

const TARGET_COLOR_1 = Color(0.1216, 0.2196, 0.9373)
const TARGET_COLOR_2 = Color(1.0, 0.7490, 0.6863)

const TEAM_COLORS = {
	0: { "primary": Color(0.1216, 0.2196, 0.9373), "secondary": Color(1.0, 0.7490, 0.6863) },
	1: { "primary": Color(0.8784, 0.0, 0.3725),   "secondary": Color(1.0, 0.6549, 0.7529) }
}

const GRAY_COLORS = {
	"primary": Color(0.4980, 0.0431, 0.0),
	"secondary": Color(1.0, 0.6078, 0.2314)
}

var music_volume : float = 0.2
var sound_volume : float = 0.2
var game_speed : int = 0

var unlocked_units: Array = []
var unlock_config: Dictionary = {}

var item_unlock_config: Dictionary = {}
var item_unlocked_items: Array = []
var unlocked_items: Array = []

var unlocked_talents: Array = []

const REWARD_SUMMARY_PATH = Config.PATHS.REWARD_SUMMARY_UI
const REWARD_SUMMARY_NODE_NAME = "RewardSummaryUI_Instance"
var _reward_summary_instance: CanvasLayer = null

var is_fading : bool = false
var is_performing_action : bool = false
var is_transitioning : bool = false
var is_dialogue_active : bool = false
var is_item_get_popup_active : bool = false
var is_equip_menu_active : bool = false
var suppress_sound: bool = false
var is_map_mode: bool = false
var is_non_combat_mode: bool = false
var current_battle_turn: int = 0

var _last_increment_time: float = 0.0
var pending_save_slot: int = -1

var current_map_level_data: MapLevelData = null
var current_map_day: int = -1


func _ready():
	_set_default_window()
	_apply_game_speed()
	_load_unlock_config()
	_load_item_unlock_config()
	_load_talent_unlock_config()


# ============================================================
#  窗口 / 速度
# ============================================================
func _set_default_window():
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(BASE_WIDTH * DEFAULT_SCALE, BASE_HEIGHT * DEFAULT_SCALE))

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

func get_time_scale(speed_val: int) -> float:
	if speed_val >= 0:
		return 1.0 + float(speed_val)
	return 1.0 / (1.0 - float(speed_val))

func _apply_game_speed():
	Engine.time_scale = get_time_scale(game_speed)

func set_game_speed(new_val: int):
	var clamped = clamp(new_val, -2, 4)
	if game_speed == clamped:
		return
	game_speed = clamped
	_apply_game_speed()
	SignalBus.speed_changed.emit(game_speed)

# ============================================================
#  游戏状态重置
# ============================================================
func reset_all_game_state():
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}

	TurnManager.all_acted = false
	TurnManager.is_moving = false
	TurnManager.is_ai_moving = false
	TurnManager.clear_ai_state()
	TurnManager.last_player_unit = null
	TurnManager.current_turn_team = TurnManager.Team.PLAYER
	TurnManager.is_game_over = false

	UnitManager.clear_all_units()

func get_team_color(team_id: int, primary: bool = true) -> Color:
	var colors = TEAM_COLORS.get(team_id, TEAM_COLORS[0])
	return colors["primary"] if primary else colors["secondary"]

func get_gray_color(primary: bool = true) -> Color:
	return GRAY_COLORS["primary"] if primary else GRAY_COLORS["secondary"]

func reset_battle_turn():
	current_battle_turn = 0

func increment_battle_turn():
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_increment_time < 0.05:
		return
	_last_increment_time = now
	current_battle_turn += 1


# ============================================================
#  单位解锁
# ============================================================
func _load_unlock_config():
	var path = Config.PATHS.UNIT_UNLOCK
	var default_units = ["swordsman", "spearman", "axeman"]

	if not FileAccess.file_exists(path):
		unlock_config = { "default_unlocked": default_units }
		unlocked_units = default_units.duplicate()
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)

	if data and data is Dictionary:
		unlock_config = data
		var raw = data.get("default_unlocked", default_units)
		var arr: Array = []
		for item in raw:
			if item is String:
				arr.append(item)
		unlocked_units = arr
	else:
		unlock_config = { "default_unlocked": default_units }
		unlocked_units = default_units.duplicate()

func is_unit_unlocked(unit_name: String) -> bool:
	return unit_name in unlocked_units

func unlock_unit(unit_name: String):
	if unit_name not in unlocked_units:
		unlocked_units.append(unit_name)

func get_unlocked_units() -> Array:
	return unlocked_units.duplicate()


# ============================================================
#  道具解锁
# ============================================================
func _load_item_unlock_config():
	var path = Config.PATHS.ITEM_UNLOCK
	var raw_items = []
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

	var arr: Array = []
	for item in raw_items:
		if item is String:
			arr.append(item)
	item_unlocked_items = arr

	for item_id in item_unlocked_items:
		if item_id not in unlocked_items:
			unlocked_items.append(item_id)

func is_item_unlocked(item_id: String) -> bool:
	return item_id in unlocked_items

func unlock_item(item_id: String):
	if item_id not in unlocked_items:
		unlocked_items.append(item_id)

func get_unlocked_items() -> Array:
	return unlocked_items.duplicate()


# ============================================================
#  特技解锁（方案 B：从 TalentManager 读取）
# ============================================================
func _load_talent_unlock_config():
	# 从 TalentManager 获取默认解锁列表
	var default_talents = TalentManager.get_default_unlocked_talents()
	unlocked_talents = default_talents.duplicate()


func is_talent_unlocked(talent_id: String) -> bool:
	return talent_id in unlocked_talents


func unlock_talent(talent_id: String):
	if talent_id not in unlocked_talents:
		unlocked_talents.append(talent_id)
		print("词条解锁：", talent_id)


func get_unlocked_talents() -> Array:
	return unlocked_talents.duplicate()


func can_soul_unlock_talent(talent_id: String) -> bool:
	if talent_id in unlocked_talents:
		return false
	var cost = TalentManager.get_soul_cost(talent_id)
	if cost < 0:
		return false
	return GameState.soul >= cost


func get_talent_soul_cost(talent_id: String) -> int:
	return TalentManager.get_soul_cost(talent_id)


func soul_unlock_talent(talent_id: String) -> bool:
	if not can_soul_unlock_talent(talent_id):
		return false
	var cost = get_talent_soul_cost(talent_id)
	GameState.soul -= cost
	unlock_talent(talent_id)
	SaveManager.auto_save()
	return true


func is_talent_story_locked(talent_id: String) -> bool:
	if talent_id in unlocked_talents:
		return false
	var data = TalentManager.get_talent_data(talent_id)
	if not data:
		return false
	return data.unlock_type == "story"


# ============================================================
#  确认对话框
# ============================================================
func show_confirm(parent: Node, message: String, confirm_text: String = "确定", cancel_text: String = "取消", confirm_cb: Callable = Callable(), cancel_cb: Callable = Callable(), show_cancel: bool = true):
	for child in parent.get_children():
		if child is CanvasLayer:
			var script = child.get_script()
			if script and script.resource_path.ends_with("ConfirmUI.gd"):
				return
	var ui = load(Config.PATHS.CONFIRM_UI)
	if not ui:
		return
	var instance = ui.instantiate()
	parent.add_child(instance)
	instance.show_confirm(message, confirm_text, cancel_text, confirm_cb, cancel_cb, show_cancel)


# ============================================================
#  结算面板
# ============================================================
func get_reward_summary() -> CanvasLayer:
	if _reward_summary_instance != null and is_instance_valid(_reward_summary_instance):
		return _reward_summary_instance

	var root = get_tree().root
	var existing = root.get_node_or_null(REWARD_SUMMARY_NODE_NAME)
	if existing:
		_reward_summary_instance = existing
		return existing

	var scene = load(REWARD_SUMMARY_PATH)
	if not scene:
		return null
	var inst = scene.instantiate()
	inst.name = REWARD_SUMMARY_NODE_NAME
	root.add_child(inst)
	_reward_summary_instance = inst
	return inst


# ============================================================
#  遗物转发
# ============================================================
func is_relic_unlocked(relic_id: String) -> bool:
	return RelicManager.is_relic_unlocked(relic_id)

func unlock_relic(relic_id: String):
	RelicManager.unlock_relic(relic_id)

func get_unlocked_relics() -> Array:
	return RelicManager.get_unlocked_relics()


# ============================================================
#  本轮结算
# ============================================================
func show_cycle_reward() -> void:
	MusicManager.play_defeat_music()

	var effective_soul = GameState.soul + GameState.temp_soul
	var earned_soul = max(0, effective_soul - GameState.cycle_start_soul)

	var earned_materials = {}
	var order = ["粗铁", "精钢", "秘银", "龙鳞"]
	for key in order:
		var before = GameState.cycle_start_materials.get(key, 0)
		var now = GameState.materials.get(key, 0)
		var earned = now - before
		if earned > 0:
			earned_materials[key] = earned

	var reward_items: Array = []
	for mat_name in order:
		if not earned_materials.has(mat_name):
			continue
		var count = earned_materials[mat_name]
		if count <= 0:
			continue
		var data = ItemData.new()
		data.id = "material_" + mat_name
		data.name = mat_name + " x" + str(count)
		data.description = ""
		reward_items.append(data)

	var summary = get_reward_summary()
	if not summary:
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	summary.setup_reward(0, earned_soul, reward_items, true, "本轮结算")
	summary.open()
	await summary.confirmed
	summary.close()
