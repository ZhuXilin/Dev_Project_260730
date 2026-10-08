class_name WeaponUpgradeHelper
extends RefCounted

# ============================================================
#  WeaponUpgradeHelper — 读取 item_data.json 里的 upgrade_stats
#  缺省值：max=3，attack_per_level=2，其余 0
# ============================================================

const DEFAULT_MAX_LEVEL : int = 3
const DEFAULT_ATTACK_PER_LEVEL : int = 2
const DEFAULT_DEFENSE_PER_LEVEL : int = 0


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


## 含升级的最终攻击力（未乘品质）
static func get_effective_base_attack(data : ItemData, upgrade_level : int) -> int:
	if data == null: return 0
	return data.base_attack + upgrade_level * get_attack_per_level(data)


## 含升级的最终防御力（未乘品质）
static func get_effective_defense(data : ItemData, upgrade_level : int) -> int:
	if data == null: return 0
	return data.defense + upgrade_level * get_defense_per_level(data)


## 含升级的最终 modifier（叠加 per_level 加成）
static func get_effective_modifier(data : ItemData, upgrade_level : int) -> Dictionary:
	if data == null: return {}
	var result : Dictionary = data.modifier.duplicate()
	var per_lv : Dictionary = get_modifier_per_level(data)
	for k in per_lv:
		result[k] = result.get(k, 0.0) + per_lv[k] * upgrade_level
	return result


## 兼容旧调用：返回攻击增量（用于 UI 显示 +N 字样）
static func get_upgrade_attack_bonus(data : ItemData, upgrade_level : int) -> int:
	return upgrade_level * get_attack_per_level(data)
