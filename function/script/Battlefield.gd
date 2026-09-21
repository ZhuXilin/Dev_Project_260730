extends Node2D
class_name Battlefield

const BOSS_NODE_TYPE = 6

# ---- 导出变量 ----
@export var map_data : MapData = null
@export var transition_delay_before_fade : float = 1.0
@export var transition_delay_after_fade : float = 1.0

# ---- 节点引用 ----
@onready var action_menu : CanvasLayer = $ActionMenu
@onready var attack_btn : Button = $ActionMenu/ActionPanel/ButtonContainer/AttackBtn
@onready var move_btn : Button = $ActionMenu/ActionPanel/ButtonContainer/MoveBtn
@onready var equip_btn : Button = $ActionMenu/ActionPanel/ButtonContainer/EquipBtn
@onready var relic_view_btn: Button = $SettingLayer/SettingPanel/SettingContainer/RelicViewBtn
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
@onready var back_camp_btn: Button = $SettingLayer/SettingPanel/SettingContainer/BackCampBtn
@onready var setting_btn : Button = $SettingLayer/SettingPanel/SettingContainer/SettingBtn
@onready var setting_menu_panel : Panel = $SettingLayer/SettingMenuPanel
@onready var team_view_btn : Button = $SettingLayer/SettingPanel/SettingContainer/TeamViewBtn
@onready var team_view_panel : PanelContainer = $SettingLayer/TeamViewPanel
@onready var team_view_container : VBoxContainer = $SettingLayer/TeamViewPanel/TeamViewContainer
@onready var speed_indicator : Label = $SpeedLayer/SpeedIndicator
@onready var item_list_btn : Button = $SettingLayer/SettingPanel/SettingContainer/ItemListBtn
@onready var item_list_panel : PanelContainer = $SettingLayer/ItemListPanel
@onready var item_list_container : VBoxContainer = $SettingLayer/ItemListPanel/ItemListContainer
@onready var end_turn_button: Label = $EndTurnLayer/EndTurnButton
@onready var turn_count_label: Label = $TurnCountLayer/TurnCountIndicator
@onready var relic_icon_container = $RelicLayer/RelicIconContainer

const PERFORMANCE_DURATION : float = 0.5
const ItemGetPopupScene = preload(Config.PATHS.ITEM_GET_POPUP)

var map_grid_size : Vector2i = MapConst.DEFAULT_MAP_SIZE
var _initialized : bool = false
var _viewport_scale : float = 1.0
var _battle_start_event_id : String = ""
var _attack_indicator : TextureRect = null
var map_functions : Dictionary = {}
var _turn_changed_locked : bool = false
var is_non_combat_mode: bool = false
var non_combat_back_button: Button = null
var current_node_type: int = MapNode.NodeType.NORMAL
var _victory_processed: bool = false
var _detail_popup = null
var _is_reward_ui_active: bool = false
var _is_showing_relics: bool = false

func _ready():
	_victory_processed = false
	_is_reward_ui_active = false

	action_menu = get_node("ActionMenu")
	attack_btn = get_node("ActionMenu/ActionPanel/ButtonContainer/AttackBtn")
	move_btn = get_node("ActionMenu/ActionPanel/ButtonContainer/MoveBtn")
	equip_btn = get_node("ActionMenu/ActionPanel/ButtonContainer/EquipBtn")
	wait_btn = get_node("ActionMenu/ActionPanel/ButtonContainer/WaitBtn")
	victory_panel = get_node("VictoryLayer/VictoryPanel")
	victory_label = get_node("VictoryLayer/VictoryPanel/VictoryLabel")
	victory_button = get_node("VictoryLayer/VictoryPanel/VictoryButton")
	turn_overlay = get_node("TurnLayer/TurnRect")
	cursor_layer = get_node("CursorLayer")
	cursor = get_node("CursorLayer/Cursor")
	highlight_manager = $HighlightManager
	movement_animator = $MovementAnimator
	ui_manager = $UIManager
	turnlayer_manager = $TurnLayerManager
	camera_controller = $Camera2D
	menu_blocker = $MenuBlocker
	info_panel = $Info/InfoPanel
	info_text_label = $Info/InfoPanel/InfoTextLabel
	setting_panel = $SettingLayer/SettingPanel
	setting_btn = $SettingLayer/SettingPanel/SettingContainer/SettingBtn
	setting_menu_panel = $SettingLayer/SettingMenuPanel
	team_view_btn = $SettingLayer/SettingPanel/SettingContainer/TeamViewBtn
	team_view_panel = $SettingLayer/TeamViewPanel
	team_view_container = $SettingLayer/TeamViewPanel/TeamViewContainer
	speed_indicator = $SpeedLayer/SpeedIndicator
	item_list_btn = $SettingLayer/SettingPanel/SettingContainer/ItemListBtn
	item_list_panel = $SettingLayer/ItemListPanel
	item_list_container = $SettingLayer/ItemListPanel/ItemListContainer
	end_turn_button = $EndTurnLayer/EndTurnButton
	turn_count_label = $TurnCountLayer/TurnCountIndicator
	relic_view_btn = $SettingLayer/SettingPanel/SettingContainer/RelicViewBtn
	relic_icon_container = $RelicLayer/RelicIconContainer

	var node_list = {
		"action_menu": action_menu,
		"attack_btn": attack_btn,
		"move_btn": move_btn,
		"wait_btn": wait_btn,
		"victory_panel": victory_panel,
		"turn_overlay": turn_overlay,
		"cursor": cursor,
		"highlight_manager": highlight_manager,
		"menu_blocker": menu_blocker,
		"info_panel": info_panel,
		"setting_panel": setting_panel,
		"relic_view_btn": relic_view_btn,
		"relic_icon_container": relic_icon_container
	}
	for node_name in node_list:
		if not node_list[node_name]:
			print("警告：节点 '", node_name, "' 未找到！")

	setting_btn.pressed.connect(_on_setting_btn_pressed)
	equip_btn.pressed.connect(_on_equip_btn_pressed)
	item_list_btn.pressed.connect(_on_item_list_btn_pressed)
	SignalBus.non_combat_complete.connect(_on_non_combat_complete)
	if not UnitManager.unit_removed.is_connected(_on_unit_removed_for_vengeance):
		UnitManager.unit_removed.connect(_on_unit_removed_for_vengeance)

	_detail_popup = load(Config.PATHS.ITEM_DETAIL_POPUP).instantiate()
	add_child(_detail_popup)
	_detail_popup.visible = false

	if end_turn_button:
		end_turn_button.text = "鼠标中键结束回合"
		end_turn_button.visible = not is_non_combat_mode

	if relic_view_btn:
		relic_view_btn.pressed.connect(_on_relic_view_btn_pressed)

	if _initialized:
		return
	_initialized = true
	_init_cursor()

	team_view_panel.visible = false
	item_list_panel.visible = false
	setting_menu_panel.visible = false
	team_view_btn.pressed.connect(_on_team_view_btn_pressed)

	_attack_indicator = TextureRect.new()
	if cursor and cursor.texture:
		_attack_indicator.texture = cursor.texture
	else:
		print("警告：cursor.texture 无效，使用默认纹理")
	_attack_indicator.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	_attack_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_indicator.z_index = UIConst.ATTACK_INDICATOR_Z_INDEX
	_attack_indicator.visible = false
	add_child(_attack_indicator)

	if victory_panel:
		victory_panel.visible = false

	_initialize_managers()
	_connect_signals()

	if turn_overlay:
		turn_overlay.modulate = Color(1, 1, 1, 0)
		Globals.is_fading = false

	if GameState.current_map_data:
		var map_to_load = GameState.current_map_data
		if not map_to_load.scene:
			print("警告：当前地图数据无效，使用默认地图")
			_load_default_map()
		else:
			print("加载地图：", map_to_load.map_name)
			load_map(map_to_load)
	else:
		print("没有地图数据，加载默认地图")
		_load_default_map()

	if not map_data:
		var map_pixel_size = Vector2(map_grid_size.x * MapConst.CELL_SIZE, map_grid_size.y * MapConst.CELL_SIZE)
		if camera_controller:
			camera_controller.set_map_boundary(Rect2(Vector2.ZERO, map_pixel_size))

	if camera_controller:
		camera_controller.set_grid_size(MapConst.CELL_SIZE)
		var viewport_size = get_viewport().get_visible_rect().size
		camera_controller.set_edge_scroll_margin(viewport_size.x * 0.16)

	if action_menu:
		action_menu.visible = false
	if move_btn:
		move_btn.disabled = true
	if attack_btn:
		attack_btn.disabled = true
	if wait_btn:
		wait_btn.disabled = true
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
	_on_clear_highlight_unit()

	if menu_blocker:
		menu_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		menu_blocker.visible = false
		menu_blocker.gui_input.connect(_on_menu_blocker_clicked)
		menu_blocker.size = Vector2(map_grid_size.x * MapConst.CELL_SIZE, map_grid_size.y * MapConst.CELL_SIZE)
		menu_blocker.position = Vector2.ZERO
		menu_blocker.z_index = UIConst.MENU_BLOCKER_Z_INDEX

	var is_non_combat = GameState.current_map_data and GameState.current_map_data.node_type in [
		MapNode.NodeType.SHOP,
		MapNode.NodeType.EVENT,
		MapNode.NodeType.FORGE,
	]

	if is_non_combat:
		await _setup_non_combat_mode()
		await get_tree().process_frame

		if back_camp_btn:
			for conn in back_camp_btn.pressed.get_connections():
				back_camp_btn.pressed.disconnect(conn.callable)
			back_camp_btn.pressed.connect(_on_back_camp_pressed)
			back_camp_btn.text = "回到营地"
			print("BackCampBtn 已连接（非战斗）")

		TurnManager.start_turn(TurnManager.Team.PLAYER)
		_update_relic_icons()
		return

	if _battle_start_event_id != "":
		print("检测到战斗开始事件：", _battle_start_event_id)
		var music = MusicManager.config.battle_start_dialogue_music if MusicManager.config else null
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

	if MusicManager:
		MusicManager.stop_music()
		MusicManager._saved_stream = null
		MusicManager._saved_position = 0.0

	await get_tree().process_frame
	print("=== 准备启动玩家回合 ===")
	TurnManager.start_turn(TurnManager.Team.PLAYER)
	print("=== TurnManager.start_turn(0) 调用完成 ===")
	_update_end_turn_button_visibility()

	print("back_camp_btn: ", back_camp_btn)
	if back_camp_btn:
		print("back_camp_btn 已获取")
		for conn in back_camp_btn.pressed.get_connections():
			back_camp_btn.pressed.disconnect(conn.callable)
		back_camp_btn.pressed.connect(_on_back_camp_pressed)
		back_camp_btn.text = "回到营地"
		print("BackCampBtn 已连接")
	InputManager.ui_manager = ui_manager

	_update_relic_icons()

	_victory_processed = false
	_is_reward_ui_active = false
	_apply_team_buffs()
	print("Battlefield _ready 完成")

func _on_unit_removed_for_vengeance(unit: Unit, team: int):
	# 复仇：玩家单位死亡时，其他玩家单位攻击力 +30%（每单位每场只触发一次）
	if team != 0:
		return
	if not is_instance_valid(unit):
		return
	for u in UnitManager.unit_list:
		if not is_instance_valid(u):
			continue
		if u.unit_stats.team_id != 0:
			continue
		if u == unit:
			continue
		if u.vengeance_triggered:
			continue
		var inst = u.get_talent_instance("vengeance")
		if inst and inst.is_active:
			u.buff_attack_percent += 0.30
			u.vengeance_triggered = true
			print("[复仇] %s 攻击力 +30%%（本场只触发一次）" % u.unit_stats.unit_name)

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

	if InputManager.ui_manager == ui_manager:
		InputManager.ui_manager = null
	if InputManager.selected_unit != null:
		InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	InputManager.pending_attack_cells = {}
	InputManager.current_move_attack_targets = {}

# ===================== 主循环 =====================
func _process(_delta):
	var should_pause = (
		action_menu.visible or
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

func _physics_process(_delta):
	_update_cursor_and_mouse()

# ===================== 光标初始化 =====================
func _init_cursor():
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	cursor.visible = true
	if cursor.texture == null:
		var path = Config.PATHS.CURSOR_TEXTURE
		if ResourceLoader.exists(path):
			cursor.texture = load(path)
		else:
			push_error("光标图片不存在：", path)
	_viewport_scale = _get_viewport_scale()
	var target_size = round(MapConst.CELL_SIZE * _viewport_scale)
	cursor.size = Vector2(target_size, target_size)
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _get_viewport_scale() -> float:
	var viewport = get_viewport()
	var canvas_transform = viewport.get_canvas_transform()
	var scale_value = canvas_transform.get_scale()
	return scale_value.x

# ===================== 地图加载 =====================
func load_map(new_map_data: MapData):
	print("=== load_map 被调用 ===")
	if not new_map_data:
		print("地图数据为空，加载默认地图")
		_load_default_map()
		return

	print("地图名称：", new_map_data.map_name)
	GameState.current_map_data = new_map_data
	current_node_type = new_map_data.node_type

	var map_pixel_rect: Rect2
	var tilemap: TileMapLayer = null
	var main_scene_instance: Node = null
	var used_rect: Rect2i = Rect2i()
	var spawn_points: Array[Vector2i] = []

	if new_map_data.scene:
		var scene_path = new_map_data.scene.resource_path
		print("加载场景：", scene_path)

		var scene = load(scene_path) as PackedScene
		if scene:
			main_scene_instance = scene.instantiate()
			if main_scene_instance:
				tilemap = _find_tilemap(main_scene_instance)
				if tilemap:
					_remove_old_terrain()

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

					spawn_points = _extract_spawn_points(main_scene_instance)
					if spawn_points.size() > 0:
						print("提取到出生点：", spawn_points)
				else:
					print("错误：场景中未找到 TileMapLayer，使用默认地形")
					if main_scene_instance:
						main_scene_instance.queue_free()
						main_scene_instance = null
			else:
				print("错误：无法实例化场景：", scene_path)
		else:
			print("错误：无法加载场景文件：", scene_path)

	if not tilemap:
		_remove_old_terrain()

		_generate_default_terrain(new_map_data.map_size)
		used_rect = Rect2i(Vector2i.ZERO, map_grid_size)
		map_pixel_rect = Rect2(Vector2.ZERO, new_map_data.map_size * MapConst.CELL_SIZE)
		menu_blocker.size = new_map_data.map_size * MapConst.CELL_SIZE
		menu_blocker.position = Vector2.ZERO
	else:
		map_pixel_rect = Rect2(
			used_rect.position * MapConst.CELL_SIZE,
			used_rect.size * MapConst.CELL_SIZE
		)
		menu_blocker.size = used_rect.size * MapConst.CELL_SIZE
		menu_blocker.position = used_rect.position * MapConst.CELL_SIZE

	_clear_units()

	var configs: Array[UnitConfig] = []
	if main_scene_instance:
		configs = UnitSpawner.extract_configs_from_node(main_scene_instance)
	if configs.size() > 0:
		print("从场景提取到 ", configs.size(), " 个固定单位")
		UnitSpawner.spawn_units_from_configs(self, configs, grid_to_world)
	else:
		print("场景中没有固定单位配置")

	if GameState.party.size() > 0 and spawn_points.size() > 0:
		print("使用队伍数据生成单位，队伍大小：", GameState.party.size(), "，出生点数：", spawn_points.size())
		UnitSpawner.spawn_party_from_gamestate(self, grid_to_world, spawn_points)
	else:
		if GameState.party.size() == 0:
			print("队伍为空")
		if spawn_points.size() == 0:
			print("没有出生点")

	if UnitManager.unit_list.is_empty():
		print("没有任何单位，生成测试单位")
		UnitSpawner.spawn_test_units(self, grid_to_world)

	for unit in UnitManager.unit_list:
		unit.position = grid_to_world(unit.grid_cell)
		unit.z_index = 1

	menu_blocker.z_index = 2
	camera_controller.set_map_boundary(map_pixel_rect)
	print("地图边界（像素）:", map_pixel_rect)

	_center_camera_on_player()
	TurnManager.map_functions = map_functions
	print("地图加载完成：", new_map_data.map_name)

func _create_fallback_map_data() -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	map.map_size = MapConst.DEFAULT_MAP_SIZE
	var cfg = UnitConfig.new()
	cfg.unit_name = "剑士"
	cfg.team_id = 0
	cfg.position = Vector2i(10, 10)
	var enemy_cfg = UnitConfig.new()
	enemy_cfg.unit_name = "斧兵"
	enemy_cfg.team_id = 1
	enemy_cfg.position = Vector2i(5, 5)
	return map

func _create_flat_terrain(size: Vector2i):
	push_warning("没有地形数据，所有格子视为平地")
	map_grid_size = size
	TerrainManager.grid_size = size
	var grid = []
	for y in range(size.y):
		var row = []
		for x in range(size.x):
			row.append(TerrainManager.TerrainType.PLAIN)
		grid.append(row)
	TerrainManager.terrain_grid = grid

func _extract_map_unit_placers(node: Node):
	map_functions.clear()
	var battle_start_event = ""
	var tool_nodes: Array[Node] = []

	_find_tools(node, tool_nodes)

	for tool in tool_nodes:
		var cfg = tool.export_config()
		var cell: Vector2i
		if cfg is Dictionary:
			if cfg.has("position"):
				cell = cfg["position"]
			else:
				continue
		else:
			continue

		var entry = {"triggered": false}

		match cfg.get("type", ""):
			"event_trigger":
				var event_id = cfg.get("event_id", "")
				if event_id != "":
					entry["event_id"] = event_id
					map_functions[cell] = entry
					print("功能格: 位置 ", cell, " 事件ID: ", event_id)

			"hp_function":
				var amount = cfg.get("hp_amount", 0)
				if amount != 0:
					var generated_id = "hp_%d_%d" % [cell.x, cell.y]
					var action_type = "heal" if amount > 0 else "damage"
					var actions = [{ "type": action_type, "amount": amount }]
					EventManager.register_event(generated_id, { "actions": actions, "once": false })
					entry["event_id"] = generated_id
					map_functions[cell] = entry
					print("功能格: 位置 ", cell, " HP事件: ", generated_id)

			"battle_start":
				var event_id = cfg.get("event_id", "")
				if event_id != "":
					battle_start_event = event_id
					print("战斗开始事件: ", event_id)

			_:
				pass

	_battle_start_event_id = battle_start_event
	print("共提取 ", map_functions.size(), " 个功能格，战斗开始事件: ", battle_start_event)

	for tool in tool_nodes:
		if is_instance_valid(tool):
			tool.queue_free()

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
		camera_controller.smooth_move_to(target_pos, 0.0, true)
	else:
		var viewport_size = get_viewport().get_visible_rect().size
		var center = camera_controller.map_rect.position + camera_controller.map_rect.size / 2
		var target_pos = center - viewport_size / 2
		target_pos = camera_controller.clamp_position(target_pos)
		camera_controller.smooth_move_to(target_pos, 0.0, true)

func _load_default_map():
	print("加载默认测试地图")
	var default_map = MapData.new()
	default_map.map_name = "默认地图"
	default_map.scene = null
	default_map.map_size = MapConst.DEFAULT_MAP_SIZE
	load_map(default_map)

func _clear_units():
	for child in get_children():
		if child is Unit:
			UnitManager.unregister_unit(child)
			child.queue_free()

func _remove_old_terrain():
	var old = get_node_or_null("TerrainTileMap")
	if old:
		remove_child(old)
		old.free()
		print("已清理旧地形节点")

func _find_tilemap(node: Node) -> TileMapLayer:
	if not node:
		return null
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
		"victory_panel": victory_panel,
		"victory_label": victory_label,
		"victory_button": victory_button,
	})
	highlight_manager.initialize(self)
	turnlayer_manager.initialize(turn_overlay)
	InputManager.ui_manager = ui_manager

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

	if SignalBus.request_highlight.is_connected(_on_highlight_request):
		SignalBus.request_highlight.disconnect(_on_highlight_request)
	SignalBus.request_highlight.connect(_on_highlight_request)

	if SignalBus.request_clear_highlight.is_connected(highlight_manager.clear_highlight):
		SignalBus.request_clear_highlight.disconnect(highlight_manager.clear_highlight)
	SignalBus.request_clear_highlight.connect(highlight_manager.clear_highlight)

	if SignalBus.request_move_unit.is_connected(_on_instant_move):
		SignalBus.request_move_unit.disconnect(_on_instant_move)
	SignalBus.request_move_unit.connect(_on_instant_move)

	if SignalBus.request_move_along_path.is_connected(_on_request_move_along_path):
		SignalBus.request_move_along_path.disconnect(_on_request_move_along_path)
	SignalBus.request_move_along_path.connect(_on_request_move_along_path)

	if SignalBus.request_ai_move_along_path.is_connected(_on_ai_move_along_path):
		SignalBus.request_ai_move_along_path.disconnect(_on_ai_move_along_path)
	SignalBus.request_ai_move_along_path.connect(_on_ai_move_along_path)

	if SignalBus.request_show_menu.is_connected(_on_request_show_menu):
		SignalBus.request_show_menu.disconnect(_on_request_show_menu)
	SignalBus.request_show_menu.connect(_on_request_show_menu)

	if SignalBus.request_hide_menu.is_connected(ui_manager.hide_menu):
		SignalBus.request_hide_menu.disconnect(ui_manager.hide_menu)
	SignalBus.request_hide_menu.connect(ui_manager.hide_menu)

	if SignalBus.request_show_victory.is_connected(_on_request_show_victory):
		SignalBus.request_show_victory.disconnect(_on_request_show_victory)
	SignalBus.request_show_victory.connect(_on_request_show_victory)

	if SignalBus.turn_changed.is_connected(_on_turn_changed):
		SignalBus.turn_changed.disconnect(_on_turn_changed)
	SignalBus.turn_changed.connect(_on_turn_changed)

	if SignalBus.request_highlight_unit.is_connected(_on_highlight_unit):
		SignalBus.request_highlight_unit.disconnect(_on_highlight_unit)
	SignalBus.request_highlight_unit.connect(_on_highlight_unit)

	if SignalBus.request_clear_highlight_unit.is_connected(_on_clear_highlight_unit):
		SignalBus.request_clear_highlight_unit.disconnect(_on_clear_highlight_unit)
	SignalBus.request_clear_highlight_unit.connect(_on_clear_highlight_unit)

	if SignalBus.request_screen_shake.is_connected(_on_request_screen_shake):
		SignalBus.request_screen_shake.disconnect(_on_request_screen_shake)
	SignalBus.request_screen_shake.connect(_on_request_screen_shake)

	if SignalBus.request_damage_popup.is_connected(_on_request_damage_popup):
		SignalBus.request_damage_popup.disconnect(_on_request_damage_popup)
	SignalBus.request_damage_popup.connect(_on_request_damage_popup)

	if SignalBus.request_show_info.is_connected(_on_request_show_info):
		SignalBus.request_show_info.disconnect(_on_request_show_info)
	SignalBus.request_show_info.connect(_on_request_show_info)

	if SignalBus.request_hide_info.is_connected(_on_request_hide_info):
		SignalBus.request_hide_info.disconnect(_on_request_hide_info)
	SignalBus.request_hide_info.connect(_on_request_hide_info)

	if SignalBus.request_show_setting.is_connected(_on_request_show_setting):
		SignalBus.request_show_setting.disconnect(_on_request_show_setting)
	SignalBus.request_show_setting.connect(_on_request_show_setting)

	if SignalBus.request_hide_setting.is_connected(_on_request_hide_setting):
		SignalBus.request_hide_setting.disconnect(_on_request_hide_setting)
	SignalBus.request_hide_setting.connect(_on_request_hide_setting)

	if SignalBus.speed_changed.is_connected(_on_speed_changed):
		SignalBus.speed_changed.disconnect(_on_speed_changed)
	SignalBus.speed_changed.connect(_on_speed_changed)

	if SignalBus.request_show_enemy_preview.is_connected(_on_show_enemy_preview):
		SignalBus.request_show_enemy_preview.disconnect(_on_show_enemy_preview)
	SignalBus.request_show_enemy_preview.connect(_on_show_enemy_preview)

	_on_speed_changed(Globals.game_speed)

	if movement_animator.movement_finished.is_connected(_on_player_movement_finished):
		movement_animator.movement_finished.disconnect(_on_player_movement_finished)
	movement_animator.movement_finished.connect(_on_player_movement_finished)

	if movement_animator.ai_movement_finished.is_connected(_on_ai_movement_finished):
		movement_animator.ai_movement_finished.disconnect(_on_ai_movement_finished)
	movement_animator.ai_movement_finished.connect(_on_ai_movement_finished)

# ===================== 信号回调 =====================
func _on_highlight_request(cells: Dictionary):
	match InputManager.interaction_phase:
		InputManager.Phase.MOVING:
			if cells == InputManager.current_highlight_cells:
				highlight_manager.show_move_highlight(cells, MapConst.HIGHLIGHT_MOVE, 0, true)
			else:
				var unit = InputManager.selected_unit
				var preview_color = MapConst.HIGHLIGHT_ATTACK
				if unit and unit.get_weapon_type() == "staff":
					preview_color = MapConst.HIGHLIGHT_HEAL
				highlight_manager.show_move_highlight(cells, preview_color, 1, false)
		InputManager.Phase.ATTACKING:
			var unit = InputManager.selected_unit
			var color = MapConst.HIGHLIGHT_ATTACK
			if unit and unit.get_weapon_type() == "staff":
				color = MapConst.HIGHLIGHT_HEAL
			highlight_manager.show_move_highlight(cells, color, 1, true)
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
	if map_functions.has(cell):
		var func_config = map_functions[cell]
		var event_id = func_config.get("event_id", "")
		if event_id != "" and not event_id.begins_with("hp_") and not EventManager.is_event_completed(event_id):
			SoundManager.play_select_sound()
			func_config["triggered"] = true
			func_config["triggered_by_unit"] = unit
			await EventManager.trigger_event(event_id, unit)
			if EventManager.is_event_completed(event_id):
				func_config["triggered"] = true
			else:
				func_config["triggered"] = false
				func_config["triggered_by_unit"] = null
			unit.can_act_this_turn = false
			unit.set_gray(true)
			TurnManager.finish_unit_action(unit)
			return

	InputManager.on_wait_button_pressed()

func _on_request_show_victory(winning_team: int):
	print("=== _on_request_show_victory 被调用, _victory_processed: ", _victory_processed)
	await _wait_for_ui_clear()

	if _victory_processed:
		print("胜利已处理，跳过重复调用")
		return
	_victory_processed = true
	print("胜利处理开始")

	var tree = get_tree()
	if not tree:
		print("错误：无法获取场景树，无法处理胜利")
		_victory_processed = false
		return

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
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	InputManager.current_move_attack_targets = {}

	var is_win = (winning_team == 0)
	var is_last = LevelManager.is_last_level()

	var is_boss = (current_node_type == MapNode.NodeType.BOSS)
	if not is_boss and GameState.current_map_data:
		is_boss = (GameState.current_map_data.node_type == MapNode.NodeType.BOSS)
	print("is_boss 判断结果：", is_boss, " current_node_type=", current_node_type)

	var player_units = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0:
			player_units.append(unit)
	GameState.sync_units_from_battlefield(player_units)

	# ============================================================
	# 地图模式
	# ============================================================
	if Globals.is_map_mode:
		print("当前地图节点类型: ", current_node_type, " 是否为BOSS: ", is_boss)

		if is_win:
			var is_non_combat_node = current_node_type in [
				MapNode.NodeType.SHOP,
				MapNode.NodeType.EVENT,
				MapNode.NodeType.FORGE,
			]

			if not is_non_combat_node:
				var reward = EconomyManager.get_battle_reward(current_node_type, is_boss)
				var gold_gain = reward.gold
				var soul_gain = reward.soul
				var materials = reward.materials

				print("--- 奖励配置 ---")
				print("gold_gain: ", gold_gain)
				print("soul_gain: ", soul_gain)
				print("materials: ", materials)

				GameState.current_reward_gold = gold_gain
				GameState.current_reward_soul = soul_gain
				GameState.current_reward_materials = materials

				EconomyManager.add_temp_gold(gold_gain)
				EconomyManager.add_temp_soul(soul_gain)
				EconomyManager.apply_material_reward(materials)

				print("--- 资源累加完成 ---")
				print("temp_gold: ", GameState.temp_gold)
				print("temp_soul: ", GameState.temp_soul)
				print("materials: ", GameState.materials)
			else:
				print("非战斗地图，不累加资源")
				GameState.current_reward_gold = 0
				GameState.current_reward_soul = 0
				GameState.current_reward_materials = {}

		if is_win and is_boss:
			GameState.should_advance_day = true

		SignalBus.battle_completed.emit(winning_team, is_boss)

		if is_win:
			if is_last:
				MusicManager.play_win_game_music()
			else:
				MusicManager.play_victory_music()
		else:
			MusicManager.play_defeat_music()

		if is_instance_valid(ui_manager):
			if is_win:
				if is_last:
					ui_manager.show_victory("全部胜利！", "回到营地", self._on_map_victory_continue)
				else:
					ui_manager.show_victory("战斗胜利！", "继续旅程", self._on_map_victory_continue)
			else:
				ui_manager.show_victory("战斗失败", "重启旅程", self._on_map_defeat_gameover)
		else:
			if is_win:
				tree.change_scene_to_file(Config.PATHS.MAP_SCENE)
			else:
				GameState.reset_all()
				tree.change_scene_to_file(Config.PATHS.UNIT_SELECT_UI)
		return

	# ============================================================
	# 非地图模式
	# ============================================================
	print("非地图模式（旧版流程）")
	if is_win and is_last:
		MusicManager.play_win_game_music()
	elif is_win:
		MusicManager.play_victory_music()
	else:
		MusicManager.play_defeat_music()

	if is_win:
		if is_last:
			ui_manager.show_victory("全部胜利", "回到营地", LevelManager.on_victory)
		else:
			ui_manager.show_victory("战斗胜利", "下一关", LevelManager.on_victory)
	else:
		ui_manager.show_victory("战斗失败", "回到营地", self._on_non_map_defeat)

func _on_turn_changed(team: int):
	print("连接数: ", SignalBus.turn_changed.get_connections().size())
	await _wait_for_ui_clear()
	_handle_turn_change_async(team)

func _handle_turn_change_async(team: int):
	if team == TurnManager.Team.PLAYER:
		print("玩家回合开始，递增前计数: ", Globals.current_battle_turn)
		Globals.increment_battle_turn()
		turn_count_label.text = "第 " + str(Globals.current_battle_turn) + " 回合"
		print("玩家回合开始，递增后计数: ", Globals.current_battle_turn)
	if TurnManager.is_game_over:
		return
	if _turn_changed_locked:
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
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}

	MusicManager.stop_music()

	if team == TurnManager.Team.PLAYER:
		Globals.increment_battle_turn()

	await get_tree().create_timer(transition_delay_before_fade, true, false, true).timeout
	await turnlayer_manager.play_transition(team)
	await get_tree().create_timer(transition_delay_after_fade, true, false, true).timeout

	print("回合切换：", "玩家" if team == TurnManager.Team.PLAYER else "敌人")

	var target_pos = null
	if team == TurnManager.Team.PLAYER:
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

	if not is_non_combat_mode:
		var is_boss = GameState.current_map_data and GameState.current_map_data.node_type == MapNode.NodeType.BOSS
		if is_boss:
			if team == TurnManager.Team.PLAYER:
				if MusicManager.config and MusicManager.config.boss_player_turn_music:
					MusicManager.play_music(MusicManager.config.boss_player_turn_music)
				else:
					MusicManager.play_player_turn_music()
			else:
				if MusicManager.config and MusicManager.config.boss_enemy_turn_music:
					MusicManager.play_music(MusicManager.config.boss_enemy_turn_music)
				else:
					MusicManager.play_enemy_turn_music()
		else:
			if team == TurnManager.Team.PLAYER:
				MusicManager.play_player_turn_music()
			else:
				MusicManager.play_enemy_turn_music()
	else:
		var music_stream = null
		if MusicManager.config and MusicManager.config.non_combat_music:
			music_stream = MusicManager.config.non_combat_music
		elif MusicManager.config and MusicManager.config.map_music:
			music_stream = MusicManager.config.map_music
		if music_stream:
			var player = MusicManager.player
			if not player.playing or player.stream != music_stream:
				MusicManager.play_music(music_stream)

	await apply_map_functions(team)
	_update_relic_icons()
	Globals.is_transitioning = false
	_turn_changed_locked = false

	if team == TurnManager.Team.ENEMY and not is_non_combat_mode:
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
	var target_size = MapConst.CELL_SIZE * _viewport_scale
	_attack_indicator.size = Vector2(target_size, target_size)
	var world_pos = grid_to_world(unit.grid_cell)
	_attack_indicator.position = world_pos - _attack_indicator.size / 2
	_attack_indicator.visible = true

func _on_clear_highlight_unit():
	if _attack_indicator:
		_attack_indicator.visible = false

# ===================== 输入处理 =====================
func _input(event: InputEvent):
	if Globals.is_equip_menu_active:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			Globals.suppress_sound = true
			ui_manager.hide_equip_menu()
			get_viewport().set_input_as_handled()
			if InputManager.selected_unit:
				InputManager.interaction_phase = InputManager.Phase.MENU
				SignalBus.request_show_menu.emit(InputManager.selected_unit)
		return

	if Globals.is_dialogue_active or Globals.is_item_get_popup_active:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		if TurnManager.current_turn_team == TurnManager.Team.PLAYER and not Globals.is_fading and not Globals.is_transitioning and not Globals.is_dialogue_active:
			_end_player_turn()
			return

	if Globals.is_transitioning or Globals.is_fading:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if (Globals.is_equip_menu_active or
				setting_panel.visible or
				setting_menu_panel.visible or
				team_view_panel.visible or
				item_list_panel.visible or
				InputManager.interaction_phase in [InputManager.Phase.MOVING, InputManager.Phase.ATTACKING]):
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
			if action_menu.visible:
				return
			var mouse_pos = get_global_mouse_position()
			var clicked_cell = world_to_grid(mouse_pos)
			InputManager.handle_click(clicked_cell)
	else:
		InputManager.handle_input(event, map_grid_size, MapConst.CELL_SIZE)

	if Globals.is_equip_menu_active:
		return

# ===================== UI回调 =====================
func _on_request_show_menu(unit: Unit):
	if TurnManager.is_game_over or TurnManager.current_turn_team != TurnManager.Team.PLAYER or TurnManager.all_acted:
		return
	if not unit or not is_instance_valid(unit) or unit.hit_points <= 0:
		print("单位已死亡，不显示菜单")
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
	InputManager.interaction_phase = InputManager.Phase.MENU

	ui_manager.show_menu(unit)

	if is_instance_valid(menu_blocker):
		menu_blocker.visible = true
		menu_blocker.z_index = UIConst.MENU_BLOCKER_Z_INDEX

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

	if is_instance_valid(move_btn):
		var can_move = false
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
		InputManager.interaction_phase = InputManager.Phase.IDLE

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
	return Vector2(cell.x * MapConst.CELL_SIZE + MapConst.CELL_SIZE / 2.0, cell.y * MapConst.CELL_SIZE + MapConst.CELL_SIZE / 2.0)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / MapConst.CELL_SIZE), floor(world_pos.y / MapConst.CELL_SIZE))

# ===================== 其他信号 =====================
func _on_request_screen_shake(duration: float, intensity: float, direction: Vector2 = Vector2.ZERO):
	var shake_node = $Camera2D.get_node_or_null("ScreenShake") as ScreenShake
	if shake_node:
		shake_node.shake(duration, intensity, direction)

func _on_request_damage_popup(world_pos: Vector2, damage: int, is_crit: bool, is_miss: bool, is_heal: bool):
	var popup = preload(Config.PATHS.DAMAGE_POPUP_SCRIPT).new()
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

		var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
		var type_name = UnitDataManager.get_unit_type_display_name(unit.unit_stats.unit_name)
		lines.append(display_name + "|" + unit.unit_stats.faction + "|" + type_name)

		lines.append("HP: " + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp))

		var weapon_data = unit.get_weapon_data()
		if weapon_data:
			lines.append("武器: " + weapon_data.name)
			var stats = weapon_data.stats
			var attrs = []
			if stats.has("attack"):
				attrs.append("攻击+" + str(stats["attack"]))
			if stats.has("magic_attack"):
				attrs.append("魔法+" + str(stats["magic_attack"]))
			if stats.has("heal_amount"):
				attrs.append("治疗+" + str(stats["heal_amount"]))
			if attrs.size() > 0:
				lines.append("武器属性: " + ", ".join(attrs))
			lines.append("射程: " + str(weapon_data.min_attack_range) + "~" + str(weapon_data.attack_range))
		else:
			lines.append("武器: 无")

		var armor_slots = unit.get_armor_slots()
		var armor_str = ""
		for i in range(armor_slots.size()):
			var inst = armor_slots[i]
			if inst:
				var data = ItemManager.get_item_data(inst.item_id)
				if data:
					armor_str += "槽" + str(i+1) + ":" + data.name + " "
				else:
					armor_str += "槽" + str(i+1) + ":(?) "
			else:
				armor_str += "槽" + str(i+1) + ":(空) "
		if armor_str != "":
			lines.append("防具: " + armor_str.strip_edges())

		lines.append("力量: " + str(unit.unit_stats.strength))
		lines.append("敏捷: " + str(unit.unit_stats.dexterity))
		lines.append("智力: " + str(unit.unit_stats.intelligence))
		lines.append("信仰: " + str(unit.unit_stats.faith))
		lines.append("感应: " + str(unit.unit_stats.arcane))

		var cell = unit.grid_cell
		terrain_type = TerrainManager.get_terrain(cell)
		terrain_name = TerrainManager.get_terrain_name(terrain_type)
		lines.append("地形: " + terrain_name)

		display_text = "\n".join(lines)

	info_text_label.text = display_text
	_adjust_info_panel(info_text_label, info_panel)

func _on_request_hide_info():
	info_panel.visible = false

func _on_request_show_setting():
	setting_panel.visible = true
	_update_end_turn_button_visibility()

func _on_request_hide_setting():
	setting_panel.visible = false
	team_view_panel.visible = false
	item_list_panel.visible = false
	setting_menu_panel.visible = false
	_update_end_turn_button_visibility()

func _on_team_view_btn_pressed():
	if setting_menu_panel.visible:
		setting_menu_panel.visible = false
	if item_list_panel.visible:
		item_list_panel.visible = false
	team_view_panel.visible = not team_view_panel.visible
	if team_view_panel.visible:
		_refresh_team_view()

func _refresh_team_view():
	for child in team_view_container.get_children():
		child.queue_free()

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

			var full_name = UnitDataManager.get_display_name_from_unit(unit)
			btn.text = full_name + " HP:" + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp) + status
			# ★ 词条状态
			var talent_line = _format_unit_talents(unit)
			if talent_line != "":
				btn.text += "  [ " + talent_line + " ]"
			btn.add_theme_font_size_override("font_size", 6)
			if color != Color.WHITE:
				btn.add_theme_color_override("font_color", color)
			btn.pressed.connect(_on_team_member_selected.bind(unit))
			team_view_container.add_child(btn)

	var parent = team_view_container.get_parent()
	var scroll = parent as ScrollContainer
	if not scroll:
		scroll = _create_scroll_container(team_view_container, parent, "TeamViewScroll")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	await get_tree().process_frame
	var content_height = team_view_container.get_minimum_size().y
	var viewport_height = get_viewport().get_visible_rect().size.y
	var max_height = viewport_height * 0.8
	var panel_height = clamp(content_height + 16, 20, max_height)
	team_view_panel.size.y = panel_height

func _format_unit_talents(unit: Unit) -> String:
	var parts: Array = []
	for inst in unit.talent_slots:
		if not inst or not inst.is_active:
			continue
		var data = TalentManager.get_talent_data(inst.talent_id)
		if not data:
			continue
		var status := ""

		# 复仇是永久被动，不显示状态
		if inst.talent_id == "vengeance":
			status = ""
		# 主动技能：CD 或就绪
		elif data.is_active_skill:
			if inst.is_ready:
				status = "(就绪★)"
			else:
				status = "(冷%d)" % inst.cooldown_remaining
		# R 词条
		elif inst.cooldown_remaining >= 9999:
			status = "(R)"
		elif inst.cooldown_remaining > 0:
			status = "(冷%d)" % inst.cooldown_remaining
		elif inst.is_ready:
			status = "(就绪)"
		else:
			var remain = max(0, data.accumulation_threshold - inst.current_stack)
			status = "(%d)" % remain

		if status == "":
			parts.append(data.display_name)
		else:
			parts.append(data.display_name + status)
	return " ".join(parts)

func _on_team_member_selected(unit: Unit):
	setting_menu_panel.visible = false
	team_view_panel.visible = false
	SignalBus.request_hide_setting.emit()
	SignalBus.request_hide_info.emit()

	InputManager.selected_unit = unit
	if unit.can_act_this_turn and unit.hit_points > 0:
		InputManager.interaction_phase = InputManager.Phase.MENU
		SignalBus.request_show_menu.emit(unit)
	else:
		InputManager.interaction_phase = InputManager.Phase.IDLE

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

	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			var unit_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name

			var weapon = unit.get_weapon()
			if weapon:
				var data = ItemManager.get_item_data(weapon.item_id)
				if data:
					var type_display = ""
					if data.category != "":
						type_display = UnitDataManager.get_weapon_category_display(data.category)
					else:
						type_display = _get_type_display_name(data.type)
					entries.append({
						"item_name": data.name,
						"type_display": type_display,
						"source": unit_name,
						"slot": "武器",
						"is_equipped": true,
						"data": data
					})

			var armor_slots = unit.get_armor_slots()
			for i in range(armor_slots.size()):
				var inst = armor_slots[i]
				if inst:
					var data = ItemManager.get_item_data(inst.item_id)
					if data:
						entries.append({
							"item_name": data.name,
							"type_display": "",
							"source": unit_name,
							"slot": "防具槽" + str(i+1),
							"is_equipped": true,
							"data": data
						})

	if entries.is_empty():
		var label = Label.new()
		label.text = "没有装备"
		label.add_theme_font_size_override("font_size", 6)
		item_list_container.add_child(label)
	else:
		entries.sort_custom(func(a, b):
			if a["source"] != b["source"]:
				return a["source"] < b["source"]
			return a["slot"] < b["slot"]
		)

		for entry in entries:
			var btn = Button.new()
			var data = entry["data"]
			if data.icon:
				btn.icon = data.icon

			var equipped_str = " [已装备]" if entry["is_equipped"] else ""
			var type_str = "[" + entry["type_display"] + "]" if entry["type_display"] != "" else ""
			btn.text = entry["item_name"] + " " + type_str + equipped_str + " (" + entry["source"] + " " + entry["slot"] + ")"
			btn.add_theme_font_size_override("font_size", 6)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.clip_text = true
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			btn.disabled = true

			btn.mouse_entered.connect(_on_item_hover_entered.bind(entry["data"].id))
			btn.mouse_exited.connect(_on_item_hover_exited)

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

func _on_item_hover_entered(item_id: String):
	show_item_detail(item_id)

func _on_item_hover_exited():
	hide_item_detail()

func _find_unit_by_name(display_name: String) -> Unit:
	for unit in UnitManager.unit_list:
		var unit_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
		if unit_name == display_name:
			return unit
	return null

func _on_equip_btn_pressed():
	InputManager.on_equip_button_pressed()

func _get_type_display_name(type: String) -> String:
	match type:
		"weapon": return "武器"
		"armor": return "防具"
		"relic": return "遗物"
		_:
			return type

func _show_attack_highlight(cells: Dictionary, unit: Unit):
	var color = MapConst.HIGHLIGHT_ATTACK
	if unit and unit.get_weapon_type() == "staff":
		color = MapConst.HIGHLIGHT_HEAL
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

# ---- 地图模式：胜利继续 ----
func _on_map_victory_continue():
	print("=== _on_map_victory_continue ===")
	print("reward_gold: ", GameState.current_reward_gold)
	print("reward_soul: ", GameState.current_reward_soul)
	print("reward_materials: ", GameState.current_reward_materials)
	print("reward_items: ", GameState.reward_items)
	print("current_node_key: ", GameState.current_node_key)
	print("current_node_type: ", current_node_type)

	var reward_gold = GameState.current_reward_gold
	var reward_soul = GameState.current_reward_soul
	var reward_materials = GameState.current_reward_materials

	var reward_item_datas: Array = []
	for item_id in GameState.reward_items:
		var data = ItemManager.get_item_data(item_id)
		if data:
			reward_item_datas.append(data)
		else:
			var relic_data = RelicManager.get_relic_data(item_id)
			if not relic_data.is_empty():
				var virtual_data = ItemData.new()
				virtual_data.id = item_id
				virtual_data.name = relic_data.get("name", "未知遗物")
				var icon_path = relic_data.get("icon", "")
				if icon_path != "" and ResourceLoader.exists(icon_path):
					virtual_data.icon = load(icon_path)
				reward_item_datas.append(virtual_data)

	if reward_materials and not reward_materials.is_empty():
		for material_name in reward_materials:
			var amount = reward_materials[material_name]
			if amount > 0:
				var data = ItemData.new()
				data.id = "material_" + material_name
				data.name = material_name + " x" + str(amount)
				data.description = "材料 x" + str(amount)
				reward_item_datas.append(data)
				print("添加材料显示: ", data.name)

	var has_reward = (reward_gold > 0 or reward_soul > 0 or not reward_item_datas.is_empty())

	var is_boss = (current_node_type == MapNode.NodeType.BOSS)
	if not is_boss and GameState.current_map_data:
		is_boss = (GameState.current_map_data.node_type == MapNode.NodeType.BOSS)

	var is_last_day = (GameState.current_day >= 3)

	print("is_boss=", is_boss, " is_last_day=", is_last_day, " has_reward=", has_reward)

	var need_ui_block = has_reward or is_boss
	if need_ui_block:
		_is_reward_ui_active = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cursor.visible = false

	var summary = null
	if has_reward:
		print("有奖励，弹出结算界面")
		summary = Globals.get_reward_summary()
		if summary:
			summary.setup_reward(reward_gold, reward_soul, reward_item_datas, false, "关卡结算")
			summary.open()
			await summary.confirmed
			print("结算界面已确认，summary 保持可见")
		else:
			push_error("Battlefield: 无法获取 RewardSummaryUI 实例")

	if is_boss:
		GameState.should_advance_day = true
		print("Boss 胜利，设置 should_advance_day = true")

		if is_last_day:
			print("第三天最终Boss，跳过遗物三选一和英灵殿")
		else:
			# ---- 1. 遗物三选一 ----
			print("弹出遗物三选一，叠加在结算之上")
			var relic_select_scene = load(Config.PATHS.RELIC_SELECT_UI)
			var relic_select = relic_select_scene.instantiate()
			add_child(relic_select)

			var owned_ids = []
			for relic in GameState.get_relics_from_passives():
				owned_ids.append(relic.item_id)

			relic_select.setup_options(owned_ids)

			await relic_select.relic_selected
			print("遗物选择完成")

			# ---- 2. 英灵殿 ----
			print("弹出英灵殿")
			var hero_shrine_scene = load(Config.PATHS.HERO_SHRINE_UI)
			if hero_shrine_scene:
				var hero_shrine = hero_shrine_scene.instantiate()
				add_child(hero_shrine)
				await hero_shrine.closed
				print("英灵殿关闭")
			else:
				push_warning("HeroShrineUI 场景未找到")

	if summary:
		print("结算界面已关闭")

	if need_ui_block:
		_is_reward_ui_active = false
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		cursor.visible = true

	if GameState.current_node_key != "":
		GameState.visited_nodes[GameState.current_node_key] = true
		GameState.current_node_key = ""

	GameState.reward_items.clear()
	GameState.clear_current_reward()
	SaveManager.auto_save()

	print("切换场景到 MapScene")
	get_tree().change_scene_to_file(Config.PATHS.MAP_SCENE)

# ---- 统一的放弃战斗逻辑 ----
func _execute_abandon_battle():
	Globals.is_transitioning = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if cursor:
		cursor.visible = false

	GameState.current_node_key = ""
	Globals.is_performing_action = false
	TurnManager.is_game_over = true
	GameState.abandon_and_return_to_camp()

func _on_map_defeat_gameover():
	_execute_abandon_battle()

func _on_non_map_defeat():
	_execute_abandon_battle()

func _on_retry_battle():
	if GameState.current_node_key != "":
		GameState.visited_nodes.erase(GameState.current_node_key)
		GameState.current_node_key = ""
	get_tree().change_scene_to_file(Config.PATHS.MAP_SCENE)

# ===================== 非战斗模式 =====================
func _setup_non_combat_mode():
	print("进入非战斗模式：", GameState.current_map_data.map_name if GameState.current_map_data else "未知地图")
	is_non_combat_mode = true
	Globals.is_non_combat_mode = true

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cursor.visible = false

	var music_stream = null
	if MusicManager.config and MusicManager.config.non_combat_music:
		music_stream = MusicManager.config.non_combat_music
	elif MusicManager.config and MusicManager.config.map_music:
		music_stream = MusicManager.config.map_music
	if music_stream:
		MusicManager.play_music(music_stream)

	if attack_btn:
		attack_btn.disabled = true
	if move_btn:
		move_btn.disabled = false
	if wait_btn:
		wait_btn.disabled = false
	if equip_btn:
		equip_btn.disabled = false
	if setting_panel:
		setting_panel.visible = false

	if end_turn_button:
		end_turn_button.text = "鼠标中键结束回合"
		end_turn_button.visible = true
		end_turn_button.modulate = Color.WHITE

	if _battle_start_event_id != "":
		print("检测到非战斗地图事件：", _battle_start_event_id)
		var music = MusicManager.config.battle_start_dialogue_music if MusicManager.config else null
		if EventManager and EventManager.has_event(_battle_start_event_id):
			await EventManager.trigger_event(_battle_start_event_id, null, music)
		else:
			if DialogueManager.has_dialogue(_battle_start_event_id):
				DialogueManager.start_dialogue(_battle_start_event_id, music)
				await DialogueManager.dialogue_finished
			else:
				print("警告：非战斗地图事件/对话不存在: ", _battle_start_event_id)
		print("非战斗地图事件结束")

	print("非战斗模式设置完成，回合系统已启动，等待玩家操作")

func _on_non_combat_complete():
	print("非战斗节点完成，显示胜利面板")
	TurnManager.is_game_over = true
	MusicManager._saved_stream = null
	MusicManager._saved_position = 0.0
	_on_request_show_victory(0)

# ---- 提取出生点 ----
func _extract_spawn_points(node: Node) -> Array[Vector2i]:
	var points = []
	_find_spawn_points(node, points)
	points.sort_custom(func(a, b): return a["index"] < b["index"])
	var result: Array[Vector2i] = []
	for p in points:
		result.append(p["position"])
	return result

func _find_spawn_points(node: Node, result: Array):
	if node is UnitPlacerTool:
		var cfg = node.export_config()
		if cfg is Dictionary and cfg.get("type") == "spawn_point":
			result.append({
				"position": cfg["position"],
				"index": cfg["spawn_index"]
			})
	for child in node.get_children():
		_find_spawn_points(child, result)

func _generate_default_terrain(map_size: Vector2i):
	map_grid_size = map_size
	TerrainManager.grid_size = map_size
	var grid = []
	for y in range(map_size.y):
		var row = []
		for x in range(map_size.x):
			row.append(TerrainManager.TerrainType.PLAIN)
		grid.append(row)
	TerrainManager.terrain_grid = grid
	print("生成默认平地地形，尺寸：", map_size)

func _update_end_turn_button_visibility():
	if not end_turn_button:
		return
	if is_non_combat_mode:
		return
	end_turn_button.visible = true
	end_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP

func _end_player_turn():
	if TurnManager.is_game_over:
		print("游戏已结束，无法结束回合")
		return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		print("当前不是玩家回合，无法结束")
		return
	if Globals.is_transitioning or Globals.is_fading:
		print("正在过渡中，无法结束回合")
		return

	if _is_any_ui_active():
		print("有 UI 活跃，稍后重试结束回合")
		return

	SignalBus.request_hide_info.emit()
	SignalBus.request_hide_setting.emit()
	SignalBus.request_hide_menu.emit()
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

	print("玩家回合结束，切换到敌方回合")
	TurnManager.start_turn(TurnManager.Team.ENEMY)

func _update_cursor_and_mouse():
	if _is_reward_ui_active:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cursor.visible = false
		return

	var force_hide_cursor = (
		Globals.is_dialogue_active or
		Globals.is_performing_action or
		Globals.is_item_get_popup_active or
		Globals.is_equip_menu_active or
		victory_panel.visible or
		setting_panel.visible or
		team_view_panel.visible or
		item_list_panel.visible or
		setting_menu_panel.visible or
		TurnManager.current_turn_team == TurnManager.Team.ENEMY or
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

	# ---- 鼠标进入遗物/精炼面板：切回系统鼠标，让 Button 可点 ----
	if relic_icon_container and is_instance_valid(relic_icon_container):
		var relic_rect = relic_icon_container.get_global_rect().grow(4.0)
		var vp_mouse = get_viewport().get_mouse_position()
		if relic_rect.has_point(vp_mouse):
			cursor.visible = false
			if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

	var show_cursor = false
	var cursor_world_pos = Vector2.ZERO
	var show_system_mouse = false

	if (action_menu.visible or info_panel.visible) and InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit):
		show_cursor = true
		cursor_world_pos = grid_to_world(InputManager.selected_unit.grid_cell)
		show_system_mouse = true
	else:
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
			if not force_hide_cursor:
				show_cursor = true
				var world_mouse = get_global_mouse_position()
				var grid_pos = world_to_grid(world_mouse)
				cursor_world_pos = grid_to_world(grid_pos)

		show_system_mouse = not show_cursor

	if show_cursor:
		if not (action_menu.visible or info_panel.visible):
			var world_mouse = get_global_mouse_position()
			var grid_pos = world_to_grid(world_mouse)
			grid_pos.x = clamp(grid_pos.x, 0, map_grid_size.x - 1)
			grid_pos.y = clamp(grid_pos.y, 0, map_grid_size.y - 1)
			cursor_world_pos = grid_to_world(grid_pos)

		var canvas_transform = get_viewport().get_canvas_transform()
		var screen_pos = canvas_transform * cursor_world_pos
		screen_pos = screen_pos.round()
		var size = cursor.size.round()
		cursor.position = screen_pos - size / 2
		cursor.visible = true
	else:
		cursor.visible = false

	if show_system_mouse:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	if cursor.visible:
		var new_scale = _get_viewport_scale()
		if new_scale != _viewport_scale:
			_viewport_scale = new_scale
			var target_size = round(MapConst.CELL_SIZE * _viewport_scale)
			cursor.size = Vector2(target_size, target_size)
			if _attack_indicator:
				_attack_indicator.size = Vector2(target_size, target_size)

	var should_be_pink = false
	if Globals.is_equip_menu_active:
		should_be_pink = true
	elif action_menu.visible or info_panel.visible:
		should_be_pink = true
	elif InputManager.selected_unit != null and InputManager.selected_unit.unit_stats.team_id == 0:
		var phase = InputManager.interaction_phase
		if phase in [InputManager.Phase.MENU, InputManager.Phase.MOVING, InputManager.Phase.ATTACKING]:
			should_be_pink = true

	var target_color = Color.FUCHSIA if should_be_pink else Color.WHITE
	if cursor.modulate != target_color:
		cursor.modulate = target_color

# ---- 遗物查看按钮回调（复用 ItemListPanel） ----
func _on_relic_view_btn_pressed():
	if setting_menu_panel.visible:
		setting_menu_panel.visible = false
	if team_view_panel.visible:
		team_view_panel.visible = false
	if item_list_panel.visible and _is_showing_relics:
		item_list_panel.visible = false
		_is_showing_relics = false
		return

	item_list_panel.visible = true
	_refresh_relic_list()
	_is_showing_relics = true

# ---- 刷新遗物列表（只显示被动槽里的遗物） ----
func _refresh_relic_list():
	for child in item_list_container.get_children():
		child.queue_free()

	var relics = GameState.get_relics_from_passives()
	if relics.is_empty():
		var label = Label.new()
		label.text = "暂无遗物"
		label.add_theme_font_size_override("font_size", 6)
		item_list_container.add_child(label)
		return

	for relic in relics:
		var data = RelicManager.get_relic_data(relic.item_id)
		if data.is_empty():
			continue
		var btn = Button.new()
		btn.text = data.get("name", "未知遗物")
		var icon_path = data.get("icon", "")
		if icon_path != "" and ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
		btn.add_theme_font_size_override("font_size", 6)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = true

		var item_id = relic.item_id
		btn.mouse_entered.connect(_on_relic_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_relic_hover_exited)

		item_list_container.add_child(btn)

	await get_tree().process_frame
	var content_height = item_list_container.get_minimum_size().y
	var viewport_size = get_viewport().get_visible_rect().size
	var max_height = viewport_size.y * 0.9
	var panel_height = clamp(content_height + 16, 20, max_height)
	var panel_width = clamp(120, 80, viewport_size.x * 0.4)
	item_list_panel.size = Vector2(panel_width, panel_height)

	var parent = item_list_container.get_parent()
	var scroll = parent as ScrollContainer
	if not scroll:
		scroll = _create_scroll_container(item_list_container, parent, "ItemListScroll")
	scroll.size = item_list_panel.size

func _on_relic_hover_entered(item_id: String):
	show_item_detail(item_id)

func _on_relic_hover_exited():
	hide_item_detail()

func _on_item_list_btn_pressed():
	if setting_menu_panel.visible:
		setting_menu_panel.visible = false
	if team_view_panel.visible:
		team_view_panel.visible = false
	if _is_showing_relics:
		item_list_panel.visible = false
		_is_showing_relics = false
		return
	item_list_panel.visible = not item_list_panel.visible
	if item_list_panel.visible:
		_refresh_item_list()
		_is_showing_relics = false

# ---- 更新常驻遗物显示（从被动槽过滤遗物） ----
func _update_relic_icons():
	for child in relic_icon_container.get_children():
		child.queue_free()

	var passives = GameState.get_passives()
	var has_any = false

	for i in range(passives.size()):
		var p = passives[i]
		if p == null:
			continue

		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 6)
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.custom_minimum_size = Vector2(0, 14)

		if p is ItemInstance:
			# ---- 遗物：只展示，点击无效果 ----
			var data = RelicManager.get_relic_data(p.item_id)
			if data.is_empty():
				continue
			btn.text = "◆ " + data.get("name", "?")
			btn.disabled = true                     # 视觉上不可点击
			btn.tooltip_text = data.get("description", "")
			relic_icon_container.add_child(btn)
			has_any = true

		elif p is Dictionary and p.has("refine_id"):
			# ---- 精炼：可点击使用 ----
			var refine_id : String = p.get("refine_id", "")
			var recipe : Dictionary = RefineManager.get_recipe(refine_id)
			if recipe.is_empty():
				continue
			btn.text = "★ " + recipe.get("name", "?") + " ▶"
			btn.tooltip_text = recipe.get("description", "")
			btn.pressed.connect(_on_use_refine.bind(i))
			relic_icon_container.add_child(btn)
			has_any = true

	if not has_any:
		var label := Label.new()
		label.text = "无遗物/精炼"
		label.add_theme_font_size_override("font_size", 6)
		relic_icon_container.add_child(label)


func _on_use_refine(slot_idx: int) -> void:
	var passives = GameState.get_passives()
	if slot_idx < 0 or slot_idx >= passives.size():
		return
	var p = passives[slot_idx]
	if not (p is Dictionary and p.has("refine_id")):
		return

	var refine_id : String = p.get("refine_id", "")
	var effect : Dictionary = RefineManager.get_effect(refine_id)
	if effect.is_empty():
		return

	var effect_type : String = effect.get("type", "")
	var value : Variant = effect.get("value", 0)

	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0:
			continue
		match effect_type:
			"attack_percent":
				unit.buff_attack_percent += value
			"crit_damage_bonus":
				unit.buff_crit_damage_bonus += value
			"defense_flat":
				unit.buff_defense_flat += int(value)
			"damage_reduction":
				unit.buff_damage_reduction += value
			"heal_full":
				unit.hit_points = unit.unit_stats.max_hp
				unit.update_hp_label()

	GameState.set_passive_at_slot(slot_idx, null)

	_update_relic_icons()
	SoundManager.play_heal_sound()
	print("[Battlefield] 使用精炼：", refine_id, " 类型：", effect_type)

func show_item_detail(item_id: String):
	if _detail_popup:
		_detail_popup.show_item(item_id)
		_detail_popup.visible = true

func hide_item_detail():
	if _detail_popup:
		_detail_popup.visible = false

func _wait_for_ui_clear(timeout_ms: int = 5000) -> void:
	var start = Time.get_ticks_msec()
	while _is_any_ui_active():
		if Time.get_ticks_msec() - start > timeout_ms:
			push_warning("Battlefield: 等待 UI 结束超时（%d ms），强制继续" % timeout_ms)
			return
		await get_tree().process_frame

func _is_any_ui_active() -> bool:
	return (
		Globals.is_dialogue_active or
		Globals.is_item_get_popup_active or
		Globals.is_equip_menu_active or
		Globals.is_fading or
		Globals.is_transitioning or
		Globals.is_performing_action
	)

func _on_back_camp_pressed():
	GameState.show_abandon_confirmation(self)

# ============================================================
#  战斗开始：精炼品消耗（从被动槽读） + 遗物属性应用
# ============================================================
func _apply_team_buffs():
	# ---- 1. 汇总被动槽里的精炼 buff ----
	var buffs = {
		"attack_percent": 0.0,
		"crit_damage_bonus": 0.0,
		"defense_flat": 0,
		"damage_reduction": 0.0,
		"heal_full": false,
	}
	for entry in GameState.get_refines_from_passives():
		var refine_id = entry.get("refine_id", "")
		if refine_id == "":
			continue
		var effect = RefineManager.get_effect(refine_id)
		if effect.is_empty():
			continue
		var value = effect.get("value", 0)
		match effect.get("type", ""):
			"attack_percent":     buffs["attack_percent"] += value
			"crit_damage_bonus":  buffs["crit_damage_bonus"] += value
			"defense_flat":       buffs["defense_flat"] += int(value)
			"damage_reduction":   buffs["damage_reduction"] += value
			"heal_full":          buffs["heal_full"] = true

	GameState.clear_refine_passives()

	# ---- 2. 遗物属性加成（保留旧接口） ----
	var relic_stats = GameState.get_global_relic_stats()
	# ---- 3. 遗物 effects ----
	var relic_effects = GameState.get_global_relic_effects()

	# ---- 4. 应用到玩家单位 ----
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0:
			continue

		# 精炼 buff
		unit.buff_attack_percent += buffs["attack_percent"]
		unit.buff_crit_damage_bonus += buffs["crit_damage_bonus"]
		unit.buff_defense_flat += int(buffs["defense_flat"])
		unit.buff_damage_reduction += buffs["damage_reduction"]

		# 遗物属性
		var s = unit.unit_stats
		var old_max = s.max_hp
		s.max_hp       += int(relic_stats.get("max_hp", 0))
		s.strength     += int(relic_stats.get("strength", 0))
		s.dexterity    += int(relic_stats.get("dexterity", 0))
		s.intelligence += int(relic_stats.get("intelligence", 0))
		s.faith        += int(relic_stats.get("faith", 0))
		s.arcane       += int(relic_stats.get("arcane", 0))
		s.move_range   += int(relic_stats.get("move_range", 0))
		unit.buff_attack_flat       += int(relic_stats.get("attack", 0))
		unit.buff_defense_flat      += int(relic_stats.get("defense", 0))
		unit.buff_magic_attack_flat += int(relic_stats.get("magic_attack", 0))

		var hp_delta = s.max_hp - old_max
		if hp_delta > 0:
			unit.hit_points += hp_delta
		if unit.hit_points > s.max_hp:
			unit.hit_points = s.max_hp

		# ★ 遗物 effects 应用到单位
		unit.relic_first_attack_crit_available = bool(relic_effects.get("first_attack_crit", false))
		unit.relic_low_hp_damage_reduce = float(relic_effects.get("low_hp_damage_reduce", 0.0))
		unit.relic_kill_grants_extra_move = int(relic_effects.get("kill_grants_extra_move", 0))
		unit.relic_first_spell_free_available = bool(relic_effects.get("first_spell_free", false))
		unit.relic_turn_first_hit_regen = float(relic_effects.get("turn_first_hit_regen", 0.0))
		unit.relic_strength_scale_damage = float(relic_effects.get("strength_scale_damage", 0.0))
		unit.relic_counter_damage_bonus = float(relic_effects.get("counter_damage_bonus", 0.0))
		unit.relic_heal_bonus = float(relic_effects.get("heal_bonus", 0.0))

		unit.update_hp_label()

	if buffs["heal_full"]:
		for unit in UnitManager.unit_list:
			if unit.unit_stats.team_id == 0:
				unit.hit_points = unit.unit_stats.max_hp
				unit.update_hp_label()

	print("[Battlefield] buff 已应用 | 精炼：", buffs, " 遗物属性：", relic_stats, " 遗物效果：", relic_effects)
