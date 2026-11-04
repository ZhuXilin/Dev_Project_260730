extends Node
class_name HighlightManager

var highlight_container : Node2D
var _cells : Dictionary = {} 

const DELAY_TIME : float = 0.08  
const ANIM_TIME : float = 0.04   

var _last_move_center : Vector2i = Vector2i(-1, -1)
var _last_attack_center : Vector2i = Vector2i(-1, -1)

var _cross_texture : ImageTexture = null

var _highlight_shader : Shader = null

func initialize(container : Node2D):
	highlight_container = container
	_highlight_shader = load("res://content/resource/shader/range_indicator.gdshader")

func clear_highlight(origin_cell: Vector2i = Vector2i(-1, -1)):
	if not highlight_container: return
	
	var m_center = origin_cell if origin_cell.x >= 0 else _last_move_center
	var a_center = origin_cell if origin_cell.x >= 0 else _last_attack_center
	
	if m_center.x < 0: m_center = Vector2i.ZERO
	if a_center.x < 0: a_center = Vector2i.ZERO
		
	var max_dist_move = 0
	var max_dist_attack = 0
	
	for cell in _cells:
		var data = _cells[cell]
		var is_attack = data.get("is_attack", false)
		var center = a_center if is_attack else m_center
		var d = abs(cell.x - center.x) + abs(cell.y - center.y)
		if is_attack: max_dist_attack = maxi(max_dist_attack, d)
		else: max_dist_move = maxi(max_dist_move, d)
		
	for cell in _cells.keys():
		var data = _cells[cell]
		if data["target_a"] == 0.0: continue
		
		var is_attack = data.get("is_attack", false)
		var center = a_center if is_attack else m_center
		var max_d = max_dist_attack if is_attack else max_dist_move
		var d = abs(cell.x - center.x) + abs(cell.y - center.y)
		
		var delay_factor = float(max_d - d) / float(maxi(1, max_d))
		data["target_a"] = 0.0
		data["delay"] = delay_factor * DELAY_TIME
		data["speed"] = 1.0 / ANIM_TIME

func clear_highlight_split(move_center: Vector2i, attack_center: Vector2i):
	# ... (保持原样，和 clear_highlight 类似)
	if not highlight_container: return
	if move_center.x < 0 or move_center.y < 0: move_center = Vector2i.ZERO
	if attack_center.x < 0 or attack_center.y < 0: attack_center = Vector2i.ZERO
	
	var max_dist_move = 0
	var max_dist_attack = 0
	for cell in _cells.keys():
		var data = _cells[cell]
		var is_attack = data.get("is_attack", false)
		var center = attack_center if is_attack else move_center
		var d = abs(cell.x - center.x) + abs(cell.y - center.y)
		if is_attack: max_dist_attack = maxi(max_dist_attack, d)
		else: max_dist_move = maxi(max_dist_move, d)
		
	for cell in _cells.keys():
		var data = _cells[cell]
		if data["target_a"] == 0.0: continue
		
		var is_attack = data.get("is_attack", false)
		var center = attack_center if is_attack else move_center
		var max_d = max_dist_attack if is_attack else max_dist_move
		var d = abs(cell.x - center.x) + abs(cell.y - center.y)
		
		var delay_factor = float(max_d - d) / float(maxi(1, max_d))
		data["target_a"] = 0.0
		data["delay"] = delay_factor * DELAY_TIME
		data["speed"] = 1.0 / ANIM_TIME

# ============================================================
# ★ 新增：缓存 4x4 小叉纹理
# ============================================================
func _get_cross_texture() -> ImageTexture:
	if _cross_texture: return _cross_texture
	# 生成一个 4x4 的像素叉（白色，用 modulate 染成对应的攻击色）
	var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	for i in range(4):
		img.set_pixel(i, i, Color(1, 1, 1, 1))
		img.set_pixel(3-i, i, Color(1, 1, 1, 1))
	_cross_texture = ImageTexture.create_from_image(img)
	return _cross_texture


func show_move_highlight(reachable_dict: Dictionary, color: Color = Color(0, 1, 0, 0.4), z_index: int = -1, clear: bool = true, origin_cell: Vector2i = Vector2i(-1, -1), danger_cells: Dictionary = {}, danger_color: Color = Color.RED):
	if not highlight_container: return
	
	if origin_cell.x >= 0 and origin_cell.y >= 0:
		_last_move_center = origin_cell
		
	var safe_origin = _last_move_center
	if safe_origin.x < 0: safe_origin = Vector2i.ZERO
	
	if clear:
		_fade_out_missing(reachable_dict, safe_origin, false)
		
	_process_incoming(reachable_dict, color, z_index, safe_origin, false, false, danger_cells, danger_color)


func show_enemy_preview(move_cells: Dictionary, attack_cells: Dictionary, attack_color: Color = Color(0.7, 0.1, 0.2, 0.7), origin_cell: Vector2i = Vector2i(-1, -1), instant: bool = false, danger_cells: Dictionary = {}, danger_color: Color = Color.RED):
	if not highlight_container: return
	
	if origin_cell.x >= 0 and origin_cell.y >= 0:
		_last_attack_center = origin_cell
		
	var safe_move = _last_move_center
	if safe_move.x < 0: safe_move = Vector2i.ZERO
	var safe_attack = _last_attack_center
	if safe_attack.x < 0: safe_attack = Vector2i.ZERO
	
	_fade_out_missing(move_cells, safe_move, false)
	_fade_out_missing(attack_cells, safe_attack, true)
	
	# 1. 移动格渲染（正常挂载危险区小叉）
	_process_incoming(move_cells, Color(1, 1, 1, 0.3), -1, safe_move, false, instant, danger_cells, danger_color)
	
	# 2. 攻击格渲染
	# ★ 特殊处理：如果是拖拽状态(instant=true)且该落脚点恰好是危险区，挂载小叉；否则不画叉
	var attack_danger = {}
	if instant and danger_cells.has(origin_cell):
		attack_danger[origin_cell] = true
	_process_incoming(attack_cells, attack_color, 0, safe_attack, true, instant, attack_danger, danger_color)


func _process_incoming(target_cells: Dictionary, color: Color, z_index: int, origin_cell: Vector2i, is_attack_type: bool, instant: bool = false, danger_cells: Dictionary = {}, danger_color: Color = Color.RED):
	var max_dist = 0
	for cell in target_cells:
		var d = abs(cell.x - origin_cell.x) + abs(cell.y - origin_cell.y)
		max_dist = maxi(max_dist, d)

	for cell in target_cells:
		if _cells.has(cell):
			var data = _cells[cell]
			var rect = data["rect"]
			var was_attack = data.get("is_attack", false)
			
			var mat : ShaderMaterial = rect.material
			if mat:
				mat.set_shader_parameter("base_color", color)
				
			rect.z_index = z_index
			data["is_attack"] = is_attack_type
			
			# ★ 核心修复 1：动态刷新已存在格子的叉子状态
			var existing_cross = rect.get_node_or_null("DangerCross")
			var should_have_cross = danger_cells.has(cell)
			
			if should_have_cross and existing_cross == null:
				var cross = TextureRect.new()
				cross.name = "DangerCross"
				cross.texture = _get_cross_texture()
				cross.custom_minimum_size = Vector2(4, 4)
				cross.size = Vector2(4, 4)
				cross.position = Vector2(6, 6)
				cross.modulate = danger_color
				cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
				rect.add_child(cross)
			elif not should_have_cross and existing_cross != null:
				existing_cross.queue_free()
			
			if instant:
				data["current_a"] = 1.0
				data["target_a"] = 1.0
				data["delay"] = 0.0
				rect.modulate.a = 1.0
				continue
			
			if data["target_a"] == 1.0 and was_attack == is_attack_type:
				continue
				
			if was_attack != is_attack_type:
				data["current_a"] = 0.0
				rect.modulate.a = 0.0
				
			var d = abs(cell.x - origin_cell.x) + abs(cell.y - origin_cell.y)
			var delay_factor = float(d) / float(maxi(1, max_dist))
			data["target_a"] = 1.0
			data["delay"] = delay_factor * DELAY_TIME
			data["speed"] = 1.0 / ANIM_TIME
		else:
			var rect = ColorRect.new()
			rect.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
			rect.position = Vector2(cell.x * MapConst.CELL_SIZE, cell.y * MapConst.CELL_SIZE)
			rect.z_index = z_index
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			var mat = ShaderMaterial.new()
			mat.shader = _highlight_shader
			mat.set_shader_parameter("base_color", color)
			rect.material = mat
			
			if danger_cells.has(cell):
				var cross = TextureRect.new()
				cross.name = "DangerCross" # ★ 核心修复 2：确保节点名字一致
				cross.texture = _get_cross_texture()
				cross.custom_minimum_size = Vector2(4, 4)
				cross.size = Vector2(4, 4)
				cross.position = Vector2(6, 6)
				cross.modulate = danger_color
				cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
				rect.add_child(cross)
			
			highlight_container.add_child(rect)
			
			if instant:
				rect.modulate.a = 1.0
				_cells[cell] = {
					"rect": rect, "current_a": 1.0, "target_a": 1.0, "delay": 0.0, "speed": 1.0 / ANIM_TIME, "is_attack": is_attack_type
				}
			else:
				rect.modulate.a = 0.0
				var d = abs(cell.x - origin_cell.x) + abs(cell.y - origin_cell.y)
				var delay_factor = float(d) / float(maxi(1, max_dist))
				_cells[cell] = {
					"rect": rect, "current_a": 0.0, "target_a": 1.0, "delay": delay_factor * DELAY_TIME, "speed": 1.0 / ANIM_TIME, "is_attack": is_attack_type
				}


func _fade_out_missing(target_cells: Dictionary, origin_cell: Vector2i, is_attack_type: bool):
	var max_dist = 0
	for cell in _cells.keys():
		var data = _cells[cell]
		if data.get("is_attack", false) != is_attack_type: continue
		var d = abs(cell.x - origin_cell.x) + abs(cell.y - origin_cell.y)
		max_dist = maxi(max_dist, d)
		
	for cell in _cells.keys():
		var data = _cells[cell]
		if data.get("is_attack", false) != is_attack_type: continue
		if not target_cells.has(cell):
			if data["target_a"] == 0.0: continue
			var d = abs(cell.x - origin_cell.x) + abs(cell.y - origin_cell.y)
			var delay_factor = float(max_dist - d) / float(maxi(1, max_dist))
			data["target_a"] = 0.0
			data["delay"] = delay_factor * DELAY_TIME
			data["speed"] = 1.0 / ANIM_TIME

func _process(delta: float):
	var to_remove = []
	for cell in _cells:
		var data = _cells[cell]
		var rect = data["rect"]
		var current_a = data["current_a"]
		var target_a = data["target_a"]
		var delay = data["delay"]
		var speed = data["speed"]
		
		if delay > 0.0:
			data["delay"] = maxf(0.0, delay - delta)
			rect.modulate.a = current_a
			continue
			
		if current_a != target_a:
			if current_a < target_a:
				current_a = minf(1.0, current_a + delta * speed)
			else:
				current_a = maxf(0.0, current_a - delta * speed)
			data["current_a"] = current_a
			rect.modulate.a = current_a
			
		if target_a == 0.0 and current_a <= 0.01:
			to_remove.append(cell)
			
	for c in to_remove:
		if is_instance_valid(_cells[c]["rect"]):
			_cells[c]["rect"].queue_free()
		_cells.erase(c)
