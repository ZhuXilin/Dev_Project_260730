class_name CursorController
extends Node

var _bf : Node2D
var _viewport_scale : float = 1.0
var _attack_indicator : TextureRect = null
var _hovered_unit : Unit = null

var is_locked : bool = false

func _init(bf: Node2D):
	_bf = bf

func init_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_bf.cursor.visible = true
	if _bf.cursor.texture == null:
		var path = Config.PATHS.CURSOR_TEXTURE
		if ResourceLoader.exists(path):
			_bf.cursor.texture = load(path)
		else:
			push_error("光标图片不存在：", path)
			
	_viewport_scale = get_viewport_scale()
	var target_size = round(MapConst.CELL_SIZE * _viewport_scale)
	_bf.cursor.size = Vector2(target_size, target_size)
	_bf.cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bf.cursor.z_index = 0 

	_attack_indicator = TextureRect.new()
	if _bf.cursor and _bf.cursor.texture:
		_attack_indicator.texture = _bf.cursor.texture
	_attack_indicator.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	_attack_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_indicator.z_index = UIConst.ATTACK_INDICATOR_Z_INDEX
	_attack_indicator.visible = false
	_bf.add_child(_attack_indicator)

func get_viewport_scale() -> float:
	return get_viewport().get_canvas_transform().get_scale().x

func cleanup() -> void:
	if _attack_indicator and is_instance_valid(_attack_indicator):
		_attack_indicator.queue_free()
		_attack_indicator = null

func show_attack_indicator(unit) -> void:
	if not is_instance_valid(unit) or not _attack_indicator: return
	clear_attack_indicator()
	var target_size = MapConst.CELL_SIZE * _viewport_scale
	_attack_indicator.size = Vector2(target_size, target_size)
	var world_pos = _bf.grid_to_world(unit.grid_cell)
	_attack_indicator.position = world_pos - _attack_indicator.size / 2
	_attack_indicator.visible = true

func clear_attack_indicator() -> void:
	if _attack_indicator:
		_attack_indicator.visible = false

func set_locked(locked: bool) -> void:
	is_locked = locked
	if is_locked:
		_bf.cursor.visible = false
		_set_hovered_unit(null)
		SignalBus.request_hide_info.emit()

func update_cursor_and_mouse() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# ★ 最高优先级拦截：如果正在过场、淡入淡出、或者有对话，直接隐藏光标并拦截一切交互
	if Globals.is_transitioning or Globals.is_fading or Globals.is_dialogue_active:
		_bf.cursor.visible = false
		_set_hovered_unit(null)
		return

	if is_locked:
		_bf.cursor.visible = false
		_set_hovered_unit(null)
		SignalBus.request_hide_info.emit()
		return

	var force_hide = false

	if Globals.is_attack_menu_active: # ★ 新增：拦截悬停
		force_hide = true
	elif Globals.is_confirm_ui_active or Globals.is_reward_summary_active or _bf._is_reward_ui_active:
		force_hide = true
	elif Globals.is_dialogue_active or Globals.is_performing_action or Globals.is_item_get_popup_active or _bf.victory_panel.visible or TurnManager.current_turn_team == TurnManager.Team.ENEMY or TurnManager.is_ai_moving or TurnManager.is_moving or Globals.is_fading or Globals.is_transitioning or is_locked:
		force_hide = true
	elif _bf.setting_panel.visible or _bf.team_view_panel.visible or _bf.setting_menu_panel.visible:
		force_hide = true
	elif InputManager.is_wheel_cooldown():
		force_hide = true

	if not force_hide and _bf.relic_icon_container and is_instance_valid(_bf.relic_icon_container):
		var relic_rect = _bf.relic_icon_container.get_global_rect().grow(4.0)
		if relic_rect.has_point(get_viewport().get_mouse_position()):
			force_hide = true

	var drag_ctrl = _bf._drag_move_controller
	if not force_hide and drag_ctrl and drag_ctrl.is_dragging():
		var vp_size = get_viewport().get_visible_rect().size
		var mouse_screen = get_viewport().get_mouse_position()
		if drag_ctrl.is_mouse_out_of_range() or mouse_screen.x < 0 or mouse_screen.x > vp_size.x or mouse_screen.y < 0 or mouse_screen.y > vp_size.y:
			force_hide = true

	if force_hide:
		_set_hovered_unit(null)
		_bf.cursor.visible = false
		SignalBus.request_hide_info.emit()
		return

	var cursor_world_pos : Vector2
	var world_mouse = _bf.get_global_mouse_position()
	var grid_pos = _bf.world_to_grid(world_mouse)
	grid_pos.x = clamp(grid_pos.x, 0, _bf.map_grid_size.x - 1)
	grid_pos.y = clamp(grid_pos.y, 0, _bf.map_grid_size.y - 1)

	if drag_ctrl and drag_ctrl.is_dragging():
		cursor_world_pos = _bf.grid_to_world(grid_pos)
	elif InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit):
		cursor_world_pos = _bf.grid_to_world(InputManager.selected_unit.grid_cell)
	else:
		cursor_world_pos = _bf.grid_to_world(grid_pos)

	_bf.cursor.visible = true
	var screen_pos = get_viewport().get_canvas_transform() * cursor_world_pos
	_bf.cursor.position = (screen_pos - _bf.cursor.size / 2).floor()

	var new_scale = get_viewport_scale()
	if new_scale != _viewport_scale:
		_viewport_scale = new_scale
		var target_size = round(MapConst.CELL_SIZE * _viewport_scale)
		_bf.cursor.size = Vector2(target_size, target_size)
		if _attack_indicator: _attack_indicator.size = Vector2(target_size, target_size)

	_update_hovered_unit_from_mouse()

	var should_be_pink = false
	if InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit) and InputManager.selected_unit.unit_stats.team_id == 0:
		should_be_pink = true
	var target_color = Color.FUCHSIA if should_be_pink else Color.WHITE
	if _bf.cursor.modulate != target_color:
		_bf.cursor.modulate = target_color

func _update_hovered_unit_from_mouse() -> void:
	if TurnManager.is_game_over:
		_set_hovered_unit(null)
		SignalBus.request_hide_info.emit()
		return
		
	var world_mouse = _bf.get_global_mouse_position()
	var grid_pos = _bf.world_to_grid(world_mouse)
	
	if grid_pos.x < 0 or grid_pos.x >= _bf.map_grid_size.x or grid_pos.y < 0 or grid_pos.y >= _bf.map_grid_size.y:
		_set_hovered_unit(null)
		SignalBus.request_hide_info.emit()
		return
		
	var new_unit = UnitManager.get_unit_at_cell(grid_pos)
	if not is_instance_valid(new_unit): new_unit = null

	var suppressed = _bf.get_suppressed_range_unit()
	if not is_instance_valid(suppressed): suppressed = null
	if suppressed != null and new_unit != suppressed: _bf.clear_suppressed_range()
	if not is_instance_valid(_hovered_unit): _hovered_unit = null
		
	if _hovered_unit != new_unit:
		if is_instance_valid(_hovered_unit): _hovered_unit.show_hp_label(false)
		if is_instance_valid(new_unit) and new_unit.hit_points > 0: new_unit.show_hp_label(true)
		_hovered_unit = new_unit
		
	if is_instance_valid(new_unit) and new_unit.hit_points > 0:
		SignalBus.request_show_info.emit(new_unit)
	else:
		SignalBus.request_show_info.emit(null)

func _set_hovered_unit(new_unit: Unit) -> void:
	if not is_instance_valid(new_unit): new_unit = null
	if not is_instance_valid(_hovered_unit): _hovered_unit = null
	if new_unit == _hovered_unit: return
		
	if is_instance_valid(_hovered_unit): _hovered_unit.show_hp_label(false)
	if is_instance_valid(new_unit) and new_unit.hit_points > 0: new_unit.show_hp_label(true)
	_hovered_unit = new_unit
