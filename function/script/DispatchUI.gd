class_name DispatchUI
extends CanvasLayer

signal closed

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/Title
@onready var hint_label : Label = $Panel/VBox/Hint
@onready var unit_row : VBoxContainer = $Panel/VBox/MainHBox/LeftVBox/UnitScroll/UnitRow
@onready var route_row : VBoxContainer = $Panel/VBox/MainHBox/LeftVBox/RouteScroll/RouteRow
@onready var active_list : VBoxContainer = $Panel/VBox/ActiveScroll/ActiveList
@onready var dispatch_btn : Button = $Panel/VBox/BottomBar/DispatchBtn
@onready var back_btn : Button = $Panel/VBox/BottomBar/BackBtn

# 新增的信息栏节点
@onready var info_name : Label = $Panel/VBox/MainHBox/RightVBox/InfoPanel/InfoVBox/InfoName
@onready var info_stats : Label = $Panel/VBox/MainHBox/RightVBox/InfoPanel/InfoVBox/Scroll/ContentVBox/InfoStats
@onready var info_desc : Label = $Panel/VBox/MainHBox/RightVBox/InfoPanel/InfoVBox/Scroll/ContentVBox/InfoDesc

var _selected_unit : String = ""
var _selected_route : String = ""
var _hover_unit : String = ""

const COLOR_UNIT_ON : Color = Color(0.4, 0.9, 0.5, 1)
const COLOR_UNIT_OFF : Color = Color(0.85, 0.85, 0.85, 1)
const COLOR_UNIT_DISABLED : Color = Color(0.45, 0.45, 0.45, 1)
const COLOR_ROUTE_ON : Color = Color(0.4, 0.9, 0.5, 1)

const BTN_HEIGHT : int = 20


func _ready():
	layer = 24
	MusicManager.play_dispatch_music()
	
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
	_update_info_panel()


func _refresh_hint():
	if not hint_label: return
	if _selected_unit == "" and _selected_route == "":
		hint_label.text = "① 选一个单位   ② 选一条空闲路线   ③ 点派遣"
	elif _selected_unit == "":
		var rn : String = DispatchManager.ROUTES.get(_selected_route, {}).get("name", _selected_route)
		hint_label.text = "已选路线「%s」，请选一个单位" % rn
	elif _selected_route == "":
		hint_label.text = "已选单位「%s」，请选一条空闲路线" % _get_unit_display(_selected_unit)
	else:
		var rn : String = DispatchManager.ROUTES.get(_selected_route, {}).get("name", _selected_route)
		hint_label.text = "%s → 「%s」，点【派遣】确认" % [_get_unit_display(_selected_unit), rn]


func _refresh_units():
	for c in unit_row.get_children():
		unit_row.remove_child(c); c.queue_free()

	var all_unlocked : Array = Globals.get_unlocked_units()
	var dispatched : Array = DispatchManager.get_dispatched_unit_names()

	if all_unlocked.is_empty():
		var lb := Label.new()
		lb.text = "（暂无可派遣单位）"
		lb.add_theme_font_size_override("font_size", 7)
		lb.modulate = Color(0.6, 0.6, 0.6)
		unit_row.add_child(lb)
		return

	for unit_key in all_unlocked:
		var btn := Button.new()
		var display_name : String = UnitDataManager.get_display_name(unit_key)
		var is_dispatched : bool = unit_key in dispatched
		var is_selected : bool = unit_key == _selected_unit

		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, BTN_HEIGHT)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 7)
		btn.focus_mode = Control.FOCUS_NONE

		if is_dispatched:
			btn.disabled = true
			btn.text = "  " + display_name + "  (派遣中)"
			btn.modulate = COLOR_UNIT_DISABLED
		else:
			btn.button_pressed = is_selected
			btn.text = "  " + display_name
			btn.modulate = COLOR_UNIT_ON if is_selected else COLOR_UNIT_OFF
			btn.pressed.connect(_on_unit_clicked.bind(unit_key))
			
		# ★ 悬停事件
		btn.mouse_entered.connect(_on_unit_hover.bind(unit_key))
		btn.mouse_exited.connect(_on_unit_hover_exit)

		unit_row.add_child(btn)
		
	# 默认选中第一个可用单位
	if _selected_unit == "":
		for u in all_unlocked:
			if u not in dispatched:
				_selected_unit = u
				break


func _on_unit_clicked(unit_key : String):
	if _selected_unit == unit_key:
		_selected_unit = ""
	else:
		_selected_unit = unit_key
	SoundManager.play_select_sound()
	_refresh_units()
	_refresh_dispatch_btn()
	_refresh_hint()
	if _hover_unit == "":
		_update_info_panel()


# ★ 悬停事件
func _on_unit_hover(unit_key: String):
	if DispatchManager.is_unit_dispatched(unit_key):
		return
	_hover_unit = unit_key
	_update_info_panel()

func _on_unit_hover_exit():
	_hover_unit = ""
	_update_info_panel()


func _refresh_routes():
	for c in route_row.get_children():
		route_row.remove_child(c); c.queue_free()

	var unlocked : Array = DispatchManager.get_unlocked_routes()
	if unlocked.is_empty():
		var lb := Label.new()
		lb.text = "（无可用路线）"
		lb.add_theme_font_size_override("font_size", 7)
		lb.modulate = Color(0.6, 0.6, 0.6)
		route_row.add_child(lb)
		return

	for rid in unlocked:
		var route : Dictionary = DispatchManager.ROUTES[rid]
		var is_busy : bool = DispatchManager.is_route_busy(rid)
		var is_selected : bool = rid == _selected_route

		var btn := Button.new()
		var tags_text : String = "/".join(route.get("tags", []))
		var label_text : String = "%s [%s]" % [route.get("name", rid), tags_text]
		if is_busy:
			label_text += "  (进行中)"
		btn.text = "  " + label_text
		btn.toggle_mode = true
		btn.button_pressed = is_selected
		btn.custom_minimum_size = Vector2(0, BTN_HEIGHT)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 7)
		btn.focus_mode = Control.FOCUS_NONE

		if is_busy:
			btn.disabled = true
			btn.modulate = COLOR_UNIT_DISABLED
		else:
			btn.modulate = COLOR_ROUTE_ON if is_selected else Color.WHITE
			btn.pressed.connect(_on_route_clicked.bind(rid))

		route_row.add_child(btn)


func _on_route_clicked(route_id : String):
	if _selected_route == route_id:
		_selected_route = ""
	else:
		_selected_route = route_id
	SoundManager.play_select_sound()
	_refresh_routes()
	_refresh_dispatch_btn()
	_refresh_hint()


func _refresh_active():
	for c in active_list.get_children():
		active_list.remove_child(c); c.queue_free()

	if DispatchManager.active_dispatches.is_empty():
		var lb := Label.new()
		lb.text = "（无进行中的派遣）"
		lb.add_theme_font_size_override("font_size", 6)
		lb.modulate = Color(0.6, 0.6, 0.6)
		active_list.add_child(lb)
		return

	for d in DispatchManager.active_dispatches:
		var lb := Label.new()
		var route : Dictionary = DispatchManager.ROUTES.get(d.route_id, {})
		var match_mark : String = ""
		var unit_tags : Array = DispatchManager._get_unit_tags(d.unit_name)
		var route_tags : Array = route.get("tags", [])
		for t in unit_tags:
			if t in route_tags:
				match_mark = "  ★ 标签匹配"
				break
		lb.text = "%s → %s（剩 %d 局）%s" % [
			_get_unit_display(d.unit_name),
			route.get("name", d.route_id),
			d.remaining_runs,
			match_mark,
		]
		lb.add_theme_font_size_override("font_size", 7)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if match_mark != "":
			lb.modulate = Color(1.0, 0.85, 0.3)
		active_list.add_child(lb)


func _refresh_dispatch_btn():
	if not dispatch_btn: return
	var has_unit : bool = _selected_unit != ""
	var has_route : bool = _selected_route != ""
	var route_busy : bool = has_route and DispatchManager.is_route_busy(_selected_route)
	var unit_busy : bool = has_unit and DispatchManager.is_unit_dispatched(_selected_unit)
	var ok : bool = has_unit and has_route and not route_busy and not unit_busy
	dispatch_btn.disabled = not ok


func _do_dispatch():
	if _selected_unit == "" or _selected_route == "": return
	if DispatchManager.dispatch(_selected_unit, _selected_route):
		_selected_unit = ""
		_selected_route = ""
		_refresh()
		SoundManager.play_select_sound()


func _on_back_pressed():
	closed.emit()
	queue_free()


func _get_unit_display(unit_key : String) -> String:
	return UnitDataManager.get_display_name(unit_key)


# ============================================================
#  信息栏刷新 (头像 + 属性)
# ============================================================
func _update_info_panel():
	var target_unit = ""
	if _hover_unit != "":
		target_unit = _hover_unit
	elif _selected_unit != "":
		target_unit = _selected_unit
		
	var avatar_rect = $Panel/VBox/MainHBox/RightVBox/InfoPanel/InfoVBox/AvatarRect as TextureRect
	var avatar_bg = $Panel/VBox/MainHBox/RightVBox/InfoPanel/InfoVBox/AvatarBg as Panel

	if target_unit == "":
		info_name.text = "选择单位"
		info_stats.text = ""
		info_desc.text = ""
		_update_avatar("", avatar_rect, avatar_bg)
		return

	var unit_dict = UnitDataManager.get_unit_data(target_unit)
	if unit_dict.is_empty():
		info_name.text = "（无数据）"
		info_stats.text = ""
		info_desc.text = ""
		_update_avatar("", avatar_rect, avatar_bg)
		return

	_update_avatar(target_unit, avatar_rect, avatar_bg)

	var display = unit_dict.get("display_name", target_unit)
	var faction = unit_dict.get("faction", "无")
	var type_cn = UnitDataManager.get_unit_type_display_name(target_unit)

	info_name.text = "%s\n（%s｜%s）" % [display, faction, type_cn]

	var lines : Array = []
	lines.append("HP      %d" % unit_dict.get("max_hp", 0))
	lines.append("力量    %d" % unit_dict.get("strength", 0))
	lines.append("灵巧    %d" % unit_dict.get("dexterity", 0))
	lines.append("智力    %d" % unit_dict.get("intelligence", 0))
	lines.append("信仰    %d" % unit_dict.get("faith", 0))
	lines.append("感应    %d" % unit_dict.get("arcane", 0))
	lines.append("移动力  %d" % unit_dict.get("move_range", 0))

	if DispatchManager.is_unit_dispatched(target_unit):
		lines.append("")
		lines.append("【派遣中，本局不能出战】")

	info_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_stats.text = "\n".join(lines)
	info_desc.text = unit_dict.get("description", "")


func _update_avatar(unit_name: String, avatar_rect: TextureRect, avatar_bg: Panel):
	if not avatar_rect or not avatar_bg: return
	
	if unit_name == "":
		if avatar_bg.visible: PanelRevealer.hide_panel(avatar_bg)
		if avatar_rect.visible: PanelRevealer.hide_panel(avatar_rect)
		return

	var avatar_id = GameState.get_unit_avatar(unit_name)
	var has_avatar = false
	
	if avatar_id != "":
		var path = "res://content/images/characters/avatar/%s.png" % avatar_id
		if ResourceLoader.exists(path):
			avatar_rect.texture = load(path)
			has_avatar = true
			
	if has_avatar:
		avatar_rect.custom_minimum_size = Vector2(48, 48)
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		if not avatar_bg.visible:
			avatar_bg.visible = true
			PanelRevealer.show_panel(avatar_bg)
		if not avatar_rect.visible:
			avatar_rect.visible = true
			PanelRevealer.show_panel(avatar_rect)
	else:
		if avatar_bg.visible: PanelRevealer.hide_panel(avatar_bg)
		if avatar_rect.visible: PanelRevealer.hide_panel(avatar_rect)
