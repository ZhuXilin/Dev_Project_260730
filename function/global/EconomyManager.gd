extends Node

# ============================================================
#  EconomyManager — 从 JSON 读经济配置
#  数据文件：res://content/data/config/economy_config.json
#  与 EconomyCalculator 工具共用同一份文件
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

# ---- 战斗奖励（从 JSON 加载） ----
var REWARD_GOLD : Dictionary = {}
var REWARD_SOUL : Dictionary = {}
var REWARD_MATERIALS : Dictionary = {}
var BOSS_EXTRA_SOUL : int = 2


func _ready():
	reload_config()


func reload_config():
	var cfg : Dictionary = GameConfigManager.get_file("economy_config.json")

	# ---- 金币 ----
	REWARD_GOLD.clear()
	var raw_gold : Dictionary = cfg.get("reward_gold", {})
	for key in raw_gold:
		if TYPE_NAME_TO_ID.has(key):
			REWARD_GOLD[TYPE_NAME_TO_ID[key]] = int(raw_gold[key])

	# ---- 魂 ----
	REWARD_SOUL.clear()
	var raw_soul : Dictionary = cfg.get("reward_soul", {})
	for key in raw_soul:
		if TYPE_NAME_TO_ID.has(key):
			REWARD_SOUL[TYPE_NAME_TO_ID[key]] = int(raw_soul[key])

	# ---- 材料 ----
	REWARD_MATERIALS.clear()
	var raw_mats : Dictionary = cfg.get("reward_materials", {})
	for key in raw_mats:
		if not TYPE_NAME_TO_ID.has(key): continue
		var mats : Dictionary = {}
		for mat_name in raw_mats[key]:
			mats[mat_name] = int(raw_mats[key][mat_name])
		REWARD_MATERIALS[TYPE_NAME_TO_ID[key]] = mats

	BOSS_EXTRA_SOUL = int(cfg.get("boss_extra_soul", 2))

	print("[EconomyManager] 已加载: %d 金 / %d 魂 / %d 材料" % [
		REWARD_GOLD.size(), REWARD_SOUL.size(), REWARD_MATERIALS.size()])


# ============================================================
#  奖励查询
# ============================================================
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


# ============================================================
#  临时资源
# ============================================================
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
