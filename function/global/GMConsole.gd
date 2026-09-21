extends CanvasLayer
# 通用 GM 控制台
# 唤起：` 或 F12
# 快捷键：5=魂+100  6=金币+1000  7=全材料+20  0=胜利  9=失败

# ============================================================
#  状态
# ============================================================
var _commands : Dictionary = {}
var _history : Array[String] = []
var _history_idx : int = -1
var _enabled : bool = true

var _panel : PanelContainer
var _cmd_input : LineEdit
var _output : RichTextLabel
var _hint : Label


# ============================================================
#  生命周期
# ============================================================
func _ready():
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	_register_commands()
	print("[GMConsole] 就绪，按 ` 键打开")


# ============================================================
#  UI 构建
# ============================================================
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


# ============================================================
#  输入处理
# ============================================================
func _input(event: InputEvent):
	if not _enabled:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# ---- 1. 控制台开关 ----
	if event.keycode == KEY_QUOTELEFT or event.keycode == KEY_F12:
		_toggle()
		get_viewport().set_input_as_handled()
		return

	# ---- 2. 控制台已打开：只响应 Esc / 方向键 ----
	if visible:
		if event.keycode == KEY_ESCAPE:
			_toggle(false)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_UP and _cmd_input.has_focus():
			_nav_history(-1)
		elif event.keycode == KEY_DOWN and _cmd_input.has_focus():
			_nav_history(1)
		return

	# ---- 3. 控制台关闭时：数字键热键 ----
	if event.ctrl_pressed or event.alt_pressed:
		return
	_handle_hotkey(event.keycode)


func _handle_hotkey(keycode: int):
	# 小键盘兼容
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
			_hotkey_materials()
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


# ============================================================
#  热键处理
# ============================================================
func _hotkey_soul():
	GameState.soul += 100
	print("[GM] 魂 +100 → %d" % GameState.soul)
	_refresh_all_ui()


func _hotkey_gold():
	# ---- 1. 优先：竞技场商店（EquipmentConfig）----
	var equip_ctx = _find_arena_equip_context()
	var arena = _find_arena()

	if equip_ctx != null:
		equip_ctx.arena_gold += 1000
		if arena != null:
			arena._arena_gold = equip_ctx.arena_gold
		print("[GM] 竞技场金币 +1000 → %d" % equip_ctx.arena_gold)
		_refresh_all_ui()
		return

	# ---- 2. 竞技场主界面（未开商店）----
	if arena != null:
		arena._arena_gold += 1000
		print("[GM] 竞技场金币 +1000 → %d" % arena._arena_gold)
		_refresh_all_ui()
		return

	# ---- 3. 局内 ----
	if _is_in_run():
		EconomyManager.add_temp_gold(1000)
		print("[GM] 金币 +1000 → %d" % GameState.temp_gold)
		_refresh_all_ui()
		return

	print("[GM] 加金币只在局内或竞技场有效")


func _hotkey_materials():
	for mat_name in ["粗铁", "精钢", "秘银", "龙鳞"]:
		GameState.add_material(mat_name, 20)
	print("[GM] 全材料 +20")
	_refresh_all_ui()


func _hotkey_win():
	if not _is_in_combat():
		print("[GM] 该场景不可用胜负快捷键")
		return

	# 竞技场战斗
	var arena_battle = _find_node_by_name("ArenaBattle")
	if arena_battle != null and is_instance_valid(arena_battle):
		arena_battle.set("_enemy_hp", 0)
		print("[GM] 竞技场：敌方 HP 归零")
		return

	# 战场
	_do_kill_team(1)


func _hotkey_lose():
	if not _is_in_combat():
		print("[GM] 该场景不可用胜负快捷键")
		return

	var arena_battle = _find_node_by_name("ArenaBattle")
	if arena_battle != null and is_instance_valid(arena_battle):
		arena_battle.set("_player_hp", 0)
		print("[GM] 竞技场：我方 HP 归零")
		return

	_do_kill_team(0)


# ============================================================
#  核心击杀逻辑（统一入口，带 is_instance_valid 保护）
# ============================================================
## team_id = 0 杀我方，team_id = 1 杀敌方
func _do_kill_team(team_id: int) -> int:
	# ---- 1. 收集有效目标 ----
	var targets : Array = []
	for u in UnitManager.unit_list:
		if not is_instance_valid(u):
			continue
		if u.unit_stats.team_id != team_id:
			continue
		if u.hit_points <= 0:
			continue
		targets.append(u)

	# ---- 2. 逐个处理 ----
	var n = 0
	for u in targets:
		if not is_instance_valid(u):
			continue
		u.apply_damage(u.hit_points)
		UnitManager.unregister_unit(u)
		u.queue_free()
		n += 1

	# ---- 3. 胜负判定 ----
	if n > 0:
		TurnManager.check_victory()
	return n


# ============================================================
#  命令注册
# ============================================================
func register(cmd: String, handler: Callable, help_text: String, aliases: Array = []):
	_commands[cmd] = {"handler": handler, "help": help_text}
	for a in aliases:
		_commands[a] = {"handler": handler, "help": help_text}


func _register_commands():
	register("help", _cmd_help, "help  显示所有命令", ["?"])

	register("gold", _cmd_gold, "gold <数量>  修改金币（局内/竞技场）", ["g"])
	register("soul", _cmd_soul, "soul <数量>  修改魂", ["s"])
	register("mat", _cmd_material, "mat <材料名> <数量>  修改材料", ["material"])
	register("mat_all", _cmd_material_all, "mat_all <数量>  全材料 +N")

	register("unlock", _cmd_unlock, "unlock <unit|weapon|armor|item|talent|relic> <id|all>")
	register("unlock_all", _cmd_unlock_all, "unlock_all  解锁所有内容")

	register("tutorial", _cmd_tutorial, "tutorial <0-3>  设置新手阶段")
	register("skip_tutorial", _cmd_skip_tutorial, "skip_tutorial  跳到新手结束", ["skip"])
	register("day", _cmd_day, "day <1-3>  设置天数")
	register("reset_cycle", _cmd_reset_cycle, "reset_cycle  重置本轮（保留永久资源）")

	register("kill_enemies", _cmd_kill_enemies, "kill_enemies  杀死所有敌人", ["ke"])
	register("kill_allies", _cmd_kill_allies, "kill_allies  杀死所有我方", ["ka"])
	register("win", _cmd_win, "win  直接胜利", ["w"])
	register("lose", _cmd_lose, "lose  直接失败", ["l"])
	register("god", _cmd_god, "god  我方 HP 设为 9999")

	register("goto", _cmd_goto, "goto <camp|map|arena|main>")

	register("blessing", _cmd_blessing, "blessing <unit> <attr> <level>")
	register("adv_class", _cmd_adv_class, "adv_class <unit_index>  给队伍成员转职")
	register("max_armor", _cmd_max_armor, "max_armor <n>  全员防具槽 = n")

	register("speed", _cmd_speed, "speed <-2..4>  设置游戏速度")
	register("save", _cmd_save, "save  立即保存")
	register("clear", _cmd_clear, "clear  清空输出", ["cls"])


# ============================================================
#  命令解析与执行
# ============================================================
func _on_submit(text: String):
	text = text.strip_edges()
	if text == "": return
	_history.append(text)
	if _history.size() > 50: _history.pop_front()
	_history_idx = -1
	_output.append_text("[color=#888]>>> %s[/color]\n" % text)
	_execute(text)
	_cmd_input.text = ""


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


# ============================================================
#  命令实现
# ============================================================
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

	# 竞技场商店
	var equip_ctx = _find_arena_equip_context()
	var arena = _find_arena()
	if equip_ctx != null:
		equip_ctx.arena_gold = maxi(0, equip_ctx.arena_gold + n)
		if arena != null:
			arena._arena_gold = equip_ctx.arena_gold
		_out("竞技场金币 %+d → %d" % [n, equip_ctx.arena_gold], "green")
		_refresh_all_ui()
		return
	if arena != null:
		arena._arena_gold = maxi(0, arena._arena_gold + n)
		_out("竞技场金币 %+d → %d" % [n, arena._arena_gold], "green")
		_refresh_all_ui()
		return

	# 局内
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


func _cmd_material(args: Array):
	if args.size() < 2:
		_out("用法: mat <材料名> <数量>", "red"); return
	var mat_name = args[0]
	var n = _parse_int(args[1])
	GameState.add_material(mat_name, n)
	_out("%s %+d → %d" % [mat_name, n, GameState.get_material(mat_name)], "green")
	_refresh_all_ui()


func _cmd_material_all(args: Array):
	var n = _parse_int(args[0]) if not args.is_empty() else 10
	for mat in ["粗铁", "精钢", "秘银", "龙鳞"]:
		GameState.add_material(mat, n)
	_out("全材料 +%d" % n, "green")
	_refresh_all_ui()


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
	_out("已击杀 %d 个敌人" % n, "green")


func _cmd_kill_allies(_args: Array):
	if not _is_in_combat():
		_out("该场景无我方单位可击杀", "yellow")
		return
	var n = _do_kill_team(0)
	_out("已击杀 %d 个我方" % n, "green")


func _cmd_win(_args: Array):
	if not _is_in_combat():
		_out("该场景不可用胜负命令", "yellow")
		return
	_cmd_kill_enemies([])


func _cmd_lose(_args: Array):
	if not _is_in_combat():
		_out("该场景不可用胜负命令", "yellow")
		return
	_cmd_kill_allies([])


func _cmd_god(_args: Array):
	if not _is_in_combat():
		_out("该场景无我方单位", "yellow")
		return
	var n = 0
	for u in UnitManager.unit_list:
		if not is_instance_valid(u):
			continue
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


# ============================================================
#  通用 UI 刷新
# ============================================================
const REFRESH_METHODS : Array = [
	"refresh_gm_display",
	"update_all_displays",
	"update_display",
	"_refresh_soul",
	"_refresh_materials",
	"_update_gold_display",
	"_refresh_streak_label",
	"_refresh_center_panel",
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


# ============================================================
#  场景 / 节点查找辅助
# ============================================================
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


## 是否处于"可判定胜负"的战斗中
## Arena 战斗 或 战场战斗 → true
func _is_in_combat() -> bool:
	# Arena 战斗
	var arena_battle = _find_node_by_name("ArenaBattle")
	if arena_battle != null and is_instance_valid(arena_battle):
		return true

	# 战场：必须是 Battlefield 场景且非非战斗模式
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


# ============================================================
#  辅助
# ============================================================
func _parse_int(s: String) -> int:
	s = s.strip_edges()
	if s.begins_with("+"): s = s.substr(1)
	return int(s) if s.is_valid_int() else 0
