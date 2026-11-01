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

enum Team {
	玩家 = 0,
	敌人 = 1
}

const WAVE_LABELS : Array = ["首发", "第2波", "第3波", "第4波", "第5波", "第6波"]

const UNIT_SCENE_PATH = Config.PATHS.UNIT_SCENE
const UNIT_DATA_PATH = "res://content/data/unit_data.json"

static var _avatar_file_cache : PackedStringArray = []
static var _editor_unit_db : Dictionary = {} # 编辑器兜底缓存


# ============================================================
#  核心工具：清理 Godot 自动拼接的脏数据
#  (例如把 "armored:重甲兵" 变成 "armored")
# ============================================================
func _clean_id(raw_id: String) -> String:
	if raw_id == "（无）" or raw_id == "": return ""
	if raw_id.contains(":"): 
		return raw_id.split(":")[0]
	return raw_id


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

@export var unit_name : String = "swordsman":
	set(value):
		if unit_name != value:
			unit_name = value
			advanced_class_id = "（无）"   # 换单位时重置为"（无）"
			notify_property_list_changed()
			if Engine.is_editor_hint():
				call_deferred("_build_preview")

@export var advanced_class_id : String = "（无）":
	set(value):
		if advanced_class_id != value:
			advanced_class_id = value
			if Engine.is_editor_hint():
				call_deferred("_build_preview")

@export var avatar_id : String = "":
	set(value):
		if avatar_id != value:
			avatar_id = value
			_refresh_avatar_preview()
			notify_property_list_changed()
			if Engine.is_editor_hint():
				call_deferred("_build_preview")

@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "Texture2D", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var avatar_preview_display : Texture2D = null

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

@export var enemy_pool: Array[String] = []:
	set(value):
		enemy_pool = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

@export_tool_button("编辑随机池", "Edit")
var edit_pool_btn: Callable = _open_pool_editor

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
	if avatar_id == "":
		avatar_preview_display = null
	else:
		avatar_preview_display = IconManager.get_icon_or_null(avatar_id)

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


# 动态生成中文下拉 + 隐藏无关字段
func _validate_property(property : Dictionary) -> void:
	var hide_it : bool = false

	match property.name:
		"spawn_index":
			if placement_mode != PlacementMode.SPAWN_POINT: hide_it = true
		"pool_key", "enemy_pool", "edit_pool_btn":
			if placement_mode != PlacementMode.RANDOM_POOL: hide_it = true

		"unit_name", "advanced_class_id", "immobile", "is_boss", "avatar_id":
			if placement_mode == PlacementMode.RANDOM_POOL \
					or placement_mode == PlacementMode.SPAWN_POINT:
				hide_it = true

		"avatar_id", "avatar_preview_display", "is_boss", "immobile":
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

	if property.name == "unit_name":
		var items : PackedStringArray = []
		var fallback_names = {
			"swordsman": "剑士", "spearman": "枪兵", "axeman": "斧兵",
			"archer": "弓兵", "pegasus": "飞马", "mage": "法师",
			"cleric": "修女", "dragonborn": "龙人", "armored": "重甲兵"
		}
		for k in UnitDataManager.get_all_unit_ids():
			var cn : String = UnitDataManager.get_unit_type_display_name(k)
			if cn == "" or cn == k: cn = fallback_names.get(k, k)
			items.append("%s:%s" % [k, cn])
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(items)

	if property.name == "advanced_class_id":
		var items : PackedStringArray = ["（无）"]
		var clean_unit = _clean_id(unit_name) # ★ 清理脏数据
		var branches : Array = _get_branches_for_unit(clean_unit)
		for b in branches:
			if b is Dictionary:
				var bid : String = str(b.get("id", ""))
				var bname : String = str(b.get("name", bid))
				if bid != "":
					items.append("%s:%s" % [bid, bname])
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(items)

	if property.name == "avatar_id":
		_ensure_avatar_file_cache()
		var items : PackedStringArray = ["（无）"]
		for f in _avatar_file_cache:
			items.append(f)
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(items)


func _get_branches_for_unit(unit_key : String) -> Array:
	var clean_key = _clean_id(unit_key)
	var ud : Dictionary = UnitDataManager.get_unit_data(clean_key)
	
	if ud.is_empty():
		# 编辑器下直接读 JSON 兜底
		if _editor_unit_db.is_empty():
			if FileAccess.file_exists(UNIT_DATA_PATH):
				var f = FileAccess.open(UNIT_DATA_PATH, FileAccess.READ)
				if f:
					var data = JSON.parse_string(f.get_as_text())
					f.close()
					if data is Dictionary:
						_editor_unit_db = data
		ud = _editor_unit_db.get(clean_key, {})

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
			warnings.append("节点位置未对齐到网格顶点。")

		if placement_mode == PlacementMode.FIXED_UNIT:
			var clean_unit = _clean_id(unit_name)
			var clean_adv = _clean_id(advanced_class_id)
			var branches : Array = _get_branches_for_unit(clean_unit)
			if clean_adv != "":
				var found : bool = false
				for b in branches:
					if b is Dictionary and str(b.get("id", "")) == clean_adv:
						found = true
						break
				if not found:
					warnings.append("advanced_class_id=%s 不属于 %s 的转职分支" % [clean_adv, clean_unit])
			if avatar_id != "":
				var p : String = "res://content/images/characters/avatar/%s.png" % avatar_id
				if not ResourceLoader.exists(p):
					warnings.append("头像文件不存在: " + p)

		elif placement_mode == PlacementMode.RANDOM_POOL:
			if pool_key == "" and enemy_pool.is_empty():
				warnings.append("RANDOM_POOL 格子没有池子。")
			if team == Team.玩家:
				warnings.append("RANDOM_POOL 一般用于敌方。")
				
			var all_unit_ids : Array = UnitDataManager.get_all_unit_ids()
			for entry in enemy_pool:
				if entry == "": continue
				var parts : PackedStringArray = entry.split(":", false)
				var base_key : String = parts[0] if parts.size() > 0 else ""
				if base_key == "" or base_key not in all_unit_ids:
					warnings.append("随机池中存在无效单位: %s" % entry)
					continue
				if parts.size() >= 2 and parts[1] != "":
					var adv_id : String = parts[1]
					var found_b : bool = false
					for b in _get_branches_for_unit(base_key):
						if b is Dictionary and str(b.get("id", "")) == adv_id:
							found_b = true
							break
					if not found_b:
						warnings.append("随机池中的转职分支不存在: %s" % entry)
	return warnings


func _build_preview():
	if not Engine.is_editor_hint(): return
	_clear_all_children()
	match placement_mode:
		PlacementMode.SPAWN_POINT: _build_spawn_point_preview()
		PlacementMode.RANDOM_POOL: _build_random_pool_preview()
		_: _build_unit_preview()


func _build_spawn_point_preview():
	var control := Control.new()
	control.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	control.position = Vector2.ZERO
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)

	var bg = ColorRect.new()
	bg.color = MapConst.HIGHLIGHT_SPAWN
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.add_child(bg)

	var label = Label.new()
	label.text = "S" + str(spawn_index)
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.add_child(label)


func _build_random_pool_preview():
	var control := Control.new()
	control.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	control.position = Vector2.ZERO
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)

	var bg = ColorRect.new()
	bg.color = Color(0.9, 0.5, 0.1, 0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.add_child(bg)

	var lines : Array[String] = []
	if wave_idx >= 1:
		lines.append("W%d" % (wave_idx + 1))
	lines.append("RU")
	var text := "\n".join(lines)

	var ru_label := Label.new()
	ru_label.text = text
	ru_label.add_theme_font_size_override("font_size", 6) 
	ru_label.add_theme_constant_override("line_spacing", -2) 
	ru_label.add_theme_color_override("font_color", Color.WHITE) 
	ru_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ru_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ru_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ru_label.clip_text = true 
	control.add_child(ru_label)

	if pool_key != "":
		var key_label := Label.new()
		key_label.text = pool_key
		key_label.add_theme_font_size_override("font_size", 4) 
		key_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3)) 
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT 
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		key_label.size = Vector2(MapConst.CELL_SIZE * 2, 8)
		key_label.position = Vector2(0, -2) 
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_label.clip_text = true
		key_label.z_index = 30 
		control.add_child(key_label)


func _build_unit_preview():
	var bg = ColorRect.new()
	bg.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	bg.position = Vector2.ZERO
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

	var clean_unit = _clean_id(unit_name)
	var clean_adv = _clean_id(advanced_class_id)
	
	var data = UnitDataManager.get_unit_data(clean_unit)
	var frames_path : String = data.get("sprite_frames_path", "")
	var adv_hp_bonus : int = 0
	
	if clean_adv != "":
		var branches : Array = _get_branches_for_unit(clean_unit)
		for b in branches:
			if b is Dictionary and str(b.get("id", "")) == clean_adv:
				var bd : Dictionary = b
				var adv_path : String = str(bd.get("sprite_frames_path", ""))
				if adv_path != "" and ResourceLoader.exists(adv_path):
					frames_path = adv_path
				var sb : Dictionary = bd.get("stat_bonus", {})
				adv_hp_bonus = int(sb.get("max_hp", 0))
				break

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

	_add_editor_badge_label()

	_update_visibility()
	if Engine.is_editor_hint(): queue_redraw()


func _add_editor_badge_label():
	var badges : Array[String] = []
	if wave_idx >= 1:
		badges.append("W%d" % (wave_idx + 1))
	if team == Team.敌人 and is_boss:
		badges.append("BO")
	if badges.is_empty(): return

	var text : String = "\n".join(badges)

	var control := Control.new()
	control.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	control.position = Vector2.ZERO
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.z_index = 20
	control.z_as_relative = false
	add_child(control)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 6) 
	label.add_theme_constant_override("line_spacing", -2) 
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.clip_text = true
	control.add_child(label)


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


# ============================================================
#  随机池弹窗入口
# ============================================================
func _open_pool_editor():
	if not Engine.is_editor_hint():
		return

	var script_path : String = "res://function/tool/mapplacer/UnitPoolEditor.gd"
	if not ResourceLoader.exists(script_path):
		push_error("[UnitPlacer] UnitPoolEditor.gd 未找到: " + script_path)
		return

	var script_res = load(script_path)
	if script_res == null or not (script_res is GDScript):
		push_error("[UnitPlacer] UnitPoolEditor.gd 不是有效 GDScript")
		return

	var editor = script_res.new()
	if editor == null:
		push_error("[UnitPlacer] UnitPoolEditor 实例化失败")
		return
	if not editor.has_method("setup"):
		push_error("[UnitPlacer] UnitPoolEditor 缺少 setup 方法，实际类型: %s" % editor.get_class())
		if editor is Node: editor.queue_free()
		return

	editor.setup(enemy_pool, func(new_pool : Array):
		var typed : Array[String] = []
		for p in new_pool:
			if p is String and (p as String) != "":
				typed.append(p)
		enemy_pool = typed
		notify_property_list_changed()
		if Engine.is_editor_hint():
			call_deferred("_build_preview")
	)

	EditorInterface.get_base_control().add_child(editor)


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
		for e in enemy_pool:
			if e != "":
				cfg.enemy_pool.append(e)
		return cfg

	# ★ 导出时使用清理后的纯 ID
	cfg.unit_name = _clean_id(unit_name)
	cfg.override_stats = {}
	cfg.advanced_class_id = _clean_id(advanced_class_id)
	cfg.avatar_override = avatar_id
	return cfg
