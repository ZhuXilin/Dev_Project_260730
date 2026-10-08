class_name MoveArrowRenderer
extends Node2D

# ============================================================
#  MoveArrowRenderer — 拖拽移动的蛇形箭头
#  样式参考 GBA 火纹：粗线 + 圆角转弯 + 末端三角箭头
# ============================================================

const ARROW_WIDTH : float = MapConst.CELL_SIZE / 4.0     # 4px
const HEAD_LENGTH : float = MapConst.CELL_SIZE / 2.5
const HEAD_HALF_WIDTH : float = MapConst.CELL_SIZE / 4.0
const COLOR_FILL : Color = Color(1.0, 0.95, 0.4, 0.9)
const COLOR_OUTLINE : Color = Color(0.15, 0.1, 0.05, 0.95)

var _line : Line2D = null
var _head : Polygon2D = null
var _outline_line : Line2D = null
var _outline_head : Polygon2D = null


func _ready():
	z_index = 20          # 高于移动范围(0) / 攻击范围(1)
	z_as_relative = false

	_outline_line = Line2D.new()
	_outline_line.width = ARROW_WIDTH + 2.0
	_outline_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_outline_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_outline_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_outline_line.default_color = COLOR_OUTLINE
	add_child(_outline_line)

	_outline_head = Polygon2D.new()
	_outline_head.color = COLOR_OUTLINE
	add_child(_outline_head)

	_line = Line2D.new()
	_line.width = ARROW_WIDTH
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.default_color = COLOR_FILL
	add_child(_line)

	_head = Polygon2D.new()
	_head.color = COLOR_FILL
	add_child(_head)

	visible = false


func show_path(start_cell: Vector2i, path: Array, grid_to_world: Callable):
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


func _apply_points(points: PackedVector2Array):
	if points.size() < 2:
		visible = false
		return

	_line.points = points
	_outline_line.points = points

	var p_end : Vector2 = points[points.size() - 1]
	var p_prev : Vector2 = points[points.size() - 2]
	var dir : Vector2 = p_end - p_prev
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var perp : Vector2 = Vector2(-dir.y, dir.x)

	var tip : Vector2 = p_end + dir * (HEAD_LENGTH * 0.4)
	var base_c : Vector2 = p_end - dir * (HEAD_LENGTH * 0.6)
	var left : Vector2 = base_c + perp * HEAD_HALF_WIDTH
	var right : Vector2 = base_c - perp * HEAD_HALF_WIDTH
	_head.polygon = PackedVector2Array([tip, left, right])

	# 描边（1.25x）
	var s : float = 1.25
	var o_tip : Vector2 = p_end + dir * (HEAD_LENGTH * 0.4 * s)
	var o_base : Vector2 = p_end - dir * (HEAD_LENGTH * 0.6 * s)
	_outline_head.polygon = PackedVector2Array([
		o_tip,
		o_base + perp * HEAD_HALF_WIDTH * s,
		o_base - perp * HEAD_HALF_WIDTH * s,
	])
