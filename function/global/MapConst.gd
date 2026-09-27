class_name MapConst
extends RefCounted

# ============================================================
#  基础尺寸
# ============================================================

const CELL_SIZE : int = 16
const DEFAULT_MAP_SIZE : Vector2i = Vector2i(20, 15)


# ============================================================
#  高亮 / 预览颜色
# ============================================================
const HIGHLIGHT_MOVE : Color = Color(1.0, 1.0, 1.0, 0.3)
const HIGHLIGHT_ATTACK : Color = Color(0.7, 0.1, 0.2, 0.7)
const HIGHLIGHT_HEAL : Color = Color(0.2, 0.5, 0.8, 0.7)
const HIGHLIGHT_ENEMY_HEAL : Color = Color(0.2, 0.5, 0.4, 0.7)
const HIGHLIGHT_SPAWN : Color = Color(0.2, 0.6, 1.0, 0.4)
const HIGHLIGHT_BATTLE_START : Color = Color(0.7, 0.3, 0.9, 0.3)
const HIGHLIGHT_EVENT : Color = Color(0.3, 0.6, 1.0, 0.3)
const HIGHLIGHT_HP_HEAL : Color = Color(0.0, 1.0, 0.0, 0.3)
const HIGHLIGHT_HP_DAMAGE : Color = Color(1.0, 0.0, 0.0, 0.3)


# ============================================================
#  地图节点 / 连线颜色
# ============================================================
const MAP_LINE_COLOR : Color = Color(0.5, 0.5, 0.5, 0.6)
const MAP_LINE_WIDTH : float = 2.0
const MAP_NODE_VISITED : Color = Color(0.4, 0.4, 0.4)
const MAP_NODE_UNAVAILABLE : Color = Color(0.3, 0.3, 0.3)
const MAP_NODE_AVAILABLE : Color = Color.WHITE


# ============================================================
#  地图节点按钮尺寸 / 字号
# ============================================================
const MAP_NODE_SIZE : Vector2 = Vector2(40, 20)
const MAP_NODE_FONT_SIZE : int = 5


# ============================================================
#  战斗动画时长
# ============================================================
const PERFORMANCE_DURATION : float = 0.5
const STEP_DURATION_PLAYER : float = 0.15
const STEP_DURATION_AI : float = 0.12
const HIT_FLASH_DURATION : float = 0.15
const HIT_OFFSET_DISTANCE : float = 8.0
const DAMAGE_POPUP_DURATION : float = 0.5
const DAMAGE_POPUP_SIZE : Vector2 = Vector2(50, 25)
const DAMAGE_FONT_SIZE : int = 12


# ============================================================
#  敌人 AI 评分权重
# ============================================================
const AI_HP_LOW_THRESHOLD : float = 0.4
const AI_SCORE_KILL_BONUS : int = 50
const AI_SCORE_NO_COUNTER_BONUS : int = 30
const AI_SCORE_DEATH_PENALTY : int = -100
const AI_SCORE_ALLY_NEAR_BONUS : int = 5
const AI_SCORE_DIST_PLAYER_WEIGHT : float = 0.5
const AI_SCORE_DIST_ENEMY_WEIGHT : float = 2.0
const AI_SCORE_TERRAIN_DEF_WEIGHT : float = 2.0


# ============================================================
#  节点类型显示名（★ 全项目唯一来源）
# ============================================================
## 用于：局内地图节点按钮、地图编辑器测试模式
## 战斗节点的中文名仅作为"兜底名"，正常情况下应显示 map_name
static func get_node_display_name(node_type: int) -> String:
	match node_type:
		MapNode.NodeType.START:    return "起始"
		MapNode.NodeType.NORMAL:   return "普通"
		MapNode.NodeType.ELITE:    return "精英"
		MapNode.NodeType.BOSS:     return "首领"
		MapNode.NodeType.SHOP:     return "商店"
		MapNode.NodeType.FORGE:    return "铁匠铺"
		MapNode.NodeType.TREASURE: return "宝箱"
		MapNode.NodeType.CHAPEL:   return "圣坛"
	return "?"
