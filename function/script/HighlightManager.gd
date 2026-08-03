extends Node
class_name HighlightManager

const CELL_SIZE : int = 16
var highlight_container : Node2D

func initialize(container: Node2D):
	highlight_container = container

func clear_highlight():
	print("clear_highlight 被调用，调用栈：")
	print_stack()
	if not highlight_container:
		return
	for child in highlight_container.get_children():
		if child is ColorRect:
			child.queue_free()

# ---- 通用添加高亮格子 ----
func _add_highlight_cells(cells: Dictionary, color: Color, z_index: int):
	if not highlight_container:
		print("错误：highlight_container 为 null")
		return
	for cell in cells.keys():
		var rect = ColorRect.new()
		rect.color = color
		rect.size = Vector2(CELL_SIZE, CELL_SIZE)
		rect.position = Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)
		rect.name = "Highlight_" + str(cell.x) + "_" + str(cell.y)
		rect.z_index = z_index
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight_container.add_child(rect)

# ---- 己方高亮（移动范围 / 攻击范围） ----
func show_move_highlight(reachable_dict: Dictionary, color: Color = Color(0, 1, 0, 0.4), z_index: int = 0, clear: bool = true):
	if clear:
		clear_highlight()
	_add_highlight_cells(reachable_dict, color, z_index)

# ---- 敌方预览（移动范围 + 攻击范围） ----
func show_enemy_preview(move_cells: Dictionary, attack_cells: Dictionary, attack_color: Color = Color(0.7, 0.1, 0.2, 0.7)):
	clear_highlight()
	_add_highlight_cells(move_cells, Color(1, 1, 1, 0.3), 0)
	_add_highlight_cells(attack_cells, attack_color, 1)
