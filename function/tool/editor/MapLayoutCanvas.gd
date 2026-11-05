@tool
extends Control
class_name MapLayoutCanvas

var editor = null
var _hover_idx : int = -1

const ARROW_LENGTH : float = 5.0
const ARROW_WIDTH  : float = 3.5


func _gui_input(e : InputEvent):
	if editor == null: return
	
	# ★ 核心：在测试模式下追踪鼠标悬停
	if editor._in_test_mode:
		if e is InputEventMouseMotion:
			var day_layout = editor._get_current_day_layout()
			if day_layout:
				var old_hover = _hover_idx
				_hover_idx = -1
				for i in range(day_layout.nodes.size()):
					var pos : Vector2 = editor._node_pos(i)
					var rect := Rect2(
						pos - Vector2(editor.NODE_W / 2.0, editor.NODE_H / 2.0),
						Vector2(editor.NODE_W, editor.NODE_H)
					)
					if rect.grow(4).has_point(e.position):
						_hover_idx = i
						break
				if _hover_idx != old_hover:
					queue_redraw()
			return
			
	editor._on_canvas_input(e)

func _draw():
	if editor == null: return
	var day_layout = editor._get_current_day_layout()
	if day_layout == null: return

	var canvas_w : float = size.x
	var max_layer : int = editor._get_max_layer()
	var in_test : bool = editor._in_test_mode

	# 编辑模式的底层辅助线
	if not in_test:
		for i in range(max_layer + 1):
			var y : float = editor.CANVAS_PADDING_TOP + (max_layer - i + 0.5) * editor.LAYER_HEIGHT
			draw_line(Vector2(0, y), Vector2(canvas_w, y), Color(0.3, 0.3, 0.3, 0.5), 1)
			var font : Font = ThemeDB.fallback_font
			draw_string(font, Vector2(2, y - 2), "L%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.5, 0.5, 0.5, 0.7))

	var link_color : Color = Color.WHITE if in_test else Color(0.6, 0.6, 0.6, 0.9)
	for i in range(day_layout.nodes.size()):
		var node = day_layout.nodes[i]
		for target in node.connects_to:
			if target < 0 or target >= day_layout.nodes.size(): continue
			var from_pos : Vector2 = editor._node_pos(i)
			var to_pos : Vector2 = editor._node_pos(target)
			_draw_directed_line(from_pos, to_pos, link_color, 1.0)

	for i in range(day_layout.nodes.size()):
		var node = day_layout.nodes[i]
		var pos : Vector2 = editor._node_pos(i)
		var rect := Rect2(
			pos - Vector2(editor.NODE_W / 2.0, editor.NODE_H / 2.0),
			Vector2(editor.NODE_W, editor.NODE_H)
		)
		
		if in_test:
			# --- 测试模式：纯粹显示图标和名字 ---
			var is_pool = not node.random_pool.is_empty()
			var real_type = node.node_type
			if node.node_type == MapNode.NodeType.QUESTION and node.hidden_node_type != -1:
				real_type = node.hidden_node_type
				
			var tex = null
			if is_pool:
				tex = MapConst.get_node_texture(node.random_pool[0], -1)
			else:
				tex = MapConst.get_node_texture(real_type, -1)

			# 1. 绘制图标（修复变量名冲突：draw_rect 改为 image_rect）
			if tex:
				var tex_size = tex.get_size()
				var image_rect = Rect2(pos - tex_size / 2.0, tex_size)
				draw_texture_rect(tex, image_rect, false)
			else:
				# 如果没图，画个明显的占位，防止看不见
				draw_rect(rect, Color(0.8, 0.2, 0.8, 0.8), true)

			# 2. 绘制下方的文本
			var label : String = editor._test_map_assignment.get(node, "")
			if label != "":
				var font : Font = ThemeDB.fallback_font
				var font_size : int = 7
				var text_size : Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				
				var text_y = pos.y + editor.NODE_H / 2.0 + 10
				var text_pos = Vector2(pos.x - text_size.x / 2.0, text_y)
				
				draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color.BLACK)
				draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
				
		else:
			# --- 编辑模式 ---
			var color : Color = _node_color(node)
			draw_rect(rect, color, true)
			var label2 : String = _node_label(node)
			var font2 : Font = ThemeDB.fallback_font
			var font_size2 : int = editor.NODE_FONT_SIZE
			var text_size2 : Vector2 = font2.get_string_size(label2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size2)
			var ascent2 : float = font2.get_ascent(font_size2)
			var descent2 : float = font2.get_descent(font_size2)
			var baseline_y2 : float = pos.y + (ascent2 - descent2) / 2.0
			draw_string(font2, Vector2(pos.x - text_size2.x / 2.0, baseline_y2), label2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size2, Color.BLACK)

			if not node.unlock_relics.is_empty():
				var relic_line : String = _format_relic_line(node.unlock_relics)
				if relic_line != "":
					var font_r : Font = ThemeDB.fallback_font
					var font_size_r : int = 4
					var ts_r : Vector2 = font_r.get_string_size(relic_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_r)
					var rel_y : float = pos.y + editor.NODE_H / 2.0 + 6.0
					draw_string(font_r, Vector2(pos.x - ts_r.x / 2.0, rel_y), relic_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_r, Color(1.0, 0.82, 0.3, 1.0))

	if not in_test and editor._selected_link >= 0:
		var p : Vector2 = editor._node_pos(editor._selected_link)
		var rect2 := Rect2(p - Vector2(editor.NODE_W / 2.0 + 2, editor.NODE_H / 2.0 + 2), Vector2(editor.NODE_W + 4, editor.NODE_H + 4))
		draw_rect(rect2, Color.YELLOW, false, 2)

	if not in_test and editor._dragging_idx >= 0:
		var new_layer : int = editor._layer_at_y(editor._mouse_pos.y)
		var preview_y : float = editor.CANVAS_PADDING_TOP + (max_layer - new_layer + 0.5) * editor.LAYER_HEIGHT
		draw_line(Vector2(0, preview_y), Vector2(canvas_w, preview_y), Color(1, 1, 0, 0.5), 1)

func _draw_directed_line(from_pos: Vector2, to_pos: Vector2, color: Color, width: float = 1.0):
	var dx = to_pos.x - from_pos.x
	var dy = to_pos.y - from_pos.y
	var points : PackedVector2Array = PackedVector2Array()
	
	var segments : int = 24
	
	if abs(dx) < 2.0:
		# 垂直直线也细分点，方便后面算切线方向
		for i in range(segments + 1):
			var t : float = float(i) / float(segments)
			points.append(from_pos.lerp(to_pos, t))
	else:
		# S 型曲线
		var mid_y = from_pos.y + dy * 0.5
		var p1 = Vector2(from_pos.x, mid_y)
		var p2 = Vector2(to_pos.x, mid_y)
		
		for i in range(segments + 1):
			var t : float = float(i) / float(segments)
			var p : Vector2 = pow(1 - t, 3) * from_pos + 3 * pow(1 - t, 2) * t * p1 + 3 * (1 - t) * pow(t, 2) * p2 + pow(t, 3) * to_pos
			points.append(p)
			
	draw_polyline(points, color, width)
	
	# ★ 绘制箭头：放在 65% 的位置，防止被两端节点遮挡
	var arrow_t : float = 0.65
	var arrow_idx : int = int(segments * arrow_t)
	var tip : Vector2 = points[arrow_idx]
	var prev_p : Vector2 = points[arrow_idx - 1]
	
	var dir = (tip - prev_p).normalized()
	if dir == Vector2.ZERO:
		dir = (to_pos - from_pos).normalized()
		
	var perp = Vector2(-dir.y, dir.x)
	var arrow_len = 6.0
	var arrow_w = 3.0
	
	var base_center = tip - dir * arrow_len
	var left = base_center + perp * arrow_w
	var right = base_center - perp * arrow_w
	
	draw_colored_polygon(PackedVector2Array([tip, left, right]), color)

func _exit_gap_distance(dir: Vector2, hw: float, hh: float) -> float:
	var ax : float = abs(dir.x)
	var ay : float = abs(dir.y)
	if ax < 0.001:
		return hh
	if ay < 0.001:
		return hw
	return min(hw / ax, hh / ay)


func _node_color(node) -> Color:
	if not node.random_pool.is_empty():
		return Color(0.9, 0.85, 0.3)
	match node.node_type:
		MapNode.NodeType.START: return Color(0.3, 0.9, 0.3)
		MapNode.NodeType.NORMAL: return Color(0.85, 0.85, 0.85)
		MapNode.NodeType.ELITE: return Color(1.0, 0.4, 0.4)
		MapNode.NodeType.TREASURE: return Color(0.7, 0.5, 1.0)
		MapNode.NodeType.BOSS: return Color(1.0, 0.3, 0.8)
		MapNode.NodeType.FORGE: return Color(1.0, 0.7, 0.4)
		MapNode.NodeType.CHAPEL: return Color(0.9, 0.9, 0.4)
		MapNode.NodeType.QUESTION: return Color(0.2, 0.8, 0.8)
	return Color.WHITE


func _node_label(node) -> String:
	if not node.random_pool.is_empty():
		var parts : Array = []
		for t in node.random_pool:
			parts.append(_node_type_short(t))
		return "/".join(parts)
	return _node_type_short(node.node_type)


func _node_type_short(t: int) -> String:
	match t:
		MapNode.NodeType.START: return "ST"
		MapNode.NodeType.NORMAL: return "NM"
		MapNode.NodeType.ELITE: return "EL"
		MapNode.NodeType.TREASURE: return "TR"
		MapNode.NodeType.BOSS: return "BS"
		MapNode.NodeType.FORGE: return "FG"
		MapNode.NodeType.CHAPEL: return "CH"
		MapNode.NodeType.QUESTION: return "?"
	return "?"


func _format_relic_line(relics: Array) -> String:
	var names : Array = []
	for rid in relics:
		if not (rid is String) or rid == "":
			continue
		var n : String = ""
		if editor and editor.has_method("_relic_display_name"):
			n = editor._relic_display_name(rid)
		else:
			n = rid
		names.append(n)
		if names.size() >= 2:
			break
	var line : String = " ".join(names)
	if relics.size() > 2:
		line += "…"
	return line
