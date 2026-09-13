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
#  UI 动画 / 计时时长（秒）
# ============================================================

## 对话音乐过渡
const DIALOGUE_MUSIC_DELAY : float = 0.5

## 回合过渡总时长
const TURN_TRANSITION_DURATION : float = 1.0

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
