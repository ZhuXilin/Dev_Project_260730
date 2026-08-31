extends Resource
class_name UnitConfig

@export var unit_name: String = "剑士"
@export var display_name: String = ""
@export var faction: String = ""
@export var team_id: int = 0
@export var position : Vector2i = Vector2i.ZERO
@export var override_stats : Dictionary = {}
@export var immobile : bool = false   # 新增：是否不可移动（仅对敌方有效）
@export var initial_items : Array[ItemEntry] = []

func apply_override(stats: UnitData):
	# ---- 基础属性 ----
	if override_stats.has("max_hp"):
		stats.max_hp = override_stats["max_hp"]
	if override_stats.has("move_range"):
		stats.move_range = override_stats["move_range"]
	if override_stats.has("ignore_terrain_cost"):
		stats.ignore_terrain_cost = override_stats["ignore_terrain_cost"]
	
	# ---- 新属性（力/敏/智/信/感） ----
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
	
	# ---- 旧属性兼容（若从旧场景加载，映射到新属性） ----
	# defense → strength（物理防御由力量决定）
	if override_stats.has("defense"):
		stats.strength += override_stats["defense"]
	# magic_defense → intelligence（魔法防御由智力决定）
	if override_stats.has("magic_defense"):
		stats.intelligence += override_stats["magic_defense"]
	# skill → dexterity + intelligence（技巧拆分）
	if override_stats.has("skill"):
		stats.dexterity += override_stats["skill"] * 0.6
		stats.intelligence += override_stats["skill"] * 0.4
	# speed → dexterity（速度归入敏捷）
	if override_stats.has("speed"):
		stats.dexterity += override_stats["speed"]
	# luck → arcane（幸运重做为感应）
	if override_stats.has("luck"):
		stats.arcane += override_stats["luck"]
