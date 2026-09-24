extends Area2D
class_name Unit

@export var unit_stats : UnitData
@export var hit_offset_distance: float = MapConst.HIT_OFFSET_DISTANCE

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
var bleed_stacks : int = 0
var movement_after_attack : bool = false
var previous_flip_h : bool = false
var used_non_attack_item_this_turn : bool = false
var moves_since_act: int = 0

# ---- 战斗 Buff ----
var buff_attack_percent : float = 0.0
var buff_crit_damage_bonus : float = 0.0
var buff_defense_flat : int = 0
var buff_damage_reduction : float = 0.0
var buff_attack_flat : int = 0
var buff_magic_attack_flat : int = 0

# ---- 主动技能状态 ----
var active_skill_ready_consumed: Dictionary = {}

# ---- 嘲讽状态 ----
var taunt_rounds: int = 0
var taunt_by: Unit = null
var taunt_rounds_left: int = 0

# ---- 遗物效果状态 ----
var relic_first_attack_crit_available: bool = false
var relic_low_hp_damage_reduce: float = 0.0
var relic_kill_grants_extra_move: int = 0
var relic_first_spell_free_available: bool = false
var relic_turn_first_hit_regen: float = 0.0
var relic_turn_first_hit_regen_used: bool = false
var relic_strength_scale_damage: float = 0.0
var relic_counter_damage_bonus: float = 0.0
var relic_heal_bonus: float = 0.0
var relic_auto_revive_available: bool = false

# ---- 连锁词条状态 ----
var vengeance_triggered: bool = false   # 复仇：本场是否已触发（只触发一次）
var zeal_target: String = ""            # 狂热目标 key
var zeal_stacks: int = 0                # 狂热层数

# ---- 装备 ----
var weapon_slot: ItemInstance = null
var armor_slots: Array[ItemInstance] = []
var max_armor_slots: int = 2

# ---- 词条 ----
var talent_slots: Array[TalentInstance] = []
var advanced_talent_inst : TalentInstance = null   # 职业特技运行时实例
var max_talent_slots: int = 1

# ---- 连击追踪 ----
var combo_last_target: String = ""
var combo_count: int = 0

# ---- 动画与材质 ----
var animated_sprite : AnimatedSprite2D
var current_anim : String = "idle"
var facing_flip_h : bool = false
var _color_material : ShaderMaterial = null

var _initialized: bool = false


func _ready():
	if _initialized:
		return
	if not animated_sprite:
		animated_sprite = $Sprite as AnimatedSprite2D
	if animated_sprite and not animated_sprite.sprite_frames:
		var image = Image.create(MapConst.CELL_SIZE, MapConst.CELL_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color.MAGENTA)
		var placeholder = ImageTexture.create_from_image(image)
		var frames = SpriteFrames.new()
		frames.add_animation("idle")
		frames.add_frame("idle", placeholder)
		animated_sprite.sprite_frames = frames
		animated_sprite.play("idle")
		animated_sprite.visible = true
		animated_sprite.z_index = 2


func _resolve_sprite_path() -> String:
	if unit_stats and unit_stats.override_sprite_path != "":
		if ResourceLoader.exists(unit_stats.override_sprite_path):
			return unit_stats.override_sprite_path
	return UnitDataManager.get_sprite_frames_path(unit_stats.unit_name)


func setup_unit(stats_data: UnitData, start_cell: Vector2i, initial_items: Array[ItemEntry] = []):
	if not animated_sprite:
		animated_sprite = $Sprite as AnimatedSprite2D
	if not animated_sprite:
		push_error("Unit %s: 缺少 AnimatedSprite2D 节点！" % stats_data.unit_name)
		return

	reset_combat_buffs()
	reset_relic_effects()
	reset_chain_talents()

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

	weapon_slot = null
	max_armor_slots = stats_data.max_armor_slots
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
			elif data.equipment_slot in ["armor"]:
				if not can_equip_armor(entry.item_id):
					continue
				for i in range(armor_slots.size()):
					if armor_slots[i] == null:
						var inst = ItemInstance.new()
						inst.item_id = entry.item_id
						inst.count = 1
						armor_slots[i] = inst
						break

	_init_talent_slots_from_data(stats_data)

	var frames_path = _resolve_sprite_path()
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
		var image = Image.create(MapConst.CELL_SIZE, MapConst.CELL_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color.MAGENTA)
		var placeholder = ImageTexture.create_from_image(image)
		var frames = SpriteFrames.new()
		frames.add_animation("idle")
		frames.add_frame("idle", placeholder)
		animated_sprite.sprite_frames = frames
		animated_sprite.play("idle")
		animated_sprite.visible = true
		animated_sprite.z_index = 2

	animated_sprite.flip_h = (unit_stats.team_id == 1)
	facing_flip_h = animated_sprite.flip_h
	previous_flip_h = facing_flip_h

	update_terrain_info()
	update_hp_label()
	update_name_label()
	update_color()

	combo_last_target = ""
	combo_count = 0
	active_skill_ready_consumed.clear()
	taunt_rounds = 0
	taunt_by = null
	taunt_rounds_left = 0

	_initialized = true


func reset_relic_effects():
	relic_first_attack_crit_available = false
	relic_low_hp_damage_reduce = 0.0
	relic_kill_grants_extra_move = 0
	relic_first_spell_free_available = false
	relic_turn_first_hit_regen = 0.0
	relic_turn_first_hit_regen_used = false
	relic_strength_scale_damage = 0.0
	relic_counter_damage_bonus = 0.0
	relic_heal_bonus = 0.0
	relic_auto_revive_available = false


func reset_chain_talents():
	vengeance_triggered = false
	zeal_target = ""
	zeal_stacks = 0
	taunt_rounds = 0
	taunt_by = null
	taunt_rounds_left = 0


func get_weapon() -> ItemInstance:
	return weapon_slot

func get_equipped_weapon_id() -> String:
	return weapon_slot.item_id if weapon_slot else ""

func get_weapon_data() -> ItemData:
	if not weapon_slot:
		return null
	return ItemManager.get_item_data(weapon_slot.item_id)

func get_weapon_stats() -> Dictionary:
	var default_stats := {
		"attack": 0, "magic_attack": 0, "heal_amount": 0,
		"attack_range": 0, "min_attack_range": 0, "attack_style": "standard",
	}
	var data = get_weapon_data()
	if not data:
		return default_stats

	var quality_mult := 1.0
	match data.quality:
		"rare": quality_mult = 1.25
		"epic": quality_mult = 1.5
		"legendary": quality_mult = 1.8

	var upgrade_bonus = weapon_slot.upgrade_level if weapon_slot else 0

	var stats := default_stats.duplicate()
	stats["attack"] = int((data.base_attack + upgrade_bonus) * quality_mult)
	stats["attack_range"] = data.attack_range
	stats["min_attack_range"] = data.min_attack_range
	stats["attack_style"] = data.attack_style

	if data.magic_attack.get("ignore_defense", false):
		stats["magic_attack"] = int((data.base_attack + upgrade_bonus) * quality_mult)
	if not data.heal_effect.is_empty():
		stats["heal_amount"] = data.heal_effect.get("base_heal", 0)

	return stats

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

func count_used_armor_slots() -> int:
	return unit_stats.count_used_armor_slots()

func can_equip_armor(item_id: String, exclude_slot_idx: int = -1) -> bool:
	return unit_stats.can_equip_armor(item_id, exclude_slot_idx)

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

	if weapon_slot:
		var data = ItemManager.get_item_data(weapon_slot.item_id)
		if data:
			var quality_mult := 1.0
			match data.quality:
				"rare": quality_mult = 1.25
				"epic": quality_mult = 1.5
				"legendary": quality_mult = 1.8
			var upgrade_bonus = weapon_slot.upgrade_level
			total["attack"] = int((data.base_attack + upgrade_bonus) * quality_mult)
			total["attack_range"] = data.attack_range
			total["min_attack_range"] = data.min_attack_range
			total["attack_style"] = data.attack_style
			if data.magic_attack.get("ignore_defense", false):
				total["magic_attack"] = int((data.base_attack + upgrade_bonus) * quality_mult)
			if not data.heal_effect.is_empty():
				total["heal_amount"] = data.heal_effect.get("base_heal", 0)

	for slot in armor_slots:
		if slot:
			var data = ItemManager.get_item_data(slot.item_id)
			if data:
				total["defense"] += data.defense

	var armor_mod := unit_stats.get_armor_modifier_bonus()
	for key in armor_mod:
		if key in total:
			total[key] += int(armor_mod[key])

	var relic_bonus = GameState.get_global_relic_stats()
	for key in relic_bonus:
		if key in total:
			total[key] += relic_bonus[key]

	return total

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

func restore_from_unit_data(data: UnitData, cell: Vector2i):
	reset_combat_buffs()
	reset_relic_effects()
	reset_chain_talents()

	unit_stats = data
	grid_cell = cell
	previous_grid_cell = cell
	hit_points = data.hit_points
	remaining_move = data.move_range
	can_act_this_turn = true
	has_moved = false
	has_attacked = false
	has_acted = false

	if data.weapon_slot:
		var inst := ItemInstance.new()
		inst.item_id = data.weapon_slot.item_id
		inst.count = data.weapon_slot.count
		inst.upgrade_level = data.weapon_slot.upgrade_level
		weapon_slot = inst
	else:
		weapon_slot = null

	armor_slots.clear()
	for slot in data.armor_slots:
		if slot:
			var inst := ItemInstance.new()
			inst.item_id = slot.item_id
			inst.count = slot.count
			inst.upgrade_level = slot.upgrade_level
			armor_slots.append(inst)
		else:
			armor_slots.append(null)
	max_armor_slots = data.max_armor_slots
	# ★ 补齐空槽
	while armor_slots.size() < max_armor_slots:
		armor_slots.append(null)
	# ★ 截断溢出（防旧存档）
	while armor_slots.size() > max_armor_slots:
		armor_slots.pop_back()

	_init_talent_slots_from_data(data)
	while talent_slots.size() < max_talent_slots:
		talent_slots.append(null)

	if not animated_sprite:
		animated_sprite = $Sprite as AnimatedSprite2D

	if animated_sprite:
		var frames_path = _resolve_sprite_path()
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
			var image = Image.create(MapConst.CELL_SIZE, MapConst.CELL_SIZE, false, Image.FORMAT_RGBA8)
			image.fill(Color.MAGENTA)
			var placeholder = ImageTexture.create_from_image(image)
			var frames = SpriteFrames.new()
			frames.add_animation("idle")
			frames.add_frame("idle", placeholder)
			animated_sprite.sprite_frames = frames
			animated_sprite.play("idle")
			animated_sprite.visible = true
			animated_sprite.z_index = 2

	animated_sprite.flip_h = (unit_stats.team_id == 1)
	facing_flip_h = animated_sprite.flip_h
	previous_flip_h = facing_flip_h

	update_color()
	update_hp_label()
	update_name_label()
	update_terrain_info()

	combo_last_target = ""
	combo_count = 0
	active_skill_ready_consumed.clear()
	taunt_rounds = 0
	taunt_by = null
	taunt_rounds_left = 0

	_initialized = true


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
	relic_turn_first_hit_regen_used = false   # ★ 每回合重置
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

func apply_damage(damage_amount : int) -> bool:
	hit_points -= damage_amount
	if hit_points < 0: hit_points = 0
	update_hp_label()
	return hit_points <= 0

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

func set_gray(gray: bool):
	is_gray = gray
	if hit_points <= 0:
		is_gray = true
	update_color()

func update_color():
	if not animated_sprite:
		return
	var shader = preload(Config.PATHS.SHADER_REPLACE_COLOR)
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
	_color_material.set_shader_parameter("hit_duration", MapConst.HIT_FLASH_DURATION)
	_color_material.set_shader_parameter("hit_elapsed", 0.0)
	_color_material.set_shader_parameter("hit_flash_color", Color.RED if is_hit else Color.WHITE)
	_color_material.set_shader_parameter("hit_enable_flash", true)

	var tween = create_tween()
	tween.tween_method(
		func(val): _color_material.set_shader_parameter("hit_elapsed", val),
		0.0, MapConst.HIT_FLASH_DURATION, MapConst.HIT_FLASH_DURATION
	)
	tween.tween_callback(func():
		if is_instance_valid(_color_material):
			_color_material.set_shader_parameter("hit_enable_flash", false)
			_color_material.set_shader_parameter("hit_elapsed", 0.0)
	)

func update_hp_label():
	var hp_label = $HPLabel
	if hp_label:
		hp_label.text = str(hit_points) + "/" + str(unit_stats.max_hp)

func update_name_label():
	var na_label = $NameLabel
	if na_label:
		var display = unit_stats.display_name if unit_stats.display_name != "" else unit_stats.unit_name
		var type_name = UnitDataManager.get_unit_type_display_name(unit_stats.unit_name)
		if unit_stats.advanced_class != "":
			var adv_name : String = AdvancedClassManager.get_display_name(unit_stats.advanced_class)
			na_label.text = display + "|" + unit_stats.faction + "|★" + adv_name
		else:
			na_label.text = display + "|" + unit_stats.faction + "|" + type_name

func update_terrain_info():
	var terrain_label = $TerrainInfoLabel
	if not terrain_label:
		return
	var terrain_type = TerrainManager.get_terrain(grid_cell)
	var terrain_name = TerrainManager.get_terrain_name(terrain_type)
	var def_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["def_bonus"]
	var avoid_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["avoid_bonus"]
	terrain_label.text = terrain_name + "\n防御+" + str(def_bonus) + " 回避+" + str(avoid_bonus)

func _init_talent_slots_from_data(data: UnitData):
	talent_slots.clear()

	var target_max = data.max_talent_slots
	if target_max <= 0:
		target_max = 1
	max_talent_slots = target_max

	if data.talent_slots is Array:
		for slot_data in data.talent_slots:
			if talent_slots.size() >= max_talent_slots:
				break
			if slot_data and slot_data is TalentInstance and slot_data.is_active:
				var new_inst = TalentInstance.new()
				new_inst.talent_id = slot_data.talent_id
				new_inst.current_stack = 0
				new_inst.is_active = true
				# ★ 主动技能初始就绪
				var tdata = TalentManager.get_talent_data(slot_data.talent_id)
				if tdata and tdata.is_active_skill:
					new_inst.is_ready = true
					new_inst.cooldown_remaining = 0
				else:
					new_inst.is_ready = false
				talent_slots.append(new_inst)
			else:
				talent_slots.append(null)

	while talent_slots.size() < max_talent_slots:
		talent_slots.append(null)

	# ★ 职业特技（转职授予，不占普通词条槽）
	advanced_talent_inst = null
	if data.advanced_talent_id != "":
		var new_adv := TalentInstance.new()
		new_adv.talent_id = data.advanced_talent_id
		new_adv.is_active = true
		var tdata_adv = TalentManager.get_talent_data(data.advanced_talent_id)
		if tdata_adv and tdata_adv.is_active_skill:
			new_adv.is_ready = true
			new_adv.cooldown_remaining = 0
		else:
			new_adv.is_ready = false
		advanced_talent_inst = new_adv
		

func get_talent_instance(talent_id: String) -> TalentInstance:
	for inst in talent_slots:
		if inst and inst.talent_id == talent_id and inst.is_active:
			return inst
	# ★ 也查职业特技
	if advanced_talent_inst and advanced_talent_inst.talent_id == talent_id and advanced_talent_inst.is_active:
		return advanced_talent_inst
	return null

func equip_talent(talent_id: String) -> bool:
	var data = TalentManager.get_talent_data(talent_id)
	if not data:
		return false
	if get_talent_instance(talent_id) != null:
		return false
	for i in range(talent_slots.size()):
		if talent_slots[i] == null:
			var inst = TalentInstance.new()
			inst.talent_id = talent_id
			inst.is_active = true
			talent_slots[i] = inst
			return true
	if talent_slots.size() < max_talent_slots:
		var inst = TalentInstance.new()
		inst.talent_id = talent_id
		inst.is_active = true
		talent_slots.append(inst)
		return true
	return false

func unequip_talent(talent_id: String):
	for i in range(talent_slots.size()):
		var inst = talent_slots[i]
		if inst and inst.talent_id == talent_id:
			talent_slots[i] = null
			return

func get_talent_threshold(talent_id: String) -> int:
	var data = TalentManager.get_talent_data(talent_id)
	return data.accumulation_threshold if data else 0

func get_talents_by_school(school: String) -> Array:
	var result = []
	for inst in talent_slots:
		if inst and inst.is_active:
			var data = TalentManager.get_talent_data(inst.talent_id)
			if data and data.school == school:
				result.append(inst.talent_id)
	return result

func reset_all_talents():
	for inst in talent_slots:
		if inst:
			inst.reset()
	# ★ 职业特技也重置
	if advanced_talent_inst:
		advanced_talent_inst.reset()

func get_talent_school_count(school: String) -> int:
	var count = 0
	for inst in talent_slots:
		if inst and inst.is_active:
			var data = TalentManager.get_talent_data(inst.talent_id)
			if data and data.school == school:
				count += 1
	return count

# ★ 改为调用 TalentManager 静态方法
func accumulate_all_talents():
	TalentManager.accumulate_talents(talent_slots)
	# ★ 职业特技也积累
	if advanced_talent_inst:
		TalentManager.accumulate_talents([advanced_talent_inst])

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

func reset_combat_buffs():
	buff_attack_percent = 0.0
	buff_crit_damage_bonus = 0.0
	buff_defense_flat = 0
	buff_damage_reduction = 0.0
	buff_attack_flat = 0
	buff_magic_attack_flat = 0

func can_counter() -> bool:
	# 词条
	if get_talent_instance("counter_boost") != null:
		return true
	# 武器类型（长枪/盾）
	var wdata = get_weapon_data()
	if wdata and wdata.category in ["spear", "shield"]:
		return true
	# 遗物/协同 buff
	if relic_counter_damage_bonus > 0.0:
		return true
	return false
