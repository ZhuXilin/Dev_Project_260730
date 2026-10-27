class_name PowerEvaluator
extends RefCounted

# 战力评估：
#   - 每个单位的"基础战力"= HP + (力量 + 灵巧 + 智力 + 信仰) × 3
#   - 玩家总战力再叠加武器攻击、防具减伤、词条加成、等级
#   - 敌人总战力再乘以节点类型的 HP 倍率（ELITE ×1.5 / BOSS 杂兵 ×1.2）
#   - 星级 = 敌人总战力 / 玩家总战力 的比值映射

static func unit_power(unit_name: String) -> int:
	var d = UnitDataManager.get_unit_data(unit_name)
	if d.is_empty(): return 0
	var hp := int(d.get("max_hp", 20))
	var str_ := int(d.get("strength", 5))
	var dex := int(d.get("dexterity", 5))
	var int_ := int(d.get("intelligence", 3))
	var faith := int(d.get("faith", 3))
	return hp + (str_ + dex + int_ + faith) * 3

static func player_party_power() -> int:
	var total := 0
	for ud in GameState.party:
		if ud.is_dead: continue
		var power := unit_power(ud.unit_name)

		if ud.weapon_slot:
			var wd = ItemManager.get_item_data(ud.weapon_slot.item_id)
			if wd:
				power += wd.base_attack * 5
				power += ud.weapon_slot.upgrade_level * 20

		for slot in ud.armor_slots:
			if slot:
				var ad = ItemManager.get_item_data(slot.item_id)
				if ad:
					power += int((ad.physical_reduction + ad.magic_reduction) * 100) * 3

		power = int(power * (1.0 + (ud.level - 1) * 0.1))
		total += power
	return total

static func evaluate_map_node(map_data: MapData) -> Dictionary:
	if map_data == null or map_data.scene == null:
		return _empty_result()

	var scene_inst = map_data.scene.instantiate()
	if scene_inst == null:
		return _empty_result()

	var pool_map: Dictionary = {}
	_collect_pools(scene_inst, pool_map)

	var acc: Array = [0]
	_eval_node(scene_inst, pool_map, acc)

	# 节点类型 HP 倍率（与 UnitSpawner._create_unit_stats 对齐）
	var type_mult := 1.0
	match map_data.node_type:
		MapNode.NodeType.ELITE: type_mult = 1.5
		MapNode.NodeType.BOSS:  type_mult = 1.2
		_: type_mult = 1.0
	var extra_hp := maxf(1.0, map_data.enemy_hp_multiplier)
	var enemy_power := int(acc[0] * type_mult * extra_hp)

	scene_inst.queue_free()

	var party_power := player_party_power()
	var ratio := float(enemy_power) / maxf(1.0, float(party_power))
	var grade := _ratio_to_grade(ratio)
	return {
		"enemy_power": enemy_power,
		"party_power": party_power,
		"ratio": ratio,
		"stars": grade.stars,
		"label": grade.label,
	}

static func _collect_pools(node: Node, pool_map: Dictionary):
	if node is UnitPlacerTool and node.placement_mode == UnitPlacerTool.PlacementMode.RANDOM_POOL:
		if node.pool_key != "" and not node.enemy_pool.is_empty():
			if not pool_map.has(node.pool_key):
				pool_map[node.pool_key] = node.enemy_pool.duplicate()
	for child in node.get_children():
		_collect_pools(child, pool_map)

static func _eval_node(node: Node, pool_map: Dictionary, acc: Array):
	if node is UnitPlacerTool:
		var cfg = node.export_config()
		if cfg is UnitConfig:
			if cfg.team_id == 1:   # 只统计敌人
				if cfg.is_random_pool:
					acc[0] += _eval_random_pool(cfg, pool_map)
				else:
					var p := unit_power(cfg.unit_name)
					if cfg.is_boss:
						p *= 2   # Boss 本体战力 ×2
					acc[0] += p
	for child in node.get_children():
		_eval_node(child, pool_map, acc)

static func _eval_random_pool(cfg: UnitConfig, pool_map: Dictionary) -> int:
	var pool: Array = []
	if cfg.pool_key != "" and pool_map.has(cfg.pool_key):
		pool = pool_map[cfg.pool_key]
	elif not cfg.enemy_pool.is_empty():
		pool = cfg.enemy_pool
	if pool.is_empty(): return 0
	var total := 0
	for u in pool:
		total += unit_power(u)
	return int(float(total) / float(pool.size()))

static func _ratio_to_grade(ratio: float) -> Dictionary:
	if ratio < 0.6:  return {"stars": 1, "label": "简单"}
	if ratio < 0.9:  return {"stars": 2, "label": "普通"}
	if ratio < 1.2:  return {"stars": 3, "label": "挑战"}
	if ratio < 1.6:  return {"stars": 4, "label": "困难"}
	return {"stars": 5, "label": "绝望"}

static func _empty_result() -> Dictionary:
	return {"enemy_power": 0, "party_power": 0, "ratio": 0.0, "stars": 0, "label": "未知"}

static func format_stars(stars: int) -> String:
	return "★".repeat(clampi(stars, 0, 5)) + "☆".repeat(clampi(5 - stars, 0, 5))
