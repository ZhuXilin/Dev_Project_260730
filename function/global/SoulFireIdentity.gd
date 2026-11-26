class_name SoulFireIdentity
extends RefCounted

## ============================================================
##  SoulFireIdentity — 魂火身份（v6.64）
## ============================================================
##  转职 = 魂火身份升级：每个单位有独特的燃烧态特有效果与爆发附加。
##  数据来自 content/data/config/soulfire_identity.json。
##  与 v6.63 体系兼容：爆发仍在技能按钮内、仍清空魂火、仍结束行动；
##  转职仍只给被动——变的是"效果"，不是"入口"。
## ============================================================

const CFG_FILE: String = "soulfire_identity.json"
const DEFAULT_BURN: Dictionary = {
	"id": "none", "desc": "",
}
const DEFAULT_BURST: Dictionary = {
	"id": "none", "desc": "",
}

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var raw: Variant = GameConfigManager.get_value(CFG_FILE, "units", null)
	# ★ v6.72c：读空不锁定——若首次访问早于 GameConfigManager.load_all()，
	#   旧实现会把 _loaded 永久置 true，导致配置永远读不到（此前死配置根因之一）。
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		_data = raw as Dictionary
		_loaded = true


static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


## 取单位的基础身份配置（unit_name → Dictionary）
static func get_unit_identity(unit_name: String) -> Dictionary:
	_ensure_loaded()
	var d: Variant = _data.get(unit_name, null)
	return d as Dictionary if d is Dictionary else {}


## 取转职分支的身份覆盖（advanced_class id → Dictionary）
static func get_advanced_override(advanced_class: String) -> Dictionary:
	if advanced_class == "":
		return {}
	_ensure_loaded()
	var raw: Variant = GameConfigManager.get_value(CFG_FILE, "advanced_overrides", null)
	if not (raw is Dictionary):
		return {}
	var d: Variant = (raw as Dictionary).get(advanced_class, null)
	return d as Dictionary if d is Dictionary else {}


## 合成单位最终身份：基础 + 转职覆盖（burst_label/hud_icon/name 等被覆盖）
static func resolve(unit_name: String, advanced_class: String = "") -> Dictionary:
	var base: Dictionary = get_unit_identity(unit_name).duplicate(true)
	var ov: Dictionary = get_advanced_override(advanced_class)
	for k in ov:
		if k == "_doc":
			continue
		base[k] = ov[k]
	return base


## 燃烧态特有效果（战斗内读取 id 与数值字段）
static func get_burn_trait(unit_name: String, advanced_class: String = "") -> Dictionary:
	var d: Dictionary = resolve(unit_name, advanced_class)
	var t: Variant = d.get("burn_trait", null)
	return t as Dictionary if t is Dictionary else DEFAULT_BURN.duplicate()


## 爆发附加效果
static func get_burst_trait(unit_name: String, advanced_class: String = "") -> Dictionary:
	var d: Dictionary = resolve(unit_name, advanced_class)
	var t: Variant = d.get("burst_trait", null)
	return t as Dictionary if t is Dictionary else DEFAULT_BURST.duplicate()


## 爆发文案（技能按钮用）：优先转职覆盖，其次单位身份，最后通用
static func get_burst_label(unit_name: String, advanced_class: String = "") -> String:
	var d: Dictionary = resolve(unit_name, advanced_class)
	var label: String = str(d.get("burst_label", ""))
	if label != "":
		return label
	var t: Dictionary = get_burst_trait(unit_name, advanced_class)
	var desc: String = str(t.get("desc", ""))
	return desc if desc != "" else "爆发"


## 魂火 HUD 图标字符
static func get_hud_icon(unit_name: String, advanced_class: String = "") -> String:
	var d: Dictionary = resolve(unit_name, advanced_class)
	return str(d.get("hud_icon", ""))


## 转职后名号（无覆盖时返回空串）
static func get_advanced_name(advanced_class: String) -> String:
	return str(get_advanced_override(advanced_class).get("name", ""))


## 爆发倍率配置（含 threshold 触发阈值、shield_reduction_cap 等）
static func get_burst_config() -> Dictionary:
	_ensure_loaded()
	var raw: Variant = GameConfigManager.get_value(CFG_FILE, "burst_multiplier", null)
	return raw as Dictionary if raw is Dictionary else {}


## 魂火通用底盘（燃烧阈值/移动+1/溅射50%），所有单位共用
static func get_common_base() -> Dictionary:
	_ensure_loaded()
	var raw: Variant = GameConfigManager.get_value(CFG_FILE, "common_base", null)
	return raw as Dictionary if raw is Dictionary else {}


## 技能自动爆发的魂火阈值（v6.66 身份化）。
##   优先：单位身份 burst_threshold → 转职覆盖 → 全局 burst_multiplier.threshold（默认 3）。
##   无参调用保留兼容（返回全局阈值）。
static func get_burst_threshold(unit_name: String = "", advanced_class: String = "") -> int:
	if unit_name != "":
		var ident: Dictionary = resolve(unit_name, advanced_class)
		var v: Variant = ident.get("burst_threshold", null)
		if v != null and int(v) > 0:
			return maxi(1, int(v))
	return maxi(1, int(get_burst_config().get("threshold", 3)))
