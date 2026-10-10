extends Node

# ============================================================
#  BossMechanicManager — Boss 魂火交互
#  Day1: 魂火窃贼（每回合吸 2 魂火）
#  Day2: 灰烬护盾（需魂火破盾）
#  Day3: 三形态（每次死降魂火上限）
# ============================================================

enum Mechanic { NONE, SOUL_DRAIN, ASH_SHIELD, THREE_FORMS }

var _current : Mechanic = Mechanic.NONE
var _ash_shield_stacks : int = 0
var _three_forms_stage : int = 0

signal boss_mechanic_triggered(name: String, description: String)


func setup_for_node(node_type: int, is_boss: bool):
	if not is_boss:
		_current = Mechanic.NONE
		return
	var day : int = GameState.current_day
	match day:
		1: _current = Mechanic.SOUL_DRAIN
		2: _current = Mechanic.ASH_SHIELD
		3: _current = Mechanic.THREE_FORMS
		_: _current = Mechanic.NONE
	_ash_shield_stacks = 0
	_three_forms_stage = 0
	print("[Boss] 机制设置：%s（day=%d）" % [_name(), day])


func _name() -> String:
	match _current:
		Mechanic.SOUL_DRAIN: return "魂火窃贼"
		Mechanic.ASH_SHIELD: return "灰烬护盾"
		Mechanic.THREE_FORMS: return "三形态"
		_: return "无"


# ============================================================
#  Day1 · 魂火窃贼
# ============================================================
func on_player_turn_start():
	if _current != Mechanic.SOUL_DRAIN: return
	if SoulFireManager.current >= 2:
		SoulFireManager.spend(2)
		SignalBus.request_hint_override.emit("★ Boss 汲取了 2 魂火", 1.5)
		boss_mechanic_triggered.emit("soul_drain", "吸取 2 魂火")
		print("[Boss] 魂火窃贼吸取 2 魂火")
	else:
		# 魂火不足 → 全队扣 10% 最大 HP
		for u in UnitManager.unit_list:
			if u.unit_stats.team_id == 0 and u.hit_points > 0:
				var dmg : int = int(u.unit_stats.max_hp * 0.1)
				u.apply_damage(dmg)
				SignalBus.request_damage_popup.emit(u.global_position, dmg, false, false, false)
		SignalBus.request_hint_override.emit("★ Boss 汲取失败，全队受伤", 1.5)
		boss_mechanic_triggered.emit("soul_drain_fail", "全队受伤")
		print("[Boss] 魂火窃贼未能吸取，全队受伤")


# ============================================================
#  Day2 · 灰烬护盾
# ============================================================
func on_enemy_turn_start():
	if _current != Mechanic.ASH_SHIELD: return
	_ash_shield_stacks = mini(_ash_shield_stacks + 1, 3)
	SignalBus.request_hint_override.emit("★ 灰烬护盾 +1（%d 层）" % _ash_shield_stacks, 1.5)
	boss_mechanic_triggered.emit("ash_shield_gain", "护盾 +1")
	print("[Boss] 灰烬护盾层数：%d" % _ash_shield_stacks)


## 攻击时调用：返回实际伤害
func modify_damage_to_boss(attacker : Unit, damage : int) -> int:
	if _current != Mechanic.ASH_SHIELD:
		return damage
	if _ash_shield_stacks <= 0:
		return damage
	if attacker == null or attacker.unit_stats.team_id != 0:
		return damage

	# 玩家消耗 1 魂火破一层盾
	if SoulFireManager.can_spend(1):
		SoulFireManager.spend(1)
		_ash_shield_stacks -= 1
		SignalBus.request_hint_override.emit("★ 破盾！剩余 %d 层" % _ash_shield_stacks, 1.0)
		boss_mechanic_triggered.emit("ash_shield_break", "破盾")
		print("[Boss] 破盾，剩余层数：%d" % _ash_shield_stacks)
		return damage
	else:
		# 无法穿透 → 伤害减半
		var reduced : int = maxi(1, int(damage * 0.5))
		print("[Boss] 护盾抵挡，伤害 %d → %d" % [damage, reduced])
		return reduced


# ============================================================
#  Day3 · 三形态
# ============================================================
func on_boss_defeated(defender : Unit) -> bool:
	if _current != Mechanic.THREE_FORMS:
		return false
	if _three_forms_stage >= 2:
		return false
	_three_forms_stage += 1

	# 复活 Boss
	defender.hit_points = int(defender.unit_stats.max_hp * 0.75)
	defender.unit_stats.strength += 3
	defender.unit_stats.dexterity += 2
	defender.update_hp_label()
	defender.update_color()

	# ★ 魂火上限 -3（通过降 1 级祭坛实现，且不能低于 0）
	var old_max : int = SoulFireManager.get_max_carried()
	var new_altar : int = SoulFireManager.altar_level
	if new_altar > 0:
		SoulFireManager.altar_level = new_altar - 1
	SoulFireManager.current = mini(SoulFireManager.current, SoulFireManager.get_max_carried())

	SignalBus.request_hint_override.emit("★ Boss 进化到第 %d 形态！魂火上限 -3" % (_three_forms_stage + 1), 2.0)
	boss_mechanic_triggered.emit("three_forms", "魂火上限降低")
	print("[Boss] 三形态 → 第 %d 形态，魂火上限 %d → %d" % [
		_three_forms_stage + 1, old_max, SoulFireManager.get_max_carried()])
	return true


# ============================================================
#  查询
# ============================================================
func get_mechanic_name() -> String:
	return _name()

func get_ash_shield_stacks() -> int:
	return _ash_shield_stacks

func get_three_forms_stage() -> int:
	return _three_forms_stage

func get_current_mechanic() -> int:
	return _current
