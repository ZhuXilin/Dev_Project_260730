extends Control
class_name MapLayoutCanvas

var editor : Node = null

const ARROW_LENGTH : float = 5.0
const ARROW_WIDTH  : float = 3.5


func _draw():
	if editor == null: return
	var day_layout : MapLayoutDay = editor._get_current_day_layout()
	if day_layout == null: return

	var canvas_w : float = size.x
	var max_layer : int = editor._get_max_layer()
	var in_test : bool = editor._in_test_mode

	if not in_test:
		for i in range(max_layer + 1):
			var y : float = editor.CANVAS_PADDING_TOP + (max_layer - i + 0.5) * editor.LAYER_HEIGHT
			draw_line(Vector2(0, y), Vector2(canvas_w, y),
				Color(0.3, 0.3, 0.3, 0.5), 1)
			var font : Font = ThemeDB.fallback_font
			draw_string(font, Vector2(2, y - 2), "L%d" % i,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.5, 0.5, 0.5, 0.7))

	# ---- 连线（动态 gap）----
	var link_color : Color = Color(0.35, 0.35, 0.35, 0.9) if in_test else Color(0.6, 0.6, 0.6, 0.9)
	for i in range(day_layout.nodes.size()):
		var node : MapLayoutNode = day_layout.nodes[i]
		for target in node.connects_to:
			if target < 0 or target >= day_layout.nodes.size(): continue
			var from_pos : Vector2 = editor._node_pos(i)
			var to_pos : Vector2 = editor._node_pos(target)
			_draw_directed_line(from_pos, to_pos, link_color, 1.0)

	# ---- 节点 ----
	for i in range(day_layout.nodes.size()):
		var node : MapLayoutNode = day_layout.nodes[i]
		var pos : Vector2 = editor._node_pos(i)
		var rect := Rect2(
			pos - Vector2(editor.NODE_W / 2.0, editor.NODE_H / 2.0),
			Vector2(editor.NODE_W, editor.NODE_H)
		)
		if in_test:
			draw_rect(rect, Color(0.1, 0.1, 0.1, 1), true)
			draw_rect(rect, Color(0.4, 0.4, 0.4, 1), false, 1)
			var label : String = editor._test_map_assignment.get(node, "")
			if label == "":
				label = MapConst.get_node_display_name(node.node_type)
			if label.length() > 8:
				label = label.substr(0, 7) + "…"
			var font : Font = ThemeDB.fallback_font
			var font_size : int = 5
			var text_size : Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var ascent : float = font.get_ascent(font_size)
			var descent : float = font.get_descent(font_size)
			var baseline_y : float = pos.y + (ascent - descent) / 2.0
			draw_string(font, Vector2(pos.x - text_size.x / 2.0, baseline_y),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.85, 0.85, 0.85))
		else:
			var color : Color = _node_color(node)
			draw_rect(rect, color, true)
			var label2 : String = _node_label(node)
			var font2 : Font = ThemeDB.fallback_font
			var font_size2 : int = editor.NODE_FONT_SIZE
			var text_size2 : Vector2 = font2.get_string_size(label2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size2)
			var ascent2 : float = font2.get_ascent(font_size2)
			var descent2 : float = font2.get_descent(font_size2)
			var baseline_y2 : float = pos.y + (ascent2 - descent2) / 2.0
			draw_string(font2, Vector2(pos.x - text_size2.x / 2.0, baseline_y2),
				label2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size2, Color.BLACK)

	if not in_test and editor._selected_link >= 0:
		var p : Vector2 = editor._node_pos(editor._selected_link)
		var rect2 := Rect2(
			p - Vector2(editor.NODE_W / 2.0 + 2, editor.NODE_H / 2.0 + 2),
			Vector2(editor.NODE_W + 4, editor.NODE_H + 4)
		)
		draw_rect(rect2, Color.YELLOW, false, 2)

	if not in_test and editor._dragging_idx >= 0:
		var new_layer : int = editor._layer_at_y(editor._mouse_pos.y)
		var preview_y : float = editor.CANVAS_PADDING_TOP + (max_layer - new_layer + 0.5) * editor.LAYER_HEIGHT
		draw_line(Vector2(0, preview_y), Vector2(canvas_w, preview_y),
			Color(1, 1, 0, 0.5), 1)


# ============================================================
#  带方向箭头（动态出口距离）
# ============================================================
func _draw_directed_line(from_pos: Vector2, to_pos: Vector2, color: Color, width: float = 1.0):
	var dir : Vector2 = to_pos - from_pos
	var dist : float = dir.length()
	if dist < 1.0:
		return
	dir = dir / dist
	var perp : Vector2 = Vector2(-dir.y, dir.x)

	# ★ 动态 gap：沿 dir 方向走到目标矩形边界外 2px
	var hw : float = editor.NODE_W * 0.5
	var hh : float = editor.NODE_H * 0.5
	var gap : float = _exit_gap_distance(dir, hw, hh) + 2.0
	var line_end : Vector2 = to_pos - dir * gap

	# 若线段被压得过短 → 退化到中点
	if (line_end - from_pos).dot(dir) <= 0.0:
		line_end = from_pos + dir * (dist * 0.5)
		# 中点太短就放弃箭头（只画线）
		draw_line(from_pos, line_end, color, width)
		return

	draw_line(from_pos, line_end, color, width)

	# 箭头三角
	var tip : Vector2 = line_end
	var base_center : Vector2 = line_end - dir * ARROW_LENGTH
	var left : Vector2 = base_center + perp * ARROW_WIDTH * 0.5
	var right : Vector2 = base_center - perp * ARROW_WIDTH * 0.5
	var arrow_color : Color = color.lightened(0.3)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), arrow_color)


## 从矩形中心沿 dir 走到矩形边界的距离
func _exit_gap_distance(dir: Vector2, hw: float, hh: float) -> float:
	var ax : float = abs(dir.x)
	var ay : float = abs(dir.y)
	if ax < 0.001:
		return hh
	if ay < 0.001:
		return hw
	return min(hw / ax, hh / ay)


func _node_color(node: MapLayoutNode) -> Color:
	if not node.random_pool.is_empty():
		return Color(0.9, 0.85, 0.3)
	match node.node_type:
		MapNode.NodeType.START: return Color(0.3, 0.9, 0.3)
		MapNode.NodeType.NORMAL: return Color(0.85, 0.85, 0.85)
		MapNode.NodeType.ELITE: return Color(1.0, 0.4, 0.4)
		MapNode.NodeType.SHOP: return Color(0.4, 0.7, 1.0)
		MapNode.NodeType.TREASURE: return Color(0.7, 0.5, 1.0)
		MapNode.NodeType.BOSS: return Color(1.0, 0.3, 0.8)
		MapNode.NodeType.FORGE: return Color(1.0, 0.7, 0.4)
		MapNode.NodeType.CHAPEL: return Color(0.9, 0.9, 0.4)
	return Color.WHITE


func _node_label(node: MapLayoutNode) -> String:
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
		MapNode.NodeType.SHOP: return "SH"
		MapNode.NodeType.TREASURE: return "TR"
		MapNode.NodeType.BOSS: return "BS"
		MapNode.NodeType.FORGE: return "FG"
		MapNode.NodeType.CHAPEL: return "CH"
	return "?"
