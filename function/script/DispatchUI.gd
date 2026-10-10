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
	if hint_label:
		hint_label.text = "选 1-2 个单位 + 1 条路线后确认派遣"


func _refresh_units():
	for c in unit_row.get_children():
		unit_row.remove_child(c); c.queue_free()
	var dispatched = DispatchManager.get_dispatched_unit_names()
	if GameState.party.is_empty():
		var lb = Label.new()
		lb.text = "（暂无队伍）"
		lb.add_theme_font_size_override("font_size", 7)
		lb.modulate = Color(0.6, 0.6, 0.6)
		unit_row.add_child(lb)
		return
	for u in GameState.party:
		var btn = Button.new()
		btn.text = u.display_name
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(80, 24)
		btn.add_theme_font_size_override("font_size", 7)
		if u.unit_name in dispatched:
			btn.disabled = true
			btn.text += "（派遣中）"
		else:
			btn.button_pressed = u.unit_name in _selected_units
			btn.toggled.connect(_on_unit_toggled.bind(u.unit_name))
		unit_row.add_child(btn)


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
		btn.add_theme_font_size_override("font_size", 7)
		btn.pressed.connect(func(): _selected_route = rid; _refresh_routes(); _refresh_dispatch_btn())
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
			var lb = Label.new()
			var route : Dictionary = DispatchManager.ROUTES.get(d.route_id, {})
			lb.text = "%s → %s（剩 %d 局）" % [
				d.unit_name, route.get("name", d.route_id), d.remaining_runs
			]
			lb.add_theme_font_size_override("font_size", 7)
			active_list.add_child(lb)


func _refresh_dispatch_btn():
	if not dispatch_btn: return
	var ok : bool = (not _selected_units.is_empty()) and _selected_route != ""
	dispatch_btn.disabled = not ok


func _on_unit_toggled(pressed: bool, unit_name: String):
	if pressed:
		if _selected_units.size() >= 2:
			return
		_selected_units.append(unit_name)
	else:
		_selected_units.erase(unit_name)
	_refresh_dispatch_btn()


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
