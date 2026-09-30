class_name CursorController
extends Node

var _bf : Node2D
var _viewport_scale : float = 1.0
var _attack_indicator : TextureRect = null


func _init(bf: Node2D):
	_bf = bf


func init_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
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

	# 攻击指示器
	_attack_indicator = TextureRect.new()
	if _bf.cursor and _bf.cursor.texture:
		_attack_indicator.texture = _bf.cursor.texture
	else:
		print("警告：cursor.texture 无效，使用默认纹理")
	_attack_indicator.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	_attack_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_indicator.z_index = UIConst.ATTACK_INDICATOR_Z_INDEX
	_attack_indicator.visible = false
	_bf.add_child(_attack_indicator)


func get_viewport_scale() -> float:
	var viewport = get_viewport()
	var canvas_transform = viewport.get_canvas_transform()
	var scale_value = canvas_transform.get_scale()
	return scale_value.x


func get_attack_indicator() -> TextureRect:
	return _attack_indicator


func cleanup() -> void:
	if _attack_indicator and is_instance_valid(_attack_indicator):
		_attack_indicator.queue_free()
		_attack_indicator = null


# ---- 信号回调：SignalBus.request_highlight_unit ----
func show_attack_indicator(unit) -> void:
	if not is_instance_valid(unit) or not _attack_indicator:
		return
	clear_attack_indicator()
	var target_size = MapConst.CELL_SIZE * _viewport_scale
	_attack_indicator.size = Vector2(target_size, target_size)
	var world_pos = _bf.grid_to_world(unit.grid_cell)
	_attack_indicator.position = world_pos - _attack_indicator.size / 2
	_attack_indicator.visible = true


# ---- 信号回调：SignalBus.request_clear_highlight_unit ----
func clear_attack_indicator() -> void:
	if _attack_indicator:
		_attack_indicator.visible = false


func update_cursor_and_mouse() -> void:
	if _bf._is_reward_ui_active:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_bf.cursor.visible = false
		return

	var force_hide_cursor = (
		Globals.is_dialogue_active or
		Globals.is_performing_action or
		Globals.is_item_get_popup_active or
		Globals.is_equip_menu_active or
		_bf.victory_panel.visible or
		_bf.setting_panel.visible or
		_bf.team_view_panel.visible or
		_bf.item_list_panel.visible or
		_bf.setting_menu_panel.visible or
		TurnManager.current_turn_team == TurnManager.Team.ENEMY or
		TurnManager.is_ai_moving or
		TurnManager.is_moving or
		Globals.is_fading or
		Globals.is_transitioning or
		_bf.camera_controller._is_smooth_moving
	)

	if force_hide_cursor:
		_bf.cursor.visible = false
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	# ---- 鼠标进入遗物/精炼面板：切回系统鼠标，让 Button 可点 ----
	if _bf.relic_icon_container and is_instance_valid(_bf.relic_icon_container):
		var relic_rect = _bf.relic_icon_container.get_global_rect().grow(4.0)
		var vp_mouse = get_viewport().get_mouse_position()
		if relic_rect.has_point(vp_mouse):
			_bf.cursor.visible = false
			if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

	var show_cursor = false
	var cursor_world_pos = Vector2.ZERO
	var show_system_mouse = false

	if (_bf.action_menu.visible or _bf.info_panel.visible) and InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit):
		show_cursor = true
		cursor_world_pos = _bf.grid_to_world(InputManager.selected_unit.grid_cell)
		show_system_mouse = true
	else:
		if _bf.info_panel.visible:
			var unit = InputManager.selected_unit
			if unit != null and is_instance_valid(unit):
				show_cursor = true
				cursor_world_pos = _bf.grid_to_world(unit.grid_cell)
			else:
				var empty_cell = InputManager.current_empty_cell
				if empty_cell != Vector2i(-1, -1):
					show_cursor = true
					cursor_world_pos = _bf.grid_to_world(empty_cell)
				else:
					show_cursor = true
					var world_mouse = _bf.get_global_mouse_position()
					var grid_pos = _bf.world_to_grid(world_mouse)
					cursor_world_pos = _bf.grid_to_world(grid_pos)
		else:
			if not force_hide_cursor:
				show_cursor = true
				var world_mouse = _bf.get_global_mouse_position()
				var grid_pos = _bf.world_to_grid(world_mouse)
				cursor_world_pos = _bf.grid_to_world(grid_pos)

		show_system_mouse = not show_cursor

	if show_cursor:
		if not (_bf.action_menu.visible or _bf.info_panel.visible):
			var world_mouse = _bf.get_global_mouse_position()
			var grid_pos = _bf.world_to_grid(world_mouse)
			grid_pos.x = clamp(grid_pos.x, 0, _bf.map_grid_size.x - 1)
			grid_pos.y = clamp(grid_pos.y, 0, _bf.map_grid_size.y - 1)
			cursor_world_pos = _bf.grid_to_world(grid_pos)

		var canvas_transform = get_viewport().get_canvas_transform()
		var screen_pos = canvas_transform * cursor_world_pos
		screen_pos = screen_pos.round()
		var size = _bf.cursor.size.round()
		_bf.cursor.position = screen_pos - size / 2
		_bf.cursor.visible = true
	else:
		_bf.cursor.visible = false

	if show_system_mouse:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			_set_mouse_mode_deferred.call_deferred(Input.MOUSE_MODE_VISIBLE)
	else:
		if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
			_set_mouse_mode_deferred.call_deferred(Input.MOUSE_MODE_HIDDEN)
			

	if _bf.cursor.visible:
		var new_scale = get_viewport_scale()
		if new_scale != _viewport_scale:
			_viewport_scale = new_scale
			var target_size = round(MapConst.CELL_SIZE * _viewport_scale)
			_bf.cursor.size = Vector2(target_size, target_size)
			if _attack_indicator:
				_attack_indicator.size = Vector2(target_size, target_size)

	var should_be_pink = false
	if Globals.is_equip_menu_active:
		should_be_pink = true
	elif _bf.action_menu.visible or _bf.info_panel.visible:
		should_be_pink = true
	elif InputManager.selected_unit != null and InputManager.selected_unit.unit_stats.team_id == 0:
		var phase = InputManager.interaction_phase
		if phase in [InputManager.Phase.MENU, InputManager.Phase.MOVING, InputManager.Phase.ATTACKING]:
			should_be_pink = true

	var target_color = Color.FUCHSIA if should_be_pink else Color.WHITE
	if _bf.cursor.modulate != target_color:
		_bf.cursor.modulate = target_color


func _set_mouse_mode_deferred(mode: Input.MouseMode) -> void:
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode
