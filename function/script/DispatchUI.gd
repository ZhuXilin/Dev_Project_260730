class_name DispatchUI
extends CanvasLayer

signal closed

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/Title
@onready var hint_label : Label = $Panel/VBox/Hint
@onready var unit_row : HBoxContainer = $Panel/VBox/UnitScroll/UnitRow
@onready var route_row : HBoxContainer = $Panel/VBox/RouteScroll/RouteRow
@onready var active_list : VBoxContainer = $Panel/VBox/ActiveScroll/ActiveList
@onready var dispatch_btn : Button = $Panel/VBox/BottomBar/DispatchBtn
@onready var back_btn : Button = $Panel/VBox/BottomBar/BackBtn

var _selected_units : Array = []
var _selected_route : String = ""

const COLOR_UNIT_ON : Color = Color(0.4, 0.9, 0.5, 1)
const COLOR_UNIT_OFF : Color = Color(0.85, 0.85, 0.85, 1)
const COLOR_UNIT_DISABLED : Color = Color(0.45, 0.45, 0.45, 1)


func _ready():
	layer = 24
	if back_btn and not back_btn.pressed.is_connected(_on_back_pressed):
		back_btn.pressed.connect(_on_back_pressed)
	if dispatch_btn and not dispatch_btn.pressed.is_connected(_do_dispatch):
		dispatch_btn.pressed.connect(_do_dispatch)
	_refresh()


func _refresh():
	_refresh_units()
	_refresh_routes()
	_refresh_active()
	_refresh_dispatch_btn()
	_refresh_hint()


func _refresh_hint():
	if not hint_label: return
	var n : int = _selected_units.size()
	var route_name : String = ""
	if _selected_route != "" and DispatchManager.ROUTES.has(_selected_route):
		route_name = DispatchManager.ROUTES[_selected_route].get("name", _selected_route)
	if n == 0:
		hint_label.text = "① 选择 1-2 个单位   ② 选择 1 条路线   ③ 点派遣"
	elif _selected_route == "":
		hint_label.text = "已选 %d 人，请选择路线" % n
	else:
		hint_label.text = "已选 %d 人 → %s，点【派遣】确认" % [n, route_name]


# ============================================================
#  单位选择
# ============================================================
func _refresh_units():
	for c in unit_row.get_children():
		unit_row.remove_child(c); c.queue_free()

	# ★ 动态加大滚动区高度，避免按钮被压扁
	var unit_scroll : ScrollContainer = $Panel/VBox/UnitScroll
	if unit_scroll:
		unit_scroll.custom_minimum_size = Vector2(0, 56)

	var dispatched : Array = DispatchManager.get_dispatched_unit_names()

	if GameState.party.is_empty():
		var lb = Label.new()
		lb.text = "（暂无队伍，请先在营地大门组队）"
		lb.add_theme_font_size_override("font_size", 7)
		lb.modulate = Color(0.6, 0.6, 0.6)
		unit_row.add_child(lb)
		return

	for u in GameState.party:
		var btn := Button.new()
		var display_name : String = u.display_name if u.display_name != "" else u.unit_name
		var is_dispatched : bool = u.unit_name in dispatched
		var is_selected : bool = u.unit_name in _selected_units

		btn.text = display_name
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(90, 32)
		btn.add_theme_font_size_override("font_size", 7)
		btn.focus_mode = Control.FOCUS_NONE

		if is_dispatched:
			btn.disabled = true
			btn.text = display_name + "\n(派遣中)"
			btn.modulate = COLOR_UNIT_DISABLED
		else:
			btn.button_pressed = is_selected
			btn.modulate = COLOR_UNIT_ON if is_selected else COLOR_UNIT_OFF
			btn.toggled.connect(_on_unit_toggled.bind(u.unit_name, btn))
			# ★ 双击直接派遣（可选，提升手感）
			btn.pressed.connect(func(): _update_unit_visual(btn, u.unit_name))

		unit_row.add_child(btn)


## 选中状态视觉刷新
func _update_unit_visual(btn : Button, unit_name : String):
	if unit_name in _selected_units:
		btn.modulate = COLOR_UNIT_ON
	else:
		btn.modulate = COLOR_UNIT_OFF


func _refresh_routes():
	for c in route_row.get_children():
		route_row.remove_child(c); c.queue_free()
	var unlocked = DispatchManager.get_unlocked_routes()
	if unlocked.is_empty():
		var lb = Label.new()
		lb.text = "（无可用路线）"
		lb.add_theme_font_size_override("font_size", 7)
		lb.modulate = Color(0.6, 0.6, 0.6)
		route_row.add_child(lb)
		return
	for rid in unlocked:
		var route = DispatchManager.ROUTES[rid]
		var btn = Button.new()
		btn.text = "%s [%s]" % [route["name"], "/".join(route["tags"])]
		btn.toggle_mode = true
		btn.button_pressed = (rid == _selected_route)
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 7)
		btn.modulate = Color(0.4, 0.9, 0.5, 1) if rid == _selected_route else Color.WHITE
		btn.pressed.connect(func():
			_selected_route = rid
			_refresh_routes()
			_refresh_dispatch_btn()
			_refresh_hint()
		)
		route_row.add_child(btn)


func _refresh_active():
	for c in active_list.get_children():
		active_list.remove_child(c); c.queue_free()
	if DispatchManager.active_dispatches.is_empty():
		var lb = Label.new()
		lb.text = "（无进行中的派遣）"
		lb.add_theme_font_size_override("font_size", 6)
		lb.modulate = Color(0.6, 0.6, 0.6)
		active_list.add_child(lb)
	else:
		for d in DispatchManager.active_dispatches:
			var lb := Label.new()
			var route : Dictionary = DispatchManager.ROUTES.get(d.route_id, {})
			var match_mark : String = ""
			var unit_tags : Array = _get_unit_tags(d.unit_name)
			var route_tags : Array = route.get("tags", [])
			for t in unit_tags:
				if t in route_tags:
					match_mark = "  ★ 标签匹配"
					break
			lb.text = "%s → %s（剩 %d 局）%s" % [
				d.unit_name, route.get("name", d.route_id), d.remaining_runs, match_mark
			]
			lb.add_theme_font_size_override("font_size", 7)
			if match_mark != "":
				lb.modulate = Color(1.0, 0.85, 0.3)
			active_list.add_child(lb)


func _get_unit_tags(unit_name: String) -> Array:
	for u in GameState.party:
		if u.unit_name == unit_name:
			return u.tags
	return []


func _refresh_dispatch_btn():
	if not dispatch_btn: return
	var has_team : bool = not GameState.party.is_empty()
	var ok : bool = has_team and (not _selected_units.is_empty()) and _selected_route != ""
	dispatch_btn.disabled = not ok
	if not has_team:
		dispatch_btn.text = "派遣（无队伍）"
	else:
		dispatch_btn.text = "派遣 (%d/2)" % _selected_units.size()


func _on_unit_toggled(pressed: bool, unit_name: String, btn : Button):
	if pressed:
		if _selected_units.size() >= 2:
			# 超额 → 立即回弹
			btn.set_pressed_no_signal(false)
			SoundManager.play_invalid_sound()
			return
		_selected_units.append(unit_name)
	else:
		_selected_units.erase(unit_name)
	_update_unit_visual(btn, unit_name)
	_refresh_dispatch_btn()
	_refresh_hint()
	SoundManager.play_select_sound()


func _do_dispatch():
	if _selected_units.is_empty() or _selected_route == "": return
	if DispatchManager.dispatch(_selected_units, _selected_route):
		_selected_units.clear()
		_selected_route = ""
		_refresh()
		SoundManager.play_select_sound()


func _on_back_pressed():
	closed.emit()
	queue_free()
