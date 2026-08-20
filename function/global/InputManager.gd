extends Node

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

# ---- 核心状态 ----
var selected_unit : Unit = null
var interaction_phase : String = "idle"

# ---- 高亮与目标 ----
var current_highlight_cells : Dictionary = {}
var attackable_targets : Array = []
var current_empty_cell : Vector2i = Vector2i(-1, -1)

# ---- 移动后攻击目标预览 ----
var current_move_attack_targets : Dictionary = {}

# ---- 道具相关 ----
var pending_item_id : String = ""
var pending_item_effect : Dictionary = {}
var pending_is_attack_item : bool = false

# ---- 武器攻击相关 ----
var pending_attack_weapon_id : String = ""
var pending_attack_cells : Dictionary = {}

# ---- UI管理器引用 ----
var ui_manager : UIManager = null

# ============================================================
#  点击处理（主要输入路由）
# ============================================================
func handle_click(clicked_cell: Vector2i):
	if TurnManager.is_game_over or TurnManager.is_moving:
		return
	if TurnManager.current_turn_team != 0:
		print("敌人回合，禁止操作")
		return

	var clicked_unit = UnitManager.get_unit_at_cell(clicked_cell)

	match interaction_phase:
		"idle":
			if selected_unit != null and selected_unit.unit_stats.team_id == 1 and interaction_phase == "idle":
				return

			if clicked_unit:
				SignalBus.request_show_info.emit(clicked_unit)
				current_empty_cell = Vector2i(-1, -1)

				if clicked_unit.unit_stats.team_id == 0:
					selected_unit = clicked_unit
					if clicked_unit.hit_points > 0 and clicked_unit.can_act_this_turn:
						interaction_phase = "menu"
						_print_unit_info(selected_unit)
						SignalBus.request_show_menu.emit(selected_unit)
						SignalBus.request_clear_highlight.emit()
					else:
						interaction_phase = "idle"
						SignalBus.request_clear_highlight.emit()
				else:
					# ---- 敌方单位预览 ----
					selected_unit = clicked_unit
					interaction_phase = "idle"
					var reachable = UnitManager.get_reachable_cells(
						selected_unit.grid_cell,
						selected_unit.unit_stats.move_range,
						selected_unit
					)
					var weapon_data = selected_unit.get_weapon_data()
					var max_range = weapon_data.attack_range if weapon_data else 0
					var min_range = weapon_data.min_attack_range if weapon_data else 0
					var is_healer = (selected_unit.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL)
					var attack_preview = {}

					# 计算敌方单位移动到每个可达格后能攻击的范围
					for move_cell in reachable.keys():
						for x in range(-max_range, max_range + 1):
							for y in range(-max_range, max_range + 1):
								var dist = abs(x) + abs(y)
								if dist < min_range or dist > max_range:
									continue
								var cell = move_cell + Vector2i(x, y)
								if cell.x < 0 or cell.x >= TerrainManager.grid_size.x or cell.y < 0 or cell.y >= TerrainManager.grid_size.y:
									continue
								if is_healer:
									var target = UnitManager.get_unit_at_cell(cell)
									if target and target.unit_stats.team_id == 1 and target.hit_points > 0 and target != selected_unit:
										attack_preview[cell] = true
								else:
									var target = UnitManager.get_unit_at_cell(cell)
									if target and target.unit_stats.team_id == 0 and target.hit_points > 0:
										attack_preview[cell] = true

					current_highlight_cells = reachable
					current_move_attack_targets = attack_preview
					var attack_color = Color(0.2, 0.5, 0.4, 0.7) if is_healer else Color(0.7, 0.1, 0.2, 0.7)
					SignalBus.request_show_enemy_preview.emit(reachable, attack_preview, attack_color)
					SoundManager.play_select_sound()
			else:
				# 点击空地
				if selected_unit == null:
					SignalBus.request_show_info.emit(null)
					SignalBus.request_show_setting.emit()
					SoundManager.play_select_sound()
					interaction_phase = "setting"
					SignalBus.request_clear_highlight.emit()
					current_empty_cell = clicked_cell
				else:
					if interaction_phase == "menu":
						SignalBus.request_hide_menu.emit()
						interaction_phase = "idle"
					SignalBus.request_show_info.emit(null)
					SignalBus.request_clear_highlight.emit()
					current_highlight_cells = {}
					current_move_attack_targets = {}
					current_empty_cell = clicked_cell
					SoundManager.play_select_sound()

		"menu":
			return

		"moving":
			if current_highlight_cells.has(clicked_cell):
				if selected_unit and selected_unit.can_move() and not UnitManager.is_cell_occupied(clicked_cell):
					var path = UnitManager.calculate_path(selected_unit.grid_cell, clicked_cell, selected_unit)
					if path.size() > 0:
						TurnManager.start_movement(selected_unit, path)
						SignalBus.request_clear_highlight.emit()
						current_highlight_cells = {}
						current_move_attack_targets = {}
						interaction_phase = "idle"
						selected_unit = null
						SignalBus.request_hide_info.emit()
						current_empty_cell = Vector2i(-1, -1)
						return
				SoundManager.play_invalid_sound()
			else:
				SoundManager.play_invalid_sound()

		"attacking":
			if pending_attack_cells.has(clicked_cell):
				var target_unit = UnitManager.get_unit_at_cell(clicked_cell)
				if target_unit:
					var is_healer = false
					if pending_attack_weapon_id != "":
						var data = ItemManager.get_item_data(pending_attack_weapon_id)
						if data and data.type == "weapon" and data.stats.get("heal_amount", 0) > 0:
							is_healer = true
					var is_valid_target = false
					if is_healer:
						if target_unit.unit_stats.team_id == selected_unit.unit_stats.team_id:
							is_valid_target = true
					else:
						if target_unit.unit_stats.team_id != selected_unit.unit_stats.team_id:
							is_valid_target = true
					if is_valid_target:
						SignalBus.request_clear_highlight.emit()
						pending_attack_cells = {}
						current_highlight_cells = {}
						await CombatManager.execute_attack(selected_unit, target_unit)
						_clear_attack_state()
						return
				SoundManager.play_invalid_sound()
			else:
				SoundManager.play_invalid_sound()

		"item_target":
			# 道具使用仍保留（但单位已无消耗品，所以不会触发）
			if clicked_unit:
				var targets = []
				if ui_manager:
					targets = ui_manager.get_usable_targets(selected_unit, pending_item_effect)
				if clicked_unit in targets:
					var unit = selected_unit
					if not unit:
						SoundManager.play_invalid_sound()
						return
					Globals.is_performing_action = true
					var success = ItemManager.use_item_on_target(pending_item_id, unit, clicked_unit)
					if success:
						SignalBus.request_clear_highlight.emit()
						if pending_is_attack_item:
							unit.mark_attacked()
						else:
							unit.mark_non_attack_action()
						await get_tree().create_timer(CombatManager.PERFORMANCE_DURATION).timeout
						Globals.is_performing_action = false
						interaction_phase = "idle"
						pending_item_id = ""
						pending_item_effect = {}
						pending_is_attack_item = false
						InputManager.selected_unit = unit
						interaction_phase = "menu"
						SignalBus.request_show_menu.emit(unit)
						return
					else:
						Globals.is_performing_action = false
			SoundManager.play_invalid_sound()

		"setting":
			return

		_:
			pass

# ============================================================
#  右键处理
# ============================================================
func _handle_right_click():
	match interaction_phase:
		"menu":
			if selected_unit == null or not is_instance_valid(selected_unit):
				SignalBus.request_hide_menu.emit()
				SignalBus.request_clear_highlight.emit()
				SignalBus.request_clear_highlight_unit.emit()
				SignalBus.request_hide_info.emit()
				interaction_phase = "idle"
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
				interaction_phase = "idle"
				current_empty_cell = Vector2i(-1, -1)
			else:
				print("右键：取消菜单")
				SignalBus.request_hide_menu.emit()
				SignalBus.request_clear_highlight.emit()
				SignalBus.request_clear_highlight_unit.emit()
				SignalBus.request_hide_info.emit()
				selected_unit = null
				interaction_phase = "idle"
				current_empty_cell = Vector2i(-1, -1)

		"attacking":
			if selected_unit == null or not is_instance_valid(selected_unit):
				SignalBus.request_clear_highlight.emit()
				attackable_targets = []
				current_highlight_cells = {}
				pending_attack_cells = {}
				pending_attack_weapon_id = ""
				interaction_phase = "idle"
				current_empty_cell = Vector2i(-1, -1)
				return
			print("右键：取消攻击/治疗选择")
			Globals.suppress_sound = true
			SoundManager.play_cancel_sound()
			SignalBus.request_clear_highlight.emit()
			attackable_targets = []
			current_highlight_cells = {}
			pending_attack_cells = {}
			pending_attack_weapon_id = ""
			SignalBus.request_show_info.emit(selected_unit)
			interaction_phase = "menu"
			SignalBus.request_show_menu.emit(selected_unit)
			current_empty_cell = Vector2i(-1, -1)

		"moving":
			if selected_unit == null or not is_instance_valid(selected_unit):
				SignalBus.request_clear_highlight.emit()
				current_highlight_cells = {}
				current_move_attack_targets = {}
				SignalBus.request_hide_info.emit()
				interaction_phase = "idle"
				current_empty_cell = Vector2i(-1, -1)
				return
			print("右键：取消移动选择，回到菜单")
			Globals.suppress_sound = true
			SoundManager.play_cancel_sound()
			SignalBus.request_clear_highlight.emit()
			current_highlight_cells = {}
			current_move_attack_targets = {}
			SignalBus.request_show_info.emit(selected_unit)
			interaction_phase = "menu"
			SignalBus.request_show_menu.emit(selected_unit)
			current_empty_cell = Vector2i(-1, -1)

		"setting":
			var battlefield = get_node("/root/Battlefield")
			if battlefield:
				if battlefield.team_view_panel.visible:
					battlefield._on_team_view_btn_pressed()
					return
				elif battlefield.item_list_panel.visible:
					battlefield._on_item_list_btn_pressed()
					return
				elif battlefield.setting_menu_panel.visible:
					battlefield.setting_menu_panel.visible = false
					return

			SignalBus.request_hide_setting.emit()
			SignalBus.request_hide_info.emit()
			interaction_phase = "idle"
			current_empty_cell = Vector2i(-1, -1)

		"item_target":
			if selected_unit == null or not is_instance_valid(selected_unit):
				pending_item_id = ""
				pending_item_effect = {}
				pending_is_attack_item = false
				interaction_phase = "idle"
				SignalBus.request_clear_highlight.emit()
				current_empty_cell = Vector2i(-1, -1)
				return
			Globals.suppress_sound = true
			pending_item_id = ""
			pending_item_effect = {}
			pending_is_attack_item = false
			interaction_phase = "menu"
			SignalBus.request_clear_highlight.emit()
			SignalBus.request_show_menu.emit(selected_unit)

		_:
			if selected_unit != null:
				SignalBus.request_hide_info.emit()
				SignalBus.request_clear_highlight.emit()
				selected_unit = null
				interaction_phase = "idle"
				current_highlight_cells = {}
				current_move_attack_targets = {}
				current_empty_cell = Vector2i(-1, -1)

# ============================================================
#  鼠标滚轮切换单位
# ============================================================
func handle_wheel(delta: int):
	if Globals.is_transitioning or Globals.is_fading:
		return
	if TurnManager.current_turn_team != 0:
		return
	if TurnManager.is_moving or TurnManager.is_ai_moving:
		return
	if Globals.is_performing_action:
		return
	if interaction_phase in ["moving", "attacking"]:
		return

	if interaction_phase == "setting":
		SignalBus.request_hide_setting.emit()
		SignalBus.request_hide_info.emit()
		interaction_phase = "idle"
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

	if interaction_phase == "menu":
		SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()
	current_highlight_cells = {}
	current_move_attack_targets = {}
	interaction_phase = "idle"
	current_empty_cell = Vector2i(-1, -1)

	selected_unit = new_unit
	SignalBus.request_show_info.emit(new_unit)

	if new_unit.hit_points > 0 and new_unit.can_act_this_turn:
		interaction_phase = "menu"
		_print_unit_info(new_unit)
		SignalBus.request_show_menu.emit(new_unit)
	else:
		interaction_phase = "idle"

	SoundManager.play_select_sound()

	var camera = get_node("/root/Battlefield/Camera2D")
	if camera and camera.has_method("smooth_move_to"):
		if camera.has_method("cancel_smooth_move"):
			camera.cancel_smooth_move()
		camera.smooth_move_to(new_unit.global_position, 0.2, true)
	else:
		if camera and camera.has_method("force_position"):
			camera.force_position(new_unit.global_position)

# ============================================================
#  攻击辅助
# ============================================================
func _start_attack_target_selection(unit: Unit, weapon_id: String):
	print("=== 进入 _start_attack_target_selection ===")
	print("单位: ", unit.unit_stats.unit_name, " 武器ID: ", weapon_id)
	pending_attack_weapon_id = weapon_id
	var data = ItemManager.get_item_data(weapon_id)
	if not data or data.type != "weapon":
		print("错误：武器数据不存在或类型错误")
		pending_attack_weapon_id = ""
		return

	print("武器名称: ", data.name)
	print("攻击范围: ", data.min_attack_range, " ~ ", data.attack_range)
	var max_range = data.attack_range
	var min_range = data.min_attack_range
	if max_range == 0 and min_range == 0:
		print("警告：武器射程为0，无法攻击")
		pending_attack_weapon_id = ""
		return

	var attack_range_dict = {}
	for x in range(-max_range, max_range+1):
		for y in range(-max_range, max_range+1):
			var dist = abs(x) + abs(y)
			if dist < min_range or dist > max_range:
				continue
			var cell = unit.grid_cell + Vector2i(x, y)
			if cell.x < 0 or cell.x >= TerrainManager.grid_size.x or cell.y < 0 or cell.y >= TerrainManager.grid_size.y:
				continue
			attack_range_dict[cell] = true

	if attack_range_dict.is_empty():
		print("警告：攻击范围为空，无法攻击")
		pending_attack_weapon_id = ""
		return

	pending_attack_cells = attack_range_dict
	current_highlight_cells = attack_range_dict
	interaction_phase = "attacking"

	var battlefield = get_node("/root/Battlefield")
	if battlefield and battlefield.has_method("_show_attack_highlight"):
		battlefield._show_attack_highlight(attack_range_dict, unit)
	else:
		print("无法获取 Battlefield 或方法不存在")

	SignalBus.request_hide_info.emit()
	SignalBus.request_hide_menu.emit()
	print("攻击范围格子数: ", attack_range_dict.size())
	print("攻击范围格子列表: ", attack_range_dict.keys())

func _clear_attack_state():
	SignalBus.request_clear_highlight.emit()
	pending_attack_cells = {}
	current_highlight_cells = {}
	pending_attack_weapon_id = ""

# ============================================================
#  按钮回调（由Battlefield调用）
# ============================================================
func on_move_button_pressed():
	print("移动按钮被点击")
	if selected_unit == null:
		print("移动按钮：selected_unit 为空")
		return
	if interaction_phase == "menu" and selected_unit.can_move():
		SignalBus.request_hide_info.emit()
		var reachable = UnitManager.get_reachable_cells(selected_unit.grid_cell, selected_unit.remaining_move, selected_unit)
		if reachable.size() <= 1:
			print("单位无法移动到任何格子")
			selected_unit.remaining_move = 0
			SignalBus.request_show_menu.emit(selected_unit)
			return
		var attack_targets = {}
		var weapon_data = selected_unit.get_weapon_data()
		var max_range = weapon_data.attack_range if weapon_data else 0
		var min_range = weapon_data.min_attack_range if weapon_data else 0
		var is_healer = (selected_unit.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL)
		for unit in UnitManager.unit_list:
			if unit.hit_points <= 0:
				continue
			if is_healer:
				if unit.unit_stats.team_id != selected_unit.unit_stats.team_id:
					continue
				if unit == selected_unit:
					continue
			else:
				if unit.unit_stats.team_id == selected_unit.unit_stats.team_id:
					continue
			var can_reach = false
			for move_cell in reachable.keys():
				if move_cell == selected_unit.grid_cell:
					continue
				var dist = abs(move_cell.x - unit.grid_cell.x) + abs(move_cell.y - unit.grid_cell.y)
				if dist >= min_range and dist <= max_range:
					can_reach = true
					break
			if can_reach:
				attack_targets[unit.grid_cell] = true
		current_highlight_cells = reachable
		current_move_attack_targets = attack_targets
		interaction_phase = "moving"
		SignalBus.request_highlight.emit(reachable)
		if attack_targets.size() > 0:
			SignalBus.request_highlight.emit(attack_targets)
		SignalBus.request_hide_menu.emit()
	else:
		print("移动条件不满足")

func on_attack_button_pressed():
	# 强制使用当前装备武器，不弹出武器选择
	if selected_unit == null or interaction_phase != "menu":
		return
	if selected_unit.has_attacked or not selected_unit.can_act_this_turn or selected_unit.has_acted:
		return

	var weapon_id = selected_unit.get_equipped_weapon_id()
	if weapon_id == "":
		print("没有装备武器，无法攻击")
		return
	if weapon_id == "":
		print("没有装备武器")
		return
	# 直接进入攻击目标选择
	_start_attack_target_selection(selected_unit, weapon_id)

func on_wait_button_pressed():
	print("待机按钮被点击")
	if selected_unit == null:
		print("待机按钮：selected_unit 为空")
		return
	if interaction_phase == "menu" and selected_unit.can_act_this_turn:
		SignalBus.request_hide_info.emit()
		SoundManager.play_wait_sound()
		var unit = selected_unit
		print("执行待机: ", unit.unit_stats.unit_name)
		TurnManager.finish_unit_action(unit)
		SignalBus.request_dialogue_check.emit(unit)
		selected_unit = null
		interaction_phase = "idle"
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
#  输入事件处理（由Battlefield转发）
# ============================================================
func handle_input(event: InputEvent, _map_grid_size: Vector2i, _cell_size: int):
	if TurnManager.is_game_over or TurnManager.is_moving:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click()
		return

# ============================================================
#  调试信息
# ============================================================
func _print_unit_info(unit: Unit):
	print("===== 单位信息 =====")
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	print("姓名: ", display_name)
	print("类型: ", unit.unit_stats.unit_name)
	print("阵营: ", unit.unit_stats.faction if unit.unit_stats.faction != "" else "无")
	print("队伍: ", "玩家" if unit.unit_stats.team_id == 0 else "敌人")
	print("HP: ", unit.hit_points, "/", unit.unit_stats.max_hp)
	
	# 获取武器数据（用于范围和属性）
	var weapon_data = unit.get_weapon_data()
	var weapon_stats = unit.get_weapon_stats()   # 只包含 stats 字典
	
	# 攻击力（从 stats 中读取）
	var attack = weapon_stats.get("attack", 0)
	var magic_attack = weapon_stats.get("magic_attack", 0)
	print("攻击: ", attack, " (魔法: ", magic_attack, ")")
	
	print("防御: ", unit.unit_stats.defense)
	print("魔防: ", unit.unit_stats.magic_defense)
	print("技巧: ", unit.unit_stats.skill)
	print("速度: ", unit.unit_stats.speed)
	print("幸运: ", unit.unit_stats.luck)
	print("移动力: ", unit.unit_stats.move_range)
	
	# 攻击范围（从 weapon_data 读取）
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
