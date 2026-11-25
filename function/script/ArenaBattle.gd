extends CanvasLayer

signal closed(result: Dictionary)


var CRIT_BASE_CHANCE : float = 0.05
var CRIT_PER_DEXTERITY : float = 0.005
var CRIT_CHANCE_BY_QUALITY : Dictionary = {"common":0.0,"rare":0.03,"epic":0.05,"legendary":0.08}
var CRIT_DAMAGE_MULT : float = 1.5
var CRIT_DAMAGE_CAP : float = 2.0  # ★ v5.10 对齐正式战场：暴伤倍率上限
var QUALITY_MULT : Dictionary = {"common":1.0,"rare":1.25,"epic":1.5,"legendary":1.8}
var STRENGTH_DEF_FACTOR : float = 0.3
var REDUCTION_CAP : float = 0.75
var MIN_DAMAGE_FLOOR : float = 0.10
var BLEED_MAX_STACKS : int = 5
var BLEED_BASE_PERCENT : float = 0.15
var BLEED_PER_LEVEL : float = 0.05
var COUNTER_BASE_PERCENT : float = 0.30
var COUNTER_PER_LEVEL : float = 0.10
var STAFF_SELF_HEAL_PERCENT : float = 0.10
var HEAL_BOOST_BASE : float = 1.30
var HEAL_BOOST_PER_LEVEL : float = 0.20
var SPELL_CHAIN_BASE : float = 0.80
var SPELL_CHAIN_PER_LEVEL : float = 0.10


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

var _player_zeal_target : String = ""
var _player_zeal_stacks : int = 0
var _enemy_zeal_target : String = ""
var _enemy_zeal_stacks : int = 0

# ★ 对齐正式战场：遗物"首攻必暴击"剩余次数
# 用独立成员跟踪，避免污染外部传入、竞技场连续多场复用的 UnitData
var _player_first_attack_crit_remaining : int = 0
var _enemy_first_attack_crit_remaining : int = 0
var _first_crit_this_hit : bool = false  # 本次攻击是否由首攻必暴击触发（用于日志提示）

var _player_bleed_stacks : int = 0
var _enemy_bleed_stacks : int = 0

var _total_damage_dealt : int = 0
var _total_damage_taken : int = 0
var _crit_count : int = 0

# ★ v6.10：六流派机制同步（竞技场简化版，复用 BuildManager 数值表）
var _player_soul: int = 0          # 简化魂火：命中+1、击杀按轮回额外，上限 6
var _enemy_soul: int = 0
const ARENA_SOUL_CAP: int = 6
var _player_sacrifice_bonus: float = 0.0   # 献祭本轮攻击加成
var _enemy_sacrifice_bonus: float = 0.0
# ★ v6.69：觉醒技改为魂火消费 + 按回合冷却（1v1 自动战斗版，条件满足自动释放）
var _player_awakening_cd: int = 0
var _enemy_awakening_cd: int = 0
var _arena_awakening_cost: int = 6
var _arena_awakening_cd_rounds: int = 3
var _player_ember_charged: bool = false    # 余烬：魂火耗尽后的必暴标记
var _enemy_ember_charged: bool = false

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
	_apply_config()
	await get_tree().process_frame
	if is_instance_valid(panel):
		_panel_base_pos = panel.position


func _apply_config():
	var aw_cfg : Dictionary = GameConfigManager.get_value("combat_config.json", "awakening", {})
	_arena_awakening_cost = maxi(1, int(aw_cfg.get("soul_fire_cost", _arena_awakening_cost)))
	_arena_awakening_cd_rounds = maxi(0, int(aw_cfg.get("cooldown_rounds", _arena_awakening_cd_rounds)))
	var cfg : Dictionary = GameConfigManager.get_value("combat_config.json", "arena_battle", {})
	CRIT_BASE_CHANCE = float(cfg.get("crit_base_chance", CRIT_BASE_CHANCE))
	CRIT_PER_DEXTERITY = float(cfg.get("crit_per_dexterity", CRIT_PER_DEXTERITY))
	CRIT_CHANCE_BY_QUALITY = cfg.get("crit_chance_by_quality", CRIT_CHANCE_BY_QUALITY).duplicate()
	CRIT_DAMAGE_MULT = float(cfg.get("crit_damage_mult", CRIT_DAMAGE_MULT))
	# ★ v5.10 对齐正式战场：竞技场配置段若无该键，回退到 combat_config 顶层值
	CRIT_DAMAGE_CAP = float(cfg.get("crit_damage_cap",
		GameConfigManager.get_value("combat_config.json", "crit_damage_cap", CRIT_DAMAGE_CAP)))
	QUALITY_MULT = cfg.get("quality_mult", QUALITY_MULT).duplicate()
	STRENGTH_DEF_FACTOR = float(cfg.get("strength_def_factor", STRENGTH_DEF_FACTOR))
	REDUCTION_CAP = float(cfg.get("reduction_cap", REDUCTION_CAP))
	MIN_DAMAGE_FLOOR = float(cfg.get("min_damage_floor", MIN_DAMAGE_FLOOR))
	BLEED_MAX_STACKS = int(cfg.get("bleed_max_stacks", BLEED_MAX_STACKS))
	BLEED_BASE_PERCENT = float(cfg.get("bleed_base_percent", BLEED_BASE_PERCENT))
	BLEED_PER_LEVEL = float(cfg.get("bleed_per_level", BLEED_PER_LEVEL))
	COUNTER_BASE_PERCENT = float(cfg.get("counter_base_percent", COUNTER_BASE_PERCENT))
	COUNTER_PER_LEVEL = float(cfg.get("counter_per_level", COUNTER_PER_LEVEL))
	STAFF_SELF_HEAL_PERCENT = float(cfg.get("staff_self_heal_percent", STAFF_SELF_HEAL_PERCENT))
	HEAL_BOOST_BASE = float(cfg.get("heal_boost_base", HEAL_BOOST_BASE))
	HEAL_BOOST_PER_LEVEL = float(cfg.get("heal_boost_per_level", HEAL_BOOST_PER_LEVEL))
	SPELL_CHAIN_BASE = float(cfg.get("spell_chain_base", SPELL_CHAIN_BASE))
	SPELL_CHAIN_PER_LEVEL = float(cfg.get("spell_chain_per_level", SPELL_CHAIN_PER_LEVEL))


func setup(player_data: UnitData, enemy_data: UnitData, crystal_reward: int = 0, battle_index: int = 1):
	_player = player_data
	_enemy = enemy_data
	_crystal_reward = crystal_reward
	_battle_index = battle_index

	MusicManager.play_arena_battle_music()

	_player_hp = player_data.hit_points
	_enemy_hp = enemy_data.max_hp

	# ★ v6.10：简化魂火初始化；双方按流派机制生效
	_player_soul = 1
	_enemy_soul = 1
	_player_sacrifice_bonus = 0.0
	_enemy_sacrifice_bonus = 0.0
	_player_awakening_cd = 0
	_enemy_awakening_cd = 0
	_player_ember_charged = false
	_enemy_ember_charged = false

	# ★ 对齐正式战场：遗物"首攻必暴击"（TurnController.apply_team_buffs 同源）
	# 每场竞技场战斗重新结算；精炼 relic_attack 时 2 次，否则 1 次
	var relic_effects : Dictionary = GameState.get_global_relic_effects()
	_player_first_attack_crit_remaining = 0
	if bool(relic_effects.get("first_attack_crit", false)):
		_player_first_attack_crit_remaining = 2 if GameState.is_relic_equipped_and_refined("relic_attack") else 1
	_enemy_first_attack_crit_remaining = 0

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
	# ★ v6.62p：赋能单位统一用 overlord 图片/动画
	var frames : SpriteFrames = null
	if unit_data != null and unit_data.is_empowered:
		frames = load(UnitDataManager.EMPOWERED_FRAMES_PATH) as SpriteFrames
	if frames == null:
		frames = UnitDataManager.get_sprite_frames(unit_data.unit_name)

	if frames:
		sprite.sprite_frames = frames
		if frames.has_animation("idle"):
			sprite.play("idle")
		else:
			var anims = frames.get_animation_names()
			if anims.size() > 0: sprite.play(anims[0])
	else:
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


func _is_talent_ready(data: UnitData, talent_id: String) -> bool:
	var inst = _get_talent_inst(data, talent_id)
	return inst != null and inst.is_ready and inst.is_active


# ★ 对齐正式战场：遗物"首攻必暴击"剩余次数读取（竞技场用独立成员，避免污染 UnitData）
func _get_first_attack_crit_remaining(data: UnitData) -> int:
	if data == _player:
		return _player_first_attack_crit_remaining
	return _enemy_first_attack_crit_remaining


func _consume_first_attack_crit(data: UnitData) -> void:
	if data == _player:
		_player_first_attack_crit_remaining = maxi(0, _player_first_attack_crit_remaining - 1)
	else:
		_enemy_first_attack_crit_remaining = maxi(0, _enemy_first_attack_crit_remaining - 1)


func _reset_talent(data: UnitData, talent_id: String):
	var inst = _get_talent_inst(data, talent_id)
	if not inst: return
	inst.reset()
	var cd = TalentManager.get_cooldown_after_trigger(talent_id)
	if cd > 0:
		inst.cooldown_remaining = cd


func _accumulate_talents(data: UnitData):
	if not data: return
	TalentManager.accumulate_talents(data.talent_slots)
	if data.advanced_talent_inst:
		TalentManager.accumulate_talents([data.advanced_talent_inst])


func _get_talent_level(data: UnitData, talent_id: String) -> int:
	if not data: return 1
	return TalentManager.get_talent_level(data.unit_name, talent_id)


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
		# ★ v6.10：献祭流派——回合开始扣血换本回合攻击加成
		_apply_sacrifice(_player, true)
		_apply_sacrifice(_enemy, false)
		# ★ v6.69：觉醒技冷却按回合递减；魂火够 + 冷却归零则自动释放
		if _player_awakening_cd > 0: _player_awakening_cd -= 1
		if _enemy_awakening_cd > 0: _enemy_awakening_cd -= 1
		_try_release_build_burst(_player, true)
		_try_release_build_burst(_enemy, false)
		if _player_hp <= 0 or _enemy_hp <= 0:
			break

	# ★ v6.10：击杀方的轮回流派回魂火
	if _enemy_hp <= 0 and _player_hp > 0:
		_arena_on_kill(_player, _enemy, true)
	elif _player_hp <= 0 and _enemy_hp > 0:
		_arena_on_kill(_enemy, _player, false)

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
		var p_max : int = maxi(1, _player.max_hp)
		var e_max : int = maxi(1, _enemy.max_hp)
		var p_ratio : float = float(_player_hp) / float(p_max)
		var e_ratio : float = float(_enemy_hp) / float(e_max)

		if p_ratio > e_ratio:
			winner_team = 0
			result_label.text = "险胜"
			result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
			MusicManager.play_victory_music()
		elif e_ratio > p_ratio:
			winner_team = 1
			result_label.text = "惜败"
			result_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1))
			MusicManager.play_defeat_music()
		else:
			winner_team = 0 if _player_hp >= _enemy_hp else 1
			result_label.text = "险胜" if winner_team == 0 else "惜败"
			result_label.add_theme_color_override(
				"font_color",
				Color(0.3, 1.0, 0.3, 1) if winner_team == 0 else Color(1.0, 0.4, 0.4, 1))
			if winner_team == 0:
				MusicManager.play_victory_music()
			else:
				MusicManager.play_defeat_music()
		continue_btn.visible = false
		return_btn.visible = true


func _do_attack(attacker: UnitData, defender: UnitData):
	if _player_hp <= 0 or _enemy_hp <= 0:
		return

	var is_player_attacker = (attacker == _player)
	var force_crit_skill : bool = false  # 主动技能强制暴击标记（v5.10 改为走统一暴伤通道）
	_first_crit_this_hit = false

	var damage = _calc_damage(attacker, defender)

	# ★ v5.10 对齐正式战场：重击倍率。竞技场无 charge 叠层，用普通 damage_multiplier；
	# 与主动技能倍率取 max（不叠加），与 CombatManager 第 438 行口径一致。
	var heavy_mult : float = 1.0
	if not attacker.heavy_attack.is_empty():
		heavy_mult = float(attacker.heavy_attack.get("damage_multiplier", 1.0))

	# ---- 主动技能 ----
	var ready_skills : Array = TalentManager.get_ready_active_skills(attacker)
	var has_active_skill : bool = false
	if ready_skills.size() > 0:
		var skill_id : String = ready_skills[0]
		var skill_data = TalentManager.get_talent_data(skill_id)
		if skill_data:
			has_active_skill = true
			var ep : Dictionary = skill_data.effect_params
			var skill_mult : float = float(ep.get("damage_mult", 1.0))
			damage = int(damage * maxf(skill_mult, heavy_mult))
			if bool(ep.get("force_crit", false)):
				force_crit_skill = true
				print("[Arena] 主动技能 %s 触发：强制暴击" % skill_data.display_name)
			else:
				print("[Arena] 主动技能 %s 触发" % skill_data.display_name)
			TalentManager.consume_active_skill(attacker, skill_id)
			# ★ v6.10：主动技能消耗简化魂火（对齐主线 2 点），归零则给余烬必暴标记
			var soul_cost: int = int(skill_data.effect_params.get("soul_fire_cost", 2))
			if is_player_attacker:
				_player_soul = maxi(0, _player_soul - soul_cost)
				if _player_soul <= 0 and BuildManager.get_effective_school_level(_player, "余烬") > 0:
					_player_ember_charged = true
			else:
				_enemy_soul = maxi(0, _enemy_soul - soul_cost)
				if _enemy_soul <= 0 and BuildManager.get_effective_school_level(_enemy, "余烬") > 0:
					_enemy_ember_charged = true

	if not has_active_skill and heavy_mult > 1.0:
		damage = int(damage * heavy_mult)

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

	# ---- 暴击（v5.10 全面对齐正式战场统一暴伤通道）----
	var is_crit := false
	var crit_talent_triggered : bool = false
	# 竞技场无魂火系统，故不含 SoulFireManager 暴伤；其余加成与正式战场一致
	var crit_mult : float = CRIT_DAMAGE_MULT
	crit_mult += _total_affix(attacker, "crit_damage")
	crit_mult += attacker.static_crit_damage_bonus
	crit_mult += attacker.buff_crit_damage_bonus

	if force_crit_skill:
		is_crit = true
	elif _is_talent_ready(attacker, "crit"):
		var lv_crit = _get_talent_level(attacker, "crit")
		var cdata = TalentManager.get_talent_data("crit")
		var base_mult : float = 1.5
		if cdata:
			base_mult = float(cdata.effect_params.get("damage_multiplier", 1.5))
		crit_mult = base_mult + (lv_crit - 1) * 0.25 \
			+ attacker.buff_crit_damage_bonus \
			+ _total_affix(attacker, "crit_damage") \
			+ attacker.static_crit_damage_bonus
		is_crit = true
		crit_talent_triggered = true
		_reset_talent(attacker, "crit")
	elif _get_first_attack_crit_remaining(attacker) > 0:
		# ★ 对齐正式战场：遗物"首攻必暴击"（CombatManager 第 503 行）
		# crit_mult 开头已含 buff_crit_damage_bonus，与局内该分支口径一致，不重复叠加
		is_crit = true
		_first_crit_this_hit = true
		_consume_first_attack_crit(attacker)
	elif _roll_crit(attacker):
		is_crit = true
	# ★ v6.10：余烬流派——魂火耗尽后本次必暴，并追加暴伤
	var ember_charged: bool = _player_ember_charged if is_player_attacker else _enemy_ember_charged
	if ember_charged:
		var ember_lv: int = BuildManager.get_effective_school_level(attacker, "余烬")
		if ember_lv > 0:
			is_crit = true
			crit_mult += BuildManager.get_ember_crit_bonus(ember_lv)
			if is_player_attacker:
				_player_ember_charged = false
			else:
				_enemy_ember_charged = false

	if is_crit:
		crit_mult = minf(crit_mult, CRIT_DAMAGE_CAP)
		# 抗暴词条（对齐正式战场）
		var anti_crit : float = clampf(_total_affix(defender, "anti_crit"), 0.0, 0.8)
		var effective_crit_mult : float = 1.0 + (crit_mult - 1.0) * (1.0 - anti_crit)
		damage = int(damage * effective_crit_mult)
		# ★ v5.10：暴击天赋触发破甲 debuff（对齐正式战场，写入防守方下次受击生效）
		if crit_talent_triggered:
			var cdata2 = TalentManager.get_talent_data("crit")
			var shred_amt : float = 0.20
			var shred_cap : float = 0.50
			if cdata2:
				shred_amt = float(cdata2.effect_params.get("defense_shred", 0.20))
				shred_cap = float(cdata2.effect_params.get("shred_cap", 0.50))
			defender.buff_defense_shred = minf(defender.buff_defense_shred + shred_amt, shred_cap)
		if is_player_attacker:
			_crit_count += 1

	# ---- 盾反 ----
	if _is_talent_ready(defender, "parry"):
		var lv = _get_talent_level(defender, "parry")
		var reflect = 0.5 + (lv - 1) * 0.15
		var parry_dmg = int(damage * reflect)
		if is_player_attacker:
			_player_hp = max(0, _player_hp - parry_dmg)
			player_hp_bar.value = _player_hp
			_total_damage_taken += parry_dmg
		else:
			_enemy_hp = max(0, _enemy_hp - parry_dmg)
			enemy_hp_bar.value = _enemy_hp
		_reset_talent(defender, "parry")

	# ---- 反击强化 ----
	if _is_talent_ready(defender, "counter_boost"):
		var lv = _get_talent_level(defender, "counter_boost")
		var reflect_pct = COUNTER_BASE_PERCENT + (lv - 1) * COUNTER_PER_LEVEL
		var reflect_dmg = maxi(1, int(damage * reflect_pct))
		if is_player_attacker:
			_player_hp = maxi(0, _player_hp - reflect_dmg)
			player_hp_bar.value = _player_hp
			_total_damage_taken += reflect_dmg
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
		_total_damage_dealt += damage
		_play_hit_effect(enemy_sprite, _enemy_material, Vector2(-1, 0))
		_shake_panel(Vector2(-1, 0))
	else:
		_player_hp = max(0, _player_hp - damage)
		player_hp_bar.value = _player_hp
		_total_damage_taken += damage
		_play_hit_effect(player_sprite, _player_material, Vector2(1, 0))
		_shake_panel(Vector2(1, 0))

	SoundManager.play_hit_sound()

	# ★ v6.10：守护流派机制——受击反弹（对齐 BuildManager 有效 Lv 曲线）
	var guard_lv: int = BuildManager.get_effective_school_level(defender, "守护")
	if guard_lv > 0 and damage > 0:
		var reflect: int = maxi(1, int(damage * BuildManager.get_guard_reflect_ratio(guard_lv)))
		if is_player_attacker:
			_player_hp = maxi(0, _player_hp - reflect)
			player_hp_bar.value = _player_hp
			_total_damage_taken += reflect
		else:
			_enemy_hp = maxi(0, _enemy_hp - reflect)
			enemy_hp_bar.value = _enemy_hp
			_total_damage_dealt += reflect
		log_label.text += "  [守护反弹 Lv%d +%d]" % [guard_lv, reflect]
		# ★ v6.35（A-B2）守护 Lv2 质变：反弹同时为自身回血（对齐主线）
		if BuildManager.has_breakthrough(defender, "守护", "guard_lifesteal"):
			var ls := maxi(1, int(reflect * 0.5))
			if is_player_attacker:
				_enemy_hp = mini(_enemy_hp + ls, maxi(1, defender.max_hp))
				enemy_hp_bar.value = _enemy_hp
			else:
				_player_hp = mini(_player_hp + ls, maxi(1, defender.max_hp))
				player_hp_bar.value = _player_hp
			log_label.text += "  [守护回血 +%d]" % ls

	var atk_name = attacker.display_name if attacker.display_name != "" else attacker.unit_name
	var def_name = defender.display_name if defender.display_name != "" else defender.unit_name
	var crit_str : String = ""
	if _first_crit_this_hit:
		crit_str = "（首攻暴击！）"
	elif is_crit:
		crit_str = "（暴击！）"
	log_label.text = "%s 攻击 %s%s，造成 %d 伤害" % [atk_name, def_name, crit_str, damage]

	# ---- 吸血（v5.10 对齐正式战场：天赋 + buff 走 CD，词条独立每次生效）----
	var ls_pct : float = 0.0
	if _is_talent_ready(attacker, "lifesteal"):
		var lv_ls = _get_talent_level(attacker, "lifesteal")
		ls_pct = 0.2 + (lv_ls - 1) * 0.1
		ls_pct += attacker.buff_lifesteal_percent
		_reset_talent(attacker, "lifesteal")
	# 词条吸血不依赖天赋 CD，对齐 CombatManager._apply_damage_with_effects
	ls_pct += _total_affix(attacker, "lifesteal")
	if ls_pct > 0.0:
		var heal = int(damage * ls_pct)
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

	# ---- 火焰伤害词条（v5.10 对齐正式战场被动 flame_damage）----
	var flame_bonus : int = 0
	for slot in attacker.armor_slots:
		if slot: flame_bonus += slot.get_affix_value("flame_damage")
	if flame_bonus > 0:
		if is_player_attacker:
			_enemy_hp = maxi(0, _enemy_hp - flame_bonus)
			enemy_hp_bar.value = _enemy_hp
			_total_damage_dealt += flame_bonus
		else:
			_player_hp = maxi(0, _player_hp - flame_bonus)
			player_hp_bar.value = _player_hp
			_total_damage_taken += flame_bonus
		log_label.text += "  [灼烧 +%d]" % flame_bonus

	# ★ v6.10：烈焰流派机制——按本次伤害追加灼烧（对齐 BuildManager 有效 Lv 曲线）
	var flame_lv: int = BuildManager.get_effective_school_level(attacker, "烈焰")
	if flame_lv > 0:
		var burn: int = maxi(1, int(damage * BuildManager.get_flame_burn_ratio(flame_lv)))
		if is_player_attacker:
			_enemy_hp = maxi(0, _enemy_hp - burn)
			enemy_hp_bar.value = _enemy_hp
			_total_damage_dealt += burn
		else:
			_player_hp = maxi(0, _player_hp - burn)
			player_hp_bar.value = _player_hp
			_total_damage_taken += burn
		log_label.text += "  [烈焰灼烧 Lv%d +%d]" % [flame_lv, burn]

	_refresh_hp_labels()
	await get_tree().create_timer(0.6, true, false, true).timeout

	# ---- 出血 ----
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
				_total_damage_dealt += bleed_dmg
				log_label.text += "  [出血爆发 -%d]" % bleed_dmg
		else:
			_player_bleed_stacks += 1
			if _player_bleed_stacks >= BLEED_MAX_STACKS:
				var bleed_dmg = maxi(1, int(defender.max_hp * pct))
				_player_hp = maxi(0, _player_hp - bleed_dmg)
				player_hp_bar.value = _player_hp
				_player_bleed_stacks = 0
				_total_damage_taken += bleed_dmg
				log_label.text += "  [出血爆发 -%d]" % bleed_dmg
		_reset_talent(attacker, "bleed")
		_refresh_hp_labels()

	# ---- 法杖自愈 ----
	# ★ v5.1：武器数值已内联单位，直接读 weapon_category
	if attacker.weapon_category == "staff":
		var self_heal_pct = STAFF_SELF_HEAL_PERCENT
		if _is_talent_ready(attacker, "heal_boost"):
			var lv_hb = _get_talent_level(attacker, "heal_boost")
			self_heal_pct *= (HEAL_BOOST_BASE + (lv_hb - 1) * HEAL_BOOST_PER_LEVEL)
			_reset_talent(attacker, "heal_boost")
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

	# ---- 法术连击 ----
	if _is_talent_ready(attacker, "spell_chain"):
		# ★ v5.10 修复：原 weapon_data 为武器系统删除后的残留未定义变量，导致法术连击永不触发；
		# 对齐正式战场 get_weapon_type()=="spellbook"，竞技场用内联 weapon_category
		if attacker.weapon_category == "spellbook":
			var lv_sc = _get_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_BASE + (lv_sc - 1) * SPELL_CHAIN_PER_LEVEL
			var extra = maxi(1, int(damage * mult))
			if is_player_attacker:
				_enemy_hp = maxi(0, _enemy_hp - extra)
				enemy_hp_bar.value = _enemy_hp
				_total_damage_dealt += extra
			else:
				_player_hp = maxi(0, _player_hp - extra)
				player_hp_bar.value = _player_hp
				_total_damage_taken += extra
			_reset_talent(attacker, "spell_chain")
			log_label.text += "  [法术连击 +%d]" % extra
			_refresh_hp_labels()
			await get_tree().create_timer(0.4, true, false, true).timeout

	# ---- 复活 ----
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
			_total_damage_dealt += extra
		else:
			_player_hp = max(0, _player_hp - extra)
			player_hp_bar.value = _player_hp
			_total_damage_taken += extra
		log_label.text += "  [二次攻击 +%d]" % extra
		_refresh_hp_labels()
		await get_tree().create_timer(0.4, true, false, true).timeout

	# ★ v6.10：简化魂火——命中 +1，魂火归零则给余烬必暴标记
	_arena_on_hit(attacker, is_player_attacker)


func _arena_on_hit(_attacker: UnitData, is_player: bool):
	# 命中 +1 魂火；魂火归零时给余烬必暴标记
	# ★ v6.69：取消 build 能量累计，觉醒改由魂火支付（魂火同时是技能/觉醒唯一资源）
	if is_player:
		_player_soul = mini(_player_soul + 1, ARENA_SOUL_CAP)
		if _player_soul <= 0 and BuildManager.get_effective_school_level(_player, "余烬") > 0:
			_player_ember_charged = true
	else:
		_enemy_soul = mini(_enemy_soul + 1, ARENA_SOUL_CAP)
		if _enemy_soul <= 0 and BuildManager.get_effective_school_level(_enemy, "余烬") > 0:
			_enemy_ember_charged = true


## ★ v6.10：轮回流派——击杀时额外回魂火
func _arena_on_kill(killer: UnitData, victim: UnitData, is_player: bool):
	# ★ v6.58：击杀得经验——按被击杀者强度(exp)给击杀者，与主线一致
	if is_player and victim != null:
		BuildManager.grant_kill_exp(killer, victim.kill_exp)
	# ★ v6.69：觉醒不再靠击杀攒能量——统一由魂火支付。
	var lv: int = BuildManager.get_effective_school_level(killer, "轮回")
	if lv <= 0:
		return
	var gain: int = BuildManager.get_cycle_soul_gain(lv)
	if is_player:
		_player_soul = mini(_player_soul + gain, ARENA_SOUL_CAP)
	else:
		_enemy_soul = mini(_enemy_soul + gain, ARENA_SOUL_CAP)
	log_label.text += "  [轮回回魂 +%d]" % gain


## ★ v6.10：献祭流派——回合开始扣血，写入本回合攻击加成
func _apply_sacrifice(unit: UnitData, is_player: bool):
	var lv: int = BuildManager.get_effective_school_level(unit, "献祭")
	if lv <= 0:
		if is_player: _player_sacrifice_bonus = 0.0
		else: _enemy_sacrifice_bonus = 0.0
		return
	var cost_ratio: float = BuildManager.get_sacrifice_hp_cost_ratio(lv)
	var hp: int = _player_hp if is_player else _enemy_hp
	var max_hp: int = maxi(1, unit.max_hp)
	var cost: int = maxi(1, int(max_hp * cost_ratio))
	cost = mini(cost, maxi(0, hp - 1))   # 保底留 1 HP
	if is_player:
		_player_hp = maxi(1, hp - cost)
		player_hp_bar.value = _player_hp
		_player_sacrifice_bonus = BuildManager.get_sacrifice_attack_bonus(lv)
		# ★ v6.35（A-B2）献祭 Lv4 质变：残血(<30%)攻击加成翻倍
		if BuildManager.has_breakthrough(unit, "献祭", "sacrifice_rage") \
				and float(_player_hp) / float(max_hp) < 0.30:
			_player_sacrifice_bonus *= 2.0
			log_label.text += "  [献祭·焚尽 残血攻翻倍]"
	else:
		_enemy_hp = maxi(1, hp - cost)
		enemy_hp_bar.value = _enemy_hp
		_enemy_sacrifice_bonus = BuildManager.get_sacrifice_attack_bonus(lv)
		if BuildManager.has_breakthrough(unit, "献祭", "sacrifice_rage") \
				and float(_enemy_hp) / float(max_hp) < 0.30:
			_enemy_sacrifice_bonus *= 2.0
			log_label.text += "  [献祭·焚尽 残血攻翻倍]"
	_refresh_hp_labels()


## ★ v6.69：觉醒技自动释放（1v1 简化）——魂火够付 + 冷却归零时触发，效果按最高流派。
func _try_release_build_burst(unit: UnitData, is_player: bool) -> void:
	var cd: int = _player_awakening_cd if is_player else _enemy_awakening_cd
	var soul: int = _player_soul if is_player else _enemy_soul
	if cd > 0 or soul < _arena_awakening_cost:
		return
	var school := _dominant_school(unit)
	if school == "":
		return
	# 扣魂火 + 进入冷却（按回合递减，见主循环）
	if is_player:
		_player_soul -= _arena_awakening_cost
		_player_awakening_cd = _arena_awakening_cd_rounds
	else:
		_enemy_soul -= _arena_awakening_cost
		_enemy_awakening_cd = _arena_awakening_cd_rounds
	var my_hp: int = _player_hp if is_player else _enemy_hp
	var foe_hp: int = _enemy_hp if is_player else _player_hp
	var atk: int = maxi(5, int(unit.attack * 0.6))
	match school:
		"烈焰", "灰烬", "余烬":
			foe_hp = maxi(0, foe_hp - atk)
		"守护", "轮回":
			my_hp = mini(my_hp + maxi(5, int(maxi(1, unit.max_hp) * 0.20)), maxi(1, unit.max_hp))
		"献祭":
			if is_player: _player_sacrifice_bonus += 0.30
			else: _enemy_sacrifice_bonus += 0.30
	if is_player:
		_player_hp = my_hp
		_enemy_hp = foe_hp
		enemy_hp_bar.value = _enemy_hp
	else:
		_enemy_hp = my_hp
		_player_hp = foe_hp
		player_hp_bar.value = _player_hp
	_refresh_hp_labels()
	_shake_panel(Vector2.ZERO, 8.0, 0.4)
	log_label.text += "  ★ Build 觉醒技【%s】！" % school


## 取单位有效 Lv 最高的流派
func _dominant_school(unit: UnitData) -> String:
	var best: String = ""
	var best_lv: int = 0
	for s in BuildManager.SCHOOL_ORDER:
		var lv := BuildManager.get_effective_school_level(unit, s)
		if lv > best_lv:
			best_lv = lv
			best = s
	return best


func _calc_damage(attacker: UnitData, defender: UnitData) -> int:
	if attacker == null or defender == null:
		return 0
	# ★ v5.1：武器数值已内联单位，无武器直接保底伤害
	if attacker.weapon_name == "":
		return 1

	var is_magic : bool = (attacker.attack_style == "magic") \
		or (attacker.weapon_category == "staff") \
		or attacker.magic_attack.get("ignore_defense", false)

	# ---- 1. 攻击力 ----
	var quality_mult : float = QUALITY_MULT.get(attacker.weapon_quality, 1.0)
	var base_attack : float = attacker.attack * quality_mult

	var atk_bonus : float = 0.0
	for attr in attacker.modifier:
		atk_bonus += attacker.get_effective_attr(attr) * attacker.modifier[attr]

	var total_attack : float = base_attack + atk_bonus + attacker.buff_attack_flat
	if is_magic:
		total_attack += attacker.buff_magic_attack_flat
	total_attack *= (1.0 + attacker.buff_attack_percent)
	# ★ v6.10：献祭流派本回合攻击加成
	var sac_bonus: float = _player_sacrifice_bonus if attacker == _player else _enemy_sacrifice_bonus
	total_attack *= (1.0 + sac_bonus)
	# ★ v5.10 对齐正式战场：遗物力量缩放伤害
	if attacker.relic_strength_scale_damage > 0.0:
		var str_val : int = attacker.get_effective_attr("strength")
		total_attack *= (1.0 + str_val * attacker.relic_strength_scale_damage)

	# ---- 2. 减伤率 ----
	var base_reduction : float = defender.magic_reduction if is_magic else defender.physical_reduction

	var armor_reduction : float = 0.0
	for slot in defender.armor_slots:
		if slot == null:
			continue
		var idata = ItemManager.get_item_data(slot.item_id)
		if idata == null:
			continue
		var aq : float = QUALITY_MULT.get(idata.quality, 1.0)
		armor_reduction += (idata.magic_reduction if is_magic else idata.physical_reduction) * aq

	var affix_reduction : float = 0.0
	for slot in defender.armor_slots:
		if slot:
			affix_reduction += slot.get_affix_value("defense_flat") * 0.01

	var buff_reduction : float = (defender.buff_magic_reduction if is_magic else defender.buff_physical_reduction) \
		+ defender.buff_damage_reduction
	# ★ v5.10 对齐正式战场：破甲 debuff 只在物理减伤侧生效（UnitData 现已带 buff_defense_shred）
	var shred : float = 0.0 if is_magic else defender.buff_defense_shred
	var total_reduction : float = clampf(
		base_reduction + armor_reduction + affix_reduction + buff_reduction - shred,
		0.0, REDUCTION_CAP)

	# ---- 3. 穿透 ----
	var weapon_pen : float = attacker.magic_penetration if is_magic else attacker.physical_penetration
	var affix_pen : float = 0.0
	for slot in attacker.armor_slots:
		if slot:
			affix_pen += slot.get_affix_value_float("magic_penetration" if is_magic else "physical_penetration")
	# ★ v5.10 对齐正式战场：静态穿透（竞技场入场已清零，商店/成长可写入）
	var static_pen : float = attacker.static_magic_penetration if is_magic else attacker.static_physical_penetration
	var total_pen : float = weapon_pen + affix_pen + static_pen

	# ---- 4. 伤害结算 ----
	# ★ v5.11 对齐正式战场：无视防御的攻击（magic_attack.ignore_defense）跳过减伤与穿透，
	# effective_reduction 直接置 0（对齐 CombatManager 第 214-219 行）
	var ignore_def : bool = attacker.magic_attack.get("ignore_defense", false)
	var effective_reduction : float = 0.0 if ignore_def else clampf(total_reduction - total_pen, 0.0, 1.0)
	var damage_raw : float = total_attack * (1.0 - effective_reduction)
	var floor_raw : float = total_attack * MIN_DAMAGE_FLOOR
	var damage : int = max(1, int(max(damage_raw, floor_raw)))

	# ★ v5.10 对齐正式战场：攻击方 attack_flat 词条（此前竞技场漏算）
	var atk_affix_bonus : int = 0
	for slot in attacker.armor_slots:
		if slot: atk_affix_bonus += slot.get_affix_value("attack_flat")
	damage += atk_affix_bonus

	return max(1, damage)


## v5.10：竞技场用 UnitData，无 Unit.get_total_affix_value_float，这里自行聚合防具槽词条
## （ItemInstance.get_affix_value_float 已 /100，与正式战场 get_total_affix_value_float 同量纲）
func _total_affix(data: UnitData, affix_type: String) -> float:
	if data == null: return 0.0
	var total : float = 0.0
	for slot in data.armor_slots:
		if slot:
			total += slot.get_affix_value_float(affix_type)
	return total


func _roll_crit(attacker: UnitData) -> bool:
	var chance : float = CRIT_BASE_CHANCE
	chance += attacker.get_effective_attr("dexterity") * CRIT_PER_DEXTERITY
	# ★ v5.1：品质从内联字段读
	if attacker.weapon_name != "":
		chance += CRIT_CHANCE_BY_QUALITY.get(attacker.weapon_quality, 0.0)
	# ★ v5.10 对齐正式战场：暴击率词条
	chance += _total_affix(attacker, "crit_chance")
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


func _get_talent_inst(data: UnitData, talent_id: String) -> TalentInstance:
	if not data: return null
	for inst in data.talent_slots:
		if inst and inst.talent_id == talent_id and inst.is_active:
			return inst
	if data.advanced_talent_inst and data.advanced_talent_inst.talent_id == talent_id:
		return data.advanced_talent_inst
	return null


func _emit_result(continue_requested: bool):
	closed.emit({
		"winner_team": winner_team,
		"remaining_hp": _player_hp,
		"continue_requested": continue_requested,
		"total_damage_dealt": _total_damage_dealt,
		"total_damage_taken": _total_damage_taken,
		"crit_count": _crit_count
	})
	queue_free()


func _on_continue_pressed():
	_emit_result(true)


func _on_return_pressed():
	_emit_result(false)
