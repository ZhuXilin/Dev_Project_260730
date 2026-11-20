extends TestPlugin

var _mode : String = "map"
var _mode_buttons : Dictionary = {}


func get_key() -> String: return "hero_shrine"
func get_category() -> String: return "流程"
func get_display_name() -> String: return "英灵殿"


func build_params(container: VBoxContainer, on_ready: Callable):
	container.add_child(_make_label("转职界面测试"))

	var info := _make_label("自动补全前置（若队伍为空则生成测试队伍）", 7)
	info.modulate = Color(0.7, 0.7, 0.7)
	container.add_child(info)

	var mode_row := HBoxContainer.new()
	mode_row.add_child(_make_label("模式："))

	var btn_map := _make_button("地图")
	btn_map.toggle_mode = true
	btn_map.button_pressed = (_mode == "map")
	btn_map.pressed.connect(func(): _set_mode("map"))
	mode_row.add_child(btn_map)
	_mode_buttons["map"] = btn_map

	var btn_arena := _make_button("竞技场")
	btn_arena.toggle_mode = true
	btn_arena.button_pressed = (_mode == "arena")
	btn_arena.pressed.connect(func(): _set_mode("arena"))
	mode_row.add_child(btn_arena)
	_mode_buttons["arena"] = btn_arena

	container.add_child(mode_row)
	on_ready.call()


func _set_mode(m: String):
	_mode = m
	for k in _mode_buttons:
		_mode_buttons[k].button_pressed = (k == m)


func validate() -> String:
	return ""


func launch():
	_ensure_party()
	var scene = load(Config.PATHS.HERO_SHRINE_UI)
	if not scene:
		push_error("HeroShrineUI 未找到")
		return
	var ui = scene.instantiate()
	_attach_to_root(ui)   # ★ 用基类方法
	if _mode == "arena" and not GameState.party.is_empty():
		ui.setup_arena(null, GameState.party[0])
	else:
		ui.setup_map(1)
	await ui.closed


func _ensure_party():
	if not GameState.party.is_empty():
		return
	for key in ["swordsman", "spearman", "axeman"]:
		GameState.party.append(UnitDataManager.create_unit_data(key))
	GameState.main_unit_name = "swordsman"


func get_status_text() -> String:
	if GameState.party.is_empty():
		return "队伍为空"
	return "队伍 %d 人 / 模式 %s" % [GameState.party.size(), _mode]
