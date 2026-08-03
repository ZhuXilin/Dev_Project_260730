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

# ---- 库存与装备（列表化，实例引用） ----
var inventory: Array[ItemInstance] = []
var equipped_weapon_instance: ItemInstance = null   # 存储当前装备的武器实例

# ---- 动画与材质 ----
var animated_sprite : AnimatedSprite2D
var current_anim : String = "idle"
var facing_flip_h : bool = false
var _color_material : ShaderMaterial = null

func _ready():
	pass

func setup_unit(stats_data : UnitData, start_cell : Vector2i, initial_items : Array[ItemEntry] = []):
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

	inventory.clear()
	equipped_weapon_instance = null
	for entry in initial_items:
		if entry and entry.item_id != "":
			add_item(entry.item_id, entry.count)

	# 自动装备第一把武器
	if not equipped_weapon_instance and inventory.size() > 0:
		for inst in inventory:
			var data = ItemManager.get_item_data(inst.item_id)
			if data and data.type == "weapon":
				equipped_weapon_instance = inst
				print("单位 %s 自动装备武器: %s" % [unit_stats.unit_name, inst.item_id])
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

# ---- 库存辅助方法 ----
func get_inventory_summary() -> Dictionary:
	var summary = {}
	for inst in inventory:
		summary[inst.item_id] = summary.get(inst.item_id, 0) + inst.count
	return summary

func get_instances_by_id(item_id: String) -> Array[ItemInstance]:
	var result = []
	for inst in inventory:
		if inst.item_id == item_id:
			result.append(inst)
	return result

func find_first_instance(item_id: String) -> ItemInstance:
	for inst in inventory:
		if inst.item_id == item_id:
			return inst
	return null

func has_item(item_id: String) -> bool:
	return find_first_instance(item_id) != null

func get_item_total_count(item_id: String) -> int:
	var total = 0
	for inst in inventory:
		if inst.item_id == item_id:
			total += inst.count
	return total

func is_inventory_full() -> bool:
	var unique_ids = {}
	for inst in inventory:
		unique_ids[inst.item_id] = true
	return unique_ids.size() >= 5

func add_item(item_id: String, count: int = 1) -> bool:
	if is_inventory_full() and not has_item(item_id):
		return false
	var data = ItemManager.get_item_data(item_id)
	if data and data.type == "weapon":
		for _i in range(count):
			var inst = ItemInstance.new()
			inst.item_id = item_id
			inst.count = 1
			inventory.append(inst)
		return true
	else:
		for inst in inventory:
			if inst.item_id == item_id:
				inst.count += count
				return true
		var inst = ItemInstance.new()
		inst.item_id = item_id
		inst.count = count
		inventory.append(inst)
		return true

func remove_instance(instance: ItemInstance) -> bool:
	var idx = inventory.find(instance)
	if idx != -1:
		if instance == equipped_weapon_instance:
			equipped_weapon_instance = null
		inventory.remove_at(idx)
		return true
	return false

func drop_item(item_id: String) -> bool:
	var inst = find_first_instance(item_id)
	if inst:
		return remove_instance(inst)
	return false

# ---- 装备系统 ----
func get_weapon_data() -> ItemData:
	if not equipped_weapon_instance:
		return null
	return ItemManager.get_item_data(equipped_weapon_instance.item_id)

func get_weapon_stats() -> Dictionary:
	var weapon = get_weapon_data()
	if weapon:
		return {
			"attack": weapon.weapon_attack,
			"magic_attack": weapon.weapon_magic_attack,
			"heal_amount": weapon.weapon_heal_amount,
			"attack_range": weapon.weapon_attack_range,
			"min_attack_range": weapon.weapon_min_attack_range
		}
	return {
		"attack": 0,
		"magic_attack": 0,
		"heal_amount": 0,
		"attack_range": 0,
		"min_attack_range": 0
	}

func get_weapon_type() -> int:
	var weapon = get_weapon_data()
	return weapon.weapon_type if weapon else -1

func equip_weapon(item_id: String) -> bool:
	var inst = find_first_instance(item_id)
	if not inst:
		return false
	var data = ItemManager.get_item_data(item_id)
	if data and data.type == "weapon" and can_use_weapon(item_id):
		equipped_weapon_instance = inst
		return true
	return false

func equip_weapon_instance(inst: ItemInstance) -> bool:
	if inst and inst in inventory:
		var data = ItemManager.get_item_data(inst.item_id)
		if data and data.type == "weapon":
			equipped_weapon_instance = inst
			return true
	return false

func get_weapon_ids() -> Array[String]:
	var ids: Array[String] = []
	for inst in inventory:
		var data = ItemManager.get_item_data(inst.item_id)
		if data and data.type == "weapon" and not ids.has(inst.item_id):
			ids.append(inst.item_id)
	return ids

func has_any_weapon() -> bool:
	for inst in inventory:
		var data = ItemManager.get_item_data(inst.item_id)
		if data and data.type == "weapon":
			return true
	return false

func has_attack_target_with_weapon(weapon_id: String) -> bool:
	var data = ItemManager.get_item_data(weapon_id)
	if not data or data.type != "weapon":
		return false
	var max_range = data.weapon_attack_range
	var min_range = data.weapon_min_attack_range
	var is_healer = (data.weapon_heal_amount > 0)
	for target in UnitManager.unit_list:
		if target.hit_points <= 0:
			continue
		if is_healer:
			if target.unit_stats.team_id != unit_stats.team_id:
				continue
			if target == self:
				continue
		else:
			if target.unit_stats.team_id == unit_stats.team_id:
				continue
		var dist = abs(grid_cell.x - target.grid_cell.x) + abs(grid_cell.y - target.grid_cell.y)
		if dist >= min_range and dist <= max_range:
			return true
	return false

func has_any_attack_target() -> bool:
	for inst in inventory:
		if has_attack_target_with_weapon(inst.item_id):
			return true
	return false

# ---- 行动标记 ----
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

# ---- 动画控制 ----
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

# ---- 位置与状态保存/恢复 ----
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

# ---- UI 更新 ----
func update_hp_label():
	var hp_label = $HPLabel
	if hp_label:
		hp_label.text = str(hit_points) + "/" + str(unit_stats.max_hp)

func update_name_label():
	var na_label = $NameLabel
	if na_label:
		na_label.text = unit_stats.unit_name

func update_terrain_info():
	var terrain_label = $TerrainInfoLabel
	if not terrain_label:
		return
	var terrain_type = TerrainManager.get_terrain(grid_cell)
	var terrain_name = TerrainManager.get_terrain_name(terrain_type)
	var def_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["def_bonus"]
	var avoid_bonus = TerrainManager.TERRAIN_DATA[terrain_type]["avoid_bonus"]
	terrain_label.text = terrain_name + "\n防御+" + str(def_bonus) + " 回避+" + str(avoid_bonus)

# ---- 战斗伤害 ----
func apply_damage(damage_amount : int) -> bool:
	hit_points -= damage_amount
	if hit_points < 0: hit_points = 0
	update_hp_label()
	return hit_points <= 0

func update_position(new_cell: Vector2i):
	grid_cell = new_cell
	update_terrain_info()

# ---- 移动与行动 ----
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

# ---- 颜色与着色器（包含受击效果） ----
func set_gray(gray: bool):
	is_gray = gray
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

# Unit.gd 添加方法
func can_use_weapon(item_id: String) -> bool:
	if item_id == "":
		return false
	var data = ItemManager.get_item_data(item_id)
	if not data or data.type != "weapon":
		return false
	var allowed = UnitDataManagerClass.get_allowed_weapon_categories(unit_stats.unit_name)
	# 如果单位没有限制（如其他自定义单位），默认允许所有武器
	if allowed.is_empty():
		return true
	# 检查 category 是否在允许列表中
	return data.category in allowed

# 从 UnitData 恢复单位状态
func restore_from_unit_data(data: UnitData, cell: Vector2i):
	unit_stats = data
	grid_cell = cell
	previous_grid_cell = cell
	hit_points = data.hit_points
	remaining_move = data.move_range
	can_act_this_turn = true
	has_moved = false
	has_attacked = false
	has_acted = false
	
	# ---- 恢复库存 ----
	inventory.clear()
	for inst in data.inventory:
		var new_inst = ItemInstance.new()
		new_inst.item_id = inst.item_id
		new_inst.count = inst.count
		inventory.append(new_inst)
	
	if data.equipped_weapon != "":
		for inst in inventory:
			if inst.item_id == data.equipped_weapon:
				equipped_weapon_instance = inst
				break
	
	# ---- 加载 SpriteFrames（参考 setup_unit） ----
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
			# 占位纹理
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
	
	# ---- 更新颜色 ----
	update_color()
	
	# ---- 更新UI ----
	update_hp_label()
	update_name_label()
	update_terrain_info()

func serialize_inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []   # 显式类型
	for inst in inventory:
		result.append({
			"item_id": inst.item_id,
			"count": inst.count
		})
	return result

func get_equipped_weapon_id() -> String:
	return equipped_weapon_instance.item_id if equipped_weapon_instance else ""
