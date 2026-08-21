extends Node2D
class_name Battlefield

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")
const BOSS_NODE_TYPE = 6

# ---- 导出变量 ----
@export var map_data : MapData = null
@export var transition_delay_before_fade : float = 1.0
@export var transition_delay_after_fade : float = 1.0

# ---- 节点引用（方式一：使用 @onready 自动获取） ----
# 如果您仍在使用 @onready，保留以下代码；如果已改为手动获取，请注释或删除
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

# ---- 常量 ----
const CELL_SIZE : int = 16
const PERFORMANCE_DURATION : float = 0.5
const ItemGetPopupScene = preload("res://content/scenes/ui/ItemGetPopup.tscn")
const RewardSummaryUI = preload("res://content/scenes/ui/RewardSummaryUI.tscn")

# ---- 普通变量（运行时可修改） ----
var map_grid_size : Vector2i = Vector2i(20, 15)
var _initialized : bool = false
var _viewport_scale : float = 1.0
var _battle_start_event_id : String = ""
var _attack_indicator : TextureRect = null
var map_functions : Dictionary = {}
var _turn_changed_locked : bool = false
var is_non_combat_mode: bool = false
var non_combat_back_button: Button = null
var current_node_type: int = MapNode.NodeType.NORMAL   # 当前地图的节点类型
var _victory_processed: bool = false   # 防止重复处理胜利
var _detail_popup = null
var _is_reward_ui_active: bool = false   # 结算界面是否激活

func _ready():
	# ---- 手动获取所有节点 ----
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
	
	# ---- 新增遗物节点 ----
	relic_view_btn = $SettingLayer/SettingPanel/SettingContainer/RelicViewBtn
	relic_icon_container = $RelicLayer/RelicIconContainer

	# ---- 检查关键节点 ----
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

	# ---- 原有信号连接 ----
	setting_btn.pressed.connect(_on_setting_btn_pressed)
	equip_btn.pressed.connect(_on_equip_btn_pressed)
	item_list_btn.pressed.connect(_on_item_list_btn_pressed)
	SignalBus.non_combat_complete.connect(_on_non_combat_complete)
	
	# ---- 创建详情弹窗（隐藏） ----
	_detail_popup = load("res://content/scenes/ui/ItemDetailPopup.tscn").instantiate()
	add_child(_detail_popup)
	_detail_popup.visible = false
	
	if end_turn_button:
		end_turn_button.text = "鼠标中键结束回合"
		end_turn_button.visible = not is_non_combat_mode
		
	# ---- 遗物查看按钮 ----
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
	_attack_indicator.size = Vector2(CELL_SIZE, CELL_SIZE)
	_attack_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_indicator.z_index = 5
	_attack_indicator.visible = false
	add_child(_attack_indicator)

	if victory_panel:
		victory_panel.visible = false

	_initialize_managers()
	_connect_signals()

	if turn_overlay:
		turn_overlay.modulate = Color(1, 1, 1, 0)
		Globals.is_fading = false

	# ---- 加载地图 ----
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
		var map_pixel_size = Vector2(map_grid_size.x * CELL_SIZE, map_grid_size.y * CELL_SIZE)
		if camera_controller:
			camera_controller.set_map_boundary(Rect2(Vector2.ZERO, map_pixel_size))

	if camera_controller:
		camera_controller.set_grid_size(CELL_SIZE)
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
	InputManager.interaction_phase = "idle"
	InputManager.current_highlight_cells = {}
	InputManager.attackable_targets = []

	TurnManager.all_acted = false
	TurnManager.is_moving = false
	TurnManager.is_ai_moving = false
	TurnManager.clear_ai_state()
	TurnManager.last_player_unit = null
	TurnManager.current_turn_team = 0

	if highlight_manager:
		highlight_manager.clear_highlight()
	_on_clear_highlight_unit()

	if menu_blocker:
		menu_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		menu_blocker.visible = false
		menu_blocker.gui_input.connect(_on_menu_blocker_clicked)
		menu_blocker.size = Vector2(map_grid_size.x * CELL_SIZE, map_grid_size.y * CELL_SIZE)
		menu_blocker.position = Vector2.ZERO
		menu_blocker.z_index = 10

	# ---- 判断是否为非战斗模式 ----
	var is_non_combat = GameState.current_map_data and GameState.current_map_data.node_type in [
		MapNode.NodeType.CAMPFIRE,
		MapNode.NodeType.SHOP,
		MapNode.NodeType.EVENT,
		MapNode.NodeType.FINAL_PREP
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
		
		TurnManager.start_turn(0)
		# ---- 更新遗物显示 ----
		_update_relic_icons()
		return

	# ---- 战斗模式：触发战斗开始事件 ----
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
	TurnManager.start_turn(0)
	print("=== TurnManager.start_turn(0) 调用完成 ===")
	_update_end_turn_button_visibility()

	# ---- 改造 BackCampBtn ----
	print("back_camp_btn: ", back_camp_btn)
	if back_camp_btn:
		print("back_camp_btn 已获取")
		for conn in back_camp_btn.pressed.get_connections():
			back_camp_btn.pressed.disconnect(conn.callable)
		back_camp_btn.pressed.connect(_on_back_camp_pressed)
		back_camp_btn.text = "回到营地"
		print("BackCampBtn 已连接")
	InputManager.ui_manager = ui_manager
	
	# ---- 更新遗物常驻显示 ----
	_update_relic_icons()
	print("Battlefield _ready 完成")

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
	# 光标更新移至 _physics_process

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
	print("=== load_map 被调用 ===")
	if not new_map_data:
		print("地图数据为空，加载默认地图")
		_load_default_map()
		return
	
	print("地图名称：", new_map_data.map_name)
	GameState.current_map_data = new_map_data
	current_node_type = new_map_data.node_type   # 安全
	
	# ---- 声明变量 ----
	var map_pixel_rect: Rect2
	var tilemap: TileMapLayer = null
	var main_scene_instance: Node = null
	var used_rect: Rect2i = Rect2i()
	var spawn_points: Array[Vector2i] = []

	# ---- 尝试加载场景 ----
	if new_map_data.scene:
		var scene_path = new_map_data.scene.resource_path
		print("加载场景：", scene_path)
		
		var scene = load(scene_path) as PackedScene
		if scene:
			main_scene_instance = scene.instantiate()
			if main_scene_instance:
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
					
					# ---- 提取出生点 ----
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
	
	# ---- 如果未找到地形，生成默认 ----
	if not tilemap:
		_generate_default_terrain(new_map_data.map_size)
		used_rect = Rect2i(Vector2i.ZERO, map_grid_size)
		map_pixel_rect = Rect2(Vector2.ZERO, new_map_data.map_size * CELL_SIZE)
		menu_blocker.size = new_map_data.map_size * CELL_SIZE
		menu_blocker.position = Vector2.ZERO
	else:
		map_pixel_rect = Rect2(
			used_rect.position * CELL_SIZE,
			used_rect.size * CELL_SIZE
		)
		menu_blocker.size = used_rect.size * CELL_SIZE
		menu_blocker.position = used_rect.position * CELL_SIZE

	# ---- 清除旧单位 ----
	_clear_units()

	# ---- 生成单位 ----
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

	# ---- 设置摄像机边界 ----
	menu_blocker.z_index = 2
	camera_controller.set_map_boundary(map_pixel_rect)
	print("地图边界（像素）:", map_pixel_rect)

	_center_camera_on_player()
	TurnManager.map_functions = map_functions
	print("地图加载完成：", new_map_data.map_name)

# ---- 辅助函数：生成备用地图 ----
func _create_fallback_map_data() -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	var cfg = UnitConfig.new()
	cfg.unit_name = "剑士"
	cfg.team_id = 0
	cfg.position = Vector2i(10, 10)
	var enemy_cfg = UnitConfig.new()
	enemy_cfg.unit_name = "斧兵"
	enemy_cfg.team_id = 1
	enemy_cfg.position = Vector2i(5, 5)
	return map

# ---- 辅助函数：创建全平地 ----
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

# Battlefield.gd
# 提取场景中的功能格配置，并在运行时移除工具节点
func _extract_map_unit_placers(node: Node):
	map_functions.clear()
	var battle_start_event = ""
	var tool_nodes: Array[Node] = []   # 收集所有工具节点

	# 递归收集工具节点（EventTrigger, HpFunction, BattleStartEvent）
	_find_tools(node, tool_nodes)

	for tool in tool_nodes:
		var cfg = tool.export_config()
		# 对于 UnitPlacerTool，cfg 可能是 UnitConfig 对象；但工具节点都返回字典
		var cell: Vector2i
		if cfg is Dictionary:
			if cfg.has("position"):
				cell = cfg["position"]
			else:
				continue
		else:
			# 若不是字典，可能是其他类型，跳过
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
				# 忽略其他类型
				pass

	_battle_start_event_id = battle_start_event
	print("共提取 ", map_functions.size(), " 个功能格，战斗开始事件: ", battle_start_event)

	# ---- 删除所有工具节点（运行时不再需要） ----
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
		# 使用平滑移动，duration=0 立即跳转，但避免半格偏移
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
	default_map.map_size = Vector2i(20, 15)
	load_map(default_map)

func _clear_units():
	for child in get_children():
		if child is Unit:
			UnitManager.unregister_unit(child)
			child.queue_free()

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
		# "weapon_select_menu": $ActionMenu/WeaponSelectMenu,   # 已删除
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

	# 先断开再连接所有 SignalBus 信号，避免重复
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

	# 关键：turn_changed 只连接一次，先断开再连接
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

	# MovementAnimator 信号
	if movement_animator.movement_finished.is_connected(_on_player_movement_finished):
		movement_animator.movement_finished.disconnect(_on_player_movement_finished)
	movement_animator.movement_finished.connect(_on_player_movement_finished)

	if movement_animator.ai_movement_finished.is_connected(_on_ai_movement_finished):
		movement_animator.ai_movement_finished.disconnect(_on_ai_movement_finished)
	movement_animator.ai_movement_finished.connect(_on_ai_movement_finished)

# ===================== 信号回调 =====================
func _on_highlight_request(cells: Dictionary):
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
			await EventManager.trigger_event(event_id, unit)   # 等待事件完成（含 UI）
			if EventManager.is_event_completed(event_id):
				func_config["triggered"] = true
			else:
				func_config["triggered"] = false
				func_config["triggered_by_unit"] = null
			# 事件完成后才执行待机
			unit.can_act_this_turn = false
			unit.set_gray(true)
			TurnManager.finish_unit_action(unit)
			return

	# 普通待机
	InputManager.on_wait_button_pressed()

func _on_request_show_victory(winning_team: int):
	# ---- 等待所有 UI 结束 ----
	while _is_any_ui_active():
		await get_tree().process_frame
	# ============================================================
	
	if _victory_processed:
		print("胜利已处理，跳过重复调用")
		return
	_victory_processed = true

	var tree = get_tree()
	if not tree:
		print("错误：无法获取场景树，无法处理胜利")
		return

	# ---- 清理动画和UI ----
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

		# 在地图模式分支内，累加资源部分
		if is_win:
			var is_non_combat_node = current_node_type in [
				MapNode.NodeType.CAMPFIRE,
				MapNode.NodeType.SHOP,
				MapNode.NodeType.EVENT,
				MapNode.NodeType.FINAL_PREP
			]

			if not is_non_combat_node:
				var reward = EconomyManager.get_battle_reward(current_node_type, is_boss)
				var gold_gain = reward.gold
				var soul_gain = reward.soul

				GameState.current_reward_gold = gold_gain
				GameState.current_reward_soul = soul_gain
				EconomyManager.add_temp_gold(gold_gain)
				EconomyManager.add_temp_soul(soul_gain)
				
				print("--- 资源累加前 ---")
				print("gold_gain: ", gold_gain, " soul_gain: ", soul_gain)
				print("Battlefield 累加资源：temp_gold=", GameState.temp_gold, " temp_soul=", GameState.temp_soul)
				print("本次增量：gold=", gold_gain, " soul=", soul_gain)
			else:
				print("非战斗地图，不累加资源")
				GameState.current_reward_gold = 0
				GameState.current_reward_soul = 0
			GameState.current_node_key = ""

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
					# ============================================================
					# 修复1：直接使用方法引用，避免三目运算符类型错误
					# ============================================================
					ui_manager.show_victory("全部胜利！", "回到营地", self._on_map_victory_continue)
				else:
					ui_manager.show_victory("战斗胜利！", "继续旅程", self._on_map_victory_continue)
			else:
				ui_manager.show_victory("战斗失败", "重启旅程", self._on_map_defeat_gameover)
		else:
			if is_win:
				tree.change_scene_to_file("res://content/scenes/ui/MapScene.tscn")
			else:
				GameState.reset_all()
				tree.change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")
		return

	# ============================================================
	# 非地图模式（旧版流程）
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

	_victory_processed = false

func _on_turn_changed(team: int):
	print("连接数: ", SignalBus.turn_changed.get_connections().size())
	# ---- 等待 UI 结束 ----
	while _is_any_ui_active():
		await get_tree().process_frame
	_handle_turn_change_async(team)

# 新增异步处理函数（将原 _on_turn_changed 的全部逻辑移入）
func _handle_turn_change_async(team: int):
	if team == 0:
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

	# ---- 隐藏所有UI ----
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
	
	if team == 0:
		Globals.increment_battle_turn()
		
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

	# ---- 音乐控制（原逻辑不变） ----
	if not is_non_combat_mode:
		var is_boss = GameState.current_map_data and GameState.current_map_data.node_type == MapNode.NodeType.BOSS
		if is_boss:
			if team == 0:
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
			if team == 0:
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

	if team == 1 and not is_non_combat_mode:
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
	# ---- 装备菜单右键关闭 ----
	if Globals.is_equip_menu_active:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			Globals.suppress_sound = true
			ui_manager.hide_equip_menu()
			get_viewport().set_input_as_handled()
			if InputManager.selected_unit:
				InputManager.interaction_phase = "menu"
				SignalBus.request_show_menu.emit(InputManager.selected_unit)
		return

	# ---- 对话或道具弹出时屏蔽所有输入 ----
	if Globals.is_dialogue_active or Globals.is_item_get_popup_active:
		return

	# ---- 鼠标中键结束回合（替代原 F 键） ----
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		if TurnManager.current_turn_team == 0 and not Globals.is_fading and not Globals.is_transitioning and not Globals.is_dialogue_active:
			_end_player_turn()
			return

	# ---- 键盘事件（调试快捷键等，已移除 F 键） ----
	if event is InputEventKey and event.pressed:
		# 调试：杀死所有敌方单位 (0 键)
		if event.keycode == KEY_0 or event.keycode == KEY_KP_0:
			if Globals.is_transitioning:
				return  # 回合动画期间禁止
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
		# 调试：杀死所有我方单位 (9 键)
		elif event.keycode == KEY_9 or event.keycode == KEY_KP_9:
			if Globals.is_transitioning:
				return  # 回合动画期间禁止
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

	# ---- 过渡或锁定状态时屏蔽输入 ----
	if Globals.is_transitioning or Globals.is_fading:
		return

	# ---- 鼠标滚轮切换单位 ----
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if (Globals.is_equip_menu_active or 
				setting_panel.visible or 
				setting_menu_panel.visible or 
				team_view_panel.visible or 
				item_list_panel.visible or
				InputManager.interaction_phase in ["moving", "attacking", "item_target"]):
				return
			if TurnManager.is_game_over:
				return
			if TurnManager.current_turn_team == 0 and not TurnManager.is_moving and not TurnManager.is_ai_moving and not Globals.is_performing_action:
				var direction = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				InputManager.handle_wheel(direction)
			return

	# ---- 敌方回合或游戏结束屏蔽 ----
	if TurnManager.current_turn_team != 0:
		return
	if TurnManager.all_acted:
		return

	# ---- 键盘 1/2/3 模拟移动/攻击/待机（仅调试） ----
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

	# ---- 移动动画中屏蔽鼠标操作 ----
	if TurnManager.is_moving:
		return

	# ---- 鼠标事件（左键点击 / 右键取消） ----
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			InputManager.handle_input(event, map_grid_size, CELL_SIZE)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 如果菜单打开且不是给予模式，则忽略左键点击（由菜单按钮处理）
			if action_menu.visible:
				return
			var mouse_pos = get_global_mouse_position()
			var clicked_cell = world_to_grid(mouse_pos)
			InputManager.handle_click(clicked_cell)
	else:
		# 其他输入（如鼠标移动）交给 InputManager
		InputManager.handle_input(event, map_grid_size, CELL_SIZE)

	# ---- 装备菜单激活时阻止后续操作 ----
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
		
		# ---- 统一显示格式：姓名|阵营|职业 ----
		lines.append(UnitDataManager.get_display_name_from_unit(unit))

		lines.append("HP: " + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp))

		# ---- 装备数据 ----
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

		# ---- 防具槽 ----
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

		# ---- 基本属性 ----
		lines.append("防御: " + str(unit.unit_stats.defense))
		lines.append("魔防: " + str(unit.unit_stats.magic_defense))
		lines.append("技巧: " + str(unit.unit_stats.skill))
		lines.append("速度: " + str(unit.unit_stats.speed))
		lines.append("幸运: " + str(unit.unit_stats.luck))
		lines.append("移动力: " + str(unit.unit_stats.move_range))

		# ---- 地形 ----
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
			# 获取图标
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

			# ---- 统一显示格式：姓名|阵营|职业 ----
			var full_name = UnitDataManager.get_display_name_from_unit(unit)
			btn.text = full_name + " HP:" + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp) + status
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

	# 更新面板高度
	await get_tree().process_frame
	var content_height = team_view_container.get_minimum_size().y
	var viewport_height = get_viewport().get_visible_rect().size.y
	var max_height = viewport_height * 0.8
	var panel_height = clamp(content_height + 16, 20, max_height)
	team_view_panel.size.y = panel_height

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

	# ---- 只显示单位装备，不显示仓库 ----
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			var unit_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
			
			# 武器
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
			
			# 防具/饰品槽
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
			btn.disabled = true   # 禁用点击
			
			# ---- 悬停显示详情 ----
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

# ---- 地图模式：胜利继续 ----
func _on_map_victory_continue():
	print("=== _on_map_victory_continue ===")
	print("reward_gold: ", GameState.current_reward_gold)
	print("reward_soul: ", GameState.current_reward_soul)
	print("reward_items: ", GameState.reward_items)
	print("=== 进入 _on_map_victory_continue ===")
	
	var reward_gold = GameState.current_reward_gold
	var reward_soul = GameState.current_reward_soul
	
	# ---- 收集物品数据（从 reward_items 中获取 ItemData） ----
	var reward_item_datas: Array = []
	for item_id in GameState.reward_items:
		var data = ItemManager.get_item_data(item_id)
		if data:
			reward_item_datas.append(data)
		else:
			# 可能是遗物，尝试从 RelicManager 获取
			var relic_data = RelicManager.get_relic_data(item_id)
			if not relic_data.is_empty():
				# 构建虚拟 ItemData 用于显示
				var virtual_data = ItemData.new()
				virtual_data.id = item_id
				virtual_data.name = relic_data.get("name", "未知遗物")
				var icon_path = relic_data.get("icon", "")
				if icon_path != "" and ResourceLoader.exists(icon_path):
					virtual_data.icon = load(icon_path)
				reward_item_datas.append(virtual_data)
	
	# ---- 是否有奖励？ ----
	var has_reward = (reward_gold > 0 or reward_soul > 0 or not reward_item_datas.is_empty())
	
	if has_reward:
		print("有奖励，弹出结算界面")
		
		# ---- 设置光标 ----
		_is_reward_ui_active = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cursor.visible = false
		
		# ---- 实例化结算 UI ----
		var summary = RewardSummaryUI.instantiate()
		add_child(summary)
		summary.setup_reward(reward_gold, reward_soul, reward_item_datas)
		
		# ---- 等待确认 ----
		await summary.confirmed
		
		# ---- 恢复光标 ----
		_is_reward_ui_active = false
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		cursor.visible = true
	else:
		print("无奖励，直接返回地图")
	
	# ---- 清理 ----
	GameState.reward_items.clear()
	GameState.clear_current_reward()
	SaveManager.auto_save()
	
	# ---- 返回地图 ----
	get_tree().change_scene_to_file("res://content/scenes/ui/MapScene.tscn")

# ---- 统一的放弃战斗逻辑 ----
func _execute_abandon_battle():
	GameState.current_node_key = ""
	Globals.is_performing_action = false
	TurnManager.is_game_over = true

	GameState.abandon_cycle()
	GameState.reset_progress()

	# ---- 清空队伍 ----
	GameState.party.clear()
	GameState.main_unit_name = ""
	GameState.main_unit_index = 0
	GameState.current_faction = ""
	GameState.global_relics.clear()

	GameState.interrupt_state = 1

	var slot = SaveManager.current_slot
	if slot == -1:
		slot = SaveManager.find_empty_slot()
		if slot == -1:
			slot = 0
	SaveManager.save_game(slot, false)
	SaveManager.current_slot = slot

	get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")

# ---- 地图模式失败处理（直接放弃，无确认框） ----
func _on_map_defeat_gameover():
	_execute_abandon_battle()

# ---- 非地图模式失败处理（直接放弃，无确认框） ----
func _on_non_map_defeat():
	_execute_abandon_battle()

func _on_retry_battle():
	if GameState.current_node_key != "":
		GameState.visited_nodes.erase(GameState.current_node_key)
		GameState.current_node_key = ""
	get_tree().change_scene_to_file("res://content/scenes/ui/MapScene.tscn")

# ===================== 非战斗模式 =====================
func _setup_non_combat_mode():
	print("进入非战斗模式：", GameState.current_map_data.map_name if GameState.current_map_data else "未知地图")
	is_non_combat_mode = true
	Globals.is_non_combat_mode = true
	
	# ---- 恢复鼠标可见 ----
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cursor.visible = false
	
	# ---- 播放非战斗地图音乐 ----
	var music_stream = null
	if MusicManager.config and MusicManager.config.non_combat_music:
		music_stream = MusicManager.config.non_combat_music
	elif MusicManager.config and MusicManager.config.map_music:
		music_stream = MusicManager.config.map_music
	if music_stream:
		MusicManager.play_music(music_stream)
	
	# ---- UI 设置：禁用攻击，保留其他 ----
	if attack_btn:
		attack_btn.disabled = true      # 非战斗不能攻击
	if move_btn:
		move_btn.disabled = false
	if wait_btn:
		wait_btn.disabled = false
	if equip_btn:
		equip_btn.disabled = false      # 允许装备调整
	if setting_panel:
		setting_panel.visible = false   # 默认隐藏，通过设置按钮打开
	
	# ---- EndTurnButton 保持正常 ----
	if end_turn_button:
		end_turn_button.text = "鼠标中键结束回合"
		end_turn_button.visible = true
		end_turn_button.modulate = Color.WHITE
	
	# ---- 不设置 TurnManager.is_game_over，让回合系统正常运行 ----
	
	# ---- 触发地图开始事件（如果有） ----
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
	# 清除保存的音乐状态，防止覆盖胜利音乐
	MusicManager._saved_stream = null
	MusicManager._saved_position = 0.0
	_on_request_show_victory(0)

# ---- 提取出生点 ----
func _extract_spawn_points(node: Node) -> Array[Vector2i]:
	var points = []
	_find_spawn_points(node, points)
	# 按 spawn_index 排序
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

# ---- 生成默认地形 ----
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
	if TurnManager.current_turn_team != 0:
		print("当前不是玩家回合，无法结束")
		return
	if Globals.is_transitioning or Globals.is_fading:
		print("正在过渡中，无法结束回合")
		return
	
	# ---- 检查是否有 UI 活跃 ----
	if _is_any_ui_active():
		print("有 UI 活跃，稍后重试结束回合")
		# 可选：显示提示，或等待后自动重试
		return

	# ---- 隐藏所有菜单和信息 ----
	SignalBus.request_hide_info.emit()
	SignalBus.request_hide_setting.emit()
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()

	# ---- 将所有己方单位标记为已行动 ----
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

	print("玩家回合结束，切换到敌方回合")
	TurnManager.start_turn(1)   # 敌方回合会被 TurnManager 跳过（非战斗模式）

func _update_cursor_and_mouse():
	# ---- 如果结算界面激活，则保持系统鼠标可见，不进行任何控制 ----
	if _is_reward_ui_active:
		# 确保系统鼠标可见
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
			var target_size = round(CELL_SIZE * _viewport_scale)
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
		if phase in ["menu", "moving", "attacking", "item_target"]:
			should_be_pink = true

	var target_color = Color.FUCHSIA if should_be_pink else Color.WHITE
	if cursor.modulate != target_color:
		cursor.modulate = target_color

func _on_back_camp_pressed():
	Globals.show_confirm(
		self,
		"确定放弃本局游戏吗？进度将丢失，已获得的临时资源将丢弃。",
		"放弃",
		"取消",
		GameState.abandon_and_return_to_camp,
		func(): pass
	)

func _ensure_default_relics():
	if GameState.global_relics.is_empty() and not Globals.unlocked_relics.is_empty():
		print("兜底：遗物为空，根据 unlocked_relics 重新填充")
		for relic_id in Globals.unlocked_relics:
			var inst = ItemInstance.new()
			inst.item_id = relic_id
			inst.count = 1
			GameState.global_relics.append(inst)
			print("自动添加遗物：", relic_id)

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

var _is_showing_relics: bool = false

# ---- 刷新遗物列表 ----
func _refresh_relic_list():
	for child in item_list_container.get_children():
		child.queue_free()
	
	var relics = GameState.get_global_relics()
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
		btn.disabled = true   # 禁用点击
		
		# ---- 悬停显示详情 ----
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

# ---- 修改道具列表按钮 ----
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

# ---- 更新常驻遗物显示 ----
func _update_relic_icons():
	print("_update_relic_icons 被调用")
	for child in relic_icon_container.get_children():
		child.queue_free()
	
	var relics = GameState.get_global_relics()
	print("当前遗物数量：", relics.size())
	if relics.is_empty():
		var label = Label.new()
		label.text = "无遗物"
		label.add_theme_font_size_override("font_size", 6)
		relic_icon_container.add_child(label)
		return
	
	for relic in relics:
		# 修复：使用 RelicManager 而不是 ItemManager
		var data = RelicManager.get_relic_data(relic.item_id)
		if data.is_empty():
			continue
		var label = Label.new()
		label.text = data.get("name", "未知遗物")
		label.add_theme_font_size_override("font_size", 6)
		relic_icon_container.add_child(label)
	print("遗物显示更新完成，共显示 ", relics.size(), " 个")

func show_item_detail(item_id: String):
	if _detail_popup:
		_detail_popup.show_item(item_id)
		_detail_popup.visible = true

func hide_item_detail():
	if _detail_popup:
		_detail_popup.visible = false

func _is_any_ui_active() -> bool:
	return (
		Globals.is_dialogue_active or
		Globals.is_item_get_popup_active or
		Globals.is_equip_menu_active or
		Globals.is_fading or
		Globals.is_transitioning or
		Globals.is_performing_action
	)
