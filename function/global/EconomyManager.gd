extends Node

# ---- 战斗奖励配置 ----
const REWARD_GOLD = {
	MapNode.NodeType.START: 100,
	MapNode.NodeType.NORMAL: 200,
	MapNode.NodeType.ELITE: 400,
	MapNode.NodeType.BOSS: 1000,
}

# ---- 材料奖励配置 ----
const REWARD_MATERIALS = {
	MapNode.NodeType.START: { "粗铁": 1 },
	MapNode.NodeType.NORMAL: { "粗铁": 1 },
	MapNode.NodeType.ELITE: { "精钢": 1 },
	MapNode.NodeType.BOSS: { "秘银": 1 },
}

# ---- Boss奖励 ----
const REWARD_SOUL_BOSS = 1   # Boss 额外奖励魂

# ---- 获取战斗奖励（已移除龙族Boss参数） ----
func get_battle_reward(node_type: int, is_boss: bool) -> Dictionary:
	var gold = REWARD_GOLD.get(node_type, 0)
	var soul = REWARD_SOUL_BOSS if is_boss else 0
	var materials = REWARD_MATERIALS.get(node_type, {}).duplicate()
	
	return {
		"gold": gold,
		"soul": soul,
		"materials": materials
	}

# ---- 临时资源操作 ----
func add_temp_gold(amount: int):
	GameState.temp_gold += amount

func add_temp_soul(amount: int):
	GameState.temp_soul += amount

func subtract_temp_gold(amount: int):
	GameState.temp_gold -= amount

func subtract_temp_soul(amount: int):
	GameState.temp_soul -= amount

func get_temp_gold() -> int:
	return GameState.temp_gold

func get_temp_soul() -> int:
	return GameState.temp_soul

# ---- 永久资源操作（魂） ----
func add_soul(amount: int):
	GameState.soul += amount

func get_soul() -> int:
	return GameState.soul

# ---- 清空临时资源（用于新轮回开始） ----
func reset_temp_resources():
	GameState.temp_gold = 0
	GameState.temp_soul = 0

# ---- 重置所有（用于完全重置） ----
func reset_all():
	reset_temp_resources()
	GameState.soul = 0

# ---- 应用材料奖励 ----
func apply_material_reward(materials: Dictionary):
	for material_name in materials:
		var amount = materials[material_name]
		if amount > 0:
			GameState.add_material(material_name, amount)

# ---- 获取材料 ----
func get_material(material_name: String) -> int:
	return GameState.get_material(material_name)

func get_all_materials() -> Dictionary:
	return GameState.get_all_materials()

func reset_materials():
	GameState.reset_materials()
