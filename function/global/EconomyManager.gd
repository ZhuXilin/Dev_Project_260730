extends Node

# ---- 战斗奖励配置 ----
const REWARD_GOLD = {
	MapNode.NodeType.START: 150,
	MapNode.NodeType.NORMAL: 350,
	MapNode.NodeType.ELITE: 700,
	MapNode.NodeType.BOSS: 1500,
}

# ★ 新增：按节点类型给魂（大幅提高，参考斗技场收益）
const REWARD_SOUL = {
	MapNode.NodeType.START: 2,
	MapNode.NodeType.NORMAL: 2,
	MapNode.NodeType.ELITE: 3,
	MapNode.NodeType.BOSS: 8,
}

# Boss 额外加成
const BOSS_EXTRA_SOUL : int = 2

# ---- 材料奖励配置 ----
const REWARD_MATERIALS = {
	MapNode.NodeType.START: { "粗铁": 2 },
	MapNode.NodeType.NORMAL: { "粗铁": 2 },
	MapNode.NodeType.ELITE: { "精钢": 2 },
	MapNode.NodeType.BOSS: { "秘银": 2, "精钢": 1 },
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

func add_soul(amount: int): GameState.soul += amount
func get_soul() -> int: return GameState.soul

func reset_temp_resources():
	GameState.temp_gold = 0
	GameState.temp_soul = 0

func reset_all():
	reset_temp_resources()
	GameState.soul = 0

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
