class_name UIConst
extends RefCounted

# ============================================================
#  UI 面板尺寸
# ============================================================

## 模态消息框（show_modal_message）
const MODAL_PANEL_SIZE : Vector2 = Vector2(160, 80)

## 短暂提示框（show_message）
const MSG_PANEL_SIZE : Vector2 = Vector2(180, 60)

## 装备菜单最小宽度
const EQUIP_MENU_MIN_WIDTH : float = 60.0
const EQUIP_CONTAINER_MIN_WIDTH : float = 80.0


# ============================================================
#  通用字号
# ============================================================
const FONT_SIZE_TINY : int = 4
const FONT_SIZE_SMALL : int = 6
const FONT_SIZE_NORMAL : int = 8
const FONT_SIZE_LARGE : int = 10
const FONT_SIZE_TITLE : int = 12

# ============================================================
#  按钮统一口径（v6.72：所有按钮文字统一 8 号；确认/取消按钮尺寸统一）
# ============================================================
## 所有按钮文字统一字号（不传字号时也用这个）
const BUTTON_FONT_SIZE : int = 8
## 确认 / 取消 / 关闭 这类标准操作按钮的统一最小尺寸
const BUTTON_CONFIRM_SIZE : Vector2 = Vector2(64, 24)

## 动态创建的文本按钮统一套 8bit 按钮皮肤。
## 注意：只给代码 new 出来的按钮用；场景里的按钮在 .tscn 配，不用代码兜底覆盖。
static func style_button(btn: Button) -> void:
	var sb := load(Config.PATHS.STYLEBOX_8BIT_BUTTON) as StyleBox
	if sb == null:
		return
	for state in ["normal", "pressed", "hover", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, sb)


# ============================================================
#  UI 动画 / 计时时长（秒）
# ============================================================

## 对话音乐过渡
const DIALOGUE_MUSIC_DELAY : float = 0.5

## 回合过渡总时长
const TURN_TRANSITION_DURATION : float = 0.5

## 道具获得弹窗自动关闭时长
const ITEM_POPUP_DURATION : float = 2.0

## 事件动作间隔
const EVENT_ACTION_DELAY : float = 0.3

## AI 行动间隔
const AI_ACTION_DELAY : float = 0.5

## 胜利面板弹出前的等待
const VICTORY_WAIT_DELAY : float = 1.5


# ============================================================
#  高亮 / 预览相关 UI
# ============================================================

## 攻击指示器 z_index
const ATTACK_INDICATOR_Z_INDEX : int = 5

## 菜单拦截层 z_index
const MENU_BLOCKER_Z_INDEX : int = 10

## 拖拽预览 z_index
const DRAG_PREVIEW_Z_INDEX : int = 100


# ============================================================
#  奖励结算面板
# ============================================================

## 结算面板最大高度（占视口比例）
const REWARD_PANEL_MAX_HEIGHT_RATIO : float = 0.9

## 结算面板最小宽度
const REWARD_PANEL_MIN_WIDTH : float = 120.0

## 结算面板最大宽度（占视口比例）
const REWARD_PANEL_MAX_WIDTH_RATIO : float = 0.4


# ============================================================
#  回合过渡文字
# ============================================================
const TURN_TEXT_PLAYER : String = "我方第 %d 回合"
const TURN_TEXT_ENEMY : String = "敌方第 %d 回合"

## 品质颜色（统一来源）
const QUALITY_COLORS : Dictionary = {
	"common":    Color(1.0, 1.0, 1.0),
	"rare":      Color(0.3, 0.6, 1.0),
	"epic":      Color(0.7, 0.3, 1.0),
	"legendary": Color(1.0, 0.7, 0.0),
}

## v5.1：Build 标签颜色（临时配色，统一来源）
## 用于防具图标背后的方向方块 + 队伍标签统计槽
const BUILD_TAG_COLORS : Dictionary = {
	"烈焰": Color(0.95, 0.35, 0.20),  # 火焰红橙
	"轮回": Color(0.30, 0.75, 0.65),  # 轮回青绿
	"灰烬": Color(0.65, 0.65, 0.68),  # 灰烬灰
	"守护": Color(0.30, 0.55, 0.95),  # 守护蓝
	"献祭": Color(0.80, 0.20, 0.40),  # 献祭暗红
	"余烬": Color(0.70, 0.40, 0.95),  # 余烬紫（v5.3：原金色与连通箭头黄色过近，箭头看不清）
}
const BUILD_TAG_ORDER : Array = ["烈焰", "轮回", "灰烬", "守护", "献祭", "余烬"]
const NO_TAG_COLOR : Color = Color(0.35, 0.35, 0.35)  # 无标签（熔铸防具等）
