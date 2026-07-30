@tool
extends Node2D
class_name UnitPlacerTool

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

enum UnitType {
	剑士,
	枪兵,
	斧兵,
	弓兵,
	飞马,
	法师,
	修女,
	龙人,
	重甲兵
}

enum Team {
	玩家 = 0,
	敌人 = 1
}

@export var unit_type : UnitType = UnitType.剑士:
	set(value):
		unit_type = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")
@export var team : Team = Team.玩家:
	set(value):
		team = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")
@export var show_preview : bool = true:
	set(value):
		show_preview = value
		if Engine.is_editor_hint():
			_update_visibility()
@export var immobile : bool = false:
	set(value):
		if team == Team.玩家:
			immobile = false
		else:
			immobile = value
		if Engine.is_editor_hint():
			pass

@export var initial_items : Array[ItemEntry] = []
			
const CELL_SIZE : int = 16
const UNIT_SCENE_PATH = "res://content/scenes/units/Unit.tscn"

func _ready():
	if Engine.is_editor_hint():
		_build_preview()
		
func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	if Engine.is_editor_hint():
		if initial_items.size() > 5:
			warnings.append("初始道具数量超过5个，将只保留前5个")
		
		var default_id = UnitDataManagerClass.get_default_weapon_id(_get_unit_name())
		if default_id != "":
			var has_default = false
			for entry in initial_items:
				if entry and entry.item_id == default_id:
					has_default = true
					break
			if not has_default and initial_items.size() >= 5:
				warnings.append("默认武器 %s 将自动添加，当前已满5格，请移除一个道具以容纳" % default_id)
	return warnings

func _build_preview():
	_clear_all_children()

	var bg = ColorRect.new()
	bg.size = Vector2(CELL_SIZE, CELL_SIZE)
	bg.position = Vector2(CELL_SIZE/2.0, CELL_SIZE/2.0) - bg.size / 2
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -1
	add_child(bg)

	if not ResourceLoader.exists(UNIT_SCENE_PATH):
		return

	var unit_scene = load(UNIT_SCENE_PATH)
	var unit_instance = unit_scene.instantiate()
	if not unit_instance:
		return

	unit_instance.position = Vector2(CELL_SIZE/2.0, CELL_SIZE/2.0)
	unit_instance.process_mode = PROCESS_MODE_DISABLED
	unit_instance.input_pickable = false
	add_child(unit_instance)

	var unit_name = _get_unit_name()
	var team_id = 0 if team == Team.玩家 else 1
	var data = UnitDataManagerClass.get_unit_data(unit_name)

	var anim_sprite = unit_instance.get_node("Sprite") as AnimatedSprite2D
	if anim_sprite:
		var frames_path = data.get("sprite_frames_path", "")
		var loaded_ok = false
		if frames_path != "" and ResourceLoader.exists(frames_path):
			var frames = load(frames_path) as SpriteFrames
			if frames:
				anim_sprite.sprite_frames = frames
				anim_sprite.visible = true
				anim_sprite.z_index = 1
				loaded_ok = true

		if not loaded_ok:
			anim_sprite.visible = false

		_apply_shader_to_sprite(anim_sprite, team_id)
		anim_sprite.flip_h = (team_id == 1)

	var name_label = unit_instance.get_node("NameLabel") as Label
	if name_label:
		name_label.text = unit_name

	var hp_label = unit_instance.get_node("HPLabel") as Label
	if hp_label:
		hp_label.text = str(data["max_hp"]) + "/" + str(data["max_hp"])

	var terrain_label = unit_instance.get_node("TerrainInfoLabel") as Label
	if terrain_label:
		terrain_label.text = ""

	unit_instance.visible = true
	_update_visibility()
	if Engine.is_editor_hint():
		queue_redraw()

func _apply_texture_to_animated_sprite(anim_sprite: AnimatedSprite2D, data: Dictionary):
	var path = data.get("texture_path", "")
	if path and ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			var frames = SpriteFrames.new()
			frames.add_animation("idle")
			frames.add_frame("idle", texture)
			anim_sprite.sprite_frames = frames
			anim_sprite.play("idle")
			anim_sprite.playing = true
			return
	anim_sprite.visible = false

func _apply_shader_to_sprite(sprite: CanvasItem, team_id: int):
	var shader = preload("res://content/resource/shader/replace_color.gdshader") as Shader
	if not shader:
		sprite.modulate = Globals.get_team_color(team_id, true)
		return
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("target_color_1", Globals.TARGET_COLOR_1)
	mat.set_shader_parameter("target_color_2", Globals.TARGET_COLOR_2)
	mat.set_shader_parameter("assign_color_1", Globals.get_team_color(team_id, true))
	mat.set_shader_parameter("assign_color_2", Globals.get_team_color(team_id, false))
	sprite.material = mat
	sprite.modulate = Color.WHITE

func _clear_all_children():
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _update_visibility():
	for child in get_children():
		child.visible = show_preview

func _get_unit_name() -> String:
	match unit_type:
		UnitType.剑士: return "剑士"
		UnitType.枪兵: return "枪兵"
		UnitType.斧兵: return "斧兵"
		UnitType.弓兵: return "弓兵"
		UnitType.飞马: return "飞马"
		UnitType.法师: return "法师"
		UnitType.修女: return "修女"
		UnitType.龙人: return "龙人"
		UnitType.重甲兵: return "重甲兵"
		_: return "剑士"

func export_config() -> UnitConfig:
	var cfg = UnitConfig.new()
	cfg.unit_name = _get_unit_name()
	cfg.team_id = 0 if team == Team.玩家 else 1
	cfg.override_stats = {}
	cfg.immobile = (team == Team.敌人 and immobile)
	
	var items_to_export = initial_items.duplicate()
	var default_id = UnitDataManagerClass.get_default_weapon_id(cfg.unit_name)
	if default_id != "":
		var already_has = false
		for entry in items_to_export:
			if entry and entry.item_id == default_id:
				already_has = true
				break
		if not already_has:
			var weapon_entry = ItemEntry.new()
			weapon_entry.item_id = default_id
			weapon_entry.count = 1
			items_to_export.insert(0, weapon_entry)
	
	if items_to_export.size() > 5:
		items_to_export = items_to_export.slice(0, 5)
		push_warning("UnitPlacer: 初始道具（含默认武器）超过5个，已截断至前5个")
	cfg.initial_items = items_to_export
	
	var grid_pos = Vector2i(floor(position.x / CELL_SIZE), floor(position.y / CELL_SIZE))
	cfg.position = grid_pos
	return cfg
