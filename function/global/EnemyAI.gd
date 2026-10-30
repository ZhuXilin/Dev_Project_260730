extends Node
class_name EnemyAI

signal ai_queue_finished

var ai_queue : Array = []
var _processing : bool = false
var _turn_manager : TurnManager = null
var first_ai_unit : Unit = null

# ---- AI 随机选择参数 ----
## 评分相近的容差：低于最高分超过此值的候选被剔除
const AI_SCORE_TOLERANCE : int = 10
## 权重偏移：让负分候选仍有机会（避免权重为负导致 randi 异常）
const AI_WEIGHT_OFFSET : int = 200

## ★ 本回合我方 AI 已经瞄准的目标（仅在玩家 AI 期间启用）
## key: "unit_name|x|y" -> 累积计数
var _focus_targets : Dictionary = {}


func initialize(turn_manager: TurnManager):
	_turn_manager = turn_manager
	if _turn_manager:
		_turn_manager.move_completed.connect(_on_move_completed)


# ============================================================
#  集火机制（AllyAutoBattleManager 在玩家回合开始/结束时调用）
# ============================================================
func begin_ally_turn_focus() -> void:
	_focus_targets.clear()


func record_focus_target(target: Unit) -> void:
	if not is_instance_valid(target): return
	if target.hit_points <= 0: return
	var key : String = _make_target_key(target)
	_focus_targets[key] = int(_focus_targets.get(key, 0)) + 1


func _make_target_key(u: Unit) -> String:
	return "%s|%d|%d" % [u.unit_stats.unit_name, u.grid_cell.x, u.grid_cell.y]


# ============================================================
#  ★ 地形评分：封顶 0.10，让"建筑"与"树林"吸引力相当
# ============================================================
func _terrain_score(cell: Vector2i) -> int:
	var t : int = TerrainManager.get_terrain(cell)
	var td : Dictionary = TerrainManager.TERRAIN_DATA.get(t, {})
	var phys : float = float(td.get("physical_reduction", 0.0))
	var mag : float = float(td.get("magic_reduction", 0.0))
	var effective : float = minf(phys + mag, 0.10)
	return int(effective * 100.0)


# ============================================================
#  ★ 公共入口：供 AllyAutoBattleManager 复用
# ============================================================
func decide_action_for(unit: Unit) -> Dictionary:
	if unit == null or not is_instance_valid(unit) or unit.hit_points <= 0:
		return {"type": "wait", "unit": unit}
	var act = _decide_action(unit)
	if act == null or act.is_empty():
		return {"type": "wait", "unit": unit}
	if str(act.get("type", "")) == "attack":
		var target = act.get("target", null)
		if target == unit and unit.get_weapon_type() != "staff":
			return {"type": "wait", "unit": unit}
	return act


# ============================================================
#  敌方 AI 主循环
# ============================================================
func run_enemy_ai():
	if _turn_manager == null:
		return
	if _turn_manager.is_game_over or _turn_manager.is_moving:
		return
	if _processing:
		return
	_processing = true

	# ★ 敌方回合清空集火，避免被玩家回合的残留影响
	_focus_targets.clear()

	var enemies = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 1 and unit.hit_points > 0 and unit.visible:
			enemies.append(unit)

	first_ai_unit = enemies[0] if enemies.size() > 0 else null

	ai_queue.clear()

	var cached_actions : Array = []
	var can_act : bool = false
	for enemy in enemies:
		var action = _decide_action(enemy)
		cached_actions.append(action)
		if action and action["type"] != "wait":
			can_act = true

	if not can_act:
		_processing = false
		ai_queue_finished.emit()
		return

	for action in cached_actions:
		if action: ai_queue.append(action)

	_process_ai_queue()


# ============================================================
#  决策统一入口（敌我通用）
# ============================================================
func _decide_action(unit: Unit):
	# 0. 嘲讽：强制攻击嘲讽者
	if unit.taunt_by != null and is_instance_valid(unit.taunt_by) \
			and unit.taunt_rounds_left > 0 and unit.taunt_by.hit_points > 0:
		var taunt_action = _evaluate_taunt_attack(unit, unit.taunt_by)
		if taunt_action:
			return taunt_action

	var hp_ratio = float(unit.hit_points) / float(unit.unit_stats.max_hp)

	# 1. 治疗者：能治疗就治疗
	if unit.get_weapon_type() == "staff":
		var heal_action = _decide_healer_action(unit)
		if heal_action:
			return heal_action

		if hp_ratio < 0.4:
			var healer_survive = _evaluate_survival_move(unit)
			if healer_survive:
				return healer_survive

		var healer_attack = _evaluate_attack(unit, true)
		if healer_attack:
			return healer_attack

		var healer_move = _evaluate_move(unit)
		if healer_move:
			return healer_move

		return {"type": "wait", "unit": unit}

	var attack_action = _evaluate_attack(unit)

	# 2. 低血量特殊战术
	if hp_ratio < 0.4:
		if attack_action:
			var target = attack_action["target"]
			var damage = CombatManager.calculate_damage(unit, target)
			var target_hp_ratio = float(target.hit_points) / float(max(1, target.unit_stats.max_hp))

			if damage >= target.hit_points:
				return attack_action

			if target_hp_ratio < 0.3:
				return attack_action

			var enemies_around = 0
			for p in UnitManager.unit_list:
				if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
					var d = abs(unit.grid_cell.x - p.grid_cell.x) + abs(unit.grid_cell.y - p.grid_cell.y)
					if d <= unit.unit_stats.move_range + 2:
						enemies_around += 1
			if enemies_around >= 3:
				return attack_action

		var survival_move = _evaluate_survival_move(unit)
		if survival_move:
			return survival_move

	# 3. 正常攻击
	if attack_action:
		return attack_action

	# 4. 普通移动
	var move_action = _evaluate_move(unit)
	if move_action:
		return move_action

	return {"type": "wait", "unit": unit}


# ============================================================
#  辅助：远程 / 距离
# ============================================================
func _is_ranged_unit(unit: Unit) -> bool:
	var wt = unit.get_weapon_type()
	return wt in ["bow", "crossbow", "spellbook", "staff"]

func _nearest_enemy_dist(unit: Unit, cell: Vector2i) -> int:
	var best : int = 999
	for p in UnitManager.unit_list:
		if p == unit:
			continue
		if p.hit_points <= 0:
			continue
		if p.unit_stats.team_id != unit.unit_stats.team_id:
			var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
			if d < best:
				best = d
	return best

## ★ 到最近友军的距离（不含自己），无友军返回 999
func _nearest_ally_dist(unit: Unit, cell: Vector2i) -> int:
	var best : int = 999
	for a in UnitManager.unit_list:
		if a == unit:
			continue
		if a.unit_stats.team_id != unit.unit_stats.team_id:
			continue
		if a.hit_points <= 0:
			continue
		var d = abs(cell.x - a.grid_cell.x) + abs(cell.y - a.grid_cell.y)
		if d < best:
			best = d
	return best


# ============================================================
#  治疗者决策（法杖治疗）
# ============================================================
func _decide_healer_action(unit: Unit):
	var weapon_data = unit.get_weapon_data()
	var heal_range = weapon_data.attack_range if weapon_data else 0
	var min_heal_range = weapon_data.min_attack_range if weapon_data else 0

	var self_hp_ratio = float(unit.hit_points) / float(max(1, unit.unit_stats.max_hp))
	if self_hp_ratio < 0.3 and unit.hit_points < unit.unit_stats.max_hp:
		return {"type": "attack", "unit": unit, "target": unit}

	var best_target = null
	var max_hp_loss = 0
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id != unit.unit_stats.team_id: continue
		if ally.hit_points <= 0: continue
		var dist = abs(unit.grid_cell.x - ally.grid_cell.x) + abs(unit.grid_cell.y - ally.grid_cell.y)
		if dist < min_heal_range or dist > heal_range: continue
		var hp_loss = ally.unit_stats.max_hp - ally.hit_points
		if hp_loss <= 0: continue
		if hp_loss > max_hp_loss:
			max_hp_loss = hp_loss
			best_target = ally

	if best_target:
		return {"type": "attack", "unit": unit, "target": best_target}

	var wounded_ally = null
	max_hp_loss = 0
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id != unit.unit_stats.team_id: continue
		if ally.hit_points <= 0: continue
		if ally == unit: continue
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
#  攻击评估（强化集火 / 脆弱目标 / 击杀）
# ============================================================
func _evaluate_attack(unit: Unit, allow_healer: bool = false):
	var is_healer = (unit.get_weapon_type() == "staff")
	if is_healer and not allow_healer:
		return null

	var weapon_id = unit.get_equipped_weapon_id()
	if weapon_id == "":
		return null

	var data = ItemManager.get_item_data(weapon_id)
	if not data:
		return null

	var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
	var max_range : int = WeaponUpgradeHelper.get_effective_attack_range(data, up_lv)
	var min_range : int = data.min_attack_range

	var candidates : Array = []

	for enemy in UnitManager.unit_list:
		if enemy.unit_stats.team_id == unit.unit_stats.team_id or enemy.hit_points <= 0:
			continue

		var dist = abs(unit.grid_cell.x - enemy.grid_cell.x) + abs(unit.grid_cell.y - enemy.grid_cell.y)
		if dist < min_range or dist > max_range:
			continue

		var damage = CombatManager.calculate_damage(unit, enemy)
		if damage <= 0:
			continue

		var score = damage * 2

		# ★ 击杀加分提高
		if damage >= enemy.hit_points:
			score += 150

		# ★ 脆弱目标加分提高
		var target_hp_ratio = float(enemy.hit_points) / float(max(1, enemy.unit_stats.max_hp))
		if target_hp_ratio < 0.3:
			score += 70
		elif target_hp_ratio < 0.5:
			score += 35

		# ★ 高威胁辅助优先
		var enemy_wt = enemy.get_weapon_type()
		if enemy_wt == "staff":
			score += 40
		elif enemy_wt == "spellbook":
			score += 20

		# ★ 集火：本回合已被我方 AI 瞄准的目标大幅加权
		var tkey : String = _make_target_key(enemy)
		if _focus_targets.has(tkey):
			score += 40 * int(_focus_targets[tkey])

		# 反击判定
		var can_counter = false
		var enemy_weapon_type = enemy.get_weapon_type()
		if enemy_weapon_type != "" and enemy_weapon_type != "staff":
			var enemy_weapon_data = enemy.get_weapon_data()
			if enemy_weapon_data:
				var enemy_min = enemy_weapon_data.min_attack_range
				var enemy_max = enemy_weapon_data.attack_range
				var dist_to_attacker = abs(enemy.grid_cell.x - unit.grid_cell.x) + abs(enemy.grid_cell.y - unit.grid_cell.y)
				if dist_to_attacker >= enemy_min and dist_to_attacker <= enemy_max:
					can_counter = true

		if not can_counter:
			score += 30

		if can_counter and unit.hit_points < unit.unit_stats.max_hp * 0.4:
			var counter_dmg = CombatManager.calculate_damage(enemy, unit)
			if enemy.relic_first_attack_crit_remaining > 0:
				counter_dmg = int(counter_dmg * 1.5)
			if counter_dmg >= unit.hit_points and damage < enemy.hit_points:
				score -= 100

		candidates.append({"target": enemy, "score": score})

	if candidates.is_empty():
		return null

	var picked : Dictionary = _pick_target_by_weight(candidates)
	var best_target : Unit = picked["target"]
	return {"type": "attack", "unit": unit, "target": best_target, "weapon_id": weapon_id}


# ============================================================
#  移动评估
# ============================================================
func _evaluate_move(unit: Unit):
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.unit_stats.move_range, unit)
	if reachable.is_empty():
		return null

	var best_cell = unit.grid_cell
	var best_score = -999

	# 1. 回血点
	var hp_ratio = float(unit.hit_points) / float(unit.unit_stats.max_hp)
	if hp_ratio < 0.7 and _turn_manager != null:
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

	# 2. 低血撤退
	if hp_ratio < 0.4:
		var healers = []
		for ally in UnitManager.unit_list:
			if ally.unit_stats.team_id == unit.unit_stats.team_id and ally != unit and ally.hit_points > 0:
				if ally.get_weapon_type() == "staff":
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

		# 2b. 高防御地形（已封顶）
		best_cell = unit.grid_cell
		best_score = -999
		for cell in reachable.keys():
			var score : int = _terrain_score(cell)
			var dist_to_enemy = 999
			for p in UnitManager.unit_list:
				if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
					var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
					if d < dist_to_enemy:
						dist_to_enemy = d
			score += dist_to_enemy * 2
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
		return null

	# 3. 正常：近战 / 远程差异化 + ★ 队形保持
	best_cell = unit.grid_cell
	best_score = -999
	var is_ranged := _is_ranged_unit(unit)
	for cell in reachable.keys():
		var terrain_score : int = _terrain_score(cell)
		var score : int = 0

		var ally_near = false
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor = cell + dir
			var neighbor_unit = UnitManager.get_unit_at_cell(neighbor)
			if neighbor_unit and neighbor_unit.unit_stats.team_id == unit.unit_stats.team_id:
				ally_near = true
				break

		if is_ranged:
			var can_attack := _can_attack_from_cell(unit, cell)
			if can_attack:
				score = 100 + int(terrain_score / 2.0)
				var nd := _nearest_enemy_dist(unit, cell)
				if nd < 999:
					score += nd * 15
			else:
				score = -40 + int(terrain_score / 2.0)

			# ★ 远程队形保持（不能跑太远）
			var ally_dist := _nearest_ally_dist(unit, cell)
			if ally_dist < 999:
				score += maxi(-5, 8 - ally_dist * 2)
		else:
			# ★ 近战：贴上去打，但要避免落单
			score = terrain_score

			var dist_to_enemy = 999
			for p in UnitManager.unit_list:
				if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
					var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
					if d < dist_to_enemy:
						dist_to_enemy = d
			score += int((10 - dist_to_enemy) * 0.5)

			# ★ 近战队形保持（强力约束，防止单点深入）
			var ally_dist := _nearest_ally_dist(unit, cell)
			if ally_dist < 999:
				score += int((4 - ally_dist) * 3)

			# ★ 深入敌阵惩罚：周围敌人 > 队友时扣分
			var enemies_around = 0
			var allies_around = 0
			for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n = UnitManager.get_unit_at_cell(cell + dir)
				if n:
					if n.unit_stats.team_id == unit.unit_stats.team_id:
						allies_around += 1
					else:
						enemies_around += 1
			if enemies_around > allies_around:
				score -= 10 * (enemies_around - allies_around)

			if _can_attack_from_cell(unit, cell):
				score += 50

		if ally_near:
			score += 5

		if score > best_score:
			best_score = score
			best_cell = cell

	if best_cell != unit.grid_cell:
		var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
		if path.size() > 0:
			return {"type": "move", "unit": unit, "path": path}

	return null


func _can_attack_from_cell(unit: Unit, cell: Vector2i) -> bool:
	var weapon_data = unit.get_weapon_data()
	if not weapon_data:
		return false
	var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
	var max_range : int = WeaponUpgradeHelper.get_effective_attack_range(weapon_data, up_lv)
	var min_range : int = weapon_data.min_attack_range
	for enemy in UnitManager.unit_list:
		if enemy.unit_stats.team_id == unit.unit_stats.team_id: continue
		if enemy.hit_points <= 0: continue
		var dist = abs(cell.x - enemy.grid_cell.x) + abs(cell.y - enemy.grid_cell.y)
		if dist >= min_range and dist <= max_range:
			return true
	return false


# ---- 低血量生存移动 ----
func _evaluate_survival_move(unit: Unit):
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.unit_stats.move_range, unit)
	if reachable.is_empty():
		return null

	var best_cell = unit.grid_cell
	var best_score = -999

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

	# 治疗者
	var healers = []
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id == unit.unit_stats.team_id and ally != unit and ally.hit_points > 0:
			if ally.get_weapon_type() == "staff":
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

	# 高防御地形（封顶）
	best_cell = unit.grid_cell
	best_score = -999
	for cell in reachable.keys():
		var score : int = _terrain_score(cell)
		var dist_to_enemy = 999
		for p in UnitManager.unit_list:
			if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
				var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
				if d < dist_to_enemy:
					dist_to_enemy = d
		score += dist_to_enemy * 2
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


func _retry_find_path(unit: Unit) -> Array:
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.unit_stats.move_range, unit)
	if reachable.is_empty():
		return []

	var best_cell = unit.grid_cell
	var best_score = -999999
	var has_candidate = false
	var is_ranged := _is_ranged_unit(unit)

	for cell in reachable.keys():
		if cell == unit.grid_cell:
			continue
		if UnitManager.is_cell_occupied(cell):
			continue

		var nearest_enemy_dist : int = 9999
		for enemy in UnitManager.unit_list:
			if enemy.unit_stats.team_id == unit.unit_stats.team_id:
				continue
			if enemy.hit_points <= 0:
				continue
			var d = abs(cell.x - enemy.grid_cell.x) + abs(cell.y - enemy.grid_cell.y)
			if d < nearest_enemy_dist:
				nearest_enemy_dist = d

		var score : int = 0
		if is_ranged:
			if _can_attack_from_cell(unit, cell):
				score = 1000 + nearest_enemy_dist * 15
			else:
				score = -nearest_enemy_dist * 5
		else:
			score = -nearest_enemy_dist * 10

		# ★ 地形加成（封顶）
		score += _terrain_score(cell) * 3

		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor_unit = UnitManager.get_unit_at_cell(cell + dir)
			if neighbor_unit and neighbor_unit.unit_stats.team_id == unit.unit_stats.team_id:
				score += 5
				break

		if score > best_score:
			best_score = score
			best_cell = cell
			has_candidate = true

	if not has_candidate or best_cell == unit.grid_cell:
		return []

	return UnitManager.calculate_path(unit.grid_cell, best_cell, unit)


# ============================================================
#  AI 队列执行（仅敌方走此路径）
# ============================================================
func _process_ai_queue():
	var total_tasks : int = ai_queue.size()
	print("[AI] 开始处理队列，共 %d 个任务" % total_tasks)
	var processed : int = 0
	while ai_queue.size() > 0:
		await get_tree().create_timer(0.5).timeout
		if _turn_manager.is_game_over:
			_processing = false
			print("[AI] 游戏结束，终止")
			return
		if ai_queue.size() == 0:
			break

		var task = ai_queue.pop_front()
		var unit = task["unit"]
		if not is_instance_valid(unit) or unit.hit_points <= 0:
			continue

		match task["type"]:
			"attack":
				var target = task["target"]
				if is_instance_valid(target) and target.hit_points > 0:
					if target == unit:
						print("[AI] %s 自愈" % unit.unit_stats.unit_name)
					else:
						print("[AI] %s 攻击 %s" % [
							unit.unit_stats.unit_name, target.unit_stats.unit_name])
					SignalBus.request_highlight_unit.emit(target)
					await get_tree().create_timer(0.3).timeout
					await CombatManager.execute_attack(unit, target)
					unit.can_act_this_turn = false
					unit.has_attacked = true
					unit.set_gray(true)
					SignalBus.request_clear_highlight_unit.emit()
			"move":
				var path = task["path"]
				if path.size() == 0 or UnitManager.is_cell_occupied(path[-1]):
					path = _retry_find_path(unit)
					if path.size() == 0 or UnitManager.is_cell_occupied(path[-1]):
						continue
				print("[AI] %s 移动 %d 格" % [unit.unit_stats.unit_name, path.size()])
				_turn_manager.start_ai_movement(unit, path)
				await _turn_manager.move_completed
			"wait":
				unit.can_act_this_turn = false
				unit.set_gray(true)
		processed += 1

	for u in UnitManager.unit_list:
		if is_instance_valid(u) and u.unit_stats.team_id == 1:
			u.taunt_rounds_left = 0
			u.taunt_by = null

	_processing = false
	print("[AI] 队列处理完毕（处理 %d / %d）" % [processed, total_tasks])
	ai_queue_finished.emit()


func _on_move_completed():
	pass

func clear_state():
	ai_queue.clear()
	_processing = false
	first_ai_unit = null


# ============================================================
#  加权随机选目标
# ============================================================
func _pick_target_by_weight(candidates: Array) -> Dictionary:
	var top_score : int = -999999
	for c in candidates:
		if c["score"] > top_score:
			top_score = c["score"]

	var finalists : Array = []
	for c in candidates:
		if c["score"] >= top_score - AI_SCORE_TOLERANCE:
			finalists.append(c)

	if finalists.size() == 1:
		return finalists[0]

	var total_weight : int = 0
	for f in finalists:
		total_weight += maxi(1, f["score"] + AI_WEIGHT_OFFSET)

	var roll : int = randi() % total_weight
	var acc : int = 0
	for f in finalists:
		acc += maxi(1, f["score"] + AI_WEIGHT_OFFSET)
		if acc > roll:
			return f

	return finalists[0]


func _evaluate_taunt_attack(unit: Unit, taunter: Unit) -> Dictionary:
	var weapon_data = unit.get_weapon_data()
	if not weapon_data:
		return {}

	var dist = abs(unit.grid_cell.x - taunter.grid_cell.x) \
			+ abs(unit.grid_cell.y - taunter.grid_cell.y)
	var min_range = weapon_data.min_attack_range
	var max_range = weapon_data.attack_range

	if dist >= min_range and dist <= max_range:
		return {"type": "attack", "unit": unit, "target": taunter,
				"weapon_id": unit.get_equipped_weapon_id()}

	var path = _find_best_move_to_target(unit, taunter.grid_cell, min_range, max_range)
	if path.size() > 0:
		return {"type": "move", "unit": unit, "path": path}

	var greedy = _greedy_move_towards(unit, taunter.grid_cell)
	if greedy.size() > 0:
		return {"type": "move", "unit": unit, "path": greedy}

	return {}
