extends Node2D
class_name Battlefield

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

@export var map_data : MapData = null

@onready var action_menu : CanvasLayer = $ActionMenu
@onready var attack_btn : Button = $ActionMenu/ActionPanel/ButtonContainer/AttackBtn
@onready var move_btn : Button = $ActionMenu/ActionPanel/ButtonContainer/MoveBtn
@onready var equip_btn : Button = $ActionMenu/ActionPanel/ButtonContainer/EquipBtn
@onready var wait_btn : Button = $ActionMenu/ActionPanel/ButtonContainer/WaitBtn
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

@onready var setting_panel : PanelContainer = $SettingLayer/SettingPanel
@onready var setting_end_turn_btn : Button = $SettingLayer/SettingPanel/SettingContainer/EndTurnBtn
@onready var setting_btn : Button = $SettingLayer/SettingPanel/SettingContainer/SettingBtn
@onready var setting_menu_panel : Panel = $SettingLayer/SettingMenuPanel
@onready var team_view_btn : Button = $SettingLayer/SettingPanel/SettingContainer/TeamViewBtn
@onready var team_view_panel : PanelContainer = $SettingLayer/TeamViewPanel
@onready var team_view_container : VBoxContainer = $SettingLayer/TeamViewPanel/TeamViewContainer
@onready var speed_indicator: Label = $SpeedLayer/SpeedIndicator

@export var transition_delay_before_fade : float = 1.0
@export var transition_delay_after_fade : float = 1.0

@onready var item_list_btn : Button = $SettingLayer/SettingPanel/SettingContainer/ItemListBtn
@onready var item_list_panel : PanelContainer = $SettingLayer/ItemListPanel
@onready var item_list_container : VBoxContainer = $SettingLayer/ItemListPanel/ItemListContainer
@onready var item_action_panel: CanvasLayer = $ItemActionPanel

const CELL_SIZE : int = 16
var map_grid_size : Vector2i = Vector2i(20, 15)
var _initialized : bool = false
var _viewport_scale : float = 1.0
var _battle_start_event_id: String = ""
var _attack_indicator : TextureRect = null

# ---- 功能格系统 ----
var map_functions : Dictionary = {}
var _turn_changed_locked : bool = false

const PERFORMANCE_DURATION : float = 0.5
const ItemGetPopupScene = preload("res://content/scenes/ui/ItemGetPopup.tscn")

# ===================== 生命周期 =====================
func _ready():
	setting_btn.pressed.connect(_on_setting_btn_pressed)
	equip_btn.pressed.connect(_on_equip_btn_pressed)
	item_list_btn.pressed.connect(_on_item_list_btn_pressed)

	if _initialized:
		return
	_initialized = true
	_init_cursor()

	team_view_panel.visible = false
	item_list_panel.visible = false
	setting_menu_panel.visible = false
	team_view_btn.pressed.connect(_on_team_view_btn_pressed)

	_attack_indicator = TextureRect.new()
	_attack_indicator.texture = cursor.texture
	_attack_indicator.size = Vector2(CELL_SIZE, CELL_SIZE)
	_attack_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_indicator.z_index = 5
	_attack_indicator.visible = false
	add_child(_attack_indicator)

	victory_panel.visible = false

	_initialize_managers()
	_connect_signals()

	if turn_overlay:
		turn_overlay.modulate = Color(1, 1, 1, 0)
		Globals.is_fading = false

	if Globals.current_map_data:
		load_map(Globals.current_map_data)
	else:
		_load_default_map()

	if not map_data:
		var map_pixel_size = Vector2(map_grid_size.x * CELL_SIZE, map_grid_size.y * CELL_SIZE)
		camera_controller.set_map_boundary(Rect2(Vector2.ZERO, map_pixel_size))

	camera_controller.set_grid_size(CELL_SIZE)
	var viewport_size = get_viewport().get_visible_rect().size
	camera_controller.set_edge_scroll_margin(viewport_size.x * 0.25)

	action_menu.visible = false
	move_btn.disabled = true
	attack_btn.disabled = true
	wait_btn.disabled = true
	info_panel.visible = false
	setting_panel.visible = false
	item_action_panel.visible = false

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

	highlight_manager.clear_highlight()
	_on_clear_highlight_unit()

	menu_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_blocker.visible = false
	menu_blocker.gui_input.connect(_on_menu_blocker_clicked)
	menu_blocker.size = Vector2(map_grid_size.x * CELL_SIZE, map_grid_size.y * CELL_SIZE)
	menu_blocker.position = Vector2.ZERO
	menu_blocker.z_index = 10

	if _battle_start_event_id != "":
		print("检测到战斗开始事件：", _battle_start_event_id)
		var music = MusicManager.config.battle_start_dialogue_music
		if EventManager and EventManager.has_event(_battle_start_event_id):
			await EventManager.trigger_event(_battle_start_event_id, null, music)
		else:
			if DialogueManager.has_dialogue(_battle_start_event_id):
				DialogueManager.start_dialogue(_battle_start_event_id, music)
				await DialogueManager.dialogue_finished
			else:
				print("警告：战斗开始事件/对话不存在: ", _battle_start_event_id)
		print("战斗开始事件结束")
	else:
		print("没有战斗开始事件")

	MusicManager.stop_music()
	MusicManager._saved_stream = null
	MusicManager._saved_position = 0.0

	await get_tree().process_frame
	print("=== 准备启动玩家回合 ===")
	TurnManager.start_turn(0)
	print("=== TurnManager.start_turn(0) 调用完成 ===")

func _exit_tree():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cursor.visible = false
	if _attack_indicator:
		_attack_indicator.queue_free()
		_attack_indicator = null
	if move_btn.pressed.is_connected(_on_move_btn_pressed):
		move_btn.pressed.disconnect(_on_move_btn_pressed)
	if attack_btn.pressed.is_connected(_on_attack_btn_pressed):
		attack_btn.pressed.disconnect(_on_attack_btn_pressed)
	if wait_btn.pressed.is_connected(_on_wait_btn_pressed):
		wait_btn.pressed.disconnect(_on_wait_btn_pressed)

# ===================== 主循环 =====================
func _process(_delta):
	# ---- 摄像机暂停条件 ----
	var should_pause = (
		action_menu.visible or 
		victory_panel.visible or 
		info_panel.visible or 
		TurnManager.is_moving or 
		TurnManager.is_ai_moving or 
		TurnManager.current_turn_team == 1 or 
		Globals.is_fading or 
		Globals.is_transitioning or
		Globals.is_performing_action or
		Globals.is_dialogue_active or
		Globals.is_item_get_popup_active or
		camera_controller._is_smooth_moving
	)
	camera_controller.set_paused(should_pause)

	# ---- 强制隐藏光标条件（UI/对话框/敌人回合等） ----
	var force_hide_cursor = (
		Globals.is_dialogue_active or
		Globals.is_performing_action or
		Globals.is_item_get_popup_active or
		Globals.is_item_action_panel_open or
		Globals.is_equip_menu_active or
		Globals.is_weapon_select_active or
		victory_panel.visible or
		setting_panel.visible or
		team_view_panel.visible or
		item_list_panel.visible or
		setting_menu_panel.visible or
		TurnManager.current_turn_team == 1 or
		TurnManager.is_ai_moving or
		TurnManager.is_moving or
		Globals.is_fading or
		Globals.is_transitioning or
		camera_controller._is_smooth_moving
	)

	if force_hide_cursor:
		cursor.visible = false
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	# ---- 初始化光标状态 ----
	var show_cursor = false
	var cursor_world_pos = Vector2.ZERO
	var show_system_mouse = false

	# ---- 优先判断“锁定模式”：行动菜单或信息面板打开且选中单位有效 ----
	if (action_menu.visible or info_panel.visible) and InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit):
		show_cursor = true
		cursor_world_pos = grid_to_world(InputManager.selected_unit.grid_cell)
		show_system_mouse = true   # 允许操作菜单按钮
	else:
		# ---- 正常光标跟随鼠标逻辑 ----
		if info_panel.visible:
			var unit = InputManager.selected_unit
			if unit != null and is_instance_valid(unit):
				show_cursor = true
				cursor_world_pos = grid_to_world(unit.grid_cell)
			else:
				var empty_cell = InputManager.current_empty_cell
				if empty_cell != Vector2i(-1, -1):
					show_cursor = true
					cursor_world_pos = grid_to_world(empty_cell)
				else:
					show_cursor = true
					var world_mouse = get_global_mouse_position()
					var grid_pos = world_to_grid(world_mouse)
					cursor_world_pos = grid_to_world(grid_pos)
		else:
			if not should_pause:
				show_cursor = true
				var world_mouse = get_global_mouse_position()
				var grid_pos = world_to_grid(world_mouse)
				cursor_world_pos = grid_to_world(grid_pos)

		show_system_mouse = not show_cursor

	# ---- 更新光标位置（关键：像素对齐） ----
	if show_cursor:
		# 限制地图范围（仅在非锁定模式）
		if not (action_menu.visible or info_panel.visible):
			var world_mouse = get_global_mouse_position()
			var grid_pos = world_to_grid(world_mouse)
			grid_pos.x = clamp(grid_pos.x, 0, map_grid_size.x - 1)
			grid_pos.y = clamp(grid_pos.y, 0, map_grid_size.y - 1)
			cursor_world_pos = grid_to_world(grid_pos)

		# 计算屏幕坐标并强制对齐整数像素
		var canvas_transform = get_viewport().get_canvas_transform()
		var screen_pos = canvas_transform * cursor_world_pos
		screen_pos = screen_pos.round()                     # 像素对齐
		var size = cursor.size.round()                      # 尺寸对齐
		cursor.position = screen_pos - size / 2
		cursor.visible = true
	else:
		cursor.visible = false

	# ---- 设置鼠标模式 ----
	if show_system_mouse:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	# ---- 光标缩放更新（尺寸保持整数） ----
	if cursor.visible:
		var new_scale = _get_viewport_scale()
		if new_scale != _viewport_scale:
			_viewport_scale = new_scale
			var target_size = round(CELL_SIZE * _viewport_scale)
			cursor.size = Vector2(target_size, target_size)
			if _attack_indicator:
				_attack_indicator.size = Vector2(target_size, target_size)

	# ---- 光标颜色（粉色标识选中状态） ----
	var should_be_pink = false
	if Globals.is_item_action_panel_open:
		should_be_pink = true
	elif Globals.is_equip_menu_active:
		should_be_pink = true
	elif action_menu.visible or info_panel.visible:
		should_be_pink = true
	elif InputManager.selected_unit != null and InputManager.selected_unit.unit_stats.team_id == 0:
		var phase = InputManager.interaction_phase
		if phase in ["menu", "moving", "attacking", "item_target"]:
			should_be_pink = true

	var target_color = Color.FUCHSIA if should_be_pink else Color.WHITE
	if cursor.modulate != target_color:
		cursor.modulate = target_color

# ===================== 光标初始化 =====================
func _init_cursor():
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	cursor.visible = true
	if cursor.texture == null:
		var path = "res://content/images/system/选择框.png"
		if ResourceLoader.exists(path):
			cursor.texture = load(path)
		else:
			push_error("光标图片不存在：", path)
	_viewport_scale = _get_viewport_scale()
	var target_size = round(CELL_SIZE * _viewport_scale)
	cursor.size = Vector2(target_size, target_size)
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _get_viewport_scale() -> float:
	var viewport = get_viewport()
	var canvas_transform = viewport.get_canvas_transform()
	var scale_value = canvas_transform.get_scale()
	return scale_value.x

# ===================== 地图加载 =====================
func load_map(new_map_data: MapData):
	self.map_data = new_map_data

	var tilemap : TileMapLayer = null
	var main_scene_instance : Node = null
	var used_rect : Rect2i = Rect2i()

	if new_map_data.scene:
		main_scene_instance = new_map_data.scene.instantiate()
		tilemap = _find_tilemap(main_scene_instance)
		if tilemap:
			var old_tilemap = get_node_or_null("TerrainTileMap")
			if old_tilemap:
				old_tilemap.queue_free()
			main_scene_instance.name = "TerrainTileMap"
			add_child(main_scene_instance)
			move_child(main_scene_instance, 0)
			tilemap.z_index = -1
			used_rect = tilemap.get_used_rect()
			if used_rect.size.x > 0 and used_rect.size.y > 0:
				map_grid_size = used_rect.size
			else:
				map_grid_size = new_map_data.map_size
			TerrainManager.grid_size = map_grid_size
			TerrainManager.load_from_tilemap(tilemap, map_grid_size)
			_extract_map_unit_placers(main_scene_instance)
		else:
			push_error("场景中未找到 TileMapLayer")
			if main_scene_instance:
				main_scene_instance.queue_free()
			tilemap = get_node_or_null("TerrainTileMap") as TileMapLayer
			if tilemap:
				used_rect = tilemap.get_used_rect()
				if used_rect.size.x > 0 and used_rect.size.y > 0:
					map_grid_size = used_rect.size
				else:
					map_grid_size = new_map_data.map_size
				TerrainManager.grid_size = map_grid_size
				TerrainManager.load_from_tilemap(tilemap, map_grid_size)
	else:
		tilemap = get_node_or_null("TerrainTileMap") as TileMapLayer
		if tilemap:
			used_rect = tilemap.get_used_rect()
			if used_rect.size.x > 0 and used_rect.size.y > 0:
				map_grid_size = used_rect.size
			else:
				map_grid_size = new_map_data.map_size
			TerrainManager.grid_size = map_grid_size
			TerrainManager.load_from_tilemap(tilemap, map_grid_size)
		else:
			push_warning("没有地形数据，所有格子视为平地")
			map_grid_size = new_map_data.map_size
			TerrainManager.grid_size = map_grid_size

	_clear_units()

	var configs: Array[UnitConfig] = []
	if main_scene_instance:
		configs = UnitSpawner.extract_configs_from_node(main_scene_instance)
	if configs.size() == 0 and new_map_data.unit_configs.size() > 0:
		configs = new_map_data.unit_configs

	if configs.size() > 0:
		UnitSpawner.spawn_units_from_configs(self, configs, grid_to_world)
	else:
		UnitSpawner.spawn_test_units(self, grid_to_world)

	for unit in UnitManager.unit_list:
		unit.position = grid_to_world(unit.grid_cell)
		unit.z_index = 1

	var map_pixel_rect = Rect2()
	if used_rect.size.x > 0 and used_rect.size.y > 0:
		map_pixel_rect = Rect2(
			used_rect.position * CELL_SIZE,
			used_rect.size * CELL_SIZE
		)
		menu_blocker.size = used_rect.size * CELL_SIZE
		menu_blocker.position = used_rect.position * CELL_SIZE
	else:
		map_pixel_rect = Rect2(Vector2.ZERO, new_map_data.map_size * CELL_SIZE)
		menu_blocker.size = new_map_data.map_size * CELL_SIZE
		menu_blocker.position = Vector2.ZERO

	menu_blocker.z_index = 2
	camera_controller.set_map_boundary(map_pixel_rect)
	print("地图边界（像素）:", map_pixel_rect)

	_center_camera_on_player()
	TurnManager.map_functions = map_functions
	print("地图加载完成：", new_map_data.map_name)

func _extract_map_unit_placers(node: Node):
	map_functions.clear()
	var battle_start_event = ""

	var tools = []
	_find_tools(node, tools)

	for tool in tools:
		var cfg = tool.export_config()
		var cell = cfg["position"]
		var entry = {"triggered": false}

		match cfg["type"]:
			"event_trigger":
				var event_id = cfg["event_id"]
				if event_id != "":
					entry["event_id"] = event_id
					map_functions[cell] = entry
					print("功能格: 位置 ", cell, " 事件ID: ", event_id)

			"hp_function":
				var amount = cfg["hp_amount"]
				if amount != 0:
					var generated_id = "hp_%d_%d" % [cell.x, cell.y]
					var action_type = "heal" if amount > 0 else "damage"
					var actions = [{ "type": action_type, "amount": amount }]
					EventManager.register_event(generated_id, { "actions": actions, "once": false })
					entry["event_id"] = generated_id
					map_functions[cell] = entry
					print("功能格: 位置 ", cell, " HP事件: ", generated_id)

			"battle_start":
				var event_id = cfg["event_id"]
				if event_id != "":
					battle_start_event = event_id
					print("战斗开始事件: ", event_id)

	_battle_start_event_id = battle_start_event
	print("共提取 ", map_functions.size(), " 个功能格，战斗开始事件: ", battle_start_event)

func _find_tools(node: Node, result: Array):
	if node is EventTrigger or node is HpFunction or node is BattleStartEvent:
		result.append(node)
	for child in node.get_children():
		_find_tools(child, result)

func _center_camera_on_player():
	var player_units = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			player_units.append(unit)
	if player_units.size() > 0:
		var target_unit = player_units[0]
		var target_pos = grid_to_world(target_unit.grid_cell)
		target_pos = camera_controller.clamp_position(target_pos)
		# 使用平滑移动，duration=0 立即跳转，但避免半格偏移
		camera_controller.smooth_move_to(target_pos, 0.0, true)
	else:
		var viewport_size = get_viewport().get_visible_rect().size
		var center = camera_controller.map_rect.position + camera_controller.map_rect.size / 2
		var target_pos = center - viewport_size / 2
		target_pos = camera_controller.clamp_position(target_pos)
		camera_controller.smooth_move_to(target_pos, 0.0, true)

func _load_default_map():
	var default_map = MapData.new()
	default_map.map_name = "默认地图"
	default_map.scene = null
	default_map.map_size = map_grid_size
	var configs: Array[UnitConfig] = []
	var p1 = UnitConfig.new()
	p1.unit_name = "剑士"
	p1.team_id = 0
	p1.position = Vector2i(15, 10)
	configs.append(p1)

	var p2 = UnitConfig.new()
	p2.unit_name = "枪兵"
	p2.team_id = 0
	p2.position = Vector2i(15, 11)
	configs.append(p2)

	var e1 = UnitConfig.new()
	e1.unit_name = "枪兵"
	e1.team_id = 1
	e1.position = Vector2i(3, 3)
	configs.append(e1)

	var e2 = UnitConfig.new()
	e2.unit_name = "斧兵"
	e2.team_id = 1
	e2.position = Vector2i(3, 4)
	configs.append(e2)

	default_map.unit_configs = configs
	load_map(default_map)

func _clear_units():
	for child in get_children():
		if child is Unit:
			UnitManager.unregister_unit(child)
			child.queue_free()

func _find_tilemap(node: Node) -> TileMapLayer:
	if node is TileMapLayer:
		return node
	for child in node.get_children():
		var found = _find_tilemap(child)
		if found:
			return found
	return null

# ===================== 初始化管理器 =====================
func _initialize_managers():
	ui_manager.initialize({
		"action_menu": action_menu,
		"action_panel": $ActionMenu/ActionPanel,
		"move_btn": move_btn,
		"attack_btn": attack_btn,
		"wait_btn": wait_btn,
		"equip_btn": equip_btn,
		"equip_menu": $ActionMenu/EquipMenu,
		"weapon_select_menu": $ActionMenu/WeaponSelectMenu,
		"victory_panel": victory_panel,
		"victory_label": victory_label,
		"victory_button": victory_button,
		"ItemActionPanel": item_action_panel,
	})
	highlight_manager.initialize(self)
	turnlayer_manager.initialize(turn_overlay)

func _connect_signals():
	if move_btn.pressed.is_connected(_on_move_btn_pressed):
		move_btn.pressed.disconnect(_on_move_btn_pressed)
	if attack_btn.pressed.is_connected(_on_attack_btn_pressed):
		attack_btn.pressed.disconnect(_on_attack_btn_pressed)
	if wait_btn.pressed.is_connected(_on_wait_btn_pressed):
		wait_btn.pressed.disconnect(_on_wait_btn_pressed)

	move_btn.pressed.connect(_on_move_btn_pressed)
	attack_btn.pressed.connect(_on_attack_btn_pressed)
	wait_btn.pressed.connect(_on_wait_btn_pressed)
	setting_end_turn_btn.pressed.connect(_on_setting_end_turn_pressed)

	SignalBus.request_highlight.connect(_on_highlight_request)
	SignalBus.request_clear_highlight.connect(highlight_manager.clear_highlight)
	SignalBus.request_move_unit.connect(_on_instant_move)
	SignalBus.request_move_along_path.connect(_on_request_move_along_path)
	SignalBus.request_ai_move_along_path.connect(_on_ai_move_along_path)
	SignalBus.request_show_menu.connect(_on_request_show_menu)
	SignalBus.request_hide_menu.connect(ui_manager.hide_menu)
	SignalBus.request_show_victory.connect(_on_request_show_victory)
	SignalBus.turn_changed.connect(_on_turn_changed)
	SignalBus.request_highlight_unit.connect(_on_highlight_unit)
	SignalBus.request_clear_highlight_unit.connect(_on_clear_highlight_unit)
	SignalBus.request_screen_shake.connect(_on_request_screen_shake)
	SignalBus.request_damage_popup.connect(_on_request_damage_popup)
	SignalBus.request_show_info.connect(_on_request_show_info)
	SignalBus.request_hide_info.connect(_on_request_hide_info)
	SignalBus.request_show_setting.connect(_on_request_show_setting)
	SignalBus.request_hide_setting.connect(_on_request_hide_setting)
	SignalBus.speed_changed.connect(_on_speed_changed)
	SignalBus.request_show_enemy_preview.connect(_on_show_enemy_preview)
	_on_speed_changed(Globals.game_speed)

	movement_animator.movement_finished.connect(_on_player_movement_finished)
	movement_animator.ai_movement_finished.connect(_on_ai_movement_finished)

# ===================== 信号回调 =====================
func _on_highlight_request(cells: Dictionary):
	print("_on_highlight_request 收到, interaction_phase=", InputManager.interaction_phase, " cells.size=", cells.size())
	match InputManager.interaction_phase:
		"moving":
			if cells == InputManager.current_highlight_cells:
				highlight_manager.show_move_highlight(cells, Color(1, 1, 1, 0.3), 0, true)
			else:
				var unit = InputManager.selected_unit
				var preview_color = Color(0.7, 0.1, 0.2, 0.7)
				if unit and unit.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL:
					preview_color = Color(0.2, 0.5, 0.8, 0.7)
				highlight_manager.show_move_highlight(cells, preview_color, 1, false)
		"attacking":
			var unit = InputManager.selected_unit
			var color = Color(0.7, 0.1, 0.2, 0.7)
			if unit and unit.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL:
				color = Color(0.2, 0.5, 0.8, 0.7)
			highlight_manager.show_move_highlight(cells, color, 1, true)
		"item_target":
			var color = Color(0.7, 0.1, 0.2, 0.7)
			var effect = InputManager.pending_item_effect
			if effect and effect.has("type"):
				var eff_type = effect["type"]
				if eff_type == "heal":
					color = Color(0.2, 0.5, 0.8, 0.7)
				elif eff_type == "cure" or eff_type == "buff":
					color = Color(0.2, 0.5, 0.8, 0.7)
			highlight_manager.show_move_highlight(cells, color, 1, true)
		"give":
			highlight_manager.show_move_highlight(cells, Color(1, 0.6, 0, 0.7), 0, true)
		_:
			highlight_manager.clear_highlight()

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
	_clear_function_trigger(unit)
	TurnManager.on_movement_finished(unit)
	camera_controller.follow_mouse()
	SignalBus.request_clear_highlight.emit()

func _on_ai_movement_finished(unit: Unit):
	_clear_function_trigger(unit)
	TurnManager.on_ai_movement_finished(unit)
	camera_controller.follow_mouse()
	SignalBus.request_clear_highlight.emit()

func _clear_function_trigger(unit: Unit):
	if not is_instance_valid(unit):
		return
	var old_cell = unit.previous_grid_cell
	if map_functions.has(old_cell):
		var cfg = map_functions[old_cell]
		if cfg.get("triggered_by_unit") == unit:
			cfg["triggered"] = false
			cfg["triggered_by_unit"] = null

func _on_move_btn_pressed():
	InputManager.on_move_button_pressed()

func _on_attack_btn_pressed():
	InputManager.on_attack_button_pressed()

func _on_wait_btn_pressed():
	var unit = InputManager.selected_unit
	if unit == null or not is_instance_valid(unit):
		return

	var cell = unit.grid_cell
	# 检查功能格（非 HP 事件）
	if map_functions.has(cell):
		var func_config = map_functions[cell]
		var event_id = func_config.get("event_id", "")
		if event_id != "" and not event_id.begins_with("hp_") and not EventManager.is_event_completed(event_id):
			# 触发事件
			SoundManager.play_select_sound()
			func_config["triggered"] = true
			func_config["triggered_by_unit"] = unit
			await EventManager.trigger_event(event_id, unit)
			if EventManager.is_event_completed(event_id):
				func_config["triggered"] = true
			else:
				func_config["triggered"] = false
				func_config["triggered_by_unit"] = null
			# 无论成功与否，执行待机
			unit.can_act_this_turn = false
			unit.set_gray(true)
			TurnManager.finish_unit_action(unit)
			return

	# 否则普通待机
	InputManager.on_wait_button_pressed()

func _on_request_show_victory(winning_team: int):
	if is_instance_valid(movement_animator):
		movement_animator.cancel_movement()
	if is_instance_valid(camera_controller):
		camera_controller.cancel_smooth_move()
	if is_instance_valid(highlight_manager):
		highlight_manager.clear_highlight()
	_on_clear_highlight_unit()
	TurnManager.clear_ai_state()

	if is_instance_valid(ui_manager):
		ui_manager.hide_menu()
	if is_instance_valid(menu_blocker):
		menu_blocker.visible = false
	if is_instance_valid(info_panel):
		info_panel.visible = false
	if is_instance_valid(setting_panel):
		setting_panel.visible = false
	if is_instance_valid(team_view_panel):
		team_view_panel.visible = false
	if is_instance_valid(setting_menu_panel):
		setting_menu_panel.visible = false
	if is_instance_valid(action_menu):
		action_menu.visible = false
	if is_instance_valid(item_list_panel):
		item_list_panel.visible = false

	InputManager.selected_unit = null
	InputManager.interaction_phase = "idle"
	InputManager.current_highlight_cells = {}
	InputManager.current_move_attack_targets = {}
	InputManager.attackable_targets = []

	var is_win = (winning_team == 0)
	var is_last = LevelManager.is_last_level()
	if is_win and is_last:
		MusicManager.play_win_game_music()
	elif is_win:
		MusicManager.play_victory_music()
	else:
		MusicManager.play_defeat_music()

	var label_text = ""
	var button_text = ""
	var callback = Callable()
	if is_win:
		if is_last:
			label_text = "全部胜利"
			button_text = "回到开始"
		else:
			label_text = "战斗胜利"
			button_text = "下一关"
		callback = Callable(LevelManager, "on_victory")
	else:
		label_text = "战斗失败"
		button_text = "回到开始"
		callback = Callable(LevelManager, "on_defeat")

	if is_instance_valid(ui_manager):
		ui_manager.show_victory(label_text, button_text, callback)

func _on_turn_changed(team: int):
	print("_on_turn_changed 被调用，team:", team)
	if _turn_changed_locked:
		print("_turn_changed_locked 为 true，跳过")
		return
	_turn_changed_locked = true
	Globals.is_transitioning = true

	if is_instance_valid(action_menu):
		action_menu.visible = false
	if is_instance_valid(ui_manager):
		ui_manager.hide_menu()
	if is_instance_valid(menu_blocker):
		menu_blocker.visible = false
	if is_instance_valid(info_panel):
		info_panel.visible = false
	if is_instance_valid(setting_panel):
		setting_panel.visible = false
	if is_instance_valid(team_view_panel):
		team_view_panel.visible = false
	if is_instance_valid(setting_menu_panel):
		setting_menu_panel.visible = false

	InputManager.selected_unit = null
	InputManager.interaction_phase = "idle"
	InputManager.current_highlight_cells = {}
	InputManager.attackable_targets = []

	MusicManager.stop_music()

	await get_tree().create_timer(transition_delay_before_fade).timeout
	await turnlayer_manager.play_transition(team)
	await get_tree().create_timer(transition_delay_after_fade).timeout

	print("回合切换：", "玩家" if team == 0 else "敌人")

	var target_pos = null
	if team == 0:
		var last_unit = TurnManager.get_last_player_unit()
		if is_instance_valid(last_unit):
			target_pos = grid_to_world(last_unit.grid_cell)
	else:
		var first_enemy = TurnManager.get_first_enemy_unit()
		if is_instance_valid(first_enemy):
			target_pos = grid_to_world(first_enemy.grid_cell)

	if target_pos:
		camera_controller.smooth_move_to(target_pos, turnlayer_manager.transition_duration, true)
	else:
		var fallback_pos = _get_center_position()
		if fallback_pos:
			camera_controller.smooth_move_to(fallback_pos, turnlayer_manager.transition_duration, true)

	if team == 0:
		print("播放玩家回合音乐")
		MusicManager.play_player_turn_music()
	else:
		print("播放敌人回合音乐")
		MusicManager.play_enemy_turn_music()

	await apply_map_functions(team)

	Globals.is_transitioning = false
	_turn_changed_locked = false

	if team == 1:
		print("准备启动 AI，时间: ", Time.get_ticks_msec())
		TurnManager.run_enemy_ai()

func _get_center_position() -> Vector2:
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			return unit.global_position
	var viewport_size = get_viewport().get_visible_rect().size
	var center = camera_controller.map_rect.position + camera_controller.map_rect.size / 2
	return center - viewport_size / 2

func _on_highlight_unit(unit: Unit):
	if not is_instance_valid(unit) or not _attack_indicator:
		return
	_on_clear_highlight_unit()
	var target_size = CELL_SIZE * _viewport_scale
	_attack_indicator.size = Vector2(target_size, target_size)
	var world_pos = grid_to_world(unit.grid_cell)
	_attack_indicator.position = world_pos - _attack_indicator.size / 2
	_attack_indicator.visible = true

func _on_clear_highlight_unit():
	if _attack_indicator:
		_attack_indicator.visible = false

# ===================== 输入处理 =====================
func _input(event: InputEvent):
	if Globals.is_item_action_panel_open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		print("_input 捕获到 ItemActionPanel 右键")
		get_viewport().set_input_as_handled()
		var panel_unit = ui_manager.panel_unit
		ui_manager.hide_item_action_panel()
		if panel_unit and is_instance_valid(panel_unit):
			ui_manager.show_equip_menu(panel_unit)
			InputManager.selected_unit = panel_unit
			InputManager.interaction_phase = "menu"
			SignalBus.request_show_info.emit(panel_unit)
		ui_manager.panel_unit = null
		return

	if Globals.is_weapon_select_active:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			ui_manager.hide_weapon_select_menu()
			get_viewport().set_input_as_handled()
		return

	if Globals.is_equip_menu_active:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			Globals.suppress_sound = true
			ui_manager.hide_equip_menu()
			get_viewport().set_input_as_handled()
			if InputManager.selected_unit:
				InputManager.interaction_phase = "menu"
				SignalBus.request_show_menu.emit(InputManager.selected_unit)
		return

	if Globals.is_dialogue_active or Globals.is_item_menu_active or Globals.is_item_get_popup_active:
		return

	if event is InputEventKey and event.pressed:
		if TurnManager.current_turn_team == 0 and not Globals.is_fading:
			if event.keycode == KEY_0 or event.keycode == KEY_KP_0:
				print("调试：杀死所有敌方单位")
				var enemies = []
				for unit in UnitManager.unit_list:
					if unit.unit_stats.team_id == 1 and unit.hit_points > 0:
						enemies.append(unit)
				for enemy in enemies:
					enemy.apply_damage(enemy.hit_points)
					UnitManager.unregister_unit(enemy)
					enemy.queue_free()
				TurnManager.check_victory()
				return
			elif event.keycode == KEY_8 or event.keycode == KEY_KP_8:
				print("调试：所有己方单位执行待机")
				var allies = []
				for unit in UnitManager.unit_list:
					if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
						allies.append(unit)
				for ally in allies:
					TurnManager.finish_unit_action(ally)
				return
			elif event.keycode == KEY_9 or event.keycode == KEY_KP_9:
				print("调试：杀死所有我方单位")
				var allies = []
				for unit in UnitManager.unit_list:
					if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
						allies.append(unit)
				for ally in allies:
					ally.apply_damage(ally.hit_points)
					UnitManager.unregister_unit(ally)
					ally.queue_free()
				TurnManager.check_victory()
				return

	if Globals.is_transitioning or Globals.is_fading:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if (Globals.is_equip_menu_active or 
				Globals.is_item_action_panel_open or 
				Globals.is_weapon_select_active or
				setting_panel.visible or 
				setting_menu_panel.visible or 
				team_view_panel.visible or 
				item_list_panel.visible or
				InputManager.interaction_phase in ["moving", "attacking", "item_target", "give"]):
				return
			if TurnManager.current_turn_team == 0 and not TurnManager.is_moving and not TurnManager.is_ai_moving and not Globals.is_performing_action:
				var direction = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				InputManager.handle_wheel(direction)
			return

	if TurnManager.current_turn_team != 0:
		return
	if TurnManager.all_acted:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			print("键盘 1 按下 - 模拟移动")
			_on_move_btn_pressed()
		elif event.keycode == KEY_2:
			print("键盘 2 按下 - 模拟攻击/治疗")
			_on_attack_btn_pressed()
		elif event.keycode == KEY_3:
			print("键盘 3 按下 - 模拟待机")
			_on_wait_btn_pressed()

	if TurnManager.is_moving:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			InputManager.handle_input(event, map_grid_size, CELL_SIZE)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if action_menu.visible and InputManager.interaction_phase != "give":
				return
			var mouse_pos = get_global_mouse_position()
			var clicked_cell = world_to_grid(mouse_pos)
			InputManager.handle_click(clicked_cell)
	else:
		InputManager.handle_input(event, map_grid_size, CELL_SIZE)

	if Globals.is_equip_menu_active:
		return

# ===================== UI回调 =====================
func _on_request_show_menu(unit: Unit):
	if TurnManager.is_game_over or TurnManager.current_turn_team != 0 or TurnManager.all_acted:
		return
	if unit.unit_stats.team_id != 0:
		print("警告：试图为敌方单位显示菜单，已阻止")
		return

	if not Globals.suppress_sound:
		SoundManager.play_select_sound()
	else:
		Globals.suppress_sound = false

	print("显示菜单，单位：", unit.unit_stats.unit_name)

	InputManager.selected_unit = unit
	InputManager.interaction_phase = "menu"

	ui_manager.show_menu(unit)

	if is_instance_valid(menu_blocker):
		menu_blocker.visible = true
		menu_blocker.z_index = 10

	if is_instance_valid(move_btn):
		var can_move = false
		if unit.can_act_this_turn and not TurnManager.is_game_over:
			var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.remaining_move, unit)
			for c in reachable.keys():
				if c != unit.grid_cell:
					can_move = true
					break
		move_btn.disabled = not can_move

	if is_instance_valid(equip_btn):
		equip_btn.disabled = false

	if is_instance_valid(ui_manager.wait_btn):
		var cell = unit.grid_cell
		if map_functions.has(cell):
			var cfg = map_functions[cell]
			var event_id = cfg.get("event_id", "")
			if event_id != "" and EventManager.is_event_completed(event_id):
				ui_manager.wait_btn.text = "待机"
			elif event_id.begins_with("hp_"):
				ui_manager.wait_btn.text = "占领"
			elif event_id != "":
				ui_manager.wait_btn.text = "探索"
			else:
				ui_manager.wait_btn.text = "待机"
		else:
			ui_manager.wait_btn.text = "待机"

	# ---- 移动按钮状态 ----
	if is_instance_valid(move_btn):
		var can_move = false
		# 只有未攻击、未行动、可行动且未游戏结束时才能移动
		if not unit.has_attacked and not unit.has_acted and unit.can_act_this_turn and not TurnManager.is_game_over:
			var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.remaining_move, unit)
			for c in reachable.keys():
				if c != unit.grid_cell:
					can_move = true
					break
		move_btn.disabled = not can_move

func _on_request_hide_menu():
	if is_instance_valid(ui_manager):
		ui_manager.hide_menu()
	if is_instance_valid(menu_blocker):
		menu_blocker.visible = false
	if is_instance_valid(move_btn):
		move_btn.disabled = true
	print("菜单隐藏")

func _on_menu_blocker_clicked(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		SignalBus.request_hide_menu.emit()
		InputManager.selected_unit = null
		InputManager.interaction_phase = "idle"

# ===================== 功能格系统 =====================
func apply_map_functions(team: int):
	var units_to_remove = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == team and unit.hit_points > 0:
			var cell = unit.grid_cell
			if map_functions.has(cell):
				var func_config = map_functions[cell]
				var event_id = func_config.get("event_id", "")
				if event_id == "":
					continue
				# 只处理 HP 事件（以 "hp_" 开头）
				if not event_id.begins_with("hp_"):
					continue
				if EventManager.is_event_completed(event_id):
					continue
				if func_config.get("triggered", false):
					if func_config.get("triggered_by_unit") == unit:
						continue
				func_config["triggered"] = true
				func_config["triggered_by_unit"] = unit
				await EventManager.trigger_event(event_id, unit)
				if EventManager.is_event_completed(event_id):
					func_config["triggered"] = true
				else:
					func_config["triggered"] = false
					func_config["triggered_by_unit"] = null
				if unit.hit_points <= 0:
					units_to_remove.append(unit)

	for unit in units_to_remove:
		print(unit.unit_stats.unit_name + " 因陷阱死亡！")
		UnitManager.unregister_unit(unit)
		unit.queue_free()

	if units_to_remove.size() > 0:
		TurnManager.check_victory()

	print("=== 应用功能格效果完成 ===")

func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / CELL_SIZE), floor(world_pos.y / CELL_SIZE))

# ===================== 其他信号 =====================
func _on_request_screen_shake(duration: float, intensity: float, direction: Vector2 = Vector2.ZERO):
	var shake_node = $Camera2D.get_node_or_null("ScreenShake") as ScreenShake
	if shake_node:
		shake_node.shake(duration, intensity, direction)

func _on_request_damage_popup(world_pos: Vector2, damage: int, is_crit: bool, is_miss: bool, is_heal: bool):
	var popup = preload("res://function/script/DamagePopup.gd").new()
	add_child(popup)
	popup.setup(world_pos, damage, is_crit, is_miss, is_heal)

func _on_request_show_info(unit: Unit):
	var terrain_type: int
	var terrain_name: String
	var def_bonus: int
	var magic_def_bonus: int
	var avoid_bonus: int
	var display_text: String

	if unit == null:
		var mouse_pos = get_global_mouse_position()
		var cell = world_to_grid(mouse_pos)
		terrain_type = TerrainManager.get_terrain(cell)
		terrain_name = TerrainManager.get_terrain_name(terrain_type)
		def_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["def_bonus"]
		magic_def_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["magic_defense_bonus"]
		avoid_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["avoid_bonus"]
		display_text = "地形: " + terrain_name + "\n防御+" + str(def_bonus) + " 魔防+" + str(magic_def_bonus) + " 回避+" + str(avoid_bonus)
	else:
		if not is_instance_valid(unit):
			return
		var lines = []
		lines.append("名称: " + unit.unit_stats.unit_name)
		lines.append("HP: " + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp))

		var weapon_data = unit.get_weapon_data()
		var weapon_stats = unit.get_weapon_stats()

		if weapon_data:
			var attack_type = "物理" if weapon_stats["attack"] > 0 else "魔法" if weapon_stats["magic_attack"] > 0 else "治疗" if weapon_stats["heal_amount"] > 0 else "无"
			lines.append("装备: " + weapon_data.name + " (" + attack_type + ")")
			var attack_str = ""
			if weapon_stats["attack"] > 0:
				attack_str += "物理+" + str(weapon_stats["attack"]) + " "
			if weapon_stats["magic_attack"] > 0:
				attack_str += "魔法+" + str(weapon_stats["magic_attack"]) + " "
			if weapon_stats["heal_amount"] > 0:
				attack_str += "治疗+" + str(weapon_stats["heal_amount"]) + " "
			if attack_str == "":
				attack_str = "无攻击力"
			lines.append("攻击: " + attack_str.strip_edges())
			lines.append("范围: " + str(weapon_stats["min_attack_range"]) + "~" + str(weapon_stats["attack_range"]))
		else:
			lines.append("装备: 未装备")
			lines.append("攻击: 0")
			lines.append("范围: 0~0")

		var cell = unit.grid_cell
		terrain_type = TerrainManager.get_terrain(cell)
		def_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["def_bonus"]
		magic_def_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["magic_defense_bonus"]
		avoid_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["avoid_bonus"]

		var base_def = unit.unit_stats.defense
		var base_mdef = unit.unit_stats.magic_defense
		var base_avoid = unit.unit_stats.speed * 2 + unit.unit_stats.luck

		var def_text = str(base_def)
		if def_bonus > 0:
			def_text += " + " + str(def_bonus)
		lines.append("防御: " + def_text)

		var mdef_text = str(base_mdef)
		if magic_def_bonus > 0:
			mdef_text += " + " + str(magic_def_bonus)
		lines.append("魔防: " + mdef_text)

		var avoid_text = str(base_avoid)
		if avoid_bonus > 0:
			avoid_text += " + " + str(avoid_bonus)
		lines.append("回避: " + avoid_text)

		lines.append("技巧: " + str(unit.unit_stats.skill))
		lines.append("速度: " + str(unit.unit_stats.speed))
		lines.append("幸运: " + str(unit.unit_stats.luck))
		lines.append("移动力: " + str(unit.unit_stats.move_range))

		terrain_name = TerrainManager.get_terrain_name(terrain_type)
		lines.append("地形: " + terrain_name)

		if unit.inventory.size() > 0:
			for inst in unit.inventory:
				if inst == unit.equipped_weapon_instance:
					continue
				var item_id = inst.item_id
				var data = ItemManager.get_item_data(item_id)
				if data:
					var type_display = "武器" if data.type == "weapon" else "道具"
					var count = inst.count
					var item_str = "携带：" + data.name + " [" + type_display + "]"
					if data.type != "weapon":
						item_str += " x" + str(count)
					lines.append(item_str)
		else:
			lines.append("携带: 无")

		display_text = "\n".join(lines)

	info_text_label.text = display_text
	_adjust_info_panel(info_text_label, info_panel)

func _on_request_hide_info():
	info_panel.visible = false

func _on_request_show_setting():
	setting_panel.visible = true

func _on_request_hide_setting():
	setting_panel.visible = false
	team_view_panel.visible = false
	item_list_panel.visible = false
	setting_menu_panel.visible = false

func _on_setting_end_turn_pressed():
	SignalBus.request_hide_info.emit()
	SignalBus.request_hide_setting.emit()

	var allies = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			allies.append(unit)

	for ally in allies:
		ally.can_act_this_turn = false
		ally.set_gray(true)

	InputManager.selected_unit = null
	InputManager.interaction_phase = "idle"
	InputManager.current_highlight_cells = {}
	InputManager.attackable_targets = []
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()

	TurnManager.start_turn(1)

func _on_team_view_btn_pressed():
	if setting_menu_panel.visible:
		setting_menu_panel.visible = false
	if item_list_panel.visible:
		item_list_panel.visible = false
	team_view_panel.visible = not team_view_panel.visible
	if team_view_panel.visible:
		_refresh_team_view()

func _refresh_team_view():
	# 清空容器
	for child in team_view_container.get_children():
		child.queue_free()

	# 收集我方单位
	var units = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			units.append(unit)

	if units.is_empty():
		var label = Label.new()
		label.text = "没有存活的我方单位"
		label.add_theme_font_size_override("font_size", 6)
		team_view_container.add_child(label)
	else:
		units.sort_custom(func(a, b):
			if a.grid_cell.y != b.grid_cell.y:
				return a.grid_cell.y < b.grid_cell.y
			return a.grid_cell.x < b.grid_cell.x
		)

		for unit in units:
			var btn = Button.new()
			# 获取图标...
			var icon_texture: Texture2D = null
			if unit.animated_sprite and unit.animated_sprite.sprite_frames:
				var frames = unit.animated_sprite.sprite_frames
				var anim = unit.current_anim if unit.current_anim else "idle"
				if frames.has_animation(anim):
					icon_texture = frames.get_frame_texture(anim, 0)
				elif frames.has_animation("idle"):
					icon_texture = frames.get_frame_texture("idle", 0)
			if icon_texture:
				var image = icon_texture.get_image()
				image.resize(16, 16, Image.INTERPOLATE_NEAREST)
				btn.icon = ImageTexture.create_from_image(image)
				btn.add_theme_constant_override("hseparation", 4)

			var status = ""
			var color = Color.WHITE
			if unit.has_attacked:
				status = "   已攻击"
				color = Color(0.7, 0.4, 0.2, 1.0)
			elif not unit.can_act_this_turn:
				status = "   已待机"
				color = Color(0.5, 0.5, 0.5)
			else:
				status = "   可行动"

			btn.text = unit.unit_stats.unit_name + " HP:" + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp) + status
			btn.add_theme_font_size_override("font_size", 6)
			if color != Color.WHITE:
				btn.add_theme_color_override("font_color", color)
			btn.pressed.connect(_on_team_member_selected.bind(unit))
			team_view_container.add_child(btn)

	# ---- 确保 ScrollContainer 存在 ----
	var parent = team_view_container.get_parent()
	var scroll = parent as ScrollContainer
	if not scroll:
		scroll = _create_scroll_container(team_view_container, parent, "TeamViewScroll")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	# 更新面板高度（宽度保持场景中的设置）
	await get_tree().process_frame
	var content_height = team_view_container.get_minimum_size().y
	var viewport_height = get_viewport().get_visible_rect().size.y
	var max_height = viewport_height * 0.8
	var panel_height = clamp(content_height + 16, 20, max_height)
	team_view_panel.size.y = panel_height   # 只改高度，不改变位置

func _on_team_member_selected(unit: Unit):
	setting_menu_panel.visible = false
	team_view_panel.visible = false
	SignalBus.request_hide_setting.emit()
	SignalBus.request_hide_info.emit()

	InputManager.selected_unit = unit
	if unit.can_act_this_turn and unit.hit_points > 0:
		InputManager.interaction_phase = "menu"
		SignalBus.request_show_menu.emit(unit)
	else:
		InputManager.interaction_phase = "idle"

	SignalBus.request_show_info.emit(unit)
	SoundManager.play_select_sound()
	SignalBus.request_clear_highlight.emit()
	camera_controller.smooth_move_to(grid_to_world(unit.grid_cell), 0.3, true)
	InputManager.current_highlight_cells = {}
	InputManager.current_move_attack_targets = {}

func _on_setting_btn_pressed():
	if team_view_panel.visible:
		team_view_panel.visible = false
	if item_list_panel.visible:
		item_list_panel.visible = false
	setting_menu_panel.visible = not setting_menu_panel.visible

func _sync_speed_slider(new_val: int):
	if setting_menu_panel.visible:
		var menu = setting_menu_panel as SettingMenu
		if menu and menu.has_method("update_display"):
			menu.update_display(new_val)

func _on_speed_changed(new_speed: int):
	if new_speed == 0:
		speed_indicator.visible = false
	else:
		speed_indicator.visible = true
		var prefix = "+" if new_speed > 0 else ""
		speed_indicator.text = prefix + str(new_speed) + "X"

func _on_show_enemy_preview(move_cells: Dictionary, attack_cells: Dictionary, attack_color: Color):
	highlight_manager.clear_highlight()
	highlight_manager.show_enemy_preview(move_cells, attack_cells, attack_color)

func _on_dialogue_check(unit: Unit):
	if not is_instance_valid(unit):
		return
	if unit.unit_stats.team_id != 0 or unit.hit_points <= 0:
		return

	var cell = unit.grid_cell
	if not map_functions.has(cell):
		return

	var func_config = map_functions[cell]

	if func_config.get("triggered", false):
		var trigger_unit = func_config.get("triggered_by_unit", null)
		if trigger_unit == unit:
			return
		else:
			func_config["triggered"] = false
			func_config["triggered_by_unit"] = null

	var event_id = func_config.get("event_id", "")
	if event_id == "":
		return

	if EventManager.is_event_completed(event_id):
		return

	var event_def = EventManager.get_event(event_id)
	if not event_def.is_empty():
		for action in event_def.get("actions", []):
			if action.get("type") in ["heal", "damage"]:
				print("HP 事件将在回合开始时触发，跳过待机触发: ", event_id)
				return

	func_config["triggered"] = true
	func_config["triggered_by_unit"] = unit

	await EventManager.trigger_event(event_id, unit)

	if EventManager.is_event_completed(event_id):
		func_config["triggered"] = true
	else:
		func_config["triggered"] = false
		func_config["triggered_by_unit"] = null

# ===================== 道具列表 =====================
func _on_item_list_btn_pressed():
	if setting_menu_panel.visible:
		setting_menu_panel.visible = false
	if team_view_panel.visible:
		team_view_panel.visible = false
	item_list_panel.visible = not item_list_panel.visible
	if item_list_panel.visible:
		_refresh_item_list()

func _refresh_item_list():
	item_list_panel.size = Vector2(120, 20)
	for child in item_list_container.get_children():
		child.queue_free()

	item_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var parent = item_list_container.get_parent()
	var scroll = parent as ScrollContainer
	if not scroll:
		scroll = _create_scroll_container(item_list_container, parent, "ItemListScroll")
	scroll.size = item_list_panel.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var entries = []
	var global_items = ItemManager.get_all_items()
	for item_id in global_items:
		var data = ItemManager.get_item_data(item_id)
		if data:
			entries.append({
				"item_id": item_id,
				"source": "仓库",
				"count": global_items[item_id],
				"is_weapon": (data.type == "weapon"),
				"is_equipped": false
			})

	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			var unit_name = unit.unit_stats.unit_name
			var item_counts = {}
			var weapon_entries = []
			for inst in unit.inventory:
				var data = ItemManager.get_item_data(inst.item_id)
				if not data:
					continue
				var is_equipped = (inst == unit.equipped_weapon_instance)
				if data.type == "weapon":
					weapon_entries.append({
						"item_id": inst.item_id,
						"source": unit_name,
						"count": 1,
						"is_weapon": true,
						"is_equipped": is_equipped
					})
				else:
					if inst.item_id in item_counts:
						item_counts[inst.item_id] += inst.count
					else:
						item_counts[inst.item_id] = inst.count
			for item_id in item_counts:
				entries.append({
					"item_id": item_id,
					"source": unit_name,
					"count": item_counts[item_id],
					"is_weapon": false,
					"is_equipped": false
				})
			entries.append_array(weapon_entries)

	if entries.is_empty():
		var label = Label.new()
		label.text = "没有道具"
		label.add_theme_font_size_override("font_size", 6)
		item_list_container.add_child(label)
	else:
		entries.sort_custom(func(a, b):
			if a["source"] != b["source"]:
				return a["source"] < b["source"]
			if a["is_weapon"] != b["is_weapon"]:
				return a["is_weapon"] and not b["is_weapon"]
			return a["item_id"] < b["item_id"]
		)

		for entry in entries:
			var item_id = entry["item_id"]
			var source = entry["source"]
			var count = entry["count"]
			var is_equipped = entry["is_equipped"]
			var data = ItemManager.get_item_data(item_id)
			if not data:
				continue

			var btn = Button.new()
			btn.icon = data.icon
			var type_display = ""
			if data.type == "weapon" and data.category != "":
				type_display = UnitDataManager.get_weapon_category_display(data.category)   # ← 修正处
			elif data.type != "":
				type_display = _get_type_display_name(data.type)
			var type_str = "[" + type_display + "]" if type_display != "" else ""
			var equipped_str = " [已装备]" if is_equipped else ""
			btn.text = data.name + " " + type_str + equipped_str + " x" + str(count) + " (" + source + ")"
			btn.add_theme_font_size_override("font_size", 6)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.clip_text = true
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

			if source != "仓库":
				var unit = null
				for u in UnitManager.unit_list:
					if u.unit_stats.team_id == 0 and u.hit_points > 0 and u.unit_stats.unit_name == source:
						unit = u
						break
				if unit:
					btn.pressed.connect(_on_item_list_unit_selected.bind(unit))
				else:
					btn.pressed.connect(_on_item_list_warehouse_selected)
			else:
				btn.pressed.connect(_on_item_list_warehouse_selected)

			item_list_container.add_child(btn)

	await get_tree().process_frame

	var viewport_size = get_viewport().get_visible_rect().size

	var max_panel_width = viewport_size.x * 0.4
	var min_panel_width = 120
	var content_width = min_panel_width
	for child in item_list_container.get_children():
		if child is Button:
			var w = child.size.x
			if w > content_width:
				content_width = w
	content_width += 16
	var panel_width = clamp(content_width, min_panel_width, max_panel_width)

	var content_height = item_list_container.get_minimum_size().y
	var padding = 16
	var max_height = viewport_size.y * 0.9
	var final_height = clamp(content_height + padding, 20, max_height)

	item_list_panel.size = Vector2(panel_width, final_height)
	scroll.size = item_list_panel.size
	item_list_container.size = scroll.size

func _on_equip_btn_pressed():
	InputManager.on_equip_button_pressed()

func _get_type_display_name(type: String) -> String:
	match type:
		"weapon": return "武器"
		"heal": return "回复"
		"cure": return "治愈"
		"buff": return "增益"
		"attack": return "攻击"
		_: return type

func _on_item_list_unit_selected(unit: Unit):
	item_list_panel.visible = false
	_on_team_member_selected(unit)

func _on_item_list_warehouse_selected():
	print("点击了仓库道具，暂无操作")

func _show_attack_highlight(cells: Dictionary, unit: Unit):
	var color = Color(0.7, 0.1, 0.2, 0.7)
	if unit and unit.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL:
		color = Color(0.2, 0.5, 0.8, 0.7)
	highlight_manager.show_move_highlight(cells, color, 1, true)

func _adjust_info_panel(label: Label, panel: PanelContainer):
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
	panel.visible = true

func _create_scroll_container(child: Control, parent: Node, container_name: String) -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.name = container_name
	scroll.anchors_preset = Control.PRESET_FULL_RECT
	scroll.offset_left = 0
	scroll.offset_top = 0
	scroll.offset_right = 0
	scroll.offset_bottom = 0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var idx = parent.get_index()
	parent.add_child(scroll)
	parent.move_child(scroll, idx)
	parent.remove_child(child)
	scroll.add_child(child)

	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_vertical = Control.SIZE_EXPAND_FILL

	return scroll
