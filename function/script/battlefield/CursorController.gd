class_name CursorController
extends Node

var _bf : Node2D
var _viewport_scale : float = 1.0
var _attack_indicator : TextureRect = null
var _hovered_unit : Unit = null

func _init(bf: Node2D):
	_bf = bf

func init_cursor() -> void:
	# 1. 强制使用系统鼠标
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# 2. 显示像素格子指示框
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

	# 3. 攻击指示器
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
	# 确保系统鼠标始终可见
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# 判断是否需要隐藏“像素格子框”和“面板”
	var force_hide = false

	if Globals.is_confirm_ui_active or Globals.is_reward_summary_active or _bf._is_reward_ui_active:
		force_hide = true
	elif Globals.is_dialogue_active or Globals.is_performing_action or Globals.is_item_get_popup_active or _bf.victory_panel.visible or TurnManager.current_turn_team == TurnManager.Team.ENEMY or TurnManager.is_ai_moving or TurnManager.is_moving or Globals.is_fading or Globals.is_transitioning:
		force_hide = true
	elif _bf.setting_panel.visible or _bf.team_view_panel.visible or _bf.setting_menu_panel.visible:
		force_hide = true

	# 遗物悬停
	if not force_hide and _bf.relic_icon_container and is_instance_valid(_bf.relic_icon_container):
		var relic_rect = _bf.relic_icon_container.get_global_rect().grow(4.0)
		var vp_mouse = get_viewport().get_mouse_position()
		if relic_rect.has_point(vp_mouse):
			force_hide = true

	# 拖拽中且鼠标超范围
	var drag_ctrl = _bf._drag_move_controller
	if not force_hide and drag_ctrl and drag_ctrl.is_dragging():
		var vp_size = get_viewport().get_visible_rect().size
		var mouse_screen = get_viewport().get_mouse_position()
		if drag_ctrl.is_mouse_out_of_range() or mouse_screen.x < 0 or mouse_screen.x > vp_size.x or mouse_screen.y < 0 or mouse_screen.y > vp_size.y:
			force_hide = true

	if force_hide:
		_set_hovered_unit(null)
		_bf.cursor.visible = false
		# 强制隐藏面板，确保走 PanelRevealer 扫出动画
		SignalBus.request_hide_info.emit()
		return

	# ---- 计算像素框所在的世界坐标 ----
	var cursor_world_pos : Vector2
	var world_mouse = _bf.get_global_mouse_position()
	var grid_pos = _bf.world_to_grid(world_mouse)
	grid_pos.x = clamp(grid_pos.x, 0, _bf.map_grid_size.x - 1)
	grid_pos.y = clamp(grid_pos.y, 0, _bf.map_grid_size.y - 1)

	if drag_ctrl and drag_ctrl.is_dragging():
		cursor_world_pos = _bf.grid_to_world(grid_pos)
	elif InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit):
		# 有选中单位时，像素框锁定在单位脚下
		cursor_world_pos = _bf.grid_to_world(InputManager.selected_unit.grid_cell)
	else:
		cursor_world_pos = _bf.grid_to_world(grid_pos)

	# ---- 更新像素框位置（吸附网格跳跃） ----
	_bf.cursor.visible = true
	var canvas_transform = get_viewport().get_canvas_transform()
	var screen_pos = canvas_transform * cursor_world_pos
	var size = _bf.cursor.size
	_bf.cursor.position = (screen_pos - size / 2).floor()

	# 缩放同步
	var new_scale = get_viewport_scale()
	if new_scale != _viewport_scale:
		_viewport_scale = new_scale
		var target_size = round(MapConst.CELL_SIZE * _viewport_scale)
		_bf.cursor.size = Vector2(target_size, target_size)
		if _attack_indicator: _attack_indicator.size = Vector2(target_size, target_size)

	# 悬停单位 HP 和 面板
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


func _update_hovered_unit_from_mouse() -> void:
	if TurnManager.is_game_over:
		_set_hovered_unit(null)
		SignalBus.request_hide_info.emit()
		return
		
	var world_mouse = _bf.get_global_mouse_position()
	var grid_pos = _bf.world_to_grid(world_mouse)
	
	# 超出地图边界
	if grid_pos.x < 0 or grid_pos.x >= _bf.map_grid_size.x \
			or grid_pos.y < 0 or grid_pos.y >= _bf.map_grid_size.y:
		_set_hovered_unit(null)
		SignalBus.request_hide_info.emit()
		return
		
	var new_unit = UnitManager.get_unit_at_cell(grid_pos)
	if not is_instance_valid(new_unit):
		new_unit = null

	# ★ 关键修复：这里绝对不能写 var suppressed : Unit，否则强类型接收废弃实例直接崩溃
	var suppressed = _bf.get_suppressed_range_unit()
	if not is_instance_valid(suppressed):
		suppressed = null
		
	if suppressed != null and new_unit != suppressed:
		_bf.clear_suppressed_range()
	
	if not is_instance_valid(_hovered_unit):
		_hovered_unit = null
		
	# 更新 HP 标签显隐
	if _hovered_unit != new_unit:
		if is_instance_valid(_hovered_unit):
			_hovered_unit.show_hp_label(false)
		if is_instance_valid(new_unit) and new_unit.hit_points > 0:
			new_unit.show_hp_label(true)
		_hovered_unit = new_unit
		
	# 持续发送面板显示请求（拖拽时除外）
	if not (_bf._drag_move_controller and _bf._drag_move_controller.is_dragging()):
		if is_instance_valid(new_unit) and new_unit.hit_points > 0:
			SignalBus.request_show_info.emit(new_unit)
		else:
			SignalBus.request_hide_info.emit() # 这里的 null 改为直接发 hide


func _set_hovered_unit(new_unit: Unit) -> void:
	# ★ 核心修复：两边都先净化，再比较
	if not is_instance_valid(new_unit):
		new_unit = null
	if not is_instance_valid(_hovered_unit):
		_hovered_unit = null

	if new_unit == _hovered_unit:
		return
		
	if is_instance_valid(_hovered_unit):
		_hovered_unit.show_hp_label(false)
	if is_instance_valid(new_unit) and new_unit.hit_points > 0:
		new_unit.show_hp_label(true)
	_hovered_unit = new_unit
