extends CanvasLayer

signal closed

# ============================================================
#  常量
# ============================================================
const CLEAR_TARGET : int = 4
const SURVIVAL_ROUNDS : int = 3

const ENTRY_COST_MINI_BOSS : int = 1
const ENTRY_COST_SURVIVAL : int = 3
const RETREAT_FEE_AFTER_STREAK_4 : int = 1

const GOLD_BY_STREAK : Array = [200, 300, 500, 800]
const SOUL_BY_STREAK : Array = [0, 0, 1, 1]

const GOLD_SURVIVAL : Array = [1200, 1800, 3000]
const SOUL_SURVIVAL : Array = [2, 3, 5]

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
var _earned_soul : int = 0
var _total_paid : int = 0
var _retreat_fee : int = 0
var _arena_passives : Array = [null, null, null, null]

# ============================================================
#  节点引用
# ============================================================
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/UnitListScroll/UnitList
@onready var selected_unit_label : Label = $Panel/VBox/MainHBox/CenterPanel/SelectedUnitLabel
@onready var unit_stats_label : Label = $Panel/VBox/MainHBox/CenterPanel/UnitStatsPanel/UnitStatsLabel
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

	var all_units : Array = UnitDataManager.get_all_unit_ids()
	var unlocked_list : Array = []
	for unit_type in all_units:
		if Globals.is_unit_unlocked(unit_type):
			unlocked_list.append(unit_type)

	# ★ Debug：确认当前已解锁列表（排查"未解锁单位也显示"的问题）
	print("[Arena] 全部单位：", all_units)
	print("[Arena] 已解锁单位：", unlocked_list)
	print("[Arena] Globals.unlocked_units = ", Globals.unlocked_units)

	for unit_type in unlocked_list:
		var btn := Button.new()
		btn.text = UnitDataManager.get_unit_type_display_name(unit_type)
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE
		btn.pressed.connect(_on_unit_selected.bind(unit_type))
		btn.mouse_entered.connect(_on_unit_hover.bind(unit_type))
		btn.mouse_exited.connect(_on_unit_hover_exit)
		unit_list.add_child(btn)

	if unlocked_list.size() > 0:
		_on_unit_selected(unlocked_list[0])
	else:
		_current_player_data = null
		_refresh_center_panel()


func _on_unit_selected(unit_type: String):
	if _phase != Phase.IDLE:
		return
	_current_player_data = UnitDataManager.create_unit_data(unit_type)
	_current_player_data.hit_points = _current_player_data.max_hp

	for child in unit_list.get_children():
		if child is Button:
			var ut : String = child.get_meta("unit_type", "")
			child.modulate = Color.WHITE if ut == unit_type else Color(0.6, 0.6, 0.6, 1)

	_refresh_center_panel()


# ============================================================
#  悬停显示单位属性
# ============================================================
func _on_unit_hover(unit_type: String):
	if _phase != Phase.IDLE:
		return
	_refresh_unit_stats(unit_type)


func _on_unit_hover_exit():
	if _current_player_data:
		_refresh_unit_stats(_current_player_data.unit_name)
	else:
		if unit_stats_label:
			unit_stats_label.text = ""


func _refresh_unit_stats(unit_type: String):
	if not unit_stats_label:
		return
	var dict : Dictionary = UnitDataManager.get_unit_data(unit_type)
	if dict.is_empty():
		unit_stats_label.text = ""
		return

	var display : String = dict.get("display_name", unit_type)
	var type_cn : String = UnitDataManager.get_unit_type_display_name(unit_type)

	var lines : Array = []
	lines.append("【%s｜%s】" % [display, type_cn])
	lines.append("")
	lines.append("HP    %d        移动力  %d" % [
		dict.get("max_hp", 0), dict.get("move_range", 0)])
	lines.append("力量  %d        灵巧    %d" % [
		dict.get("strength", 0), dict.get("dexterity", 0)])
	lines.append("智力  %d        信仰    %d" % [
		dict.get("intelligence", 0), dict.get("faith", 0)])
	lines.append("感应  %d" % dict.get("arcane", 0))
	lines.append("")
	lines.append(dict.get("description", ""))

	unit_stats_label.text = "\n".join(lines)


# ============================================================
#  显示刷新
# ============================================================
func _refresh_center_panel():
	if not _current_player_data:
		selected_unit_label.text = "（未选择单位）"
		if unit_stats_label:
			unit_stats_label.text = ""
		info_label.text = ""
		return

	var display : String = UnitDataManager.get_unit_type_display_name(_current_player_data.unit_name)
	var slots : int = _current_player_data.max_armor_slots
	selected_unit_label.text = "单位：%s  HP %d/%d  防具槽 %d" % [
		display, _current_player_data.hit_points, _current_player_data.max_hp, slots
	]

	# 属性面板
	_refresh_unit_stats(_current_player_data.unit_name)

	# 目标词条信息（★ 改为"当前级内经验/当前级所需"）
	var talent_id : String = GameState.arena_target_talents.get(_current_player_data.unit_name, "")
	if talent_id != "":
		var data : TalentData = TalentManager.get_talent_data(talent_id)
		if data:
			var lv : int = TalentManager.get_talent_level(_current_player_data.unit_name, talent_id)
			if TalentManager.is_talent_max_level(_current_player_data.unit_name, talent_id):
				info_label.text = "目标词条：Lv.%d %s（MAX）" % [lv, data.display_name]
			else:
				var cur_exp : int = TalentManager.get_talent_exp_in_level(_current_player_data.unit_name, talent_id)
				var need_exp : int = TalentManager.get_level_required_exp(_current_player_data.unit_name, talent_id)
				info_label.text = "目标词条：Lv.%d %s（%d/%d）" % [lv, data.display_name, cur_exp, need_exp]
		else:
			info_label.text = ""
	else:
		info_label.text = "目标词条：未设置（可在商店配置）"

func _refresh_streak_label():
	if _phase == Phase.IDLE:
		streak_label.text = "通关：%d 次  |  当前魂：%d" % [
			GameState.arena_clear_count, GameState.soul
		]
	elif _phase == Phase.SURVIVAL:
		streak_label.text = "生存：%d / %d（不可撤离）  |  本局净：%+d 魂" % [
			_survival_round, SURVIVAL_ROUNDS, _get_net_gain()
		]
	else:
		var next_type : String = "普通"
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
#  音乐辅助
# ============================================================
func _restore_arena_music():
	if MusicManager.config and MusicManager.config.arena_music:
		MusicManager.play_arena_music()


# ============================================================
#  开始
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
	_earned_soul = 0
	_total_paid = 0
	_retreat_fee = 0
	_arena_passives = [null, null, null, null]
	_locked_talent_id = ""

	_current_player_data.reset_combat_buffs()
	_current_player_data.hit_points = _current_player_data.max_hp
	_current_player_data.max_armor_slots = 2
	_current_player_data.armor_slots = [null, null]

	var saved_talent : String = GameState.arena_target_talents.get(_current_player_data.unit_name, "")
	if saved_talent != "":
		_locked_talent_id = saved_talent

	_current_player_data.hit_points = _current_player_data.max_hp


func _grant_armor_slot_for_entry() -> void:
	if _current_player_data == null: return
	if _current_player_data.max_armor_slots >= GameState.MAX_ARMOR_SLOTS_CAP: return
	_current_player_data.max_armor_slots += 1
	while _current_player_data.armor_slots.size() < _current_player_data.max_armor_slots:
		_current_player_data.armor_slots.append(null)
	print("[Arena] 支付参与费：防具槽 → %d" % _current_player_data.max_armor_slots)


# ============================================================
#  主循环
# ============================================================
func _run_battle_loop():
	while _phase != Phase.END:
		var entry_choice : String = await _check_entry_fee()
		if not is_inside_tree():
			return
		if entry_choice == "decline":
			_show_summary(true, "及时止损")
			return

		var shop_action : String = await _show_shop()
		if not is_inside_tree():
			return
		if shop_action == "quit":
			if _streak == 0:
				_return_to_idle()
			else:
				_show_summary(true, "放弃")
			return

		var winner : int = await _do_one_battle()
		if not is_inside_tree():
			return

		if winner != 0:
			_show_summary(false, "失败", true)
			return

		_restore_arena_music()

		if _phase == Phase.NORMAL:
			_streak += 1
			_grant_progress_rewards()

			if _streak >= CLEAR_TARGET:
				_phase = Phase.CLEAR
				var choice : String = await _show_clear_panel()
				if not is_inside_tree():
					return
				if choice == "survival":
					_phase = Phase.SURVIVAL
					_survival_round = 0
				else:
					_apply_retreat_fee(RETREAT_FEE_AFTER_STREAK_4)
					_show_summary(true, "撤离")
					return

		elif _phase == Phase.SURVIVAL:
			_survival_round += 1
			if _survival_round >= SURVIVAL_ROUNDS:
				_show_summary(true, "生存通过", true)
				return

		SaveManager.auto_save()


func _apply_retreat_fee(fee: int):
	if fee <= 0:
		return
	if GameState.soul >= fee:
		GameState.soul -= fee
		_retreat_fee += fee
	else:
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

	var cost : int = 0
	if _streak == 2:
		cost = ENTRY_COST_MINI_BOSS
	else:
		return "accept"

	var choice : String = await _show_entry_fee_panel(cost)
	if choice != "accept":
		return "decline"

	if not _pay_soul(cost):
		return "decline"

	_grant_armor_slot_for_entry()

	SaveManager.auto_save()
	return "accept"


func _show_entry_fee_panel(cost: int) -> String:
	var scene = load(Config.PATHS.CONFIRM_UI)
	if not scene:
		return "decline"

	var ui = scene.instantiate()
	add_child(ui)

	var soul_now : int = GameState.soul
	var can_afford : bool = soul_now >= cost
	var reward_soul : int = SOUL_BY_STREAK[2]

	var msg : String = ""
	msg += "关键节点 · 小Boss\n"
	msg += "下一战难度提升\n\n"
	msg += "支付即得：+1 防具槽（可立即购物）\n"
	msg += "胜利奖励：+%d 魂 +金币\n" % reward_soul
	msg += "参与费：%d 魂\n" % cost
	msg += "当前魂：%d   金币：%d\n" % [soul_now, _arena_gold]

	var holder := {"value": ""}

	if can_afford:
		msg += "\n是否支付并继续？"
		ui.show_confirm(
			msg,
			"支付 %d 魂" % cost,
			"撤退",
			func(): holder["value"] = "accept",
			func(): holder["value"] = "decline",
			true,
			8
		)
	else:
		msg += "\n\n⚠ 魂不足，本局结束"
		ui.show_confirm(
			msg,
			"放弃",
			"",
			func(): holder["value"] = "decline",
			func(): pass,
			false,
			8
		)

	while is_instance_valid(ui) and holder["value"] == "":
		await get_tree().process_frame
	await get_tree().process_frame
	return holder["value"]


# ============================================================
#  商店
# ============================================================
func _show_shop() -> String:
	_restore_arena_music()

	var ctx := ArenaEquipContext.new()
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

	if ctx.was_cancelled():
		return "quit"

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

	var enemy_type : String = _roll_enemy()
	if enemy_type == "":
		push_error("敌人池为空")
		return 1

	var enemy_data : UnitData = UnitDataManager.create_unit_data(enemy_type)
	_apply_enemy_scaling(enemy_data)

	var gold_gain : int = _calc_gold_reward()
	var soul_gain : int = _calc_soul_reward()
	var exp_gain : int = _calc_exp_gain(enemy_type)

	var battle_index : int = _streak + 1
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
	var result : Dictionary = await battle.closed

	if not is_inside_tree():
		return 1

	if result.get("winner_team", 1) == 0:
		_arena_gold += gold_gain
		if soul_gain > 0:
			GameState.soul += soul_gain
			_earned_soul += soul_gain

		# ★ 所有已装备词条加经验
		var talent_results : Array = _add_talent_exp_to_all(exp_gain)

		_current_player_data.hit_points = _current_player_data.max_hp
		_streak_active = true
		SaveManager.auto_save()

		await _show_battle_rewards(gold_gain, soul_gain, talent_results, battle_index)
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
		var idx : int = mini(_survival_round, 2)
		return GOLD_SURVIVAL[idx]
	var i : int = mini(_streak, GOLD_BY_STREAK.size() - 1)
	return GOLD_BY_STREAK[i]


func _calc_soul_reward() -> int:
	if _phase == Phase.SURVIVAL:
		var idx : int = mini(_survival_round, 2)
		return SOUL_SURVIVAL[idx]
	var i : int = mini(_streak, SOUL_BY_STREAK.size() - 1)
	return SOUL_BY_STREAK[i]


func _calc_exp_gain(enemy_type: String) -> int:
	var base : int = _get_enemy_arena_exp(enemy_type)
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
		talent_results: Array, battle_index: int):
	var summary = Globals.get_reward_summary()
	if not summary:
		return

	var items : Array = []

	for r in talent_results:
		var tid : String = r["talent_id"]
		var data : TalentData = TalentManager.get_talent_data(tid)
		var tname : String = data.display_name if data else tid
		var old_lv : int = r["old_level"]
		var new_lv : int = r["new_level"]
		var old_in : int = r["old_in"]
		var old_need : int = r["old_need"]
		var new_in : int = r["new_in"]
		var new_need : int = r["new_need"]

		var exp_item := ItemData.new()
		exp_item.id = "arena_exp_" + tid
		if new_lv > old_lv:
			# ★ 升级
			exp_item.name = "★ %s 升级 Lv%d→Lv%d  (%d/%d → %d/%d)" % [
				tname, old_lv, new_lv, old_in, old_need, new_in, new_need]
		else:
			# ★ 未升级
			exp_item.name = "%s Lv%d 经验 +%d  (%d/%d → %d/%d)" % [
				tname, new_lv, r["exp_gain"], old_in, old_need, new_in, new_need]
		if data:
			exp_item.description = data.description
		items.append(exp_item)

	var title : String = "第 %d 战胜利" % battle_index
	if _phase == Phase.SURVIVAL:
		title = "生存 %d / %d 胜利" % [_survival_round + 1, SURVIVAL_ROUNDS]

	summary.setup_reward(gold_gain, soul_gain, items, false, title)
	summary.open()
	await summary.confirmed
	summary.close()


# ============================================================
#  进度奖励（精英后再 +1）
# ============================================================
func _grant_progress_rewards():
	if _phase != Phase.NORMAL:
		return
	if _streak == 4:
		if _current_player_data.max_armor_slots < GameState.MAX_ARMOR_SLOTS_CAP:
			_current_player_data.max_armor_slots += 1
			while _current_player_data.armor_slots.size() < _current_player_data.max_armor_slots:
				_current_player_data.armor_slots.append(null)
			print("[Arena] 精英胜利：防具槽 → %d" % _current_player_data.max_armor_slots)


func _is_elite_battle() -> bool:
	return _phase == Phase.NORMAL and _streak == 3


func _is_mini_boss_battle() -> bool:
	return _phase == Phase.NORMAL and _streak == 2


# ============================================================
#  敌人
# ============================================================
func _roll_enemy() -> String:
	var path : String = Config.PATHS.ARENA_ENEMIES
	if not FileAccess.file_exists(path):
		return ""
	var file = FileAccess.open(path, FileAccess.READ)
	var content : String = file.get_as_text()
	file.close()
	var data : Variant = JSON.parse_string(content)
	if data == null or not (data is Dictionary):
		return ""

	var pool_key : String = "easy"
	if _phase == Phase.SURVIVAL:
		if _survival_round == 0:
			pool_key = "elite"
		else:
			pool_key = "boss"
	elif _streak == 0:
		pool_key = "easy"
	elif _streak == 1:
		pool_key = "normal"
	elif _streak == 2:
		pool_key = "hard"
	else:
		pool_key = "elite"

	var data_dict : Dictionary = data
	var pool : Array = data_dict.get(pool_key, [])
	if pool.is_empty():
		pool = data_dict.get("normal", [])
		if pool.is_empty():
			pool = data_dict.get("easy", [])
		if pool.is_empty():
			return ""
	return pool[randi() % pool.size()]


func _apply_enemy_scaling(enemy_data: UnitData):
	var mult : float = 1.0
	if _phase == Phase.SURVIVAL:
		var idx : int = mini(_survival_round, ENEMY_SCALE_SURVIVAL.size() - 1)
		mult = ENEMY_SCALE_SURVIVAL[idx]
	else:
		var idx2 : int = mini(_streak, ENEMY_SCALE_BY_STREAK.size() - 1)
		mult = ENEMY_SCALE_BY_STREAK[idx2]

	enemy_data.max_hp = int(enemy_data.max_hp * mult)
	enemy_data.hit_points = enemy_data.max_hp
	enemy_data.strength = int(enemy_data.strength * mult)
	enemy_data.dexterity = int(enemy_data.dexterity * mult)


func _get_enemy_arena_exp(enemy_type: String) -> int:
	var unit_dict : Dictionary = UnitDataManager.get_unit_data(enemy_type)
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

	var soul_now : int = GameState.soul
	var can_afford : bool = soul_now >= ENTRY_COST_SURVIVAL
	var survival_soul_total : int = SOUL_SURVIVAL[0] + SOUL_SURVIVAL[1] + SOUL_SURVIVAL[2]
	var retreat_fee : int = RETREAT_FEE_AFTER_STREAK_4

	var msg : String = ""
	msg += "4 连胜达成！\n\n"
	msg += "已赚：+%d 魂  已付：-%d 魂\n" % [_earned_soul, _total_paid]
	msg += "当前魂：%d\n\n" % soul_now
	msg += "撤离：结算（-%d 魂手续费）\n" % retreat_fee
	msg += "生存：付 %d 魂，3 连 Boss\n" % ENTRY_COST_SURVIVAL
	msg += "通过后本局再 +%d 魂\n" % survival_soul_total
	if not can_afford:
		msg += "\n⚠ 魂不足（需 %d）" % ENTRY_COST_SURVIVAL

	var holder := {"value": ""}
	if can_afford:
		ui.show_confirm(
			msg,
			"付 %d 魂进入" % ENTRY_COST_SURVIVAL,
			"撤离（-%d 魂）" % retreat_fee,
			func(): holder["value"] = "survival",
			func(): holder["value"] = "settle",
			true,
			8
		)
	else:
		ui.show_confirm(
			msg,
			"撤离（-%d 魂）" % retreat_fee,
			"",
			func(): holder["value"] = "settle",
			func(): pass,
			false,
			8
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
func _show_summary(success: bool, reason: String, skip_music: bool = false):
	if not skip_music:
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

	summary.set_interactable(true)

	var net_gain : int = _get_net_gain()

	var items : Array = []

	if _earned_soul > 0:
		var i1 := ItemData.new()
		i1.id = "arena_earned"
		i1.name = "本局已赚 +%d 魂" % _earned_soul
		items.append(i1)

	if _total_paid > 0:
		var i2 := ItemData.new()
		i2.id = "arena_paid"
		i2.name = "参与费 -%d 魂" % _total_paid
		items.append(i2)

	if _retreat_fee > 0:
		var i3 := ItemData.new()
		i3.id = "arena_fee"
		i3.name = "撤离手续费 -%d 魂" % _retreat_fee
		items.append(i3)

	var tail_hint : String = ""
	match reason:
		"及时止损":
			tail_hint = "✅ 明智撤退，零损失"
		"撤离":
			tail_hint = "已提前离场，扣手续费 %d 魂" % _retreat_fee
		"生存通过":
			tail_hint = "★ 生存全通，硬核 Build 验证成功"
		"失败":
			tail_hint = "再来一次，试试不同 Build"
		"放弃":
			tail_hint = "已放弃本局，本局收益保留"
	if tail_hint != "":
		var hint_item := ItemData.new()
		hint_item.id = "arena_hint"
		hint_item.name = tail_hint
		items.append(hint_item)

	var title : String = "斗技场 · %s（净 %+d 魂）" % [reason, net_gain]

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
	_restore_arena_music()
	_build_unit_list()
	_refresh_center_panel()
	_refresh_streak_label()


func _show_hint(text: String):
	info_label.text = text
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(info_label) and is_inside_tree():
		_refresh_center_panel()


func _add_talent_exp_to_all(exp_gain: int) -> Array:
	var results : Array = []
	if not _current_player_data:
		return results
	var unit_name : String = _current_player_data.unit_name
	for inst in _current_player_data.talent_slots:
		if not inst or not inst.is_active:
			continue
		var tid : String = inst.talent_id
		var old_lv : int = TalentManager.get_talent_level(unit_name, tid)
		var old_in : int = TalentManager.get_talent_exp_in_level(unit_name, tid)
		var old_need : int = TalentManager.get_level_required_exp(unit_name, tid)
		var actual : int = TalentManager.add_talent_exp(unit_name, tid, exp_gain)
		if actual <= 0:
			continue
		var new_lv : int = TalentManager.get_talent_level(unit_name, tid)
		var new_in : int = TalentManager.get_talent_exp_in_level(unit_name, tid)
		var new_need : int = TalentManager.get_level_required_exp(unit_name, tid)
		results.append({
			"talent_id": tid,
			"exp_gain": actual,
			"old_level": old_lv,
			"old_in": old_in,
			"old_need": old_need,
			"new_level": new_lv,
			"new_in": new_in,
			"new_need": new_need,
		})
	return results
