extends CanvasLayer

signal closed(result: Dictionary)

const HIT_DURATION : float = 0.15
const HIT_OFFSET_DISTANCE : float = 8.0
const SHAKE_INTENSITY : float = 4.0
const SHAKE_DURATION : float = 0.15

# 暴击
const CRIT_BASE_CHANCE : float = 0.05
const CRIT_PER_DEXTERITY : float = 0.005
const CRIT_CHANCE_BY_QUALITY : Dictionary = {
	"common": 0.0, "rare": 0.03, "epic": 0.05, "legendary": 0.08,
}
const CRIT_DAMAGE_MULT : float = 1.5
const QUALITY_MULT = {
	"common": 1.0, "rare": 1.25, "epic": 1.5, "legendary": 1.8,
}
const STRENGTH_DEF_FACTOR : float = 0.3

# ---- 新增词条参数 ----
const BLEED_MAX_STACKS : int = 5
const BLEED_BASE_PERCENT : float = 0.15
const BLEED_PER_LEVEL : float = 0.05

const COUNTER_BASE_PERCENT : float = 0.30
const COUNTER_PER_LEVEL : float = 0.10

const STAFF_SELF_HEAL_PERCENT : float = 0.10
const HEAL_BOOST_BASE : float = 1.30
const HEAL_BOOST_PER_LEVEL : float = 0.20

const SPELL_CHAIN_BASE : float = 0.80
const SPELL_CHAIN_PER_LEVEL : float = 0.10

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

# ---- 词条运行时状态 ----
var _player_zeal_target : String = ""
var _player_zeal_stacks : int = 0
var _enemy_zeal_target : String = ""
var _enemy_zeal_stacks : int = 0

# ---- 出血层数（本场累积）----
var _player_bleed_stacks : int = 0
var _enemy_bleed_stacks : int = 0

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
	if unit_data.override_sprite_path != "" and ResourceLoader.exists(unit_data.override_sprite_path):
		frames_path = unit_data.override_sprite_path
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


# ============================================================
#  词条运行时辅助
# ============================================================
func _is_talent_ready(data: UnitData, talent_id: String) -> bool:
	if not data: return false
	for inst in data.talent_slots:
		if inst and inst.talent_id == talent_id and inst.is_active:
			return inst.is_ready
	return false


func _reset_talent(data: UnitData, talent_id: String):
	if not data: return
	for inst in data.talent_slots:
		if inst and inst.talent_id == talent_id:
			inst.reset()
			var cd = TalentManager.get_cooldown_after_trigger(talent_id)
			if cd > 0:
				inst.cooldown_remaining = cd
			return


func _accumulate_talents(data: UnitData):
	if not data: return
	TalentManager.accumulate_talents(data.talent_slots)


func _get_talent_level(data: UnitData, talent_id: String) -> int:
	if not data: return 1
	return TalentManager.get_talent_level(data.unit_name, talent_id)


# ============================================================
#  战斗主循环
# ============================================================
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
		_accumulate_talents(_player)
		_accumulate_talents(_enemy)

	if _player_hp > 0 and _enemy_hp <= 0:
		winner_team = 0
		result_label.text = "胜利"
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
		# 平局：以剩余 HP 多寡判定
		winner_team = 0 if _player_hp >= _enemy_hp else 1
		if winner_team == 0:
			result_label.text = "险胜"
			result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
			MusicManager.play_victory_music()
		else:
			result_label.text = "惜败"
			result_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1))
			MusicManager.play_defeat_music()
		continue_btn.visible = false
		return_btn.visible = true

func _do_attack(attacker: UnitData, defender: UnitData):
	if _player_hp <= 0 or _enemy_hp <= 0:
		return

	var is_player_attacker = (attacker == _player)

	# ---- 计算基础伤害 ----
	var damage = _calc_damage(attacker, defender)

	# ---- 主动技能（就绪时自动触发）----
	var ready_skills : Array = TalentManager.get_ready_active_skills(attacker)
	if ready_skills.size() > 0:
		var skill_id : String = ready_skills[0]
		var skill_data = TalentManager.get_talent_data(skill_id)
		if skill_data:
			var ep : Dictionary = skill_data.effect_params
			damage = int(damage * float(ep.get("damage_mult", 1.0)))
			if bool(ep.get("force_crit", false)):
				damage = int(damage * CRIT_DAMAGE_MULT)
				print("[Arena] 主动技能 %s 触发：强制暴击" % skill_data.display_name)
			else:
				print("[Arena] 主动技能 %s 触发" % skill_data.display_name)
			TalentManager.consume_active_skill(attacker, skill_id)

	# ---- 狂热 ----
	var target_key = defender.unit_name
	var zeal_stacks : int = 0
	if is_player_attacker:
		if _player_zeal_target == target_key:
			_player_zeal_stacks = mini(_player_zeal_stacks + 1, 5)
		else:
			_player_zeal_target = target_key
			_player_zeal_stacks = 1
		zeal_stacks = _player_zeal_stacks
	else:
		if _enemy_zeal_target == target_key:
			_enemy_zeal_stacks = mini(_enemy_zeal_stacks + 1, 5)
		else:
			_enemy_zeal_target = target_key
			_enemy_zeal_stacks = 1
		zeal_stacks = _enemy_zeal_stacks

	if zeal_stacks > 1 and _is_talent_ready(attacker, "zeal"):
		var lv_zeal = _get_talent_level(attacker, "zeal")
		var per = 0.10 + (lv_zeal - 1) * 0.05
		var bonus = 1.0 + (zeal_stacks - 1) * per
		damage = int(damage * bonus)
		_reset_talent(attacker, "zeal")

	# ---- 暴击判定 ----
	var is_crit := false
	var crit_mult : float = CRIT_DAMAGE_MULT

	if _is_talent_ready(attacker, "crit"):
		var lv_crit = _get_talent_level(attacker, "crit")
		crit_mult = 2.0 + (lv_crit - 1) * 0.5
		is_crit = true
		_reset_talent(attacker, "crit")
	elif _roll_crit(attacker):
		is_crit = true

	if is_crit:
		damage = int(damage * crit_mult)

	# ---- 盾反（parry）----
	if _is_talent_ready(defender, "parry"):
		var lv = _get_talent_level(defender, "parry")
		var reflect = 0.5 + (lv - 1) * 0.15
		var parry_dmg = int(damage * reflect)
		if is_player_attacker:
			_player_hp = max(0, _player_hp - parry_dmg)
			player_hp_bar.value = _player_hp
		else:
			_enemy_hp = max(0, _enemy_hp - parry_dmg)
			enemy_hp_bar.value = _enemy_hp
		_reset_talent(defender, "parry")

	# ★ ---- 反击强化（counter_boost）----
	if _is_talent_ready(defender, "counter_boost"):
		var lv = _get_talent_level(defender, "counter_boost")
		var reflect_pct = COUNTER_BASE_PERCENT + (lv - 1) * COUNTER_PER_LEVEL
		var reflect_dmg = maxi(1, int(damage * reflect_pct))
		if is_player_attacker:
			_player_hp = maxi(0, _player_hp - reflect_dmg)
			player_hp_bar.value = _player_hp
		else:
			_enemy_hp = maxi(0, _enemy_hp - reflect_dmg)
			enemy_hp_bar.value = _enemy_hp
		_reset_talent(defender, "counter_boost")
		print("[Arena] 反击强化触发：Lv.%d 反弹 %d" % [lv, reflect_dmg])

	# ---- 格挡 ----
	if _is_talent_ready(defender, "block"):
		var lv = _get_talent_level(defender, "block")
		var reduce = 0.5 + (lv - 1) * 0.1
		damage = int(damage * (1.0 - reduce))
		_reset_talent(defender, "block")

	# ---- 应用伤害 ----
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
	var crit_str : String = "（暴击！）" if is_crit else ""
	log_label.text = "%s 攻击 %s%s，造成 %d 伤害" % [atk_name, def_name, crit_str, damage]

	# ---- 吸血 ----
	if _is_talent_ready(attacker, "lifesteal"):
		var lv_ls = _get_talent_level(attacker, "lifesteal")
		var pct = 0.2 + (lv_ls - 1) * 0.1
		var heal = int(damage * pct)
		if is_player_attacker:
			var old = _player_hp
			_player_hp = mini(_player_hp + heal, _player.max_hp)
			var actual = _player_hp - old
			if actual > 0:
				player_hp_bar.value = _player_hp
				log_label.text += "  [吸血 +%d]" % actual
		else:
			var old = _enemy_hp
			_enemy_hp = mini(_enemy_hp + heal, _enemy.max_hp)
			var actual = _enemy_hp - old
			if actual > 0:
				enemy_hp_bar.value = _enemy_hp
				log_label.text += "  [吸血 +%d]" % actual
		_reset_talent(attacker, "lifesteal")

	_refresh_hp_labels()
	await get_tree().create_timer(0.6, true, false, true).timeout

	# ★ ---- 出血（bleed）：攻击方给防守方叠层 ----
	if _is_talent_ready(attacker, "bleed"):
		var lv = _get_talent_level(attacker, "bleed")
		var pct = BLEED_BASE_PERCENT + (lv - 1) * BLEED_PER_LEVEL
		if is_player_attacker:
			_enemy_bleed_stacks += 1
			if _enemy_bleed_stacks >= BLEED_MAX_STACKS:
				var bleed_dmg = maxi(1, int(defender.max_hp * pct))
				_enemy_hp = maxi(0, _enemy_hp - bleed_dmg)
				enemy_hp_bar.value = _enemy_hp
				_enemy_bleed_stacks = 0
				log_label.text += "  [出血爆发 -%d]" % bleed_dmg
		else:
			_player_bleed_stacks += 1
			if _player_bleed_stacks >= BLEED_MAX_STACKS:
				var bleed_dmg = maxi(1, int(defender.max_hp * pct))
				_player_hp = maxi(0, _player_hp - bleed_dmg)
				player_hp_bar.value = _player_hp
				_player_bleed_stacks = 0
				log_label.text += "  [出血爆发 -%d]" % bleed_dmg
		_reset_talent(attacker, "bleed")
		_refresh_hp_labels()

	# ★ ---- 治疗法杖自愈（heal_boost）----
	var weapon_data = null
	if attacker.weapon_slot:
		weapon_data = ItemManager.get_item_data(attacker.weapon_slot.item_id)
	if weapon_data and weapon_data.category == "staff":
		var self_heal_pct = STAFF_SELF_HEAL_PERCENT
		if _is_talent_ready(attacker, "heal_boost"):
			var lv_hb = _get_talent_level(attacker, "heal_boost")
			self_heal_pct *= (HEAL_BOOST_BASE + (lv_hb - 1) * HEAL_BOOST_PER_LEVEL)
			_reset_talent(attacker, "heal_boost")
			print("[Arena] 治愈强化：自愈倍率 %.2f" % self_heal_pct)
		var heal = maxi(1, int(attacker.max_hp * self_heal_pct))
		if is_player_attacker:
			var old_hp = _player_hp
			_player_hp = mini(_player_hp + heal, _player.max_hp)
			var actual = _player_hp - old_hp
			if actual > 0:
				player_hp_bar.value = _player_hp
				log_label.text += "  [自愈 +%d]" % actual
		else:
			var old_hp = _enemy_hp
			_enemy_hp = mini(_enemy_hp + heal, _enemy.max_hp)
			var actual = _enemy_hp - old_hp
			if actual > 0:
				enemy_hp_bar.value = _enemy_hp
				log_label.text += "  [自愈 +%d]" % actual
		_refresh_hp_labels()

	# ★ ---- 法术连击（spell_chain）----
	if _is_talent_ready(attacker, "spell_chain"):
		if weapon_data and (weapon_data.category == "spellbook" or weapon_data.category == "staff"):
			var lv_sc = _get_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_BASE + (lv_sc - 1) * SPELL_CHAIN_PER_LEVEL
			var extra = maxi(1, int(damage * mult))
			if is_player_attacker:
				_enemy_hp = maxi(0, _enemy_hp - extra)
				enemy_hp_bar.value = _enemy_hp
			else:
				_player_hp = maxi(0, _player_hp - extra)
				player_hp_bar.value = _player_hp
			_reset_talent(attacker, "spell_chain")
			log_label.text += "  [法术连击 +%d]" % extra
			_refresh_hp_labels()
			await get_tree().create_timer(0.4, true, false, true).timeout

	# ---- 复活（死亡检查）----
	if _player_hp <= 0 and _is_talent_ready(_player, "revive"):
		_player_hp = _player.max_hp
		player_hp_bar.value = _player_hp
		_reset_talent(_player, "revive")
		log_label.text = "复活触发！%s 满血复活" % (atk_name if not is_player_attacker else def_name)
		_refresh_hp_labels()
		await get_tree().create_timer(0.6, true, false, true).timeout
	if _enemy_hp <= 0 and _is_talent_ready(_enemy, "revive"):
		_enemy_hp = _enemy.max_hp
		enemy_hp_bar.value = _enemy_hp
		_reset_talent(_enemy, "revive")
		log_label.text = "复活触发！%s 满血复活" % (atk_name if is_player_attacker else def_name)
		_refresh_hp_labels()
		await get_tree().create_timer(0.6, true, false, true).timeout

	# ---- 二次攻击 ----
	if _is_talent_ready(attacker, "double_attack") and _player_hp > 0 and _enemy_hp > 0:
		var lv_da = _get_talent_level(attacker, "double_attack")
		var mult = 0.8 + (lv_da - 1) * 0.1
		var extra = int(damage * mult)
		_reset_talent(attacker, "double_attack")
		if is_player_attacker:
			_enemy_hp = max(0, _enemy_hp - extra)
			enemy_hp_bar.value = _enemy_hp
		else:
			_player_hp = max(0, _player_hp - extra)
			player_hp_bar.value = _player_hp
		SignalBus.request_damage_popup.emit(Vector2.ZERO, extra, false, false, false)
		log_label.text += "  [二次攻击 +%d]" % extra
		_refresh_hp_labels()
		await get_tree().create_timer(0.4, true, false, true).timeout

func _calc_damage(attacker: UnitData, defender: UnitData) -> int:
	var wdata = null
	if attacker.weapon_slot:
		wdata = ItemManager.get_item_data(attacker.weapon_slot.item_id)
	if not wdata:
		return 1

	var quality_mult = QUALITY_MULT.get(wdata.quality, 1.0)
	var upgrade_bonus = attacker.weapon_slot.upgrade_level
	var base_attack = (wdata.base_attack + upgrade_bonus) * quality_mult

	var atk_bonus = 0.0
	for attr in wdata.modifier:
		var val = attacker.get_effective_attr(attr)
		atk_bonus += val * wdata.modifier[attr]

	var total_attack = base_attack + atk_bonus
	total_attack *= (1.0 + attacker.buff_attack_percent)

	var armor_defense = 0
	for slot in defender.armor_slots:
		if slot:
			var idata = ItemManager.get_item_data(slot.item_id)
			if idata:
				var aq = QUALITY_MULT.get(idata.quality, 1.0)
				armor_defense += idata.defense * aq

	var def_value = defender.get_effective_attr("strength") * STRENGTH_DEF_FACTOR + armor_defense
	var damage = max(1, int(total_attack - def_value))

	if defender.buff_damage_reduction > 0:
		damage = max(1, int(damage * (1.0 - defender.buff_damage_reduction)))

	return damage


func _roll_crit(attacker: UnitData) -> bool:
	var chance : float = CRIT_BASE_CHANCE
	chance += attacker.get_effective_attr("dexterity") * CRIT_PER_DEXTERITY
	if attacker.weapon_slot:
		var wdata = ItemManager.get_item_data(attacker.weapon_slot.item_id)
		if wdata:
			chance += CRIT_CHANCE_BY_QUALITY.get(wdata.quality, 0.0)
	return randf() < chance


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
