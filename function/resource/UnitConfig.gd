extends Resource
class_name UnitConfig

@export var unit_name : String = "剑士"
@export var team_id : int = 0
@export var position : Vector2i = Vector2i.ZERO
@export var override_stats : Dictionary = {}
@export var immobile : bool = false   # 新增：是否不可移动（仅对敌方有效）
@export var initial_items : Array[ItemEntry] = []

func apply_override(stats: UnitData):
	if override_stats.has("max_hp"):
		stats.max_hp = override_stats["max_hp"]
	if override_stats.has("defense"):
		stats.defense = override_stats["defense"]
	if override_stats.has("magic_defense"):
		stats.magic_defense = override_stats["magic_defense"]
	if override_stats.has("move_range"):
		stats.move_range = override_stats["move_range"]
	if override_stats.has("skill"):
		stats.skill = override_stats["skill"]
	if override_stats.has("speed"):
		stats.speed = override_stats["speed"]
	if override_stats.has("luck"):
		stats.luck = override_stats["luck"]
	if override_stats.has("ignore_terrain_cost"):
		stats.ignore_terrain_cost = override_stats["ignore_terrain_cost"]
