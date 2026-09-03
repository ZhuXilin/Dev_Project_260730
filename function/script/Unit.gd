extends Area2D
class_name Unit

const CELL_SIZE = 16
const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

@export var unit_stats : UnitData
@export var hit_offset_distance: float = 8.0

# ---- 状态变量 ----
var hit_points : int
var grid_cell : Vector2i
var previous_grid_cell : Vector2i
var previous_remaining_move : int = 0
var can_act_this_turn : bool = true
var has_moved : bool = false
var has_attacked : bool = false
var has_acted : bool = false
var remaining_move : int = 0
var used_move : int = 0
var is_gray : bool = false
var movement_after_attack : bool = false
var previous_flip_h : bool = false
var used_non_attack_item_this_turn : bool = false
var moves_since_act: int = 0   # 自从执行行动后移动的次数

# ---- 装备 ----
var weapon_slot: ItemInstance = null          # 武器实例
var armor_slots: Array[ItemInstance] = []    # 防具/饰品槽
var max_armor_slots: int = 2

# ---- 词条 ----
var talent_slots: Array[TalentInstance] = []
var max_talent_slots: int = 2

# ---- 动画与材质 ----
var animated_sprite : AnimatedSprite2D
var current_anim : String = "idle"
var facing_flip_h : bool = false
var _color_material : ShaderMaterial = null

var _initialized: bool = false

# ---- 词条 ----
var _talent_instances: Dictionary = {}

# ============================================================
#  初始化
# ============================================================
func _ready():
	# 如果已经通过 restore 或 setup 初始化，跳过 _ready 的默认初始化
	if _initialized:
		print("Unit._ready 跳过，已初始化")
		return
	
	# 如果场景中已有 animated_sprite 但尚未设置，进行最小初始化
	if not animated_sprite:
		animated_sprite = $Sprite as AnimatedSprite2D
	
	# 如果还没有精灵帧，使用占位纹理
	if animated_sprite and not animated_sprite.sprite_frames:
		var image = Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color.MAGENTA)
		var placeholder = ImageTexture.create_from_image(image)
		var frames = SpriteFrames.new()
		frames.add_animation("idle")
		frames.add_frame("idle", placeholder)
		animated_sprite.sprite_frames = frames
		animated_sprite.play("idle")
		animated_sprite.visible = true
		animated_sprite.z_index = 2

func setup_unit(stats_data: UnitData, start_cell: Vector2i, initial_items: Array[ItemEntry] = []):
	if not animated_sprite:
		animated_sprite = $Sprite as AnimatedSprite2D
	if not animated_sprite:
		push_error("Unit %s: 缺少 AnimatedSprite2D 节点！" % stats_data.unit_name)
		return

	unit_stats = stats_data
	grid_cell = start_cell
	previous_grid_cell = start_cell
	hit_points = unit_stats.max_hp
	has_moved = false
	has_attacked = false
	has_acted = false
	can_act_this_turn = true
	remaining_move = unit_stats.move_range
	used_move = 0
	previous_remaining_move = unit_stats.move_range
	is_gray = false

	# ---- 清空并装备初始物品 ----
	weapon_slot = null
	armor_slots.clear()
	for _i in range(max_armor_slots):
		armor_slots.append(null)

	for entry in initial_items:
		if entry and entry.item_id != "":
			var data = ItemManager.get_item_data(entry.item_id)
			if not data:
				continue
			if data.equipment_slot == "weapon":
				var inst = ItemInstance.new()
				inst.item_id = entry.item_id
				inst.count = 1
				weapon_slot = inst
				print("单位 %s 装备武器: %s" % [unit_stats.unit_name, data.name])
			elif data.equipment_slot in ["armor"]:
				for i in range(armor_slots.size()):
					if armor_slots[i] == null:
						var inst = ItemInstance.new()
						inst.item_id = entry.item_id
						inst.count = 1
						armor_slots[i] = inst
						print("单位 %s 装备防具: %s (槽 %d)" % [unit_stats.unit_name, data.name, i+1])
						break

	# ---- 加载 SpriteFrames ----
	var frames_path = UnitDataManagerClass.get_sprite_frames_path(unit_stats.unit_name)
	var loaded_ok = false
	if frames_path != "" and ResourceLoader.exists(frames_path):
		var frames = load(frames_path) as SpriteFrames
		if frames:
			animated_sprite.sprite_frames = frames
			if animated_sprite.sprite_frames.has_animation("idle"):
				animated_sprite.play("idle")
			else:
				var anims = animated_sprite.sprite_frames.get_animation_names()
				if anims.size() > 0:
					animated_sprite.play(anims[0])
			animated_sprite.visible = true
			animated_sprite.z_index = 2
			loaded_ok = true

	if not loaded_ok:
		var image = Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color.MAGENTA)
		var placeholder = ImageTexture.create_from_image(image)
		var frames = SpriteFrames.new()
		frames.add_animation("idle")
		frames.add_frame("idle", placeholder)
		animated_sprite.sprite_frames = frames
		animated_sprite.play("idle")
		animated_sprite.visible = true
		animated_sprite.z_index = 2
		print("Warning: 单位 %s 的 SpriteFrames 加载失败，使用占位纹理" % unit_stats.unit_name)

	animated_sprite.flip_h = (unit_stats.team_id == 1)
	facing_flip_h = animated_sprite.flip_h
	previous_flip_h = facing_flip_h

	update_terrain_info()
	update_hp_label()
	update_name_label()
	update_color()
	
	# ---- 标记已初始化，防止 _ready() 覆盖 ----
	_initialized = true

# ============================================================
#  装备系统
# ============================================================
func get_weapon() -> ItemInstance:
	return weapon_slot

func get_equipped_weapon_id() -> String:
	return weapon_slot.item_id if weapon_slot else ""

func get_weapon_data() -> ItemData:
	if not weapon_slot:
		return null
	return ItemManager.get_item_data(weapon_slot.item_id)

func get_weapon_stats() -> Dictionary:
	var data = get_weapon_data()
	return data.stats if data else {}

func get_weapon_type() -> String:
	var data = get_weapon_data()
	if not data:
		return ""
	return data.category

func can_use_weapon(_item_id: String) -> bool:
	return true

func equip_weapon(weapon: ItemInstance) -> ItemInstance:
	var old = weapon_slot
	weapon_slot = weapon
	return old

func unequip_weapon() -> ItemInstance:
	var old = weapon_slot
	weapon_slot = null
	return old

func get_armor_slots() -> Array[ItemInstance]:
	return armor_slots

func equip_armor(index: int, item: ItemInstance) -> ItemInstance:
	if index < 0 or index >= armor_slots.size():
		return null
	var old = armor_slots[index]
	armor_slots[index] = item
	return old

func unequip_armor(index: int) -> ItemInstance:
	if index < 0 or index >= armor_slots.size():
		return null
	var old = armor_slots[index]
	armor_slots[index] = null
	return old

func add_armor_slot():
	armor_slots.append(null)
	max_armor_slots += 1

func get_total_stats() -> Dictionary:
	var total = {
		"max_hp": unit_stats.max_hp,
		"strength": unit_stats.strength,
		"dexterity": unit_stats.dexterity,
		"intelligence": unit_stats.intelligence,
		"faith": unit_stats.faith,
		"arcane": unit_stats.arcane,
		"move_range": unit_stats.move_range,
		"defense": 0,
		"magic_defense": 0,
		"attack": 0,
		"magic_attack": 0,
		"heal_amount": 0,
		"attack_range": 0,
		"min_attack_range": 0,
		"attack_style": "standard"
	}
	
	# ---- 武器加成 ----
	if weapon_slot:
		var data = ItemManager.get_item_data(weapon_slot.item_id)
		if data:
			total["attack"] = data.base_attack
			total["attack_range"] = data.attack_range
			total["min_attack_range"] = data.min_attack_range
			total["attack_style"] = data.attack_style
			
			# 兼容旧 stats（如 magic_attack / heal_amount）
			if data.stats:
				if data.stats.has("magic_attack"):
					total["magic_attack"] = data.stats["magic_attack"]
				if data.stats.has("heal_amount"):
					total["heal_amount"] = data.stats["heal_amount"]
	
	# ---- 防具加成 ----
	for slot in armor_slots:
		if slot:
			var data = ItemManager.get_item_data(slot.item_id)
			if data:
				# ✅ 直接访问属性，不使用 .get()
				total["defense"] += data.defense
	
	# ---- 遗物加成 ----
	var relic_bonus = GameState.get_global_relic_stats()
	for key in relic_bonus:
		if key in total:
			total[key] += relic_bonus[key]
	
	return total

# ---- 序列化（用于存档） ----
func serialize_inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if weapon_slot:
		result.append({
			"item_id": weapon_slot.item_id,
			"count": 1,
			"slot": "weapon"
		})
	for i in range(armor_slots.size()):
		var slot = armor_slots[i]
		if slot:
			result.append({
				"item_id": slot.item_id,
				"count": 1,
				"slot": "armor",
				"index": i
			})
	return result

# ---- 从存档恢复 ----
func restore_from_unit_data(data: UnitData, cell: Vector2i):
	print("restore_from_unit_data: 单位 ", data.unit_name, " 武器: ", data.weapon_slot.item_id if data.weapon_slot else "无")
	
	unit_stats = data
	grid_cell = cell
	previous_grid_cell = cell
	hit_points = data.hit_points
	remaining_move = data.move_range
	can_act_this_turn = true
	has_moved = false
	has_attacked = false
	has_acted = false

	# ---- 恢复装备（创建新实例，避免引用问题） ----
	if data.weapon_slot:
		var inst = ItemInstance.new()
		inst.item_id = data.weapon_slot.item_id
		inst.count = data.weapon_slot.count
		weapon_slot = inst
	else:
		weapon_slot = null
	
	armor_slots.clear()
	for slot in data.armor_slots:
		if slot:
			var inst = ItemInstance.new()
			inst.item_id = slot.item_id
			inst.count = slot.count
			armor_slots.append(inst)
		else:
			armor_slots.append(null)
	max_armor_slots = data.max_armor_slots

	# ---- 加载 SpriteFrames ----
	if not animated_sprite:
		animated_sprite = $Sprite as AnimatedSprite2D
	
	if animated_sprite:
		var frames_path = UnitDataManagerClass.get_sprite_frames_path(unit_stats.unit_name)
		var loaded_ok = false
		if frames_path != "" and ResourceLoader.exists(frames_path):
			var frames = load(frames_path) as SpriteFrames
			if frames:
				animated_sprite.sprite_frames = frames
				if animated_sprite.sprite_frames.has_animation("idle"):
					animated_sprite.play("idle")
				else:
					var anims = animated_sprite.sprite_frames.get_animation_names()
					if anims.size() > 0:
						animated_sprite.play(anims[0])
				animated_sprite.visible = true
				animated_sprite.z_index = 2
				loaded_ok = true
		if not loaded_ok:
			var image = Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
			image.fill(Color.MAGENTA)
			var placeholder = ImageTexture.create_from_image(image)
			var frames = SpriteFrames.new()
			frames.add_animation("idle")
			frames.add_frame("idle", placeholder)
			animated_sprite.sprite_frames = frames
			animated_sprite.play("idle")
			animated_sprite.visible = true
			animated_sprite.z_index = 2
			print("Warning: 单位 %s 的 SpriteFrames 加载失败，使用占位纹理" % unit_stats.unit_name)

	animated_sprite.flip_h = (unit_stats.team_id == 1)
	facing_flip_h = animated_sprite.flip_h
	previous_flip_h = facing_flip_h

	update_color()
	update_hp_label()
	update_name_label()
	update_terrain_info()
	
	# ---- 标记已初始化，防止 _ready() 覆盖 ----
	_initialized = true
	print("restore_from_unit_data 完成，weapon_slot: ", weapon_slot.item_id if weapon_slot else "无")

# ============================================================
#  状态与行动
# ============================================================
func mark_attacked():
	has_attacked = true
	has_acted = true
	movement_after_attack = false

func mark_non_attack_action():
	has_acted = true

func reset_turn():
	can_act_this_turn = true
	has_moved = false
	has_attacked = false
	has_acted = false
	used_non_attack_item_this_turn = false
	movement_after_attack = false
	remaining_move = unit_stats.move_range
	used_move = 0
	moves_since_act = 0
	previous_remaining_move = unit_stats.move_range
	set_gray(false)
	play_animation("idle")

func consume_move(cost: int):
	remaining_move -= cost
	if remaining_move < 0:
		remaining_move = 0
	used_move = unit_stats.move_range - remaining_move
	has_moved = true
	if has_attacked:
		movement_after_attack = true

func can_move() -> bool:
	return can_act_this_turn and remaining_move > 0 and not has_attacked

func save_previous_position():
	previous_grid_cell = grid_cell
	previous_remaining_move = remaining_move
	if animated_sprite:
		previous_flip_h = animated_sprite.flip_h

func revert_to_previous_position():
	grid_cell = previous_grid_cell
	update_position(grid_cell)
	remaining_move = previous_remaining_move
	used_move = 0
	has_moved = false
	can_act_this_turn = true
	movement_after_attack = false
	if animated_sprite:
		animated_sprite.flip_h = previous_flip_h
		facing_flip_h = previous_flip_h
	play_animation("idle")

func update_position(new_cell: Vector2i):
	grid_cell = new_cell
	update_terrain_info()

# ============================================================
#  战斗
# ============================================================
func apply_damage(damage_amount : int) -> bool:
	hit_points -= damage_amount
	if hit_points < 0: hit_points = 0
	update_hp_label()
	return hit_points <= 0

# ============================================================
#  动画
# ============================================================
func play_animation(anim_name: String, force: bool = false):
	if not animated_sprite or not animated_sprite.sprite_frames:
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.sprite_frames.has_animation("idle"):
			anim_name = "idle"
		else:
			return
	if current_anim == anim_name and not force:
		return
	animated_sprite.play(anim_name)
	current_anim = anim_name
	if animated_sprite:
		animated_sprite.flip_h = facing_flip_h

func set_facing_direction(dir: Vector2):
	if dir == Vector2.ZERO or not animated_sprite:
		return
	if dir.x != 0:
		animated_sprite.flip_h = (dir.x > 0)
		facing_flip_h = animated_sprite.flip_h

# ============================================================
#  颜色与着色器
# ============================================================
func set_gray(gray: bool):
	is_gray = gray
	# ---- 如果单位已死亡，强制灰色 ----
	if hit_points <= 0:
		is_gray = true
	update_color()

func update_color():
	if not animated_sprite:
		return
	var shader = preload("res://content/resource/shader/replace_color.gdshader")
	if not shader:
		push_error("无法加载替换 Shader")
		return
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("target_color_1", Globals.TARGET_COLOR_1)
	mat.set_shader_parameter("target_color_2", Globals.TARGET_COLOR_2)
	
	var color1: Color
	var color2: Color
	if is_gray:
		color1 = Globals.get_gray_color(true)
		color2 = Globals.get_gray_color(false)
	else:
		color1 = Globals.get_team_color(unit_stats.team_id, true)
		color2 = Globals.get_team_color(unit_stats.team_id, false)
	mat.set_shader_parameter("assign_color_1", color1)
	mat.set_shader_parameter("assign_color_2", color2)
	animated_sprite.material = mat
	_color_material = mat
	animated_sprite.modulate = Color.WHITE

func play_hit_effect(direction: Vector2, is_hit: bool):
	if not animated_sprite or not _color_material:
		return
	var dir_norm = direction.normalized()
	var offset = dir_norm * hit_offset_distance
	_color_material.set_shader_parameter("hit_offset_amount", offset)
	_color_material.set_shader_parameter("hit_duration", 0.15)
	_color_material.set_shader_parameter("hit_elapsed", 0.0)
	_color_material.set_shader_parameter("hit_flash_color", Color.RED if is_hit else Color.WHITE)
	_color_material.set_shader_parameter("hit_enable_flash", true)

	var tween = create_tween()
	tween.tween_method(
		func(val): _color_material.set_shader_parameter("hit_elapsed", val),
		0.0, 0.15, 0.15
	)
	tween.tween_callback(func():
		if is_instance_valid(_color_material):
			_color_material.set_shader_parameter("hit_enable_flash", false)
			_color_material.set_shader_parameter("hit_elapsed", 0.0)
	)

# ============================================================
#  UI 更新
# ============================================================
func update_hp_label():
	var hp_label = $HPLabel
	if hp_label:
		hp_label.text = str(hit_points) + "/" + str(unit_stats.max_hp)

func update_name_label():
	var na_label = $NameLabel
	if na_label:
		na_label.text = unit_stats.display_name if unit_stats.display_name != "" else unit_stats.unit_name

func update_terrain_info():
	var terrain_label = $TerrainInfoLabel
	if not terrain_label:
		return
	var terrain_type = TerrainManager.get_terrain(grid_cell)
	var terrain_name = TerrainManager.get_terrain_name(terrain_type)
	var def_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["def_bonus"]
	var avoid_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["avoid_bonus"]
	terrain_label.text = terrain_name + "\n防御+" + str(def_bonus) + " 回避+" + str(avoid_bonus)

# ---- 词条方法 ----
func equip_talent(talent_id: String) -> bool:
	var data = TalentManager.get_talent_data(talent_id)
	if not data:
		return false
	if _talent_instances.has(talent_id):
		return false  # 已装备
	var inst = TalentInstance.new()
	inst.talent_id = talent_id
	_talent_instances[talent_id] = inst
	return true

func unequip_talent(talent_id: String):
	if _talent_instances.has(talent_id):
		_talent_instances.erase(talent_id)

func get_talent_instance(talent_id: String) -> TalentInstance:
	return _talent_instances.get(talent_id)

func get_talent_threshold(talent_id: String) -> int:
	var data = TalentManager.get_talent_data(talent_id)
	return data.accumulation_threshold if data else 0

func get_talents_by_school(school: String) -> Array:
	var result = []
	for talent_id in _talent_instances:
		var data = TalentManager.get_talent_data(talent_id)
		if data and data.school == school:
			result.append(talent_id)
	return result

func reset_all_talents():
	for inst in _talent_instances.values():
		inst.reset()

func get_talent_school_count(school: String) -> int:
	var count = 0
	for talent_id in _talent_instances:
		var data = TalentManager.get_talent_data(talent_id)
		if data and data.school == school and _talent_instances[talent_id].is_active:
			count += 1
	return count

func accumulate_all_talents():
	for inst in _talent_instances.values():
		if inst and inst.is_active:
			inst.current_stack += 1
			var threshold = get_talent_threshold(inst.talent_id)
			if inst.current_stack >= threshold:
				inst.is_ready = true

func equip_talent_to_slot(slot_index: int, talent_id: String) -> bool:
	if slot_index < 0 or slot_index >= talent_slots.size():
		return false
	var data = TalentManager.get_talent_data(talent_id)
	if not data:
		return false
	var inst = TalentInstance.new()
	inst.talent_id = talent_id
	inst.current_stack = 0
	inst.is_ready = false
	inst.is_active = true
	talent_slots[slot_index] = inst
	return true

func get_talent_slots() -> Array[TalentInstance]:
	return talent_slots
