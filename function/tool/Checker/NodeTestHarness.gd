extends CanvasLayer

# ============================================================
#  NodeTestHarness — 节点测试工具
#  - 路径：res://function/tool/Checker/NodeTestHarness.gd
#  - 注册：project.godot autoload
#  - 热键：数字 1 开关，Esc 关闭
#  - 存档保护：默认开启，无法关闭
# ============================================================

# ============================================================
#  节点类型定义
# ============================================================
const NODE_TYPES : Array = [
	MapNode.NodeType.START,
	MapNode.NodeType.NORMAL,
	MapNode.NodeType.ELITE,
	MapNode.NodeType.BOSS,
	MapNode.NodeType.SHOP,
	MapNode.NodeType.FORGE,
	MapNode.NodeType.TREASURE,
	MapNode.NodeType.CHAPEL,
]

const EquipmentConfigScript = preload(Config.PATHS.EQUIPMENT_CONFIG_SCRIPT)

# ============================================================
#  状态
# ============================================================
var _selected_type : MapNode.NodeType = MapNode.NodeType.NORMAL
var _selected_map : MapData = null
var _built : bool = false
var _protect_hint : Label = null

# LevelList 选择
var _selected_levellist : LevelListResource = null
var _levellist_path : String = ""
var _levellist_btn : Button = null

# ============================================================
#  节点引用
# ============================================================
@onready var type_list : VBoxContainer = $Panel/VBox/MainHBox/LeftColumn/TypeScroll/TypeList
@onready var map_list : VBoxContainer = $Panel/VBox/MainHBox/MidColumn/MapScroll/MapList
@onready var info_label : Label = $Panel/VBox/InfoBar/InfoLabel
@onready var launch_btn : Button = $Panel/VBox/BottomBar/LaunchBtn
@onready var setup_party_btn : Button = $Panel/VBox/BottomBar/SetupPartyBtn
@onready var close_btn : Button = $Panel/VBox/BottomBar/CloseBtn
@onready var party_label : Label = $Panel/VBox/TopBar/PartyLabel


# ============================================================
#  生命周期
# ============================================================
func _ready():
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if visible and event.keycode == KEY_ESCAPE:
		_toggle(false)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_1:
		var focus = get_viewport().gui_get_focus_owner()
		if focus and (focus is LineEdit or focus is TextEdit):
			return
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle(force = null):
	var target : bool = (not visible) if force == null else force
	if target:
		SaveManager.suppress_save = true
		if not _built:
			_build_all()
			_built = true
		_build_type_list()
		_build_map_list()
		_refresh_party_label()
		_refresh_protect_hint()
		_update_levellist_btn_text()
	visible = target


func _build_all():
	launch_btn.pressed.connect(_on_launch)
	setup_party_btn.pressed.connect(_on_setup_party)
	close_btn.pressed.connect(_on_close)

	var top_bar : HBoxContainer = $Panel/VBox/TopBar
	_levellist_btn = Button.new()
	_levellist_btn.text = "关卡池"
	_levellist_btn.add_theme_font_size_override("font_size", 7)
	_levellist_btn.clip_text = true
	_levellist_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_levellist_btn.custom_minimum_size = Vector2(70, 0)
	_levellist_btn.tooltip_text = "选择一个 LevelList，候选地图从它拉取"
	_levellist_btn.pressed.connect(_on_pick_levellist)
	top_bar.add_child(_levellist_btn)
	var spacer = top_bar.get_node_or_null("Spacer")
	if spacer:
		top_bar.move_child(_levellist_btn, spacer.get_index())

	var info_bar : HBoxContainer = info_label.get_parent()
	_protect_hint = Label.new()
	_protect_hint.add_theme_font_size_override("font_size", 7)
	_protect_hint.modulate = Color(1.0, 0.85, 0.3)
	info_bar.add_child(_protect_hint)
	_refresh_protect_hint()
	_update_levellist_btn_text()


func _refresh_protect_hint():
	if not _protect_hint:
		return
	_protect_hint.text = "⚠️ 存档保护中" if SaveManager.suppress_save else "存档：正常"


func _update_levellist_btn_text():
	if not _levellist_btn:
		return
	if _levellist_path != "":
		var fname : String = _levellist_path.get_file()
		if fname.ends_with(".tres"):
			fname = fname.substr(0, fname.length() - 5)
		_levellist_btn.text = _truncate(fname, 14)
		_levellist_btn.tooltip_text = _levellist_path
	else:
		_levellist_btn.text = "关卡池"
		_levellist_btn.tooltip_text = "选择一个 LevelList，候选地图从它拉取"


func _truncate(s: String, max_len: int) -> String:
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len - 1) + "…"


# ============================================================
#  Day 推断
# ============================================================
func _get_day() -> int:
	if _levellist_path == "":
		return 1
	var fname : String = _levellist_path.get_file().to_lower()
	if "day3" in fname: return 3
	if "day2" in fname: return 2
	if "day1" in fname: return 1
	return 1


# ============================================================
#  LevelList 选择
# ============================================================
func _on_pick_levellist():
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.add_filter("*.tres", "Tres 文件")
	fd.use_native_dialog = true
	fd.current_dir = "res://content/scenes/levels/levellists/"
	fd.title = "选择 LevelList 文件"
	fd.file_selected.connect(func(path):
		var res = load(path)
		if res == null:
			push_warning("加载失败: " + path)
			fd.queue_free()
			return
		if not (res is LevelListResource):
			push_warning("选中的不是 LevelList 资源: " + path)
			Globals.show_confirm(
				self,
				"选中的文件不是关卡池（LevelList）\n请选择 levellists/ 目录下的 .tres 文件",
				"确定", "", func(): pass, func(): pass, false
			)
			fd.queue_free()
			return
		_selected_levellist = res
		_levellist_path = path
		_update_levellist_btn_text()
		_build_map_list()
		print("[NodeTestHarness] 已加载 LevelList: ", path, " day=", _get_day())
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(500, 400))


# ============================================================
#  左侧：节点类型
# ============================================================
func _build_type_list():
	for child in type_list.get_children():
		type_list.remove_child(child)
		child.queue_free()

	for t in NODE_TYPES:
		var btn := Button.new()
		btn.text = MapConst.get_node_display_name(t)
		btn.toggle_mode = true
		btn.button_pressed = (t == _selected_type)
		btn.add_theme_font_size_override("font_size", 8)
		btn.clip_text = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_type_selected.bind(t))
		type_list.add_child(btn)


func _on_type_selected(node_type: MapNode.NodeType):
	_selected_type = node_type
	_selected_map = null
	_build_type_list()
	_build_map_list()
	_update_info()


# ============================================================
#  中间：候选地图
# ============================================================
func _build_map_list():
	for child in map_list.get_children():
		map_list.remove_child(child)
		child.queue_free()

	var pools : Array = _get_maps_for_type(_selected_type)

	if pools.is_empty():
		var hint := Label.new()
		hint.text = "（无候选）"
		hint.add_theme_font_size_override("font_size", 7)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.modulate = Color(0.6, 0.6, 0.6)
		map_list.add_child(hint)
		_update_info()
		return

	for m in pools:
		if m == null: continue
		var btn := Button.new()
		var label : String = m.map_name if m.map_name != "" else "（未命名）"
		btn.text = _truncate(label, 16)
		btn.tooltip_text = label
		btn.toggle_mode = true
		btn.button_pressed = (_selected_map == m)
		btn.add_theme_font_size_override("font_size", 8)
		btn.clip_text = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_map_selected.bind(m))
		map_list.add_child(btn)


func _on_map_selected(map_data: MapData):
	_selected_map = map_data
	_build_map_list()
	_update_info()


func _get_maps_for_type(node_type: MapNode.NodeType) -> Array:
	var result : Array = []

	if _selected_levellist and _selected_levellist.levels:
		for m in _selected_levellist.levels:
			if m and m.node_type == node_type:
				result.append(m)
		return result

	for day_idx in range(3):
		var levels = LevelManager.get_levels_for_day(day_idx + 1)
		for m in levels:
			if m and m.node_type == node_type:
				result.append(m)
	return result


func _update_info():
	if _selected_map:
		var s : String = "选中：%s（%s）" % [
			_selected_map.map_name,
			MapConst.get_node_display_name(_selected_map.node_type)
		]
		info_label.text = _truncate(s, 26)
		info_label.tooltip_text = s
	else:
		info_label.text = "选中类型：%s" % MapConst.get_node_display_name(_selected_type)
		info_label.tooltip_text = info_label.text


# ============================================================
#  队伍状态
# ============================================================
func _refresh_party_label():
	if GameState.party.is_empty():
		party_label.text = "队伍：空"
		party_label.tooltip_text = ""
		return
	var names : Array = []
	for u in GameState.party:
		names.append(u.display_name if u.display_name != "" else u.unit_name)
	var full : String = "队伍：%s" % ", ".join(names)
	party_label.text = _truncate(full, 16)
	party_label.tooltip_text = full


func _on_setup_party():
	GameState.party.clear()
	GameState.current_faction = "王国"
	var unit_keys : Array = ["swordsman", "spearman", "axeman"]
	for key in unit_keys:
		var ud : UnitData = UnitDataManager.create_unit_data(key)
		GameState.party.append(ud)
	GameState.main_unit_name = unit_keys[0]
	_refresh_party_label()
	info_label.text = "已生成测试队伍（3 人）"


# ============================================================
#  启动
# ============================================================
func _on_launch():
	if GameState.party.is_empty():
		info_label.text = "队伍为空，请先点「准备测试队伍」"
		return

	SaveManager.suppress_save = true
	_refresh_protect_hint()

	var map_to_use : MapData = _selected_map
	if map_to_use == null:
		map_to_use = MapData.new()
		map_to_use.map_name = "测试地图（%s）" % MapConst.get_node_display_name(_selected_type)
		map_to_use.node_type = _selected_type
		map_to_use.map_size = MapConst.DEFAULT_MAP_SIZE

	if _selected_type in [
		MapNode.NodeType.SHOP,
		MapNode.NodeType.FORGE,
		MapNode.NodeType.TREASURE,
		MapNode.NodeType.CHAPEL,
	]:
		GameState.current_map_data = map_to_use
		GameState.current_day = _get_day()
		_launch_non_combat()
		return

	GameState.current_map_data = map_to_use
	GameState.current_day = _get_day()
	GameState.is_map_mode = true
	Globals.is_map_mode = true
	Globals.reset_all_game_state()
	print("[NodeTestHarness] 启动战斗节点：%s（day=%d）" % [
		MapConst.get_node_display_name(_selected_type), _get_day()
	])
	visible = false
	get_tree().change_scene_to_file(Config.PATHS.LOADING)


# ============================================================
#  非战斗节点：直接弹 UI（含音乐）
# ============================================================
func _launch_non_combat():
	visible = false
	print("[NodeTestHarness] 启动非战斗节点：%s（day=%d）" % [
		MapConst.get_node_display_name(_selected_type), _get_day()
	])

	_play_non_combat_music()

	match _selected_type:
		MapNode.NodeType.SHOP:
			await _open_shop()
		MapNode.NodeType.FORGE:
			await _open_forge()
		MapNode.NodeType.TREASURE:
			await _open_treasure()
		MapNode.NodeType.CHAPEL:
			await _open_chapel()

	if is_instance_valid(self):
		visible = true
		_refresh_protect_hint()
		MusicManager.play_main_menu_music()


func _play_non_combat_music():
	if MusicManager == null or MusicManager.config == null:
		return
	var music_stream : AudioStream = null
	if MusicManager.config.non_combat_music:
		music_stream = MusicManager.config.non_combat_music
	elif MusicManager.config.map_music:
		music_stream = MusicManager.config.map_music
	if music_stream:
		MusicManager.play_music(music_stream)


func _open_shop():
	var config = load(Config.PATHS.EQUIPMENT_CONFIG).instantiate()
	add_child(config)
	var panel = config.get_node("MainPanel")
	var unit_names : Array[String] = _get_party_unit_names()
	var slot : int = -1
	panel.call("init", unit_names, slot, int(EquipmentConfigScript.Mode.SHOP))
	await panel.tree_exited


func _open_forge():
	var config = load(Config.PATHS.EQUIPMENT_CONFIG).instantiate()
	add_child(config)
	var panel = config.get_node("MainPanel")
	var unit_names : Array[String] = _get_party_unit_names()
	var slot : int = -1

	var mode_forge : int = int(EquipmentConfigScript.Mode.FORGE)
	var mode_rest : int = int(EquipmentConfigScript.Mode.MAP_SHOP_REST)

	if _get_day() >= 3:
		panel.call("init", unit_names, slot, mode_rest)
	else:
		panel.call("init", unit_names, slot, mode_forge)
	await panel.tree_exited


func _open_treasure():
	var scene = load(Config.PATHS.TREASURE_UI)
	if not scene:
		push_error("[NodeTestHarness] Treasure UI 未找到")
		return
	var treasure = scene.instantiate()
	add_child(treasure)
	treasure.setup(_get_day())
	await treasure.closed


func _open_chapel():
	var scene = load(Config.PATHS.CHAPEL_UI)
	if not scene:
		push_error("[NodeTestHarness] ChapelUI 未找到")
		return
	var ui = scene.instantiate()
	add_child(ui)
	await ui.closed


func _get_party_unit_names() -> Array[String]:
	var names : Array[String] = []
	for u in GameState.party:
		names.append(u.unit_name)
	return names


# ============================================================
#  关闭
# ============================================================
func _on_close():
	_toggle(false)
