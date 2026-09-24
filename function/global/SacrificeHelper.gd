class_name SacrificeHelper
extends RefCounted

const REWARDS : Array = [
	{"gold": 1000, "epic_count": 2, "relic": false},
	{"gold": 2000, "epic_count": 2, "relic": false},
	{"gold": 3000, "epic_count": 2, "relic": true},
]


static func get_reward_preview(count: int) -> Dictionary:
	if count <= 0:
		count = 1
	var idx : int = count - 1
	if idx >= REWARDS.size():
		idx = REWARDS.size() - 1
	return REWARDS[idx].duplicate()


static func do_sacrifice(party: Array, unit: UnitData) -> Dictionary:
	unit.is_dead = true
	unit.hit_points = 0

	GameState.sacrifice_count += 1
	var reward : Dictionary = get_reward_preview(GameState.sacrifice_count)

	EconomyManager.add_temp_gold(reward["gold"])

	var epic_rewards : Array = _generate_epic_armor_rewards(reward["epic_count"])
	for inst in epic_rewards:
		GameState.pending_sacrifice_rewards.append(inst)

	var relic_id : String = ""
	if reward["relic"]:
		relic_id = _grant_random_relic()

	for member in party:
		if member.is_dead: continue
		member.persistent_attack_bonus += 0.30

	SaveManager.auto_save()

	return {
		"gold": reward["gold"],
		"epic_count": epic_rewards.size(),
		"relic_id": relic_id,
	}


static func _generate_epic_armor_rewards(count: int) -> Array:
	var result : Array = []
	var candidates : Array = []
	for item_id in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(item_id)
		if not d: continue
		if d.type != "armor": continue
		if d.quality != "epic": continue
		candidates.append(item_id)

	if candidates.is_empty():
		for item_id in ItemManager.get_all_item_ids():
			var d : ItemData = ItemManager.get_item_data(item_id)
			if not d: continue
			if d.type != "armor": continue
			if d.quality != "rare": continue
			candidates.append(item_id)

	if candidates.is_empty():
		return result

	for i in range(count):
		var pick : String = candidates[randi() % candidates.size()]
		var inst := ItemInstance.new()
		inst.item_id = pick
		inst.count = 1
		result.append(inst)
	return result


static func _grant_random_relic() -> String:
	var pool : Array = []
	for rid in RelicManager.get_unlocked_relics():
		pool.append(rid)
	if pool.is_empty():
		return ""
	pool.shuffle()
	var pick : String = pool[0]
	RelicManager.unlock_relic(pick)
	var inst := ItemInstance.new()
	inst.item_id = pick
	inst.count = 1
	if not GameState.add_relic_to_passive_slot(inst):
		print("[熔铸] 遗物 %s 解锁但未入槽（槽满）" % pick)
	return pick
