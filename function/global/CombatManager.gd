extends Node

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

const PERFORMANCE_DURATION : float = 0.5

func get_attackable_targets(unit: Unit) -> Array:
	var weapon_data = unit.get_weapon_data()
	if not weapon_data: return []
	var max_range = weapon_data.attack_range
	var min_range = weapon_data.min_attack_range
	var is_healer = weapon_data.stats.get("heal_amount", 0) > 0
	
	var targets = []
	for x in range(-max_range, max_range+1):
		for y in range(-max_range, max_range+1):
			var dist = abs(x) + abs(y)
			if dist < min_range or dist > max_range:
				continue
			var cell = unit.grid_cell + Vector2i(x, y)
			if cell.x < 0 or cell.x >= TerrainManager.grid_size.x or cell.y < 0 or cell.y >= TerrainManager.grid_size.y:
				continue
			var target = UnitManager.get_unit_at_cell(cell)
			if not target or target.hit_points <= 0:
				continue
			if is_healer:
				# 治疗只能对己方单位
				if target.unit_stats.team_id == unit.unit_stats.team_id:
					targets.append(target)
			else:
				# 攻击只能对敌方单位
				if target.unit_stats.team_id != unit.unit_stats.team_id:
					targets.append(target)

	# 排序：治疗按受伤程度降序，攻击按距离升序
	if is_healer:
		targets.sort_custom(func(a, b):
			var loss_a = a.unit_stats.max_hp - a.hit_points
			var loss_b = b.unit_stats.max_hp - b.hit_points
			return loss_a > loss_b
		)
	else:
		targets.sort_custom(func(a, b):
			var da = abs(a.grid_cell.x - unit.grid_cell.x) + abs(a.grid_cell.y - unit.grid_cell.y)
			var db = abs(b.grid_cell.x - unit.grid_cell.x) + abs(b.grid_cell.y - unit.grid_cell.y)
			return da < db
		)
	return targets

func attempt_attack_after_move(unit: Unit):
	var targets = get_attackable_targets(unit)
	if targets.size() > 0:
		await execute_attack(unit, targets[0])

# ---- 命中率计算 ----
func calculate_hit_rate(attacker: Unit, defender: Unit) -> int:
	var hit = attacker.unit_stats.skill * 2 + attacker.unit_stats.luck
	var weapon_hit = UnitDataManagerClass.WEAPON_HIT.get(attacker.get_weapon_type(), 0)
	hit += weapon_hit
	var avoid = defender.unit_stats.speed * 2 + defender.unit_stats.luck
	var hit_rate = hit - avoid
	hit_rate = clamp(hit_rate, 1, 99)
	return hit_rate

# ---- 暴击率计算 ----
func calculate_crit_rate(attacker: Unit) -> int:
	var crit = int(attacker.unit_stats.skill / 2.0)
	var weapon_crit = UnitDataManagerClass.WEAPON_CRIT.get(attacker.get_weapon_type(), 0)
	crit += weapon_crit
	crit = clamp(crit, 0, 100)
	return crit

# ---- 伤害计算（含相克和特效） ----
func calculate_damage(attacker: Unit, defender: Unit) -> int:
	var weapon_stats = attacker.get_weapon_stats()
	var atk = 0
	var def = 0
	
	# 安全获取攻击属性
	var attack_val = weapon_stats.get("attack", 0)
	var magic_attack_val = weapon_stats.get("magic_attack", 0)
	
	# 判断攻击类型
	if magic_attack_val > 0:
		atk = attack_val + magic_attack_val
		var def_terrain = TerrainManager.get_terrain(defender.grid_cell)
		var def_bonus = TerrainManager.TERRAIN_DATA[def_terrain]["def_bonus"]
		def = defender.unit_stats.magic_defense + def_bonus
	else:
		atk = attack_val
		var def_terrain = TerrainManager.get_terrain(defender.grid_cell)
		var def_bonus = TerrainManager.TERRAIN_DATA[def_terrain]["def_bonus"]
		def = defender.unit_stats.defense + def_bonus

	# 武器相克（保持不变）
	var aw = attacker.get_weapon_type()
	var dw = defender.get_weapon_type()
	var bonus = 0
	if aw in [UnitDataManagerClass.WEAPON_SWORD, UnitDataManagerClass.WEAPON_SPEAR, UnitDataManagerClass.WEAPON_AXE]:
		if aw == UnitDataManagerClass.WEAPON_SWORD and dw == UnitDataManagerClass.WEAPON_AXE: bonus = 2
		elif aw == UnitDataManagerClass.WEAPON_AXE and dw == UnitDataManagerClass.WEAPON_SPEAR: bonus = 2
		elif aw == UnitDataManagerClass.WEAPON_SPEAR and dw == UnitDataManagerClass.WEAPON_SWORD: bonus = 2
		elif aw == UnitDataManagerClass.WEAPON_AXE and dw == UnitDataManagerClass.WEAPON_SWORD: bonus = -2
		elif aw == UnitDataManagerClass.WEAPON_SWORD and dw == UnitDataManagerClass.WEAPON_SPEAR: bonus = -2
		elif aw == UnitDataManagerClass.WEAPON_SPEAR and dw == UnitDataManagerClass.WEAPON_AXE: bonus = -2

	# 特效：弓克飞马
	var effective = 1
	if aw == UnitDataManagerClass.WEAPON_BOW and defender.unit_stats.unit_name == "飞马":
		effective = 2
		print("弓对飞行单位特效！")

	var damage = (atk + bonus) * effective - def
	if damage < 0: damage = 0
	return damage

# 核心攻击函数
func execute_attack(attacker: Unit, defender: Unit) -> bool:
	# 检查攻击者当前装备武器是否可用
	if attacker.get_equipped_weapon_id() == "":
		print("错误：攻击者没有装备武器")
		Globals.is_performing_action = false
		return false
		
	# 设置朝向
	_face_each_other(attacker, defender)
	
	Globals.is_performing_action = true
	print(attacker.unit_stats.unit_name + " 攻击 " + defender.unit_stats.unit_name)
	
	# ---- 治疗分支 ----
	if attacker.get_weapon_type() == UnitDataManagerClass.WEAPON_HEAL:
		if defender.unit_stats.team_id != attacker.unit_stats.team_id:
			print("错误：修女不能攻击敌方！")
			Globals.is_performing_action = false
			return false
		var heal_amount = attacker.get_weapon_stats()["heal_amount"]
		if heal_amount <= 0:
			print("警告：治疗武器治疗量为0")
		var old_hp = defender.hit_points
		defender.hit_points = min(defender.hit_points + heal_amount, defender.unit_stats.max_hp)
		var actual_heal = defender.hit_points - old_hp
		print("治疗 ", actual_heal, " 点 HP (", old_hp, " → ", defender.hit_points, ")")
		defender.update_hp_label()
		SignalBus.request_damage_popup.emit(defender.global_position, actual_heal, false, false, true)
		SoundManager.play_heal_sound()
		await get_tree().create_timer(PERFORMANCE_DURATION).timeout
		attacker.mark_attacked()
		_show_menu_after_action(attacker)
		Globals.is_performing_action = false
		return false

	# ---- 命中判定 ----
	var hit_rate = calculate_hit_rate(attacker, defender)
	print("命中率: ", hit_rate, "%")
	var is_hit = (randf() * 100 <= hit_rate)

	if not is_hit:
		print("攻击未命中！")
		# 受击效果（未命中）
		var miss_dir = (defender.global_position - attacker.global_position).normalized()
		defender.play_hit_effect(miss_dir, false)
		
		SignalBus.request_damage_popup.emit(defender.global_position, 0, false, true, false)
		SoundManager.play_miss_sound()
		await get_tree().create_timer(PERFORMANCE_DURATION).timeout
		attacker.mark_attacked()
		_show_menu_after_action(attacker)
		Globals.is_performing_action = false
		return false

	SoundManager.play_hit_sound()

	# ---- 伤害计算 ----
	var damage = calculate_damage(attacker, defender)
	print("基础伤害: ", damage)

	# ---- 暴击判定 ----
	var crit_rate = calculate_crit_rate(attacker)
	print("暴击率: ", crit_rate, "%")
	var is_crit = (randf() * 100 <= crit_rate)
	if is_crit:
		damage *= 2
		print("暴击！")

	# 受击效果（命中）已在之前计算 hit_dir
	var hit_dir = (defender.global_position - attacker.global_position).normalized()
	defender.play_hit_effect(hit_dir, true)

	# ---- 显示反馈 ----
	var shake_intensity = 4.0
	if is_crit:
		shake_intensity = 10.0
	SignalBus.request_damage_popup.emit(defender.global_position, damage, is_crit, false, false)
	SignalBus.request_screen_shake.emit(0.15, shake_intensity, hit_dir)   # 传入方向

	await get_tree().create_timer(PERFORMANCE_DURATION).timeout

	# ---- 应用伤害 ----
	var defeated = defender.apply_damage(damage)
	if defeated:
		print(defender.unit_stats.unit_name + " 阵亡！")
		UnitManager.unregister_unit(defender)
		defender.queue_free()
		attacker.mark_attacked()
		if attacker.remaining_move > 0 or not attacker.can_move():
			_show_menu_after_action(attacker)
		else:
			TurnManager.finish_unit_action(attacker)
		Globals.is_performing_action = false
		return true

	# ---- 反击判定 ----
	var def_weapon_type = defender.get_weapon_type()
	if def_weapon_type != UnitDataManagerClass.WEAPON_HEAL:
		var defender_weapon = defender.get_weapon_data()
		var def_min_range = defender_weapon.min_attack_range if defender_weapon else 0
		var def_max_range = defender_weapon.attack_range if defender_weapon else 0
		var dist = abs(defender.grid_cell.x - attacker.grid_cell.x) + abs(defender.grid_cell.y - attacker.grid_cell.y)
		if dist >= def_min_range and dist <= def_max_range:
			print(defender.unit_stats.unit_name + " 反击!")
			var counter_hit_rate = calculate_hit_rate(defender, attacker)
			print("反击命中率: ", counter_hit_rate, "%")
			var counter_is_hit = (randf() * 100 <= counter_hit_rate)

			if counter_is_hit:
				SoundManager.play_hit_sound()
				var counter_damage = calculate_damage(defender, attacker)
				var counter_crit_rate = calculate_crit_rate(defender)
				var counter_is_crit = (randf() * 100 <= counter_crit_rate)
				if counter_is_crit:
					counter_damage *= 2
					print("反击暴击！")
				# 反击受击效果（命中）已在之前计算 counter_hit_dir
				var counter_hit_dir = (attacker.global_position - defender.global_position).normalized()
				attacker.play_hit_effect(counter_hit_dir, true)

				var counter_shake = 4.0
				if counter_is_crit:
					counter_shake = 10.0
				SignalBus.request_damage_popup.emit(attacker.global_position, counter_damage, counter_is_crit, false, false)
				SignalBus.request_screen_shake.emit(0.15, counter_shake, counter_hit_dir)   # 传入方向
				await get_tree().create_timer(PERFORMANCE_DURATION).timeout
				var attacker_dead = attacker.apply_damage(counter_damage)
				if attacker_dead:
					print(attacker.unit_stats.unit_name + " 阵亡！")
					UnitManager.unregister_unit(attacker)
					attacker.queue_free()
					Globals.is_performing_action = false
					return true
			else:
				SoundManager.play_miss_sound()
				# 反击未命中受击效果
				var counter_miss_dir = (attacker.global_position - defender.global_position).normalized()
				attacker.play_hit_effect(counter_miss_dir, false)
				
				SignalBus.request_damage_popup.emit(attacker.global_position, 0, false, true, false)
				await get_tree().create_timer(PERFORMANCE_DURATION).timeout
				print("反击未命中")

	# 标记攻击者已攻击
	attacker.mark_attacked()
	_show_menu_after_action(attacker)
	Globals.is_performing_action = false
	return false

# ---- 行动后菜单 ----
func _show_menu_after_action(unit: Unit):
	if TurnManager.current_turn_team != 0:
		return
	# 只有玩家单位才能触发菜单（防止敌方异步调用）
	if unit.unit_stats.team_id != 0:
		return
	print("行动后显示菜单: ", unit.unit_stats.unit_name)
	print("当前剩余移动: ", unit.remaining_move)
	if unit.remaining_move < 0:
		unit.remaining_move = 0
	InputManager.selected_unit = unit
	InputManager.interaction_phase = "menu"
	SignalBus.request_show_menu.emit(unit)

# ---- 新增：攻击双方互相面向 ----
func _face_each_other(attacker: Unit, defender: Unit):
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	var dir = defender.grid_cell - attacker.grid_cell
	if dir.x != 0:
		# 攻击者面向目标方向（水平）
		attacker.set_facing_direction(Vector2(sign(dir.x), 0))
		# 防御者面向攻击者（反向）
		defender.set_facing_direction(Vector2(-sign(dir.x), 0))
	# 若水平方向为0（上下攻击），则不改变朝向（保持当前）

func get_unit_attack_stats(unit: Unit) -> Dictionary:
	var weapon = unit.get_weapon_data()
	if weapon and weapon.type == "weapon":
		return {
			"attack": weapon.stats.get("attack", 0),
			"magic_attack": weapon.stats.get("magic_attack", 0),
			"heal_amount": weapon.stats.get("heal_amount", 0),
			"attack_range": weapon.attack_range,
			"min_attack_range": weapon.min_attack_range
		}
	else:
		return {
			"attack": 0,
			"magic_attack": 0,
			"heal_amount": 0,
			"attack_range": 0,
			"min_attack_range": 0
		}
