class_name BattleSimEngine
extends RefCounted

# ============================================================
#  BattleSimEngine — 1v1 战斗引擎
#  含：主动技能 / 反击 / 全词条 / 遗物 / 精炼 / 武器升级
# ============================================================

const QUALITY_MULT : Dictionary = {"common":1.0,"rare":1.25,"epic":1.5,"legendary":1.8}
const CRIT_QUALITY_BONUS : Dictionary = {"common":0.0,"rare":0.03,"epic":0.05,"legendary":0.08}
const STRENGTH_DEF_FACTOR : float = 0.3
const CRIT_BASE_CHANCE : float = 0.05
const CRIT_PER_DEXTERITY : float = 0.005
const CRIT_DAMAGE_MULT : float = 1.5

const DOUBLE_ATTACK_MULT : Array = [0.8, 0.9, 1.0]
const BLEED_MAX_STACKS : int = 5
const BLEED_DAMAGE_PERCENT : Array = [0.15, 0.20, 0.25]
const SPELL_CHAIN_MULT : Array = [0.8, 0.9, 1.0]
const COUNTER_BOOST_MULT : Array = [1.5, 1.75, 2.0]
const LIFESTEAL_PERCENT : Array = [0.2, 0.3, 0.4]
const COMBO_MULT_PER_HIT : Array = [0.15, 0.25, 0.35]
const BLOOD_RAGE_HEAL_PERCENT : Array = [0.15, 0.20, 0.25]
const ZEAL_PER_STACK : Array = [0.10, 0.15, 0.20]
const ZEAL_MAX_STACKS : int = 5

# ---- 状态 ----
var battle_log : Array = []
var _p : UnitData
var _e : UnitData
var _php : int
var _ehp : int
var _winner : int = -1

# ---- 词条触发标记（每回合重置） ----
var _p_used_this_turn : Dictionary = {}
var _e_used_this_turn : Dictionary = {}

# ---- 累积状态 ----
var _p_bleed_stacks : int = 0
var _e_bleed_stacks : int = 0
var _p_zeal_target : String = ""
var _p_zeal_stacks : int = 0
var _e_zeal_target : String = ""
var _e_zeal_stacks : int = 0
var _p_combo_target : String = ""
var _p_combo_count : int = 0
var _e_combo_target : String = ""
var _e_combo_count : int = 0

# ---- 遗物 ----
var _p_first_attack_crit : bool = false
var _e_first_attack_crit : bool = false
var _p_first_spell_free : bool = false
var _e_first_spell_free : bool = false
var _p_auto_revive : bool = false
var _e_auto_revive : bool = false
var _p_turn_first_hit_used : bool = false
var _e_turn_first_hit_used : bool = false

# ---- 手动触发策略 ----
var _manual_triggers : Dictionary = {"p": [], "e": []}

# ---- 配置 ----
var talent_mode : String = "auto"    # "auto" / "disabled"
var counter_enabled : bool = true    # 是否启用反击


func set_manual_triggers(p_list : Array, e_list : Array):
	_manual_triggers["p"] = p_list.duplicate()
	_manual_triggers["e"] = e_list.duplicate()


func set_talent_mode(mode : String):
	talent_mode = mode


func set_counter_enabled(enabled : bool):
	counter_enabled = enabled


# ============================================================
#  主入口
# ============================================================
func run(p : UnitData, e : UnitData) -> Array:
	battle_log.clear()
	_p = p
	_e = e
	_php = p.hit_points if p.hit_points > 0 else p.max_hp
	_ehp = e.hit_points if e.hit_points > 0 else e.max_hp
	_winner = -1

	# 遗物状态初始化
	_p_first_attack_crit = p.relic_first_attack_crit_available
	_e_first_attack_crit = e.relic_first_attack_crit_available
	_p_first_spell_free = p.relic_first_spell_free_available
	_e_first_spell_free = e.relic_first_spell_free_available
	_p_auto_revive = p.relic_auto_revive_available
	_e_auto_revive = e.relic_auto_revive_available
	_p_turn_first_hit_used = false
	_e_turn_first_hit_used = false

	# 累积状态重置
	_p_bleed_stacks = 0
	_e_bleed_stacks = 0
	_p_zeal_target = ""
	_p_zeal_stacks = 0
	_e_zeal_target = ""
	_e_zeal_stacks = 0
	_p_combo_target = ""
	_p_combo_count = 0
	_e_combo_target = ""
	_e_combo_count = 0

	_add("[b]═══ 战斗开始 ═══[/b]")
	_add("%s [color=cyan](HP %d)[/color]  VS  %s [color=red](HP %d)[/color]" % [
		_display(p), _php, _display(e), _ehp])

	_log_buffs(p, "p")
	_log_buffs(e, "e")
	_log_weapon_upgrade(p)
	_log_weapon_upgrade(e)

	var p_dex : int = p.get_effective_attr("dexterity")
	var e_dex : int = e.get_effective_attr("dexterity")
	var p_first : bool = p_dex >= e_dex
	_add("先手: %s（灵巧 %d vs %d）" % [
		_display(p) if p_first else _display(e), p_dex, e_dex])
	_add("")

	var first = p if p_first else e
	var second = e if p_first else p

	var turn : int = 0
	while _php > 0 and _ehp > 0 and turn < 50:
		turn += 1
		_p_used_this_turn.clear()
		_e_used_this_turn.clear()
		_p_turn_first_hit_used = false
		_e_turn_first_hit_used = false

		_add("[b]─── 回合 %d ───[/b]" % turn)

		_do_attack(first, second, false)
		if _php <= 0 or _ehp <= 0: break
		_do_attack(second, first, false)

	if _php <= 0 and _ehp <= 0:
		_winner = -1
		_add("[b][color=yellow]平局！[/color][/b]")
	elif _ehp <= 0:
		_winner = 0
		_add("[b][color=green]%s 胜利！[/color][/b]" % _display(p))
	else:
		_winner = 1
		_add("[b][color=red]%s 胜利！[/color][/b]" % _display(e))

	return battle_log


func get_result_text() -> String:
	if _winner == 0: return "%s 胜" % _display(_p)
	if _winner == 1: return "%s 胜" % _display(_e)
	return "平局"


# ============================================================
#  攻击（含主动技能 / 暴击 / 反击 / 词条）
# ============================================================
func _do_attack(atk : UnitData, dfd : UnitData, is_counter : bool):
	if _php <= 0 or _ehp <= 0: return
	var is_p_atk : bool = (atk == _p)

	# ---------- 主动技能 ----------
	var skill_name : String = ""
	var damage_mult : float = 1.0
	var force_crit : bool = false
	var ignore_def : bool = false
	var hp_cost_percent : float = 0.0
	var skill_id : String = ""

	if not is_counter:
		skill_id = _pick_active_skill(atk, is_p_atk)
		if skill_id != "":
			var tdata = TalentManager.get_talent_data(skill_id)
			if tdata:
				skill_name = tdata.display_name
				var ep : Dictionary = tdata.effect_params
				damage_mult = float(ep.get("damage_mult", 1.0))
				force_crit = bool(ep.get("force_crit", false))
				ignore_def = bool(ep.get("ignore_defense", false))
				hp_cost_percent = float(ep.get("hp_cost_percent", 0.0))

	# ---------- 基础伤害 ----------
	var dmg : int = _calc_damage(atk, dfd)
	if damage_mult != 1.0:
		dmg = int(dmg * damage_mult)
		_add("[color=yellow]%s 触发【%s】 伤害×%.2f[/color]" % [_display(atk), skill_name, damage_mult])

	# ---------- 词条：zeal / combo（累积型） ----------
	if talent_mode == "auto":
		# zeal：连续攻击同一目标
		var target_key : String = dfd.unit_name
		var zeal_stacks : int = _zeal_update(atk, is_p_atk, target_key)
		if zeal_stacks > 1 and _has_talent(atk, "zeal"):
			var lv_z = _get_talent_level(atk, "zeal")
			var per = ZEAL_PER_STACK[clampi(lv_z - 1, 0, ZEAL_PER_STACK.size() - 1)]
			var bonus : float = 1.0 + (zeal_stacks - 1) * per
			dmg = int(dmg * bonus)
			_add("[color=yellow]狂热 ×%.2f（第 %d 次）[/color]" % [bonus, zeal_stacks])

		# combo：连续攻击同一目标
		var combo_count : int = _combo_update(atk, is_p_atk, target_key)
		if combo_count > 1 and _has_talent(atk, "combo"):
			var lv_c = _get_talent_level(atk, "combo")
			var per_hit = COMBO_MULT_PER_HIT[clampi(lv_c - 1, 0, COMBO_MULT_PER_HIT.size() - 1)]
			var bonus : float = 1.0 + (combo_count - 1) * per_hit
			dmg = int(dmg * bonus)
			_add("[color=yellow]连击 ×%.2f（第 %d 次）[/color]" % [bonus, combo_count])

	# ---------- 暴击 ----------
	var is_crit : bool = false
	var crit_mult : float = CRIT_DAMAGE_MULT + atk.buff_crit_damage_bonus
	var first_atk_crit : bool = (_p_first_attack_crit if is_p_atk else _e_first_attack_crit)

	if force_crit:
		is_crit = true
		_add("  [color=yellow]技能强制暴击[/color]")
	elif first_atk_crit:
		is_crit = true
		if is_p_atk: _p_first_attack_crit = false
		else: _e_first_attack_crit = false
		_add("  [color=#DDA0DD][遗物] 首击必暴[/color]")
	elif talent_mode == "auto" and _try_consume_talent(atk, is_p_atk, "crit"):
		var lv_crit = _get_talent_level(atk, "crit")
		crit_mult = 2.0 + (lv_crit - 1) * 0.5 + atk.buff_crit_damage_bonus
		is_crit = true
		_add("  [color=yellow]暴击词条！倍率 %.1f[/color]" % crit_mult)
	else:
		var crit_chance : float = CRIT_BASE_CHANCE + atk.get_effective_attr("dexterity") * CRIT_PER_DEXTERITY
		var wd = _get_weapon_data(atk)
		if wd: crit_chance += CRIT_QUALITY_BONUS.get(wd.quality, 0.0)
		if randf() < crit_chance:
			is_crit = true

	if is_crit:
		dmg = int(dmg * crit_mult)

	# ---------- 主动技能：无视防御 ----------
	if ignore_def:
		var no_def_dmg : int = _calc_damage_no_defense(atk, damage_mult)
		if is_crit:
			no_def_dmg = int(no_def_dmg * crit_mult)
		dmg = max(dmg, no_def_dmg)
		_add("  [color=yellow]无视防御[/color]")

	# ---------- 遗物：力量×伤害 ----------
	if atk.relic_strength_scale_damage > 0.0:
		var str_val : int = atk.get_effective_attr("strength")
		dmg = int(dmg * (1.0 + str_val * atk.relic_strength_scale_damage))

	# ---------- 消耗 HP（龙息） ----------
	if hp_cost_percent > 0.0:
		var hp_cost : int = int(atk.max_hp * hp_cost_percent)
		if is_p_atk: _php = max(1, _php - hp_cost)
		else: _ehp = max(1, _ehp - hp_cost)
		_add("  [color=red]消耗 %d HP[/color]" % hp_cost)

	# ---------- 防守方：parry / block ----------
	if talent_mode == "auto" and _try_consume_talent(dfd, not is_p_atk, "parry"):
		var lv_p = _get_talent_level(dfd, "parry")
		var reflect_mult = 0.5 + (lv_p - 1) * 0.15
		var reflect : int = int(dmg * reflect_mult)
		if is_p_atk: _php = max(0, _php - reflect)
		else: _ehp = max(0, _ehp - reflect)
		_add("  [color=cyan]%s 盾反！反弹 %d[/color]" % [_display(dfd), reflect])

	if talent_mode == "auto" and _try_consume_talent(dfd, not is_p_atk, "block"):
		var lv_b = _get_talent_level(dfd, "block")
		var reduction = 0.5 + (lv_b - 1) * 0.1
		dmg = int(dmg * (1.0 - reduction))
		_add("  [color=cyan]%s 格挡！减伤 %d%%[/color]" % [_display(dfd), int(reduction * 100)])

	# ---------- 遗物：低血减伤 ----------
	if dfd.relic_low_hp_damage_reduce > 0.0:
		var dfd_hp : int = _ehp if is_p_atk else _php
		var dfd_max : int = _e.max_hp if is_p_atk else _p.max_hp
		if float(dfd_hp) / float(dfd_max) < 0.3:
			dmg = max(1, int(dmg * (1.0 - dfd.relic_low_hp_damage_reduce)))
			_add("  [color=#DDA0DD][遗物] 低血减伤 %.0f%%[/color]" % (dfd.relic_low_hp_damage_reduce * 100))

	# ---------- 精炼：减伤 ----------
	if dfd.buff_damage_reduction > 0.0:
		dmg = max(1, int(dmg * (1.0 - dfd.buff_damage_reduction)))
		_add("  [color=#87CEEB][精炼] 减伤 %.0f%%[/color]" % (dfd.buff_damage_reduction * 100))

	# ---------- 应用伤害 ----------
	if is_p_atk: _ehp = max(0, _ehp - dmg)
	else: _php = max(0, _php - dmg)

	var crit_str : String = " [color=yellow](暴击!)[/color]" if is_crit else ""
	var prefix : String = "[color=#FF8080]反击[/color] " if is_counter else ""
	_add("%s%s → %s：%d 伤害%s" % [prefix, _display(atk), _display(dfd), dmg, crit_str])
	_add("  [color=cyan]%s HP %d[/color] | [color=red]%s HP %d[/color]" % [
		_display(_p), _php, _display(_e), _ehp])

	# ---------- 消耗主动技能 ----------
	if skill_id != "":
		_add("  [color=yellow]消耗主动技能 %s[/color]" % skill_name)

	# ---------- 遗物：回合首伤回复 ----------
	var is_p_def : bool = not is_p_atk
	var used_flag : bool = _p_turn_first_hit_used if is_p_def else _e_turn_first_hit_used
	if dfd.relic_turn_first_hit_regen > 0.0 and not used_flag:
		var regen : int = int(dmg * dfd.relic_turn_first_hit_regen)
		if is_p_def: _php = mini(_php + regen, _p.max_hp); _p_turn_first_hit_used = true
		else: _ehp = mini(_ehp + regen, _e.max_hp); _e_turn_first_hit_used = true
		_add("  [color=#DDA0DD][遗物] 回合首伤回复 %d[/color]" % regen)

	# ---------- 词条：bleed ----------
	if talent_mode == "auto" and _try_consume_talent(atk, is_p_atk, "bleed"):
		_apply_bleed(atk, dfd, is_p_atk)

	# ---------- 词条：lifesteal ----------
	if talent_mode == "auto" and _try_consume_talent(atk, is_p_atk, "lifesteal"):
		var lv_ls = _get_talent_level(atk, "lifesteal")
		var pct = LIFESTEAL_PERCENT[clampi(lv_ls - 1, 0, LIFESTEAL_PERCENT.size() - 1)]
		var heal : int = int(dmg * pct)
		if is_p_atk: _php = mini(_php + heal, _p.max_hp)
		else: _ehp = mini(_ehp + heal, _e.max_hp)
		_add("  [color=green]吸血 +%d[/color]" % heal)

	# ---------- 词条：double_attack ----------
	if talent_mode == "auto" and _try_consume_talent(atk, is_p_atk, "double_attack") \
			and _php > 0 and _ehp > 0:
		var lv_da = _get_talent_level(atk, "double_attack")
		var mult = DOUBLE_ATTACK_MULT[clampi(lv_da - 1, 0, DOUBLE_ATTACK_MULT.size() - 1)]
		var extra : int = int(dmg * mult)
		if is_p_atk: _ehp = max(0, _ehp - extra)
		else: _php = max(0, _php - extra)
		_add("  [color=yellow]二次攻击 +%d[/color]" % extra)
		_add("  [color=cyan]%s HP %d[/color] | [color=red]%s HP %d[/color]" % [
			_display(_p), _php, _display(_e), _ehp])

	# ---------- 词条：spell_chain（法系武器） ----------
	if talent_mode == "auto" and _try_consume_talent(atk, is_p_atk, "spell_chain") \
			and _php > 0 and _ehp > 0:
		var wt : String = atk.get_weapon_type()
		if wt == "spellbook" or wt == "staff":
			var lv_sc = _get_talent_level(atk, "spell_chain")
			var mult_sc = SPELL_CHAIN_MULT[clampi(lv_sc - 1, 0, SPELL_CHAIN_MULT.size() - 1)]
			var extra_sc : int = int(dmg * mult_sc)
			if is_p_atk: _ehp = max(0, _ehp - extra_sc)
			else: _php = max(0, _php - extra_sc)
			_add("  [color=yellow]法术连击 +%d[/color]" % extra_sc)

	# ---------- 击杀检查 ----------
	if _ehp <= 0 or _php <= 0:
		# 遗物：auto_revive
		if _ehp <= 0 and _e_auto_revive:
			_ehp = _e.max_hp
			_e_auto_revive = false
			_add("  [color=#DDA0DD][遗物] %s 凤凰之羽复活[/color]" % _display(_e))
		elif _php <= 0 and _p_auto_revive:
			_php = _p.max_hp
			_p_auto_revive = false
			_add("  [color=#DDA0DD][遗物] %s 凤凰之羽复活[/color]" % _display(_p))
		else:
			# 词条：revive
			if _ehp <= 0 and talent_mode == "auto" and _try_consume_talent(_e, false, "revive"):
				_ehp = _e.max_hp
				_add("  [color=yellow]%s 复活词条！满血复活[/color]" % _display(_e))
			elif _php <= 0 and talent_mode == "auto" and _try_consume_talent(_p, true, "revive"):
				_php = _p.max_hp
				_add("  [color=yellow]%s 复活词条！满血复活[/color]" % _display(_p))
			else:
				# 真正击杀：触发击杀词条
				if _ehp <= 0:
					_add("[color=green]%s 阵亡！[/color]" % _display(_e))
					_on_kill(atk, is_p_atk)
				else:
					_add("[color=green]%s 阵亡！[/color]" % _display(_p))
					_on_kill(dfd, not is_p_atk)
				return

	# ---------- 反击 ----------
	if counter_enabled and not is_counter and _php > 0 and _ehp > 0:
		if _can_counter(dfd):
			_add("  [color=#FF8080]%s 反击！[/color]" % _display(dfd))
			_do_attack(dfd, atk, true)


# ============================================================
#  反击判定
# ============================================================
func _can_counter(defender : UnitData) -> bool:
	# 只有 counter_boost 词条可触发（跟原游戏一致）
	if not _has_talent(defender, "counter_boost"):
		return false
	var wt : String = defender.get_weapon_type()
	if wt == "" or wt == "staff":
		return false
	return true


# ============================================================
#  词条就绪检查 / 消耗
# ============================================================
## 每回合每词条只触发一次
func _try_consume_talent(unit : UnitData, is_p : bool, tid : String) -> bool:
	if talent_mode != "auto": return false
	if not _has_talent(unit, tid): return false
	var used : Dictionary = _p_used_this_turn if is_p else _e_used_this_turn
	if used.get(tid, false): return false
	used[tid] = true
	return true


func _has_talent(unit : UnitData, tid : String) -> bool:
	for inst in unit.talent_slots:
		if inst and inst.is_active and inst.talent_id == tid:
			return true
	if unit.advanced_talent_inst and unit.advanced_talent_inst.is_active \
			and unit.advanced_talent_inst.talent_id == tid:
		return true
	return false


func _get_talent_level(unit : UnitData, tid : String) -> int:
	return TalentManager.get_talent_level(unit.unit_name, tid)


# ============================================================
#  zeal / combo 累积
# ============================================================
func _zeal_update(_atk : UnitData, is_p : bool, target_key : String) -> int:
	if is_p:
		if _p_zeal_target == target_key:
			_p_zeal_stacks = mini(_p_zeal_stacks + 1, ZEAL_MAX_STACKS)
		else:
			_p_zeal_target = target_key
			_p_zeal_stacks = 1
		return _p_zeal_stacks
	else:
		if _e_zeal_target == target_key:
			_e_zeal_stacks = mini(_e_zeal_stacks + 1, ZEAL_MAX_STACKS)
		else:
			_e_zeal_target = target_key
			_e_zeal_stacks = 1
		return _e_zeal_stacks


func _combo_update(_atk : UnitData, is_p : bool, target_key : String) -> int:
	if is_p:
		if _p_combo_target == target_key:
			_p_combo_count += 1
		else:
			_p_combo_target = target_key
			_p_combo_count = 1
		return _p_combo_count
	else:
		if _e_combo_target == target_key:
			_e_combo_count += 1
		else:
			_e_combo_target = target_key
			_e_combo_count = 1
		return _e_combo_count


# ============================================================
#  bleed
# ============================================================
func _apply_bleed(atk : UnitData, dfd : UnitData, is_p_atk : bool):
	var target_is_enemy : bool = (dfd != atk)
	if not target_is_enemy: return

	if is_p_atk:
		_e_bleed_stacks += 1
		_add("  [color=orange]%s 出血 %d/%d[/color]" % [_display(dfd), _e_bleed_stacks, BLEED_MAX_STACKS])
		if _e_bleed_stacks >= BLEED_MAX_STACKS:
			var lv = _get_talent_level(atk, "bleed")
			var pct = BLEED_DAMAGE_PERCENT[clampi(lv - 1, 0, BLEED_DAMAGE_PERCENT.size() - 1)]
			var bdmg : int = int(_e.max_hp * pct)
			_ehp = max(0, _ehp - bdmg)
			_e_bleed_stacks = 0
			_add("  [color=orange]出血爆发 -%d[/color]" % bdmg)
			_add("  [color=cyan]%s HP %d[/color] | [color=red]%s HP %d[/color]" % [
				_display(_p), _php, _display(_e), _ehp])
	else:
		_p_bleed_stacks += 1
		_add("  [color=orange]%s 出血 %d/%d[/color]" % [_display(dfd), _p_bleed_stacks, BLEED_MAX_STACKS])
		if _p_bleed_stacks >= BLEED_MAX_STACKS:
			var lv = _get_talent_level(atk, "bleed")
			var pct = BLEED_DAMAGE_PERCENT[clampi(lv - 1, 0, BLEED_DAMAGE_PERCENT.size() - 1)]
			var bdmg : int = int(_p.max_hp * pct)
			_php = max(0, _php - bdmg)
			_p_bleed_stacks = 0
			_add("  [color=orange]出血爆发 -%d[/color]" % bdmg)
			_add("  [color=cyan]%s HP %d[/color] | [color=red]%s HP %d[/color]" % [
				_display(_p), _php, _display(_e), _ehp])


# ============================================================
#  击杀连锁（blood_rage / cleave）
# ============================================================
func _on_kill(killer : UnitData, killer_is_p : bool):
	if talent_mode == "auto" and _has_talent(killer, "blood_rage"):
		var lv = _get_talent_level(killer, "blood_rage")
		var pct = BLOOD_RAGE_HEAL_PERCENT[clampi(lv - 1, 0, BLOOD_RAGE_HEAL_PERCENT.size() - 1)]
		var heal = int(killer.max_hp * pct)
		if killer_is_p: _php = mini(_php + heal, _p.max_hp)
		else: _ehp = mini(_ehp + heal, _e.max_hp)
		_add("  [color=green]血怒 +%d[/color]" % heal)


# ============================================================
#  伤害计算
# ============================================================
func _calc_damage(atk : UnitData, dfd : UnitData) -> int:
	var wd = _get_weapon_data(atk)
	if wd == null: return 1
	var upgrade_lv : int = atk.weapon_slot.upgrade_level if atk.weapon_slot else 0

	var eff_attack : int = WeaponUpgradeHelper.get_effective_base_attack(wd, upgrade_lv)
	var eff_mod : Dictionary = WeaponUpgradeHelper.get_effective_modifier(wd, upgrade_lv)
	var qm : float = QUALITY_MULT.get(wd.quality, 1.0)
	var base : float = eff_attack * qm
	var bonus : float = 0.0
	for attr in eff_mod:
		bonus += atk.get_effective_attr(attr) * eff_mod[attr]
	var total : float = base + bonus + atk.buff_attack_flat
	total *= (1.0 + atk.buff_attack_percent)

	var armor_def : float = 0.0
	for slot in dfd.armor_slots:
		if slot:
			var d = ItemManager.get_item_data(slot.item_id)
			if d:
				var armor_up_lv : int = 0
				var base_def : int = WeaponUpgradeHelper.get_effective_defense(d, armor_up_lv)
				armor_def += base_def * QUALITY_MULT.get(d.quality, 1.0)
	var def_val : float = dfd.get_effective_attr("strength") * STRENGTH_DEF_FACTOR + armor_def
	def_val += dfd.buff_defense_flat
	return max(1, int(total - def_val))


func _calc_damage_no_defense(atk : UnitData, damage_mult : float) -> int:
	var wd = _get_weapon_data(atk)
	if wd == null: return 1
	var upgrade_lv : int = atk.weapon_slot.upgrade_level if atk.weapon_slot else 0
	var eff_attack : int = WeaponUpgradeHelper.get_effective_base_attack(wd, upgrade_lv)
	var eff_mod : Dictionary = WeaponUpgradeHelper.get_effective_modifier(wd, upgrade_lv)
	var qm : float = QUALITY_MULT.get(wd.quality, 1.0)
	var base : float = eff_attack * qm
	var bonus : float = 0.0
	for attr in eff_mod:
		bonus += atk.get_effective_attr(attr) * eff_mod[attr]
	var total : float = (base + bonus + atk.buff_attack_flat) * (1.0 + atk.buff_attack_percent)
	return int(total * damage_mult)


# ============================================================
#  辅助
# ============================================================
func _pick_active_skill(atk : UnitData, is_p : bool) -> String:
	var ready : Array = _get_ready_skills(atk)
	if ready.is_empty(): return ""
	var manual : Array = _manual_triggers["p"] if is_p else _manual_triggers["e"]
	if manual.is_empty():
		# 未指定手动触发 → 默认第一个就绪技能
		return ready[0]
	for sid in ready:
		if sid in manual: return sid
	return ""


func _get_ready_skills(u : UnitData) -> Array:
	var result : Array = []
	for inst in u.talent_slots:
		if not inst or not inst.is_active: continue
		var tdata = TalentManager.get_talent_data(inst.talent_id)
		if tdata and tdata.is_active_skill and inst.is_ready:
			result.append(inst.talent_id)
	if u.advanced_talent_inst and u.advanced_talent_inst.is_active:
		var td = TalentManager.get_talent_data(u.advanced_talent_inst.talent_id)
		if td and td.is_active_skill and u.advanced_talent_inst.is_ready:
			result.append(u.advanced_talent_inst.talent_id)
	return result


func _get_weapon_data(u : UnitData) -> ItemData:
	if u.weapon_slot == null: return null
	return ItemManager.get_item_data(u.weapon_slot.item_id)


func _display(u : UnitData) -> String:
	return u.display_name if u.display_name != "" else u.unit_name


func _add(text : String):
	battle_log.append(text)


func _log_buffs(u : UnitData, _side : String):
	var parts : Array = []
	if u.relic_first_attack_crit_available: parts.append("首击必暴")
	if u.relic_low_hp_damage_reduce > 0.0: parts.append("低血减伤%.0f%%" % (u.relic_low_hp_damage_reduce*100))
	if u.relic_turn_first_hit_regen > 0.0: parts.append("回合首伤回%.0f%%" % (u.relic_turn_first_hit_regen*100))
	if u.relic_strength_scale_damage > 0.0: parts.append("力量×%.2f%%" % (u.relic_strength_scale_damage*100))
	if u.relic_auto_revive_available: parts.append("凤凰")
	if u.buff_attack_percent > 0.0: parts.append("攻%.0f%%" % (u.buff_attack_percent*100))
	if u.buff_damage_reduction > 0.0: parts.append("减伤%.0f%%" % (u.buff_damage_reduction*100))
	if parts.size() > 0:
		_add("[color=#DDA0DD]%s: %s[/color]" % [_display(u), ", ".join(parts)])


func _log_weapon_upgrade(u : UnitData):
	if u.weapon_slot == null: return
	if u.weapon_slot.upgrade_level <= 0: return
	var wd = ItemManager.get_item_data(u.weapon_slot.item_id)
	if wd == null: return
	var per_lv : int = WeaponUpgradeHelper.get_attack_per_level(wd)
	_add("[color=#FFD700]%s 武器 +%d（+%d 攻击）[/color]" % [
		_display(u), u.weapon_slot.upgrade_level,
		u.weapon_slot.upgrade_level * per_lv])
