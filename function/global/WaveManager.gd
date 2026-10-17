extends Node

# ============================================================
#  WaveManager — 波次与增援（v4.5）
#  敌人分批入场：第 1 波直接在场上，后续波次隐藏等激活
#  增援：每波激活时额外从地图边缘生成
# ============================================================

var _type_total_waves : int = 1
var _current_wave : int = 1
var _pending_groups : Array = []          # Array[Array[Unit]]
var _next_wave_delay : int = 0             # 剩余等待回合数
var _warning_shown : bool = false

var _map_data : MapData = null
var _battlefield : Node2D = null

signal wave_advanced(current_wave: int, total_waves: int)
signal wave_warning(current_wave: int, total_waves: int)


# ============================================================
#  初始化
# ============================================================
func setup_for_node(map_data : MapData, battlefield : Node2D = null) -> void:
	reset()
	_map_data = map_data
	_battlefield = battlefield
	if map_data == null:
		return
	if map_data.max_waves <= 1:
		return

	_type_total_waves = map_data.max_waves
	_current_wave = 1
	_pending_groups.clear()
	_next_wave_delay = 0
	_warning_shown = false

	# 延迟到所有单位注册完之后再分组
	call_deferred("_build_groups")


func reset() -> void:
	_type_total_waves = 1
	_current_wave = 1
	_pending_groups.clear()
	_next_wave_delay = 0
	_warning_shown = false
	_map_data = null
	_battlefield = null


# ============================================================
#  查询
# ============================================================
func get_current_wave() -> int:
	return _current_wave

func get_total_waves() -> int:
	return _type_total_waves

func has_pending_waves() -> bool:
	return not _pending_groups.is_empty()

func is_active() -> bool:
	return _type_total_waves > 1

func get_pending_count() -> int:
	var n : int = 0
	for g in _pending_groups:
		n += (g as Array).size()
	return n


# ============================================================
#  分组算法
# ============================================================
func _build_groups():
	if _type_total_waves <= 1:
		return

	# 收集场上敌人
	var enemies : Array = []
	for u in UnitManager.unit_list:
		if not is_instance_valid(u):
			continue
		if u.unit_stats.team_id != 1:
			continue
		if u.hit_points <= 0:
			continue
		enemies.append(u)

	if enemies.is_empty():
		return
	if enemies.size() <= _type_total_waves:
		# 敌人数量 <= 波次数 → 每波至少 1 个，但实际没意义
		# 直接不分组，按老逻辑
		_type_total_waves = 1
		return

	# 玩家中心
	var player_units : Array = []
	for u in UnitManager.unit_list:
		if not is_instance_valid(u):
			continue
		if u.unit_stats.team_id != 0:
			continue
		if u.hit_points <= 0:
			continue
		player_units.append(u)

	var player_center : Vector2 = Vector2.ZERO
	if not player_units.is_empty():
		for u in player_units:
			player_center += u.global_position
		player_center /= float(player_units.size())
	else:
		player_center = Vector2.ZERO

	# 按距离玩家从近到远排序
	enemies.sort_custom(func(a, b):
		return a.global_position.distance_to(player_center) < b.global_position.distance_to(player_center)
	)

	# 按 N 等分
	var n : int = _type_total_waves
	var total : int = enemies.size()
	var groups : Array = []
	for i in range(n):
		var from_idx : int = int(float(i) * float(total) / float(n))
		var to_idx : int = int(float(i + 1) * float(total) / float(n))
		if to_idx <= from_idx:
			to_idx = from_idx + 1
		var g : Array = []
		for j in range(from_idx, mini(to_idx, total)):
			g.append(enemies[j])
		groups.append(g)

	# 把 boss 挪到最后一组
	var boss_unit : Unit = null
	for g in groups:
		for u in g:
			if u.unit_stats.is_boss:
				boss_unit = u
				break
		if boss_unit != null:
			break

	if boss_unit != null:
		var boss_group_idx : int = -1
		var boss_pos_in_group : int = -1
		for gi in range(groups.size()):
			var g : Array = groups[gi]
			for ui in range(g.size()):
				if g[ui] == boss_unit:
					boss_group_idx = gi
					boss_pos_in_group = ui
					break
			if boss_group_idx >= 0:
				break

		if boss_group_idx >= 0 and boss_group_idx != n - 1:
			# 从原组移除 boss
			(groups[boss_group_idx] as Array).remove_at(boss_pos_in_group)
			# 从最后一组拿一个非 boss 来补位
			var last_group : Array = groups[n - 1]
			var swap_unit : Unit = null
			for u in last_group:
				if not u.unit_stats.is_boss:
					swap_unit = u
					break
			if swap_unit != null:
				last_group.erase(swap_unit)
				(groups[boss_group_idx] as Array).append(swap_unit)
			# boss 放最后一组
			last_group.append(boss_unit)

	# 第 1 组直接在场，第 2..N 组隐藏
	for gi in range(1, groups.size()):
		var g : Array = groups[gi]
		for u in g:
			if not is_instance_valid(u):
				continue
			u.visible = false
			u.process_mode = Node.PROCESS_MODE_DISABLED
			u.can_act_this_turn = false
			u.remaining_move = 0
			u.hit_points = u.unit_stats.max_hp
			# 不让这些单位参与碰撞/查找
			if u is CollisionObject2D:
				(u as CollisionObject2D).set_collision_layer_value(1, false)
		_pending_groups.append(g)

	_current_wave = 1
	_next_wave_delay = 0
	_warning_shown = false

	print("[Wave] 初始化 %d 波，共 %d 敌人。当前波 %d / %d" % [
		_type_total_waves, enemies.size(), _current_wave, _type_total_waves])
	wave_advanced.emit(_current_wave, _type_total_waves)


# ============================================================
#  玩家回合结束钩子（由 TurnManager 调用）
# ============================================================
func on_player_turn_end() -> void:
	if not is_active():
		return
	if _pending_groups.is_empty():
		return

	var alive_enemies : int = 0
	for u in UnitManager.unit_list:
		if not is_instance_valid(u):
			continue
		if u.unit_stats.team_id != 1:
			continue
		if u.hit_points <= 0:
			continue
		if u.visible == false:
			continue
		alive_enemies += 1

	if alive_enemies > 0:
		return

	if not _warning_shown:
		_warning_shown = true
		_next_wave_delay = 1
		print("[Wave] 第 %d 波清空，警告即将增援" % _current_wave)
		wave_warning.emit(_current_wave + 1, _type_total_waves)
		return

	if _next_wave_delay > 0:
		_next_wave_delay -= 1
		if _next_wave_delay > 0:
			return
		_activate_next_wave()


func _activate_next_wave():
	if _pending_groups.is_empty():
		return
	var next_group : Array = _pending_groups.pop_front()
	for u in next_group:
		if not is_instance_valid(u):
			continue
		u.visible = true
		u.process_mode = Node.PROCESS_MODE_INHERIT
		u.hit_points = u.unit_stats.max_hp
		u.can_act_this_turn = true
		u.has_moved = false
		u.has_attacked = false
		u.has_acted = false
		u.remaining_move = u.get_total_move_range()
		u.set_gray(false)
		if u is CollisionObject2D:
			(u as CollisionObject2D).set_collision_layer_value(1, true)

	_current_wave += 1
	_warning_shown = false
	_next_wave_delay = 0
	print("[Wave] 第 %d / %d 波入场（%d 个敌人）" % [
		_current_wave, _type_total_waves, next_group.size()])
	wave_advanced.emit(_current_wave, _type_total_waves)

	# 增援
	if _map_data != null and _map_data.reinforcement_count > 0:
		_spawn_reinforcements(_map_data.reinforcement_count)


# ============================================================
#  增援生成
# ============================================================
func _spawn_reinforcements(count : int):
	if count <= 0:
		return
	if _battlefield == null or not is_instance_valid(_battlefield):
		return
	if not ("grid_to_world" in _battlefield):
		return

	var pool : Array = _map_data.reinforcement_pool.duplicate() if _map_data else []
	if pool.is_empty():
		for u in UnitManager.unit_list:
			if not is_instance_valid(u):
				continue
			if u.unit_stats.team_id != 1:
				continue
			var tn : String = u.unit_stats.unit_name
			if tn != "" and not (tn in pool):
				pool.append(tn)
	if pool.is_empty():
		pool.append("axeman")

	var spawn_cells : Array = _find_edge_spawn_cells(count)
	if spawn_cells.is_empty():
		return

	var unit_path : String = Config.PATHS.UNIT_SCENE
	if not ResourceLoader.exists(unit_path):
		return
	var unit_scene = load(unit_path)
	if unit_scene == null:
		return

	# ★ v4.5：增援也吃高收益节点的负面 HP 倍率
	var extra_hp : float = 1.0
	if _map_data != null:
		extra_hp = maxf(1.0, _map_data.enemy_hp_multiplier)

	for i in range(mini(count, spawn_cells.size())):
		var cell : Vector2i = spawn_cells[i]
		var tname : String = pool[randi() % pool.size()]
		var stats : UnitData = UnitDataManager.create_unit_data(tname)
		stats.team_id = 1
		if _map_data and _map_data.node_type == MapNode.NodeType.BOSS:
			stats.max_hp = int(stats.max_hp * 2.0 * extra_hp)
		elif _map_data and _map_data.node_type == MapNode.NodeType.ELITE:
			stats.max_hp = int(stats.max_hp * 1.5 * extra_hp)
		else:
			stats.max_hp = int(stats.max_hp * extra_hp)
		stats.hit_points = stats.max_hp

		var unit = unit_scene.instantiate()
		unit.setup_unit(stats, cell)
		_battlefield.add_child(unit)
		unit.position = _battlefield.grid_to_world(cell)
		UnitManager.register_unit(unit)
		print("[Wave] 增援 %s → %s" % [tname, str(cell)])


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
			if not is_edge:
				continue
			var cell : Vector2i = Vector2i(x, y)
			if UnitManager.is_cell_occupied(cell):
				continue
			var terrain : int = TerrainManager.get_terrain(cell)
			if not TerrainManager.TERRAIN_DATA[terrain]["passable"]:
				continue
			if terrain == TerrainManager.TerrainType.IMPASSABLE_ALL:
				continue
			candidates.append(cell)

	if candidates.is_empty():
		return result
	candidates.shuffle()
	for i in range(mini(count, candidates.size())):
		result.append(candidates[i])
	return result
