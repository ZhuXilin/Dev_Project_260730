class_name CursorController
extends Node

var _bf : Node2D
var _viewport_scale : float = 1.0
var _attack_indicator : TextureRect = null
var _hovered_unit : Unit = null


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

	_attack_indicator = TextureRect.new()
	if _bf.cursor and _bf.cursor.texture:
		_attack_indicator.texture = _bf.cursor.texture
	_attack_indicator.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	_attack_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_indicator.z_index = UIConst.ATTACK_INDICATOR_Z_INDEX
	_attack_indicator.visible = false
	_bf.add_child(_attack_indicator)


func get_viewport_scale() -> float:
	var canvas_transform = get_viewport().get_canvas_transform()
	return canvas_transform.get_scale().x


func get_attack_indicator() -> TextureRect:
	return _attack_indicator


func cleanup() -> void:
	if _attack_indicator and is_instance_valid(_attack_indicator):
		_attack_indicator.queue_free()
		_attack_indicator = null


func show_attack_indicator(unit) -> void:
	if not is_instance_valid(unit) or not _attack_indicator:
		return
	clear_attack_indicator()
	var target_size = MapConst.CELL_SIZE * _viewport_scale
	_attack_indicator.size = Vector2(target_size, target_size)
	var world_pos = _bf.grid_to_world(unit.grid_cell)
	_attack_indicator.position = world_pos - _attack_indicator.size / 2
	_attack_indicator.visible = true


func clear_attack_indicator() -> void:
	if _attack_indicator:
		_attack_indicator.visible = false


# ============================================================
#  主更新
# ============================================================
func update_cursor_and_mouse() -> void:
	if _bf._is_reward_ui_active:
		_set_hovered_unit(null)
		_bf.cursor.visible = false
		_use_system_mouse()
		return

	# 强制隐藏
	var force_hide_cursor = (
		Globals.is_dialogue_active or
		Globals.is_performing_action or
		Globals.is_item_get_popup_active or
		_bf.victory_panel.visible or
		TurnManager.current_turn_team == TurnManager.Team.ENEMY or
		TurnManager.is_ai_moving or
		TurnManager.is_moving or
		Globals.is_fading or
		Globals.is_transitioning or
		_bf.camera_controller._is_smooth_moving
	)
	if force_hide_cursor:
		_set_hovered_unit(null)
		_bf.cursor.visible = false
		_use_system_mouse()
		return

	# 面板打开
	var panel_open = (
		_bf.setting_panel.visible or
		_bf.team_view_panel.visible or
		_bf.item_list_panel.visible or
		_bf.setting_menu_panel.visible
	)
	if panel_open:
		_set_hovered_unit(null)
		_bf.cursor.visible = false
		_use_system_mouse()
		return

	# 遗物悬停
	if _bf.relic_icon_container and is_instance_valid(_bf.relic_icon_container):
		var relic_rect = _bf.relic_icon_container.get_global_rect().grow(4.0)
		var vp_mouse = get_viewport().get_mouse_position()
		if relic_rect.has_point(vp_mouse):
			_set_hovered_unit(null)
			_bf.cursor.visible = false
			_use_system_mouse()
			return

	# ★ 拖拽中且鼠标超范围 → 系统鼠标
	var drag_ctrl = _bf._drag_move_controller
	if drag_ctrl and drag_ctrl.is_dragging():
		# 双条件：移动范围外 OR 视口外
		var vp_size = get_viewport().get_visible_rect().size
		var mouse_screen = get_viewport().get_mouse_position()
		var mouse_outside_vp = (mouse_screen.x < 0 or mouse_screen.x > vp_size.x
				or mouse_screen.y < 0 or mouse_screen.y > vp_size.y)
		if drag_ctrl.is_mouse_out_of_range() or mouse_outside_vp:
			_set_hovered_unit(null)
			_bf.cursor.visible = false
			_use_system_mouse()
			return

	# ---- 计算光标世界坐标 ----
	var cursor_world_pos : Vector2
	if drag_ctrl and drag_ctrl.is_dragging():
		# 拖拽中 → 鼠标格
		var world_mouse = _bf.get_global_mouse_position()
		var grid_pos = _bf.world_to_grid(world_mouse)
		grid_pos.x = clamp(grid_pos.x, 0, _bf.map_grid_size.x - 1)
		grid_pos.y = clamp(grid_pos.y, 0, _bf.map_grid_size.y - 1)
		cursor_world_pos = _bf.grid_to_world(grid_pos)
	elif InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit):
		# ★ 有选中单位 → 跳到选中单位格（光标锁住）
		cursor_world_pos = _bf.grid_to_world(InputManager.selected_unit.grid_cell)
	else:
		# 无选中 → 鼠标格
		var world_mouse = _bf.get_global_mouse_position()
		var grid_pos = _bf.world_to_grid(world_mouse)
		grid_pos.x = clamp(grid_pos.x, 0, _bf.map_grid_size.x - 1)
		grid_pos.y = clamp(grid_pos.y, 0, _bf.map_grid_size.y - 1)
		cursor_world_pos = _bf.grid_to_world(grid_pos)

	var canvas_transform = get_viewport().get_canvas_transform()
	var screen_pos = canvas_transform * cursor_world_pos
	var size = _bf.cursor.size
	_bf.cursor.position = (screen_pos - size / 2).floor()
	_bf.cursor.visible = true

	_use_hidden_mouse()

	# 缩放同步
	var new_scale = get_viewport_scale()
	if new_scale != _viewport_scale:
		_viewport_scale = new_scale
		var target_size = round(MapConst.CELL_SIZE * _viewport_scale)
		_bf.cursor.size = Vector2(target_size, target_size)
		if _attack_indicator:
			_attack_indicator.size = Vector2(target_size, target_size)

	# 悬停单位 HP
	_update_hovered_unit_from_mouse()

	# 颜色：有选中我方 → pink
	var should_be_pink = false
	if InputManager.selected_unit != null \
			and is_instance_valid(InputManager.selected_unit) \
			and InputManager.selected_unit.unit_stats.team_id == 0:
		should_be_pink = true
	var target_color = Color.FUCHSIA if should_be_pink else Color.WHITE
	if _bf.cursor.modulate != target_color:
		_bf.cursor.modulate = target_color


func _use_system_mouse():
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_set_mouse_mode_deferred.call_deferred(Input.MOUSE_MODE_VISIBLE)


func _use_hidden_mouse():
	if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		_set_mouse_mode_deferred.call_deferred(Input.MOUSE_MODE_HIDDEN)


func _set_mouse_mode_deferred(mode: Input.MouseMode) -> void:
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


func _update_hovered_unit_from_mouse() -> void:
	if TurnManager.is_game_over:
		_set_hovered_unit(null)
		return
	var world_mouse = _bf.get_global_mouse_position()
	var grid_pos = _bf.world_to_grid(world_mouse)
	if grid_pos.x < 0 or grid_pos.x >= _bf.map_grid_size.x \
			or grid_pos.y < 0 or grid_pos.y >= _bf.map_grid_size.y:
		_set_hovered_unit(null)
		return
	var new_unit = UnitManager.get_unit_at_cell(grid_pos)
	_set_hovered_unit(new_unit)


func _set_hovered_unit(new_unit: Unit) -> void:
	if new_unit == _hovered_unit:
		return
	if _hovered_unit and is_instance_valid(_hovered_unit):
		_hovered_unit.show_hp_label(false)
	if new_unit and is_instance_valid(new_unit) and new_unit.hit_points > 0:
		new_unit.show_hp_label(true)
	_hovered_unit = new_unit
