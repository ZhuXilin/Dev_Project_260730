extends Resource
class_name ItemData

@export var id : String
@export var name : String
@export var type : String
@export var use_type : String
@export var icon : Texture2D
@export var effect : Dictionary
@export var description : String
@export var category : String = ""
@export var use_effect : Dictionary = {}   # 使用效果配置

# 武器专用字段
@export var weapon_attack : int = 0
@export var weapon_magic_attack : int = 0
@export var weapon_heal_amount : int = 0
@export var weapon_attack_range : int = 1
@export var weapon_min_attack_range : int = 1
@export var weapon_type : int = -1
