extends Node

var _boss_states: Dictionary = {}

const TRIGGER_INITIAL := "initial"
const TRIGGER_HP_BELOW := "hp_below"
const TRIGGER_ON_DEATH := "on_death"


func setup_for_node(_is_boss: bool) -> void:
	_boss_states.clear()
	if SoulFireManager:
		SoulFireManager.reset_boss_penalty()

	for u in UnitManager.unit_list:
		if not is_instance_valid(u):
			continue
		if u.unit_stats.team_id != 1:
			continue
		if not u.unit_stats.is_boss:
			continue
		if u.unit_stats.phases.is_empty():
			continue

		_boss_states[u] = {
			"current_phase": 0,
			"triggered": {0: true},
			"current_mechanic_id": "",
			"current_mechanic_params": {},
			"ash_shield_stacks": 0
		}
		_apply_phase(u, 0)
		print("[Boss] 初始化多阶段单位：%s，总阶段 %d" % [u.unit_stats.display_name, u.unit_stats.phases.size()])


func _apply_phase(unit: Unit, phase_idx: int) -> void:
	if not _boss_states.has(unit):
		return
	var st: Dictionary = _boss_states[unit]
	var phases: Array = unit.unit_stats.phases
	if phase_idx < 0 or phase_idx >= phases.size():
		return
	var p: Dictionary = phases[phase_idx]

	var form_id: String = str(p.get("form_unit_id", ""))
	var new_stats: UnitData = null

	if form_id != "" and form_id != "self":
		new_stats = UnitDataManager.create_unit_data(form_id, true)
		if new_stats != null:
			new_stats.team_id = unit.unit_stats.team_id
			new_stats.is_boss = true

			# ★ 核心修复 1：若新形态没配阵营，继承老阵营
			if new_stats.faction == "":
				new_stats.faction = unit.unit_stats.faction

			# ★ 核心修复 2：若新形态没配名字，继承老名字
			if new_stats.display_name == "":
				new_stats.display_name = unit.unit_stats.display_name

			# ★ 核心修复 3：强制继承地图配置的 Boss 头像 (虽然现在统一由json管理，但保留此逻辑以防万一)
			if unit.unit_stats.avatar_override != "":
				new_stats.avatar_override = unit.unit_stats.avatar_override

			# 继承阶段数组，确保后续还能继续切阶段
			new_stats.phases = unit.unit_stats.phases

			# ★ 继承对话钩子，确保 stage 2/3 也能读到原始 boss 的配置
			if new_stats.boss_dialogue_hooks.is_empty():
				new_stats.boss_dialogue_hooks = unit.unit_stats.boss_dialogue_hooks.duplicate(true)

			# 覆盖本阶段机制参数
			new_stats.boss_mechanic_id = str(p.get("mechanic_id", ""))
			var mp: Variant = p.get("mechanic_params", {})
			new_stats.boss_mechanic_params = (mp as Dictionary).duplicate(true) if mp is Dictionary else {}
	else:
		new_stats = UnitData.from_dict(unit.unit_stats.to_dict())
		var ov: Variant = p.get("override", {})
		if ov is Dictionary:
			_apply_override_dict(new_stats, ov)
		if p.has("mechanic_id"):
			new_stats.boss_mechanic_id = str(p.get("mechanic_id", ""))
		if p.has("mechanic_params"):
			var mp2: Variant = p.get("mechanic_params", {})
			new_stats.boss_mechanic_params = (mp2 as Dictionary).duplicate(true) if mp2 is Dictionary else {}

	if new_stats == null:
		return

	# ★ 核心修复：强制继承头像，防止新形态漏配导致头像消失
	if new_stats.avatar == "":
		new_stats.avatar = unit.unit_stats.avatar
	if new_stats.avatar_override == "":
		new_stats.avatar_override = unit.unit_stats.avatar_override

	var hp_mode: String = str(p.get("hp_mode", "full"))
	var min_hp: int = int(p.get("min_hp", 1))
	var reset_turn: bool = bool(p.get("reset_turn_state", false))
	var preserve: bool = bool(p.get("preserve_buffs", true))

	unit.apply_boss_form(new_stats, hp_mode, min_hp, reset_turn, preserve)

	st["current_phase"] = phase_idx
	st["triggered"][phase_idx] = true
	st["current_mechanic_id"] = new_stats.boss_mechanic_id
	st["current_mechanic_params"] = new_stats.boss_mechanic_params
	if new_stats.boss_mechanic_id == "ash_shield":
		st["ash_shield_stacks"] = int(new_stats.boss_mechanic_params.get("max_stacks", 3))
	else:
		st["ash_shield_stacks"] = 0

	var version: int = int(unit.get_meta("boss_phase_version", 0)) + 1
	unit.set_meta("boss_phase_version", version)

	# ★ 修复：形态切换后立刻刷新血条/信息面板，避免对话期间玩家看到旧数据。
	#   原实现把刷新放在 await 之后，导致对话播放期间面板仍显示旧形态的 max_hp / 数值。
	if is_instance_valid(unit):
		unit.update_hp_label()
		SignalBus.request_show_info.emit(unit)

	# ★ 只有真正"转阶段"（phase_idx > 0）时才触发震屏和提示。
	#   初始阶段（phase_idx == 0）跳过，避免对话一结束就莫名其妙震动。
	if phase_idx > 0:
		SignalBus.request_screen_shake.emit(0.4, 8.0, Vector2.ZERO)
		SignalBus.request_hint_override.emit(
			"★ %s 进入第 %d 形态！" % [unit.unit_stats.display_name, phase_idx + 1], 2.0)

	# ★ 触发转阶段对话
	if phase_idx > 0:
		var hook_key : String = "phase_%d" % (phase_idx + 1)
		var dlg_id : String = str(new_stats.boss_dialogue_hooks.get(hook_key, ""))
		if dlg_id != "" and StoryManager.play_dialogue_by_id(dlg_id):
			await DialogueManager.dialogue_finished

	# ★ 对话结束后再刷新一次（兜底：若对话期间有其他效果改变了 unit 状态）
	if is_instance_valid(unit):
		unit.update_hp_label()
		SignalBus.request_show_info.emit(unit)


func _apply_override_dict(stats: UnitData, ov: Dictionary) -> void:
	for k in ov:
		var v: Variant = ov[k]
		match k:
			"max_hp": stats.max_hp = int(v)
			"strength": stats.strength = int(v)
			"dexterity": stats.dexterity = int(v)
			"intelligence": stats.intelligence = int(v)
			"faith": stats.faith = int(v)
			"arcane": stats.arcane = int(v)
			"move_range": stats.move_range = int(v)
			"physical_reduction": stats.physical_reduction = float(v)
			"magic_reduction": stats.magic_reduction = float(v)
			"sprite_frames_path": stats.override_sprite_path = str(v)
			"weapon_id":
				var inst := ItemInstance.new()
				inst.item_id = str(v)
				inst.count = 1
				stats.weapon_slot = inst
			"tags":
				stats.tags.clear()
				if v is Array:
					for t in v:
						if t is String:
							stats.tags.append(t)
			"core_trait": stats.core_trait = str(v)


func process_damage_phase(unit: Unit, _attacker: Unit, _damage: int, old_hp: int = -1) -> Dictionary:
	if not _boss_states.has(unit):
		return {}
	var st: Dictionary = _boss_states[unit]
	var phases: Array = unit.unit_stats.phases
	var next_idx: int = int(st.get("current_phase", 0)) + 1
	if next_idx >= phases.size():
		return {}

	var p: Dictionary = phases[next_idx]
	if str(p.get("trigger", "")) != TRIGGER_HP_BELOW:
		return {}
	if bool(st.get("triggered", {}).get(next_idx, false)):
		return {}

	var max_hp : int = maxi(1, unit.unit_stats.max_hp)
	var threshold : float = float(p.get("threshold", 0.5))
	
	# 如果扣血后的血量比例大于阈值，说明没达标，直接返回
	if float(unit.hit_points) / float(max_hp) > threshold:
		return {}

	# ★ 核心修复 1：如果一击把血打空了（变0），为了不让 keep_ratio 计算出 0，
	# 我们在转阶段前把血量临时恢复成扣血前的数值（这样新形态就能继承合理的百分比）。
	if unit.hit_points <= 0 and old_hp > 0:
		unit.hit_points = old_hp
		
	_apply_phase(unit, next_idx)
	
	# ★ 核心修复 2：如果转阶段后血量还是 <= 0，用 min_hp 兜底
	if unit.hit_points <= 0:
		unit.hit_points = maxi(1, int(p.get("min_hp", 1)))
		unit.update_hp_label()
		
	return {"transitioned": true, "prevent_death": true}


func on_boss_defeated(defender: Unit) -> bool:
	if not _boss_states.has(defender):
		return false
	var st: Dictionary = _boss_states[defender]
	var phases: Array = defender.unit_stats.phases
	var next_idx: int = int(st.get("current_phase", 0)) + 1
	if next_idx >= phases.size():
		return false

	var p: Dictionary = phases[next_idx]
	var trigger: String = str(p.get("trigger", TRIGGER_ON_DEATH))

	if trigger == TRIGGER_HP_BELOW and not bool(st.get("triggered", {}).get(next_idx, false)):
		_apply_phase(defender, next_idx)
		defender.hit_points = maxi(1, int(p.get("min_hp", 1)))
		defender.update_hp_label()
		return true

	if trigger == TRIGGER_ON_DEATH:
		_apply_phase(defender, next_idx)
		return true

	return false


func on_player_turn_start() -> void:
	for u in _boss_states.keys():
		if not is_instance_valid(u):
			continue
		var st: Dictionary = _boss_states[u]
		var mid: String = str(st.get("current_mechanic_id", ""))
		var mp: Dictionary = st.get("current_mechanic_params", {})
		if mid == "soul_drain":
			var amount: int = int(mp.get("drain_amount", 1))
			if SoulFireManager.current >= amount:
				SoulFireManager.spend(amount)
				SignalBus.request_hint_override.emit("★ 汲取了 %d 魂火！" % amount, 1.5)


func on_enemy_turn_start() -> void:
	# 预留给敌方回合开始的阶段机制（例如护盾层数刷新）
	pass


func modify_damage_to_boss(_attacker: Unit, defender: Unit, damage: int) -> int:
	if not _boss_states.has(defender):
		return damage
	var st: Dictionary = _boss_states[defender]
	var mid: String = str(st.get("current_mechanic_id", ""))
	if mid == "ash_shield":
		var stacks: int = int(st.get("ash_shield_stacks", 0))
		if stacks > 0:
			var mp: Dictionary = st.get("current_mechanic_params", {})
			var dr: float = float(mp.get("damage_reduction", 0.5))
			damage = maxi(1, int(damage * (1.0 - dr)))
			st["ash_shield_stacks"] = stacks - 1
			if stacks - 1 <= 0:
				SignalBus.request_hint_override.emit("★ %s 的灰烬护盾破碎！" % defender.unit_stats.display_name, 1.2)
	return damage
