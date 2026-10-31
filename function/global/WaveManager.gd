extends Node

# ============================================================
#  WaveManager — 波次与增援（保底修复版）
#
#  保底原则：
#    1. 显式 wave 模式下，第 1 组不再被错误隐藏
#    2. 有效组 ≤ 1 时直接降级为单波（is_active() = false）
#    3. _activate_next_wave 跳过空组，不会出场空阵容
#    4. 所有组清空但仍未胜利时，由 TurnManager.check_victory 兜底
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

	_type_total_waves = maxi(1, map_data.max_waves)
	_current_wave = 1
	_pending_groups.clear()
	_next_wave_delay = 0
	_warning_shown = false

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
	var enemies : Array = []
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.unit_stats.team_id != 1: continue
		if u.hit_points <= 0: continue
		enemies.append(u)

	if enemies.is_empty():
		return

	# 检测显式 wave
	var explicit_map : Dictionary = {}
	var has_explicit : bool = false
	for u in enemies:
		var w : int = int(u.get_meta("wave", 0))
		if w > 1:
			has_explicit = true
			if not explicit_map.has(w):
				explicit_map[w] = []
			explicit_map[w].append(u)

	# ★ 有 wave=1 的也要进 explicit_map，避免第 1 波被遗漏
	if has_explicit:
		var w1_units : Array = []
		for u in enemies:
			var w : int = int(u.get_meta("wave", 0))
			if w == 1:
				w1_units.append(u)
		if not w1_units.is_empty() and not explicit_map.has(1):
			explicit_map[1] = w1_units
		_build_groups_by_explicit_wave(explicit_map)
		return

	# ---- 隐式：按距离分 N 组 ----
	if _type_total_waves <= 1:
		return
	if enemies.size() <= _type_total_waves:
		_type_total_waves = 1
		return

	var player_units : Array = []
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.unit_stats.team_id != 0: continue
		if u.hit_points <= 0: continue
		player_units.append(u)

	var player_center : Vector2 = Vector2.ZERO
	if not player_units.is_empty():
		for u in player_units:
			player_center += u.global_position
		player_center /= float(player_units.size())

	enemies.sort_custom(func(a, b):
		return a.global_position.distance_to(player_center) < b.global_position.distance_to(player_center)
	)

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

	# Boss 挪到最后一组
	var boss_unit : Unit = null
	for g in groups:
		for u in g:
			if u.unit_stats.is_boss:
				boss_unit = u
				break
		if boss_unit != null: break

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
			if boss_group_idx >= 0: break

		if boss_group_idx >= 0 and boss_group_idx != n - 1:
			(groups[boss_group_idx] as Array).remove_at(boss_pos_in_group)
			var last_group : Array = groups[n - 1]
			var swap_unit : Unit = null
			for u in last_group:
				if not u.unit_stats.is_boss:
					swap_unit = u
					break
			if swap_unit != null:
				last_group.erase(swap_unit)
				(groups[boss_group_idx] as Array).append(swap_unit)
			last_group.append(boss_unit)

	for gi in range(1, groups.size()):
		var g : Array = groups[gi]
		for u in g:
			if not is_instance_valid(u): continue
			_hide_unit(u)
		_pending_groups.append(g)

	_current_wave = 1
	_next_wave_delay = 0
	_warning_shown = false

	print("[Wave] 初始化 %d 波，共 %d 敌人" % [_type_total_waves, enemies.size()])
	wave_advanced.emit(_current_wave, _type_total_waves)


# ★ 显式波次分组（保底修复）
func _build_groups_by_explicit_wave(wave_map: Dictionary):
	var sorted_waves : Array = wave_map.keys()
	sorted_waves.sort()

	# 只保留非空组
	var groups : Array = []
	for w in sorted_waves:
		var g : Array = wave_map[w]
		if not g.is_empty():
			groups.append(g)

	_current_wave = 1
	_pending_groups.clear()
	_next_wave_delay = 0
	_warning_shown = false

	# ★ 保底：只有 0 组或 1 组 → 视为单波
	if groups.size() <= 1:
		_type_total_waves = 1
		print("[Wave] 显式波次（仅 %d 组有效），降级为单波" % groups.size())
		wave_advanced.emit(1, 1)
		return

	# ★ 第 1 组保持原状（可见、可行动），第 2 组起隐藏
	for gi in range(1, groups.size()):
		var g : Array = groups[gi]
		for u in g:
			if not is_instance_valid(u): continue
			_hide_unit(u)
		_pending_groups.append(g)

	_type_total_waves = groups.size()
	print("[Wave] 显式波次：%d 波 / %d 组（第1组已入场）" % [_type_total_waves, _pending_groups.size()])
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


# ============================================================
#  玩家回合结束钩子
# ============================================================
func on_player_turn_end() -> void:
	if not is_active():
		return
	if _pending_groups.is_empty():
		return

	var alive_enemies : int = 0
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.unit_stats.team_id != 1: continue
		if u.hit_points <= 0: continue
		if u.visible == false: continue
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


# ★ 保底：跳过空组，若全部为空则静默退出
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
			# 空组：跳过，_current_wave 已递增，继续下一组
			print("[Wave] 第 %d 波为空，跳过" % _current_wave)
			continue

		_warning_shown = false
		_next_wave_delay = 0
		print("[Wave] 第 %d / %d 波入场（%d 个敌人）" % [
			_current_wave, _type_total_waves, activated.size()])
		wave_advanced.emit(_current_wave, _type_total_waves)

		if _map_data != null and _map_data.reinforcement_count > 0:
			_spawn_reinforcements(_map_data.reinforcement_count)
		return

	# 所有组清空
	_warning_shown = false
	_next_wave_delay = 0
	print("[Wave] 无更多可用波次")


# ============================================================
#  增援生成（走 UnitSpawner 倍率函数）
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

	# ★ 统一走 UnitSpawner 的倍率函数
	var node_type : int = _map_data.node_type if _map_data else MapNode.NodeType.NORMAL
	var hp_mult : float = UnitSpawner.get_enemy_hp_mult(node_type, false) * UnitSpawner.get_enemy_hp_extra()
	var day_mult : float = UnitSpawner.get_day_attr_mult(GameState.current_day)

	for i in range(mini(count, spawn_cells.size())):
		var cell : Vector2i = spawn_cells[i]
		var tname : String = pool[randi() % pool.size()]
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
			if not is_edge: continue
			var cell : Vector2i = Vector2i(x, y)
			if UnitManager.is_cell_occupied(cell): continue
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
