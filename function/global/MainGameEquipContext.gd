# function/global/MainGameEquipContext.gd
class_name MainGameEquipContext
extends EquipContext

func get_context_id() -> String: return "main_game"

func get_title() -> String: return ""

# ---- 货币 ----
func get_gold() -> int:
	return EconomyManager.get_temp_gold()

func subtract_gold(amount: int) -> bool:
	if EconomyManager.get_temp_gold() < amount:
		return false
	EconomyManager.subtract_temp_gold(amount)
	return true

func show_gold() -> bool:
	return true

# ---- 单位列表 ----
func get_units() -> Array:
	return GameState.party

# ---- 被动槽 ----
func get_passives() -> Array:
	return GameState.get_passives()

func set_passive_at_slot(idx: int, value) -> void:
	GameState.set_passive_at_slot(idx, value)

func remove_passive_at_slot(idx: int) -> void:
	GameState.remove_passive_at_slot(idx)

# ---- 铁匠铺 ----
func has_forge() -> bool:
	return false

# ---- 特技 ----
func is_talent_locked() -> bool:
	return false

# ---- 商店（走 EquipmentConfig 里的 shop_manager，context 不接管） ----
func buy_item(item_id: String) -> bool:
	var data = ItemManager.get_item_data(item_id)
	if not data:
		return false
	Globals.unlock_item(item_id)
	GameState.add_reward_item(item_id)
	return true

func get_shop_reset_cost() -> int:
	return 0

func on_shop_reset() -> bool:
	return false

# ---- 解锁 ----
func can_unlock_items() -> bool:
	return true

func unlock_item(item_id: String) -> void:
	Globals.unlock_item(item_id)
	if item_id not in GameState.unlocked_recipes:
		GameState.unlocked_recipes.append(item_id)

# ---- 确认 ----
func on_confirm() -> void:
	if _pending_faction != "":
		GameState.current_faction = _pending_faction
	GameState.interrupt_state = GameState.InterruptState.MAP
	GameState.reset_progress()
	LevelManager.start_game()
