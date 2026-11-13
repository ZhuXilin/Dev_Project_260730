extends Node

# ============================================================
#  WaveManager — 波次与增援（智能推导版）
# ============================================================

var _type_total_waves : int = 1
var _current_wave : int = 1
var _pending_groups : Array = []          # Array[Array[Unit]]
var _next_wave_delay : int = 0
var _warning_shown : bool = false

var _map_data : MapData = null
var _battlefield : Node2D = null

signal wave_advanced(current_wave: int, total_waves: int)


func setup_for_node(map_data : MapData, battlefield : Node2D = null) -> void:
	reset()
	_map_data = map_data
	_battlefield = battlefield
	if map_data == null:
		return

	# 注意：这里不再直接读取 map_data.max_waves 作为总数
	# 留给 _build_groups 进行动态推导
	call_deferred("_build_groups")


func reset() -> void:
	_type_total_waves = 1
	_current_wave = 1
	_pending_groups.clear()
	_next_wave_delay = 0
	_warning_shown = false
	_map_data = null
	_battlefield = null


func get_current_wave() -> int:
	return _current_wave

func get_total_waves() -> int:
	return _type_total_waves

func has_pending_waves() -> bool:
	return not _pending_groups.is_empty()

func is_active() -> bool:
	return _type_total_waves > 1


# ============================================================
#  分组核心算法
# ============================================================
func _build_groups():
	var enemies : Array = []
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.unit_stats.team_id != 1: continue
		if u.hit_points <= 0: continue
		enemies.append(u)

	if enemies.is_empty():
		return

	var explicit_map : Dictionary = {}
	var max_wave_in_scene : int = 1
	
	for u in enemies:
		var w : int = int(u.get_meta("wave", 1))
		max_wave_in_scene = maxi(max_wave_in_scene, w)
		if not explicit_map.has(w):
			explicit_map[w] = []
		explicit_map[w].append(u)

	# ★ 核心：结合地图配置与场景实际波次
	var target_total : int = max_wave_in_scene
	if _map_data != null:
		target_total = maxi(max_wave_in_scene, _map_data.max_waves)

	_build_groups_by_target(explicit_map, target_total)


func _build_groups_by_target(wave_map: Dictionary, target_total: int):
	var sorted_waves : Array = wave_map.keys()
	sorted_waves.sort()

	var groups : Array = []
	for w in sorted_waves:
		groups.append(wave_map[w])

	_current_wave = 1
	_pending_groups.clear()
	_next_wave_delay = 0
	_warning_shown = false

	_type_total_waves = maxi(1, target_total)

	# 如果只有 1 波，不开启波次隐藏
	if _type_total_waves <= 1:
		wave_advanced.emit(1, 1)
		return

	# 隐藏第 2 波及以后的所有单位
	for gi in range(1, groups.size()):
		var g : Array = groups[gi]
		for u in g:
			if not is_instance_valid(u): continue
			_hide_unit(u)
		_pending_groups.append(g)

	# ★ 如果地图要求的总波次 > 场景里实际摆的波次，补空组（触发动态增援）
	var missing_waves : int = _type_total_waves - groups.size()
	for i in range(missing_waves):
		_pending_groups.append([]) # 空组，在激活时会调用 _spawn_reinforcements

	print("[Wave] 场景摆放最高 %d 波，地图要求 %d 波，实际生成 %d 个待命组" % [
		groups.size(), _type_total_waves, _pending_groups.size()])
	wave_advanced.emit(1, _type_total_waves)


func _hide_unit(u: Unit):
	u.visible = false
	u.process_mode = Node.PROCESS_MODE_DISABLED
	u.can_act_this_turn = false
	u.remaining_move = 0
	u.hit_points = u.unit_stats.max_hp
	if u is CollisionObject2D:
		(u as CollisionObject2D).set_collision_layer_value(1, false)


func _show_unit(u: Unit):
	if not is_instance_valid(u):
		return

	# 先强制重置所有状态，保证出场后绝对可见
	u.visible = true
	u.process_mode = Node.PROCESS_MODE_INHERIT
	u.hit_points = u.unit_stats.max_hp
	
	# 冲突推挤逻辑
	var conflicting : Unit = null
	for other in UnitManager.unit_list:
		if not is_instance_valid(other): continue
		if other == u: continue
		if other.grid_cell == u.grid_cell and other.hit_points > 0:
			conflicting = other
			break

	if conflicting != null:
		var new_cell : Vector2i = UnitManager.find_nearest_empty_cell(u.grid_cell)
		if new_cell != Vector2i(-1, -1):
			u.grid_cell = new_cell
			if _battlefield != null and _battlefield.has_method("grid_to_world"):
				u.position = _battlefield.grid_to_world(new_cell)
		# 如果找不到空位，也不再强制 hit_points=0，避免直接“消失”

	u.can_act_this_turn = true
	u.has_moved = false
	u.has_attacked = false
	u.has_acted = false
	u.remaining_move = u.get_total_move_range()
	u.set_gray(false)
	
	if u is CollisionObject2D:
		(u as CollisionObject2D).set_collision_layer_value(1, true)


# ============================================================
#  回合结束钩子（触发下一波）
# ============================================================
# 替换此函数
func on_player_turn_end() -> void:
	# ★ 已废弃：由 TurnManager.check_victory() 实时触发，不再在这里做波次判断
	pass


# ★ 新增：立即激活下一波
func activate_next_wave_immediately():
	if _pending_groups.is_empty():
		return
	
	while not _pending_groups.is_empty():
		var next_group : Array = _pending_groups.pop_front()
		_current_wave += 1

		var activated : Array = []
		for u in next_group:
			if not is_instance_valid(u): continue
			_show_unit(u)
			activated.append(u)

		if activated.is_empty():
			print("[Wave] 第 %d 波触发动态增援（空组）" % _current_wave)
			var spawn_count : int = 3
			_spawn_reinforcements(spawn_count)
			
			var spawned_check = false
			for u in UnitManager.unit_list:
				if is_instance_valid(u) and u.unit_stats.team_id == 1 and u.visible and u.hit_points > 0:
					spawned_check = true
					break
					
			if spawned_check:
				_warning_shown = false
				_next_wave_delay = 0
				wave_advanced.emit(_current_wave, _type_total_waves)
				return
			else:
				continue # 增援失败，尝试继续激活下一组
				
		_warning_shown = false
		_next_wave_delay = 0
		wave_advanced.emit(_current_wave, _type_total_waves)

		if _map_data != null and _map_data.reinforcement_count > 0:
			_spawn_reinforcements(_map_data.reinforcement_count)
		return


func _activate_next_wave():
	while not _pending_groups.is_empty():
		var next_group : Array = _pending_groups.pop_front()
		_current_wave += 1

		var activated : Array = []
		for u in next_group:
			if not is_instance_valid(u): continue
			if u.hit_points <= 0: continue
			_show_unit(u)
			activated.append(u)

		if activated.is_empty():
			# ★ 核心：空组意味着这是由地图配置触发的“动态增援波”
			print("[Wave] 第 %d 波触发动态增援（空组）" % _current_wave)
			var spawn_count : int = 3 # 这里可以根据难度或天数配置
			_spawn_reinforcements(spawn_count)
			
			# 检查是否真的生成了
			var spawned_check = false
			for u in UnitManager.unit_list:
				if is_instance_valid(u) and u.unit_stats.team_id == 1 and u.visible and u.hit_points > 0:
					spawned_check = true
					break
					
			if spawned_check:
				_warning_shown = false
				_next_wave_delay = 0
				wave_advanced.emit(_current_wave, _type_total_waves)
				return
			else:
				continue # 增援失败（可能是没位置），继续下一组

		_warning_shown = false
		_next_wave_delay = 0
		wave_advanced.emit(_current_wave, _type_total_waves)

		if _map_data != null and _map_data.reinforcement_count > 0:
			_spawn_reinforcements(_map_data.reinforcement_count)
		return

	_warning_shown = false
	_next_wave_delay = 0


# ============================================================
#  增援生成（供空组和额外增援调用）
# ============================================================
func _spawn_reinforcements(count : int):
	if count <= 0: return
	if _battlefield == null or not is_instance_valid(_battlefield): return
	if not ("grid_to_world" in _battlefield): return

	var pool : Array = _map_data.reinforcement_pool.duplicate() if _map_data else []
	if pool.is_empty():
		for u in UnitManager.unit_list:
			if not is_instance_valid(u): continue
			if u.unit_stats.team_id != 1: continue
			var tn : String = u.unit_stats.unit_name
			if tn != "" and not (tn in pool):
				pool.append(tn)
	if pool.is_empty():
		pool.append("axeman")

	var spawn_cells : Array = _find_edge_spawn_cells(count)
	if spawn_cells.is_empty():
		return

	var unit_path : String = Config.PATHS.UNIT_SCENE
	if not ResourceLoader.exists(unit_path): return
	var unit_scene = load(unit_path)
	if unit_scene == null: return

	var node_type : int = _map_data.node_type if _map_data else MapNode.NodeType.NORMAL
	var hp_mult : float = UnitSpawner.get_enemy_hp_mult(node_type, false) * UnitSpawner.get_enemy_hp_extra()
	var day_mult : float = UnitSpawner.get_day_attr_mult(GameState.current_day)

	for i in range(mini(count, spawn_cells.size())):
		var cell : Vector2i = spawn_cells[i]
		var tname : String = pool.pick_random()
		var stats : UnitData = UnitDataManager.create_unit_data(tname)
		stats.team_id = 1
		stats.max_hp = int(stats.max_hp * hp_mult)
		stats.hit_points = stats.max_hp
		stats.strength = maxi(1, int(stats.strength * day_mult))
		stats.dexterity = maxi(1, int(stats.dexterity * day_mult))

		var unit = unit_scene.instantiate()
		unit.setup_unit(stats, cell)
		unit.set_meta("wave", _current_wave)
		_battlefield.add_child(unit)
		unit.position = _battlefield.grid_to_world(cell)
		UnitManager.register_unit(unit)


func _find_edge_spawn_cells(count : int) -> Array:
	var result : Array = []
	if not TerrainManager:
		return result
	var sz : Vector2i = TerrainManager.grid_size
	if sz.x <= 0 or sz.y <= 0:
		return result

	var candidates : Array = []
	for x in range(sz.x):
		for y in range(sz.y):
			var is_edge : bool = (x == 0 or x == sz.x - 1 or y == 0 or y == sz.y - 1)
			if not is_edge: continue
			var cell : Vector2i = Vector2i(x, y)
			if UnitManager.is_cell_occupied_including_hidden(cell): continue
			var terrain : int = TerrainManager.get_terrain(cell)
			if not TerrainManager.TERRAIN_DATA[terrain]["passable"]: continue
			if terrain == TerrainManager.TerrainType.IMPASSABLE_ALL: continue
			candidates.append(cell)

	if candidates.is_empty():
		return result
	candidates.shuffle()
	for i in range(mini(count, candidates.size())):
		result.append(candidates[i])
	return result
