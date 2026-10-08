extends Node

# ---- 交互阶段枚举 ----
enum Phase {
	IDLE,
	MENU,
	MOVING,
	DRAGGING_MOVE,   # ★ 新增
	ATTACKING,
	SETTING,
}

# ---- 核心状态 ----
var selected_unit : Unit = null
var interaction_phase : Phase = Phase.IDLE

# ---- 高亮与目标 ----
var current_highlight_cells : Dictionary = {}
var current_empty_cell : Vector2i = Vector2i(-1, -1)

# ---- 移动后攻击目标预览 ----
var current_move_attack_targets : Dictionary = {}

# ---- 武器攻击相关 ----
var pending_attack_cells : Dictionary = {}

# ---- UI管理器引用 ----
var ui_manager : UIManager = null

const DEBUG_PRINT_UNIT_INFO : bool = false


# ============================================================
#  点击处理
# ============================================================
func handle_click(clicked_cell: Vector2i):
	if not TurnManager.is_battle_ready():
		return
	if TurnManager.is_game_over or TurnManager.is_moving:
		return
	if Globals.is_transitioning or Globals.is_fading:
		return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		print("敌人回合，禁止操作")
		return

	var clicked_unit = UnitManager.get_unit_at_cell(clicked_cell)

	match interaction_phase:
		Phase.IDLE:
			if selected_unit != null and selected_unit.unit_stats.team_id == 1:
				return

			if clicked_unit:
				if clicked_unit.hit_points <= 0:
					return

				SignalBus.request_show_info.emit(clicked_unit)
				current_empty_cell = Vector2i(-1, -1)

				if clicked_unit.unit_stats.team_id == 0:
					selected_unit = clicked_unit
					if clicked_unit.hit_points > 0 and clicked_unit.can_act_this_turn:
						interaction_phase = Phase.MENU
						_print_unit_info(selected_unit)
						SignalBus.request_show_menu.emit(selected_unit)
						SignalBus.request_clear_highlight.emit()
					else:
						interaction_phase = Phase.IDLE
						SignalBus.request_clear_highlight.emit()
				else:
					# ---- 敌方单位预览（威胁版，统一）----
					selected_unit = clicked_unit
					interaction_phase = Phase.IDLE

					var reachable = UnitManager.get_reachable_cells(
						selected_unit.grid_cell,
						selected_unit.unit_stats.move_range,
						selected_unit
					)

					var weapon_data = selected_unit.get_weapon_data()
					var max_range = weapon_data.attack_range if weapon_data else 0
					var min_range = weapon_data.min_attack_range if weapon_data else 0
					var is_healer = (selected_unit.get_weapon_type() == "staff")

					# ★ 威胁范围：从所有可达位置出发，射程覆盖的格子
					var threat_dict : Dictionary = {}
					if max_range > 0:
						for move_cell in reachable.keys():
							for x in range(-max_range, max_range + 1):
								for y in range(-max_range, max_range + 1):
									var dist = abs(x) + abs(y)
									if dist < min_range or dist > max_range:
										continue
									var cell = move_cell + Vector2i(x, y)
									if cell.x < 0 or cell.x >= TerrainManager.grid_size.x:
										continue
									if cell.y < 0 or cell.y >= TerrainManager.grid_size.y:
										continue
									if reachable.has(cell):
										continue
									threat_dict[cell] = true

					current_highlight_cells = reachable
					current_move_attack_targets = threat_dict

					# ★ 颜色：治疗者蓝，其余红
					var attack_color = MapConst.HIGHLIGHT_HEAL if is_healer else MapConst.HIGHLIGHT_ATTACK
					SignalBus.request_show_enemy_preview.emit(reachable, threat_dict, attack_color)
					SoundManager.play_select_sound()

		Phase.MENU:
			return

		Phase.MOVING:
			if current_highlight_cells.has(clicked_cell):
				if selected_unit and selected_unit.can_move() and not UnitManager.is_cell_occupied(clicked_cell):
					var path = UnitManager.calculate_path(selected_unit.grid_cell, clicked_cell, selected_unit)
					if path.size() > 0:
						TurnManager.start_movement(selected_unit, path)
						SignalBus.request_clear_highlight.emit()
						current_highlight_cells = {}
						current_move_attack_targets = {}
						interaction_phase = Phase.IDLE
						selected_unit = null
						SignalBus.request_hide_info.emit()
						current_empty_cell = Vector2i(-1, -1)
						return
				SoundManager.play_invalid_sound()
			else:
				SoundManager.play_invalid_sound()

		Phase.SETTING:
			return

		_:
			pass


# ============================================================
#  右键处理
# ============================================================
func _handle_right_click():
	if not TurnManager.is_battle_ready():
		return
	match interaction_phase:
		Phase.MENU:
			if selected_unit == null or not is_instance_valid(selected_unit):
				SignalBus.request_hide_menu.emit()
				SignalBus.request_clear_highlight.emit()
				SignalBus.request_clear_highlight_unit.emit()
				SignalBus.request_hide_info.emit()
				interaction_phase = Phase.IDLE
				selected_unit = null
				current_empty_cell = Vector2i(-1, -1)
				return

			var unit = selected_unit

			var can_undo = false
			if unit.has_moved:
				if unit.has_attacked:
					can_undo = false
				else:
					if unit.has_acted and unit.moves_since_act <= 1:
						can_undo = true
					elif not unit.has_acted:
						can_undo = true

			if can_undo:
				print("右键：取消移动")
				Globals.suppress_sound = true
				SoundManager.play_cancel_sound()
				TurnManager.cancel_movement(unit)
				unit.moves_since_act -= 1
				SignalBus.request_clear_highlight.emit()
				SignalBus.request_clear_highlight_unit.emit()
				SignalBus.request_hide_info.emit()
				selected_unit = null
				interaction_phase = Phase.IDLE
				current_empty_cell = Vector2i(-1, -1)
				Globals.suppress_sound = false
			else:
				print("右键：取消菜单")
				SignalBus.request_hide_menu.emit()
				SignalBus.request_clear_highlight.emit()
				SignalBus.request_clear_highlight_unit.emit()
				SignalBus.request_hide_info.emit()
				selected_unit = null
				interaction_phase = Phase.IDLE
				current_empty_cell = Vector2i(-1, -1)

		Phase.MOVING:
			if selected_unit == null or not is_instance_valid(selected_unit):
				SignalBus.request_clear_highlight.emit()
				current_highlight_cells = {}
				current_move_attack_targets = {}
				SignalBus.request_hide_info.emit()
				interaction_phase = Phase.IDLE
				current_empty_cell = Vector2i(-1, -1)
				return
			print("右键：取消移动选择，回到菜单")
			Globals.suppress_sound = true
			SoundManager.play_cancel_sound()
			SignalBus.request_clear_highlight.emit()
			current_highlight_cells = {}
			current_move_attack_targets = {}
			SignalBus.request_show_info.emit(selected_unit)
			interaction_phase = Phase.MENU
			SignalBus.request_show_menu.emit(selected_unit)
			current_empty_cell = Vector2i(-1, -1)

		Phase.SETTING:
			SignalBus.request_setting_right_click.emit()

		_:
			if selected_unit != null:
				SignalBus.request_hide_info.emit()
				SignalBus.request_clear_highlight.emit()
				selected_unit = null
				interaction_phase = Phase.IDLE
				current_highlight_cells = {}
				current_move_attack_targets = {}
				current_empty_cell = Vector2i(-1, -1)


# ============================================================
#  鼠标滚轮切换单位
# ============================================================
func handle_wheel(delta: int):
	if not TurnManager.is_battle_ready():
		return
	if Globals.is_transitioning or Globals.is_fading:
		return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return
	if TurnManager.is_moving or TurnManager.is_ai_moving:
		return
	if Globals.is_performing_action:
		return
	if interaction_phase in [Phase.MOVING, Phase.DRAGGING_MOVE, Phase.ATTACKING]:
		return

	if interaction_phase == Phase.SETTING:
		SignalBus.request_hide_setting.emit()
		SignalBus.request_hide_info.emit()
		interaction_phase = Phase.IDLE
		current_empty_cell = Vector2i(-1, -1)

	var units = UnitManager.unit_list.filter(func(u):
		return u.unit_stats.team_id == 0 and u.hit_points > 0
	)
	if units.is_empty():
		return

	units.sort_custom(func(a, b):
		if a.grid_cell.y != b.grid_cell.y:
			return a.grid_cell.y < b.grid_cell.y
		return a.grid_cell.x < b.grid_cell.x
	)

	var current = selected_unit
	var idx = -1
	if current != null and current in units:
		idx = units.find(current)
	else:
		idx = -1

	var new_idx = idx + delta
	if new_idx < 0:
		new_idx = units.size() - 1
	elif new_idx >= units.size():
		new_idx = 0

	var new_unit = units[new_idx]

	if interaction_phase == Phase.MENU:
		SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()
	current_highlight_cells = {}
	current_move_attack_targets = {}
	interaction_phase = Phase.IDLE
	current_empty_cell = Vector2i(-1, -1)

	selected_unit = new_unit
	SignalBus.request_show_info.emit(new_unit)

	if new_unit.hit_points > 0 and new_unit.can_act_this_turn:
		interaction_phase = Phase.MENU
		_print_unit_info(new_unit)
		SignalBus.request_show_menu.emit(new_unit)
	else:
		interaction_phase = Phase.IDLE

	SoundManager.play_select_sound()

	var camera = get_node("/root/Battlefield/Camera2D")
	if camera and camera.has_method("smooth_move_to"):
		camera.smooth_move_to(new_unit.global_position, 0.2, true)
	elif camera and camera.has_method("force_position"):
		camera.force_position(new_unit.global_position)


func _clear_attack_state():
	SignalBus.request_clear_highlight.emit()
	pending_attack_cells = {}
	current_highlight_cells = {}


func on_wait_button_pressed():
	print("待机按钮被点击")
	if selected_unit == null:
		print("待机按钮：selected_unit 为空")
		return
	if interaction_phase == Phase.MENU and selected_unit.can_act_this_turn:
		SignalBus.request_hide_info.emit()
		SoundManager.play_wait_sound()
		var unit = selected_unit
		print("执行待机: ", unit.unit_stats.unit_name)
		TurnManager.finish_unit_action(unit)
		SignalBus.request_dialogue_check.emit(unit)
		selected_unit = null
		interaction_phase = Phase.IDLE
	else:
		print("待机条件不满足")


func on_equip_button_pressed():
	if selected_unit and ui_manager:
		ui_manager.show_equip_menu(selected_unit)


func get_ui_manager() -> UIManager:
	if ui_manager:
		return ui_manager
	var battlefield = get_node("/root/Battlefield")
	if battlefield:
		ui_manager = battlefield.ui_manager
	return ui_manager


# ============================================================
#  输入事件处理
# ============================================================
func handle_input(event: InputEvent, _map_grid_size: Vector2i, _cell_size: int):
	if TurnManager.is_game_over or TurnManager.is_moving:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click()
		return


# ============================================================
#  调试
# ============================================================
func _print_unit_info(unit: Unit):
	if not DEBUG_PRINT_UNIT_INFO:
		return
	print("===== 单位信息 =====")
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	print("姓名: ", display_name)
	print("类型: ", unit.unit_stats.unit_name)
	print("阵营: ", unit.unit_stats.faction if unit.unit_stats.faction != "" else "无")
	print("队伍: ", "玩家" if unit.unit_stats.team_id == 0 else "敌人")
	print("HP: ", unit.hit_points, "/", unit.unit_stats.max_hp)

	var weapon_data = unit.get_weapon_data()
	var weapon_stats = unit.get_weapon_stats()
	var attack = weapon_stats.get("attack", 0)
	var magic_attack = weapon_stats.get("magic_attack", 0)
	print("攻击: ", attack, " (魔法: ", magic_attack, ")")

	print("力量: ", unit.unit_stats.strength)
	print("敏捷: ", unit.unit_stats.dexterity)
	print("智力: ", unit.unit_stats.intelligence)
	print("信仰: ", unit.unit_stats.faith)
	print("感应: ", unit.unit_stats.arcane)
	print("移动力: ", unit.unit_stats.move_range)

	if weapon_data:
		print("攻击范围: ", weapon_data.min_attack_range, "~", weapon_data.attack_range)
	else:
		print("攻击范围: 0~0")

	print("当前格子: ", unit.grid_cell)
	print("已行动: ", unit.has_moved)
	print("可行动: ", unit.can_act_this_turn)
	print("剩余移动: ", unit.remaining_move)
	print("已攻击: ", unit.has_attacked)
	print("已主要行动: ", unit.has_acted)
	print("地形: ", _get_terrain_name(TerrainManager.get_terrain(unit.grid_cell)))
	print("==================")


func _get_terrain_name(type: int) -> String:
	match type:
		TerrainManager.TerrainType.PLAIN: return "平地"
		TerrainManager.TerrainType.FOREST: return "树林"
		TerrainManager.TerrainType.MOUNTAIN: return "山"
		TerrainManager.TerrainType.BUILDING: return "建筑"
		TerrainManager.TerrainType.IMPASSABLE: return "不可通行"
		_: return "未知"
