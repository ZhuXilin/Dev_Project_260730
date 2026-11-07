extends Node
class_name EnemyAI

signal ai_queue_finished

var ai_queue : Array = []
var _processing : bool = false
var _turn_manager : TurnManager = null
var first_ai_unit : Unit = null

const AI_SCORE_TOLERANCE : int = 10
const AI_WEIGHT_OFFSET : int = 20

var _focus_targets : Dictionary = {}


func initialize(turn_manager: TurnManager):
	_turn_manager = turn_manager
	if _turn_manager:
		_turn_manager.move_completed.connect(_on_move_completed)


func begin_ally_turn_focus() -> void:
	_focus_targets.clear()


func record_focus_target(target: Unit) -> void:
	if not is_instance_valid(target) or target.hit_points <= 0: return
	var key : String = _make_target_key(target)
	_focus_targets[key] = int(_focus_targets.get(key, 0)) + 1


func _make_target_key(u: Unit) -> String:
	return "%s|%d|%d" % [u.unit_stats.unit_name, u.grid_cell.x, u.grid_cell.y]


func _terrain_score(cell: Vector2i) -> int:
	var t : int = TerrainManager.get_terrain(cell)
	var td : Dictionary = TerrainManager.TERRAIN_DATA.get(t, {})
	return int((float(td.get("physical_reduction", 0.0)) + float(td.get("magic_reduction", 0.0))) * 300.0)

func _get_cell_danger_score(cell: Vector2i, unit: Unit) -> int:
	var danger := 0
	for enemy in UnitManager.unit_list:
		if not is_instance_valid(enemy) or enemy.unit_stats.team_id == unit.unit_stats.team_id: continue
		if enemy.hit_points <= 0: continue
		var u_stats = enemy.unit_stats
		if not u_stats: continue
		var max_range : int = u_stats.attack_range
		var min_range : int = u_stats.min_attack_range
		var dist = abs(cell.x - enemy.grid_cell.x) + abs(cell.y - enemy.grid_cell.y)
		if dist >= min_range and dist <= max_range:
			danger += int(u_stats.attack * 8)
	return danger


func _evaluate_self_danger(unit: Unit) -> int:
	var danger := 0
	for enemy in UnitManager.unit_list:
		if not is_instance_valid(enemy) or enemy.unit_stats.team_id == unit.unit_stats.team_id: continue
		if enemy.hit_points <= 0: continue
		var u_stats = enemy.unit_stats
		if not u_stats: continue
		var max_range : int = u_stats.attack_range
		var min_range : int = u_stats.min_attack_range
		var dist : int = abs(unit.grid_cell.x - enemy.grid_cell.x) + abs(unit.grid_cell.y - enemy.grid_cell.y)
		if dist >= min_range and dist <= max_range:
			danger += 1
	return danger

func _get_heal_priority(u: Unit) -> float:
	var priority := 1.0
	var u_stats = u.unit_stats
	if u_stats:
		var qm : float = CombatManager.QUALITY_MULT.get(u_stats.weapon_quality, 1.0)
		priority += u_stats.attack * qm * 0.08
	if u.get_weapon_type() == "staff":
		priority += 1.5
	if u.unit_stats.max_hp >= 40:
		priority += 0.8
	for inst in u.talent_slots:
		if inst and inst.is_active:
			var td = TalentManager.get_talent_data(inst.talent_id)
			if td and td.is_active_skill:
				priority += 0.5
				break
	return priority


func _is_desperate(unit: Unit) -> bool:
	if not is_instance_valid(unit) or unit.hit_points <= 0: return false
	var ally_count := 0
	var enemy_count := 0
	for u in UnitManager.unit_list:
		if not is_instance_valid(u) or u.hit_points <= 0: continue
		if u.unit_stats.team_id == unit.unit_stats.team_id: ally_count += 1
		else: enemy_count += 1

	if ally_count > 1: return ally_count == 2 and enemy_count >= 5
	if enemy_count >= 3: return true
	if enemy_count == 2:
		return (float(unit.hit_points) / float(max(1, unit.unit_stats.max_hp))) < 0.4
	return false

func _decide_desperate_action(unit: Unit) -> Dictionary:
	var u_stats = unit.unit_stats
	if u_stats:
		var max_range : int = u_stats.attack_range
		var min_range : int = u_stats.min_attack_range
		var best_target : Unit = null
		var best_dist : int = 9999
		for enemy in UnitManager.unit_list:
			if not is_instance_valid(enemy) or enemy.hit_points <= 0 or enemy.unit_stats.team_id == unit.unit_stats.team_id: continue
			var dist : int = abs(unit.grid_cell.x - enemy.grid_cell.x) + abs(unit.grid_cell.y - enemy.grid_cell.y)
			if dist >= min_range and dist <= max_range and dist < best_dist:
				best_dist = dist
				best_target = enemy
		if best_target:
			return {"type": "attack", "unit": unit, "target": best_target, "weapon_id": unit.get_equipped_weapon_id()}

	var nearest_enemy : Unit = null
	var nearest_dist : int = 9999
	for enemy in UnitManager.unit_list:
		if not is_instance_valid(enemy) or enemy.hit_points <= 0 or enemy.unit_stats.team_id == unit.unit_stats.team_id: continue
		var dist : int = abs(unit.grid_cell.x - enemy.grid_cell.x) + abs(unit.grid_cell.y - enemy.grid_cell.y)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_enemy = enemy

	if nearest_enemy and unit.remaining_move > 0:
		var path := _greedy_move_towards(unit, nearest_enemy.grid_cell)
		if path.size() > 0: return {"type": "move", "unit": unit, "path": path}
		return _try_force_advance(unit)
	return {"type": "wait", "unit": unit}


func decide_action_for(unit: Unit) -> Dictionary:
	if unit == null or not is_instance_valid(unit) or unit.hit_points <= 0: return {"type": "wait", "unit": unit}
	var act = _decide_action(unit)
	if act == null or act.is_empty(): return {"type": "wait", "unit": unit}
	if str(act.get("type", "")) == "attack":
		var target = act.get("target", null)
		if target == unit and unit.get_weapon_type() != "staff": return {"type": "wait", "unit": unit}
	return act


func run_enemy_ai():
	if _turn_manager == null or _turn_manager.is_game_over or _turn_manager.is_moving or _processing: return
	_processing = true
	_focus_targets.clear()

	var enemies = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 1 and unit.hit_points > 0 and unit.visible: enemies.append(unit)
	first_ai_unit = enemies[0] if enemies.size() > 0 else null
	ai_queue.clear()

	var cached_actions : Array = []
	var can_act : bool = false
	for enemy in enemies:
		var action = _decide_action(enemy)
		if action:
			action["phase_version"] = int(enemy.get_meta("boss_phase_version", 0))
		cached_actions.append(action)
		if action and action["type"] != "wait": can_act = true

	if not can_act:
		_processing = false
		ai_queue_finished.emit()
		return
	for action in cached_actions:
		if action: ai_queue.append(action)
	_process_ai_queue()


func _decide_action(unit: Unit):
	if unit.taunt_by != null and is_instance_valid(unit.taunt_by) and unit.taunt_rounds_left > 0 and unit.taunt_by.hit_points > 0:
		var taunt_action = _evaluate_taunt_attack(unit, unit.taunt_by)
		if taunt_action: return taunt_action

	if _is_desperate(unit): return _decide_desperate_action(unit)

	var hp_ratio = float(unit.hit_points) / float(unit.unit_stats.max_hp)

	if unit.get_weapon_type() == "staff":
		if hp_ratio < 0.3:
			var survive_move = _evaluate_survival_move(unit)
			if survive_move: return survive_move
		var heal_action = _decide_healer_action(unit)
		if heal_action: return heal_action
		if hp_ratio < 0.45:
			if _evaluate_self_danger(unit) >= 2:
				var healer_survive = _evaluate_survival_move(unit)
				if healer_survive: return healer_survive
		var healer_attack = _evaluate_attack(unit, true)
		if healer_attack: return healer_attack
		var healer_move = _evaluate_move(unit)
		if healer_move: return healer_move
		return _try_force_advance(unit)

	var attack_action = _evaluate_attack(unit)

	if hp_ratio < 0.4:
		var should_flee = true
		if attack_action:
			var target = attack_action["target"]
			var damage = CombatManager.calculate_damage(unit, target)
			var target_hp_ratio = float(target.hit_points) / float(max(1, target.unit_stats.max_hp))
			if damage >= target.hit_points or target_hp_ratio < 0.3: return attack_action
			var enemies_around = 0
			for p in UnitManager.unit_list:
				if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
					if abs(unit.grid_cell.x - p.grid_cell.x) + abs(unit.grid_cell.y - p.grid_cell.y) <= 2:
						enemies_around += 1
			if enemies_around <= 1 and damage > target.unit_stats.max_hp * 0.2: should_flee = false
		if should_flee:
			var survival_move = _evaluate_survival_move(unit)
			if survival_move: return survival_move

	if attack_action: return attack_action
	var move_action = _evaluate_move(unit)
	if move_action: return move_action
	return _try_force_advance(unit)


func _try_force_advance(unit: Unit) -> Dictionary:
	if unit.remaining_move <= 0: return {"type": "wait", "unit": unit}
	var best_path := _retry_find_path(unit)
	if best_path.size() > 0: return {"type": "move", "unit": unit, "path": best_path}
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.remaining_move, unit)
	if not reachable.is_empty():
		var random_cell = reachable.keys()[randi() % reachable.size()]
		if random_cell != unit.grid_cell:
			var path = UnitManager.calculate_path(unit.grid_cell, random_cell, unit)
			if path.size() > 0: return {"type": "move", "unit": unit, "path": path}
	return {"type": "wait", "unit": unit}


func _is_ranged_unit(unit: Unit) -> bool:
	return unit.get_weapon_type() in ["bow", "crossbow", "spellbook", "staff"]

func _nearest_enemy_dist(unit: Unit, cell: Vector2i) -> int:
	var best : int = 999
	for p in UnitManager.unit_list:
		if p == unit or p.hit_points <= 0 or p.unit_stats.team_id == unit.unit_stats.team_id: continue
		var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
		if d < best: best = d
	return best

func _nearest_ally_dist(unit: Unit, cell: Vector2i) -> int:
	var best : int = 999
	for a in UnitManager.unit_list:
		if a == unit or a.unit_stats.team_id != unit.unit_stats.team_id or a.hit_points <= 0: continue
		var d = abs(cell.x - a.grid_cell.x) + abs(cell.y - a.grid_cell.y)
		if d < best: best = d
	return best


func _decide_healer_action(unit: Unit):
	var weapon_data = unit.unit_stats
	var heal_range : int = weapon_data.attack_range if weapon_data else 0
	var min_heal_range : int = weapon_data.min_attack_range if weapon_data else 0
	var self_hp_ratio : float = float(unit.hit_points) / float(max(1, unit.unit_stats.max_hp))
	var self_loss : int = unit.unit_stats.max_hp - unit.hit_points
	var self_danger : int = _evaluate_self_danger(unit)
	var sf_state : int = SoulFireManager.get_state()
	var is_burning : bool = (sf_state == SoulFireManager.State.BURNING)
	var is_depleted : bool = (sf_state == SoulFireManager.State.DEPLETED)
	var danger_tolerance : int = 1 if is_depleted else 0

	var best_ally : Unit = null
	var best_ally_score : float = 0.0
	var best_ally_loss : int = 0
	var best_ally_ratio : float = 1.0
	for ally in UnitManager.unit_list:
		if not is_instance_valid(ally) or ally.unit_stats.team_id != unit.unit_stats.team_id or ally.hit_points <= 0 or ally == unit: continue
		var dist : int = abs(unit.grid_cell.x - ally.grid_cell.x) + abs(unit.grid_cell.y - ally.grid_cell.y)
		if dist < min_heal_range or dist > heal_range: continue
		var loss : int = ally.unit_stats.max_hp - ally.hit_points
		if loss <= 0: continue
		var score : float = _get_heal_priority(ally) * float(loss)
		if score > best_ally_score:
			best_ally_score = score
			best_ally = ally
			best_ally_loss = loss
			best_ally_ratio = float(ally.hit_points) / float(max(1, ally.unit_stats.max_hp))

	if self_hp_ratio < 0.25: return {"type": "attack", "unit": unit, "target": unit}
	if self_hp_ratio < 0.5 and self_danger > danger_tolerance:
		if best_ally and best_ally_ratio < 0.25 and self_danger <= danger_tolerance + 1 and self_hp_ratio > best_ally_ratio and best_ally.get_weapon_type() != "staff":
			return {"type": "attack", "unit": unit, "target": best_ally}
		return {"type": "attack", "unit": unit, "target": unit}
	if best_ally:
		if best_ally_ratio < 0.3: return {"type": "attack", "unit": unit, "target": best_ally}
		if best_ally_loss > self_loss and self_hp_ratio > 0.7: return {"type": "attack", "unit": unit, "target": best_ally}
		if is_burning and best_ally_loss > best_ally.unit_stats.max_hp * 0.4: return {"type": "attack", "unit": unit, "target": best_ally}
	if self_hp_ratio < 1.0:
		if self_danger > 0: return {"type": "attack", "unit": unit, "target": unit}
		if best_ally and best_ally_loss > self_loss: return {"type": "attack", "unit": unit, "target": best_ally}
		return {"type": "attack", "unit": unit, "target": unit}

	var wounded_ally : Unit = null
	var max_hp_loss : int = 0
	for ally in UnitManager.unit_list:
		if not is_instance_valid(ally) or ally.unit_stats.team_id != unit.unit_stats.team_id or ally.hit_points <= 0 or ally == unit: continue
		var loss : int = ally.unit_stats.max_hp - ally.hit_points
		if loss > max_hp_loss:
			max_hp_loss = loss
			wounded_ally = ally

	if wounded_ally and max_hp_loss > wounded_ally.unit_stats.max_hp * 0.3:
		var path_to_heal := _find_best_move_to_target(unit, wounded_ally.grid_cell, min_heal_range, heal_range)
		if path_to_heal.size() > 0: return {"type": "move", "unit": unit, "path": path_to_heal}
		var greedy := _greedy_move_towards(unit, wounded_ally.grid_cell)
		if greedy.size() > 0: return {"type": "move", "unit": unit, "path": greedy}
	return null


func _evaluate_attack(unit: Unit, allow_healer: bool = false):
	var is_healer = (unit.get_weapon_type() == "staff")
	if is_healer and not allow_healer: return null
	var u_stats = unit.unit_stats
	if not u_stats or u_stats.weapon_name == "": return null

	var max_range : int = u_stats.attack_range
	var min_range : int = u_stats.min_attack_range
	var candidates : Array = []

	for enemy in UnitManager.unit_list:
		if enemy.unit_stats.team_id == unit.unit_stats.team_id or enemy.hit_points <= 0: continue
		var dist = abs(unit.grid_cell.x - enemy.grid_cell.x) + abs(unit.grid_cell.y - enemy.grid_cell.y)
		if dist < min_range or dist > max_range: continue
		var damage = CombatManager.calculate_damage(unit, enemy)
		if damage <= 0: continue

		var is_kill = damage >= enemy.hit_points
		var score = damage * 2
		if is_kill:
			score += 1000
		else:
			var target_hp_ratio = float(enemy.hit_points) / float(max(1, enemy.unit_stats.max_hp))
			score += int((1.0 - target_hp_ratio) * 150)
			if enemy.hit_points - damage > 0 and enemy.hit_points - damage < enemy.unit_stats.max_hp * 0.3:
				score += 100

		var is_threatening_backline = false
		for ally in UnitManager.unit_list:
			if ally.unit_stats.team_id != unit.unit_stats.team_id or ally.hit_points <= 0: continue
			if ally.get_weapon_type() in ["bow", "crossbow", "spellbook", "staff"]:
				if abs(ally.grid_cell.x - enemy.grid_cell.x) + abs(ally.grid_cell.y - enemy.grid_cell.y) <= 2:
					is_threatening_backline = true
					break
		if is_threatening_backline: score += 150

		var enemy_wt = enemy.get_weapon_type()
		if is_kill:
			if enemy_wt == "staff" or enemy_wt == "spellbook": score += 200
		else:
			if enemy_wt == "staff": score += 60
			elif enemy_wt == "spellbook": score += 30

		var tkey : String = _make_target_key(enemy)
		if _focus_targets.has(tkey): score += 40 * int(_focus_targets[tkey])

		var can_counter = false
		if enemy_wt != "" and enemy_wt != "staff":
			var enemy_stats = enemy.unit_stats
			if enemy_stats:
				var dist_to_attacker = abs(enemy.grid_cell.x - unit.grid_cell.x) + abs(enemy.grid_cell.y - unit.grid_cell.y)
				if dist_to_attacker >= enemy_stats.min_attack_range and dist_to_attacker <= enemy_stats.attack_range:
					can_counter = true

		if not can_counter: score += 30
		if can_counter and unit.hit_points < unit.unit_stats.max_hp * 0.4:
			var counter_dmg = CombatManager.calculate_damage(enemy, unit)
			if enemy.relic_first_attack_crit_remaining > 0: counter_dmg = int(counter_dmg * 1.5)
			if counter_dmg >= unit.hit_points and damage < enemy.hit_points: score -= 100

		candidates.append({"target": enemy, "score": score, "is_kill": is_kill})

	if candidates.is_empty(): return null

	var kill_candidates : Array = []
	for c in candidates:
		if c["is_kill"]: kill_candidates.append(c)

	if not kill_candidates.is_empty():
		var picked = _pick_target_by_weight(kill_candidates)
		return {"type": "attack", "unit": unit, "target": picked["target"], "weapon_id": unit.get_equipped_weapon_id()}

	return {"type": "attack", "unit": unit, "target": _pick_target_by_weight(candidates)["target"], "weapon_id": unit.get_equipped_weapon_id()}


func _evaluate_move(unit: Unit):
	var move_mv : int = unit.remaining_move
	if move_mv <= 0: return null
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, move_mv, unit)
	if reachable.is_empty(): return null

	var best_cell = unit.grid_cell
	var best_score = -999
	var hp_ratio = float(unit.hit_points) / float(unit.unit_stats.max_hp)

	if hp_ratio < 0.7 and _turn_manager != null:
		var heal_cells = []
		for cell in reachable.keys():
			if cell == unit.grid_cell: continue
			if _turn_manager.map_functions.has(cell):
				var cfg = _turn_manager.map_functions[cell]
				if cfg.has("event_id"):
					var event_id = cfg["event_id"]
					if EventManager.is_event_completed(event_id): continue
					var event_def = EventManager.get_event(event_id)
					if event_def.is_empty(): continue
					for action in event_def.get("actions", []):
						if action.get("type") == "heal" and action.get("amount", 0) > 0:
							heal_cells.append(cell)
							break
		if heal_cells.size() > 0:
			heal_cells.sort_custom(func(a, b): return abs(a.x - unit.grid_cell.x) + abs(a.y - unit.grid_cell.y) < abs(b.x - unit.grid_cell.x) + abs(b.y - unit.grid_cell.y))
			var target_cell = heal_cells[0]
			var path = UnitManager.calculate_path(unit.grid_cell, target_cell, unit)
			if path.size() > 0: return {"type": "move", "unit": unit, "path": path}

	if hp_ratio < 0.4:
		var healers = []
		for ally in UnitManager.unit_list:
			if ally.unit_stats.team_id == unit.unit_stats.team_id and ally != unit and ally.hit_points > 0 and ally.get_weapon_type() == "staff":
				healers.append(ally)
		if healers.size() > 0:
			var nearest_healer = healers[0]
			var min_dist = 999
			for h in healers:
				var d = abs(h.grid_cell.x - unit.grid_cell.x) + abs(h.grid_cell.y - unit.grid_cell.y)
				if d < min_dist: min_dist = d; nearest_healer = h
			var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
			var target_cell = unit.grid_cell
			for d in dirs:
				var neighbor = nearest_healer.grid_cell + d
				if neighbor.x < 0 or neighbor.x >= TerrainManager.grid_size.x or neighbor.y < 0 or neighbor.y >= TerrainManager.grid_size.y: continue
				if not UnitManager.is_cell_occupied(neighbor) and reachable.has(neighbor):
					target_cell = neighbor; break
			if target_cell != unit.grid_cell:
				var path = UnitManager.calculate_path(unit.grid_cell, target_cell, unit)
				if path.size() > 0: return {"type": "move", "unit": unit, "path": path}
			else:
				best_cell = unit.grid_cell
				var best_dist = 999
				for cell in reachable.keys():
					var d = abs(cell.x - nearest_healer.grid_cell.x) + abs(cell.y - nearest_healer.grid_cell.y)
					if d < best_dist and not UnitManager.is_cell_occupied(cell):
						best_dist = d; best_cell = cell
				if best_cell != unit.grid_cell:
					var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
					if path.size() > 0: return {"type": "move", "unit": unit, "path": path}

		best_cell = unit.grid_cell
		best_score = -999
		for cell in reachable.keys():
			var score : int = _terrain_score(cell)
			var dist_to_enemy = 999
			for p in UnitManager.unit_list:
				if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
					var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
					if d < dist_to_enemy: dist_to_enemy = d
			score += dist_to_enemy * 10
			for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var neighbor_unit = UnitManager.get_unit_at_cell(cell + dir)
				if neighbor_unit and neighbor_unit.unit_stats.team_id == unit.unit_stats.team_id:
					score += 5; break
			score -= _get_cell_danger_score(cell, unit)
			if score > best_score: best_score = score; best_cell = cell
		if best_cell != unit.grid_cell:
			var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
			if path.size() > 0: return {"type": "move", "unit": unit, "path": path}
		return null

	best_cell = unit.grid_cell
	best_score = -999
	var is_ranged := _is_ranged_unit(unit)
	var protected_ally : Unit = null
	if not is_ranged: protected_ally = _find_threatened_backliner(unit)

	var all_ally_cannot_attack = true
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id == unit.unit_stats.team_id and ally.hit_points > 0:
			if _can_attack_from_cell(ally, ally.grid_cell): all_ally_cannot_attack = false; break

	for cell in reachable.keys():
		var terrain_score : int = _terrain_score(cell)
		var score : int = 0
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor_unit = UnitManager.get_unit_at_cell(cell + dir)
			if neighbor_unit and neighbor_unit.unit_stats.team_id == unit.unit_stats.team_id:
				score += 5; break

		if is_ranged:
			if _can_attack_from_cell(unit, cell):
				score = 100 + int(terrain_score / 2.0)
				var nd := _nearest_enemy_dist(unit, cell)
				if nd < 999: score += nd * 25
			else:
				if all_ally_cannot_attack:
					var nd := _nearest_enemy_dist(unit, cell)
					if nd < 999: score = -nd * 10 + int(terrain_score / 2.0)
					else: score = -80 + int(terrain_score / 2.0)
				else: score = -80 + int(terrain_score / 2.0)
			var ally_dist := _nearest_ally_dist(unit, cell)
			if ally_dist < 999: score += maxi(-15, 10 - ally_dist * 3)
		else:
			score = terrain_score
			var dist_to_enemy = 999
			for p in UnitManager.unit_list:
				if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
					var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
					if d < dist_to_enemy: dist_to_enemy = d
			if dist_to_enemy <= 1: score += 120
			elif dist_to_enemy == 2: score += 60
			elif dist_to_enemy == 3: score += 20
			else: score -= (dist_to_enemy - 3) * 10

			var ally_dist := _nearest_ally_dist(unit, cell)
			if ally_dist < 999: score += maxi(0, 10 - ally_dist) * 10

			var enemies_around = 0
			var allies_around = 0
			for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n = UnitManager.get_unit_at_cell(cell + dir)
				if n:
					if n.unit_stats.team_id == unit.unit_stats.team_id: allies_around += 1
					else: enemies_around += 1
			if enemies_around > allies_around: score -= 40 * (enemies_around - allies_around)
			if _can_attack_from_cell(unit, cell): score += 50
			if protected_ally != null and is_instance_valid(protected_ally):
				var pa_dist : int = abs(cell.x - protected_ally.grid_cell.x) + abs(cell.y - protected_ally.grid_cell.y)
				if pa_dist <= 1: score += 60
				elif pa_dist == 2: score += 25

		if is_ranged: score -= _get_cell_danger_score(cell, unit)
		else: score -= int(_get_cell_danger_score(cell, unit) * 0.3)
		if score > best_score: best_score = score; best_cell = cell

	if best_cell != unit.grid_cell:
		var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
		if path.size() > 0: return {"type": "move", "unit": unit, "path": path}
	return null


func _find_threatened_backliner(unit: Unit) -> Unit:
	var wt = unit.get_weapon_type()
	if wt in ["bow", "crossbow", "staff", "spellbook"]: return null
	var best : Unit = null
	var best_score := 0.0
	for ally in UnitManager.unit_list:
		if not is_instance_valid(ally) or ally == unit or ally.unit_stats.team_id != unit.unit_stats.team_id or ally.hit_points <= 0: continue
		var awt = ally.get_weapon_type()
		if not (awt in ["bow", "crossbow", "staff", "spellbook"]): continue
		var hp_ratio := float(ally.hit_points) / float(max(1, ally.unit_stats.max_hp))
		if hp_ratio > 0.6: continue
		var covered := 0
		for enemy in UnitManager.unit_list:
			if not is_instance_valid(enemy) or enemy.unit_stats.team_id == unit.unit_stats.team_id or enemy.hit_points <= 0: continue
			var e_stats = enemy.unit_stats
			if not e_stats: continue
			var d : int = abs(ally.grid_cell.x - enemy.grid_cell.x) + abs(ally.grid_cell.y - enemy.grid_cell.y)
			if d >= e_stats.min_attack_range and d <= e_stats.attack_range: covered += 1
		if covered >= 2:
			var score := (1.0 - hp_ratio) * covered
			if score > best_score: best_score = score; best = ally
	return best


func _can_attack_from_cell(unit: Unit, cell: Vector2i) -> bool:
	var u_stats = unit.unit_stats
	if not u_stats: return false
	var max_range : int = u_stats.attack_range + unit.bonus_attack_range
	var min_range : int = u_stats.min_attack_range
	for enemy in UnitManager.unit_list:
		if enemy.unit_stats.team_id == unit.unit_stats.team_id or enemy.hit_points <= 0: continue
		var dist = abs(cell.x - enemy.grid_cell.x) + abs(cell.y - enemy.grid_cell.y)
		if dist >= min_range and dist <= max_range: return true
	return false


func _evaluate_survival_move(unit: Unit):
	var move_mv : int = unit.remaining_move
	if move_mv <= 0: return null
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, move_mv, unit)
	if reachable.is_empty(): return null

	var best_cell = unit.grid_cell
	var best_score = -999
	var orbs = ItemBattlefieldManager.get_active_orbs()
	if not orbs.is_empty():
		for cell in reachable.keys():
			if cell in orbs:
				var path = UnitManager.calculate_path(unit.grid_cell, cell, unit)
				if path.size() > 0: return {"type": "move", "unit": unit, "path": path}

	if _turn_manager != null:
		for cell in reachable.keys():
			if cell == unit.grid_cell: continue
			if _turn_manager.map_functions.has(cell):
				var cfg = _turn_manager.map_functions[cell]
				if cfg.has("event_id"):
					var event_id = cfg["event_id"]
					if EventManager.is_event_completed(event_id): continue
					var event_def = EventManager.get_event(event_id)
					if event_def.is_empty(): continue
					for action in event_def.get("actions", []):
						if action.get("type") == "heal" and action.get("amount", 0) > 0:
							var path = UnitManager.calculate_path(unit.grid_cell, cell, unit)
							if path.size() > 0: return {"type": "move", "unit": unit, "path": path}

	var healers = []
	for ally in UnitManager.unit_list:
		if ally.unit_stats.team_id == unit.unit_stats.team_id and ally != unit and ally.hit_points > 0 and ally.get_weapon_type() == "staff":
			healers.append(ally)
	if healers.size() > 0:
		var nearest_healer = healers[0]
		var min_dist = 999
		for h in healers:
			var d = abs(h.grid_cell.x - unit.grid_cell.x) + abs(h.grid_cell.y - unit.grid_cell.y)
			if d < min_dist: min_dist = d; nearest_healer = h
		var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		var target_cell = unit.grid_cell
		for d in dirs:
			var neighbor = nearest_healer.grid_cell + d
			if neighbor.x < 0 or neighbor.x >= TerrainManager.grid_size.x or neighbor.y < 0 or neighbor.y >= TerrainManager.grid_size.y: continue
			if not UnitManager.is_cell_occupied(neighbor) and reachable.has(neighbor): target_cell = neighbor; break
		if target_cell != unit.grid_cell:
			var path = UnitManager.calculate_path(unit.grid_cell, target_cell, unit)
			if path.size() > 0: return {"type": "move", "unit": unit, "path": path}
		else:
			best_cell = unit.grid_cell
			var best_dist = 999
			for cell in reachable.keys():
				var d = abs(cell.x - nearest_healer.grid_cell.x) + abs(cell.y - nearest_healer.grid_cell.y)
				if d < best_dist and not UnitManager.is_cell_occupied(cell): best_dist = d; best_cell = cell
			if best_cell != unit.grid_cell:
				var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
				if path.size() > 0: return {"type": "move", "unit": unit, "path": path}

	best_cell = unit.grid_cell
	best_score = -999
	for cell in reachable.keys():
		var terrain = TerrainManager.get_terrain(cell)
		var td : Dictionary = TerrainManager.TERRAIN_DATA.get(terrain, {})
		var score : int = int((float(td.get("physical_reduction", 0.0)) + float(td.get("magic_reduction", 0.0))) * 100.0)
		var dist_to_enemy = 999
		for p in UnitManager.unit_list:
			if p.unit_stats.team_id != unit.unit_stats.team_id and p.hit_points > 0:
				var d = abs(cell.x - p.grid_cell.x) + abs(cell.y - p.grid_cell.y)
				if d < dist_to_enemy: dist_to_enemy = d
		score += dist_to_enemy * 20
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor_unit = UnitManager.get_unit_at_cell(cell + dir)
			if neighbor_unit and neighbor_unit.unit_stats.team_id == unit.unit_stats.team_id: score += 5; break
		score -= _get_cell_danger_score(cell, unit)
		if score > best_score: best_score = score; best_cell = cell

	if best_cell != unit.grid_cell:
		var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
		if path.size() > 0: return {"type": "move", "unit": unit, "path": path}
	return null


func _find_best_move_to_target(unit: Unit, target_cell: Vector2i, min_range: int, max_range: int) -> Array:
	var move_mv : int = unit.remaining_move
	if move_mv <= 0: return []
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, move_mv, unit)
	var best_cell = unit.grid_cell
	var best_dist = -1
	var found = false
	for cell in reachable.keys():
		var dist = abs(cell.x - target_cell.x) + abs(cell.y - target_cell.y)
		if dist >= min_range and dist <= max_range:
			if not found or dist < best_dist:
				best_dist = dist; best_cell = cell; found = true
	if found and best_cell != unit.grid_cell: return UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
	return []

func _greedy_move_towards(unit: Unit, target_cell: Vector2i) -> Array:
	var move_mv : int = unit.remaining_move
	if move_mv <= 0: return []
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, move_mv, unit)
	if reachable.is_empty(): return []
	var best_cell = unit.grid_cell
	var best_dist = INF
	for cell in reachable.keys():
		if UnitManager.is_cell_occupied(cell): continue
		var dist = abs(cell.x - target_cell.x) + abs(cell.y - target_cell.y)
		if dist < best_dist: best_dist = dist; best_cell = cell
	if best_cell == unit.grid_cell: return []
	return UnitManager.calculate_path(unit.grid_cell, best_cell, unit)


func _retry_find_path(unit: Unit) -> Array:
	var move_mv : int = unit.remaining_move
	if move_mv <= 0: return []
	var reachable = UnitManager.get_reachable_cells(unit.grid_cell, move_mv, unit)
	if reachable.is_empty(): return []

	var best_cell = unit.grid_cell
	var best_score = -999999
	var has_candidate = false
	var is_ranged := _is_ranged_unit(unit)

	for cell in reachable.keys():
		if cell == unit.grid_cell or UnitManager.is_cell_occupied(cell): continue
		var nearest_enemy_dist : int = 9999
		for enemy in UnitManager.unit_list:
			if enemy.unit_stats.team_id == unit.unit_stats.team_id or enemy.hit_points <= 0: continue
			var d = abs(cell.x - enemy.grid_cell.x) + abs(cell.y - enemy.grid_cell.y)
			if d < nearest_enemy_dist: nearest_enemy_dist = d

		var score : int = 0
		if is_ranged:
			if _can_attack_from_cell(unit, cell): score = 1000 + nearest_enemy_dist * 15
			else: score = -nearest_enemy_dist * 5
		else: score = -nearest_enemy_dist * 10

		score += _terrain_score(cell) * 3
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor_unit = UnitManager.get_unit_at_cell(cell + dir)
			if neighbor_unit and neighbor_unit.unit_stats.team_id == unit.unit_stats.team_id: score += 5; break
		if score > best_score: best_score = score; best_cell = cell; has_candidate = true

	if not has_candidate or best_cell == unit.grid_cell: return []
	return UnitManager.calculate_path(unit.grid_cell, best_cell, unit)


func _process_ai_queue():
	while ai_queue.size() > 0:
		await get_tree().create_timer(0.25).timeout
		while Globals.is_dialogue_active:
			await get_tree().process_frame
			if not is_instance_valid(self) or _turn_manager == null or _turn_manager.is_game_over: return
		if _turn_manager.is_game_over or ai_queue.size() == 0: break

		var task = ai_queue.pop_front()
		var unit = task["unit"]
		if not is_instance_valid(unit) or unit.hit_points <= 0: continue

		if task.has("phase_version") and int(task["phase_version"]) != int(unit.get_meta("boss_phase_version", 0)):
			var new_action = _decide_action(unit)
			if new_action and new_action["type"] != "wait":
				new_action["phase_version"] = int(unit.get_meta("boss_phase_version", 0))
				ai_queue.push_front(new_action)
			continue

		match task["type"]:
			"attack":
				var target = task["target"]
				if not is_instance_valid(target) or target.hit_points <= 0:
					var new_action = _decide_action(unit)
					if new_action and new_action["type"] != "wait":
						new_action["phase_version"] = int(unit.get_meta("boss_phase_version", 0))
						ai_queue.push_front(new_action)
					continue
				if target != unit: pass
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
					if path.size() == 0 or UnitManager.is_cell_occupied(path[-1]): continue
				_turn_manager.start_ai_movement(unit, path)
				await _turn_manager.move_completed
			"wait":
				unit.can_act_this_turn = false
				unit.set_gray(true)

	for u in UnitManager.unit_list:
		if is_instance_valid(u) and u.unit_stats.team_id == 1:
			u.taunt_rounds_left = 0
			u.taunt_by = null

	_processing = false
	ai_queue_finished.emit()


func _on_move_completed():
	pass

func clear_state():
	ai_queue.clear()
	_processing = false
	first_ai_unit = null


func _pick_target_by_weight(candidates: Array) -> Dictionary:
	var top_score : int = -999999
	for c in candidates:
		if c["score"] > top_score: top_score = c["score"]

	var finalists : Array = []
	for c in candidates:
		if c["score"] >= top_score - AI_SCORE_TOLERANCE: finalists.append(c)

	if finalists.size() == 1: return finalists[0]

	var total_weight : int = 0
	for f in finalists: total_weight += maxi(1, f["score"] + AI_WEIGHT_OFFSET)

	var roll : int = randi() % total_weight
	var acc : int = 0
	for f in finalists:
		acc += maxi(1, f["score"] + AI_WEIGHT_OFFSET)
		if acc > roll: return f
	return finalists[0]


func _evaluate_taunt_attack(unit: Unit, taunter: Unit) -> Dictionary:
	var u_stats = unit.unit_stats
	if not u_stats: return {}

	var dist = abs(unit.grid_cell.x - taunter.grid_cell.x) + abs(unit.grid_cell.y - taunter.grid_cell.y)
	var min_range = u_stats.min_attack_range
	var max_range = u_stats.attack_range

	if dist >= min_range and dist <= max_range:
		return {"type": "attack", "unit": unit, "target": taunter, "weapon_id": unit.get_equipped_weapon_id()}

	var path = _find_best_move_to_target(unit, taunter.grid_cell, min_range, max_range)
	if path.size() > 0: return {"type": "move", "unit": unit, "path": path}

	var greedy = _greedy_move_towards(unit, taunter.grid_cell)
	if greedy.size() > 0: return {"type": "move", "unit": unit, "path": greedy}
	return {}
