extends Control
class_name MapLayoutCanvas

var editor : Node = null


func _draw():
	if editor == null: return
	var day_layout : MapLayoutDay = editor._get_current_day_layout()
	if day_layout == null: return

	var canvas_w : float = size.x
	var max_layer : int = editor._get_max_layer()

	# ---- 网格层线 ----
	for i in range(max_layer + 1):
		var y : float = editor.CANVAS_PADDING_TOP + (max_layer - i + 0.5) * editor.LAYER_HEIGHT
		draw_line(Vector2(0, y), Vector2(canvas_w, y),
			Color(0.3, 0.3, 0.3, 0.5), 1)
		var font : Font = ThemeDB.fallback_font
		draw_string(font, Vector2(2, y - 2), "L%d" % i,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.5, 0.5, 0.5, 0.7))

	# ---- 连线 ----
	for i in range(day_layout.nodes.size()):
		var node : MapLayoutNode = day_layout.nodes[i]
		for target in node.connects_to:
			if target < 0 or target >= day_layout.nodes.size(): continue
			var from_pos : Vector2 = editor._node_pos(i)
			var to_pos : Vector2 = editor._node_pos(target)
			draw_line(from_pos, to_pos, Color(0.6, 0.6, 0.6, 0.9), 1)

	# ---- 节点（无描边） ----
	for i in range(day_layout.nodes.size()):
		var node : MapLayoutNode = day_layout.nodes[i]
		var pos : Vector2 = editor._node_pos(i)
		var color : Color = _node_color(node)
		var rect := Rect2(
			pos - Vector2(editor.NODE_W / 2.0, editor.NODE_H / 2.0),
			Vector2(editor.NODE_W, editor.NODE_H)
		)
		# ★ 只填充，不描边
		draw_rect(rect, color, true)

		# ★ 文字上下居中：用 font 的 ascent 精确居中
		var label : String = _node_label(node)
		var font : Font = ThemeDB.fallback_font
		var font_size : int = editor.NODE_FONT_SIZE
		var text_size : Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var ascent : float = font.get_ascent(font_size)
		var descent : float = font.get_descent(font_size)
		# 垂直居中的文字基线偏移
		var baseline_y : float = pos.y + (ascent - descent) / 2.0
		draw_string(font,
			Vector2(pos.x - text_size.x / 2.0, baseline_y),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

	# ---- 选中高亮（连线模式）----
	if editor._selected_link >= 0:
		var p : Vector2 = editor._node_pos(editor._selected_link)
		var rect2 := Rect2(
			p - Vector2(editor.NODE_W / 2.0 + 2, editor.NODE_H / 2.0 + 2),
			Vector2(editor.NODE_W + 4, editor.NODE_H + 4)
		)
		draw_rect(rect2, Color.YELLOW, false, 2)

	# ---- 拖拽预览 ----
	if editor._dragging_idx >= 0:
		var new_layer : int = editor._layer_at_y(editor._mouse_pos.y)
		var preview_y : float = editor.CANVAS_PADDING_TOP + (max_layer - new_layer + 0.5) * editor.LAYER_HEIGHT
		draw_line(Vector2(0, preview_y), Vector2(canvas_w, preview_y),
			Color(1, 1, 0, 0.5), 1)


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
