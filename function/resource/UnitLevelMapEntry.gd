# UnitLevelMapEntry.gd
class_name UnitLevelMapEntry
extends Resource

@export var faction: String = ""       # 阵营名（取代 unit_name）
@export var unit_name: String = ""     # 保留但不再用于查找（仅作注释）
@export var day1: LevelListResource
@export var day2: LevelListResource
@export var day3: LevelListResource
