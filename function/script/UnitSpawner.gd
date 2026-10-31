extends Node
class_name UnitSpawner

const UNIT_PATH = Config.PATHS.UNIT_SCENE

# ============================================================
#  单位强度倍率总开关（当前关闭：仅靠数量与类型做强度）
# ============================================================
const ENABLE_STRENGTH_MULTIPLIERS : bool = false
const BOSS_HP_MULT : float = 2.0
const ELITE_SCRUB_HP_MULT : float = 1.5
const BOSS_SCRUB_HP_MULT : float = 1.2
const DAY_ATTR_MULT : Dictionary = {1: 0.8, 2: 1.0, 3: 1.2}


# ============================================================
#  倍率查询
# ============================================================
static func get_enemy_hp_mult(node_type: int, is_boss: bool) -> float:
	if not ENABLE_STRENGTH_MULTIPLIERS:
		return 1.0
	if is_boss:
		return BOSS_HP_MULT
	match node_type:
		MapNode.NodeType.ELITE: return ELITE_SCRUB_HP_MULT
		MapNode.NodeType.BOSS:  return BOSS_SCRUB_HP_MULT
	return 1.0

static func get_enemy_hp_extra() -> float:
	if not ENABLE_STRENGTH_MULTIPLIERS:
		return 1.0
	if GameState.current_map_data == null:
		return 1.0
	return maxf(1.0, GameState.current_map_data.enemy_hp_multiplier)

static func get_day_attr_mult(day: int) -> float:
	if not ENABLE_STRENGTH_MULTIPLIERS:
		return 1.0
	return float(DAY_ATTR_MULT.get(day, 1.0))


# ============================================================
#  配置提取
# ============================================================
static func extract_configs_from_node(node: Node) -> Array[UnitConfig]:
	var configs: Array[UnitConfig] = []
	_find_unit_placers(node, configs)
	return configs


static func _find_unit_placers(node: Node, configs: Array[UnitConfig]):
	if node is UnitPlacerTool:
		var mode : int = node.placement_mode
		if mode == UnitPlacerTool.PlacementMode.FIXED_UNIT \
				or mode == UnitPlacerTool.PlacementMode.RANDOM_POOL:
			configs.append(node.export_config())
	for child in node.get_children():
		_find_unit_placers(child, configs)


# ============================================================
#  池条目解析
#  支持：
#    "swordsman"                      → {base="swordsman", adv=""}
#    "swordsman:swordsman_berserker"  → {base="swordsman", adv="swordsman_berserker"}
#    "@swordsman_berserker"           → {base="swordsman", adv="swordsman_berserker"}
#    "@swordsman"                     → {base="swordsman", adv=""}（容错）
# ============================================================
static func parse_pool_entry(entry: String) -> Dictionary:
	var s : String = entry.strip_edges()
	if s == "":
		return {"base": "", "adv": ""}

	if s.begins_with("@"):
		var adv_id : String = s.substr(1).strip_edges()
		if adv_id == "":
			return {"base": "", "adv": ""}
		var adv = AdvancedClassManager.get_class_data(adv_id)
		if adv != null and adv.base_unit != "":
			return {"base": adv.base_unit, "adv": adv_id}
		var fallback : String = UnitDataManager.normalize_unit_key(adv_id)
		push_warning("[UnitSpawner] 未知进阶 id: @%s（回退为基础单位 %s）" % [adv_id, fallback])
		return {"base": fallback, "adv": ""}

	if s.contains(":"):
		var parts : PackedStringArray = s.split(":", false, 1)
		if parts.size() == 2:
			var base : String = UnitDataManager.normalize_unit_key(parts[0].strip_edges())
			var adv_id2 : String = parts[1].strip_edges()
			return {"base": base, "adv": adv_id2}

	return {"base": UnitDataManager.normalize_unit_key(s), "adv": ""}


# ============================================================
#  随机池
# ============================================================
static func _build_pool_map(configs: Array[UnitConfig]) -> Dictionary:
	var pool_map : Dictionary = {}
	for cfg in configs:
		if not cfg.is_random_pool: continue
		if cfg.pool_key == "": continue
		if pool_map.has(cfg.pool_key): continue
		if not cfg.enemy_pool.is_empty():
			pool_map[cfg.pool_key] = cfg.enemy_pool.duplicate()
	return pool_map


static func _get_pool_for_config(cfg: UnitConfig, pool_map: Dictionary) -> Array:
	if cfg.pool_key != "" and pool_map.has(cfg.pool_key):
		return pool_map[cfg.pool_key]
	if not cfg.enemy_pool.is_empty():
		return cfg.enemy_pool
	return []


static func _roll_enemy_for_config(cfg: UnitConfig, pool_map: Dictionary) -> Dictionary:
	var pool : Array = _get_pool_for_config(cfg, pool_map)
	if pool.is_empty():
		push_warning("[UnitSpawner] RANDOM_POOL 格子没有可用池子，pos=%s pool_key=%s" % [
			str(cfg.position), cfg.pool_key])
		return {}
	var entry : String = str(pool[randi() % pool.size()])
	return parse_pool_entry(entry)


# ============================================================
#  进阶职业应用
# ============================================================
static func _apply_advanced_class(stats: UnitData, adv_id: String) -> void:
	if adv_id == "": return
	var adv = AdvancedClassManager.get_class_data(adv_id)
	if adv == null:
		push_warning("[UnitSpawner] 未知进阶职业: " + adv_id)
		return

	if adv.standalone_unit_id != "":
		var standalone : Dictionary = UnitDataManager.get_unit_data(adv.standalone_unit_id)
		if not standalone.is_empty():
			stats.max_hp = int(standalone.get("max_hp", stats.max_hp))
			stats.hit_points = stats.max_hp
			stats.strength = int(standalone.get("strength", stats.strength))
			stats.dexterity = int(standalone.get("dexterity", stats.dexterity))
			stats.intelligence = int(standalone.get("intelligence", stats.intelligence))
			stats.faith = int(standalone.get("faith", stats.faith))
			stats.arcane = int(standalone.get("arcane", stats.arcane))
			stats.move_range = int(standalone.get("move_range", stats.move_range))
			stats.core_trait = str(standalone.get("core_trait", stats.core_trait))
			var s_tags : Variant = standalone.get("tags", [])
			if s_tags is Array:
				stats.tags.clear()
				for t in s_tags:
					if t is String: stats.tags.append(t)
		else:
			push_warning("[UnitSpawner] standalone_unit_id 指向的条目不存在: " + adv.standalone_unit_id)
	else:
		for key in adv.stat_bonus:
			var val : int = int(adv.stat_bonus[key])
			match key:
				"max_hp":
					stats.max_hp += val
					stats.hit_points += val
				"strength":     stats.strength += val
				"dexterity":    stats.dexterity += val
				"intelligence": stats.intelligence += val
				"faith":        stats.faith += val
				"arcane":       stats.arcane += val
				"move_range":   stats.move_range += val
		if not adv.tags.is_empty():
			stats.tags.clear()
			for t in adv.tags:
				stats.tags.append(t)

	if adv.granted_talent != "":
		stats.advanced_talent_id = adv.granted_talent
	if adv.sprite_frames_path != "":
		stats.override_sprite_path = adv.sprite_frames_path
	stats.advanced_class = adv.id


# ============================================================
#  ★ 生成单位（已彻底移除 initial_items）
# ============================================================
static func spawn_units_from_configs(parent: Node, configs: Array[UnitConfig], grid_to_world_func: Callable):
	var pool_map : Dictionary = _build_pool_map(configs)

	for cfg in configs:
		var base_name : String = cfg.unit_name
		var adv_id : String = ""

		if cfg.is_random_pool:
			var picked : Dictionary = _roll_enemy_for_config(cfg, pool_map)
			if picked.is_empty(): continue
			base_name = str(picked.get("base", ""))
			adv_id = str(picked.get("adv", ""))
			if base_name == "": continue
		else:
			adv_id = cfg.advanced_class_id

		var stats = _create_unit_stats(cfg, base_name, adv_id)
		if stats == null: continue

		var unit = load(UNIT_PATH).instantiate()
		# ★ 只传两个参数，去掉 initial_items
		unit.setup_unit(stats, cfg.position)
		unit.set_meta("wave", cfg.wave)
		parent.add_child(unit)
		unit.position = grid_to_world_func.call(cfg.position)
		UnitManager.register_unit(unit)


static func _create_unit_stats(cfg: UnitConfig, base_name: String, adv_id: String) -> UnitData:
	var name_key : String = base_name if base_name != "" else cfg.unit_name
	var stats = UnitDataManager.get_default_stats(name_key)
	stats.unit_name = name_key

	if cfg.is_random_pool:
		stats.display_name = name_key
	else:
		stats.display_name = cfg.display_name if cfg.display_name != "" else name_key

	stats.faction = cfg.faction
	cfg.apply_override(stats)
	stats.team_id = cfg.team_id
	stats.is_boss = cfg.is_boss
	if cfg.immobile and cfg.team_id == 1:
		stats.move_range = 0

	# 默认武器继承
	var default_weapon_id : String = UnitDataManager.get_default_weapon_id(name_key)
	if default_weapon_id != "":
		var w_inst := ItemInstance.new()
		w_inst.item_id = default_weapon_id
		w_inst.count = 1
		w_inst.upgrade_level = 0
		stats.weapon_slot = w_inst

	# 进阶职业
	if adv_id != "":
		_apply_advanced_class(stats, adv_id)
		if cfg.is_random_pool or cfg.display_name == "":
			var adv = AdvancedClassManager.get_class_data(adv_id)
			if adv != null and adv.name != "":
				stats.display_name = adv.name

	# 头像覆盖
	if cfg.avatar_override != "":
		stats.avatar_override = cfg.avatar_override

	# 敌方强化
	if cfg.team_id == 1 and GameState.current_map_data != null:
		var node_type : int = GameState.current_map_data.node_type
		var mult : float = get_enemy_hp_mult(node_type, cfg.is_boss)
		var extra_hp : float = get_enemy_hp_extra()
		stats.max_hp = int(stats.max_hp * mult * extra_hp)
		stats.hit_points = stats.max_hp
		var day_mult : float = get_day_attr_mult(GameState.current_day)
		stats.strength = maxi(1, int(stats.strength * day_mult))
		stats.dexterity = maxi(1, int(stats.dexterity * day_mult))

	return stats


# ============================================================
#  测试单位 / 玩家队伍（不变）
# ============================================================
static func spawn_test_units(parent: Node, grid_to_world_func: Callable):
	var configs: Array[UnitConfig] = []
	var p1 = UnitConfig.new(); p1.unit_name = "剑士"; p1.team_id = 0; p1.position = Vector2i(15, 10); configs.append(p1)
	var p2 = UnitConfig.new(); p2.unit_name = "枪兵"; p2.team_id = 0; p2.position = Vector2i(15, 11); configs.append(p2)
	var e1 = UnitConfig.new(); e1.unit_name = "枪兵"; e1.team_id = 1; e1.position = Vector2i(3, 3); configs.append(e1)
	var e2 = UnitConfig.new(); e2.unit_name = "斧兵"; e2.team_id = 1; e2.position = Vector2i(3, 4); configs.append(e2)
	spawn_units_from_configs(parent, configs, grid_to_world_func)


static func spawn_party_from_gamestate(parent: Node, grid_to_world_func: Callable, spawn_points: Array[Vector2i]):
	var party = GameState.get_party_units()
	var alive : Array = []
	for u in party:
		if not u.is_dead: alive.append(u)
	var count = min(alive.size(), spawn_points.size())
	if alive.is_empty():
		print("[UnitSpawner] 警告：全队阵亡，无法生成单位")
		return

	for i in range(count):
		var unit_data = alive[i]
		var spawn_cell = spawn_points[i]
		unit_data.hit_points = unit_data.max_hp
		var unit = load(UNIT_PATH).instantiate()
		unit.restore_from_unit_data(unit_data, spawn_cell)
		parent.add_child(unit)
		unit.position = grid_to_world_func.call(spawn_cell)
		UnitManager.register_unit(unit)
