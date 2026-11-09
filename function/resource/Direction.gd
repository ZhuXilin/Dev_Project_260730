class_name Direction
extends RefCounted

# ============================================================
#  Direction — 防具方向枚举 + 辅助函数
#  几何语义：
#    UP / DOWN     —— 单位内上下相邻槽
#    LEFT / RIGHT  —— 跨单位同号行（U_i 行 r ↔ U_{i±1} 行 r）
#    VERTICAL      —— 上下都连（双箭头）
#    HORIZONTAL    —— 左右都连（双箭头）
#    DIAG_NE_SW    —— 斜线 ⤢：连"右上"或"左下"（跨单位错位）
#                      U_i 行 r ↔ U_{i+1} 行 r-1
#                      U_i 行 r ↔ U_{i-1} 行 r+1
#    DIAG_NW_SE    —— 斜线 ⤡：连"左上"或"右下"
#                      U_i 行 r ↔ U_{i+1} 行 r+1
#                      U_i 行 r ↔ U_{i-1} 行 r-1
# ============================================================

enum Value {
	NONE = 0,
	UP = 1,
	RIGHT = 2,
	DOWN = 4,
	LEFT = 8,
	VERTICAL = 5,      # UP | DOWN
	HORIZONTAL = 10,   # RIGHT | LEFT
	DIAG_NE_SW = 16,   # 右上 / 左下
	DIAG_NW_SE = 32,   # 左上 / 右下
}

const ALL_SINGLE : Array[int] = [Value.UP, Value.RIGHT, Value.DOWN, Value.LEFT]
const ALL_DOUBLE : Array[int] = [Value.VERTICAL, Value.HORIZONTAL, Value.DIAG_NE_SW, Value.DIAG_NW_SE]
const ALL_DOUBLE_ARROW : Array[int] = [Value.VERTICAL, Value.DIAG_NE_SW, Value.DIAG_NW_SE]
const ALL_DIAGONAL : Array[int] = [Value.DIAG_NE_SW, Value.DIAG_NW_SE]


static func is_arrow(dir: int) -> bool:
	return dir != Value.NONE


static func is_double_arrow(dir: int) -> bool:
	return dir in ALL_DOUBLE_ARROW


static func is_single_arrow(dir: int) -> bool:
	return dir in ALL_SINGLE


static func is_diagonal(dir: int) -> bool:
	return dir in ALL_DIAGONAL


static func roll_drop_direction() -> int:
	var r : float = randf()
	if r < 0.70:
		return Value.NONE
	elif r < 0.85:  # 15% 单箭头
		return ALL_SINGLE[randi() % ALL_SINGLE.size()]
	elif r < 0.90:  # 5% 直线双箭头
		return [Value.VERTICAL, Value.HORIZONTAL][randi() % 2]
	else:           # 10% 斜线双箭头
		return ALL_DIAGONAL[randi() % ALL_DIAGONAL.size()]


## 重 roll 方向：
##   单箭头 → 从另外 3 个单箭头里选
##   双直  → 从另外 1 个双直里选（永远变）
##   斜线  → 从另外 1 个斜线里选（永远变）
##   双箭头跨类型：允许 ↕ / ⤢ / ⤡ 三选一，但**永远不会变回单箭头**
## 返回新方向；若不可重 roll 返回原方向
static func reroll_direction(old_dir: int) -> int:
	if old_dir == Value.NONE:
		return Value.NONE
	if is_single_arrow(old_dir):
		var pool : Array = ALL_SINGLE.duplicate()
		pool.erase(old_dir)
		return pool[randi() % pool.size()]
	if is_double_arrow(old_dir):
		# ★ 跨类型：↕ / ⤢ / ⤡ 三选一，排除自己
		var pool2 : Array = ALL_DOUBLE_ARROW.duplicate()
		pool2.erase(old_dir)
		return pool2[randi() % pool2.size()]
	return old_dir


## 判断 A 是否向"某方向"连通
static func has_dir(dir: int, target: int) -> bool:
	match target:
		Value.UP:    return dir == Value.UP or dir == Value.VERTICAL
		Value.DOWN:  return dir == Value.DOWN or dir == Value.VERTICAL
		Value.LEFT:  return dir == Value.LEFT or dir == Value.HORIZONTAL
		Value.RIGHT: return dir == Value.RIGHT or dir == Value.HORIZONTAL
	return false


## 判断 A 的斜线是否包含"NE"或"SW"端
static func has_diag_ne(dir: int) -> bool:
	return dir == Value.DIAG_NE_SW

static func has_diag_sw(dir: int) -> bool:
	return dir == Value.DIAG_NE_SW

static func has_diag_nw(dir: int) -> bool:
	return dir == Value.DIAG_NW_SE

static func has_diag_se(dir: int) -> bool:
	return dir == Value.DIAG_NW_SE


static func get_arrow_type_name(dir: int) -> String:
	if dir == Value.NONE: return "none"
	if is_single_arrow(dir): return "single"
	if is_diagonal(dir): return "diagonal"
	return "double"


static func get_display_symbol(dir: int) -> String:
	match dir:
		Value.UP: return "↑"
		Value.RIGHT: return "→"
		Value.DOWN: return "↓"
		Value.LEFT: return "←"
		Value.VERTICAL: return "↕"
		Value.HORIZONTAL: return "↔"
		Value.DIAG_NE_SW: return "⤢"
		Value.DIAG_NW_SE: return "⤡"
	return ""
