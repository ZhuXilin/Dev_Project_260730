@tool
extends Node2D
class_name UnitPlacerTool

# ============================================================
#  枚举定义
# ============================================================

enum PlacementMode {
	FIXED_UNIT,     # 固定单位
	SPAWN_POINT,    # 玩家出生点
	RANDOM_POOL,    # 随机敌人池
}

enum UnitType {
	剑士, 枪兵, 斧兵, 弓兵, 飞马, 法师, 修女, 龙人, 重甲兵
}

enum Team {
	玩家 = 0,
	敌人 = 1
}

# ============================================================
#  导出属性区（分类 + 注释悬浮提示）
# ============================================================

@export_category("基础设置")
## 放置模式：固定单位 / 出生点 / 随机池。
## - Fixed Unit: 在指定坐标生成一个固定单位。
## - Spawn Point: 玩家单位的初始出生位置。
## - Random Pool: 从配置的敌人池中随机抽取一个单位生成。
@export var placement_mode: PlacementMode = PlacementMode.FIXED_UNIT:
	set(value):
		placement_mode = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

## 所属阵营。玩家阵营通常用于出生点，敌人阵营用于战斗单位。
@export var team : Team = Team.玩家:
	set(value):
		team = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

## 是否在编辑器中显示该单位的预览图。
@export var show_preview : bool = true:
	set(value):
		show_preview = value
		if Engine.is_editor_hint():
			_update_visibility()


@export_category("固定单位设置")
## 要生成的单位类型（仅在 Fixed Unit 模式下生效）。
@export var unit_type : UnitType = UnitType.剑士:
	set(value):
		unit_type = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

## 是否固定不动（通常用于木桩、宝箱怪或特定 Boss 机制）。
@export var immobile : bool = false:
	set(value):
		if team == Team.玩家:
			if immobile != false:
				immobile = false
		elif immobile != value:
			immobile = value

## 是否标记为 Boss（会影响部分技能和 AI 逻辑）。
@export var is_boss : bool = false

## 初始携带的道具（如特殊武器、防具）。
@export var initial_items : Array[ItemEntry] = []


@export_category("出生点设置")
## 玩家出生点的序号（0 为主单位，1~2 为辅助单位），仅 Spawn Point 模式下生效。
@export var spawn_index: int = 0:
	set(value):
		spawn_index = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")


@export_category("随机池设置")
## 随机池组标识。如果多个格子的 Pool Key 相同，它们会共享一个敌人池（取第一个非空池）。
@export var pool_key: String = "":
	set(value):
		pool_key = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")

## 敌人类型列表（字符串）。重复写入同一个单位名可以增加其在池中的权重。
@export var enemy_pool: Array[String] = []:
	set(value):
		enemy_pool = value
		if Engine.is_editor_hint():
			call_deferred("_build_preview")


@export_category("波次设置")
## 该单位在第几波出现（1 为基础波，2 为第二批增援，以此类推）。
@export var wave: int = 1:
	set(value):
		wave = maxi(1, value)
		if Engine.is_editor_hint():
			call_deferred("_build_preview")


# ============================================================
#  常量与运行时
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
		_build_preview()
		return


# ============================================================
#  编辑器警告
# ============================================================
func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	if Engine.is_editor_hint():
		var pos = position
		var cell_size = MapConst.CELL_SIZE
		var x_mod = fmod(pos.x, cell_size)
		var y_mod = fmod(pos.y, cell_size)
		var x_aligned = abs(x_mod) < 0.01
		var y_aligned = abs(y_mod) < 0.01
		
		if not x_aligned or not y_aligned:
			warnings.append("节点位置未对齐到网格顶点（应位于格子角点，坐标应为 %d 的整数倍）。建议使用网格吸附功能。" % MapConst.CELL_SIZE)
			
		if placement_mode == PlacementMode.FIXED_UNIT:
			if initial_items.size() > 5:
				warnings.append("初始道具数量超过5个，将只保留前5个")
			var default_id = UnitDataManager.get_default_weapon_id(_get_json_key())
			if default_id != "":
				var has_default = false
				for entry in initial_items:
					if entry and entry.item_id == default_id:
						has_default = true
						break
				if not has_default and initial_items.size() >= 5:
					warnings.append("默认武器 %s 将自动添加，当前已满5格，请移除一个道具以容纳" % default_id)
					
		elif placement_mode == PlacementMode.SPAWN_POINT:
			if spawn_index < 0 or spawn_index > 5:
				warnings.append("spawn_index 应在 0~5 范围内（通常对应队伍人数）")
				
		elif placement_mode == PlacementMode.RANDOM_POOL:
			if pool_key == "" and enemy_pool.is_empty():
				warnings.append("RANDOM_POOL 格子没有池子：要么填 pool_key（与其他格子共享），要么填 enemy_pool（自包含）")
			if team == Team.玩家:
				warnings.append("RANDOM_POOL 一般用于敌方。玩家单位请用 FIXED_UNIT / SPAWN_POINT")
				
	return warnings


# ============================================================
#  预览构建
# ============================================================
func _build_preview():
	if not Engine.is_editor_hint():
		return
	_clear_all_children()
	match placement_mode:
		PlacementMode.SPAWN_POINT:
			_build_spawn_point_preview()
		PlacementMode.RANDOM_POOL:
			_build_random_pool_preview()
		_:
			_build_unit_preview()


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

	var label = Label.new()
	var key_text = pool_key if pool_key != "" else "内联"
	label.text = "R%s\nW%d" % [key_text, wave]
	label.add_theme_font_size_override("font_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	label.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0) - label.size / 2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	if not enemy_pool.is_empty():
		var sub = Label.new()
		sub.text = "池%d" % enemy_pool.size()
		sub.add_theme_font_size_override("font_size", 6)
		sub.modulate = Color(1.0, 0.8, 0.4)
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

	if not ResourceLoader.exists(UNIT_SCENE_PATH):
		return

	var unit_scene = load(UNIT_SCENE_PATH)
	var unit_instance = unit_scene.instantiate()
	if not unit_instance:
		return

	unit_instance.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0)
	unit_instance.process_mode = PROCESS_MODE_DISABLED
	unit_instance.input_pickable = false
	add_child(unit_instance)

	var json_key = _get_json_key()
	var data = UnitDataManager.get_unit_data(json_key)

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

		var team_id = 0 if team == Team.玩家 else 1
		_apply_shader_to_sprite(anim_sprite, team_id)
		anim_sprite.flip_h = (team_id == 1)

	var hp_label = unit_instance.get_node_or_null("HPLabel") as Label
	if hp_label:
		var max_hp = data.get("max_hp", 20)
		hp_label.text = str(max_hp) + "/" + str(max_hp)
		hp_label.visible = true

	unit_instance.visible = true
	_update_visibility()
	if Engine.is_editor_hint():
		queue_redraw()


func _apply_shader_to_sprite(sprite: CanvasItem, team_id: int):
	if team_id != 0 and team_id != 1:
		team_id = 0
	if not sprite:
		return
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
	for child in get_children():
		child.visible = show_preview


# ============================================================
#  辅助方法
# ============================================================
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


func _get_json_key() -> String:
	return UNIT_TYPE_TO_JSON_KEY.get(unit_type, "swordsman")


# ============================================================
#  导出配置
# ============================================================
func export_config() -> Variant:
	var grid_pos = Vector2i(floor(position.x / MapConst.CELL_SIZE), floor(position.y / MapConst.CELL_SIZE))

	# 1. 出生点逻辑
	if placement_mode == PlacementMode.SPAWN_POINT:
		return {
			"type": "spawn_point",
			"position": grid_pos,
			"spawn_index": spawn_index
		}

	# 2. 单位和随机池共用 UnitConfig
	var cfg = UnitConfig.new()
	cfg.position = grid_pos
	cfg.team_id = 0 if team == Team.玩家 else 1
	cfg.wave = wave
	cfg.is_boss = (team == Team.敌人 and is_boss)
	cfg.immobile = (team == Team.敌人 and immobile)

	# 随机池逻辑
	if placement_mode == PlacementMode.RANDOM_POOL:
		cfg.unit_name = ""   # 占位，加载时由池子抽
		cfg.is_random_pool = true
		cfg.pool_key = pool_key
		cfg.enemy_pool = enemy_pool.duplicate()
		return cfg

	# 固定单位逻辑
	cfg.unit_name = _get_json_key()
	cfg.override_stats = {}

	var items_to_export = initial_items.duplicate()
	var default_id = UnitDataManager.get_default_weapon_id(cfg.unit_name)
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
		var dropped = items_to_export.slice(5)
		var dropped_names = []
		for entry in dropped:
			var data = ItemManager.get_item_data(entry.item_id)
			dropped_names.append(data.name if data else entry.item_id)
		if Engine.is_editor_hint():
			push_warning("UnitPlacer: 初始道具（含默认武器）超过5种，丢弃了：%s" % ", ".join(dropped_names))
		items_to_export = items_to_export.slice(0, 5)

	cfg.initial_items = items_to_export
	return cfg
