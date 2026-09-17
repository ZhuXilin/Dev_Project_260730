# function/global/ArenaEquipContext.gd
class_name ArenaEquipContext
extends EquipContext

var arena_gold : int = 100
var player_data : UnitData = null
var passives : Array = [null, null, null, null]
var weapon_tokens : int = 0
var locked_talent_id : String = ""

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

# ---- 被动槽（竞技场不再用，保留空实现） ----
func get_passives() -> Array: return passives
func set_passive_at_slot(idx: int, value) -> void:
	if idx < 0 or idx >= passives.size(): return
	passives[idx] = value
func remove_passive_at_slot(idx: int) -> void:
	if idx < 0 or idx >= passives.size(): return
	passives[idx] = null

# ---- 铁匠铺 ----
func has_forge() -> bool: return true
func get_weapon_upgrade_tokens() -> int: return weapon_tokens
func consume_weapon_upgrade_token() -> bool:
	if weapon_tokens <= 0: return false
	weapon_tokens -= 1
	return true

# ---- 特技 ----
func is_talent_locked() -> bool: return locked_talent_id != ""
func lock_talent(talent_id: String) -> void: locked_talent_id = talent_id

# ---- 确认 ----
func on_confirm() -> void:
	pass
