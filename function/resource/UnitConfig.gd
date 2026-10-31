extends Resource
class_name UnitConfig

@export var unit_name: String = "swordsman"
@export var display_name: String = ""
@export var faction: String = ""
@export var team_id: int = 0
@export var position : Vector2i = Vector2i.ZERO
@export var override_stats : Dictionary = {}
@export var immobile : bool = false
@export var is_boss : bool = false

@export var wave: int = 1

@export var is_random_pool: bool = false
@export var pool_key: String = ""
@export var enemy_pool: Array[String] = []

# 进阶职业
@export var advanced_class_id: String = ""

# 头像覆盖（仅敌方使用）
@export var avatar_override: String = ""

func apply_override(stats: UnitData):
	if override_stats.has("max_hp"):
		stats.max_hp = override_stats["max_hp"]
	if override_stats.has("move_range"):
		stats.move_range = override_stats["move_range"]
	if override_stats.has("ignore_terrain_cost"):
		stats.ignore_terrain_cost = override_stats["ignore_terrain_cost"]

	if override_stats.has("strength"):
		stats.strength = override_stats["strength"]
	if override_stats.has("dexterity"):
		stats.dexterity = override_stats["dexterity"]
	if override_stats.has("intelligence"):
		stats.intelligence = override_stats["intelligence"]
	if override_stats.has("faith"):
		stats.faith = override_stats["faith"]
	if override_stats.has("arcane"):
		stats.arcane = override_stats["arcane"]

	if override_stats.has("defense"):
		stats.strength += override_stats["defense"]
	if override_stats.has("magic_defense"):
		stats.intelligence += override_stats["magic_defense"]
	if override_stats.has("skill"):
		stats.dexterity += override_stats["skill"] * 0.6
		stats.intelligence += override_stats["skill"] * 0.4
	if override_stats.has("speed"):
		stats.dexterity += override_stats["speed"]
	if override_stats.has("luck"):
		stats.arcane += override_stats["luck"]
