extends Node

# ============================================================
#  AnalyticsLogger — 本地数据埋点（v4.5）
#  仅 debug 版启用。每局结束写一行 JSON 到 user://analytics.log
# ============================================================

const LOG_PATH : String = "user://analytics.log"
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

		"sf_samples_total": 0,
		"sf_samples_burning": 0,
		"sf_samples_depleted": 0,
		"sf_samples_zero": 0,
		"sf_peak_ratio": 0.0,
		"sf_lowest_ratio": 1.0,

		# v4.5 新增
		"high_reward_node_available": 0,
		"high_reward_node_enter": 0,
		"high_reward_win": 0,
		"relic_refine_count": 0,
		"relic_refined_id_distribution": {},
	}


# ============================================================
#  魂火状态采样
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
#  FORGE 会话
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
#  派遣
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
#  v4.5 新增埋点
# ============================================================
func record_high_reward_node_available():
	if not ENABLED: return
	if _current.is_empty(): return
	_current["high_reward_node_available"] += 1


func record_high_reward_node_enter():
	if not ENABLED: return
	if _current.is_empty(): return
	_current["high_reward_node_enter"] += 1


func record_high_reward_win():
	if not ENABLED: return
	if _current.is_empty(): return
	_current["high_reward_win"] += 1


func record_relic_refine(relic_id : String):
	if not ENABLED: return
	if _current.is_empty(): return
	_current["relic_refine_count"] += 1
	var dist : Dictionary = _current["relic_refined_id_distribution"]
	dist[relic_id] = int(dist.get(relic_id, 0)) + 1


# ============================================================
#  竞技场结果即时打点
# ============================================================
func record_arena_result(reason : String, success : bool):
	if not ENABLED: return
	var record : Dictionary = {
		"event": "arena_result",
		"timestamp": int(Time.get_unix_time_from_system()),
		"reason": reason,
		"success": success,
	}
	_write_line(record)


# ============================================================
#  结算
# ============================================================
func finish_run(win : bool, rating : String = ""):
	if not ENABLED: return
	if _current.is_empty(): return
	_current["win"] = win
	_current["rating"] = rating
	var now : int = int(Time.get_unix_time_from_system())
	_current["duration_sec"] = now - int(_current["start_time"])
	_current["timestamp"] = now

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


# ============================================================
#  导出 CSV
# ============================================================
func export_csv():
	if not FileAccess.file_exists(LOG_PATH):
		print("[Analytics] 无日志文件：" + LOG_PATH)
		return

	var f : FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		push_warning("[Analytics] 无法打开 " + LOG_PATH)
		return
	var text : String = f.get_as_text()
	f.close()

	var lines : Array = text.split("\n", false)

	var run_rows : Array = []
	var arena_rows : Array = []

	var run_keys : Array = [
		"timestamp", "win", "rating", "day_reached", "duration_sec",
		"forge_visits", "forge_total_time_sec", "forge_decisions",
		"dispatch_count", "dispatch_tag_match_count",
		"sacrifice_count", "talent_unlock_count",
		"sf_samples_total", "sf_time_in_burning", "sf_time_in_depleted", "sf_time_in_zero",
		"sf_peak_ratio", "sf_lowest_ratio",
		"high_reward_node_available", "high_reward_node_enter", "high_reward_win",
		"relic_refine_count", "relic_refined_id_distribution",
	]
	var arena_keys : Array = ["timestamp", "reason", "success"]

	for line in lines:
		var s : String = line.strip_edges()
		if s == "":
			continue
		var d = JSON.parse_string(s)
		if not (d is Dictionary):
			continue
		if d.has("event") and str(d["event"]) == "arena_result":
			arena_rows.append(d)
		elif d.has("win"):
			run_rows.append(d)

	_write_csv("user://analytics_runs.csv", run_keys, run_rows)
	_write_csv("user://analytics_arena.csv", arena_keys, arena_rows)
	print("[Analytics] CSV 已导出：analytics_runs.csv（%d 行）、analytics_arena.csv（%d 行）" % [
		run_rows.size(), arena_rows.size()])


func _write_csv(path : String, keys : Array, rows : Array):
	var f : FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[Analytics] 无法写入 " + path)
		return
	var header : Array = []
	for k in keys:
		header.append(_csv_escape(k))
	f.store_line(",".join(header))
	for row in rows:
		var cells : Array = []
		for k in keys:
			cells.append(_csv_escape(row.get(k, "")))
		f.store_line(",".join(cells))
	f.close()


func _csv_escape(v : Variant) -> String:
	var s : String = str(v)
	if s.find(",") != -1 or s.find("\"") != -1 or s.find("\n") != -1:
		s = s.replace("\"", "\"\"")
		return "\"%s\"" % s
	return s


# ============================================================
#  汇总
# ============================================================
func dump_summary():
	if not FileAccess.file_exists(LOG_PATH):
		print("[Analytics] 无日志文件：" + LOG_PATH)
		return
	var f : FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		push_warning("[Analytics] 无法打开 " + LOG_PATH)
		return
	var text : String = f.get_as_text()
	f.close()

	var lines : Array = text.split("\n", false)
	var total : int = 0
	var wins : int = 0
	var s_count : int = 0
	var forge_time_total : float = 0.0
	var forge_visits_total : int = 0
	var sf_burning_total : float = 0.0
	var sf_depleted_total : float = 0.0
	var sf_zero_total : float = 0.0
	var dispatch_total : int = 0
	var dispatch_match_total : int = 0
	var sacrifice_total : int = 0
	var day_reached_max : int = 1
	var arena_records : int = 0
	var arena_success : int = 0
	var arena_by_reason : Dictionary = {}

	var high_avail_total : int = 0
	var high_enter_total : int = 0
	var high_win_total : int = 0
	var relic_refine_total : int = 0

	for line in lines:
		var s : String = line.strip_edges()
		if s == "":
			continue
		var d = JSON.parse_string(s)
		if not (d is Dictionary):
			continue
		if d.has("event") and str(d["event"]) == "arena_result":
			arena_records += 1
			if bool(d.get("success", false)):
				arena_success += 1
			var reason : String = str(d.get("reason", "?"))
			arena_by_reason[reason] = int(arena_by_reason.get(reason, 0)) + 1
			continue

		total += 1
		if bool(d.get("win", false)):
			wins += 1
		if str(d.get("rating", "")) == "S":
			s_count += 1
		forge_time_total += float(d.get("forge_total_time_sec", 0.0))
		forge_visits_total += int(d.get("forge_visits", 0))
		sf_burning_total += float(d.get("sf_time_in_burning", 0.0))
		sf_depleted_total += float(d.get("sf_time_in_depleted", 0.0))
		sf_zero_total += float(d.get("sf_time_in_zero", 0.0))
		dispatch_total += int(d.get("dispatch_count", 0))
		dispatch_match_total += int(d.get("dispatch_tag_match_count", 0))
		sacrifice_total += int(d.get("sacrifice_count", 0))
		day_reached_max = maxi(day_reached_max, int(d.get("day_reached", 1)))
		high_avail_total += int(d.get("high_reward_node_available", 0))
		high_enter_total += int(d.get("high_reward_node_enter", 0))
		high_win_total += int(d.get("high_reward_win", 0))
		relic_refine_total += int(d.get("relic_refine_count", 0))

	var total_f : float = maxf(1.0, float(total))

	print("========== Analytics 汇总 ==========")
	print("日志路径：%s" % LOG_PATH)
	print("局数：%d    最远天数：第 %d 天" % [total, day_reached_max])
	print("通关率：%.1f%%（%d / %d）" % [
		100.0 * float(wins) / total_f, wins, total])
	print("S 评级：%.1f%%（%d 次）" % [
		100.0 * float(s_count) / total_f, s_count])
	print("FORGE：平均 %.1f 秒/次，共 %d 次" % [
		forge_time_total / maxf(1.0, float(forge_visits_total)),
		forge_visits_total])
	print("魂火时间占比：燃烧 %.1f%% ｜ 枯竭 %.1f%% ｜ 归零 %.1f%%" % [
		100.0 * sf_burning_total / total_f,
		100.0 * sf_depleted_total / total_f,
		100.0 * sf_zero_total / total_f])
	print("派遣：共 %d，匹配 %d（%.1f%%）" % [
		dispatch_total, dispatch_match_total,
		100.0 * float(dispatch_match_total) / maxf(1.0, float(dispatch_total))])
	print("献祭：共 %d（局均 %.2f）" % [
		sacrifice_total, float(sacrifice_total) / total_f])
	print("高收益节点：可用 %d，进入 %d，胜利 %d" % [
		high_avail_total, high_enter_total, high_win_total])
	print("遗物精炼：共 %d 次（局均 %.2f）" % [
		relic_refine_total, float(relic_refine_total) / total_f])
	print("竞技场：%d 场（成功 %d）" % [arena_records, arena_success])
	for r in arena_by_reason:
		print("  - %s: %d" % [r, arena_by_reason[r]])
	print("=====================================")
