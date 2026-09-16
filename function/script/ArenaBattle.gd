extends CanvasLayer

signal closed(result: Dictionary)

const HIT_DURATION : float = 0.15
const HIT_OFFSET_DISTANCE : float = 8.0
const SHAKE_INTENSITY : float = 4.0
const SHAKE_DURATION : float = 0.15

var winner_team : int = -1
var _crystal_reward : int = 0
var _battle_index : int = 1

var _player : UnitData
var _enemy : UnitData
var _player_hp : int = 0
var _enemy_hp : int = 0
var _battle_running : bool = false

var _player_material : ShaderMaterial = null
var _enemy_material : ShaderMaterial = null
var _panel_base_pos : Vector2 = Vector2.ZERO

@onready var panel : Panel = $Panel
@onready var enemy_sprite : AnimatedSprite2D = $Panel/EnemySpriteContainer/EnemySprite
@onready var enemy_name : Label = $Panel/EnemyName
@onready var enemy_hp_bar : ProgressBar = $Panel/EnemyHpBar
@onready var enemy_hp_label : Label = $Panel/EnemyHpLabel
@onready var player_sprite : AnimatedSprite2D = $Panel/PlayerSpriteContainer/PlayerSprite
@onready var player_name : Label = $Panel/PlayerName
@onready var player_hp_bar : ProgressBar = $Panel/PlayerHpBar
@onready var player_hp_label : Label = $Panel/PlayerHpLabel
@onready var log_label : Label = $Panel/LogLabel
@onready var result_label : Label = $Panel/ResultLabel
@onready var continue_btn : Button = $Panel/BottomBar/ContinueButton
@onready var return_btn : Button = $Panel/BottomBar/ReturnButton


func _ready():
	await get_tree().process_frame
	if is_instance_valid(panel):
		_panel_base_pos = panel.position


func setup(player_data: UnitData, enemy_data: UnitData, crystal_reward: int = 0, battle_index: int = 1):
	_player = player_data
	_enemy = enemy_data
	_crystal_reward = crystal_reward
	_battle_index = battle_index

	MusicManager.play_arena_battle_music()

	_player_hp = player_data.hit_points
	_enemy_hp = enemy_data.max_hp

	var p_display = player_data.display_name if player_data.display_name != "" else player_data.unit_name
	var e_display = enemy_data.display_name if enemy_data.display_name != "" else enemy_data.unit_name
	player_name.text = p_display
	enemy_name.text = e_display

	_player_material = _setup_unit_sprite(player_sprite, player_data, 0)
	_enemy_material = _setup_unit_sprite(enemy_sprite, enemy_data, 1)

	player_hp_bar.max_value = player_data.max_hp
	player_hp_bar.value = _player_hp
	enemy_hp_bar.max_value = enemy_data.max_hp
	enemy_hp_bar.value = _enemy_hp

	log_label.text = "第 %d 场战斗开始！" % _battle_index

	_refresh_hp_labels()
	_run_battle()


func _setup_unit_sprite(sprite: AnimatedSprite2D, unit_data: UnitData, team_id: int) -> ShaderMaterial:
	var frames_path = UnitDataManager.get_sprite_frames_path(unit_data.unit_name)
	var loaded_ok = false
	if frames_path != "" and ResourceLoader.exists(frames_path):
		var frames = load(frames_path) as SpriteFrames
		if frames:
			sprite.sprite_frames = frames
			if frames.has_animation("idle"):
				sprite.play("idle")
			else:
				var anims = frames.get_animation_names()
				if anims.size() > 0:
					sprite.play(anims[0])
			loaded_ok = true

	if not loaded_ok:
		var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color.MAGENTA)
		var placeholder = ImageTexture.create_from_image(image)
		var pf = SpriteFrames.new()
		pf.add_animation("idle")
		pf.add_frame("idle", placeholder)
		sprite.sprite_frames = pf
		sprite.play("idle")

	var mat = _apply_team_shader(sprite, team_id)
	sprite.flip_h = (team_id == 1)
	return mat


func _apply_team_shader(sprite: AnimatedSprite2D, team_id: int) -> ShaderMaterial:
	var path = Config.PATHS.SHADER_REPLACE_COLOR
	if not ResourceLoader.exists(path):
		sprite.modulate = Globals.get_team_color(team_id, true)
		return null
	var shader = load(path) as Shader
	if not shader:
		sprite.modulate = Globals.get_team_color(team_id, true)
		return null

	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("target_color_1", Globals.TARGET_COLOR_1)
	mat.set_shader_parameter("target_color_2", Globals.TARGET_COLOR_2)
	var colors = Globals.TEAM_COLORS.get(team_id, Globals.TEAM_COLORS[0])
	mat.set_shader_parameter("assign_color_1", colors["primary"])
	mat.set_shader_parameter("assign_color_2", colors["secondary"])
	mat.set_shader_parameter("hit_offset_amount", Vector2.ZERO)
	mat.set_shader_parameter("hit_duration", HIT_DURATION)
	mat.set_shader_parameter("hit_elapsed", HIT_DURATION)
	mat.set_shader_parameter("hit_flash_color", Color.WHITE)
	mat.set_shader_parameter("hit_enable_flash", false)

	sprite.material = mat
	sprite.modulate = Color.WHITE
	return mat


func _run_battle():
	if _battle_running:
		return
	_battle_running = true

	await get_tree().create_timer(0.5, true, false, true).timeout

	var player_first = _player.dexterity >= _enemy.dexterity
	var attacker_first = _player if player_first else _enemy
	var attacker_second = _enemy if player_first else _player

	var turn = 0
	while _player_hp > 0 and _enemy_hp > 0 and turn < 50:
		await _do_attack(attacker_first, attacker_second)
		if _player_hp <= 0 or _enemy_hp <= 0:
			break
		await _do_attack(attacker_second, attacker_first)
		if _player_hp <= 0 or _enemy_hp <= 0:
			break
		turn += 1

	if _player_hp > 0 and _enemy_hp <= 0:
		winner_team = 0
		result_label.text = "胜利  +%d 结晶" % _crystal_reward
		result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
		MusicManager.play_victory_music()
		continue_btn.visible = true
		return_btn.visible = true
	elif _enemy_hp > 0 and _player_hp <= 0:
		winner_team = 1
		result_label.text = "失败"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1))
		MusicManager.play_defeat_music()
		continue_btn.visible = false
		return_btn.visible = true
	else:
		winner_team = 0 if _player_hp >= _enemy_hp else 1
		result_label.text = "平局"
		MusicManager.play_defeat_music()
		continue_btn.visible = false
		return_btn.visible = true


func _do_attack(attacker: UnitData, defender: UnitData):
	if _player_hp <= 0 or _enemy_hp <= 0:
		return

	var damage = _calc_damage(attacker, defender)

	var is_player_attacker = (attacker == _player)
	if is_player_attacker:
		_enemy_hp = max(0, _enemy_hp - damage)
		enemy_hp_bar.value = _enemy_hp
		_play_hit_effect(enemy_sprite, _enemy_material, Vector2(-1, 0))
		_shake_panel(Vector2(-1, 0))
	else:
		_player_hp = max(0, _player_hp - damage)
		player_hp_bar.value = _player_hp
		_play_hit_effect(player_sprite, _player_material, Vector2(1, 0))
		_shake_panel(Vector2(1, 0))

	SoundManager.play_hit_sound()

	var atk_name = attacker.display_name if attacker.display_name != "" else attacker.unit_name
	var def_name = defender.display_name if defender.display_name != "" else defender.unit_name
	log_label.text = "%s 攻击 %s，造成 %d 伤害" % [atk_name, def_name, damage]

	_refresh_hp_labels()
	await get_tree().create_timer(0.6, true, false, true).timeout


func _play_hit_effect(sprite: AnimatedSprite2D, material: ShaderMaterial, direction: Vector2):
	if not is_instance_valid(sprite) or not material:
		return
	var dir_norm = direction.normalized()
	var hit_offset = dir_norm * HIT_OFFSET_DISTANCE
	material.set_shader_parameter("hit_offset_amount", hit_offset)
	material.set_shader_parameter("hit_duration", HIT_DURATION)
	material.set_shader_parameter("hit_elapsed", 0.0)
	material.set_shader_parameter("hit_flash_color", Color.WHITE)
	material.set_shader_parameter("hit_enable_flash", true)

	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_method(
		func(val):
			if is_instance_valid(material):
				material.set_shader_parameter("hit_elapsed", val),
		0.0, HIT_DURATION, HIT_DURATION
	)
	tween.tween_callback(func():
		if is_instance_valid(material):
			material.set_shader_parameter("hit_enable_flash", false)
			material.set_shader_parameter("hit_elapsed", 0.0)
	)


func _shake_panel(direction: Vector2, intensity: float = SHAKE_INTENSITY, duration: float = SHAKE_DURATION):
	if not is_instance_valid(panel):
		return
	var dir_norm = direction.normalized() if direction != Vector2.ZERO else Vector2(randf_range(-1.0, 1.0), 0)
	var shake_offset = dir_norm * intensity

	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(panel, "position", _panel_base_pos + shake_offset, duration * 0.1)
	tween.tween_property(panel, "position", _panel_base_pos, duration * 0.9)


func _calc_damage(attacker: UnitData, defender: UnitData) -> int:
	if not attacker.weapon_slot:
		return 1
	var weapon_data = ItemManager.get_item_data(attacker.weapon_slot.item_id)
	if not weapon_data:
		return 1

	var quality_mult = CombatManager.QUALITY_MULT.get(weapon_data.quality, 1.0)
	var upgrade_bonus = attacker.weapon_slot.upgrade_level
	var base_attack = (weapon_data.base_attack + upgrade_bonus) * quality_mult

	var atk_bonus = 0.0
	for attr in weapon_data.modifier:
		var val = 0
		match attr:
			"strength": val = attacker.strength
			"dexterity": val = attacker.dexterity
			"intelligence": val = attacker.intelligence
			"faith": val = attacker.faith
			"arcane": val = attacker.arcane
		atk_bonus += val * weapon_data.modifier[attr]

	var total_attack = base_attack + atk_bonus
	total_attack *= (1.0 + attacker.buff_attack_percent)

	var armor_defense = 0
	for slot in defender.armor_slots:
		if slot:
			var item_data = ItemManager.get_item_data(slot.item_id)
			if item_data:
				var armor_quality_mult = CombatManager.QUALITY_MULT.get(item_data.quality, 1.0)
				armor_defense += item_data.defense * armor_quality_mult
	var def_value = defender.strength * CombatManager.STRENGTH_DEF_FACTOR + armor_defense
	def_value += defender.buff_defense_flat

	var damage = max(1, int(total_attack - def_value))

	if defender.buff_damage_reduction > 0:
		damage = max(1, int(damage * (1.0 - defender.buff_damage_reduction)))

	return damage


func _refresh_hp_labels():
	player_hp_label.text = "%d/%d" % [_player_hp, _player.max_hp]
	enemy_hp_label.text = "%d/%d" % [_enemy_hp, _enemy.max_hp]


func _emit_result(continue_requested: bool):
	closed.emit({
		"winner_team": winner_team,
		"remaining_hp": _player_hp,
		"continue_requested": continue_requested,
	})
	queue_free()


func _on_continue_pressed():
	_emit_result(true)


func _on_return_pressed():
	_emit_result(false)
