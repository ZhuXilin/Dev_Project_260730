extends Resource
class_name AdvancedClassData

@export var id: String = ""
@export var name: String = ""
@export var base_unit: String = ""
@export var description: String = ""
@export var stat_bonus: Dictionary = {}
@export var granted_talent: String = ""
@export var flavor: String = ""
@export var sprite_frames_path: String = ""
@export var tags: Array[String] = []

# ★ 隐藏分支
@export var hidden: bool = false

# ★ 预留：若非空，则本进阶指向 unit_data.json 里一份独立条目，
#   加载时不再叠加 stat_bonus，只保留外观与专属词条。
#   空字符串表示走"基础 + 补丁"（默认行为）。
@export var standalone_unit_id: String = ""

static func from_dict(d: Dictionary, base_unit_key: String = "") -> AdvancedClassData:
	var r = AdvancedClassData.new()
	r.id = d.get("id", "")
	r.name = d.get("name", r.id)
	r.base_unit = base_unit_key
	r.description = d.get("description", "")
	r.stat_bonus = d.get("stat_bonus", {})
	r.granted_talent = d.get("granted_talent", "")
	r.flavor = d.get("flavor", "")
	r.sprite_frames_path = d.get("sprite_frames_path", "")
	r.hidden = bool(d.get("hidden", false))
	r.standalone_unit_id = d.get("standalone_unit_id", "")
	var tags_raw : Variant = d.get("tags", [])
	if tags_raw is Array:
		for t in tags_raw:
			if t is String:
				r.tags.append(t)
	return r
