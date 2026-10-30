extends Node
class_name HighlightManager

var highlight_container : Node2D
var _cells : Dictionary = {} 

# ★ 时间缩短：0.15 -> 0.08， 0.08 -> 0.04
const DELAY_TIME : float = 0.08  
const ANIM_TIME : float = 0.04   

var _last_move_center : Vector2i = Vector2i(-1, -1)
var _last_attack_center : Vector2i = Vector2i(-1, -1)

func initialize(container : Node2D):
	highlight_container = container

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

func show_move_highlight(reachable_dict: Dictionary, color: Color = Color(0, 1, 0, 0.4), z_index: int = -1, clear: bool = true, origin_cell: Vector2i = Vector2i(-1, -1)):
	if not highlight_container: return
	
	if origin_cell.x >= 0 and origin_cell.y >= 0:
		_last_move_center = origin_cell
		
	var safe_origin = _last_move_center
	if safe_origin.x < 0: safe_origin = Vector2i.ZERO
	
	if clear:
		_fade_out_missing(reachable_dict, safe_origin, false)
		
	_process_incoming(reachable_dict, color, z_index, safe_origin, false, false)

# ★ 增加 instant 参数：是否硬切
func show_enemy_preview(move_cells: Dictionary, attack_cells: Dictionary, attack_color: Color = Color(0.7, 0.1, 0.2, 0.7), origin_cell: Vector2i = Vector2i(-1, -1), instant: bool = false):
	if not highlight_container: return
	
	if origin_cell.x >= 0 and origin_cell.y >= 0:
		_last_attack_center = origin_cell
		
	var safe_move = _last_move_center
	if safe_move.x < 0: safe_move = Vector2i.ZERO
	var safe_attack = _last_attack_center
	if safe_attack.x < 0: safe_attack = Vector2i.ZERO
	
	_fade_out_missing(move_cells, safe_move, false)
	_fade_out_missing(attack_cells, safe_attack, true)
	
	_process_incoming(move_cells, Color(1, 1, 1, 0.3), -1, safe_move, false, instant)
	_process_incoming(attack_cells, attack_color, 0, safe_attack, true, instant)

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

func _process_incoming(target_cells: Dictionary, color: Color, z_index: int, origin_cell: Vector2i, is_attack_type: bool, instant: bool = false):
	var max_dist = 0
	for cell in target_cells:
		var d = abs(cell.x - origin_cell.x) + abs(cell.y - origin_cell.y)
		max_dist = maxi(max_dist, d)

	for cell in target_cells:
		if _cells.has(cell):
			var data = _cells[cell]
			var was_attack = data.get("is_attack", false)
			
			data["rect"].color = color
			data["rect"].z_index = z_index
			data["is_attack"] = is_attack_type
			
			# ★ 如果要求硬切，直接满透明度
			if instant:
				data["current_a"] = 1.0
				data["target_a"] = 1.0
				data["delay"] = 0.0
				data["rect"].modulate.a = 1.0
				continue
			
			if data["target_a"] == 1.0 and was_attack == is_attack_type:
				continue
				
			if was_attack != is_attack_type:
				data["current_a"] = 0.0
				data["rect"].modulate.a = 0.0
				
			var d = abs(cell.x - origin_cell.x) + abs(cell.y - origin_cell.y)
			var delay_factor = float(d) / float(maxi(1, max_dist))
			data["target_a"] = 1.0
			data["delay"] = delay_factor * DELAY_TIME
			data["speed"] = 1.0 / ANIM_TIME
		else:
			var rect = ColorRect.new()
			rect.color = color
			rect.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
			rect.position = Vector2(cell.x * MapConst.CELL_SIZE, cell.y * MapConst.CELL_SIZE)
			rect.z_index = z_index
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
