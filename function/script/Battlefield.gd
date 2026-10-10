extends Node2D
class_name Battlefield

const BOSS_NODE_TYPE = 6

@export var map_data : MapData = null
@export var transition_delay_before_fade : float = 1.0
@export var transition_delay_after_fade : float = 1.0

# ---- 节点引用 ----
@onready var victory_panel : Panel = $VictoryLayer/VictoryPanel
@onready var victory_label : Label = $VictoryLayer/VictoryPanel/VictoryLabel
@onready var victory_button : Button = $VictoryLayer/VictoryPanel/VictoryButton
@onready var turn_overlay : ColorRect = $TurnLayer/TurnRect
@onready var cursor_layer : CanvasLayer = $CursorLayer
@onready var cursor : TextureRect = $CursorLayer/Cursor
@onready var highlight_manager : HighlightManager = $HighlightManager
@onready var movement_animator : MovementAnimator = $MovementAnimator
@onready var ui_manager : UIManager = $UIManager
@onready var turnlayer_manager : TurnLayerManager = $TurnLayerManager
@onready var camera_controller : CameraController = $Camera2D
@onready var menu_blocker : ColorRect = $MenuBlocker
@onready var info_panel : PanelContainer = $Info/InfoPanel
@onready var info_text_label : Label = $Info/InfoPanel/InfoTextLabel

# ---- 设置栏 ----
@onready var setting_panel : PanelContainer = $SettingBar/SettingPanel
@onready var back_camp_btn : Button = $SettingBar/SettingPanel/SettingContainer/BackCampBtn
@onready var back_to_menu_btn : Button = $SettingBar/SettingPanel/SettingContainer/BackToMenuBtn
@onready var setting_btn : Button = $SettingBar/SettingPanel/SettingContainer/SettingBtn
@onready var team_view_btn : Button = $SettingBar/SettingPanel/SettingContainer/TeamViewBtn
@onready var item_list_btn : Button = $SettingBar/SettingPanel/SettingContainer/ItemListBtn
@onready var relic_view_btn : Button = $SettingBar/SettingPanel/SettingContainer/RelicViewBtn

@onready var team_view_panel : PanelContainer = $TeamViewLayer/TeamViewPanel
@onready var team_view_container : VBoxContainer = $TeamViewLayer/TeamViewPanel/TeamViewContainer

@onready var item_list_panel : PanelContainer = $ItemListLayer/ItemListPanel
@onready var item_list_container : VBoxContainer = $ItemListLayer/ItemListPanel/ItemListContainer

@onready var setting_menu_panel : Panel = $SettingMenuLayer/SettingMenuPanel

# ---- HUD ----
@onready var speed_indicator : Label = $HUD/SpeedIndicator
@onready var turn_count_label : Label = $HUD/TurnCountIndicator
@onready var hint_label : Label = $HUD/HintLabel
@onready var relic_icon_container = $HUD/RelicIconContainer

const PERFORMANCE_DURATION : float = 0.5
const ItemGetPopupScene = preload(Config.PATHS.ITEM_GET_POPUP)

# ---- 拆分模块 ----
var _map_loader : MapLoader = null
var _non_combat_handler : NonCombatHandler = null
var _function_handler : FunctionHandler = null
var _cursor_controller : CursorController = null
var _panel_manager : PanelManager = null
var _ui_binder : UIBinder = null
var _turn_controller : TurnController = null
var _victory_handler : VictoryHandler = null
var _drag_move_controller : DragMoveController = null

var _damage_popup_layer : CanvasLayer = null

# ---- 状态 ----
var map_grid_size : Vector2i = MapConst.DEFAULT_MAP_SIZE
var _initialized : bool = false
var _battle_start_event_id : String = ""
var map_functions : Dictionary = {}
var is_non_combat_mode: bool = false
var non_combat_back_button: Button = null
var current_node_type: int = MapNode.NodeType.NORMAL
var _victory_processed: bool = false
var _is_reward_ui_active: bool = false

# ---- 提示条状态 ----
var _hint_override_text : String = ""
var _hint_override_until : float = 0.0

var _marked_targets : Dictionary = {}

func _ready():
	TurnManager.set_battle_ready(false)

	if victory_panel:
		victory_panel.visible = false
		PanelRevealer.force_hide(victory_panel)

	_victory_processed = false
	_is_reward_ui_active = false

	# 节点检查
	var node_list = {
		"victory_panel": victory_panel,
		"turn_overlay": turn_overlay,
		"cursor": cursor,
		"highlight_manager": highlight_manager,
		"menu_blocker": menu_blocker,
		"info_panel": info_panel,
		"setting_panel": setting_panel,
		"hint_label": hint_label
	}
	for node_name in node_list:
		if not node_list[node_name]:
			print("警告：节点 '", node_name, "' 未找到！")

	# 模块初始化
	_cursor_controller = CursorController.new(self)
	add_child(_cursor_controller)
	_panel_manager = PanelManager.new(self)
	add_child(_panel_manager)
	_panel_manager.init()

	_map_loader = MapLoader.new(self)
	_non_combat_handler = NonCombatHandler.new(self)
	add_child(_non_combat_handler)
	_function_handler = FunctionHandler.new(self)
	add_child(_function_handler)

	_turn_controller = TurnController.new(self)
	add_child(_turn_controller)
	_victory_handler = VictoryHandler.new(self)
	add_child(_victory_handler)

	_ui_binder = UIBinder.new(self)
	add_child(_ui_binder)

	_drag_move_controller = DragMoveController.new(self)
	add_child(_drag_move_controller)
	_drag_move_controller.setup()

	_damage_popup_layer = CanvasLayer.new()
	_damage_popup_layer.name = "DamagePopupLayer"
	_damage_popup_layer.layer = 0
	add_child(_damage_popup_layer)

	# 单位信号
	if not UnitManager.unit_removed.is_connected(_on_unit_removed_death):
		UnitManager.unit_removed.connect(_on_unit_removed_death)
	if not UnitManager.unit_removed.is_connected(_on_unit_removed_for_vengeance):
		UnitManager.unit_removed.connect(_on_unit_removed_for_vengeance)

	if hint_label:
		hint_label.text = "中键结束回合"

	if _initialized:
		return
	_initialized = true
	_cursor_controller.init_cursor()

	team_view_panel.visible = false
	item_list_panel.visible = false
	setting_menu_panel.visible = false

	if victory_panel:
		victory_panel.visible = false

	_ui_binder.bind_all()

	if turn_overlay:
		turn_overlay.modulate = Color(1, 1, 1, 0)
		Globals.is_fading = false

	# 地图加载
	if GameState.current_map_data:
		var map_to_load = GameState.current_map_data
		if not map_to_load.scene:
			_map_loader.load_default_map()
		else:
			_map_loader.load_map(map_to_load)
	else:
		_map_loader.load_default_map()

	if not map_data:
		var map_pixel_size = Vector2(map_grid_size.x * MapConst.CELL_SIZE, map_grid_size.y * MapConst.CELL_SIZE)
		if camera_controller:
			camera_controller.set_map_boundary(Rect2(Vector2.ZERO, map_pixel_size))

	if camera_controller:
		camera_controller.set_grid_size(MapConst.CELL_SIZE)
		var viewport_size = get_viewport().get_visible_rect().size
		camera_controller.set_edge_scroll_margin(viewport_size.x * 0.16)

	if info_panel:
		info_panel.visible = false
	if setting_panel:
		setting_panel.visible = false

	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}

	TurnManager.all_acted = false
	TurnManager.is_moving = false
	TurnManager.is_ai_moving = false
	TurnManager.clear_ai_state()
	TurnManager.last_player_unit = null
	TurnManager.current_turn_team = TurnManager.Team.PLAYER

	if highlight_manager:
		highlight_manager.clear_highlight()
	_cursor_controller.clear_attack_indicator()

	if menu_blocker:
		menu_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		menu_blocker.visible = false
		if not menu_blocker.gui_input.is_connected(_on_menu_blocker_clicked):
			menu_blocker.gui_input.connect(_on_menu_blocker_clicked)
		menu_blocker.size = Vector2(map_grid_size.x * MapConst.CELL_SIZE, map_grid_size.y * MapConst.CELL_SIZE)
		menu_blocker.position = Vector2.ZERO
		menu_blocker.z_index = UIConst.MENU_BLOCKER_Z_INDEX

	# 非战斗/战斗分支
	var is_non_combat = GameState.current_map_data and GameState.current_map_data.node_type in [
		MapNode.NodeType.SHOP, MapNode.NodeType.TREASURE,
		MapNode.NodeType.FORGE, MapNode.NodeType.CHAPEL,
	]

	if is_non_combat:
		await _non_combat_handler.setup_non_combat_mode()
		await get_tree().process_frame

		if back_camp_btn:
			for conn in back_camp_btn.pressed.get_connections():
				back_camp_btn.pressed.disconnect(conn.callable)
			back_camp_btn.pressed.connect(_on_back_camp_pressed)
			back_camp_btn.text = "回到营地"

		if back_to_menu_btn:
			for conn in back_to_menu_btn.pressed.get_connections():
				back_to_menu_btn.pressed.disconnect(conn.callable)
			back_to_menu_btn.pressed.connect(_on_back_to_menu_pressed)
			back_to_menu_btn.text = "中断游戏"

		TurnManager.start_turn(TurnManager.Team.PLAYER)
		_panel_manager.update_relic_icons()
		return

	if _battle_start_event_id != "":
		var music = MusicManager.config.battle_start_dialogue_music if MusicManager.config else null
		if EventManager and EventManager.has_event(_battle_start_event_id):
			await EventManager.trigger_event(_battle_start_event_id, null, music)
		else:
			if DialogueManager.has_dialogue(_battle_start_event_id):
				DialogueManager.start_dialogue(_battle_start_event_id, music)
				await DialogueManager.dialogue_finished

	if MusicManager:
		MusicManager.stop_music()
		MusicManager._saved_stream = null
		MusicManager._saved_position = 0.0

	await get_tree().process_frame
	TurnManager.start_turn(TurnManager.Team.PLAYER)

	if back_camp_btn:
		for conn in back_camp_btn.pressed.get_connections():
			back_camp_btn.pressed.disconnect(conn.callable)
		back_camp_btn.pressed.connect(_on_back_camp_pressed)
		back_camp_btn.text = "回到营地"

	if back_to_menu_btn:
		for conn in back_to_menu_btn.pressed.get_connections():
			back_to_menu_btn.pressed.disconnect(conn.callable)
		back_to_menu_btn.pressed.connect(_on_back_to_menu_pressed)
		back_to_menu_btn.text = "中断游戏"

	InputManager.ui_manager = ui_manager

	_panel_manager.update_relic_icons()

	_victory_processed = false
	_is_reward_ui_active = false

	if not is_non_combat_mode:
		var alive_player : int = 0
		for u in UnitManager.unit_list:
			if u.unit_stats.team_id == 0 and u.hit_points > 0:
				alive_player += 1
		if alive_player == 0:
			TurnManager.is_game_over = true
			await get_tree().process_frame
			SignalBus.request_show_victory.emit(1)
			return

	_turn_controller.apply_team_buffs()

	var is_boss : bool = GameState.current_map_data and GameState.current_map_data.node_type == MapNode.NodeType.BOSS
	BossMechanicManager.setup_for_node(current_node_type, is_boss)

	# 预热面板
	if setting_panel:
		PanelRevealer.force_hide(setting_panel)
	if setting_menu_panel:
		PanelRevealer.force_hide(setting_menu_panel)
	if team_view_panel:
		PanelRevealer.force_hide(team_view_panel)
	if item_list_panel:
		PanelRevealer.force_hide(item_list_panel)
	if victory_panel:
		PanelRevealer.force_hide(victory_panel)
		
	_marked_targets.clear()
	print("Battlefield _ready 完成")


# ============================================================
#  提示条
# ============================================================
func _set_hint_override(text : String, duration : float = 1.0):
	_hint_override_text = text
	_hint_override_until = Time.get_ticks_msec() / 1000.0 + duration


func _update_hint_label():
	if hint_label == null:
		return

	var now := Time.get_ticks_msec() / 1000.0

	# 优先级 1：临时覆盖
	if now < _hint_override_until and _hint_override_text != "":
		hint_label.text = _hint_override_text
		return

	# 优先级 2：拖拽中
	if _drag_move_controller and _drag_move_controller.is_dragging():
		var hint := _drag_move_controller.get_drag_hint()
		if hint == "":
			hint = "释放左键移动 / 攻击"
		hint_label.text = hint
		return

	# 优先级 3：有选中单位
	var sel = InputManager.selected_unit
	if sel != null and is_instance_valid(sel) and sel.hit_points > 0:
		if sel.unit_stats.team_id != 0:
			# ★ 敌方
			hint_label.text = "不可操作单位"
		else:
			hint_label.text = "按住左键拖拽单位"
		return

	# 优先级 4：空闲
	hint_label.text = "中键结束回合"


# ============================================================
#  选中 / 取消选中
# ============================================================
func select_unit(unit: Unit):
	if not is_instance_valid(unit):
		return

	InputManager.selected_unit = unit
	InputManager.interaction_phase = InputManager.Phase.IDLE

	_on_request_show_info(unit)
	_show_unit_ranges(unit)
	SoundManager.play_select_sound()


func deselect_unit():
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	SignalBus.request_hide_info.emit()
	SignalBus.request_clear_highlight.emit()


# ============================================================
#  范围显示（威胁版，敌我统一）
# ============================================================
func _show_unit_ranges(unit: Unit):
	# 移动范围：我方用剩余移动力，敌方用总移动力
	var move_range : int = unit.remaining_move
	if unit.unit_stats.team_id != 0:
		move_range = unit.unit_stats.move_range

	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, move_range, unit)

	var weapon = unit.get_weapon_data()
	if weapon == null:
		highlight_manager.clear_highlight()
		highlight_manager.show_move_highlight(reachable, MapConst.HIGHLIGHT_MOVE, -1, true)
		return

	var max_range : int = weapon.attack_range
	var min_range : int = weapon.min_attack_range
	var is_healer : bool = (unit.get_weapon_type() == "staff")

	# 威胁范围：从所有可达位置出发
	var threat_cells : Dictionary = {}
	for move_cell in reachable.keys():
		for x in range(-max_range, max_range + 1):
			for y in range(-max_range, max_range + 1):
				var dist = abs(x) + abs(y)
				if dist < min_range or dist > max_range:
					continue
				var c = move_cell + Vector2i(x, y)
				if c.x < 0 or c.x >= TerrainManager.grid_size.x:
					continue
				if c.y < 0 or c.y >= TerrainManager.grid_size.y:
					continue

				# ★ 剔除墙（IMPASSABLE_ALL）
				var tt : int = TerrainManager.get_terrain(c)
				if tt == TerrainManager.TerrainType.IMPASSABLE_ALL:
					continue

				# 排除已在移动范围里的格
				if reachable.has(c):
					continue
				# 排除不该打的单位格
				var occ = UnitManager.get_unit_at_cell(c)
				if occ != null and not UnitManager.is_attack_target_of(unit, occ):
					continue
				threat_cells[c] = true

	var color = MapConst.HIGHLIGHT_HEAL if is_healer else MapConst.HIGHLIGHT_ATTACK
	highlight_manager.clear_highlight()
	highlight_manager.show_enemy_preview(reachable, threat_cells, color)


# ============================================================
#  信号回调
# ============================================================
func _on_unit_removed_for_vengeance(unit: Unit, team: int):
	if team != 0: return
	if not is_instance_valid(unit): return
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.unit_stats.team_id != 0: continue
		if u == unit: continue
		if u.vengeance_triggered: continue
		var inst = u.get_talent_instance("vengeance")
		if inst and inst.is_active:
			u.buff_attack_percent += 0.30
			u.vengeance_triggered = true


func _on_unit_removed_death(unit: Unit, team: int):
	if team != 0: return
	if not is_instance_valid(unit): return
	if unit.hit_points > 0: return
	for ud in GameState.party:
		if ud.unit_name == unit.unit_stats.unit_name and ud.display_name == unit.unit_stats.display_name:
			ud.is_dead = true
			ud.hit_points = 0
			break


func _exit_tree():
	Globals.is_fading = false
	Globals.is_transitioning = false
	Globals.is_performing_action = false
	Globals.is_dialogue_active = false
	Globals.is_item_get_popup_active = false
	Globals.is_equip_menu_active = false

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if cursor:
		cursor.visible = false
	if _cursor_controller:
		_cursor_controller.cleanup()

	if InputManager.ui_manager == ui_manager:
		InputManager.ui_manager = null
	if InputManager.selected_unit != null:
		InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	InputManager.pending_attack_cells = {}
	InputManager.current_move_attack_targets = {}
	
	if _turn_controller:
		_turn_controller.force_unlock()
		
	if TurnManager:
		TurnManager.set_battle_ready(false)


# ============================================================
#  主循环
# ============================================================
func _process(_delta):
	_cursor_controller.update_cursor_and_mouse()
	_update_hint_label()

	var should_pause = (
		victory_panel.visible or
		info_panel.visible or
		TurnManager.is_moving or
		TurnManager.is_ai_moving or
		TurnManager.current_turn_team == TurnManager.Team.ENEMY or
		Globals.is_fading or
		Globals.is_transitioning or
		Globals.is_performing_action or
		Globals.is_dialogue_active or
		Globals.is_item_get_popup_active or
		camera_controller._is_smooth_moving
	)
	camera_controller.set_paused(should_pause)


# ============================================================
#  移动信号
# ============================================================
func _on_instant_move(unit: Unit, cell: Vector2i):
	if is_instance_valid(unit):
		unit.position = grid_to_world(cell)
		unit.grid_cell = cell
		unit.update_position(cell)


func _on_request_move_along_path(unit: Unit, path: Array):
	camera_controller.follow_unit(unit)
	movement_animator.play_movement(unit, path, grid_to_world)


func _on_ai_move_along_path(unit: Unit, path: Array):
	camera_controller.follow_unit(unit)
	movement_animator.play_ai_movement(unit, path, grid_to_world)


func _on_player_movement_finished(unit: Unit):
	_function_handler.clear_function_trigger(unit)
	TurnManager.on_movement_finished(unit)
	camera_controller.follow_mouse()
	SignalBus.request_clear_highlight.emit()


func _on_ai_movement_finished(unit: Unit):
	_function_handler.clear_function_trigger(unit)
	TurnManager.on_ai_movement_finished(unit)
	camera_controller.follow_mouse()
	SignalBus.request_clear_highlight.emit()


func _on_menu_blocker_clicked(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		InputManager.selected_unit = null
		InputManager.interaction_phase = InputManager.Phase.IDLE


# ============================================================
#  坐标换算
# ============================================================
func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * MapConst.CELL_SIZE + MapConst.CELL_SIZE / 2.0,
				   cell.y * MapConst.CELL_SIZE + MapConst.CELL_SIZE / 2.0)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / MapConst.CELL_SIZE), floor(world_pos.y / MapConst.CELL_SIZE))


# ============================================================
#  输入
# ============================================================
func _input(event: InputEvent):
	if TurnManager and not TurnManager.is_battle_ready():
		return

	if Globals.is_dialogue_active or Globals.is_item_get_popup_active:
		return

	# 拖拽优先
	if _drag_move_controller and _drag_move_controller.handle_input(event):
		return

	# 中键结束回合
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		if TurnManager.current_turn_team == TurnManager.Team.PLAYER and not Globals.is_fading and not Globals.is_transitioning and not Globals.is_dialogue_active:
			_end_player_turn()
			return

	if Globals.is_transitioning or Globals.is_fading:
		return

	# 滚轮
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if (setting_panel.visible or
				setting_menu_panel.visible or
				team_view_panel.visible or
				item_list_panel.visible or
				InputManager.interaction_phase == InputManager.Phase.DRAGGING_MOVE):
				return
			if TurnManager.is_game_over:
				return
			if TurnManager.current_turn_team == TurnManager.Team.PLAYER and not TurnManager.is_moving and not TurnManager.is_ai_moving and not Globals.is_performing_action:
				var direction = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				InputManager.handle_wheel(direction)
			return

	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return
	if TurnManager.all_acted:
		return
	if TurnManager.is_moving:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			InputManager.handle_input(event, map_grid_size, MapConst.CELL_SIZE)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_global_mouse_position()
			var clicked_cell = world_to_grid(mouse_pos)
			InputManager.handle_click(clicked_cell)
	else:
		InputManager.handle_input(event, map_grid_size, MapConst.CELL_SIZE)


# ============================================================
#  其他信号
# ============================================================
func _on_request_screen_shake(duration: float, intensity: float, direction: Vector2 = Vector2.ZERO):
	var shake_node = $Camera2D.get_node_or_null("ScreenShake") as ScreenShake
	if shake_node:
		shake_node.shake(duration, intensity, direction)


func _on_request_damage_popup(world_pos: Vector2, damage: int, is_crit: bool, is_miss: bool, is_heal: bool):
	if _damage_popup_layer == null:
		return
	var popup = preload(Config.PATHS.DAMAGE_POPUP_SCRIPT).new()
	_damage_popup_layer.add_child(popup)
	popup.setup(world_pos, damage, is_crit, is_miss, is_heal)


# ============================================================
#  InfoPanel（完整信息）
# ============================================================
func _on_request_show_info(unit: Unit):
	if unit == null:
		# 地形
		var mouse_pos = get_global_mouse_position()
		var t_cell = world_to_grid(mouse_pos)
		var t_type = TerrainManager.get_terrain(t_cell)
		var t_name = TerrainManager.get_terrain_name(t_type)
		var t_def = TerrainManager.TERRAIN_DATA[t_type]["def_bonus"]
		var t_mdef = TerrainManager.TERRAIN_DATA[t_type]["magic_defense_bonus"]
		var t_avoid = TerrainManager.TERRAIN_DATA[t_type]["avoid_bonus"]
		info_text_label.text = "地形: " + t_name \
			+ "\n防御+" + str(t_def) \
			+ " 魔防+" + str(t_mdef) \
			+ " 回避+" + str(t_avoid)
		_adjust_info_panel(info_text_label, info_panel, null)
		return

	if not is_instance_valid(unit):
		return

	var lines : Array = []

	# 名称 | 阵营 | 类型
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	var type_name = UnitDataManager.get_unit_type_display_name(unit.unit_stats.unit_name)
	lines.append(display_name + " | " + unit.unit_stats.faction + " | " + type_name)

	# HP
	lines.append("HP: " + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp))

	# 状态
	var status_str : String = ""
	if unit.hit_points <= 0:
		status_str = "【已阵亡】"
	elif unit.has_acted or not unit.can_act_this_turn:
		status_str = "【单位待机】"
	elif unit.has_attacked:
		status_str = "【已攻击】"
	else:
		status_str = "【可行动】"
	lines.append("状态: " + status_str)

	# 武器
	var weapon_data = unit.get_weapon_data()
	if weapon_data:
		var wname : String = weapon_data.name
		if unit.weapon_slot and unit.weapon_slot.upgrade_level > 0:
			wname += "+" + str(unit.weapon_slot.upgrade_level)
		lines.append("武器: " + wname)
		if weapon_data.base_attack > 0:
			lines.append("  攻击+" + str(weapon_data.base_attack))
		if not weapon_data.heal_effect.is_empty():
			lines.append("  治疗+" + str(weapon_data.heal_effect.get("base_heal", 0)))
		lines.append("  射程: " + str(weapon_data.min_attack_range) + "~" + str(weapon_data.attack_range))
	else:
		lines.append("武器: 无")

	# 防具
	var armor_slots = unit.get_armor_slots()
	var armor_lines : Array = []
	for i in range(armor_slots.size()):
		var inst = armor_slots[i]
		if inst:
			var data = ItemManager.get_item_data(inst.item_id)
			if data:
				armor_lines.append("  槽" + str(i+1) + ": " + data.name)
		else:
			armor_lines.append("  槽" + str(i+1) + ": （空）")
	if armor_lines.size() > 0:
		lines.append("防具:")
		lines.append_array(armor_lines)

	# 属性
	lines.append("力量 " + str(unit.unit_stats.strength) \
		+ " | 灵巧 " + str(unit.unit_stats.dexterity) \
		+ " | 智力 " + str(unit.unit_stats.intelligence))
	lines.append("信仰 " + str(unit.unit_stats.faith) \
		+ " | 感应 " + str(unit.unit_stats.arcane) \
		+ " | 移动 " + str(unit.unit_stats.move_range))

	# 词条
	var talent_names : Array = []
	for inst in unit.talent_slots:
		if inst and inst.is_active:
			var tdata = TalentManager.get_talent_data(inst.talent_id)
			if tdata:
				talent_names.append(tdata.display_name)
	if unit.advanced_talent_inst and unit.advanced_talent_inst.is_active:
		var adv_tdata = TalentManager.get_talent_data(unit.advanced_talent_inst.talent_id)
		if adv_tdata:
			talent_names.append("★" + adv_tdata.display_name)
	if talent_names.size() > 0:
		lines.append("词条: " + ", ".join(talent_names))

	# 地形
	var cell = unit.grid_cell
	var terrain_type = TerrainManager.get_terrain(cell)
	var terrain_name = TerrainManager.get_terrain_name(terrain_type)
	lines.append("地形: " + terrain_name)

	info_text_label.text = "\n".join(lines)
	_adjust_info_panel(info_text_label, info_panel, unit)


func _on_request_hide_info():
	PanelRevealer.hide_panel(info_panel)


# ============================================================
#  InfoPanel 位置 + 高度
# ============================================================
const INFO_PANEL_WIDTH : float = 72.0
const INFO_PANEL_MARGIN : float = 8.0

func _adjust_info_panel(label: Label, panel: PanelContainer, ref_unit: Unit = null):
	var vp_size := get_viewport().get_visible_rect().size

	# 位置：根据参考单位在屏幕左右
	if ref_unit != null and is_instance_valid(ref_unit):
		var xform := get_viewport().get_canvas_transform()
		var screen_x : float = (xform * ref_unit.global_position).x
		if screen_x < vp_size.x * 0.5:
			panel.offset_right = vp_size.x - INFO_PANEL_MARGIN
			panel.offset_left = panel.offset_right - INFO_PANEL_WIDTH
		else:
			panel.offset_left = INFO_PANEL_MARGIN
			panel.offset_right = panel.offset_left + INFO_PANEL_WIDTH
	else:
		panel.offset_right = vp_size.x - INFO_PANEL_MARGIN
		panel.offset_left = panel.offset_right - INFO_PANEL_WIDTH

	panel.offset_top = INFO_PANEL_MARGIN

	# 内容布局
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var panel_style = panel.get_theme_stylebox("panel")
	var margin_top = panel_style.get_margin(SIDE_TOP) if panel_style else 0.0
	var margin_bottom = panel_style.get_margin(SIDE_BOTTOM) if panel_style else 0.0
	var margin_left = panel_style.get_margin(SIDE_LEFT) if panel_style else 0.0
	var margin_right = panel_style.get_margin(SIDE_RIGHT) if panel_style else 0.0

	var panel_width = panel.offset_right - panel.offset_left - margin_left - margin_right
	label.size.x = panel_width

	var label_min_height = label.get_minimum_size().y
	var panel_height = label_min_height + margin_top + margin_bottom
	panel.offset_bottom = panel.offset_top + panel_height

	if not panel.visible:
		PanelRevealer.show_panel(panel)


# ============================================================
#  设置栏
# ============================================================
func _on_request_show_setting():
	PanelRevealer.show_panel(setting_panel)


func _on_request_hide_setting():
	PanelRevealer.hide_panel(setting_panel)
	PanelRevealer.hide_panel(team_view_panel)
	PanelRevealer.hide_panel(item_list_panel)
	PanelRevealer.hide_panel(setting_menu_panel)


func _on_speed_changed(new_speed: int):
	if speed_indicator == null: return
	if new_speed == 0:
		speed_indicator.visible = false
	else:
		speed_indicator.visible = true
		var prefix = "+" if new_speed > 0 else ""
		speed_indicator.text = prefix + str(new_speed) + "X"


func _on_show_enemy_preview(move_cells: Dictionary, attack_cells: Dictionary, attack_color: Color):
	highlight_manager.clear_highlight()
	highlight_manager.show_enemy_preview(move_cells, attack_cells, attack_color)


# ============================================================
#  结束回合
# ============================================================
func _end_player_turn():
	if TurnManager.is_game_over:
		return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return
	if Globals.is_transitioning or Globals.is_fading:
		return
	if _is_any_ui_active():
		return

	SignalBus.request_hide_info.emit()
	SignalBus.request_hide_setting.emit()
	SignalBus.request_clear_highlight.emit()

	var allies = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			allies.append(unit)
	for ally in allies:
		ally.can_act_this_turn = false
		ally.set_gray(true)

	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}

	TurnManager.start_turn(TurnManager.Team.ENEMY)


func _wait_for_ui_clear(timeout_ms: int = 5000) -> void:
	var start = Time.get_ticks_msec()
	while _is_any_ui_active():
		if not is_inside_tree():
			return
		if Time.get_ticks_msec() - start > timeout_ms:
			push_warning("Battlefield: 等待 UI 结束超时")
			return
		await get_tree().process_frame


func _is_any_ui_active() -> bool:
	return (
		Globals.is_dialogue_active or
		Globals.is_item_get_popup_active or
		Globals.is_fading or
		Globals.is_transitioning or
		Globals.is_performing_action
	)


func _on_back_camp_pressed():
	PanelRevealer.force_hide(setting_panel)
	GameState.show_abandon_confirmation(self)


func _on_back_to_menu_pressed():
	# 中断：直接回主菜单（不弹确认）
	var current_scene = get_tree().current_scene
	var scene_path : String = ""
	if current_scene:
		scene_path = current_scene.scene_file_path

	if scene_path.ends_with("Battlefield.tscn"):
		GameState.undo_battle_entry()
		GameState.interrupt_state = GameState.InterruptState.MAP
	else:
		GameState.interrupt_state = GameState.InterruptState.MAP

	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")


func _on_request_setting_right_click():
	if team_view_panel.visible:
		_panel_manager.on_team_view_btn_pressed()
		return
	if item_list_panel.visible:
		_panel_manager.on_item_list_btn_pressed()
		return
	if setting_menu_panel.visible:
		PanelRevealer.hide_panel(setting_menu_panel)
		return

	SignalBus.request_hide_setting.emit()
	SignalBus.request_hide_info.emit()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_empty_cell = Vector2i(-1, -1)
