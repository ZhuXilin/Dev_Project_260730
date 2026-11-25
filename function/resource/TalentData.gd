extends Resource
class_name TalentData

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var flavor: String = ""
@export var school: String = ""
@export var rarity: String = ""
@export var accumulation_threshold: int = 3
@export var cooldown_after_trigger: int = 0
@export var effect_type: String = ""
@export var effect_params: Dictionary = {}
@export var icon_path: String = ""
@export var compatible_units: Array = []
@export var tutorial_stage: int = 0

@export var is_active_skill: bool = false
@export var skill_cooldown: int = 0
## v6.2：主动技能 × 流派共鸣标签（六流派之一；空 = 不共鸣）
@export var resonance_school: String = ""

@export var unlock_type: String = "default"
@export var soul_cost: int = 0

# ★ v6.71：技能池三层新字段（方案：初始 roll 强化/替换模板 + 单位类型适配）
## 锚点：basic_attack（强化普攻，被动）/ soul_skill（强化或替换基础魂火技能，主动）/ both
@export var anchor: String = ""
## 单位类型适配系数（按回复/魔法/近战/远程给不同结算）
@export var unit_type_scaling: Dictionary = {}
## 标签（远程/近战/法术/治疗/位移/范围/直线/连击/破甲/异常 hook）
@export var tags: Array = []
## 数值缩放来源（攻击/力量/智力/信仰/灵巧）
@export var scaling: String = ""
## 每次释放费用（新口径；旧值读 effect_params.soul_fire_cost）
@export var cost: int = 0
## 冷却回合（新口径；旧值读 cooldown_after_trigger）
@export var cooldown: int = 0

## 取锚点，空则按 effect_type 兜底
func get_anchor() -> String:
	if anchor != "":
		return anchor
	return "soul_skill"

## 取费用（新字段优先，兼容旧 effect_params）
func get_cost() -> int:
	if cost > 0:
		return cost
	var ep: Dictionary = effect_params if effect_params is Dictionary else {}
	return int(ep.get("soul_fire_cost", 0))

## 取冷却（新字段优先，兼容旧 cooldown_after_trigger）
func get_cooldown() -> int:
	if cooldown > 0:
		return cooldown
	return cooldown_after_trigger
