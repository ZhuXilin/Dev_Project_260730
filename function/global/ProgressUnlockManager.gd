extends Node

# ============================================================
#  ProgressUnlockManager — 地图进度解锁（v5.16）
# ------------------------------------------------------------
#  替代原"魂解锁天赋/遗物"未接线通道：
#   - 锚点：GameState.campaign_progress（跨局累计通关节点数，存档持久化）
#   - 里程碑：content/data/config/progress_unlocks.json
#   - 达到阈值即永久解锁对应天赋/遗物，不消耗魂。
#  设计意图：让"推进地图 → 永久成长 → 下一局更强"的超循环在代码上真实可达。
# ============================================================

const CONFIG_FILE := "progress_unlocks.json"

var _talent_milestones : Array = []
var _relic_milestones : Array = []
## 已发放里程碑标记（避免读档/多次结算重复弹提示），随存档保存
var claimed_talent_milestones : Array = []
var claimed_relic_milestones : Array = []


func _ready():
	_load_config()


func _load_config():
	var cfg : Dictionary = GameConfigManager.get_file(CONFIG_FILE)
	var tm = cfg.get("talent_milestones", [])
	var rm = cfg.get("relic_milestones", [])
	_talent_milestones = []
	_relic_milestones = []
	if tm is Array:
		for m in (tm as Array):
			_talent_milestones.append(m)
	if rm is Array:
		for m in (rm as Array):
			_relic_milestones.append(m)
	_talent_milestones.sort_custom(_threshold_asc)
	_relic_milestones.sort_custom(_threshold_asc)


static func _threshold_asc(a, b) -> bool:
	return int((a as Dictionary).get("threshold", 0)) < int((b as Dictionary).get("threshold", 0))


# ============================================================
#  核心：结算进度（战斗胜利 / 读档后调用）
# ============================================================
## 返回本次新解锁的条目描述（用于结算 UI 展示），空数组表示无新解锁。
func sync_progress(show_toast: bool = false) -> Array:
	var newly : Array = []
	var p : int = GameState.campaign_progress

	for ms in _talent_milestones:
		var m : Dictionary = ms
		var th : int = int(m.get("threshold", 0))
		var key : String = "t%d" % th
		if p < th or key in claimed_talent_milestones:
			continue
		claimed_talent_milestones.append(key)
		var unlocked_any : bool = false
		for tid in m.get("talents", []):
			if tid is String and not Globals.is_talent_unlocked(tid):
				Globals.unlock_talent(tid)
				unlocked_any = true
				newly.append("★ 新天赋：%s" % _talent_name(tid))
		if unlocked_any and show_toast:
			SignalBus.request_hint_override.emit("地图进度达成「%s」：解锁新天赋" % str(m.get("title", "")), 3.0)

	for ms in _relic_milestones:
		var m2 : Dictionary = ms
		var th2 : int = int(m2.get("threshold", 0))
		var key2 : String = "r%d" % th2
		if p < th2 or key2 in claimed_relic_milestones:
			continue
		claimed_relic_milestones.append(key2)
		var got_any : bool = false
		# 只解锁尚未拥有的；已通过 Boss/事件解锁的不重复提示
		for rid in m2.get("relics", []):
			if rid is String and not RelicManager.is_relic_unlocked(rid):
				RelicManager.unlock_relic(rid)
				got_any = true
				newly.append("★ 新遗物：%s" % _relic_name(rid))
		if got_any and show_toast:
			SignalBus.request_hint_override.emit("地图进度达成「%s」：解锁新遗物" % str(m2.get("title", "")), 3.0)

	if not newly.is_empty():
		SaveManager.auto_save()
	return newly


func advance(show_toast: bool = true) -> Array:
	GameState.campaign_progress += 1
	return sync_progress(show_toast)


## 距离下一档天赋里程碑还差几个节点（供 UI 展示）
func next_talent_milestone() -> Dictionary:
	var p : int = GameState.campaign_progress
	for ms in _talent_milestones:
		var m : Dictionary = ms
		if p < int(m.get("threshold", 0)):
			return {"threshold": int(m.get("threshold", 0)), "remain": int(m.get("threshold", 0)) - p, "title": str(m.get("title", ""))}
	return {}


func _talent_name(tid: String) -> String:
	var d = TalentManager.get_talent_data(tid)
	if d and d.display_name != "":
		return d.display_name
	return tid


func _relic_name(rid: String) -> String:
	var d : Dictionary = RelicManager.get_relic_data(rid)
	return str(d.get("name", rid))


# ============================================================
#  存档：里程碑领取标记
# ============================================================
func get_claimed() -> Dictionary:
	return {
		"talent": claimed_talent_milestones.duplicate(),
		"relic": claimed_relic_milestones.duplicate(),
	}


func set_claimed(data) -> void:
	if not (data is Dictionary):
		return
	var d : Dictionary = data
	claimed_talent_milestones.clear()
	claimed_relic_milestones.clear()
	var tarr = d.get("talent", [])
	if tarr is Array:
		for t in (tarr as Array):
			claimed_talent_milestones.append(t)
	var rarr = d.get("relic", [])
	if rarr is Array:
		for r in (rarr as Array):
			claimed_relic_milestones.append(r)
