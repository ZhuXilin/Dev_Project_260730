extends Node
class_name EnemyAI

signal ai_queue_finished

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

var ai_queue : Array = []
var _processing : bool = false
var _turn_manager : TurnManager = null
var first_ai_unit : Unit = null

func initialize(turn_manager: TurnManager):
	_turn_manager = turn_manager
	if _turn_manager:
		_turn_manager.move_completed.connect(_on_move_completed)

func run_enemy_ai():
	if _turn_manager == null:
		return
	if _turn_manager.is_game_over or _turn_manager.is_moving:
		return
	if _processing:
		return
	_processing = true

	var enemies = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 1 and unit.hit_points > 0:
			enemies.append(unit)

	first_ai_unit = enemies[0] if enemies.size() > 0 else null

	ai_queue.clear()

	# ---- 新增：检查是否有任何敌人能产生非待机动作 ----
	var can_act = false
	for enemy in enemies:
		var action = _decide_action(enemy)
		if action and action["type"] != "wait":
			can_act = true
			break

	if not can_act:
		print("所有敌方单位无法行动，强制结束 AI")
		_processing = false
		ai_queue_finished.emit()   # 发射信号，而不是调用 _on_ai_queue_finished
		return

	# 原有填充队列逻辑
	for enemy in enemies:
		var action = _decide_action(enemy)
		if action:
			ai_queue.append(action)

	_process_ai_queue()

# ============================================================
#  决策统一入口
# ============================================================
func _decide_action(unit: Unit):
	var hp_ratio = float(unit.hit_points) / unit.unit_stats.max_hp

	# 1. 治疗者优先治疗队友
	if unit.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL:
		var heal_action = _decide_healer_action(unit)
		if heal_action:
			return heal_action

	# 2. 低血量优先生存（回血点/治疗者）
	if hp_ratio < 0.4:
		var survival_move = _evaluate_survival_move(unit)
		if survival_move:
			return survival_move

	# 3. 攻击评估
	var attack_action = _evaluate_attack(unit)
	if attack_action:
		return attack_action

	# 4. 自身回复道具（血量<20%）
	var self_heal_action = _evaluate_item_use(unit)
	if self_heal_action:
		return self_heal_action

	# 5. 普通移动（有利地形）
	var move_action = _evaluate_move(unit)
	if move_action:
		return move_action

	return {"type": "wait", "unit": unit}

# ============================================================
#  治疗者决策（法杖治疗）
# ============================================================
func _decide_healer_action(unit: Unit):
	var weapon_stats = unit.get_weapon_stats()
	var heal_range = weapon_stats["attack_range"]
	var min_heal_range = weapon_stats["min_attack_range"]

	var best_ally = null
	var max_hp_loss = 0
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id == 1 and ally.hit_points > 0 and ally != unit:
			var dist = abs(unit.grid_cell.x - ally.grid_cell.x) + abs(unit.grid_cell.y - ally.grid_cell.y)
			if dist >= min_heal_range and dist <= heal_range:
				var hp_loss = ally.unit_stats.max_hp - ally.hit_points
				if hp_loss > max_hp_loss:
					max_hp_loss = hp_loss
					best_ally = ally

	if best_ally:
		return {"type": "attack", "unit": unit, "target": best_ally}

	var wounded_ally = null
	max_hp_loss = 0
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id == 1 and ally.hit_points > 0 and ally != unit:
			var loss = ally.unit_stats.max_hp - ally.hit_points
			if loss > max_hp_loss:
				max_hp_loss = loss
				wounded_ally = ally

	if wounded_ally:
		var path_to_heal = _find_best_move_to_target(unit, wounded_ally.grid_cell, min_heal_range, heal_range)
		if path_to_heal.size() > 0:
			return {"type": "move", "unit": unit, "path": path_to_heal}

	var greedy_path = _greedy_move_towards(unit, wounded_ally.grid_cell) if wounded_ally else []
	if greedy_path.size() > 0:
		return {"type": "move", "unit": unit, "path": greedy_path}

	return null

# ============================================================
#  攻击评估（含武器智能选择）
# ============================================================
func _evaluate_attack(unit: Unit):
	var is_healer = (unit.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL)
	if is_healer:
		return null

	var weapon_ids = unit.get_weapon_ids()
	if weapon_ids.is_empty():
		return null

	var best_target = null
	var best_weapon_id = ""
	var best_score = -999
	var best_damage = 0

	for enemy in UnitManager.unit_list:
		if enemy.unit_stats.team_id == unit.unit_stats.team_id or enemy.hit_points <= 0:
			continue

		for w_id in weapon_ids:
			var data = ItemManager.get_item_data(w_id)
			if not data or data.type != "weapon":
				continue

			var max_range = data.weapon_attack_range
			var min_range = data.weapon_min_attack_range
			var dist = abs(unit.grid_cell.x - enemy.grid_cell.x) + abs(unit.grid_cell.y - enemy.grid_cell.y)
			if dist < min_range or dist > max_range:
				continue

			# 临时切换武器（保存当前装备实例）
			var old_inst = unit.equipped_weapon_instance
			var weapon_inst = unit.find_first_instance(w_id)
			if weapon_inst:
				unit.equip_weapon(weapon_inst)

			var hit_rate = CombatManager.calculate_hit_rate(unit, enemy)
			var damage = CombatManager.calculate_damage(unit, enemy)
			var is_effective = _is_effective_against(unit, enemy)

			var can_counter = false
			var enemy_weapon_type = enemy.get_weapon_type()
			if enemy_weapon_type != -1 and enemy_weapon_type != UnitDataManagerClass.WEAPON_HEAL:
				var enemy_stats = enemy.get_weapon_stats()
				var enemy_min = enemy_stats["min_attack_range"]
				var enemy_max = enemy_stats["attack_range"]
				var dist_to_attacker = abs(enemy.grid_cell.x - unit.grid_cell.x) + abs(enemy.grid_cell.y - unit.grid_cell.y)
				if dist_to_attacker >= enemy_min and dist_to_attacker <= enemy_max:
					can_counter = true

			# 恢复原装备
			if old_inst:
				unit.equip_weapon_instance(old_inst)
			else:
				unit.equipped_weapon_instance = null

			if damage <= 0:
				continue

			# 评分
			var score = damage * 2
			if damage >= enemy.hit_points:
				score += 50
			if not can_counter:
				score += 30
			if hit_rate > 70:
				score += 10
			if is_effective:
				score += 20

			if can_counter and unit.hit_points < unit.unit_stats.max_hp * 0.3:
				var counter_dmg = CombatManager.calculate_damage(enemy, unit)
				if counter_dmg >= unit.hit_points:
					score -= 100

			if score > best_score:
				best_score = score
				best_target = enemy
				best_weapon_id = w_id
				best_damage = damage

	if best_target and best_weapon_id != "":
		if best_damage == 0:
			return null
		return {"type": "attack", "unit": unit, "target": best_target, "weapon_id": best_weapon_id}
	return null

# ---- 特效克制（使用 UnitClass 判断） ----
func _is_effective_against(attacker: Unit, defender: Unit) -> bool:
	var aw = attacker.get_weapon_type()
	var defender_class = UnitDataManagerClass.get_unit_class(defender.unit_stats.unit_name)
	# 弓克飞马
	if aw == UnitDataManagerClass.WEAPON_BOW and defender_class == UnitDataManagerClass.UnitClass.PEGASUS:
		return true
	# 三环相克（剑克斧，斧克枪，枪克剑）这里略，已在伤害计算中处理，此处不重复
	return false

# ============================================================
#  道具使用评估（自身回复）
# ============================================================
func _evaluate_item_use(unit: Unit):
	var heal_items = []
	for inst in unit.inventory:
		var item_id = inst.item_id
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "heal" and data.use_effect.get("type") == "heal":
			heal_items.append(item_id)

	if heal_items.is_empty():
		return null

	var hp_ratio = float(unit.hit_points) / unit.unit_stats.max_hp
	if hp_ratio < 0.2:
		var best_item = heal_items[0]
		var best_heal = 0
		for item_id in heal_items:
			var data = ItemManager.get_item_data(item_id)
			var heal_amt = data.use_effect.get("value", 0)
			if heal_amt > best_heal:
				best_heal = heal_amt
				best_item = item_id
		return {"type": "use_item", "unit": unit, "item_id": best_item, "target": unit}
	return null

# ---- 用道具治疗队友 ----
func _evaluate_heal_item_for_ally(unit: Unit):
	if float(unit.hit_points) / unit.unit_stats.max_hp < 0.3:
		return null

	var heal_items = []
	for inst in unit.inventory:
		var item_id = inst.item_id
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "heal" and data.use_effect.get("type") == "heal":
			heal_items.append(item_id)

	if heal_items.is_empty():
		return null

	var best_ally = null
	var lowest_hp_ratio = 1.0
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id == unit.unit_stats.team_id and ally != unit and ally.hit_points > 0:
			var hp_ratio = float(ally.hit_points) / ally.unit_stats.max_hp
			if hp_ratio < 0.5 and hp_ratio < lowest_hp_ratio:
				var use_effect = ItemManager.get_item_data(heal_items[0]).use_effect
				var min_range = use_effect.get("min_range", 0)
				var max_range = use_effect.get("max_range", 1)
				var dist = abs(unit.grid_cell.x - ally.grid_cell.x) + abs(unit.grid_cell.y - ally.grid_cell.y)
				if dist >= min_range and dist <= max_range:
					lowest_hp_ratio = hp_ratio
					best_ally = ally

	if best_ally:
		var best_item = heal_items[0]
		var best_heal = 0
		for item_id in heal_items:
			var data = ItemManager.get_item_data(item_id)
			var heal_amt = data.use_effect.get("value", 0)
			if heal_amt > best_heal:
				best_heal = heal_amt
				best_item = item_id
		return {"type": "use_item", "unit": unit, "item_id": best_item, "target": best_ally}
	return null

# ============================================================
#  移动评估（含回血点检测，基于事件系统）
# ============================================================
func _evaluate_move(unit: Unit):
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.unit_stats.move_range, unit)
	if reachable.is_empty():
		return null

	var hp_ratio = float(unit.hit_points) / unit.unit_stats.max_hp

	# 1. 始终优先寻找未触发的回血点（通过事件系统检测 heal 动作）
	if _turn_manager != null:
		var heal_cells = []
		for cell in reachable.keys():
			if cell == unit.grid_cell:
				continue
			if _turn_manager.map_functions.has(cell):
				var cfg = _turn_manager.map_functions[cell]
				if cfg.has("event_id"):
					var event_id = cfg["event_id"]
					if EventManager.is_event_completed(event_id):
						continue
					var event_def = EventManager.get_event(event_id)
					if event_def.is_empty():
						continue
					var actions = event_def.get("actions", [])
					for action in actions:
						if action.get("type") == "heal" and action.get("amount", 0) > 0:
							heal_cells.append(cell)
							break

		if heal_cells.size() > 0:
			heal_cells.sort_custom(func(a, b):
				var da = abs(a.x - unit.grid_cell.x) + abs(a.y - unit.grid_cell.y)
				var db = abs(b.x - unit.grid_cell.x) + abs(b.y - unit.grid_cell.y)
				return da < db
			)
			var target_cell = heal_cells[0]
			var path = UnitManager.calculate_path(unit.grid_cell, target_cell, unit)
			if path.size() > 0:
				return {"type": "move", "unit": unit, "path": path}

	# 2. 血量低于40%且无回血点，尝试撤退到治疗者或安全地形
	var best_cell = unit.grid_cell
	var best_score = -999

	if hp_ratio < 0.4:
		# 2a. 尝试移动到己方治疗者附近（持有治疗法杖）
		var healers = []
		for ally in UnitManager.unit_list:
			if ally.unit_stats.team_id == unit.unit_stats.team_id and ally != unit and ally.hit_points > 0:
				if ally.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL:
					healers.append(ally)
		if healers.size() > 0:
			var nearest_healer = healers[0]
			var min_dist = 999
			for h in healers:
				var d = abs(h.grid_cell.x - unit.grid_cell.x) + abs(h.grid_cell.y - unit.grid_cell.y)
				if d < min_dist:
					min_dist = d
					nearest_healer = h
			var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
			var target_cell = unit.grid_cell
			for d in dirs:
				var neighbor = nearest_healer.grid_cell + d
				if neighbor.x < 0 or neighbor.x >= TerrainManager.grid_size.x or neighbor.y < 0 or neighbor.y >= TerrainManager.grid_size.y:
					continue
				if not UnitManager.is_cell_occupied(neighbor) and reachable.has(neighbor):
					target_cell = neighbor
					break
			if target_cell != unit.grid_cell:
				var path = UnitManager.calculate_path(unit.grid_cell, target_cell, unit)
				if path.size() > 0:
					return {"type": "move", "unit": unit, "path": path}
			else:
				# 如果无法到达相邻格，尝试移动到治疗者附近任意可达格
				best_cell = unit.grid_cell
				var best_dist = 999
				for cell in reachable.keys():
					var d = abs(cell.x - nearest_healer.grid_cell.x) + abs(cell.y - nearest_healer.grid_cell.y)
					if d < best_dist and not UnitManager.is_cell_occupied(cell):
						best_dist = d
						best_cell = cell
				if best_cell != unit.grid_cell:
					var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
					if path.size() > 0:
						return {"type": "move", "unit": unit, "path": path}

		# 2b. 没有治疗者，寻找高防御/回避的地形作为撤退点
		best_cell = unit.grid_cell
		best_score = -999
		for cell in reachable.keys():
			var terrain = TerrainManager.get_terrain(cell)
			var def_bonus = TerrainManager.TERRAIN_DATA[terrain]["def_bonus"]
			var avoid_bonus = TerrainManager.TERRAIN_DATA[terrain]["avoid_bonus"]
			var score = def_bonus * 2 + avoid_bonus
			# 远离敌人（越远越好）
			var dist_to_enemy = 999
			for p in UnitManager.unit_list:
				if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
					var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
					if d < dist_to_enemy:
						dist_to_enemy = d
			score += dist_to_enemy * 2
			# 避免孤立无援（周围有己方单位加分）
			var ally_near = false
			for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var neighbor = cell + dir
				var neighbor_unit = UnitManager.get_unit_at_cell(neighbor)
				if neighbor_unit and neighbor_unit.unit_stats.team_id == unit.unit_stats.team_id:
					ally_near = true
					break
			if ally_near:
				score += 5

			if score > best_score:
				best_score = score
				best_cell = cell

		if best_cell != unit.grid_cell:
			var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
			if path.size() > 0:
				return {"type": "move", "unit": unit, "path": path}

		return null   # 无路可走，原地待机

	# 3. 正常情况（血量≥40%）：选择有利地形（兼顾防御和队友）
	best_cell = unit.grid_cell
	best_score = -999
	for cell in reachable.keys():
		var terrain = TerrainManager.get_terrain(cell)
		var def_bonus = TerrainManager.TERRAIN_DATA[terrain]["def_bonus"]
		var avoid_bonus = TerrainManager.TERRAIN_DATA[terrain]["avoid_bonus"]
		var score = def_bonus * 2 + avoid_bonus
		# 友军邻近加分
		var ally_near = false
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor = cell + dir
			var neighbor_unit = UnitManager.get_unit_at_cell(neighbor)
			if neighbor_unit and neighbor_unit.unit_stats.team_id == unit.unit_stats.team_id:
				ally_near = true
				break
		if ally_near:
			score += 5
		# 远离玩家（越远越好）
		var dist_to_player = 999
		for p in UnitManager.unit_list:
			if p.unit_stats.team_id == 0 and p.hit_points > 0:
				var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
				if d < dist_to_player:
					dist_to_player = d
		score += (10 - dist_to_player) * 0.5

		if score > best_score:
			best_score = score
			best_cell = cell

	if best_cell != unit.grid_cell:
		var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
		if path.size() > 0:
			return {"type": "move", "unit": unit, "path": path}

	return null

# ---- 低血量生存移动（独立调用，优先回血点） ----
func _evaluate_survival_move(unit: Unit):
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.unit_stats.move_range, unit)
	if reachable.is_empty():
		return null

	# 优先回血点
	if _turn_manager != null:
		for cell in reachable.keys():
			if cell == unit.grid_cell:
				continue
			if _turn_manager.map_functions.has(cell):
				var cfg = _turn_manager.map_functions[cell]
				if cfg.has("event_id"):
					var event_id = cfg["event_id"]
					if EventManager.is_event_completed(event_id):
						continue
					var event_def = EventManager.get_event(event_id)
					if event_def.is_empty():
						continue
					var actions = event_def.get("actions", [])
					for action in actions:
						if action.get("type") == "heal" and action.get("amount", 0) > 0:
							var path = UnitManager.calculate_path(unit.grid_cell, cell, unit)
							if path.size() > 0:
								return {"type": "move", "unit": unit, "path": path}

	# 其次治疗者
	var healers = []
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id == unit.unit_stats.team_id and ally != unit and ally.hit_points > 0:
			if ally.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL:
				healers.append(ally)
	if healers.size() > 0:
		var nearest_healer = healers[0]
		var min_dist = 999
		for h in healers:
			var d = abs(h.grid_cell.x - unit.grid_cell.x) + abs(h.grid_cell.y - unit.grid_cell.y)
			if d < min_dist:
				min_dist = d
				nearest_healer = h
		var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		var target_cell = unit.grid_cell
		for d in dirs:
			var neighbor = nearest_healer.grid_cell + d
			if neighbor.x < 0 or neighbor.x >= TerrainManager.grid_size.x or neighbor.y < 0 or neighbor.y >= TerrainManager.grid_size.y:
				continue
			if not UnitManager.is_cell_occupied(neighbor) and reachable.has(neighbor):
				target_cell = neighbor
				break
		if target_cell != unit.grid_cell:
			var path = UnitManager.calculate_path(unit.grid_cell, target_cell, unit)
			if path.size() > 0:
				return {"type": "move", "unit": unit, "path": path}
		else:
			var best_cell = unit.grid_cell
			var best_dist = 999
			for cell in reachable.keys():
				var d = abs(cell.x - nearest_healer.grid_cell.x) + abs(cell.y - nearest_healer.grid_cell.y)
				if d < best_dist and not UnitManager.is_cell_occupied(cell):
					best_dist = d
					best_cell = cell
			if best_cell != unit.grid_cell:
				var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
				if path.size() > 0:
					return {"type": "move", "unit": unit, "path": path}
	return null

# ---- 辅助移动函数 ----
func _find_best_move_to_target(unit: Unit, target_cell: Vector2i, min_range: int, max_range: int) -> Array:
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.unit_stats.move_range, unit)
	var best_cell = unit.grid_cell
	var best_dist = -1
	var found = false
	for cell in reachable.keys():
		var dist = abs(cell.x - target_cell.x) + abs(cell.y - target_cell.y)
		if dist >= min_range and dist <= max_range:
			if not found or dist < best_dist:
				best_dist = dist
				best_cell = cell
				found = true
	if found and best_cell != unit.grid_cell:
		return UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
	return []

func _greedy_move_towards(unit: Unit, target_cell: Vector2i) -> Array:
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.unit_stats.move_range, unit)
	if reachable.is_empty():
		return []

	var best_cell = unit.grid_cell
	var best_dist = INF
	for cell in reachable.keys():
		if UnitManager.is_cell_occupied(cell):
			continue
		var dist = abs(cell.x - target_cell.x) + abs(cell.y - target_cell.y)
		if dist < best_dist:
			best_dist = dist
			best_cell = cell

	if best_cell == unit.grid_cell:
		return []

	return UnitManager.calculate_path(unit.grid_cell, best_cell, unit)

# ============================================================
#  AI 队列执行
# ============================================================
func _process_ai_queue():
	print("_process_ai_queue 开始执行，队列大小: ", ai_queue.size())
	while ai_queue.size() > 0:
		print("处理任务，剩余: ", ai_queue.size())
		await get_tree().create_timer(0.5).timeout
		if _turn_manager.is_game_over:
			_processing = false
			print("游戏结束，终止 AI")
			return
		if ai_queue.size() == 0:
			break

		var task = ai_queue.pop_front()
		var unit = task["unit"]
		if not is_instance_valid(unit) or unit.hit_points <= 0:
			print("单位无效，跳过任务")
			continue

		match task["type"]:
			"attack":
				var target = task["target"]
				var weapon_id = task.get("weapon_id", "")
				if is_instance_valid(target) and target.hit_points > 0:
					print("AI 攻击: ", unit.unit_stats.unit_name, " -> ", target.unit_stats.unit_name, " 使用武器: ", weapon_id)
					SignalBus.request_highlight_unit.emit(target)
					await get_tree().create_timer(0.3).timeout
					if weapon_id != "":
						await CombatManager.execute_attack_with_weapon(unit, target, weapon_id)
					else:
						await CombatManager.execute_attack(unit, target)
					unit.can_act_this_turn = false
					unit.has_attacked = true
					unit.set_gray(true)
					SignalBus.request_clear_highlight_unit.emit()
				else:
					print("攻击目标无效，跳过")
			"move":
				var path = task["path"]
				if path.size() == 0 or UnitManager.is_cell_occupied(path[-1]):
					print("移动路径无效，跳过")
					continue
				print("AI 移动: ", unit.unit_stats.unit_name, " 路径长度 ", path.size())
				_turn_manager.start_ai_movement(unit, path)
				await _turn_manager.move_completed
				print("AI 移动完成")
			"use_item":
				var item_id = task["item_id"]
				var target = task["target"]
				if is_instance_valid(target):
					print("AI 使用道具: ", item_id)
					var success = ItemManager.use_item_on_target(item_id, unit, target)
					if success:
						unit.used_non_attack_item_this_turn = true
					else:
						print("AI 道具使用失败")
				else:
					print("AI 道具目标无效")
			"wait":
				print("AI 待机: ", unit.unit_stats.unit_name)
				unit.can_act_this_turn = false
				unit.set_gray(true)

	_processing = false
	print("AI 队列处理完毕，发射 ai_queue_finished 信号")
	ai_queue_finished.emit()

func _on_move_completed():
	pass

func clear_state():
	ai_queue.clear()
	_processing = false
	first_ai_unit = null
