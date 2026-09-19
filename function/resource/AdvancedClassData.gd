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
	return r
