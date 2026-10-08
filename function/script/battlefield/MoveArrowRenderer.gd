class_name MoveArrowRenderer
extends Node2D

# ============================================================
#  MoveArrowRenderer — 拖拽移动的蛇形箭头（无描边）
#  层级：范围高亮(z=-1) < 箭头(z=1) < 单位(z=1，后加)
# ============================================================

const ARROW_WIDTH : float = MapConst.CELL_SIZE / 3.0
const HEAD_LENGTH : float = MapConst.CELL_SIZE / 2.5
const HEAD_HALF_WIDTH : float = MapConst.CELL_SIZE / 3.0
const COLOR_FILL : Color = Color(0.92, 0.92, 0.95, 1.0)

var _line : Line2D = null
var _head : Polygon2D = null


func _ready():
	# 层级：比范围格(-1)高，和单位同层但先加 → 单位盖箭头
	z_index = 1
	z_as_relative = false

	_line = Line2D.new()
	_line.width = ARROW_WIDTH
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_NONE
	_line.end_cap_mode = Line2D.LINE_CAP_NONE
	_line.default_color = COLOR_FILL
	add_child(_line)

	_head = Polygon2D.new()
	_head.color = COLOR_FILL
	add_child(_head)

	visible = false


func show_path(start_cell : Vector2i, path : Array, grid_to_world : Callable):
	if path.size() == 0:
		hide_path()
		return

	var points : PackedVector2Array = PackedVector2Array()
	points.append(grid_to_world.call(start_cell))
	for cell in path:
		points.append(grid_to_world.call(cell))

	_apply_points(points)
	visible = true


func hide_path():
	visible = false


func _apply_points(points : PackedVector2Array):
	if points.size() < 2:
		visible = false
		return

	var p_end : Vector2 = points[points.size() - 1]
	var p_prev : Vector2 = points[points.size() - 2]
	var dir : Vector2 = p_end - p_prev
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var perp : Vector2 = Vector2(-dir.y, dir.x)

	# 箭头三角
	var tip : Vector2 = p_end + dir * (HEAD_LENGTH * 0.5)
	var base_c : Vector2 = p_end - dir * (HEAD_LENGTH * 0.5)
	var left : Vector2 = base_c + perp * HEAD_HALF_WIDTH
	var right : Vector2 = base_c - perp * HEAD_HALF_WIDTH
	_head.polygon = PackedVector2Array([tip, left, right])

	# 主线段：只画到箭头根部，避免与三角重叠
	var line_pts : PackedVector2Array = PackedVector2Array()
	for i in range(points.size() - 1):
		line_pts.append(points[i])
	line_pts.append(base_c)

	_line.points = line_pts
