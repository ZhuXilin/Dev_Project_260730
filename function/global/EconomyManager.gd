extends Node

# ---- 战斗奖励配置 ----
const REWARD_GOLD = {
	MapNode.NodeType.START: 500,
	MapNode.NodeType.NORMAL: 500,
	MapNode.NodeType.ELITE: 1000,
	MapNode.NodeType.BOSS: 2000,
}
const REWARD_SOUL_BOSS = 1   # Boss 额外奖励魂

# ---- 获取战斗奖励 ----
func get_battle_reward(node_type: int, is_boss: bool) -> Dictionary:
	var gold = REWARD_GOLD.get(node_type, 0)
	var soul = 0
	if is_boss:
		soul = REWARD_SOUL_BOSS
	return {
		"gold": gold,
		"soul": soul
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
