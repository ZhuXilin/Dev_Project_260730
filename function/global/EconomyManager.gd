extends Node

# ---- 战斗金币（★ 砍半） ----
const REWARD_GOLD = {
	MapNode.NodeType.START: 75,
	MapNode.NodeType.NORMAL: 175,
	MapNode.NodeType.ELITE: 350,
	MapNode.NodeType.BOSS: 750,
}

# ---- 魂奖励 ----
const REWARD_SOUL = {
	MapNode.NodeType.START: 2,
	MapNode.NodeType.NORMAL: 2,
	MapNode.NodeType.ELITE: 3,
	MapNode.NodeType.BOSS: 8,
}

const BOSS_EXTRA_SOUL : int = 2

# ---- 材料奖励（★ 更新：ELITE 掉秘银，BOSS 掉龙鳞） ----
const REWARD_MATERIALS = {
	MapNode.NodeType.START: { "粗铁": 2 },
	MapNode.NodeType.NORMAL: { "粗铁": 2 },
	MapNode.NodeType.ELITE: { "精钢": 1, "秘银": 1 },
	MapNode.NodeType.BOSS: { "精钢": 2, "龙鳞": 1 },
}

func get_battle_reward(node_type: int, is_boss: bool) -> Dictionary:
	var gold : int = REWARD_GOLD.get(node_type, 0)
	var soul : int = REWARD_SOUL.get(node_type, 0)
	if is_boss and node_type == MapNode.NodeType.BOSS:
		soul += BOSS_EXTRA_SOUL
	var materials : Dictionary = REWARD_MATERIALS.get(node_type, {}).duplicate()

	return {
		"gold": gold,
		"soul": soul,
		"materials": materials
	}

# ---- 临时资源操作 ----
func add_temp_gold(amount: int): GameState.temp_gold += amount
func add_temp_soul(amount: int): GameState.temp_soul += amount
func subtract_temp_gold(amount: int): GameState.temp_gold -= amount
func subtract_temp_soul(amount: int): GameState.temp_soul -= amount
func get_temp_gold() -> int: return GameState.temp_gold
func get_temp_soul() -> int: return GameState.temp_soul

# ---- 永久资源操作（魂） ----
func add_soul(amount: int): GameState.soul += amount
func get_soul() -> int: return GameState.soul

# ---- 清空临时资源 ----
func reset_temp_resources():
	GameState.temp_gold = 0
	GameState.temp_soul = 0

func reset_all():
	reset_temp_resources()
	GameState.soul = 0

# ---- 应用材料奖励 ----
func apply_material_reward(materials: Dictionary):
	for material_name in materials:
		var amount = materials[material_name]
		if amount > 0:
			GameState.add_material(material_name, amount)

func get_material(material_name: String) -> int:
	return GameState.get_material(material_name)

func get_all_materials() -> Dictionary:
	return GameState.get_all_materials()

func reset_materials():
	GameState.reset_materials()
