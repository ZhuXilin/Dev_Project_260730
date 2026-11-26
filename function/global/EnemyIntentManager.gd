class_name EnemyIntentManager
extends RefCounted

## ============================================================
##  EnemyIntentManager — 敌人意图（v6.70e，位置后果 P0）
## ============================================================
##  设计口径（GameplayDesignDoc 十一·补 位置后果方案复核）：
##   · 敌人蓄力意图 = 可预告、可被位置后果反制的"非对称敌人规则"；
##   · 蓄力按敌方回合推进，满 N 回合后下次攻击按倍率释放；
##   · 被推动（击退位移 ≥1 格）即打断，清意图并给短暂硬直；
##   · 意图状态只在本场战斗有效，挂在 Unit 实例字段，不写存档。
##
##  不新增攻击按钮：蓄力/释放/打断都是 AI 自动行为与战斗事件结果。
## ============================================================

const CONFIG_FILE := "enemy_intent.json"

static var _cfg: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_cfg = GameConfigManager.get_file(CONFIG_FILE)
	_loaded = true


static func reload_config() -> void:
	_loaded = false
	_cfg = {}
	_ensure_loaded()


static func _global(key: String, fallback) -> Variant:
	_ensure_loaded()
	return _cfg.get(key, fallback)


## 取单位的意图配置（按 unit key 优先，其次 boss mechanic id）；无配置返回空。
static func get_intent_config(unit) -> Dictionary:
	if unit == null or not is_instance_valid(unit):
		return {}
	_ensure_loaded()
	var stats = unit.unit_stats
	if stats == null:
		return {}
	var key: String = str(stats.unit_name)
	var by_unit: Dictionary = _cfg.get("intent_by_unit", {})
	if by_unit.has(key):
		var d: Variant = by_unit.get(key, {})
		return d.duplicate(true) if d is Dictionary else {}
	var by_mech: Dictionary = _cfg.get("intent_by_boss_mechanic", {})
	var mid: String = str(stats.boss_mechanic_id)
	if mid != "" and by_mech.has(mid):
		var m: Variant = by_mech.get(mid, {})
		return m.duplicate(true) if m is Dictionary else {}
	return {}


## 战斗开场给有意图配置的敌人挂初始蓄力状态。
static func setup_for_unit(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var d: Dictionary = get_intent_config(unit)
	if d.is_empty():
		return
	unit.intent_label = str(d.get("label", "蓄力"))
	unit.intent_charge_rounds = maxi(1, int(d.get("charge_rounds", _global("charge_rounds", 2))))
	unit.intent_rounds_left = unit.intent_charge_rounds
	unit.intent_release_mult = maxf(1.0, float(d.get("release_damage_mult", _global("release_damage_mult", 2.0))))
	unit.intent_ready = false
	unit.refresh_intent_icon()


## 敌方回合推进：倒计时 -1，归零则就绪（下次攻击按倍率释放）。
static func advance_turn(unit) -> void:
	if unit == null or not is_instance_valid(unit) or unit.hit_points <= 0:
		return
	if unit.intent_charge_rounds <= 0:
		return
	if unit.intent_ready:
		return
	if unit.intent_rounds_left > 0:
		unit.intent_rounds_left -= 1
	if unit.intent_rounds_left <= 0:
		unit.intent_ready = true
		unit.refresh_intent_icon()
		SignalBus.request_hint_override.emit("⚡ %s · %s 完成" % [unit.intent_label, unit.unit_stats.unit_name], 1.0)
	else:
		unit.refresh_intent_icon()


## 被推动打断（击退位移 ≥1 格）：清蓄力/就绪状态，返回是否成功打断。
static func interrupt_on_push(unit, _source = null) -> bool:
	if not bool(_global("interrupt_on_push", true)):
		return false
	if unit == null or not is_instance_valid(unit) or unit.hit_points <= 0:
		return false
	if not is_charging(unit):
		return false
	var label: String = unit.intent_label
	unit.intent_rounds_left = 0
	unit.intent_ready = false
	unit.intent_charge_rounds = 0
	unit.intent_label = ""
	unit.refresh_intent_icon()
	var stun: int = maxi(0, int(_global("interrupt_stun_rounds", 1)))
	if stun > 0:
		unit.stun_rounds = maxi(unit.stun_rounds, stun)
	SignalBus.request_hint_override.emit("⚡ %s 被打断！" % label, 1.2)
	return true


## 是否处于蓄力中（含就绪待释放）
static func is_charging(unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	return unit.intent_charge_rounds > 0 and (unit.intent_rounds_left > 0 or unit.intent_ready)


## 攻击时消费就绪意图：返回本次攻击的伤害倍率（未就绪返回 1.0）。
static func consume_release_mult(unit) -> float:
	if unit == null or not is_instance_valid(unit) or not unit.intent_ready:
		return 1.0
	var mult: float = maxf(1.0, unit.intent_release_mult)
	unit.intent_ready = false
	unit.intent_charge_rounds = 0
	unit.intent_rounds_left = 0
	unit.intent_label = ""
	unit.refresh_intent_icon()
	SignalBus.request_hint_override.emit("⚡ 蓄力释放 ×%.1f" % mult, 1.0)
	return mult


## AI 评分：目标正在蓄力时的打断加分（击退可打断）。
static func ai_interrupt_bonus(unit) -> int:
	if not is_charging(unit):
		return 0
	return maxi(0, int(_global("ai_interrupt_bonus", 45)))
