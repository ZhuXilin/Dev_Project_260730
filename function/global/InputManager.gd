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

# 滚轮循环基准
var _last_wheel_unit : Unit = null
var _last_wheel_time_ms : int = 0
const WHEEL_CHAIN_WINDOW_MS : int = 1000


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
		return

	if interaction_phase == Phase.SETTING:
		current_empty_cell = clicked_cell
		return

	if selected_unit != null:
		selected_unit = null
		interaction_phase = Phase.IDLE

	SignalBus.request_show_setting.emit()
	SoundManager.play_select_sound()
	interaction_phase = Phase.SETTING
	SignalBus.request_clear_highlight.emit()
	current_empty_cell = clicked_cell


func _handle_right_click():
	if not TurnManager.is_battle_ready():
		return

	if interaction_phase == Phase.SETTING:
		SignalBus.request_setting_right_click.emit()
		return

	if selected_unit != null and is_instance_valid(selected_unit):
		SoundManager.play_cancel_sound()
		SignalBus.request_hint_override.emit("已取消选中", 1.0)
		SignalBus.request_clear_highlight.emit()
		SignalBus.request_clear_highlight_unit.emit()
		SignalBus.request_hide_info.emit()
		selected_unit = null
		interaction_phase = Phase.IDLE
		return

	var m : Unit = TurnManager.last_moved_unit
	if m != null and is_instance_valid(m) and m.has_moved and not m.has_attacked:
		SoundManager.play_cancel_sound()
		TurnManager.cancel_movement(m)
		m.moves_since_act -= 1
		SignalBus.request_hint_override.emit("已撤销操作", 1.0)
		SignalBus.request_clear_highlight.emit()
		SignalBus.request_clear_highlight_unit.emit()
		SignalBus.request_hide_info.emit()
		selected_unit = null
		interaction_phase = Phase.IDLE
		return

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

	var bf = get_node_or_null("/root/Battlefield")

	var now_ms := Time.get_ticks_msec()
	var elapsed := now_ms - _last_wheel_time_ms
	_last_wheel_time_ms = now_ms

	var base_idx : int = -1

	var use_last_as_base : bool = (
		elapsed < WHEEL_CHAIN_WINDOW_MS
		and _last_wheel_unit != null
		and is_instance_valid(_last_wheel_unit)
		and _last_wheel_unit in units
	)

	if use_last_as_base:
		base_idx = units.find(_last_wheel_unit)
	else:
		var hover_unit : Unit = null
		if bf and bf.has_method("world_to_grid"):
			var cell = bf.world_to_grid(bf.get_global_mouse_position())
			hover_unit = UnitManager.get_unit_at_cell(cell)
		if hover_unit != null and hover_unit in units:
			base_idx = units.find(hover_unit)
		elif _last_wheel_unit != null and is_instance_valid(_last_wheel_unit) and _last_wheel_unit in units:
			base_idx = units.find(_last_wheel_unit)

	var new_idx = base_idx + delta
	if new_idx < 0:
		new_idx = units.size() - 1
	elif new_idx >= units.size():
		new_idx = 0

	var new_unit = units[new_idx]
	_last_wheel_unit = new_unit

	# 清理旧状态，改由悬停（CursorController）驱动面板
	selected_unit = null
	interaction_phase = Phase.IDLE
	current_highlight_cells = {}
	current_move_attack_targets = {}
	current_empty_cell = Vector2i(-1, -1)
	SignalBus.request_clear_highlight.emit()
	
	# 播放点击音效
	SoundManager.play_select_sound()

	# 相机移动
	if bf:
		var camera = bf.get_node_or_null("Camera2D")
		if camera:
			if camera.has_method("smooth_move_to"):
				camera.smooth_move_to(new_unit.global_position, 0.2, true)
			elif camera.has_method("force_position"):
				camera.force_position(new_unit.global_position)

	# 延迟 warp 鼠标到单位中心
	_delayed_warp_mouse_to_unit(new_unit)


## 延迟把物理鼠标移动到单位的**格子中心**
func _delayed_warp_mouse_to_unit(target_unit: Unit):
	if target_unit == null or not is_instance_valid(target_unit):
		return
	# CameraController.smooth_move_to 时长 0.2s，多留一帧余量
	await get_tree().create_timer(0.22, true, false, true).timeout
	if not is_instance_valid(self):
		return
	if not is_instance_valid(target_unit):
		return
	
	# ★ 修复：直接使用 global_position，这就是格子中心
	# 之前加了 Vector2(0, -8) 导致鼠标飘到格子上方，触发了地形面板而不是单位面板
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * target_unit.global_position
	get_viewport().warp_mouse(screen_pos)


func handle_input(event: InputEvent, _map_grid_size: Vector2i, _cell_size: int):
	if TurnManager.is_game_over or TurnManager.is_moving:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click()
		return
