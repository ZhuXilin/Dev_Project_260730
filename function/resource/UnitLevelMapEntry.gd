extends Resource
class_name UnitLevelMapEntry

@export var faction: String = ""
@export var day1: LevelListResource
@export var day2: LevelListResource
@export var day3: LevelListResource

# ★ 新增：地图布局
@export var layout: MapLayout
