extends Resource
class_name MapData

@export var map_name : String = "默认地图"
@export var scene : PackedScene   # 包含 TileMapLayer 和 UnitPlacer 的完整场景
# map_size 不再手动设置，完全从 TileMap 自动提取（保留但标记为备用）
@export var map_size : Vector2i = Vector2i(20, 15)   # 默认，会被 TileMap 覆盖
@export var unit_configs : Array[UnitConfig] = []    # 单位配置
@export var map_unit_configs : Array[Dictionary] = [] # 功能格配置（由 MapUnitPlacer 生成）
