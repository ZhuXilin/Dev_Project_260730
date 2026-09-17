# function/global/EquipContext.gd
class_name EquipContext
extends RefCounted

# ---- 标识 ----
func get_context_id() -> String: return "generic"

# ---- 标题 ----
func get_title() -> String: return ""

# ---- 货币 ----
func get_gold() -> int: return 0
func subtract_gold(_amount: int) -> bool: return false
func show_gold() -> bool: return true

# ---- 单位列表 ----
func get_units() -> Array: return []

# ---- 被动槽 ----
func get_passives() -> Array: return []
func set_passive_at_slot(_idx: int, _value) -> void: pass
func remove_passive_at_slot(_idx: int) -> void: pass

# ---- 铁匠铺 ----
func has_forge() -> bool: return false
func get_weapon_upgrade_tokens() -> int: return 0
func consume_weapon_upgrade_token() -> bool: return false

# ---- 特技锁定 ----
func is_talent_locked() -> bool: return false
func lock_talent(_talent_id: String) -> void: pass

# ---- 商店 ----
func buy_item(_item_id: String) -> bool: return false
func get_shop_reset_cost() -> int: return 0
func on_shop_reset() -> bool: return false

# ---- 确认/关闭 ----
func on_confirm() -> void: pass
func on_close() -> void: pass

# ---- 存档钩子 ----
func auto_save() -> void:
	if SaveManager:
		SaveManager.auto_save()

# ---- 解锁 ----
func can_unlock_items() -> bool: return false
func unlock_item(_item_id: String) -> void: pass

# ---- 阵营（主游戏用） ----
var _pending_faction : String = ""

func set_pending_faction(f: String):
	_pending_faction = f

# ---- 竞技场商店 ----
func get_arena_shop_items() -> Array: return []
func buy_arena_shop_item(_shop_index: int) -> Dictionary: return {"success": false, "reason": "not_supported"}
func get_arena_shop_reset_cost() -> int: return 0
func on_arena_shop_reset() -> bool: return false
