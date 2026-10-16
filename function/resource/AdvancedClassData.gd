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

# ★ 新增：隐藏分支。true 时默认不出现在英雄殿，需剧情 unlock 才可见
@export var hidden: bool = false

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
	r.hidden = bool(d.get("hidden", false))     # ★ 读 hidden 字段
	var tags_raw : Variant = d.get("tags", [])
	if tags_raw is Array:
		for t in tags_raw:
			if t is String:
				r.tags.append(t)
	return r
