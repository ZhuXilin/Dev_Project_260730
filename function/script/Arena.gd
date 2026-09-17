extends CanvasLayer

signal closed

# ============================================================
#  常量
# ============================================================
const CLEAR_TARGET : int = 4
const SURVIVAL_ROUNDS : int = 3

# ---- 关键节点参与费（只扣魂） ----
const ENTRY_COST_MINI_BOSS : int = 1
const ENTRY_COST_SURVIVAL : int = 3

# ---- 撤离手续费 ----
const RETREAT_FEE_AFTER_STREAK_4 : int = 1

# ---- 战 1-4 金币奖励 ----
const GOLD_BY_STREAK : Array = [100, 150, 350, 600]

# ---- 战 1-4 魂奖励 ----
const SOUL_BY_STREAK : Array = [0, 0, 2, 3]

# ---- 生存模式奖励（3 战） ----
const GOLD_SURVIVAL : Array = [800, 1200, 2000]
const SOUL_SURVIVAL : Array = [4, 6, 10]

# ---- 敌人倍率 ----
const ENEMY_SCALE_BY_STREAK : Array = [1.0, 1.2, 1.6, 1.9]
const ENEMY_SCALE_SURVIVAL : Array = [2.2, 2.8, 3.5]

enum Phase { IDLE, NORMAL, CLEAR, SURVIVAL, END }

const EquipmentConfigClass = preload(Config.PATHS.EQUIPMENT_CONFIG_SCRIPT)

# ============================================================
#  局内状态
# ============================================================
var _phase : Phase = Phase.IDLE
var _arena_gold : int = 0
var _streak : int = 0
var _survival_round : int = 0
var _current_player_data : UnitData = null
var _locked_talent_id : String = ""
var _streak_active : bool = false
var _run_best_streak : int = 0
var _earned_soul : int = 0
var _total_paid : int = 0
var _retreat_fee : int = 0
var _arena_passives : Array = [null, null, null, null]

# ============================================================
#  节点引用
# ============================================================
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/UnitListScroll/UnitList
@onready var selected_unit_label : Label = $Panel/VBox/MainHBox/CenterPanel/SelectedUnitLabel
@onready var info_label : Label = $Panel/VBox/MainHBox/CenterPanel/InfoLabel
@onready var streak_label : Label = $Panel/VBox/MainHBox/CenterPanel/StreakLabel
@onready var start_btn : Button = $Panel/VBox/BottomBar/StartBtn
@onready var back_btn : Button = $Panel/VBox/BottomBar/BackButton

func _ready():
	MusicManager.play_arena_music()
	_build_unit_list()
	_refresh_center_panel()
	_refresh_streak_label()

# ============================================================
#  单位选择
# ============================================================
func _build_unit_list():
	for child in unit_list.get_children():
		unit_list.remove_child(child)
		child.queue_free()

	var all_units = UnitDataManager.get_all_unit_ids()
	var unlocked_list : Array = []
	var locked_list : Array = []
	for unit_type in all_units:
		if Globals.is_unit_unlocked(unit_type):
			unlocked_list.append(unit_type)
		else:
			locked_list.append(unit_type)

	for unit_type in unlocked_list:
		var btn = Button.new()
		btn.text = UnitDataManager.get_unit_type_display_name(unit_type)
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE
		btn.pressed.connect(_on_unit_selected.bind(unit_type))
		unit_list.add_child(btn)

	for _u in locked_list:
		var btn = Button.new()
		btn.text = "？？？"
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.modulate = Color(0.4, 0.4, 0.4, 1)
		btn.disabled = true
		unit_list.add_child(btn)

	if unlocked_list.size() > 0:
		_on_unit_selected(unlocked_list[0])

func _on_unit_selected(unit_type: String):
	if _phase != Phase.IDLE:
		return
	_current_player_data = UnitDataManager.create_unit_data(unit_type)
	UnitDataManager.apply_growth(_current_player_data, unit_type)
	_current_player_data.hit_points = _current_player_data.max_hp

	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			child.modulate = Color.WHITE if ut == unit_type else Color(0.6, 0.6, 0.6, 1)

	_refresh_center_panel()

# ============================================================
#  显示刷新
# ============================================================
func _refresh_center_panel():
	if not _current_player_data:
		selected_unit_label.text = "（未选择单位）"
		info_label.text = ""
		return

	var display = UnitDataManager.get_unit_type_display_name(_current_player_data.unit_name)
	selected_unit_label.text = "单位：%s  HP %d/%d" % [
		display, _current_player_data.hit_points, _current_player_data.max_hp
	]

	var talent_id = GameState.arena_target_talents.get(_current_player_data.unit_name, "")
	if talent_id != "":
		var data = TalentManager.get_talent_data(talent_id)
		if data:
			var lv = TalentManager.get_talent_level(_current_player_data.unit_name, talent_id)
			var talent_exp_val = TalentManager.get_talent_exp(_current_player_data.unit_name, talent_id)
			info_label.text = "目标词条：Lv.%d %s（经验 %d/600）" % [lv, data.display_name, talent_exp_val]
		else:
			info_label.text = ""
	else:
		info_label.text = "目标词条：未设置（可在商店配置）"

func _refresh_streak_label():
	if _phase == Phase.IDLE:
		streak_label.text = "最高连胜：%d  |  通关：%d 次  |  当前魂：%d" % [
			GameState.arena_best_streak, GameState.arena_clear_count, GameState.soul
		]
	elif _phase == Phase.SURVIVAL:
		streak_label.text = "生存：%d / %d（不可撤离）  |  本局净：%+d 魂" % [
			_survival_round, SURVIVAL_ROUNDS, _get_net_gain()
		]
	else:
		var next_type = "普通"
		if _streak == 2:
			next_type = "★ 小Boss（付 %d 魂）" % ENTRY_COST_MINI_BOSS
		elif _streak == 3:
			next_type = "★ 精英"
		streak_label.text = "进度：%d / %d  |  下一战：%s  |  本局净：%+d 魂" % [
			_streak, CLEAR_TARGET, next_type, _get_net_gain()
		]

func _get_net_gain() -> int:
	return _earned_soul - _total_paid - _retreat_fee

# ============================================================
#  开始（免费入场）
# ============================================================
func _on_start_pressed():
	if _phase != Phase.IDLE:
		return
	if not _current_player_data:
		_show_hint("请先选择单位")
		return

	GameState.arena_total_runs += 1
	SaveManager.auto_save()

	_init_arena_state()
	_run_battle_loop()

func _on_back_pressed():
	if _phase != Phase.IDLE:
		_show_hint("挑战中无法退出")
		return
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()

func _init_arena_state():
	_phase = Phase.NORMAL
	_arena_gold = 0
	_streak = 0
	_survival_round = 0
	_streak_active = false
	_run_best_streak = 0
	_earned_soul = 0
	_total_paid = 0
	_retreat_fee = 0
	_arena_passives = [null, null, null, null]
	_locked_talent_id = ""

	_current_player_data.reset_combat_buffs()
	_current_player_data.hit_points = _current_player_data.max_hp
	_current_player_data.max_armor_slots = 2
	_current_player_data.armor_slots = [null, null]

	var saved_talent = GameState.arena_target_talents.get(_current_player_data.unit_name, "")
	if saved_talent != "":
		_locked_talent_id = saved_talent

	_apply_arena_relics_to_player()
	_current_player_data.hit_points = _current_player_data.max_hp

func _apply_arena_relics_to_player():
	var relic_stats = {}
	for p in _arena_passives:
		if p is ItemInstance:
			var data = RelicManager.get_relic_data(p.item_id)
			if data.is_empty():
				continue
			var stats = data.get("stats", {})
			for key in stats:
				relic_stats[key] = relic_stats.get(key, 0) + stats[key]

	var s = _current_player_data
	s.max_hp       += int(relic_stats.get("max_hp", 0))
	s.strength     += int(relic_stats.get("strength", 0))
	s.dexterity    += int(relic_stats.get("dexterity", 0))
	s.intelligence += int(relic_stats.get("intelligence", 0))
	s.faith        += int(relic_stats.get("faith", 0))
	s.arcane       += int(relic_stats.get("arcane", 0))
	s.move_range   += int(relic_stats.get("move_range", 0))

# ============================================================
#  主循环
# ============================================================
func _run_battle_loop():
	while _phase != Phase.END:
		# 1. 关键节点参与费
		var entry_choice = await _check_entry_fee()
		if not is_inside_tree():
			return
		if entry_choice == "decline":
			_show_summary(true, "及时止损")
			return

		# 2. 商店
		var shop_action = await _show_shop()
		if not is_inside_tree():
			return
		if shop_action == "quit":
			_show_summary(true, "放弃")
			return

		# 3. 战斗
		var winner = await _do_one_battle()
		if not is_inside_tree():
			return
		if winner != 0:
			_show_summary(false, "失败")
			return

		# 4. 胜利后处理
		if _phase == Phase.NORMAL:
			_streak += 1
			_run_best_streak = maxi(_run_best_streak, _streak)
			if _streak > GameState.arena_best_streak:
				GameState.arena_best_streak = _streak
			_grant_progress_rewards()

			if _streak >= CLEAR_TARGET:
				_phase = Phase.CLEAR
				var choice = await _show_clear_panel()
				if not is_inside_tree():
					return
				if choice == "survival":
					_phase = Phase.SURVIVAL
					_survival_round = 0
				else:
					# ★ 战 4 后撤离：扣 1 魂手续费
					_apply_retreat_fee(RETREAT_FEE_AFTER_STREAK_4)
					_show_summary(true, "撤离")
					return

		elif _phase == Phase.SURVIVAL:
			_survival_round += 1
			if _survival_round >= SURVIVAL_ROUNDS:
				_show_summary(true, "生存通过")
				return

		SaveManager.auto_save()

func _apply_retreat_fee(fee: int):
	if fee <= 0:
		return
	if GameState.soul >= fee:
		GameState.soul -= fee
		_retreat_fee += fee
	else:
		# 魂不够就扣到 0
		_retreat_fee += GameState.soul
		GameState.soul = 0

# ============================================================
#  魂支付
# ============================================================
func _can_pay_soul(cost: int) -> bool:
	return GameState.soul >= cost

func _pay_soul(cost: int) -> bool:
	if GameState.soul < cost:
		return false
	GameState.soul -= cost
	_total_paid += cost
	return true

# ============================================================
#  关键节点参与费
# ============================================================
func _check_entry_fee() -> String:
	if _phase != Phase.NORMAL:
		return "accept"

	var cost = 0
	if _streak == 2:
		cost = ENTRY_COST_MINI_BOSS
	else:
		return "accept"

	var choice = await _show_entry_fee_panel(cost)
	if choice != "accept":
		return "decline"

	if not _pay_soul(cost):
		return "decline"
	SaveManager.auto_save()
	return "accept"

func _show_entry_fee_panel(cost: int) -> String:
	var scene = load(Config.PATHS.CONFIRM_UI)
	if not scene:
		return "decline"

	var ui = scene.instantiate()
	add_child(ui)

	var soul_now = GameState.soul
	var can_afford = soul_now >= cost
	var reward_soul = SOUL_BY_STREAK[2]

	var msg = ""
	msg += "【关键节点 · 小 Boss】\n\n"
	msg += "下一战难度显著提升。\n"
	msg += "胜利奖励：+%d 魂 + 大量金币 + 防具槽 +1\n\n" % reward_soul
	msg += "参与费：%d 魂\n" % cost
	msg += "当前魂：%d\n\n" % soul_now
	if not can_afford:
		msg += "⚠ 魂不足，只能放弃\n"
	msg += "是否支付参与费继续挑战？"

	var holder = {"value": ""}
	if can_afford:
		ui.show_confirm(
			msg,
			"支付继续",
			"及时止损",
			func(): holder["value"] = "accept",
			func(): holder["value"] = "decline",
			true
		)
	else:
		ui.show_confirm(
			msg,
			"及时止损",
			"",
			func(): holder["value"] = "decline",
			func(): pass,
			false
		)

	while is_instance_valid(ui) and holder["value"] == "":
		await get_tree().process_frame
	await get_tree().process_frame
	return holder["value"]

# ============================================================
#  商店
# ============================================================
func _show_shop() -> String:
	var ctx = ArenaEquipContext.new()
	ctx.arena_gold = _arena_gold
	ctx.player_data = _current_player_data
	ctx.passives = _arena_passives.duplicate()
	ctx.locked_talent_id = _locked_talent_id

	var scene = load(Config.PATHS.EQUIPMENT_CONFIG)
	if not scene:
		push_error("EquipmentConfig 未找到")
		return "quit"

	var config = scene.instantiate()
	add_child(config)
	var panel = config.get_node("MainPanel")

	var mode : int
	if _streak == 0:
		mode = EquipmentConfigClass.Mode.DEPLOY
	else:
		mode = EquipmentConfigClass.Mode.ARENA_REST

	panel.init(
		[_current_player_data.unit_name],
		-1,
		mode,
		ctx
	)

	await panel.tree_exited
	if not is_inside_tree():
		return "quit"

	_arena_gold = ctx.arena_gold
	_arena_passives = ctx.passives.duplicate()
	_locked_talent_id = ctx.locked_talent_id

	if _locked_talent_id != "" and _current_player_data:
		GameState.arena_target_talents[_current_player_data.unit_name] = _locked_talent_id

	return "go"

# ============================================================
#  单场战斗
# ============================================================
func _do_one_battle() -> int:
	if not is_inside_tree():
		return 1
	await get_tree().process_frame
	if not is_inside_tree():
		return 1

	var enemy_type = _roll_enemy()
	if enemy_type == "":
		push_error("敌人池为空")
		return 1

	var enemy_data = UnitDataManager.create_unit_data(enemy_type)
	_apply_enemy_scaling(enemy_data)

	var gold_gain = _calc_gold_reward()
	var soul_gain = _calc_soul_reward()
	var exp_gain = _calc_exp_gain(enemy_type)

	var battle_index = _streak + 1
	if _phase == Phase.SURVIVAL:
		battle_index = 100 + _survival_round + 1

	var scene = load(Config.PATHS.ARENA_BATTLE_UI)
	if not scene:
		push_error("ArenaBattle 未找到")
		return 1

	var battle = scene.instantiate()
	add_child.call_deferred(battle)
	if not is_inside_tree():
		return 1
	await get_tree().process_frame
	if not is_inside_tree():
		return 1
	battle.setup(_current_player_data, enemy_data, 0, battle_index)
	var result = await battle.closed

	if not is_inside_tree():
		return 1

	if result.get("winner_team", 1) == 0:
		# 金币（局内）
		_arena_gold += gold_gain

		# 魂（永久，直接入账）
		if soul_gain > 0:
			GameState.soul += soul_gain
			_earned_soul += soul_gain

		# 词条经验
		var exp_actual : int = 0
		var old_level : int = 0
		var new_level : int = 0
		if _locked_talent_id != "":
			old_level = TalentManager.get_talent_level(_current_player_data.unit_name, _locked_talent_id)
			exp_actual = TalentManager.add_talent_exp(_current_player_data.unit_name, _locked_talent_id, exp_gain)
			new_level = TalentManager.get_talent_level(_current_player_data.unit_name, _locked_talent_id)

		# 每战回满 HP
		_current_player_data.hit_points = _current_player_data.max_hp
		_streak_active = true
		SaveManager.auto_save()

		await _show_battle_rewards(gold_gain, soul_gain, exp_actual, old_level, new_level, battle_index)
		if not is_inside_tree():
			return 1

		return 0
	else:
		return 1

# ============================================================
#  奖励查表
# ============================================================
func _calc_gold_reward() -> int:
	if _phase == Phase.SURVIVAL:
		var idx = mini(_survival_round, 2)
		return GOLD_SURVIVAL[idx]
	var i = mini(_streak, GOLD_BY_STREAK.size() - 1)
	return GOLD_BY_STREAK[i]

func _calc_soul_reward() -> int:
	if _phase == Phase.SURVIVAL:
		var idx = mini(_survival_round, 2)
		return SOUL_SURVIVAL[idx]
	var i = mini(_streak, SOUL_BY_STREAK.size() - 1)
	return SOUL_BY_STREAK[i]

func _calc_exp_gain(enemy_type: String) -> int:
	var base = _get_enemy_arena_exp(enemy_type)
	if _phase == Phase.SURVIVAL:
		return int(base * 2.5)
	if _is_mini_boss_battle():
		return int(base * 2.0)
	if _is_elite_battle():
		return int(base * 2.5)
	return base

# ============================================================
#  战斗奖励弹窗
# ============================================================
func _show_battle_rewards(gold_gain: int, soul_gain: int,
		exp_gain: int, old_level: int, new_level: int, battle_index: int):
	var summary = Globals.get_reward_summary()
	if not summary:
		return

	var items : Array = []

	if exp_gain > 0 and _locked_talent_id != "":
		var talent_data = TalentManager.get_talent_data(_locked_talent_id)
		var talent_name = talent_data.display_name if talent_data else _locked_talent_id
		var exp_item = ItemData.new()
		exp_item.id = "arena_exp"
		if new_level > old_level:
			exp_item.name = "★ %s 升级 Lv.%d → Lv.%d" % [talent_name, old_level, new_level]
		else:
			exp_item.name = "%s 经验 +%d" % [talent_name, exp_gain]
		if talent_data:
			exp_item.description = talent_data.description
		items.append(exp_item)

	var title = "第 %d 战胜利" % battle_index
	if _phase == Phase.SURVIVAL:
		title = "生存 %d / %d 胜利" % [_survival_round + 1, SURVIVAL_ROUNDS]

	summary.setup_reward(gold_gain, soul_gain, items, false, title)
	summary.open()
	await summary.confirmed
	summary.close()

# ============================================================
#  进度奖励（防具槽 +1）
# ============================================================
func _grant_progress_rewards():
	if _phase != Phase.NORMAL:
		return
	if _streak == 3:
		_current_player_data.max_armor_slots = 3
		while _current_player_data.armor_slots.size() < 3:
			_current_player_data.armor_slots.append(null)
		print("[Arena] 小 Boss 胜利：防具槽 2 → 3")
	elif _streak == 4:
		_current_player_data.max_armor_slots = 4
		while _current_player_data.armor_slots.size() < 4:
			_current_player_data.armor_slots.append(null)
		print("[Arena] 精英胜利：防具槽 3 → 4")

func _is_elite_battle() -> bool:
	return _phase == Phase.NORMAL and _streak == 3

func _is_mini_boss_battle() -> bool:
	return _phase == Phase.NORMAL and _streak == 2

# ============================================================
#  敌人
# ============================================================
func _roll_enemy() -> String:
	var path = Config.PATHS.ARENA_ENEMIES
	if not FileAccess.file_exists(path):
		return ""
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		return ""

	var pool_key = "easy"
	if _phase == Phase.SURVIVAL:
		if _survival_round == 0:
			pool_key = "elite"
		else:
			pool_key = "boss"
	elif _streak == 0:
		pool_key = "easy"
	elif _streak == 1:
		pool_key = "normal"
	else:
		pool_key = "elite"

	var pool = data.get(pool_key, [])
	if pool.is_empty():
		pool = data.get("normal", [])
		if pool.is_empty():
			pool = data.get("easy", [])
		if pool.is_empty():
			return ""
	return pool[randi() % pool.size()]

func _apply_enemy_scaling(enemy_data: UnitData):
	var mult = 1.0
	if _phase == Phase.SURVIVAL:
		mult = ENEMY_SCALE_SURVIVAL[mini(_survival_round, ENEMY_SCALE_SURVIVAL.size() - 1)]
	else:
		mult = ENEMY_SCALE_BY_STREAK[mini(_streak, ENEMY_SCALE_BY_STREAK.size() - 1)]

	enemy_data.max_hp = int(enemy_data.max_hp * mult)
	enemy_data.hit_points = enemy_data.max_hp
	enemy_data.strength = int(enemy_data.strength * mult)
	enemy_data.dexterity = int(enemy_data.dexterity * mult)

func _get_enemy_arena_exp(enemy_type: String) -> int:
	var unit_dict = UnitDataManager.get_unit_data(enemy_type)
	return int(unit_dict.get("arena_exp", 30))

# ============================================================
#  通关面板（进入生存）
# ============================================================
func _show_clear_panel() -> String:
	var scene = load(Config.PATHS.CONFIRM_UI)
	if not scene:
		return "settle"

	var ui = scene.instantiate()
	add_child(ui)

	var soul_now = GameState.soul
	var can_afford = soul_now >= ENTRY_COST_SURVIVAL
	var survival_soul_total = SOUL_SURVIVAL[0] + SOUL_SURVIVAL[1] + SOUL_SURVIVAL[2]
	var retreat_fee = RETREAT_FEE_AFTER_STREAK_4

	var msg = ""
	msg += "【4 连胜达成】\n\n"
	msg += "当前魂：%d\n" % soul_now
	msg += "本局已赚：+%d 魂  |  已支付：-%d 魂\n\n" % [_earned_soul, _total_paid]
	msg += "选择：\n"
	msg += "· 撤离：结算（手续费 %d 魂）\n" % retreat_fee
	msg += "· 生存：支付 %d 魂，3 连 Boss 战\n" % ENTRY_COST_SURVIVAL
	msg += "  通过：总魂 +%d（本局）\n" % survival_soul_total

	if not can_afford:
		msg += "\n⚠ 魂不足（需要 %d）\n" % ENTRY_COST_SURVIVAL

	var holder = {"value": ""}
	if can_afford:
		ui.show_confirm(
			msg,
			"支付 %d 魂进入" % ENTRY_COST_SURVIVAL,
			"撤离（-%d 魂）" % retreat_fee,
			func(): holder["value"] = "survival",
			func(): holder["value"] = "settle",
			true
		)
	else:
		ui.show_confirm(
			msg,
			"撤离（-%d 魂）" % retreat_fee,
			"",
			func(): holder["value"] = "settle",
			func(): pass,
			false
		)

	while is_instance_valid(ui) and holder["value"] == "":
		await get_tree().process_frame
	await get_tree().process_frame

	if holder["value"] == "survival":
		_pay_soul(ENTRY_COST_SURVIVAL)
		SaveManager.auto_save()

	return holder["value"]

# ============================================================
#  结算
# ============================================================
func _show_summary(success: bool, reason: String):
	if success:
		MusicManager.play_victory_music()
	else:
		MusicManager.play_defeat_music()

	if success and (reason == "通关" or reason == "生存通过"):
		GameState.arena_clear_count += 1
	if success and reason == "生存通过":
		GameState.arena_survival_clear += 1
	if _phase == Phase.SURVIVAL:
		GameState.arena_survival_best = maxi(GameState.arena_survival_best, _survival_round)

	SaveManager.auto_save()

	var summary = Globals.get_reward_summary()
	if not summary:
		_return_to_idle()
		return

	var net_gain = _get_net_gain()

	# ---- 构建明细 items ----
	var items : Array = []

	if _earned_soul > 0:
		var i1 = ItemData.new()
		i1.id = "arena_earned"
		i1.name = "本局已赚 +%d 魂" % _earned_soul
		items.append(i1)

	if _total_paid > 0:
		var i2 = ItemData.new()
		i2.id = "arena_paid"
		i2.name = "参与费 -%d 魂" % _total_paid
		items.append(i2)

	if _retreat_fee > 0:
		var i3 = ItemData.new()
		i3.id = "arena_fee"
		i3.name = "撤离手续费 -%d 魂" % _retreat_fee
		items.append(i3)

	# ---- 收尾提示 ----
	var tail_hint = ""
	match reason:
		"及时止损":
			tail_hint = "✅ 明智撤退，未支付参与费，零损失"
		"撤离":
			tail_hint = "已提前离场，扣除手续费 %d 魂" % _retreat_fee
		"生存通过":
			tail_hint = "★ 生存全通，硬核 Build 验证成功"
		"失败":
			tail_hint = "再来一次，试试不同 Build"
		"放弃":
			tail_hint = "已放弃本局，本局收益保留"
	if tail_hint != "":
		var hint_item = ItemData.new()
		hint_item.id = "arena_hint"
		hint_item.name = tail_hint
		items.append(hint_item)

	# ---- 标题 ----
	var title = "斗技场 · %s（净收益 %+d 魂）" % [reason, net_gain]

	summary.setup_reward(0, net_gain, items, true, title)
	summary.open()
	await summary.confirmed
	summary.close()

	if not is_inside_tree():
		return

	_return_to_idle()

func _return_to_idle():
	if not is_inside_tree():
		return
	_phase = Phase.IDLE
	_current_player_data = null
	_arena_passives = [null, null, null, null]
	_earned_soul = 0
	_total_paid = 0
	_retreat_fee = 0
	MusicManager.play_arena_music()
	_build_unit_list()
	_refresh_center_panel()
	_refresh_streak_label()

func _show_hint(text: String):
	info_label.text = text
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(info_label) and is_inside_tree():
		_refresh_center_panel()
