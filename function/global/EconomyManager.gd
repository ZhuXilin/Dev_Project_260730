extends Node

# ============================================================
#  EconomyManager — 战斗奖励（金币 + 魂）
#  v5.0：魂火不再兑现，战后直接发魂；数值走 economy_config.json
# ============================================================

const TYPE_NAME_TO_ID : Dictionary = {
	"START":    0,
	"NORMAL":   1,
	"ELITE":    2,
	"TREASURE": 3,
	"BOSS":     4,
	"FORGE":    5,
	"CHAPEL":   6,
}

var REWARD_GOLD : Dictionary = {}
var REWARD_SOUL : Dictionary = {}
var BOSS_EXTRA_SOUL : int = 5


func _ready():
	reload_config()


func reload_config():
	var cfg : Dictionary = GameConfigManager.get_file("economy_config.json")

	REWARD_GOLD.clear()
	var raw_gold : Dictionary = cfg.get("reward_gold", {})
	for key in raw_gold:
		if TYPE_NAME_TO_ID.has(key):
			REWARD_GOLD[TYPE_NAME_TO_ID[key]] = int(raw_gold[key])

	REWARD_SOUL.clear()
	var raw_soul : Dictionary = cfg.get("reward_soul", {})
	for key in raw_soul:
		if TYPE_NAME_TO_ID.has(key):
			REWARD_SOUL[TYPE_NAME_TO_ID[key]] = int(raw_soul[key])

	BOSS_EXTRA_SOUL = int(cfg.get("boss_extra_soul", 5))

	print("[EconomyManager] 已加载: %d 金 / %d 魂" % [
		REWARD_GOLD.size(), REWARD_SOUL.size()])


func get_battle_reward(node_type: int, is_boss: bool) -> Dictionary:
	var gold : int = REWARD_GOLD.get(node_type, 0)
	var soul : int = REWARD_SOUL.get(node_type, 0)
	if is_boss and node_type == MapNode.NodeType.BOSS:
		soul += BOSS_EXTRA_SOUL
	return {
		"gold": gold,
		"soul": soul,
	}


func add_temp_gold(amount: int): GameState.temp_gold += amount
func subtract_temp_gold(amount: int): GameState.temp_gold -= amount
func get_temp_gold() -> int: return GameState.temp_gold

func add_soul(amount: int): GameState.soul += amount
func get_soul() -> int: return GameState.soul

func reset_temp_resources():
	GameState.temp_gold = 0

func reset_all():
	reset_temp_resources()
	GameState.soul = 0
