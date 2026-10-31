@tool
extends Node2D
class_name UnitPlacerTool

# ============================================================
#  枚举定义
# ============================================================
enum PlacementMode {
	FIXED_UNIT,
	SPAWN_POINT,
	RANDOM_POOL,
}

enum UnitType {
	剑士, 枪兵, 斧兵, 弓兵, 飞马, 法师, 修女, 龙人, 重甲兵
}

enum Team {
	玩家 = 0,
	敌人 = 1
}

const WAVE_LABELS : Array = ["首发", "第2波", "第3波", "第4波", "第5波", "第6波"]

static var _avatar_file_cache : PackedStringArray = []


# ============================================================
#  导出属性区
# ============================================================
@export_category("基础设置")
@export var placement_mode: PlacementMode = PlacementMode.FIXED_UNIT:
	set(value):
		placement_mode = value
		notify_property_list_changed()
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

@export var team : Team = Team.玩家:
	set(value):
		team = value
		notify_property_list_changed()
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

@export var show_preview : bool = true:
	set(value):
		show_preview = value
		if Engine.is_editor_hint():
			_update_visibility()


@export_category("固定单位设置")

@export var unit_type : UnitType = UnitType.剑士:
	set(value):
		if unit_type != value:
			unit_type = value
			advanced_class_idx = 0
			notify_property_list_changed()
			if Engine.is_editor_hint():
				call_deferred("_build_preview")

@export var advanced_class_idx : int = 0:
	set(value):
		advanced_class_idx = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

var advanced_class_id : String:
	get:
		if advanced_class_idx <= 0: return ""
		var branches : Array = _get_branches_for_current_unit()
		var i : int = advanced_class_idx - 1
		if i >= 0 and i < branches.size():
			return str((branches[i] as Dictionary).get("id", ""))
		return ""

@export var avatar_idx : int = 0:
	set(value):
		avatar_idx = maxi(0, value)
		_refresh_avatar_preview()
		if Engine.is_editor_hint():
			notify_property_list_changed()
			call_deferred("_build_preview")

@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "Texture2D", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var avatar_preview_display : Texture2D = null

var avatar_id : String:
	get:
		if avatar_idx <= 0: return ""
		_ensure_avatar_file_cache()
		var i : int = avatar_idx - 1
		if i >= 0 and i < _avatar_file_cache.size():
			return _avatar_file_cache[i]
		return ""

@export var immobile : bool = false:
	set(value):
		if team == Team.玩家:
			if immobile != false:
				immobile = false
		elif immobile != value:
			immobile = value

@export var is_boss : bool = false


@export_category("出生点设置")
@export var spawn_index: int = 0:
	set(value):
		spawn_index = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")


@export_category("随机池设置")
@export var pool_key: String = "":
	set(value):
		pool_key = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

# ★ 使用自定义 Resource 数组，方便 UI 下拉
@export var enemy_pool_entries: Array[UnitPoolEntry] = []:
	set(value):
		enemy_pool_entries = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")


@export_category("波次设置")
@export var wave_idx : int = 0:
	set(value):
		wave_idx = clampi(value, 0, WAVE_LABELS.size() - 1)
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

var wave : int:
	get:
		return wave_idx + 1


# ============================================================
#  内部方法
# ============================================================
func _refresh_avatar_preview():
	var aid = avatar_id
	if aid == "":
		avatar_preview_display = null
	else:
		avatar_preview_display = IconManager.get_icon_or_null(aid)


func _ensure_avatar_file_cache():
	if not _avatar_file_cache.is_empty(): return
	var dir_path = "res://content/images/characters/avatar/"
	var files : Array = []
	if DirAccess.dir_exists_absolute(dir_path):
		var dir = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var fname = dir.get_next()
			while fname != "":
				if not dir.current_is_dir() and fname.ends_with(".png"):
					files.append(fname.get_basename())
				fname = dir.get_next()
			dir.list_dir_end()
	files.sort()
	_avatar_file_cache = PackedStringArray(files)


func _validate_property(property : Dictionary) -> void:
	var hide_it : bool = false

	match property.name:
		"spawn_index":
			if placement_mode != PlacementMode.SPAWN_POINT: hide_it = true
		"pool_key", "enemy_pool_entries":
			if placement_mode != PlacementMode.RANDOM_POOL: hide_it = true

		"unit_type", "advanced_class_idx", "immobile", "is_boss", "avatar_idx":
			if placement_mode == PlacementMode.RANDOM_POOL \
					or placement_mode == PlacementMode.SPAWN_POINT:
				hide_it = true

		"avatar_idx", "avatar_preview_display", "is_boss", "immobile":
			if team == Team.玩家:
				hide_it = true

		"wave_idx":
			if placement_mode == PlacementMode.SPAWN_POINT:
				hide_it = true
			elif placement_mode == PlacementMode.FIXED_UNIT and team == Team.玩家:
				hide_it = true

	if hide_it:
		property.usage &= ~PROPERTY_USAGE_EDITOR
		return

	if property.name == "wave_idx":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(WAVE_LABELS)

	if property.name == "advanced_class_idx":
		var items : PackedStringArray = ["（无）"]
		var branches : Array = _get_branches_for_current_unit()
		for b in branches:
			if b is Dictionary:
				var bname : String = str(b.get("name", ""))
				items.append(bname if bname != "" else str(b.get("id", "?")))
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(items)

	if property.name == "avatar_idx":
		_ensure_avatar_file_cache()
		var items : PackedStringArray = ["（无头像）"]
		for f in _avatar_file_cache:
			items.append(f)
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(items)


func _get_branches_for_current_unit() -> Array:
	var ud : Dictionary = UnitDataManager.get_unit_data(_get_json_key())
	if ud.is_empty(): return []
	var raw : Variant = ud.get("advanced_branches", [])
	if not (raw is Array): return []
	var result : Array = []
	for b in raw:
		if b is Dictionary:
			result.append(b)
	return result


# ============================================================
#  生命周期 / 预览 / 警告
# ============================================================
const UNIT_SCENE_PATH = Config.PATHS.UNIT_SCENE
const UNIT_TYPE_TO_JSON_KEY = {
	UnitType.剑士: "swordsman",
	UnitType.枪兵: "spearman",
	UnitType.斧兵: "axeman",
	UnitType.弓兵: "archer",
	UnitType.飞马: "pegasus",
	UnitType.法师: "mage",
	UnitType.修女: "cleric",
	UnitType.龙人: "dragonborn",
	UnitType.重甲兵: "armored"
}

func _ready():
	if Engine.is_editor_hint():
		_refresh_avatar_preview()
		_build_preview()
		return


func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	if Engine.is_editor_hint():
		var pos = position
		var cell_size = MapConst.CELL_SIZE
		if abs(fmod(pos.x, cell_size)) >= 0.01 or abs(fmod(pos.y, cell_size)) >= 0.01:
			warnings.append("节点位置未对齐到网格顶点（应位于格子角点，坐标应为 %d 的整数倍）。建议使用网格吸附功能。" % MapConst.CELL_SIZE)

		if placement_mode == PlacementMode.FIXED_UNIT:
			var branches : Array = _get_branches_for_current_unit()
			if advanced_class_idx > branches.size():
				warnings.append("advanced_class_idx=%d 越界（当前 %s 只有 %d 个进阶分支），会自动视为「无」" % [advanced_class_idx, _get_json_key(), branches.size()])
			var aid : String = avatar_id
			if aid != "":
				var p : String = "res://content/images/characters/avatar/%s.png" % aid
				if not ResourceLoader.exists(p):
					warnings.append("头像文件不存在: " + p)

		elif placement_mode == PlacementMode.SPAWN_POINT:
			if spawn_index < 0 or spawn_index > 5:
				warnings.append("spawn_index 应在 0~5 范围内（通常对应队伍人数）")

		elif placement_mode == PlacementMode.RANDOM_POOL:
			# ★ 安全防护：检查空元素
			var has_invalid = false
			for e in enemy_pool_entries:
				if e == null:
					has_invalid = true
					break
			if has_invalid:
				warnings.append("随机池中存在空元素，请删除后重新添加。")
			elif pool_key == "" and enemy_pool_entries.is_empty():
				warnings.append("RANDOM_POOL 格子没有池子：要么填 pool_key（与其他格子共享），要么在列表中添加可用单位。")
			if team == Team.玩家:
				warnings.append("RANDOM_POOL 一般用于敌方。玩家单位请用 FIXED_UNIT / SPAWN_POINT")
	return warnings


func _build_preview():
	if not Engine.is_editor_hint(): return
	_clear_all_children()
	match placement_mode:
		PlacementMode.SPAWN_POINT: _build_spawn_point_preview()
		PlacementMode.RANDOM_POOL: _build_random_pool_preview()
		_: _build_unit_preview()


func _build_spawn_point_preview():
	var bg = ColorRect.new()
	bg.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	bg.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0) - bg.size / 2
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -1
	bg.color = MapConst.HIGHLIGHT_SPAWN
	add_child(bg)

	var label = Label.new()
	label.text = "S" + str(spawn_index)
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	label.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0) - label.size / 2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _build_random_pool_preview():
	var bg = ColorRect.new()
	bg.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	bg.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0) - bg.size / 2
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -1
	bg.color = Color(0.9, 0.5, 0.1, 0.35)
	add_child(bg)

	var key_text : String = pool_key if pool_key != "" else "内联"

	var label = Label.new()
	label.text = "R%s" % [key_text] 
	label.add_theme_font_size_override("font_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	label.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0) - label.size / 2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	if not enemy_pool_entries.is_empty():
		var adv_count : int = 0
		var valid_count : int = 0
		for entry in enemy_pool_entries:
			# ★ 安全防护：防止旧地图加载时出现空对象导致死机
			if entry == null: continue
			valid_count += 1
			if entry.advanced_class_idx > 0:
				adv_count += 1
		var sub = Label.new()
		sub.text = "池%d" % valid_count
		if adv_count > 0:
			sub.text += " / 进%d" % adv_count
			sub.modulate = Color(1.0, 0.85, 0.4)
		else:
			sub.modulate = Color(1.0, 0.8, 0.4)
		sub.add_theme_font_size_override("font_size", 6)
		sub.position = Vector2(0, MapConst.CELL_SIZE + 2)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sub)


func _build_unit_preview():
	var bg = ColorRect.new()
	bg.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	bg.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0) - bg.size / 2
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -1
	add_child(bg)

	if not ResourceLoader.exists(UNIT_SCENE_PATH): return
	var unit_scene = load(UNIT_SCENE_PATH)
	var unit_instance = unit_scene.instantiate()
	if not unit_instance: return

	unit_instance.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0)
	unit_instance.process_mode = PROCESS_MODE_DISABLED
	unit_instance.input_pickable = false
	add_child(unit_instance)

	var json_key = _get_json_key()
	var data = UnitDataManager.get_unit_data(json_key)

	var frames_path : String = data.get("sprite_frames_path", "")
	var adv_hp_bonus : int = 0
	if advanced_class_idx > 0:
		var branches : Array = _get_branches_for_current_unit()
		var i : int = advanced_class_idx - 1
		if i >= 0 and i < branches.size():
			var bd : Dictionary = branches[i]
			var adv_path : String = str(bd.get("sprite_frames_path", ""))
			if adv_path != "" and ResourceLoader.exists(adv_path): frames_path = adv_path
			var sb : Dictionary = bd.get("stat_bonus", {})
			adv_hp_bonus = int(sb.get("max_hp", 0))

	var anim_sprite = unit_instance.get_node("Sprite") as AnimatedSprite2D
	if anim_sprite:
		var loaded_ok = false
		if frames_path != "" and ResourceLoader.exists(frames_path):
			var frames = load(frames_path) as SpriteFrames
			if frames:
				anim_sprite.sprite_frames = frames
				anim_sprite.visible = true
				anim_sprite.z_index = 1
				loaded_ok = true
		if not loaded_ok: anim_sprite.visible = false

		var team_id = 0 if team == Team.玩家 else 1
		_apply_shader_to_sprite(anim_sprite, team_id)
		anim_sprite.flip_h = (team_id == 1)

	var hp_label = unit_instance.get_node_or_null("HPLabel") as Label
	if hp_label:
		var max_hp = int(data.get("max_hp", 20)) + adv_hp_bonus
		hp_label.text = str(max_hp) + "/" + str(max_hp)
		hp_label.visible = true

	unit_instance.visible = true
	_update_visibility()
	if Engine.is_editor_hint(): queue_redraw()


func _apply_shader_to_sprite(sprite: CanvasItem, team_id: int):
	if team_id != 0 and team_id != 1: team_id = 0
	if not sprite: return
	var shader = preload(Config.PATHS.SHADER_REPLACE_COLOR) as Shader
	if not shader:
		var color = Color(0.1216, 0.2196, 0.9373) if team_id == 0 else Color(0.8784, 0.0, 0.3725)
		sprite.modulate = color
		return
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("target_color_1", Globals.TARGET_COLOR_1)
	mat.set_shader_parameter("target_color_2", Globals.TARGET_COLOR_2)
	var colors = Globals.TEAM_COLORS.get(team_id, Globals.TEAM_COLORS[0])
	mat.set_shader_parameter("assign_color_1", colors["primary"])
	mat.set_shader_parameter("assign_color_2", colors["secondary"])
	sprite.material = mat
	sprite.modulate = Color.WHITE


func _clear_all_children():
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _update_visibility():
	for child in get_children(): child.visible = show_preview

func _get_json_key() -> String:
	return UNIT_TYPE_TO_JSON_KEY.get(unit_type, "swordsman")


# ============================================================
#  导出配置
# ============================================================
func export_config() -> Variant:
	var grid_pos = Vector2i(floor(position.x / MapConst.CELL_SIZE), floor(position.y / MapConst.CELL_SIZE))

	if placement_mode == PlacementMode.SPAWN_POINT:
		return {
			"type": "spawn_point",
			"position": grid_pos,
			"spawn_index": spawn_index
		}

	var cfg = UnitConfig.new()
	cfg.position = grid_pos
	cfg.team_id = 0 if team == Team.玩家 else 1
	cfg.wave = wave
	cfg.is_boss = (team == Team.敌人 and is_boss)
	cfg.immobile = (team == Team.敌人 and immobile)

	if placement_mode == PlacementMode.RANDOM_POOL:
		cfg.unit_name = ""
		cfg.is_random_pool = true
		cfg.pool_key = pool_key
		
		cfg.enemy_pool.clear()
		for entry in enemy_pool_entries:
			if entry == null: continue
			if entry.advanced_class_id == "":
				cfg.enemy_pool.append(entry.unit_key)
			else:
				cfg.enemy_pool.append("%s:%s" % [entry.unit_key, entry.advanced_class_id])
				
		return cfg

	cfg.unit_name = _get_json_key()
	cfg.override_stats = {}
	cfg.advanced_class_id = advanced_class_id
	cfg.avatar_override = avatar_id
	return cfg
