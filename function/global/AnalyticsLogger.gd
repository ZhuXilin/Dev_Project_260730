extends Node

# ============================================================
#  AnalyticsLogger — 本地数据埋点（v4.1）
#  仅 debug 版启用。每局结束写一行 JSON 到 user://analytics.log
#  用途：试玩后回看"设计文档第八节"的 7 项风险指标
# ============================================================

const LOG_PATH : String = "user://analytics.log"
## ★ 注意：不能用 const，因为 OS.is_debug_build() 是运行时函数。
## 作为 autoload 单例，var 只在游戏启动时求值一次。
var ENABLED : bool = OS.is_debug_build()

var _current : Dictionary = {}
var _forge_enter_msec : int = 0


# ============================================================
#  开局
# ============================================================
func begin_run():
	if not ENABLED: return
	_current = {
		"start_time": Time.get_unix_time_from_system(),
		"day_reached": 1,

		"forge_visits": 0,
		"forge_total_time_sec": 0.0,
		"forge_decisions": 0,

		"dispatch_count": 0,
		"dispatch_tag_match_count": 0,
		"sacrifice_count": 0,
		"talent_unlock_count": 0,

		# 魂火状态采样（按玩家回合数统计）
		"sf_samples_total": 0,
		"sf_samples_burning": 0,
		"sf_samples_depleted": 0,
		"sf_samples_zero": 0,
		"sf_peak_ratio": 0.0,
		"sf_lowest_ratio": 1.0,
	}


# ============================================================
#  魂火状态采样（每个玩家回合调一次）
# ============================================================
func record_soul_fire_sample():
	if not ENABLED: return
	if _current.is_empty(): return
	var r : float = SoulFireManager.get_ratio()
	var state : int = SoulFireManager.get_state()
	_current["sf_samples_total"] += 1
	match state:
		SoulFireManager.State.BURNING:
			_current["sf_samples_burning"] += 1
		SoulFireManager.State.DEPLETED:
			_current["sf_samples_depleted"] += 1
		SoulFireManager.State.ZERO:
			_current["sf_samples_zero"] += 1
	_current["sf_peak_ratio"] = maxf(_current["sf_peak_ratio"], r)
	_current["sf_lowest_ratio"] = minf(_current["sf_lowest_ratio"], r)


# ============================================================
#  FORGE 会话（进入/离开打点）
# ============================================================
func begin_forge_session():
	if not ENABLED: return
	_forge_enter_msec = Time.get_ticks_msec()


func finish_forge_session(decisions : int = 0):
	if not ENABLED: return
	if _current.is_empty(): return
	if _forge_enter_msec <= 0: return
	var dur_ms : int = Time.get_ticks_msec() - _forge_enter_msec
	_current["forge_visits"] += 1
	_current["forge_total_time_sec"] += float(dur_ms) / 1000.0
	_current["forge_decisions"] += decisions
	_forge_enter_msec = 0


# ============================================================
#  派遣（每次完成一条路线调一次）
# ============================================================
func record_dispatch(matched : bool):
	if not ENABLED: return
	if _current.is_empty(): return
	_current["dispatch_count"] += 1
	if matched:
		_current["dispatch_tag_match_count"] += 1


# ============================================================
#  献祭 / 词条解锁
# ============================================================
func record_sacrifice():
	if not ENABLED: return
	if _current.is_empty(): return
	_current["sacrifice_count"] += 1


func record_talent_unlock():
	if not ENABLED: return
	if _current.is_empty(): return
	_current["talent_unlock_count"] += 1


# ============================================================
#  天数推进
# ============================================================
func record_day_reached(day : int):
	if not ENABLED: return
	if _current.is_empty(): return
	_current["day_reached"] = maxi(_current["day_reached"], day)


# ============================================================
#  结算（写一行 JSON）
# ============================================================
func finish_run(win : bool, rating : String = ""):
	if not ENABLED: return
	if _current.is_empty(): return
	_current["win"] = win
	_current["rating"] = rating
	var now : int = int(Time.get_unix_time_from_system())
	_current["duration_sec"] = now - int(_current["start_time"])
	_current["timestamp"] = now

	# 派生指标
	var total : int = maxi(1, int(_current["sf_samples_total"]))
	_current["sf_time_in_burning"]  = float(_current["sf_samples_burning"])  / float(total)
	_current["sf_time_in_depleted"] = float(_current["sf_samples_depleted"]) / float(total)
	_current["sf_time_in_zero"]     = float(_current["sf_samples_zero"])     / float(total)

	_write_line(_current)
	_current.clear()
	_forge_enter_msec = 0


func _write_line(dict : Dictionary):
	var f : FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Analytics] 无法写入 " + LOG_PATH)
		return
	f.seek_end()
	f.store_line(JSON.stringify(dict))
	f.close()
