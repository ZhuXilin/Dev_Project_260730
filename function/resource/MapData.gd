extends Resource
class_name MapData

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

@export var unlock_relics: Array[String] = []
@export var unlock_units: Array[String] = []

@export var objective_type: ObjectiveType = ObjectiveType.ANNIHILATE
@export var objective_params: Dictionary = {}

## v4.7：是否允许该战斗节点动态分配目标。
## 默认 false —— 战斗节点强制全灭，除非显式开启。
@export var allow_dynamic_objective: bool = false

## v4.7：动态目标的候选池（ObjectiveType 整数值）。
## 空数组 = 使用默认池 [CAPTURE, FLAG, ASSAULT]。
## 仅当 allow_dynamic_objective = true 时生效。
@export var dynamic_objective_pool: Array[int] = []

@export var max_waves: int = 1
@export var reinforcement_count: int = 0
@export var reinforcement_pool: Array[String] = []

## v4.5：高收益节点奖励倍率（金币 / 魂火 / 魂 都乘）
@export var reward_multiplier: float = 1.0

## v4.5：高收益节点的负面代价——敌人最大 HP 倍率
@export var enemy_hp_multiplier: float = 1.0

## v4.5：战斗强度等级（0 = 无，1 = I，2 = II，3 = III）
## 纯展示用，不影响实际战斗。ELITE / BOSS 节点常用 I/II/III 区分难度档位
@export var intensity: int = 0
