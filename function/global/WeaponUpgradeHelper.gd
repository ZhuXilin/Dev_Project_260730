class_name WeaponUpgradeHelper
extends RefCounted

# ============================================================
#  WeaponUpgradeHelper — 读取 item_data.json 里的 upgrade_stats
# ============================================================

const DEFAULT_MAX_LEVEL : int = 3
const DEFAULT_ATTACK_PER_LEVEL : int = 2
const DEFAULT_DEFENSE_PER_LEVEL : int = 0

# ★ 批次 5B：3 级 +1 射程，5 级 5% 特殊效果
const RANGE_BONUS_LEVEL : int = 3
const SPECIAL_EFFECT_LEVEL : int = 5
const SPECIAL_EFFECT_CHANCE : float = 0.05


static func get_max_level(data : ItemData) -> int:
	if data == null: return DEFAULT_MAX_LEVEL
	var up : Dictionary = data.upgrade_stats
	return int(up.get("max_level", DEFAULT_MAX_LEVEL))


static func get_attack_per_level(data : ItemData) -> int:
	if data == null: return DEFAULT_ATTACK_PER_LEVEL
	var up : Dictionary = data.upgrade_stats
	return int(up.get("attack_per_level", DEFAULT_ATTACK_PER_LEVEL))


static func get_defense_per_level(data : ItemData) -> int:
	if data == null: return DEFAULT_DEFENSE_PER_LEVEL
	var up : Dictionary = data.upgrade_stats
	return int(up.get("defense_per_level", DEFAULT_DEFENSE_PER_LEVEL))


static func get_modifier_per_level(data : ItemData) -> Dictionary:
	if data == null: return {}
	var up : Dictionary = data.upgrade_stats
	return up.get("modifier_per_level", {}).duplicate()


static func get_effective_base_attack(data : ItemData, upgrade_level : int) -> int:
	if data == null: return 0
	return data.base_attack + upgrade_level * get_attack_per_level(data)


static func get_effective_defense(data : ItemData, upgrade_level : int) -> int:
	if data == null: return 0
	return data.defense + upgrade_level * get_defense_per_level(data)


static func get_effective_modifier(data : ItemData, upgrade_level : int) -> Dictionary:
	if data == null: return {}
	var result : Dictionary = data.modifier.duplicate()
	var per_lv : Dictionary = get_modifier_per_level(data)
	for k in per_lv:
		result[k] = result.get(k, 0.0) + per_lv[k] * upgrade_level
	return result


static func get_upgrade_attack_bonus(data : ItemData, upgrade_level : int) -> int:
	return upgrade_level * get_attack_per_level(data)


# ★ 批次 5B
static func get_effective_attack_range(data : ItemData, upgrade_level : int) -> int:
	if data == null: return 0
	if upgrade_level >= RANGE_BONUS_LEVEL:
		return data.attack_range + 1
	return data.attack_range


static func has_special_effect(upgrade_level : int) -> bool:
	return upgrade_level >= SPECIAL_EFFECT_LEVEL
