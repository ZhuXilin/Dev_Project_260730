extends Node

signal unit_removed(unit, team)

var unit_list : Array[Unit] = []

func register_unit(unit: Unit):
	if unit not in unit_list:
		unit_list.append(unit)
		print("单位注册：", unit.unit_stats.unit_name, " 位置：", unit.grid_cell)

func unregister_unit(unit: Unit):
	if unit in unit_list:
		var team = unit.unit_stats.team_id
		unit_list.erase(unit)
		unit_removed.emit(unit, team)
		if InputManager.selected_unit == unit:
			InputManager.selected_unit = null
			InputManager.interaction_phase = InputManager.Phase.IDLE
			InputManager.current_highlight_cells = {}
			SignalBus.request_clear_highlight.emit()
		TurnManager.check_all_acted()

func get_unit_at_cell(cell: Vector2i) -> Unit:
	for unit in unit_list:
		# ★ 必须加上这句！跳过已经被 free 的单位
		if not is_instance_valid(unit): continue
		if unit.grid_cell == cell and unit.hit_points > 0 and unit.visible:
			return unit
	return null

func is_cell_occupied(cell: Vector2i) -> bool:
	return get_unit_at_cell(cell) != null

func get_reachable_cells(start_cell: Vector2i, max_move: int, unit: Unit) -> Dictionary:
	var result = {}
	var queue = []
	var cost_so_far = {}
	queue.append(start_cell)
	cost_so_far[start_cell] = 0
	result[start_cell] = true

	var team_id = unit.unit_stats.team_id
	var ignore_cost = unit.unit_stats.ignore_terrain_cost

	while queue.size() > 0:
		var cell = queue.pop_front()
		var current_cost = cost_so_far[cell]

		var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		for d in dirs:
			var neighbor = cell + d
			if neighbor.x < 0 or neighbor.x >= TerrainManager.grid_size.x or neighbor.y < 0 or neighbor.y >= TerrainManager.grid_size.y:
				continue

			var terrain_type = TerrainManager.get_terrain(neighbor)
			# ---- 完全阻挡地形（连飞马也不可通过） ----
			if terrain_type == TerrainManager.TerrainType.IMPASSABLE_ALL:
				continue
			# ---- 无视地形通行（飞马可进入所有格子） ----
			if not ignore_cost:
				if not TerrainManager.TERRAIN_DATA[terrain_type]["passable"]:
					continue
			# 否则，任何地形均可进入（包括 IMPASSABLE）

			var move_cost = 1 if ignore_cost else TerrainManager.TERRAIN_DATA[terrain_type]["move_cost"]
			var updated_cost = current_cost + move_cost
			if updated_cost > max_move:
				continue

			var occupant = get_unit_at_cell(neighbor)
			if occupant:
				if occupant.unit_stats.team_id != team_id:
					continue
				if not cost_so_far.has(neighbor) or updated_cost < cost_so_far[neighbor]:
					cost_so_far[neighbor] = updated_cost
					queue.append(neighbor)
				continue

			if not cost_so_far.has(neighbor) or updated_cost < cost_so_far[neighbor]:
				cost_so_far[neighbor] = updated_cost
				queue.append(neighbor)
				result[neighbor] = true

	return result

func calculate_path(start_cell: Vector2i, goal_cell: Vector2i, unit: Unit) -> Array:
	if is_cell_occupied(goal_cell):
		return []

	var team_id = unit.unit_stats.team_id
	var ignore_cost = unit.unit_stats.ignore_terrain_cost

	# Dijkstra：cost_so_far 记录起点到每格的最小代价
	var open_list : Array = [start_cell]
	var cost_so_far : Dictionary = { start_cell: 0 }
	var parent : Dictionary = {}

	while open_list.size() > 0:
		# 取当前最小代价节点（地图小，线性扫描可接受）
		var min_idx : int = 0
		var min_cost : int = cost_so_far[open_list[0]]
		for i in range(1, open_list.size()):
			var c : int = cost_so_far[open_list[i]]
			if c < min_cost:
				min_cost = c
				min_idx = i
		var cell : Vector2i = open_list[min_idx]
		open_list.remove_at(min_idx)

		if cell == goal_cell:
			break

		var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		for d in dirs:
			var neighbor = cell + d
			if neighbor.x < 0 or neighbor.x >= TerrainManager.grid_size.x \
					or neighbor.y < 0 or neighbor.y >= TerrainManager.grid_size.y:
				continue
			var terrain_type = TerrainManager.get_terrain(neighbor)
			if terrain_type == TerrainManager.TerrainType.IMPASSABLE_ALL:
				continue
			if not ignore_cost:
				if not TerrainManager.TERRAIN_DATA[terrain_type]["passable"]:
					continue

			var occupant = get_unit_at_cell(neighbor)
			if occupant and occupant.unit_stats.team_id != team_id:
				continue

			var step_cost : int = 1 if ignore_cost else TerrainManager.TERRAIN_DATA[terrain_type]["move_cost"]
			var new_cost : int = cost_so_far[cell] + step_cost
			if not cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:
				cost_so_far[neighbor] = new_cost
				parent[neighbor] = cell
				if not (neighbor in open_list):
					open_list.append(neighbor)

	if not parent.has(goal_cell):
		return []

	var path = []
	var current_cell = goal_cell
	while current_cell in parent:
		path.append(current_cell)
		current_cell = parent[current_cell]
	path.reverse()
	return path

func clear_all_units():
	for unit in unit_list:
		if is_instance_valid(unit):
			unit.queue_free()
	unit_list.clear()
	print("所有单位已清除，剩余单位数：", unit_list.size())

## 判断 occupant 是否是 attacker 的有效攻击/治疗目标
## 仅看敌我关系，不看射程。治疗者目标是友军，攻击者目标是敌军
func is_attack_target_of(attacker : Unit, occupant : Unit) -> bool:
	if attacker == null or occupant == null:
		return false
	if attacker == occupant:
		return false
	var is_healer = (attacker.get_weapon_type() == "staff")
	var same_team = (occupant.unit_stats.team_id == attacker.unit_stats.team_id)
	if is_healer:
		return same_team
	else:
		return not same_team


# ============================================================
#  ★ v4.7 新增：波次 / 出生点冲突检测（含隐藏单位）
# ============================================================

## 不管 visible，只要 hit_points > 0 且在该格就算占用。
## 用于波次出场 / 玩家出生前检测"隐藏的波次敌人占坑"。
func get_unit_at_cell_including_hidden(cell: Vector2i) -> Unit:
	for unit in unit_list:
		if not is_instance_valid(unit): continue
		if unit.grid_cell == cell and unit.hit_points > 0:
			return unit
	return null


func is_cell_occupied_including_hidden(cell: Vector2i) -> bool:
	return get_unit_at_cell_including_hidden(cell) != null


## 从 start_cell 出发做 BFS，返回最近的"没有单位（含隐藏）+ 地形可通行"格。
## avoid_cells 里列出的格子也视为不可用（用于玩家出生时批量避开已分配格）。
## 找不到返回 Vector2i(-1, -1)。
func find_nearest_empty_cell(start_cell: Vector2i, max_radius: int = 8,
		avoid_cells: Dictionary = {}) -> Vector2i:
	# 起点本身可用就直接返回
	if _is_cell_passable(start_cell) \
			and not avoid_cells.has(start_cell) \
			and not is_cell_occupied_including_hidden(start_cell):
		return start_cell

	var visited : Dictionary = { start_cell: true }
	var queue : Array = [start_cell]
	var dirs : Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while not queue.is_empty():
		var cur : Vector2i = queue.pop_front()
		for d in dirs:
			var n : Vector2i = cur + d
			if visited.has(n): continue
			visited[n] = true

			if n.x < 0 or n.x >= TerrainManager.grid_size.x \
					or n.y < 0 or n.y >= TerrainManager.grid_size.y:
				continue
			if abs(n.x - start_cell.x) + abs(n.y - start_cell.y) > max_radius:
				continue
			if not _is_cell_passable(n):
				continue
			if avoid_cells.has(n):
				continue
			if is_cell_occupied_including_hidden(n):
				continue

			return n

	return Vector2i(-1, -1)


func _is_cell_passable(cell: Vector2i) -> bool:
	var t : int = TerrainManager.get_terrain(cell)
	if t == TerrainManager.TerrainType.IMPASSABLE_ALL:
		return false
	var td : Dictionary = TerrainManager.TERRAIN_DATA.get(t, {})
	return bool(td.get("passable", true))
