extends Node2D
class_name Battlefield

const BOSS_NODE_TYPE = 6

@export var map_data : MapData = null
@export var transition_delay_before_fade : float = 1.0
@export var transition_delay_after_fade : float = 1.0

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
@onready var info_text_label : Label = $Info/InfoPanel/VBox/InfoTextLabel
@onready var soul_fire_bar : ProgressBar = $HUD/SoulFireHUD/SoulFireBar
@onready var soul_fire_label : Label = $HUD/SoulFireHUD/SoulFireLabel
@onready var soul_fire_state_label : Label = $HUD/SoulFireHUD/StateLabel


@onready var setting_panel : PanelContainer = $SettingBar/SettingPanel
@onready var back_camp_btn : Button = $SettingBar/SettingPanel/SettingContainer/BackCampBtn
@onready var back_to_menu_btn : Button = $SettingBar/SettingPanel/SettingContainer/BackToMenuBtn
@onready var setting_btn : Button = $SettingBar/SettingPanel/SettingContainer/SettingBtn
@onready var team_view_btn : Button = $SettingBar/SettingPanel/SettingContainer/TeamViewBtn

@onready var team_view_panel : PanelContainer = $TeamViewLayer/TeamViewPanel
@onready var team_view_container : VBoxContainer = $TeamViewLayer/TeamViewPanel/TeamViewContainer

@onready var setting_menu_panel : Panel = $SettingMenuLayer/SettingMenuPanel

@onready var speed_indicator : Label = $HUD/SpeedIndicator
@onready var turn_count_label : Label = $HUD/TurnCountIndicator
@onready var hint_label : Label = $HUD/HintLabel
@onready var relic_icon_container = $HUD/RelicIconContainer

const PERFORMANCE_DURATION : float = 0.5
const INFO_PANEL_WIDTH : float = 72.0
const INFO_PANEL_MARGIN : float = 8.0

const AVATAR_SIZE : float = 54.0
const AVATAR_GAP : float = 4.0

# ★ v4.6：伤害跳字队列参数
const POPUP_QUEUE_INTERVAL : float = 0.15
const POPUP_STACK_HEIGHT : float = 14.0
const POPUP_MAX_STACK : int = 3

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

# ★ v4.6：伤害跳字队列（同位置串行显示）
var _damage_popup_queue : Dictionary = {}
var _damage_popup_busy : Dictionary = {}

var map_grid_size : Vector2i = MapConst.DEFAULT_MAP_SIZE
var _initialized : bool = false
var map_functions : Dictionary = {}
var is_non_combat_mode: bool = false
var non_combat_back_button: Button = null
var current_node_type: int = MapNode.NodeType.NORMAL
var _victory_processed : bool = false
var _is_reward_ui_active : bool = false

var _hint_override_text : String = ""
var _hint_override_until : float = 0.0

var _marked_targets : Dictionary = {}
var _objective_banner : Label = null


func _ready():
	TurnManager.set_battle_ready(false)

	# ★ 新战斗开始 → 清除上次的 Boss 临时上限惩罚
	SoulFireManager.reset_boss_penalty()

	# ★ v4.6：进战斗时，从持久层同步魂火到战斗层
	# 保证"中途退出再进战斗"从战斗前的值开始，而不是上次残留值
	SoulFireManager.current = clampi(
		GameState.soul_fire_current, 0, SoulFireManager.get_max_carried())

	# 魂火 HUD 绑定
	if not SoulFireManager.soul_fire_changed.is_connected(_on_soul_fire_changed):
		SoulFireManager.soul_fire_changed.connect(_on_soul_fire_changed)
	_on_soul_fire_changed(SoulFireManager.current, SoulFireManager.get_max_carried())

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

	# ★ 提前计算 is_boss（两条路径都要用）
	var is_boss : bool = GameState.current_map_data and GameState.current_map_data.node_type == MapNode.NodeType.BOSS

	# 非战斗/战斗分支
	var is_non_combat = GameState.current_map_data and GameState.current_map_data.node_type in [
		MapNode.NodeType.TREASURE,
		MapNode.NodeType.FORGE,
		MapNode.NodeType.CHAPEL,
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

		# ★ 非战斗节点重置 Boss 机制和目标状态
		BossMechanicManager.setup_for_node(false)
		if ObjectiveManager:
			ObjectiveManager.setup_for_node(null)

		TurnManager.start_turn(TurnManager.Team.PLAYER)
		_panel_manager.update_relic_icons()
		return

	var battle_ctx: Dictionary = _build_battle_start_context()
	if StoryManager.trigger("battle_start", battle_ctx):
		await DialogueManager.dialogue_finished

	if MusicManager:
		MusicManager.stop_music()
		MusicManager._saved_stream = null
		MusicManager._saved_position = 0.0

	# Boss 机制设置必须在 start_turn 之前
	# 否则 start_turn 会调 on_player_turn_start() 用上一场的旧机制
	BossMechanicManager.setup_for_node(is_boss)

	# 胜利目标初始化
	if ObjectiveManager:
		ObjectiveManager.setup_for_node(GameState.current_map_data)

	# 波次初始化（先连接信号，再 setup）
	if WaveManager:
		_connect_wave_signals()
		WaveManager.setup_for_node(GameState.current_map_data, self)

	# 目标可视化 + 状态 HUD
	_render_objective_markers()
	_create_objective_status_label()

	await get_tree().process_frame
	TurnManager.start_turn(TurnManager.Team.PLAYER)

	# 显示目标 banner（延迟避开 turn overlay）
	if ObjectiveManager and not ObjectiveManager.is_annihilate():
		call_deferred("_deferred_show_objective_banner")

	# BOSS 战前显示 Boss 情报
	call_deferred("_deferred_show_boss_intel")

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
		var alive_enemy : int = 0
		for u in UnitManager.unit_list:
			if u.hit_points <= 0:
				continue
			if u.unit_stats.team_id == 0:
				alive_player += 1
			else:
				alive_enemy += 1
		if alive_player == 0:
			TurnManager.is_game_over = true
			await get_tree().process_frame
			SignalBus.request_show_victory.emit(1)
			return
		# ★ 敌人已全灭（GM 提前清场 / 布阵异常），直接胜利
		if alive_enemy == 0:
			TurnManager.is_game_over = true
			await get_tree().process_frame
			SignalBus.request_show_victory.emit(0)
			return

	_turn_controller.apply_team_buffs()

	if _victory_handler:
		_victory_handler.record_battle_start_hp()

	# 预热面板
	if setting_panel:
		PanelRevealer.force_hide(setting_panel)
	if setting_menu_panel:
		PanelRevealer.force_hide(setting_menu_panel)
	if team_view_panel:
		PanelRevealer.force_hide(team_view_panel)
	if victory_panel:
		PanelRevealer.force_hide(victory_panel)

	_marked_targets.clear()
	print("Battlefield _ready 完成")


func _build_battle_start_context() -> Dictionary:
	var md: MapData = GameState.current_map_data
	var node_type: int = md.node_type if md != null else MapNode.NodeType.NORMAL
	var is_boss: bool = (node_type == MapNode.NodeType.BOSS)
	var is_elite: bool = (node_type == MapNode.NodeType.ELITE)
	var is_start: bool = (node_type == MapNode.NodeType.START)

	var tags: Array = []
	for ud in GameState.party:
		if ud.is_dead:
			continue
		for t in ud.tags:
			if not (t in tags):
				tags.append(t)

	return {
		"node_type": node_type,
		"is_boss": is_boss,
		"is_elite": is_elite,
		"is_start": is_start,
		"current_day": GameState.current_day,
		"map_name": md.map_name if md != null else "",
		"tutorial_stage": GameState.tutorial_stage,
		"total_run_count": GameState.total_run_count,
		"team_tags": tags,
	}


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

	if now < _hint_override_until and _hint_override_text != "":
		hint_label.text = _hint_override_text
		return

	if _drag_move_controller and _drag_move_controller.is_dragging():
		var hint := _drag_move_controller.get_drag_hint()
		if hint == "":
			hint = "释放左键移动 / 攻击"
		hint_label.text = hint
		return

	var sel = InputManager.selected_unit
	if sel != null and is_instance_valid(sel) and sel.hit_points > 0:
		if sel.unit_stats.team_id != 0:
			hint_label.text = "不可操作单位"
		else:
			hint_label.text = "按住左键拖拽单位"
		return

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
#  范围显示（威胁版）
# ============================================================
func _show_unit_ranges(unit: Unit):
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

				var tt : int = TerrainManager.get_terrain(c)
				if tt == TerrainManager.TerrainType.IMPASSABLE_ALL:
					continue

				if reachable.has(c):
					continue
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

	if SoulFireManager:
		SoulFireManager.reset_boss_penalty()

	if SoulFireManager and SoulFireManager.soul_fire_changed.is_connected(_on_soul_fire_changed):
		SoulFireManager.soul_fire_changed.disconnect(_on_soul_fire_changed)

	if ObjectiveManager:
		ObjectiveManager.setup_for_node(null)

	if WaveManager:
		WaveManager.reset()
		_disconnect_wave_signals()


# ============================================================
#  主循环
# ============================================================
func _process(_delta):
	_cursor_controller.update_cursor_and_mouse()
	_update_hint_label()
	_refresh_objective_status()

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
		camera_controller.is_smooth_moving()
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

	# ★ 核心修改：全面拦截右键，交由 _on_request_setting_right_click 统一处理
	if team_view_panel.visible or setting_panel.visible or setting_menu_panel.visible:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_on_request_setting_right_click()
			get_viewport().set_input_as_handled()
		return

	if _drag_move_controller and _drag_move_controller.handle_input(event):
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		if TurnManager.current_turn_team == TurnManager.Team.PLAYER and not Globals.is_fading and not Globals.is_transitioning and not Globals.is_dialogue_active:
			_end_player_turn()
			return

	if Globals.is_transitioning or Globals.is_fading:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
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


# ★ v4.6：伤害跳字队列 —— 同位置串行 + 轻微错开
func _on_request_damage_popup(world_pos: Vector2, damage: int, is_crit: bool, is_miss: bool, is_heal: bool):
	if _damage_popup_layer == null:
		return
	# 用 4 像素容差做 key，避免同一格因浮点误差被当成两个位置
	var key := "%d_%d" % [int(world_pos.x / 4.0), int(world_pos.y / 4.0)]
	if not _damage_popup_queue.has(key):
		_damage_popup_queue[key] = []
	_damage_popup_queue[key].append({
		"world_pos": world_pos,
		"damage": damage,
		"is_crit": is_crit,
		"is_miss": is_miss,
		"is_heal": is_heal,
	})
	if _damage_popup_busy.get(key, false):
		return
	_damage_popup_busy[key] = true
	_process_popup_queue(key)


func _process_popup_queue(key: String) -> void:
	var queue : Array = _damage_popup_queue.get(key, [])
	var index : int = 0
	while queue.size() > 0:
		if not is_inside_tree():
			break
		var data : Dictionary = queue.pop_front()
		var popup = preload(Config.PATHS.DAMAGE_POPUP_SCRIPT).new()
		_damage_popup_layer.add_child(popup)
		var stack : int = index % (POPUP_MAX_STACK + 1)
		var offset : float = -float(stack) * POPUP_STACK_HEIGHT
		popup.setup(
			data.world_pos, data.damage,
			data.is_crit, data.is_miss, data.is_heal,
			offset
		)
		index += 1
		await get_tree().create_timer(POPUP_QUEUE_INTERVAL, true, false, true).timeout
	_damage_popup_busy[key] = false
	_damage_popup_queue.erase(key)


# ============================================================
#  InfoPanel (纯数值版)
# ============================================================
func _on_request_show_info(unit: Unit):
	var avatar_rect := get_node_or_null("Info/AvatarRect") as TextureRect
	var avatar_bg := get_node_or_null("Info/AvatarBg") as Panel

	if unit == null:
		_hide_avatar(avatar_rect, avatar_bg)
		var mouse_pos = get_global_mouse_position()
		var t_cell = world_to_grid(mouse_pos)
		var t_type = TerrainManager.get_terrain(t_cell)
		var t_name = TerrainManager.get_terrain_name(t_type)
		# ★ v4.6：地形减伤率口径（悬停地形时用 hover_* 前缀，避免与下方有单位时的 t_* 撞名）
		var td : Dictionary = TerrainManager.TERRAIN_DATA.get(t_type, {})
		var hover_phys : float = float(td.get("physical_reduction", 0.0))
		var hover_mag  : float = float(td.get("magic_reduction", 0.0))
		info_text_label.text = "地形: " + t_name \
			+ "\n物减 +%d%%" % int(hover_phys * 100) \
			+ "  魔减 +%d%%" % int(hover_mag * 100)
		_adjust_info_panel(info_text_label, info_panel, null)
		return

	if not is_instance_valid(unit) or unit.unit_stats == null: return

	if avatar_rect and avatar_bg:
		if unit.unit_stats.team_id != 0:
			_hide_avatar(avatar_rect, avatar_bg)
		else:
			var avatar_id = GameState.get_unit_avatar(unit.unit_stats.unit_name)
			var path := ""
			if avatar_id != "": path = "res://content/images/characters/avatar/%s.png" % avatar_id
			if path != "" and ResourceLoader.exists(path):
				var tex = load(path)
				if avatar_rect.texture != tex: avatar_rect.texture = tex
				avatar_rect.custom_minimum_size = Vector2(48, 48)
				avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				_show_avatar(avatar_rect, avatar_bg)
			else:
				_hide_avatar(avatar_rect, avatar_bg)

	var lines : Array = []
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	var type_name = UnitDataManager.get_unit_type_display_name(unit.unit_stats.unit_name)
	lines.append(display_name + " | " + unit.unit_stats.faction + " | " + type_name)
	lines.append("HP: " + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp))

	var status_str : String = ""
	if unit.hit_points <= 0: status_str = "【已阵亡】"
	elif unit.has_acted or not unit.can_act_this_turn: status_str = "【单位待机】"
	elif unit.has_attacked: status_str = "【已攻击】"
	else: status_str = "【可行动】"
	lines.append("状态: " + status_str)

	var weapon_data = unit.get_weapon_data()
	if weapon_data:
		var wname : String = weapon_data.name
		if unit.weapon_slot and unit.weapon_slot.upgrade_level > 0:
			wname += "+" + str(unit.weapon_slot.upgrade_level)
		lines.append("武器: " + wname)
		if weapon_data.base_attack > 0: lines.append("  攻击+" + str(weapon_data.base_attack))
		if not weapon_data.heal_effect.is_empty(): lines.append("  治疗+" + str(weapon_data.heal_effect.get("base_heal", 0)))
		lines.append("  射程: " + str(weapon_data.min_attack_range) + "~" + str(weapon_data.attack_range))
		if weapon_data.physical_penetration > 0.0: lines.append("  物理穿透: " + str(int(weapon_data.physical_penetration*100)) + "%")
		if weapon_data.magic_penetration > 0.0: lines.append("  魔法穿透: " + str(int(weapon_data.magic_penetration*100)) + "%")
	else:
		lines.append("武器: 无")

	var armor_slots : Array = unit.get_armor_slots()
	if armor_slots != null:
		var armor_lines : Array = []
		for i in range(armor_slots.size()):
			var inst = armor_slots[i]
			if inst:
				var data = ItemManager.get_item_data(inst.item_id)
				if data: armor_lines.append("  槽" + str(i+1) + ": " + data.name)
				else: armor_lines.append("  槽" + str(i+1) + ": （未知）")
			else: armor_lines.append("  槽" + str(i+1) + ": （空）")
		if armor_lines.size() > 0:
			lines.append("防具:")
			lines.append_array(armor_lines)

	lines.append("力量 " + str(unit.unit_stats.strength) \
		+ " | 灵巧 " + str(unit.unit_stats.dexterity) \
		+ " | 智力 " + str(unit.unit_stats.intelligence))
	lines.append("信仰 " + str(unit.unit_stats.faith) \
		+ " | 移动 " + str(unit.unit_stats.move_range))

	# ★ v4.6 减伤率显示
	var phys_red : float = unit.unit_stats.physical_reduction
	var mag_red : float = unit.unit_stats.magic_reduction
	for slot in unit.armor_slots:
		if slot:
			var d : ItemData = ItemManager.get_item_data(slot.item_id)
			if d:
				var qm : float = CombatManager.QUALITY_MULT.get(d.quality, 1.0)
				phys_red += d.physical_reduction * qm
				mag_red += d.magic_reduction * qm
	phys_red += unit.buff_physical_reduction + unit.buff_damage_reduction
	mag_red += unit.buff_magic_reduction + unit.buff_damage_reduction
	phys_red = clampf(phys_red, 0.0, 0.75)
	mag_red = clampf(mag_red, 0.0, 0.75)
	lines.append("物减 %d%% | 魔减 %d%%" % [int(phys_red*100), int(mag_red*100)])

	var talent_names : Array = []
	if unit.talent_slots != null:
		for inst in unit.talent_slots:
			if inst and inst.is_active:
				var tdata = TalentManager.get_talent_data(inst.talent_id)
				if tdata: talent_names.append(tdata.display_name)
	if unit.advanced_talent_inst and unit.advanced_talent_inst.is_active:
		var adv_tdata = TalentManager.get_talent_data(unit.advanced_talent_inst.talent_id)
		if adv_tdata: talent_names.append("★" + adv_tdata.display_name)
	if talent_names.size() > 0:
		lines.append("词条: " + ", ".join(talent_names))

	# ★ v4.6：地形减伤率口径（有单位时用 t_phys/t_mag，与上方 hover_* 不冲突）
	var unit_cell = unit.grid_cell
	var terrain_type = TerrainManager.get_terrain(unit_cell)
	var terrain_name = TerrainManager.get_terrain_name(terrain_type)
	var td_u : Dictionary = TerrainManager.TERRAIN_DATA.get(terrain_type, {})
	var t_phys : float = float(td_u.get("physical_reduction", 0.0))
	var t_mag  : float = float(td_u.get("magic_reduction", 0.0))
	lines.append("地形: " + terrain_name + "（物减+%d%% 魔减+%d%%）" % [int(t_phys * 100), int(t_mag * 100)])

	info_text_label.text = "\n".join(lines)
	_adjust_info_panel(info_text_label, info_panel, unit)


func _adjust_info_panel(label: Label, panel: PanelContainer, ref_unit: Unit = null):
	var vp_size := get_viewport().get_visible_rect().size
	var avatar_rect := get_node_or_null("Info/AvatarRect") as TextureRect
	var avatar_bg := get_node_or_null("Info/AvatarBg") as Panel
	var avatar_visible : bool = (avatar_rect != null and avatar_rect.visible)

	# ---- 1. 判定贴左还是贴右 ----
	var align_left_side : bool = false
	if ref_unit != null and is_instance_valid(ref_unit):
		var xform := get_viewport().get_canvas_transform()
		var screen_x : float = (xform * ref_unit.global_position).x
		align_left_side = (screen_x < vp_size.x * 0.5)
	else:
		align_left_side = false # 默认贴右

	if align_left_side:
		panel.offset_left = INFO_PANEL_MARGIN
		panel.offset_right = panel.offset_left + INFO_PANEL_WIDTH
	else:
		panel.offset_right = vp_size.x - INFO_PANEL_MARGIN
		panel.offset_left = panel.offset_right - INFO_PANEL_WIDTH

	panel.offset_top = INFO_PANEL_MARGIN

	# ---- 2. 文本宽度与面板高度计算 ----
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

	# ---- 3. 头像排版 ----
	if avatar_visible:
		avatar_bg.size = Vector2(54, 54)
		avatar_rect.size = Vector2(48, 48)
		
		var target_x : float
		if align_left_side:
			target_x = panel.offset_right + 4.0
		else:
			target_x = panel.offset_left - 4.0 - 54.0

		avatar_bg.offset_left = target_x
		avatar_bg.offset_right = target_x + 54.0
		avatar_bg.offset_top = INFO_PANEL_MARGIN
		avatar_bg.offset_bottom = INFO_PANEL_MARGIN + 54.0
		
		avatar_rect.offset_left = target_x + 3.0
		avatar_rect.offset_right = target_x + 54.0 - 3.0
		avatar_rect.offset_top = INFO_PANEL_MARGIN + 3.0
		avatar_rect.offset_bottom = INFO_PANEL_MARGIN + 54.0 - 3.0

	# ---- 4. 触发显示 ----
	if not panel.visible:
		PanelRevealer.show_panel(panel)
	if avatar_visible and not avatar_bg.visible:
		PanelRevealer.show_panel(avatar_bg)
		PanelRevealer.show_panel(avatar_rect)


func _on_request_hide_info():
	PanelRevealer.hide_panel(info_panel)
	var avatar_rect := get_node_or_null("Info/AvatarRect") as TextureRect
	var avatar_bg := get_node_or_null("Info/AvatarBg") as Panel
	_hide_avatar(avatar_rect, avatar_bg)


func _show_avatar(avatar_rect: TextureRect, bg_rect: Panel):
	if avatar_rect and is_instance_valid(avatar_rect):
		if not avatar_rect.visible:
			avatar_rect.visible = true
			PanelRevealer.show_panel(avatar_rect)
	if bg_rect and is_instance_valid(bg_rect):
		if not bg_rect.visible:
			bg_rect.visible = true
			PanelRevealer.show_panel(bg_rect)


func _hide_avatar(avatar_rect: TextureRect, bg_rect: Panel):
	if avatar_rect and is_instance_valid(avatar_rect):
		if avatar_rect.visible:
			PanelRevealer.hide_panel(avatar_rect)
	if bg_rect and is_instance_valid(bg_rect):
		if bg_rect.visible:
			PanelRevealer.hide_panel(bg_rect)


# ============================================================
#  设置栏
# ============================================================
func _on_request_show_setting():
	PanelRevealer.show_panel(setting_panel)
	# ★ 核心修复：打开设置时，强制关掉队伍查看面板
	if team_view_panel.visible:
		PanelRevealer.hide_panel(team_view_panel)


func _on_request_hide_setting():
	PanelRevealer.hide_panel(setting_panel)
	PanelRevealer.hide_panel(team_view_panel)
	PanelRevealer.hide_panel(setting_menu_panel)

func _on_soul_fire_changed(current: int, max_carried: int):
	if soul_fire_bar and is_instance_valid(soul_fire_bar):
		soul_fire_bar.max_value = max_carried
		soul_fire_bar.value = current
	if soul_fire_label and is_instance_valid(soul_fire_label):
		soul_fire_label.text = "%d/%d" % [current, max_carried]
	if soul_fire_state_label and is_instance_valid(soul_fire_state_label):
		match SoulFireManager.get_state():
			SoulFireManager.State.BURNING:
				soul_fire_state_label.text = "[燃烧]"
				soul_fire_state_label.modulate = Color(1.0, 0.6, 0.2, 1)
			SoulFireManager.State.DEPLETED:
				soul_fire_state_label.text = "[枯竭]"
				soul_fire_state_label.modulate = Color(0.7, 0.3, 1.0, 1)
			SoulFireManager.State.ZERO:
				soul_fire_state_label.text = "[归零]"
				soul_fire_state_label.modulate = Color(1.0, 0.3, 0.3, 1)
			_:
				soul_fire_state_label.text = ""
				soul_fire_state_label.modulate = Color.WHITE

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
	# 关闭所有菜单
	PanelRevealer.force_hide(setting_panel)
	PanelRevealer.force_hide(team_view_panel)
	PanelRevealer.force_hide(setting_menu_panel)

	# 重置输入状态
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_empty_cell = Vector2i(-1, -1)
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_hide_info.emit()

	SoundManager.play_select_sound()
	GameState.show_abandon_confirmation(self)


func _on_back_to_menu_pressed():
	PanelRevealer.force_hide(setting_panel)
	PanelRevealer.force_hide(team_view_panel)
	PanelRevealer.force_hide(setting_menu_panel)

	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_empty_cell = Vector2i(-1, -1)
	SoundManager.play_select_sound()

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
	var is_tv_open = team_view_panel.visible and team_view_panel.mouse_filter == Control.MOUSE_FILTER_STOP
	var is_sm_open = setting_menu_panel.visible and setting_menu_panel.mouse_filter == Control.MOUSE_FILTER_STOP
	var is_setting_open = setting_panel.visible and setting_panel.mouse_filter == Control.MOUSE_FILTER_STOP

	# 1. 队伍面板开着 → 关闭队伍面板，恢复竖条栏
	if is_tv_open:
		PanelRevealer.hide_panel(team_view_panel)
		PanelRevealer.show_panel(setting_panel)
		SoundManager.play_cancel_sound()
		return
		
	# 2. 大设置菜单开着 → 关闭大菜单，恢复竖条栏（★ 修复了这里之前丢失的恢复逻辑）
	if is_sm_open:
		PanelRevealer.hide_panel(setting_menu_panel)
		PanelRevealer.show_panel(setting_panel)
		SoundManager.play_cancel_sound()
		return
		
	# 3. 竖条栏开着 → 全关，彻底回到游戏
	if is_setting_open:
		PanelRevealer.hide_panel(setting_panel)
		SignalBus.request_hide_info.emit()
		SoundManager.play_cancel_sound()
		InputManager.interaction_phase = InputManager.Phase.IDLE
		InputManager.current_empty_cell = Vector2i(-1, -1)
		return


# ============================================================
#  胜利目标可视化 + 状态 HUD
# ============================================================
var _objective_marker_layer : Node2D = null
var _objective_status_label : Label = null
var _last_obj_status_text : String = ""


func _render_objective_markers():
	if _objective_marker_layer and is_instance_valid(_objective_marker_layer):
		_objective_marker_layer.queue_free()
	_objective_marker_layer = null

	if ObjectiveManager == null:
		return
	var obj_type : int = ObjectiveManager.get_objective_type()
	if obj_type == MapData.ObjectiveType.ANNIHILATE:
		return

	_objective_marker_layer = Node2D.new()
	_objective_marker_layer.name = "ObjectiveMarkerLayer"
	_objective_marker_layer.z_index = 0
	add_child(_objective_marker_layer)

	match obj_type:
		MapData.ObjectiveType.CAPTURE:
			_render_capture_marker()
		MapData.ObjectiveType.FLAG:
			_render_flag_markers()
		MapData.ObjectiveType.ASSAULT:
			_render_assault_marker()


func _render_capture_marker():
	var cell : Vector2i = ObjectiveManager.get_capture_cell()
	if cell == Vector2i(-1, -1):
		return
	_draw_cell_marker(cell, Color(1.0, 0.85, 0.3, 0.35), "★", Color(1.0, 0.85, 0.3))


func _render_flag_markers():
	var flag_cell : Vector2i = ObjectiveManager.get_flag_cell()
	var goal_cell : Vector2i = ObjectiveManager.get_flag_goal_cell()
	if flag_cell != Vector2i(-1, -1):
		_draw_cell_marker(flag_cell, Color(0.9, 0.3, 0.3, 0.4), "旗", Color(1.0, 0.4, 0.4))
	if goal_cell != Vector2i(-1, -1):
		_draw_cell_marker(goal_cell, Color(0.3, 0.9, 0.3, 0.4), "终", Color(0.4, 1.0, 0.4))


func _render_assault_marker():
	pass


func _draw_cell_marker(cell: Vector2i, bg_color: Color, text: String, text_color: Color):
	if _objective_marker_layer == null or not is_instance_valid(_objective_marker_layer):
		return

	var px : float = float(cell.x) * MapConst.CELL_SIZE
	var py : float = float(cell.y) * MapConst.CELL_SIZE

	var rect := ColorRect.new()
	rect.color = bg_color
	rect.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	rect.position = Vector2(px, py)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_marker_layer.add_child(rect)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	label.position = Vector2(px, py)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_marker_layer.add_child(label)


func _create_objective_status_label():
	if _objective_status_label and is_instance_valid(_objective_status_label):
		return
	if ObjectiveManager == null:
		return
	if ObjectiveManager.is_annihilate():
		return

	_objective_status_label = Label.new()
	_objective_status_label.name = "ObjectiveStatusLabel"
	_objective_status_label.add_theme_font_size_override("font_size", 7)
	_objective_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_objective_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_objective_status_label.add_theme_constant_override("outline_size", 2)
	_objective_status_label.anchor_left = 0.5
	_objective_status_label.anchor_right = 0.5
	_objective_status_label.offset_left = -100
	_objective_status_label.offset_right = 100
	_objective_status_label.offset_top = 46
	_objective_status_label.offset_bottom = 60
	_objective_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_status_label.z_index = 99
	_objective_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_objective_status_label)
	_last_obj_status_text = ""
	_refresh_objective_status()


func _refresh_objective_status():
	if not _objective_status_label or not is_instance_valid(_objective_status_label):
		return
	if ObjectiveManager == null:
		if _last_obj_status_text != "":
			_objective_status_label.text = ""
			_last_obj_status_text = ""
		return

	var new_text : String = ""
	match ObjectiveManager.get_objective_type():
		MapData.ObjectiveType.CAPTURE:
			var cur : int = ObjectiveManager.get_capture_progress()
			var need : int = ObjectiveManager.get_capture_hold_turns()
			new_text = "占领 %d / %d" % [cur, need]
		MapData.ObjectiveType.FLAG:
			if ObjectiveManager.get_flag_carrier() != null:
				new_text = "已拾旗 → 带回终点"
			else:
				new_text = "未拾旗 → 前往旗帜位置"
		MapData.ObjectiveType.ASSAULT:
			new_text = "击杀目标 Boss"
		_:
			new_text = ""

	if new_text != _last_obj_status_text:
		_objective_status_label.text = new_text
		_last_obj_status_text = new_text


# ============================================================
#  Boss 情报 banner
# ============================================================
var _intel_banner : Label = null


func _deferred_show_boss_intel():
	await get_tree().create_timer(2.5, true, false, true).timeout
	if not is_inside_tree():
		return
	if GameState.current_map_data == null:
		return
	if GameState.current_map_data.node_type != MapNode.NodeType.BOSS:
		return
	var intels : Array = GameState.revealed_intel
	if intels.is_empty():
		return
	_show_intel_banner(str(intels[0]))


func _show_intel_banner(text : String):
	if _intel_banner and is_instance_valid(_intel_banner):
		_intel_banner.queue_free()

	var lb := Label.new()
	lb.name = "IntelBanner"
	lb.text = "⚡ 情报：" + text
	lb.add_theme_font_size_override("font_size", 9)
	lb.add_theme_color_override("font_color", Color(0.8, 0.7, 1.0))
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 3)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.anchor_left = 0.5
	lb.anchor_right = 0.5
	lb.offset_left = -180
	lb.offset_right = 180
	lb.offset_top = 76
	lb.offset_bottom = 104
	lb.z_index = 100
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)
	_intel_banner = lb

	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(lb, "modulate:a", 0.0, 0.8).set_delay(4.0)
	tw.tween_callback(func():
		if is_instance_valid(lb):
			lb.queue_free()
		if _intel_banner == lb:
			_intel_banner = null
	)


# ============================================================
#  波次 HUD + 增援警告 banner
# ============================================================
var _wave_hud_label : Label = null
var _wave_warning_banner : Label = null


func _connect_wave_signals():
	if WaveManager == null:
		return
	if not WaveManager.wave_advanced.is_connected(_on_wave_advanced):
		WaveManager.wave_advanced.connect(_on_wave_advanced)
	if not WaveManager.wave_warning.is_connected(_on_wave_warning):
		WaveManager.wave_warning.connect(_on_wave_warning)


func _disconnect_wave_signals():
	if WaveManager == null:
		return
	if WaveManager.wave_advanced.is_connected(_on_wave_advanced):
		WaveManager.wave_advanced.disconnect(_on_wave_advanced)
	if WaveManager.wave_warning.is_connected(_on_wave_warning):
		WaveManager.wave_warning.disconnect(_on_wave_warning)


func _ensure_wave_hud():
	if _wave_hud_label and is_instance_valid(_wave_hud_label):
		return
	_wave_hud_label = Label.new()
	_wave_hud_label.name = "WaveIndicator"
	_wave_hud_label.add_theme_font_size_override("font_size", 8)
	_wave_hud_label.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
	_wave_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_wave_hud_label.add_theme_constant_override("outline_size", 2)
	_wave_hud_label.position = Vector2(240, 208)
	_wave_hud_label.size = Vector2(80, 14)
	_wave_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_wave_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wave_hud_label)


func _on_wave_advanced(current : int, total : int):
	if not is_inside_tree():
		return
	if total <= 1:
		return
	_ensure_wave_hud()
	if _wave_hud_label and is_instance_valid(_wave_hud_label):
		_wave_hud_label.text = "波次 %d / %d" % [current, total]
		_wave_hud_label.visible = true


func _on_wave_warning(next_wave : int, total : int):
	if not is_inside_tree():
		return
	_show_wave_warning_banner("⚠ 增援即将到达（%d / %d）" % [next_wave, total])


func _show_wave_warning_banner(text : String):
	if _wave_warning_banner and is_instance_valid(_wave_warning_banner):
		_wave_warning_banner.queue_free()

	var lb := Label.new()
	lb.name = "WaveWarningBanner"
	lb.text = text
	lb.add_theme_font_size_override("font_size", 10)
	lb.add_theme_color_override("font_color", Color(1.0, 0.5, 0.35))
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 3)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.anchor_left = 0.5
	lb.anchor_right = 0.5
	lb.offset_left = -140
	lb.offset_right = 140
	lb.offset_top = 104
	lb.offset_bottom = 128
	lb.z_index = 100
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)
	_wave_warning_banner = lb

	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(lb, "modulate:a", 0.0, 0.5).set_delay(2.5)
	tw.tween_callback(func():
		if is_instance_valid(lb):
			lb.queue_free()
		if _wave_warning_banner == lb:
			_wave_warning_banner = null
	)


func _deferred_show_objective_banner():
	await get_tree().create_timer(1.5, true, false, true).timeout
	if not is_inside_tree():
		return
	if ObjectiveManager == null or ObjectiveManager.is_annihilate():
		return
	_show_objective_banner()


func _show_objective_banner():
	if _objective_banner and is_instance_valid(_objective_banner):
		_objective_banner.queue_free()

	var text : String = "★ 目标：" + ObjectiveManager.get_description()
	var lb := Label.new()
	lb.name = "ObjectiveBanner"
	lb.text = text
	lb.add_theme_font_size_override("font_size", 11)
	lb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 3)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.anchor_left = 0.5
	lb.anchor_right = 0.5
	lb.offset_left = -180
	lb.offset_right = 180
	lb.offset_top = 16
	lb.offset_bottom = 42
	lb.z_index = 100
	add_child(lb)
	_objective_banner = lb

	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(lb, "modulate:a", 0.0, 0.8).set_delay(3.0)
	tw.tween_callback(func():
		if is_instance_valid(lb):
			lb.queue_free()
		if _objective_banner == lb:
			_objective_banner = null
	)


# 用于挂载/更新头像和文字
func _update_unit_display_info(unit_type: String, stats_text: String, avatar_bg: Panel, avatar_rect: TextureRect, stats_label: Label):
	# 1. 设置文字
	if stats_label:
		stats_label.text = stats_text

	# 2. 判断是否显示头像（支持全局头像覆写）
	var avatar_id = GameState.get_unit_avatar(unit_type)
	var has_avatar = false
	
	if avatar_id != "":
		var path = "res://content/images/characters/avatar/%s.png" % avatar_id
		if ResourceLoader.exists(path):
			var tex = load(path)
			if avatar_rect.texture != tex:
				avatar_rect.texture = tex
			has_avatar = true
			
	# 3. 控制显示/隐藏与排版
	if has_avatar:
		# 设置 50x50 留边：容器是 54x54，内边距 2px
		avatar_rect.custom_minimum_size = Vector2(50, 50)
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		
		# 用 PanelRevealer 刷出
		if not avatar_bg.visible:
			avatar_bg.visible = true
			PanelRevealer.show_panel(avatar_bg)
		if not avatar_rect.visible:
			avatar_rect.visible = true
			PanelRevealer.show_panel(avatar_rect)
	else:
		# 没头像就隐藏
		if avatar_bg.visible:
			PanelRevealer.hide_panel(avatar_bg)
		if avatar_rect.visible:
			PanelRevealer.hide_panel(avatar_rect)
