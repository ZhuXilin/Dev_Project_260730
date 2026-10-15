extends Node

enum Phase {
	IDLE,
	SETTING,
	DRAGGING_MOVE,
}

var selected_unit : Unit = null
var interaction_phase : Phase = Phase.IDLE

var current_highlight_cells : Dictionary = {}
var current_empty_cell : Vector2i = Vector2i(-1, -1)
var current_move_attack_targets : Dictionary = {}
var pending_attack_cells : Dictionary = {}

var ui_manager : UIManager = null


func handle_click(clicked_cell: Vector2i):
	if not TurnManager.is_battle_ready():
		return
	if TurnManager.is_game_over or TurnManager.is_moving:
		return
	if Globals.is_transitioning or Globals.is_fading:
		return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return

	var clicked_unit = UnitManager.get_unit_at_cell(clicked_cell)

	if clicked_unit != null:
		if clicked_unit.unit_stats.team_id != 0:
			# ★ 敌方 → 走 Battlefield.select_unit
			var bf = get_node_or_null("/root/Battlefield")
			if bf and bf.has_method("select_unit"):
				bf.select_unit(clicked_unit)
		return

	# ---- 点空地 ----
	if interaction_phase == Phase.SETTING:
		SignalBus.request_show_info.emit(null)
		current_empty_cell = clicked_cell
		return

	if selected_unit == null:
		SignalBus.request_show_info.emit(null)
		SignalBus.request_show_setting.emit()
		SoundManager.play_select_sound()
		interaction_phase = Phase.SETTING
		SignalBus.request_clear_highlight.emit()
		current_empty_cell = clicked_cell
	else:
		SignalBus.request_hide_info.emit()
		SignalBus.request_clear_highlight.emit()
		selected_unit = null
		interaction_phase = Phase.IDLE
		current_empty_cell = clicked_cell


func _handle_right_click():
	if not TurnManager.is_battle_ready():
		return

	if interaction_phase == Phase.SETTING:
		SignalBus.request_setting_right_click.emit()
		return

	# ★ v4.1 优化：右键分层
	#   优先级 1：有选中单位 → 只取消选中（无副作用，含隐藏信息面板）
	#   优先级 2：无选中 + 刚移动过的单位 → 撤销移动（有副作用）
	#   这样：点击单位后的第一次右键 = 取消选中；第二次右键 = 撤销移动

	# ---- 优先级 1：取消选中 ----
	if selected_unit != null and is_instance_valid(selected_unit):
		SoundManager.play_cancel_sound()
		SignalBus.request_hint_override.emit("已取消选中", 1.0)
		SignalBus.request_clear_highlight.emit()
		SignalBus.request_clear_highlight_unit.emit()
		SignalBus.request_hide_info.emit()   # ★ 关键：确保信息面板消失
		selected_unit = null
		interaction_phase = Phase.IDLE
		return

	# ---- 优先级 2：撤销移动 ----
	var m : Unit = TurnManager.last_moved_unit
	if m != null and is_instance_valid(m) and m.has_moved and not m.has_attacked:
		SoundManager.play_cancel_sound()
		TurnManager.cancel_movement(m)
		m.moves_since_act -= 1
		SignalBus.request_hint_override.emit("已撤销操作", 1.0)
		SignalBus.request_clear_highlight.emit()
		SignalBus.request_clear_highlight_unit.emit()
		SignalBus.request_hide_info.emit()   # ★ 补上：撤销移动后也要隐藏信息面板
		selected_unit = null
		interaction_phase = Phase.IDLE
		return

	# ---- 都不是：轻量级清理 ----
	SoundManager.play_cancel_sound()
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_clear_highlight_unit.emit()
	SignalBus.request_hide_info.emit()
	interaction_phase = Phase.IDLE


func handle_wheel(delta: int):
	if Globals.is_transitioning or Globals.is_fading:
		return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return
	if TurnManager.is_moving or TurnManager.is_ai_moving:
		return
	if Globals.is_performing_action:
		return
	if interaction_phase == Phase.DRAGGING_MOVE:
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

	var new_idx = idx + delta
	if new_idx < 0:
		new_idx = units.size() - 1
	elif new_idx >= units.size():
		new_idx = 0

	var new_unit = units[new_idx]

	SignalBus.request_clear_highlight.emit()
	current_highlight_cells = {}
	current_move_attack_targets = {}
	interaction_phase = Phase.IDLE
	current_empty_cell = Vector2i(-1, -1)

	selected_unit = new_unit
	SignalBus.request_show_info.emit(new_unit)
	SoundManager.play_select_sound()

	var camera = get_node_or_null("/root/Battlefield/Camera2D")
	if camera and camera.has_method("smooth_move_to"):
		camera.smooth_move_to(new_unit.global_position, 0.2, true)
	elif camera and camera.has_method("force_position"):
		camera.force_position(new_unit.global_position)


func handle_input(event: InputEvent, _map_grid_size: Vector2i, _cell_size: int):
	if TurnManager.is_game_over or TurnManager.is_moving:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click()
		return
