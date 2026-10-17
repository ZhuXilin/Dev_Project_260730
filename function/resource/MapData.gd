extends Resource
class_name MapData

# ============================================================
#  胜利目标类型（v4.3）
# ============================================================
enum ObjectiveType {
	ANNIHILATE,   # 全灭（默认）
	CAPTURE,      # 占领
	FLAG,         # 夺旗
	ASSAULT,      # 突进
}

@export var map_name : String = "默认地图"
@export var scene : PackedScene
@export var map_size : Vector2i = Vector2i(20, 15)
@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var spawn_points: Array[Vector2i] = []
@export var required_unit: String = ""

## 打完这张地图时解锁的遗物 id 列表
## 与 MapLayoutNode.unlock_relics 会合并
@export var unlock_relics: Array[String] = []

## ★ 新增：打完这张地图时解锁的单位 id 列表
## 与 MapLayoutNode.unlock_units 会合并
@export var unlock_units: Array[String] = []

## v4.3：胜利目标类型
@export var objective_type: ObjectiveType = ObjectiveType.ANNIHILATE

## v4.3：胜利目标参数（留空则用 ObjectiveManager 的智能 fallback）
## - CAPTURE: { "target_cell": Vector2i, "hold_turns": int }
## - FLAG:    { "flag_cell": Vector2i, "goal_cell": Vector2i }
## - ASSAULT: { "target_unit_name": String }（为空时用 is_boss 单位）
@export var objective_params: Dictionary = {}

## v4.5：波次（1 = 无波次，敌人全灭即胜；>1 = 分批入场）
@export var max_waves: int = 1

## v4.5：每次波次推进时额外生成的增援数量（0 = 无增援）
@export var reinforcement_count: int = 0

## v4.5：增援单位类型池（空 = 从当前地图敌人里抽）
@export var reinforcement_pool: Array[String] = []
