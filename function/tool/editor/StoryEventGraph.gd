class_name StoryEventGraph
extends Control

# ============================================================
#  StoryEventGraph — 事件节点图（Canvas 风格）
#  事件节点 + action 子节点 + 连线
# ============================================================

signal event_node_clicked()
signal action_node_clicked(idx : int)

const NODE_W : float = 110.0
const NODE_H : float = 26.0
const NODE_GAP_X : float = 12.0
const NODE_GAP_Y : float = 34.0
const NODE_RADIUS : float = 3.0
const TOP_PADDING : float = 10.0
const SIDE_PADDING : float = 10.0

const COL_EVENT_BG     : Color = Color(0.18, 0.22, 0.32, 1.0)
const COL_EVENT_BORDER : Color = Color(0.55, 0.75, 1.0, 1.0)
const COL_ACTION_BG    : Color = Color(0.12, 0.14, 0.18, 1.0)
const COL_ACTION_BORDER: Color = Color(0.42, 0.46, 0.56, 1.0)
const COL_LINK         : Color = Color(0.42, 0.46, 0.56, 0.85)
const COL_SELECTED     : Color = Color(1.0, 0.85, 0.3, 1.0)
const COL_TEXT         : Color = Color(0.92, 0.92, 0.96)
const COL_TEXT_SUB     : Color = Color(0.72, 0.74, 0.82)
const COL_BG           : Color = Color(0.06, 0.06, 0.08)

var _events : Dictionary = {}
var _event_id : String = ""
var _selected_action : int = -1

# 布局缓存
var _event_rect : Rect2 = Rect2()
var _action_rects : Array[Rect2] = []
var _hover_action : int = -1


func set_events_ref(events_ref : Dictionary) -> void:
	_events = events_ref


func show_event(event_id : String) -> void:
	_event_id = event_id
	_selected_action = -1
	_hover_action = -1
	_relayout()
	queue_redraw()


func set_selected_action(idx : int) -> void:
	_selected_action = idx
	queue_redraw()


# ============================================================
#  布局
# ============================================================
func _relayout() -> void:
	_action_rects.clear()
	var ev : Dictionary = _events.get(_event_id, {})
	if ev.is_empty():
		return

	var w : float = size.x
	if w <= 0.0:
		return

	# 事件节点
	_event_rect = Rect2(
		(w - NODE_W) * 0.5, TOP_PADDING,
		NODE_W, NODE_H
	)

	var actions : Array = ev.get("actions", [])
	if actions.is_empty():
		return

	# 每行最多几个（根据宽度）
	var per_row : int = maxi(1, int((w - SIDE_PADDING * 2.0 + NODE_GAP_X) / (NODE_W + NODE_GAP_X)))
	var rows : int = int(ceil(float(actions.size()) / float(per_row)))

	var action_top : float = TOP_PADDING + NODE_H + NODE_GAP_Y

	for row in range(rows):
		var from_idx : int = row * per_row
		var to_idx : int = mini(from_idx + per_row, actions.size())
		var count_in_row : int = to_idx - from_idx
		var row_w : float = count_in_row * NODE_W + (count_in_row - 1) * NODE_GAP_X
		var start_x : float = (w - row_w) * 0.5
		var y : float = action_top + row * (NODE_H + NODE_GAP_Y)
		for j in range(count_in_row):
			var idx : int = from_idx + j
			var rx : float = start_x + j * (NODE_W + NODE_GAP_X)
			_action_rects.append(Rect2(rx, y, NODE_W, NODE_H))

	# 自动扩展自身高度
	var total_h : float = action_top + rows * (NODE_H + NODE_GAP_Y) + TOP_PADDING
	if custom_minimum_size.y < total_h:
		custom_minimum_size = Vector2(0, total_h)


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)

	var ev : Dictionary = _events.get(_event_id, {})
	if ev.is_empty():
		_draw_center_text("（未选择事件）", COL_TEXT_SUB)
		return
	if _event_rect.size.x <= 0.0:
		_relayout()

	var actions : Array = ev.get("actions", [])
	var font : Font = ThemeDB.fallback_font

	# ---- 连线 ----
	var event_bottom := _event_rect.position + Vector2(_event_rect.size.x * 0.5, _event_rect.size.y)
	for i in range(_action_rects.size()):
		var r : Rect2 = _action_rects[i]
		var action_top := r.position + Vector2(r.size.x * 0.5, 0)
		draw_line(event_bottom, action_top, COL_LINK, 1.0)

	# ---- 事件节点 ----
	_draw_node(_event_rect, COL_EVENT_BG, COL_EVENT_BORDER)
	_draw_text_in_rect(_event_rect, _event_id, 7, COL_TEXT)
	var once_txt : String = "once" if bool(ev.get("once", true)) else "repeatable"
	_draw_text_in_rect(_event_rect, once_txt, 5, COL_TEXT_SUB, 10.0)

	# ---- action 节点 ----
	for i in range(_action_rects.size()):
		var r2 : Rect2 = _action_rects[i]
		var is_selected : bool = (i == _selected_action)
		var is_hovered : bool = (i == _hover_action)
		var bg : Color = COL_ACTION_BG
		var border : Color = COL_ACTION_BORDER
		if is_selected:
			border = COL_SELECTED
		elif is_hovered:
			bg = COL_ACTION_BG.lightened(0.15)

		var a : Dictionary = actions[i] if i < actions.size() else {}
		_draw_node(r2, bg, border, 2.0 if is_selected else 1.0)

		var type_str : String = "?" + str(a.get("type", ""))
		_draw_text_in_rect(r2, "%d. %s" % [i, type_str], 6, COL_TEXT)
		var preview : String = _action_preview(a)
		if preview != "":
			_draw_text_in_rect(r2, preview, 5, COL_TEXT_SUB, 10.0)


func _draw_node(rect : Rect2, bg : Color, border : Color, width : float = 1.0):
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, width)


func _draw_text_in_rect(rect : Rect2, text : String, fs : int, color : Color, y_off : float = 0.0):
	var font : Font = ThemeDB.fallback_font
	var ts : Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var ascent : float = font.get_ascent(fs)
	var descent : float = font.get_descent(fs)
	var baseline : float = rect.position.y + (rect.size.y + ascent - descent) * 0.5 + y_off
	var x : float = rect.position.x + (rect.size.x - ts.x) * 0.5
	draw_string(font, Vector2(x, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_center_text(text : String, color : Color):
	var font : Font = ThemeDB.fallback_font
	var ts : Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
	var baseline : float = size.y * 0.5
	draw_string(font, Vector2((size.x - ts.x) * 0.5, baseline),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, color)


func _action_preview(a : Dictionary) -> String:
	var t : String = str(a.get("type", ""))
	match t:
		"dialog":
			return str(a.get("dialog_id", ""))
		"give_item":
			var iid : String = str(a.get("item_id", ""))
			var cnt : int = int(a.get("count", 1))
			return "%s ×%d" % [iid, cnt] if cnt > 1 else iid
		"heal", "damage":
			return str(a.get("amount", 0))
		"wait":
			return "%.1fs" % float(a.get("seconds", 0.5))
		"gold", "soul":
			return str(a.get("amount", 0))
		"unlock_unit":
			var us : Array = a.get("units", [])
			return ",".join(us).substr(0, 20) if not us.is_empty() else ""
		"unlock_talent":
			return str(a.get("talent_id", ""))
		"unlock_equipment":
			return str(a.get("item_id", ""))
		"unlock_relics":
			var rs : Array = a.get("relics", [])
			return ",".join(rs).substr(0, 20) if not rs.is_empty() else ""
	return ""


# ============================================================
#  输入
# ============================================================
func _gui_input(event : InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mp : Vector2 = event.position
		var new_hover : int = -1
		for i in range(_action_rects.size()):
			if _action_rects[i].has_point(mp):
				new_hover = i
				break
		if new_hover != _hover_action:
			_hover_action = new_hover
			queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp2 : Vector2 = event.position
		if _event_rect.has_point(mp2):
			event_node_clicked.emit()
			return
		for i in range(_action_rects.size()):
			if _action_rects[i].has_point(mp2):
				_selected_action = i
				action_node_clicked.emit(i)
				queue_redraw()
				return


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_relayout()
		queue_redraw()
