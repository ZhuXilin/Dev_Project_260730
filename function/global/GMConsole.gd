extends CanvasLayer

var _commands : Dictionary = {}
var _history : Array[String] = []
var _history_idx : int = -1
var _enabled : bool = true

const DISABLED_SCENES : Array[String] = [
	"res://function/tool/editor/MapLayoutEditor.tscn",
	"res://function/tool/audio/ChipMusicValidator.tscn",
	"res://function/tool/audio/ChipMusicPreviewer.tscn",
	"res://function/tool/editor/ChipMusicEditor.tscn",
]

var _panel : PanelContainer
var _cmd_input : LineEdit
var _output : RichTextLabel
var _hint : Label


func _ready():
	if not OS.is_debug_build():
		queue_free()
		return

	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	_register_commands()
	print("[GMConsole] 就绪，按 ` 键打开")


func _build_ui():
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-200, -100)
	_panel.custom_minimum_size = Vector2(400, 200)
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_hint = Label.new()
	_hint.text = "GM 控制台 · help 查看命令 · Esc 关闭 · 快捷键 5/6/7/0/9"
	_hint.add_theme_font_size_override("font_size", 8)
	vbox.add_child(_hint)

	_output = RichTextLabel.new()
	_output.custom_minimum_size = Vector2(0, 140)
	_output.scroll_following = true
	_output.bbcode_enabled = true
	_output.add_theme_font_size_override("normal_font_size", 8)
	vbox.add_child(_output)

	_cmd_input = LineEdit.new()
	_cmd_input.placeholder_text = "输入命令..."
	_cmd_input.add_theme_font_size_override("font_size", 9)
	_cmd_input.text_submitted.connect(_on_submit)
	vbox.add_child(_cmd_input)


func _input(event: InputEvent):
	if not _enabled:
		return
	if _is_in_disabled_scene():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# ★ 检查是否正在输入框里打字，如果是，不响应快捷键
	var focus = get_viewport().gui_get_focus_owner()
	var is_typing = focus is LineEdit or focus is TextEdit or focus is SpinBox

	if event.keycode == KEY_QUOTELEFT or event.keycode == KEY_F12:
		_toggle()
		get_viewport().set_input_as_handled()
		return

	if visible:
		if event.keycode == KEY_ESCAPE:
			_toggle(false)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_UP and _cmd_input.has_focus():
			_nav_history(-1)
		elif event.keycode == KEY_DOWN and _cmd_input.has_focus():
			_nav_history(1)
		return

	if is_typing:
		return

	if event.ctrl_pressed or event.alt_pressed:
		return
		
	_handle_hotkey(event.keycode)


func _is_in_disabled_scene() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var path := scene.scene_file_path
	if path == "":
		return false
	return path in DISABLED_SCENES


func _handle_hotkey(keycode: int):
	# ★ 去除了 Input.mouse_mode 的限制，允许战斗中隐藏鼠标时按快捷键
	var k = keycode
	if k == KEY_KP_0: k = KEY_0
	elif k == KEY_KP_5: k = KEY_5
	elif k == KEY_KP_6: k = KEY_6
	elif k == KEY_KP_7: k = KEY_7
	elif k == KEY_KP_9: k = KEY_9

	match k:
		KEY_5:
			_hotkey_soul()
			get_viewport().set_input_as_handled()
		KEY_6:
			_hotkey_gold()
			get_viewport().set_input_as_handled()
		KEY_7:
			_hotkey_soul_fire()
			get_viewport().set_input_as_handled()
		KEY_0:
			_hotkey_win()
			get_viewport().set_input_as_handled()
		KEY_9:
			_hotkey_lose()
			get_viewport().set_input_as_handled()


func _toggle(force: Variant = null):
	var target = (not visible) if force == null else force
	visible = target
	if target:
		_cmd_input.text = ""
		_cmd_input.grab_focus()
		Globals.is_dialogue_active = true
	else:
		Globals.is_dialogue_active = false


func _nav_history(dir: int):
	if _history.is_empty(): return
	_history_idx = clampi(_history_idx + dir, -1, _history.size() - 1)
	_cmd_input.text = "" if _history_idx == -1 else _history[_history_idx]


func _hotkey_soul():
	GameState.soul += 100
	print("[GM] 魂 +100 → %d" % GameState.soul)
	_refresh_all_ui()


func _hotkey_gold():
	var equip_ctx = _find_arena_equip_context()
	var arena = _find_arena()

	if equip_ctx != null:
		equip_ctx.arena_gold += 1000
		if arena != null:
			arena._arena_gold = equip_ctx.arena_gold
		print("[GM] 竞技场金币 +1000 → %d" % equip_ctx.arena_gold)
		_refresh_all_ui()
		return

	if arena != null:
		arena._arena_gold += 1000
		print("[GM] 竞技场金币 +1000 → %d" % arena._arena_gold)
		_refresh_all_ui()
		return

	if _is_in_run():
		EconomyManager.add_temp_gold(1000)
		print("[GM] 金币 +1000 → %d" % GameState.temp_gold)
		_refresh_all_ui()
		return

	print("[GM] 加金币只在局内或竞技场有效")


func _hotkey_soul_fire():
	var before : int = SoulFireManager.current
	var cap : int = SoulFireManager.get_max_carried()
	SoulFireManager.current = cap
	SoulFireManager._emit_changes()
	print("[GM] 魂火 %d → %d（拉满）" % [before, cap])
	_refresh_all_ui()


func _hotkey_win():
	_cmd_win([])


func _hotkey_lose():
	_cmd_lose([])


func _do_kill_team(team_id: int) -> int:
	var targets : Array = []
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.unit_stats.team_id != team_id: continue
		if u.hit_points <= 0: continue
		targets.append(u)

	var n = 0
	for u in targets:
		if not is_instance_valid(u): continue
		u.apply_damage(u.hit_points)
		UnitManager.unregister_unit(u)
		u.queue_free()
		n += 1
	return n


func register(cmd: String, handler: Callable, help_text: String, aliases: Array = []):
	_commands[cmd] = {"handler": handler, "help": help_text}
	for a in aliases:
		_commands[a] = {"handler": handler, "help": help_text}


func _register_commands():
	register("help", _cmd_help, "help  显示所有命令", ["?"])
	register("gold", _cmd_gold, "gold <数量>  修改金币（局内/竞技场）", ["g"])
	register("soul", _cmd_soul, "soul <数量>  修改魂", ["s"])
	register("sf", _cmd_soul_fire, "sf <数量>  修改当前魂火（上限内）", ["soul_fire"])
	register("sf_max", _cmd_soul_fire_max, "sf_max  魂火拉满")
	register("sf_level", _cmd_soul_fire_level, "sf_level <0-6>  设置魂火上限等级")
	register("sf_init", _cmd_soul_fire_init, "sf_init <0-3>  设置初始魂火等级")
	register("shop_level", _cmd_shop_level, "shop_level <0-5>  设置商店等级")
	register("sac", _cmd_sacrifice, "sac <n>  设置献祭次数", ["sacrifice"])
	register("whisper", _cmd_whisper, "whisper  打印当前低语")
	register("whisper_reset", _cmd_whisper_reset, "whisper_reset  重置本局低语")
	register("wave", _cmd_wave, "wave <1-3>  设置当前地图波次")
	register("reinforce", _cmd_reinforce, "reinforce <0-5>  设置当前地图增援数量")
	register("affinity", _cmd_affinity, "affinity <npc> <n>  设置 NPC 亲密度")
	register("unlock", _cmd_unlock, "unlock <unit|weapon|armor|item|talent|relic> <id|all>")
	register("unlock_all", _cmd_unlock_all, "unlock_all  解锁所有内容")
	register("unlock_route", _cmd_unlock_route, "unlock_route <route_id>  解锁派遣路线")
	register("aura_unlock", _cmd_aura_unlock, "aura_unlock <aura_id>  直接解锁光环")
	register("tutorial", _cmd_tutorial, "tutorial <0-3>  设置新手阶段")
	register("skip_tutorial", _cmd_skip_tutorial, "skip_tutorial  跳到新手结束", ["skip"])
	register("day", _cmd_day, "day <1-3>  设置天数")
	register("reset_cycle", _cmd_reset_cycle, "reset_cycle  重置本轮（保留永久资源）")
	register("kill_enemies", _cmd_kill_enemies, "kill_enemies  杀死所有敌人", ["ke"])
	register("kill_allies", _cmd_kill_allies, "kill_allies  杀死所有我方", ["ka"])
	register("win", _cmd_win, "win  直接胜利（无视胜利条件与波次）", ["w"])
	register("lose", _cmd_lose, "lose  直接失败", ["l"])
	register("god", _cmd_god, "god  我方 HP 设为 9999")
	register("goto", _cmd_goto, "goto <camp|map|arena|main>")
	register("blessing", _cmd_blessing, "blessing <unit> <attr> <level>")
	register("adv_class", _cmd_adv_class, "adv_class <unit_index>  给队伍成员转职")
	register("clear_adv_class", _cmd_clear_adv_class, "clear_adv_class  清空所有单位转职状态")
	register("max_armor", _cmd_max_armor, "max_armor <n>  全员防具槽 = n")
	register("speed", _cmd_speed, "speed <-2..4>  设置游戏速度")
	register("save", _cmd_save, "save  立即保存")
	register("clear", _cmd_clear, "clear  清空输出", ["cls"])
	register("dump_units", _cmd_dump_units, "dump_units  打印队伍所有单位的转职字段")
	register("fix_adv_talent", _cmd_fix_adv_talent, "fix_adv_talent  清理不一致的职业特技")
	register("analytics", _cmd_analytics, "analytics  输出埋点汇总到控制台")
	register("analytics_csv", _cmd_analytics_csv, "analytics_csv  导出埋点 CSV 到 user://")
	register("key", _cmd_key, "key <n>  修改当前死眠之钥数量（0-1）")
	register("tag_pin", _cmd_tag_pin, "tag_pin <tag|clear>  设置挂起的标签定向器")
	register("threshold", _cmd_threshold, "threshold <0|1>  开启/关闭魂火阈值调节")
	register("refine_relic", _cmd_refine_relic, "refine_relic <relic_id>  直接精炼指定遗物")


func _on_submit(text: String):
	text = text.strip_edges()
	if text == "": return
	_history.append(text)
	if _history.size() > 50: _history.pop_front()
	_history_idx = -1
	_output.append_text("[color=#888]>>> %s[/color]\n" % text)
	_execute(text)
	_cmd_input.text = ""


func _cmd_analytics_csv(_args: Array):
	AnalyticsLogger.export_csv()
	_out("已导出：user://analytics_runs.csv 与 user://analytics_arena.csv", "green")


func _cmd_analytics(_args: Array):
	AnalyticsLogger.dump_summary()
	_out("已输出汇总到控制台（F12 查看 Output）", "green")


func _execute(text: String):
	var parts = text.split(" ", false)
	if parts.is_empty(): return
	var cmd = parts[0].to_lower()
	var args = parts.slice(1)

	if not _commands.has(cmd):
		_out("未知命令：%s" % cmd, "red")
		return
	_commands[cmd]["handler"].call(args)


func _out(msg: String, color: String = "white"):
	_output.append_text("[color=%s]%s[/color]\n" % [color, msg])


func _cmd_help(_args: Array):
	_out("=== 可用命令 ===", "yellow")
	var seen = {}
	for k in _commands:
		var h : String = _commands[k]["help"]
		if h in seen: continue
		seen[h] = true
		_out("  " + h, "cyan")


func _cmd_gold(args: Array):
	if args.is_empty():
		_out("用法: gold <数量>", "red")
		return
	var n = _parse_int(args[0])

	var equip_ctx = _find_arena_equip_context()
	var arena = _find_arena()
	if equip_ctx != null:
		equip_ctx.arena_gold = maxi(0, equip_ctx.arena_gold + n)
		if arena != null: arena._arena_gold = equip_ctx.arena_gold
		_out("竞技场金币 %+d → %d" % [n, equip_ctx.arena_gold], "green")
		_refresh_all_ui()
		return
	if arena != null:
		arena._arena_gold = maxi(0, arena._arena_gold + n)
		_out("竞技场金币 %+d → %d" % [n, arena._arena_gold], "green")
		_refresh_all_ui()
		return

	if not _is_in_run():
		_out("加金币只在局内或竞技场有效", "yellow")
		return
	EconomyManager.add_temp_gold(n)
	_out("金币 %+d → %d" % [n, GameState.temp_gold], "green")
	_refresh_all_ui()


func _cmd_soul(args: Array):
	if args.is_empty():
		_out("用法: soul <数量>", "red"); return
	var n = _parse_int(args[0])
	GameState.soul = maxi(0, GameState.soul + n)
	_out("魂 %+d → %d" % [n, GameState.soul], "green")
	_refresh_all_ui()


func _cmd_soul_fire(args: Array):
	if args.is_empty():
		_out("用法: sf <数量>（可为负）", "red"); return
	var n = _parse_int(args[0])
	var before : int = SoulFireManager.current
	var cap : int = SoulFireManager.get_max_carried()
	SoulFireManager.current = clampi(before + n, 0, cap)
	SoulFireManager._emit_changes()
	_out("魂火 %+d → %d / %d" % [n, SoulFireManager.current, cap], "green")
	_refresh_all_ui()


func _cmd_soul_fire_max(_args: Array):
	var cap : int = SoulFireManager.get_max_carried()
	SoulFireManager.current = cap
	SoulFireManager._emit_changes()
	_out("魂火拉满 → %d / %d" % [SoulFireManager.current, cap], "green")
	_refresh_all_ui()


func _cmd_soul_fire_level(args: Array):
	if args.is_empty():
		_out("用法: sf_level <0-6>", "red"); return
	var n : int = clampi(_parse_int(args[0]), 0, SoulFireManager.MAX_CARRIED_LEVELS.size() - 1)
	SoulFireManager.altar_level = n
	GameState.soul_fire_altar_level = n
	var cap : int = SoulFireManager.get_max_carried()
	SoulFireManager.current = mini(SoulFireManager.current, cap)
	SoulFireManager._emit_changes()
	SaveManager.auto_save()
	_out("魂火上限等级 → Lv%d（上限 %d）" % [n, cap], "green")
	_refresh_all_ui()


func _cmd_soul_fire_init(args: Array):
	if args.is_empty():
		_out("用法: sf_init <0-3>", "red"); return
	var n : int = clampi(_parse_int(args[0]), 0, SoulFireManager.INITIAL_LEVELS.size() - 1)
	GameState.soul_fire_initial_level = n
	SaveManager.auto_save()
	_out("初始魂火等级 → Lv%d（每局开始 %d）" % [n, SoulFireManager.get_initial_soul_fire()], "green")
	_refresh_all_ui()


func _cmd_shop_level(args: Array):
	if args.is_empty():
		_out("用法: shop_level <0-5>", "red"); return
	var n : int = clampi(_parse_int(args[0]), 0, 5)
	GameState.shop_level = n
	SaveManager.auto_save()
	_out("商店等级 → Lv%d" % n, "green")
	_refresh_all_ui()


func _cmd_sacrifice(args: Array):
	if args.is_empty():
		_out("用法: sac <n>", "red"); return
	var n : int = maxi(0, _parse_int(args[0]))
	GameState.sacrifice_count = n
	SaveManager.auto_save()
	_out("献祭次数 → %d（下次奖励：%s）" % [
		n, str(SacrificeHelper.get_reward_preview(n + 1))], "green")


func _cmd_affinity(args: Array):
	if args.size() < 2:
		_out("用法: affinity <npc> <n>", "red"); return
	var npc : String = args[0]
	var n : int = maxi(0, _parse_int(args[1]))
	GameState.npc_affinity[npc] = n
	SaveManager.auto_save()
	_out("%s 亲密度 → %d" % [npc, n], "green")


func _cmd_unlock(args: Array):
	if args.size() < 2:
		_out("用法: unlock <类型> <id|all>", "red"); return
	var kind = args[0].to_lower()
	var target = args[1]
	match kind:
		"unit":
			if target == "all":
				for u in UnitDataManager.get_all_unit_ids(): Globals.unlock_unit(u)
				_out("解锁所有单位", "green")
			else:
				Globals.unlock_unit(target); _out("解锁单位 " + target, "green")
		"weapon", "armor", "item":
			if target == "all":
				for i in ItemManager.get_all_item_ids():
					var d = ItemManager.get_item_data(i)
					if d and (kind == "item" or d.type == kind):
						Globals.unlock_item(i)
				_out("解锁所有 " + kind, "green")
			else:
				Globals.unlock_item(target); _out("解锁物品 " + target, "green")
		"talent":
			if target == "all":
				for t in TalentManager.get_all_talent_ids(): Globals.unlock_talent(t)
				_out("解锁所有词条", "green")
			else:
				Globals.unlock_talent(target); _out("解锁词条 " + target, "green")
		"relic":
			if target == "all":
				for r in RelicManager.get_all_relic_ids(): RelicManager.unlock_relic(r)
				_out("解锁所有遗物", "green")
			else:
				RelicManager.unlock_relic(target); _out("解锁遗物 " + target, "green")
		_:
			_out("未知类型: " + kind, "red")
	SaveManager.auto_save()


func _cmd_unlock_all(_args: Array):
	_cmd_unlock(["unit", "all"])
	_cmd_unlock(["weapon", "all"])
	_cmd_unlock(["armor", "all"])
	_cmd_unlock(["talent", "all"])
	_cmd_unlock(["relic", "all"])
	_out("★ 全部解锁完成", "yellow")


func _cmd_unlock_route(args: Array):
	if args.is_empty():
		_out("用法: unlock_route <route_id>", "red")
		_out("可用: " + ", ".join(DispatchManager.ROUTES.keys()), "cyan")
		return
	var rid : String = args[0]
	if DispatchManager.unlock_route(rid):
		_out("解锁派遣路线: " + rid, "green")
	else:
		_out("失败：路线不存在或已解锁", "red")


func _cmd_aura_unlock(args: Array):
	if args.is_empty():
		_out("用法: aura_unlock <aura_id>", "red")
		_out("可用: " + ", ".join(AuraManager.get_all_ids()), "cyan")
		return
	var aid : String = args[0]
	if AuraManager.get_aura(aid).is_empty():
		_out("未知光环: " + aid, "red"); return
	if aid in GameState.unlocked_auras:
		_out("已解锁", "yellow"); return
	GameState.unlocked_auras.append(aid)
	SaveManager.auto_save()
	_out("解锁光环: " + aid, "green")


func _cmd_tutorial(args: Array):
	if args.is_empty():
		_out("用法: tutorial <0-3>", "red"); return
	var n = clampi(_parse_int(args[0]), 0, 3)
	GameState.tutorial_stage = n
	Globals.reload_talent_unlock()
	_out("新手阶段 → %d（已重载词条解锁）" % n, "green")


func _cmd_skip_tutorial(_args: Array):
	GameState.tutorial_stage = 3
	Globals.reload_talent_unlock()
	_out("★ 已跳过新手引导", "yellow")


func _cmd_day(args: Array):
	if args.is_empty():
		_out("用法: day <1-3>", "red"); return
	var n = clampi(_parse_int(args[0]), 1, 3)
	GameState.current_day = n
	LevelManager.current_day = n - 1
	_out("天数 → %d" % n, "green")


func _cmd_reset_cycle(_args: Array):
	GameState.reset_for_new_cycle()
	_out("已重置本轮（保留永久资源）", "yellow")


func _cmd_kill_enemies(_args: Array):
	if not _is_in_combat():
		_out("该场景无敌人可击杀", "yellow")
		return
	var n = _do_kill_team(1)
	TurnManager.check_victory()
	_out("已击杀 %d 个敌人" % n, "green")


func _cmd_kill_allies(_args: Array):
	if not _is_in_combat():
		_out("该场景无我方单位可击杀", "yellow")
		return
	var n = _do_kill_team(0)
	TurnManager.check_victory()
	_out("已击杀 %d 个我方" % n, "green")


func _cmd_win(_args: Array):
	if not _is_in_combat():
		_out("该场景不可用胜负命令", "yellow")
		return

	var arena_battle = _find_node_by_name("ArenaBattle")
	if arena_battle != null and is_instance_valid(arena_battle):
		arena_battle.set("_enemy_hp", 0)
		_out("★ 竞技场：强制胜利", "green")
		return

	var n = _do_kill_team(1)
	
	if WaveManager:
		WaveManager._pending_groups.clear()
		WaveManager._type_total_waves = 1
		
	if ObjectiveManager:
		ObjectiveManager.force_complete()

	TurnManager.check_victory()
	
	if not TurnManager.is_game_over:
		TurnManager._trigger_victory(0)
		
	_out("★ 战场：强制通关（击杀 %d 名敌人）" % n, "green")


func _cmd_lose(_args: Array):
	if not _is_in_combat():
		_out("该场景不可用胜负命令", "yellow")
		return

	var arena_battle = _find_node_by_name("ArenaBattle")
	if arena_battle != null and is_instance_valid(arena_battle):
		arena_battle.set("_player_hp", 0)
		_out("★ 竞技场：强制失败", "green")
		return

	var n = _do_kill_team(0)
	TurnManager.check_victory()
	
	_out("★ 战场：强制失败（击杀 %d 名我方）" % n, "green")


func _cmd_god(_args: Array):
	if not _is_in_combat():
		_out("该场景无我方单位", "yellow")
		return
	var n = 0
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.unit_stats.team_id == 0:
			u.unit_stats.max_hp = 9999
			u.hit_points = 9999
			u.update_hp_label()
			n += 1
	_out("我方 %d 个单位已无敌" % n, "yellow")


func _cmd_goto(args: Array):
	if args.is_empty():
		_out("用法: goto <camp|map|arena|main>", "red"); return
	match args[0].to_lower():
		"camp": get_tree().change_scene_to_file(Config.PATHS.CAMP)
		"map": get_tree().change_scene_to_file(Config.PATHS.MAP_SCENE)
		"arena": get_tree().change_scene_to_file(Config.PATHS.ARENA_UI)
		"main": get_tree().change_scene_to_file(Config.PATHS.MAIN_MENU)
		_: _out("未知场景", "red"); return
	_out("跳转 → " + args[0], "green")


func _cmd_blessing(args: Array):
	if args.size() < 3:
		_out("用法: blessing <unit> <attr> <level>", "red"); return
	var unit = args[0]
	var attr = args[1]
	var lv = clampi(_parse_int(args[2]), 0, 3)
	var key = UnitDataManager.normalize_unit_key(unit)
	if not GameState.unit_blessings.has(key): GameState.unit_blessings[key] = {}
	GameState.unit_blessings[key]["blessing_" + attr] = lv
	_out("祝福 %s.%s → Lv%d" % [unit, attr, lv], "green")


func _cmd_adv_class(args: Array):
	if args.is_empty():
		_out("用法: adv_class <unit_index>", "red"); return
	var idx = _parse_int(args[0])
	if idx < 0 or idx >= GameState.party.size():
		_out("索引越界", "red"); return
	var u = GameState.party[idx]
	var adv = AdvancedClassManager.get_class_for_unit(u.unit_name)
	if adv == null:
		_out("该单位无转职", "red"); return
	u.advanced_class = adv.id
	if adv.granted_talent != "":
		u.advanced_talent_id = adv.granted_talent
	for k in adv.stat_bonus:
		match k:
			"max_hp":
				u.max_hp += int(adv.stat_bonus[k])
				u.hit_points += int(adv.stat_bonus[k])
			"strength":     u.strength += int(adv.stat_bonus[k])
			"dexterity":    u.dexterity += int(adv.stat_bonus[k])
			"intelligence": u.intelligence += int(adv.stat_bonus[k])
			"faith":        u.faith += int(adv.stat_bonus[k])
			"arcane":       u.arcane += int(adv.stat_bonus[k])
			"move_range":   u.move_range += int(adv.stat_bonus[k])
	if adv.sprite_frames_path != "":
		u.override_sprite_path = adv.sprite_frames_path
	SaveManager.auto_save()
	_out("%s → %s" % [u.display_name, adv.name], "green")


func _cmd_clear_adv_class(_args: Array):
	for u in GameState.party:
		u.advanced_class = ""
		u.advanced_talent_id = ""
		u.advanced_talent_inst = null
	SaveManager.auto_save()
	_out("已清空所有单位的转职状态（%d 个）" % GameState.party.size(), "yellow")


func _cmd_max_armor(args: Array):
	if args.is_empty():
		_out("用法: max_armor <n>", "red"); return
	var n = clampi(_parse_int(args[0]), 0, 10)
	for u in GameState.party:
		u.max_armor_slots = n
		while u.armor_slots.size() < n:
			u.armor_slots.append(null)
	_out("全员防具槽 → %d" % n, "green")


func _cmd_speed(args: Array):
	if args.is_empty():
		_out("用法: speed <-2..4>", "red"); return
	Globals.set_game_speed(_parse_int(args[0]))
	_out("速度 → %d" % Globals.game_speed, "green")


func _cmd_save(_args: Array):
	SaveManager.auto_save()
	_out("已保存", "green")


func _cmd_clear(_args: Array):
	_output.clear()


func _cmd_dump_units(_args: Array):
	_out("=== 队伍单位 ===", "yellow")
	for i in range(GameState.party.size()):
		var u : UnitData = GameState.party[i]
		_out("[%d] %s/%s" % [i, u.unit_name, u.display_name], "cyan")
		_out("    advanced_class = '%s'" % u.advanced_class, "white")
		_out("    advanced_talent_id = '%s'" % u.advanced_talent_id, "white")
		_out("    override_sprite_path = '%s'" % u.override_sprite_path, "white")
	_out("=== 结束 ===", "yellow")


func _cmd_fix_adv_talent(_args: Array):
	var fixed : int = 0
	for u in GameState.party:
		if u.advanced_class == "" and u.advanced_talent_id != "":
			u.advanced_talent_id = ""
			u.advanced_talent_inst = null
			fixed += 1
			print("[GM] 清理 %s 的不一致职业特技" % u.display_name)
	SaveManager.auto_save()
	_out("已清理 %d 个不一致的职业特技" % fixed, "yellow")


const REFRESH_METHODS : Array = [
	"refresh_gm_display",
	"update_all_displays",
	"update_display",
	"_refresh_soul",
	"_refresh_streak_label",
	"_refresh_center_panel",
	"_update_soul_fire_display",
]

func _refresh_all_ui():
	_refresh_ui_recursive(get_tree().root)


func _refresh_ui_recursive(node: Node):
	if not is_instance_valid(node):
		return
	for method in REFRESH_METHODS:
		if node.has_method(method):
			node.call(method)
	for child in node.get_children():
		_refresh_ui_recursive(child)


func _find_arena() -> Node:
	var scene = get_tree().current_scene
	if scene == null:
		return null
	if scene.name == "Arena":
		return scene
	for child in scene.get_children():
		if child.name == "Arena":
			return child
	return null


func _find_arena_equip_context() -> EquipContext:
	var main_panel = _recursive_find_by_script(get_tree().root, "EquipmentConfig.gd")
	if main_panel == null:
		return null
	var ctx = main_panel.get("_context")
	if ctx and ctx is EquipContext and ctx.get_context_id() == "arena":
		return ctx
	return null


func _is_in_run() -> bool:
	var scene = get_tree().current_scene
	if scene == null:
		return false
	var path = scene.scene_file_path
	if path == "":
		return false
	return path.contains("MapScene") or path.contains("Battlefield")


func _is_in_combat() -> bool:
	var arena_battle = _find_node_by_name("ArenaBattle")
	if arena_battle != null and is_instance_valid(arena_battle):
		return true

	var scene = get_tree().current_scene
	if scene == null:
		return false
	var path = scene.scene_file_path
	if not path.contains("Battlefield"):
		return false
	if Globals.is_non_combat_mode:
		return false
	return true


func _find_node_by_name(node_name: String) -> Node:
	return _recursive_find(get_tree().root, node_name)


func _recursive_find(node: Node, target_name: String) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found = _recursive_find(child, target_name)
		if found != null:
			return found
	return null


func _recursive_find_by_script(node: Node, script_name: String) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	var s = node.get_script()
	if s and s.resource_path.ends_with(script_name):
		return node
	for child in node.get_children():
		var found = _recursive_find_by_script(child, script_name)
		if found != null:
			return found
	return null


func _parse_int(s: String) -> int:
	s = s.strip_edges()
	if s.begins_with("+"): s = s.substr(1)
	return int(s) if s.is_valid_int() else 0


func _cmd_key(args: Array):
	if args.is_empty():
		_out("用法: key <数量>", "red")
		return
	var n = _parse_int(args[0])
	GameState.keys = clampi(GameState.keys + n, 0, 1)
	SaveManager.auto_save()
	_out("死眠之钥 %+d → %d / 1" % [n, GameState.keys], "green")


func _cmd_whisper(_args: Array):
	var intel : Array = GameState.revealed_intel
	var hints : Array = GameState.fusion_hints
	var effects : Array = GameState.active_narrative_effects

	if intel.is_empty() and hints.is_empty() and effects.is_empty():
		_out("本局尚无低语 / 情报 / 熔合提示", "yellow")
		return

	if not effects.is_empty():
		_out("生效中效果: %d" % effects.size(), "white")
		for e in effects:
			_out("  - " + str(e), "white")

	if not intel.is_empty():
		_out("Boss 情报: %d 条" % intel.size(), "yellow")
		for t in intel:
			_out("  · " + str(t), "yellow")

	if not hints.is_empty():
		_out("熔合提示: %d 条" % hints.size(), "yellow")
		for h in hints:
			_out("  · " + str(h), "yellow")


func _cmd_whisper_reset(_args: Array):
	GameState.active_narrative_effects.clear()
	GameState.revealed_intel.clear()
	GameState.fusion_hints.clear()
	_out("已清空本局低语效果 / 情报 / 熔合提示", "green")


func _cmd_wave(args: Array):
	if args.is_empty():
		_out("用法: wave <1-3>", "red")
		return
	var n : int = clampi(_parse_int(args[0]), 1, 3)
	if GameState.current_map_data == null:
		_out("当前没有地图（仅在 Battlefield 场景可用）", "yellow")
		return
	GameState.current_map_data.max_waves = n
	if WaveManager:
		WaveManager.reset()
		WaveManager.setup_for_node(GameState.current_map_data, get_tree().current_scene)
	_out("当前地图波次 → %d" % n, "green")


func _cmd_reinforce(args: Array):
	if args.is_empty():
		_out("用法: reinforce <0-5>", "red")
		return
	var n : int = clampi(_parse_int(args[0]), 0, 5)
	if GameState.current_map_data == null:
		_out("当前没有地图（仅在 Battlefield 场景可用）", "yellow")
		return
	GameState.current_map_data.reinforcement_count = n
	_out("当前地图增援数量 → %d（需再进一次波次才生效）" % n, "green")


func _cmd_tag_pin(args: Array):
	if args.is_empty():
		_out("用法: tag_pin <守护|烈焰|灰烬|轮回|献祭|余烬|clear>", "red")
		return
	if args[0] == "clear":
		GameState.pending_tag_pin = ""
		GameState.active_tag_pin = ""
		_out("已清除标签定向器", "green")
		return
	GameState.pending_tag_pin = args[0]
	_out("挂起标签定向器 → %s（下一局生效）" % args[0], "green")


func _cmd_threshold(args: Array):
	if args.is_empty():
		_out("用法: threshold <0|1>", "red")
		return
	if args[0] == "0":
		GameState.soul_fire_threshold_override = 0.0
		_out("魂火阈值调节器：关闭", "green")
	else:
		GameState.soul_fire_threshold_override = 0.4
		_out("魂火阈值调节器：燃烧线 → 40%%", "green")


func _cmd_refine_relic(args: Array):
	if args.is_empty():
		_out("用法: refine_relic <relic_id>", "red")
		_out("可用: " + ", ".join(RelicManager.get_all_relic_ids()), "cyan")
		return
	var rid : String = args[0]
	if RelicManager.get_relic_data(rid).is_empty():
		_out("未知遗物: " + rid, "red")
		return
	if GameState.is_relic_refined(rid):
		_out("已精炼", "yellow")
		return
	GameState.relic_levels[rid] = 1
	SaveManager.auto_save()
	_out("已精炼: " + rid, "green")
	_refresh_all_ui()
