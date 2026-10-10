extends Node

# ============================================================
#  EconomyManager — 战斗奖励（金币 + 魂火）
# ============================================================

const TYPE_NAME_TO_ID : Dictionary = {
	"START":    0,
	"NORMAL":   1,
	"ELITE":    2,
	"SHOP":     3,
	"TREASURE": 4,
	"BOSS":     5,
	"FORGE":    6,
	"CHAPEL":   7,
}

var REWARD_GOLD : Dictionary = {}
var REWARD_SOUL_FIRE : Dictionary = {}
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

	REWARD_SOUL_FIRE = SoulFireManager.REWARD_ON_KILL.duplicate()

	BOSS_EXTRA_SOUL = int(cfg.get("boss_extra_soul", 5))

	print("[EconomyManager] 已加载: %d 金 / %d 魂火" % [
		REWARD_GOLD.size(), REWARD_SOUL_FIRE.size()])


# ============================================================
#  奖励查询
# ============================================================
func get_battle_reward(node_type: int, is_boss: bool) -> Dictionary:
	var gold : int = REWARD_GOLD.get(node_type, 0)
	var soul_fire : int = REWARD_SOUL_FIRE.get(node_type, 0)
	if is_boss and node_type == MapNode.NodeType.BOSS:
		soul_fire += SoulFireManager.REWARD_EXTRA_BOSS
	return {
		"gold": gold,
		"soul_fire": soul_fire,
	}


# ============================================================
#  临时资源
# ============================================================
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
