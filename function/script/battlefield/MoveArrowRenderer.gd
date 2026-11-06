class_name MoveArrowRenderer
extends Node2D

# ============================================================
#  MoveArrowRenderer — 拖拽移动的蛇形箭头（终点改为圆点）
#  层级：范围高亮(z=-1) < 箭头(z=1) < 单位(z=1，后加)
# ============================================================

const ARROW_WIDTH : float = 2.0
const COLOR_FILL : Color = Color(0.8, 0.9, 1.0, 1.0) 

var _line : Line2D = null
var _head_sprite : Sprite2D = null


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
	_line.antialiased = false
	add_child(_line)

	# 用 6x6 的圆点替代原来的三角形箭头
	_head_sprite = Sprite2D.new()
	_head_sprite.texture = _make_circle_texture(2, COLOR_FILL) 
	add_child(_head_sprite)

	visible = false


func _make_circle_texture(radius: int, color: Color) -> ImageTexture:
	var size = radius * 2
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var dx = x - radius + 0.5
			var dy = y - radius + 0.5
			if dx * dx + dy * dy <= radius * radius:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


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

	# ★ 强制圆点坐标取整，消除亚像素偏移
	_head_sprite.position = p_end.round()

	# ★ 将整条线段的坐标也进行取整
	var rounded_points : PackedVector2Array = PackedVector2Array()
	for p in points:
		rounded_points.append(p.round())

	# 主线段直接贯穿到终点，由圆点覆盖线头
	_line.points = rounded_points
