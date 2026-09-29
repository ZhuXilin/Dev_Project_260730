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

# ---- 设置栏 ----
@onready var setting_panel : PanelContainer = $SettingBar/SettingPanel
@onready var back_camp_btn : Button = $SettingBar/SettingPanel/SettingContainer/BackCampBtn
@onready var setting_btn : Button = $SettingBar/SettingPanel/SettingContainer/SettingBtn
@onready var team_view_btn : Button = $SettingBar/SettingPanel/SettingContainer/TeamViewBtn
@onready var item_list_btn : Button = $SettingBar/SettingPanel/SettingContainer/ItemListBtn
@onready var relic_view_btn : Button = $SettingBar/SettingPanel/SettingContainer/RelicViewBtn

# ---- 队伍查看 ----
@onready var team_view_panel : PanelContainer = $TeamViewLayer/TeamViewPanel
@onready var team_view_container : VBoxContainer = $TeamViewLayer/TeamViewPanel/TeamViewContainer

# ---- 道具列表 ----
@onready var item_list_panel : PanelContainer = $ItemListLayer/ItemListPanel
@onready var item_list_container : VBoxContainer = $ItemListLayer/ItemListPanel/ItemListContainer

# ---- 设置菜单 ----
@onready var setting_menu_panel : Panel = $SettingMenuLayer/SettingMenuPanel

# ---- HUD ----
@onready var speed_indicator : Label = $HUD/SpeedIndicator
@onready var turn_count_label : Label = $HUD/TurnCountIndicator
@onready var end_turn_button : Label = $HUD/EndTurnButton
@onready var relic_icon_container = $HUD/RelicIconContainer

const PERFORMANCE_DURATION : float = 0.5
const ItemGetPopupScene = preload(Config.PATHS.ITEM_GET_POPUP)

const RARE_DROP_CHANCE : Dictionary = {
	MapNode.NodeType.START: 0.05,
	MapNode.NodeType.NORMAL: 0.05,
	MapNode.NodeType.ELITE: 0.25,
	MapNode.NodeType.BOSS: 0.80,
}

# ---- 拆分模块 ----
var _map_loader : MapLoader = null
var _non_combat_handler : NonCombatHandler = null
var _function_handler : FunctionHandler = null
var _cursor_controller : CursorController = null
var _panel_manager : PanelManager = null
var _ui_binder : UIBinder = null

# ---- 状态 ----
var map_grid_size : Vector2i = MapConst.DEFAULT_MAP_SIZE
var _initialized : bool = false
var _battle_start_event_id : String = ""
var map_functions : Dictionary = {}
var _turn_changed_locked : bool = false
var is_non_combat_mode: bool = false
var non_combat_back_button: Button = null
var current_node_type: int = MapNode.NodeType.NORMAL
var _victory_processed: bool = false
var _is_reward_ui_active: bool = false


func _ready():
	_victory_processed = false
	_is_reward_ui_active = false

	# ---- 节点 null 检查 ----
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

	# ---- 拆分模块初始化 ----
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

	_ui_binder = UIBinder.new(self)
	add_child(_ui_binder)

	# ---- UnitManager 信号（非 UI）----
	if not UnitManager.unit_removed.is_connected(_on_unit_removed_death):
		UnitManager.unit_removed.connect(_on_unit_removed_death)
	if not UnitManager.unit_removed.is_connected(_on_unit_removed_for_vengeance):
		UnitManager.unit_removed.connect(_on_unit_removed_for_vengeance)

	# ---- HUD 初始化 ----
	if end_turn_button:
		end_turn_button.text = "鼠标中键结束回合"
		end_turn_button.visible = not is_non_combat_mode

	if _initialized:
		return
	_initialized = true
	_cursor_controller.init_cursor()

	team_view_panel.visible = false
	item_list_panel.visible = false
	setting_menu_panel.visible = false

	if victory_panel:
		victory_panel.visible = false

	# ---- ★ 一次绑定所有 UI 信号（Managers + 按钮 + SignalBus + Animator）----
	_ui_binder.bind_all()

	if turn_overlay:
		turn_overlay.modulate = Color(1, 1, 1, 0)
		Globals.is_fading = false

	# ---- 地图加载 ----
	if GameState.current_map_data:
		var map_to_load = GameState.current_map_data
		if not map_to_load.scene:
			print("警告：当前地图数据无效，使用默认地图")
			_map_loader.load_default_map()
		else:
			print("加载地图：", map_to_load.map_name)
			_map_loader.load_map(map_to_load)
	else:
		print("没有地图数据，加载默认地图")
		_map_loader.load_default_map()

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
	_cursor_controller.clear_attack_indicator()

	# ---- MenuBlocker ----
	if menu_blocker:
		menu_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		menu_blocker.visible = false
		if not menu_blocker.gui_input.is_connected(_on_menu_blocker_clicked):
			menu_blocker.gui_input.connect(_on_menu_blocker_clicked)
		menu_blocker.size = Vector2(map_grid_size.x * MapConst.CELL_SIZE, map_grid_size.y * MapConst.CELL_SIZE)
		menu_blocker.position = Vector2.ZERO
		menu_blocker.z_index = UIConst.MENU_BLOCKER_Z_INDEX

	# ---- 非战斗 / 战斗分支 ----
	var is_non_combat = GameState.current_map_data and GameState.current_map_data.node_type in [
		MapNode.NodeType.SHOP,
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
			print("BackCampBtn 已连接（非战斗）")

		TurnManager.start_turn(TurnManager.Team.PLAYER)
		_panel_manager.update_relic_icons()
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

	_panel_manager.update_relic_icons()

	_victory_processed = false
	_is_reward_ui_active = false

	# ★ 全队阵亡检测
	if not is_non_combat_mode:
		var alive_player : int = 0
		for u in UnitManager.unit_list:
			if u.unit_stats.team_id == 0 and u.hit_points > 0:
				alive_player += 1
		if alive_player == 0:
			print("[Battlefield] 无存活玩家单位，判定失败")
			TurnManager.is_game_over = true
			await get_tree().process_frame
			SignalBus.request_show_victory.emit(1)
			return

	_apply_team_buffs()
	print("Battlefield _ready 完成")


func _on_unit_removed_for_vengeance(unit: Unit, team: int):
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


func _on_unit_removed_death(unit: Unit, team: int):
	if team != 0:
		return
	if not is_instance_valid(unit):
		return
	if unit.hit_points > 0:
		return

	for ud in GameState.party:
		if ud.unit_name == unit.unit_stats.unit_name and ud.display_name == unit.unit_stats.display_name:
			ud.is_dead = true
			ud.hit_points = 0
			print("[永久死亡] %s 阵亡" % ud.display_name)
			break


func _exit_tree():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cursor.visible = false
	if _cursor_controller:
		_cursor_controller.cleanup()
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
	_cursor_controller.update_cursor_and_mouse()


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
	_function_handler.clear_function_trigger(unit)
	TurnManager.on_movement_finished(unit)
	camera_controller.follow_mouse()
	SignalBus.request_clear_highlight.emit()


func _on_ai_movement_finished(unit: Unit):
	_function_handler.clear_function_trigger(unit)
	TurnManager.on_ai_movement_finished(unit)
	camera_controller.follow_mouse()
	SignalBus.request_clear_highlight.emit()


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
	_cursor_controller.clear_attack_indicator()
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
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			player_units.append(unit)
	GameState.sync_units_from_battlefield(player_units)

	if Globals.is_map_mode:
		print("当前地图节点类型: ", current_node_type, " 是否为BOSS: ", is_boss)

		if is_win:
			var is_non_combat_node = current_node_type in [
				MapNode.NodeType.SHOP,
				MapNode.NodeType.TREASURE,
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

				GameState.current_reward_rare_datas.clear()
				var rare_drop : Dictionary = _roll_rare_drop_for_node(current_node_type)
				if not rare_drop.is_empty():
					var rare_data : ItemData = _apply_rare_drop(rare_drop)
					if rare_data:
						GameState.current_reward_rare_datas.append(rare_data)

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

	await _function_handler.apply_map_functions(team)
	_panel_manager.update_relic_icons()
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


# ===================== 坐标换算 =====================
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


func _on_equip_btn_pressed():
	InputManager.on_equip_button_pressed()


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

	for rare_data in GameState.current_reward_rare_datas:
		if rare_data:
			reward_item_datas.append(rare_data)
			print("添加稀有掉落显示: ", rare_data.name)

	# ★ 遗物解锁（MapData + Node 合并，去重，只显示新解锁的）
	var all_relic_ids : Array = []
	if GameState.current_map_data and GameState.current_map_data.unlock_relics:
		all_relic_ids.append_array(GameState.current_map_data.unlock_relics)
	if GameState.current_node_unlock_relics:
		all_relic_ids.append_array(GameState.current_node_unlock_relics)

	if not all_relic_ids.is_empty():
		var seen : Dictionary = {}
		var unique_relics : Array = []
		for rid in all_relic_ids:
			if rid is String and rid != "" and not seen.has(rid):
				seen[rid] = true
				unique_relics.append(rid)

		var newly : Array = []
		for rid in unique_relics:
			if not RelicManager.is_relic_unlocked(rid):
				newly.append(rid)

		RelicManager.unlock_relics_by_ids(unique_relics)

		for rid in newly:
			var rd : Dictionary = RelicManager.get_relic_data(rid)
			var virtual_data := ItemData.new()
			virtual_data.id = "unlock_relic_" + rid
			virtual_data.name = "★ 新遗物：" + rd.get("name", rid)
			virtual_data.description = rd.get("description", "")
			var icon_path : String = rd.get("icon", "")
			if icon_path != "" and ResourceLoader.exists(icon_path):
				virtual_data.icon = load(icon_path)
			reward_item_datas.append(virtual_data)
		if not newly.is_empty():
			print("[Battlefield] 本节点解锁 %d 个遗物" % newly.size())

	GameState.current_node_unlock_relics.clear()

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

			print("弹出英灵殿")
			var hero_shrine_scene = load(Config.PATHS.HERO_SHRINE_UI)
			if hero_shrine_scene:
				var hero_shrine = hero_shrine_scene.instantiate()
				add_child(hero_shrine)
				hero_shrine.setup_map(1)
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


# ===================== 结束回合 =====================
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
#  InputManager 右键回调的转发（避免破坏对外接口）
# ============================================================
func _on_team_view_btn_pressed():
	_panel_manager.on_team_view_btn_pressed()


func _on_item_list_btn_pressed():
	_panel_manager.on_item_list_btn_pressed()


# ============================================================
#  战斗开始：遗物属性应用 + 熔铸持久buff
# ============================================================
func _apply_team_buffs():
	var relic_stats = GameState.get_global_relic_stats()
	var relic_effects = GameState.get_global_relic_effects()

	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0:
			continue

		var sac_buffs : Dictionary = unit.unit_stats.get_sacrifice_buffs()
		for btype in sac_buffs:
			var bvalue : float = sac_buffs[btype]
			match btype:
				"attack_percent":
					unit.buff_attack_percent += bvalue
				"crit_damage_bonus":
					unit.buff_crit_damage_bonus += bvalue
				"defense_flat":
					unit.buff_defense_flat += int(bvalue)
				"damage_reduction":
					unit.buff_damage_reduction += bvalue
				"heal_bonus":
					unit.relic_heal_bonus += bvalue
				"counter_damage_bonus":
					unit.relic_counter_damage_bonus += bvalue
				_:
					pass
		if not sac_buffs.is_empty():
			print("[Battlefield] %s 熔铸 buff: %s" % [
				unit.unit_stats.display_name, sac_buffs])

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

		unit.relic_first_attack_crit_available = bool(relic_effects.get("first_attack_crit", false))
		unit.relic_low_hp_damage_reduce = float(relic_effects.get("low_hp_damage_reduce", 0.0))
		unit.relic_kill_grants_extra_move = int(relic_effects.get("kill_grants_extra_move", 0))
		unit.relic_first_spell_free_available = bool(relic_effects.get("first_spell_free", false))
		unit.relic_turn_first_hit_regen = float(relic_effects.get("turn_first_hit_regen", 0.0))
		unit.relic_strength_scale_damage = float(relic_effects.get("strength_scale_damage", 0.0))
		unit.relic_counter_damage_bonus = float(relic_effects.get("counter_damage_bonus", 0.0))
		unit.relic_heal_bonus = float(relic_effects.get("heal_bonus", 0.0))
		unit.relic_auto_revive_available = bool(relic_effects.get("auto_revive_once", false))

		unit.update_hp_label()

	print("[Battlefield] 遗物已应用 | 属性：", relic_stats, " 效果：", relic_effects)


# ============================================================
#  稀有掉落
# ============================================================
func _roll_rare_drop_for_node(node_type: int) -> Dictionary:
	var chance : float = RARE_DROP_CHANCE.get(node_type, 0.0)
	if randf() > chance:
		return {}

	var pool : Array = []

	var owned_relics : Dictionary = {}
	for relic in GameState.get_relics_from_passives():
		owned_relics[relic.item_id] = true
	for rid in RelicManager.get_unlocked_relics():
		if not owned_relics.has(rid):
			pool.append({"type": "relic", "id": rid})

	for ref_id in RefineManager.get_all_ids():
		if RefineManager.is_recipe_unlocked(ref_id):
			pool.append({"type": "refine", "id": ref_id})

	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if not d: continue
		if d.type != "armor": continue
		if d.quality not in ["epic", "legendary"]: continue
		if d.price <= 0: continue
		pool.append({"type": "armor", "id": iid})

	if pool.is_empty():
		return {}
	pool.shuffle()
	return pool[0]


func _apply_rare_drop(drop : Dictionary) -> ItemData:
	var rtype : String = drop.get("type", "")
	var rid : String = drop.get("id", "")
	if rid == "":
		return null
	var virtual_data : ItemData = null

	match rtype:
		"relic":
			var rd : Dictionary = RelicManager.get_relic_data(rid)
			if rd.is_empty(): return null
			RelicManager.unlock_relic(rid)
			var inst := ItemInstance.new()
			inst.item_id = rid
			inst.count = 1
			if not GameState.add_relic_to_passive_slot(inst):
				print("[稀有掉落] 遗物 %s 解锁但未入槽（槽满）" % rid)
			virtual_data = ItemData.new()
			virtual_data.id = "rare_relic_" + rid
			virtual_data.name = "★ 遗物：" + rd.get("name", rid)
			virtual_data.description = rd.get("description", "")
			var icon_path : String = rd.get("icon", "")
			if icon_path != "" and ResourceLoader.exists(icon_path):
				virtual_data.icon = load(icon_path)
			print("[稀有掉落] 遗物 %s" % rid)

		"refine":
			var recipe : Dictionary = RefineManager.get_recipe(rid)
			if recipe.is_empty(): return null
			GameState.refined_items[rid] = GameState.refined_items.get(rid, 0) + 1
			virtual_data = ItemData.new()
			virtual_data.id = "rare_refine_" + rid
			virtual_data.name = "★ 精炼：" + recipe.get("name", rid)
			virtual_data.description = recipe.get("description", "")
			print("[稀有掉落] 精炼 %s" % rid)

		"armor":
			var d : ItemData = ItemManager.get_item_data(rid)
			if not d: return null
			var inst2 := ItemInstance.new()
			inst2.item_id = rid
			inst2.count = 1
			GameState.pending_forge_rewards.append(inst2)
			virtual_data = ItemData.new()
			virtual_data.id = "rare_armor_" + rid
			virtual_data.name = "★ " + d.name
			virtual_data.description = d.description
			virtual_data.icon = d.icon
			virtual_data.quality = d.quality
			print("[稀有掉落] 防具 %s" % rid)

	return virtual_data
