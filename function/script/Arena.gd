extends CanvasLayer

signal closed

# ============================================================
#  常量
# ============================================================
const ENTRY_COST : int = 2
const CLEAR_TARGET : int = 10
const SURVIVAL_ROUNDS : int = 3
const CRYSTAL_PER_SOUL : int = 100

const RETENTION_1_4 : float = 1.0
const RETENTION_5   : float = 0.8
const RETENTION_6_9 : float = 0.6
const RETENTION_10  : float = 0.3
const RETENTION_SURVIVAL : float = 0.1
const RETREAT_RATIO : float = 0.8

const GOLD_NORMAL : int = 100
const GOLD_ELITE : int = 250
const GOLD_BOSS : int = 500

const CRYSTAL_NORMAL : int = 20
const CRYSTAL_ELITE : int = 40
const CRYSTAL_BOSS : int = 80

const GOLD_SURVIVAL : Array = [200, 300, 500]
const CRYSTAL_SURVIVAL : Array = [60, 80, 120]

const SOUL_ELITE : int = 1
const SOUL_BOSS : int = 2
const SOUL_SURVIVAL_BOSS : int = 3

const ENEMY_SCALE_BY_STREAK : Array = [1.0, 1.15, 1.30, 1.45, 1.8, 1.75, 1.9, 2.05, 2.2, 2.5]
const ENEMY_SCALE_SURVIVAL : Array = [2.5, 2.8, 3.2]

enum Phase { IDLE, NORMAL, CLEAR, SURVIVAL, END }

const EquipmentConfigClass = preload(Config.PATHS.EQUIPMENT_CONFIG_SCRIPT)

# ============================================================
#  局内状态
# ============================================================
var _phase : Phase = Phase.IDLE
var _arena_gold : int = 100
var _arena_crystals : int = 0
var _streak : int = 0
var _survival_round : int = 0
var _current_player_data : UnitData = null
var _locked_talent_id : String = ""
var _streak_active : bool = false
var _run_best_streak : int = 0
var _run_total_crystals : int = 0
var _run_total_soul : int = 0
var _arena_passives : Array = [null, null, null, null]
var _talent_swap_chances : int = 1

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
		streak_label.text = "最高连胜：%d  |  通关：%d 次" % [GameState.arena_best_streak, GameState.arena_clear_count]
	elif _phase == Phase.SURVIVAL:
		streak_label.text = "生存：%d / %d（不可撤离）" % [_survival_round, SURVIVAL_ROUNDS]
	else:
		var next_type = "普通"
		if _streak == 4:
			next_type = "★ 精英"
		elif _streak == 9:
			next_type = "★ BOSS"
		streak_label.text = "进度：%d / %d  |  下一战：%s  |  结晶：%d" % [
			_streak, CLEAR_TARGET, next_type, _arena_crystals
		]

# ============================================================
#  开始
# ============================================================
func _on_start_pressed():
	if _phase != Phase.IDLE:
		return
	if not _current_player_data:
		_show_hint("请先选择单位")
		return
	if GameState.soul < ENTRY_COST:
		_show_hint("魂不足（需要 %d）" % ENTRY_COST)
		return

	GameState.soul -= ENTRY_COST
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
	_arena_gold = 100
	_arena_crystals = 0
	_streak = 0
	_survival_round = 0
	_streak_active = false
	_run_best_streak = 0
	_run_total_crystals = 0
	_run_total_soul = 0
	_arena_passives = [null, null, null, null]
	_talent_swap_chances = 1
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
		var shop_action = await _show_shop()

		if not is_inside_tree():
			return

		if shop_action == "quit":
			_show_summary(false, "放弃")
			return

		var winner = await _do_one_battle()

		if not is_inside_tree():
			return

		if winner != 0:
			_show_summary(false, "失败")
			return

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
					_arena_crystals = int(_arena_crystals * RETREAT_RATIO)
					_show_summary(true, "撤离")
					return

		elif _phase == Phase.SURVIVAL:
			_survival_round += 1
			if _survival_round >= SURVIVAL_ROUNDS:
				_arena_crystals = int(_arena_crystals * 1.5)
				_show_summary(true, "生存通过")
				return

		SaveManager.auto_save()

# ============================================================
#  商店
# ============================================================
func _show_shop() -> String:
	var ctx = ArenaEquipContext.new()
	ctx.arena_gold = _arena_gold
	ctx.player_data = _current_player_data
	ctx.passives = _arena_passives.duplicate()
	ctx.locked_talent_id = _locked_talent_id
	ctx.talent_swap_chances = _talent_swap_chances

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
	_talent_swap_chances = ctx.talent_swap_chances

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

	var rewards = _calc_battle_rewards()
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
	battle.setup(_current_player_data, enemy_data, rewards.crystal, battle_index)
	var result = await battle.closed

	if not is_inside_tree():
		return 1

	if result.get("winner_team", 1) == 0:
		# ---- 基础奖励 ----
		_arena_gold += rewards.gold
		_arena_crystals += rewards.crystal
		_run_total_crystals += rewards.crystal

		# ---- 关键节点魂 ----
		var soul_gain = _calc_soul_reward()
		if soul_gain > 0:
			GameState.soul += soul_gain
			_run_total_soul += soul_gain

		# ---- 词条经验 ----
		var exp_actual : int = 0
		var old_level : int = 0
		var new_level : int = 0
		if _locked_talent_id != "":
			old_level = TalentManager.get_talent_level(_current_player_data.unit_name, _locked_talent_id)
			exp_actual = TalentManager.add_talent_exp(_current_player_data.unit_name, _locked_talent_id, exp_gain)
			new_level = TalentManager.get_talent_level(_current_player_data.unit_name, _locked_talent_id)

		_current_player_data.hit_points = _current_player_data.max_hp
		_streak_active = true
		SaveManager.auto_save()

		# ★ 用 RewardSummaryUI 显示本场奖励
		await _show_battle_rewards(rewards, soul_gain, exp_actual, old_level, new_level, battle_index)
		if not is_inside_tree():
			return 1

		return 0
	else:
		_arena_crystals = int(_arena_crystals * _get_failure_retention())
		return 1

func _calc_soul_reward() -> int:
	if _phase == Phase.SURVIVAL and _survival_round == SURVIVAL_ROUNDS - 1:
		return SOUL_SURVIVAL_BOSS
	if _phase == Phase.NORMAL:
		if _streak == 4:
			return SOUL_ELITE
		elif _streak == 9:
			return SOUL_BOSS
	return 0

# ============================================================
#  战斗奖励弹窗（复用 RewardSummaryUI）
# ============================================================
func _show_battle_rewards(rewards: Dictionary, soul_gain: int,
		exp_gain: int, old_level: int, new_level: int, battle_index: int):
	var summary = Globals.get_reward_summary()
	if not summary:
		return

	# ---- 构建 items ----
	var items : Array = []

	# 结晶
	var crystal_item = ItemData.new()
	crystal_item.id = "arena_crystal"
	crystal_item.name = "结晶 +%d" % int(rewards.crystal)
	crystal_item.description = ""
	items.append(crystal_item)

	# 词条经验
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

	# ---- 标题 ----
	var title = "第 %d 战胜利" % battle_index
	if _phase == Phase.SURVIVAL:
		title = "生存 %d / %d 胜利" % [_survival_round + 1, SURVIVAL_ROUNDS]

	# ---- 显示 ----
	summary.setup_reward(rewards.gold, soul_gain, items, false, title)
	summary.open()
	await summary.confirmed
	summary.close()

# ============================================================
#  进度奖励
# ============================================================
func _grant_progress_rewards():
	if _phase != Phase.NORMAL:
		return
	if _streak == 5:
		_current_player_data.max_armor_slots = 3
		while _current_player_data.armor_slots.size() < 3:
			_current_player_data.armor_slots.append(null)
		_talent_swap_chances += 1
		print("[Arena] 第 5 战胜利：防具槽 +1，可换特技 ×1")
	elif _streak == 10:
		_current_player_data.max_armor_slots = 4
		while _current_player_data.armor_slots.size() < 4:
			_current_player_data.armor_slots.append(null)
		_talent_swap_chances += 1
		print("[Arena] 第 10 战胜利：防具槽 +1，可换特技 ×1")

func _get_failure_retention() -> float:
	if _phase == Phase.SURVIVAL:
		return RETENTION_SURVIVAL
	if _streak <= 4:
		return RETENTION_1_4
	elif _streak == 5:
		return RETENTION_5
	elif _streak <= 9:
		return RETENTION_6_9
	return RETENTION_10

func _is_elite_battle() -> bool:
	return _phase == Phase.NORMAL and _streak == 4

func _is_boss_battle() -> bool:
	return _phase == Phase.NORMAL and _streak == 9

func _calc_battle_rewards() -> Dictionary:
	if _phase == Phase.SURVIVAL:
		var idx = mini(_survival_round, 2)
		return {"crystal": CRYSTAL_SURVIVAL[idx], "gold": GOLD_SURVIVAL[idx]}
	if _is_elite_battle():
		return {"crystal": CRYSTAL_ELITE, "gold": GOLD_ELITE}
	if _is_boss_battle():
		return {"crystal": CRYSTAL_BOSS, "gold": GOLD_BOSS}
	return {"crystal": CRYSTAL_NORMAL, "gold": GOLD_NORMAL}

func _calc_exp_gain(enemy_type: String) -> int:
	var base = _get_enemy_arena_exp(enemy_type)
	if _phase == Phase.SURVIVAL:
		return int(base * 2.0)
	if _is_elite_battle():
		return int(base * 1.5)
	if _is_boss_battle():
		return int(base * 2.0)
	return base

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
		if _survival_round == SURVIVAL_ROUNDS - 1:
			pool_key = "boss"
		else:
			pool_key = "elite"
	elif _streak == 4:
		pool_key = "elite"
	elif _streak == 9:
		pool_key = "boss"
	elif _streak < 4:
		pool_key = "easy"
	else:
		pool_key = "normal"

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
#  通关面板
# ============================================================
func _show_clear_panel() -> String:
	var scene = load(Config.PATHS.CONFIRM_UI)
	if not scene:
		return "settle"

	var ui = scene.instantiate()
	add_child(ui)

	var soul_preview = floori(float(_arena_crystals) / CRYSTAL_PER_SOUL)
	var retreat_crystals = int(_arena_crystals * RETREAT_RATIO)
	var retreat_soul = floori(float(retreat_crystals) / CRYSTAL_PER_SOUL)
	var survival_preview = int(_arena_crystals * 1.5)
	var survival_soul = floori(float(survival_preview) / CRYSTAL_PER_SOUL)

	var msg = "【10 连胜达成】\n\n"
	msg += "当前结晶：%d（可兑换 %d 魂）\n\n" % [_arena_crystals, soul_preview]
	msg += "选择：\n"
	msg += "· 撤离：结算 +%d 结晶（%d 魂）\n" % [retreat_crystals, retreat_soul]
	msg += "· 生存：3 连战不可撤离\n"
	msg += "  · 通过：结晶 ×1.5 → %d（%d 魂）+3 魂\n" % [survival_preview, survival_soul]
	msg += "  · 失败：仅保留 10%% 结晶\n\n"
	msg += "是否进入生存模式？"

	var holder = {"value": ""}
	ui.show_confirm(
		msg,
		"进入生存",
		"撤离结算",
		func(): holder["value"] = "survival",
		func(): holder["value"] = "settle",
		true
	)

	while is_instance_valid(ui) and holder["value"] == "":
		await get_tree().process_frame
	await get_tree().process_frame
	return holder["value"]

# ============================================================
#  最终结算（也用 RewardSummaryUI）
# ============================================================
func _show_summary(success: bool, reason: String):
	if success:
		MusicManager.play_victory_music()
	else:
		MusicManager.play_defeat_music()

	var soul_gain = floori(float(_arena_crystals) / CRYSTAL_PER_SOUL)
	var total_soul_gain = soul_gain + _run_total_soul

	GameState.soul += soul_gain
	GameState.arena_total_crystals += _run_total_crystals

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

	var title = "斗技场 · %s" % reason
	summary.setup_reward(0, total_soul_gain, [], true, title)
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
	MusicManager.play_arena_music()
	_build_unit_list()
	_refresh_center_panel()
	_refresh_streak_label()

func _show_hint(text: String):
	info_label.text = text
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(info_label) and is_inside_tree():
		_refresh_center_panel()
