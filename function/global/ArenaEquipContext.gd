# function/global/ArenaEquipContext.gd
class_name ArenaEquipContext
extends EquipContext

var arena_gold : int = 100
var player_data : UnitData = null
var passives : Array = [null, null, null, null]
var locked_talent_id : String = ""
var talent_swap_chances : int = 1   # 剩余可换特技次数（开局给 1）

func get_context_id() -> String: return "arena"
func get_title() -> String: return "魂之竞技场"

# ---- 货币 ----
func get_gold() -> int: return arena_gold
func subtract_gold(amount: int) -> bool:
	if arena_gold < amount: return false
	arena_gold -= amount
	return true
func show_gold() -> bool: return true

# ---- 单位 ----
func get_units() -> Array:
	if player_data == null: return []
	return [player_data]

# ---- 被动槽（竞技场不用，保留空实现） ----
func get_passives() -> Array: return passives
func set_passive_at_slot(idx: int, value) -> void:
	if idx < 0 or idx >= passives.size(): return
	passives[idx] = value
func remove_passive_at_slot(idx: int) -> void:
	if idx < 0 or idx >= passives.size(): return
	passives[idx] = null

# ---- 铁匠铺（竞技场有，消耗金币） ----
func has_forge() -> bool: return true

# ---- 特技（有限次数可换） ----
func is_talent_locked() -> bool: return talent_swap_chances <= 0

func lock_talent(talent_id: String) -> void:
	locked_talent_id = talent_id

func consume_talent_swap() -> bool:
	if talent_swap_chances <= 0: return false
	talent_swap_chances -= 1
	return true

func grant_talent_swap(count: int = 1) -> void:
	talent_swap_chances += count

# ---- 确认 ----
func on_confirm() -> void:
	pass
