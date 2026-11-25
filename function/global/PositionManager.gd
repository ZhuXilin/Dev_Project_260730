class_name PositionManager
extends RefCounted

## ============================================================
##  PositionManager — 位置后果统一查询（v6.68）
## ============================================================
##  夹击 / 危险地形 / ZOC 的纯查询层：Config 只读，不改战斗状态。
##  · 夹击：目标四周（上下左右）攻击者阵营的存活单位数 ≥ min_allies 即成立，
##    不依赖朝向（v6.59 移除阵型后仍自洽），单核阵容自然无法夹击。
##  · 危险地形：灰烬地块作为危险地块，被推入时额外伤害；不在这里结算伤害。
##  · ZOC：守护身份（重甲 / 守护剑卫）对四周格产生控制区；进入即停、
##    处于控制区无法离开。飞行单位（ignore_terrain_cost）可无视。
##  数据源：content/data/config/soulfire_identity.json 的 position 段。
##  位置后果伤害一律 trigger_abnormal=false（由调用方保证）。
## ============================================================

const CFG_FILE: String = "soulfire_identity.json"
const ORTHO: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func get_config() -> Dictionary:
	var raw: Variant = GameConfigManager.get_value(CFG_FILE, "position", null)
	return raw as Dictionary if raw is Dictionary else {}


static func flanking_config() -> Dictionary:
	var raw: Variant = get_config().get("flanking", null)
	return raw as Dictionary if raw is Dictionary else {}


static func danger_config() -> Dictionary:
	var raw: Variant = get_config().get("danger_terrain", null)
	return raw as Dictionary if raw is Dictionary else {}


static func zoc_config() -> Dictionary:
	var raw: Variant = get_config().get("zoc", null)
	return raw as Dictionary if raw is Dictionary else {}


# ============================================================
#  夹击
# ============================================================

static func flanking_enabled() -> bool:
	return bool(flanking_config().get("enabled", true))


## 目标四周属于 attacker 阵营的存活单位数（attacker 本人若贴身也算 1 个）。
static func allies_adjacent_to(target: Unit, attacker: Unit) -> int:
	if not flanking_enabled():
		return 0
	if not is_instance_valid(target) or not is_instance_valid(attacker):
		return 0
	if target.unit_stats == null or attacker.unit_stats == null:
		return 0
	var count: int = 0
	for d in ORTHO:
		var u: Unit = UnitManager.get_unit_at_cell(target.grid_cell + d)
		if u == null or not is_instance_valid(u) or u.hit_points <= 0:
			continue
		if u.unit_stats == null:
			continue
		if u.unit_stats.team_id == attacker.unit_stats.team_id:
			count += 1
	return count


static func is_flanked(target: Unit, attacker: Unit) -> bool:
	var need: int = maxi(1, int(flanking_config().get("min_allies", 2)))
	return allies_adjacent_to(target, attacker) >= need


## 主伤害加成系数（0 表示未夹击）。只给主伤害调用方使用，避免溅射/AOE 重复吃。
static func flanking_bonus(attacker: Unit, target: Unit) -> float:
	if not is_flanked(target, attacker):
		return 0.0
	return maxf(0.0, float(flanking_config().get("damage_bonus", 0.15)))


static func flanking_denies_counter() -> bool:
	return bool(flanking_config().get("no_counter", true))


static func flanking_hint() -> String:
	return str(flanking_config().get("hint", "夹击！"))


# ============================================================
#  危险地形（灰烬地块）
# ============================================================

static func danger_enabled() -> bool:
	return bool(danger_config().get("enabled", true)) \
		and bool(danger_config().get("ash_tile_as_danger", true))


static func is_danger_cell(cell: Vector2i) -> bool:
	if not danger_enabled():
		return false
	return CombatManager.ash_tiles.has(cell)


## 被推入危险地块的追加伤害（按地块基础伤害 × 配置倍率）。
static func danger_damage(cell: Vector2i) -> int:
	if not is_danger_cell(cell):
		return 0
	var tile_v: Variant = CombatManager.ash_tiles.get(cell, null)
	if not (tile_v is Dictionary):
		return 0
	var tile: Dictionary = tile_v as Dictionary
	var base: int = int(tile.get("damage", 0))
	if base <= 0:
		return 0
	return maxi(1, int(float(base) * float(danger_config().get("push_damage_multiplier", 1.0))))


## 地块归属者（击杀归属用）；无效时返回 null。
static func danger_owner(cell: Vector2i) -> Unit:
	if not is_danger_cell(cell):
		return null
	var tile_v: Variant = CombatManager.ash_tiles.get(cell, null)
	if not (tile_v is Dictionary):
		return null
	var owner_v: Variant = (tile_v as Dictionary).get("owner", null)
	if owner_v is Unit and is_instance_valid(owner_v as Unit):
		return owner_v as Unit
	return null


static func danger_hint() -> String:
	return str(danger_config().get("hint", "推入危险地形！"))


# ============================================================
#  ZOC（守护卡位）
# ============================================================

static func zoc_enabled() -> bool:
	return bool(zoc_config().get("enabled", true))


static func zoc_stop_on_enter() -> bool:
	return zoc_enabled() and bool(zoc_config().get("stop_on_enter", true))


static func zoc_block_leave() -> bool:
	return zoc_enabled() and bool(zoc_config().get("block_leave", true))


## 飞行 / 无视地形代价的单位是否免疫 ZOC。
static func ignores_zoc(unit: Unit) -> bool:
	if not zoc_enabled():
		return true
	if unit == null or not is_instance_valid(unit) or unit.unit_stats == null:
		return true
	if bool(zoc_config().get("ignore_flying", true)) and unit.unit_stats.ignore_terrain_cost:
		return true
	return false


static func has_zoc(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit) or unit.unit_stats == null:
		return false
	if not zoc_enabled():
		return false
	var cfg: Dictionary = zoc_config()
	var providers: Array = cfg.get("providers", [])
	var advanced: Array = cfg.get("provider_advanced", [])
	if str(unit.unit_stats.unit_name) in providers:
		return true
	var advanced_id: String = str(unit.unit_stats.advanced_class)
	if advanced_id != "" and advanced_id in advanced:
		return true
	# 身份表可直接标记 zoc=true（转职覆盖优先）
	var ident: Dictionary = SoulFireIdentity.resolve(unit.unit_stats.unit_name, advanced_id)
	return bool(ident.get("zoc", false))


## cell 是否处于 unit 的敌方 ZOC 控制区（四周有敌方守护单位）。
static func is_zoc_cell(unit: Unit, cell: Vector2i) -> bool:
	if ignores_zoc(unit):
		return false
	if unit.unit_stats == null:
		return false
	for d in ORTHO:
		var u: Unit = UnitManager.get_unit_at_cell(cell + d)
		if u == null or not is_instance_valid(u) or u.hit_points <= 0:
			continue
		if u.unit_stats == null or u.unit_stats.team_id == unit.unit_stats.team_id:
			continue
		if has_zoc(u):
			return true
	return false


static func zoc_hint() -> String:
	return str(zoc_config().get("hint", "ZOC 卡位！"))
