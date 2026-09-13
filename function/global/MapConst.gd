class_name MapConst
extends RefCounted

# ============================================================
#  基础尺寸
# ============================================================

## 地图单元格尺寸（像素）
## 注意：此值需与 Config.CELL_SIZE 保持一致
const CELL_SIZE : int = 16

## 默认地图尺寸（格子数）
## 注意：此值需与 Config.DEFAULT_MAP_SIZE 保持一致
const DEFAULT_MAP_SIZE : Vector2i = Vector2i(20, 15)


# ============================================================
#  高亮 / 预览颜色
# ============================================================
# 说明：用于 HighlightManager、Battlefield、InputManager 的格子高亮

## 移动范围高亮（半透明白）
const HIGHLIGHT_MOVE : Color = Color(1.0, 1.0, 1.0, 0.3)

## 攻击范围高亮（半透明红）
const HIGHLIGHT_ATTACK : Color = Color(0.7, 0.1, 0.2, 0.7)

## 治疗范围高亮（半透明蓝）
const HIGHLIGHT_HEAL : Color = Color(0.2, 0.5, 0.8, 0.7)

## 敌方治疗预览（半透明青绿，区别于己方治疗蓝）
const HIGHLIGHT_ENEMY_HEAL : Color = Color(0.2, 0.5, 0.4, 0.7)

## 出生点预览（半透明亮蓝）
const HIGHLIGHT_SPAWN : Color = Color(0.2, 0.6, 1.0, 0.4)

## 战斗开始事件预览（半透明紫）
const HIGHLIGHT_BATTLE_START : Color = Color(0.7, 0.3, 0.9, 0.3)

## 事件触发点预览（半透明蓝）
const HIGHLIGHT_EVENT : Color = Color(0.3, 0.6, 1.0, 0.3)

## HP 功能格预览 - 治疗（半透明绿）
const HIGHLIGHT_HP_HEAL : Color = Color(0.0, 1.0, 0.0, 0.3)

## HP 功能格预览 - 伤害（半透明红）
const HIGHLIGHT_HP_DAMAGE : Color = Color(1.0, 0.0, 0.0, 0.3)


# ============================================================
#  地图节点 / 连线颜色
# ============================================================
# 说明：用于 MapScene._draw_connections 与 MapNodeButton

## 节点间连线
const MAP_LINE_COLOR : Color = Color(0.5, 0.5, 0.5, 0.6)

## 节点连线宽度（像素）
const MAP_LINE_WIDTH : float = 2.0

## 已访问节点（深灰，不可交互）
const MAP_NODE_VISITED : Color = Color(0.4, 0.4, 0.4)

## 不可用节点（更深的灰）
const MAP_NODE_UNAVAILABLE : Color = Color(0.3, 0.3, 0.3)

## 可用节点（白）
const MAP_NODE_AVAILABLE : Color = Color.WHITE


# ============================================================
#  地图节点按钮尺寸 / 字号
# ============================================================
# 说明：用于 MapNodeButton.setup

## 节点按钮尺寸（像素）
const MAP_NODE_SIZE : Vector2 = Vector2(40, 20)

## 节点按钮字号
const MAP_NODE_FONT_SIZE : int = 5


# ============================================================
#  战斗动画时长（秒）
# ============================================================
# 说明：用于 CombatManager、MovementAnimator、Unit、EnemyAI

## 攻击/治疗表演总时长
const PERFORMANCE_DURATION : float = 0.5

## 玩家移动每步时长
const STEP_DURATION_PLAYER : float = 0.15

## AI 移动每步时长
const STEP_DURATION_AI : float = 0.12

## 受击闪光时长（与 shader hit_duration 保持一致）
const HIT_FLASH_DURATION : float = 0.15

## 受击位移距离（像素）
const HIT_OFFSET_DISTANCE : float = 8.0

## 伤害数字漂浮时长
const DAMAGE_POPUP_DURATION : float = 0.5

## 伤害数字尺寸
const DAMAGE_POPUP_SIZE : Vector2 = Vector2(50, 25)

## 伤害数字字号
const DAMAGE_FONT_SIZE : int = 12


# ============================================================
#  敌人 AI 评分权重
# ============================================================
# 说明：EnemyAI._evaluate_attack / _evaluate_move 的调参常量

## 低血量阈值（HP 比例）
const AI_HP_LOW_THRESHOLD : float = 0.4

## 击杀目标加分
const AI_SCORE_KILL_BONUS : int = 50

## 不被反击加分
const AI_SCORE_NO_COUNTER_BONUS : int = 30

## 被反击致死的惩罚
const AI_SCORE_DEATH_PENALTY : int = -100

## 有队友邻接加分
const AI_SCORE_ALLY_NEAR_BONUS : int = 5

## 远离玩家权重系数
const AI_SCORE_DIST_PLAYER_WEIGHT : float = 0.5

## 远离敌人权重系数
const AI_SCORE_DIST_ENEMY_WEIGHT : float = 2.0

## 地形防御权重系数
const AI_SCORE_TERRAIN_DEF_WEIGHT : float = 2.0
