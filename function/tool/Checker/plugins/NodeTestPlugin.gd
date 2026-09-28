extends TestPlugin

# ============================================================
#  NodeTestPlugin — 节点测试
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
var _selected_levellist : LevelListResource = null
var _levellist_path : String = ""

# UI 引用
var _type_list : VBoxContainer = null
var _map_list : VBoxContainer = null
var _levellist_btn : Button = null
var _party_label : Label = null
var _on_ready : Callable = Callable()


# ============================================================
#  TestPlugin 接口
# ============================================================
func get_key() -> String: return "node"
func get_category() -> String: return "节点"
func get_display_name() -> String: return "节点测试"


func get_status_text() -> String:
	if _selected_map:
		return "地图：" + _truncate(_selected_map.map_name, 12)
	return "类型：" + MapConst.get_node_display_name(_selected_type)


func validate() -> String:
	if GameState.party.is_empty():
		return "队伍为空，请先点「准备队伍」"
	return ""


# ============================================================
#  参数区构建
# ============================================================
func build_params(container: VBoxContainer, on_ready: Callable):
	_on_ready = on_ready

	# ---------- 顶部工具行 ----------
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)

	_levellist_btn = _make_button("关卡池", 6)   # ★ 字号 6
	_levellist_btn.clip_text = true
	_levellist_btn.custom_minimum_size = Vector2(60, 0)
	_levellist_btn.pressed.connect(_on_pick_levellist)
	top.add_child(_levellist_btn)

	var party_btn := _make_button("准备队伍", 6)   # ★ 字号 6
	party_btn.pressed.connect(_on_setup_party)
	top.add_child(party_btn)

	_party_label = Label.new()
	_party_label.add_theme_font_size_override("font_size", 7)
	_party_label.text = "队伍：空"
	_party_label.clip_text = true
	_party_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_party_label)

	container.add_child(top)

	# 主体：类型 + 地图
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 4)

	# 左：类型
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(60, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.custom_minimum_size = Vector2(0, 100)   # ★ 关键，避免高度塌陷
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_type_list = VBoxContainer.new()
	_type_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type_list.add_theme_constant_override("separation", 0)
	left_scroll.add_child(_type_list)
	left.add_child(left_scroll)
	hbox.add_child(left)

	# 中：地图
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mid_scroll := ScrollContainer.new()
	mid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_scroll.custom_minimum_size = Vector2(0, 100)   # ★ 关键，避免高度塌陷
	mid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_map_list = VBoxContainer.new()
	_map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_list.add_theme_constant_override("separation", 0)
	mid_scroll.add_child(_map_list)
	mid.add_child(mid_scroll)
	hbox.add_child(mid)

	container.add_child(hbox)

	# ---------- 初始化 ----------
	_refresh_party_label()
	_refresh_levellist_btn()
	_build_type_list()
	_build_map_list()
	_notify_status_changed()


# ============================================================
#  UI 构建
# ============================================================
func _refresh_levellist_btn():
	if _levellist_btn == null:
		return
	if _levellist_path != "":
		var fname : String = _levellist_path.get_file()
		if fname.ends_with(".tres"):
			fname = fname.substr(0, fname.length() - 5)
		_levellist_btn.text = _truncate(fname, 12)
		_levellist_btn.tooltip_text = _levellist_path
	else:
		_levellist_btn.text = "关卡池"
		_levellist_btn.tooltip_text = "选择 LevelList"


func _refresh_party_label():
	if _party_label == null:
		return
	if GameState.party.is_empty():
		_party_label.text = "队伍：空"
		_party_label.tooltip_text = ""
		return
	var names : Array = []
	for u in GameState.party:
		names.append(u.display_name if u.display_name != "" else u.unit_name)
	var full : String = "队伍：%s" % ", ".join(names)
	_party_label.text = _truncate(full, 20)
	_party_label.tooltip_text = full


func _build_type_list():
	if _type_list == null:
		return
	_clear(_type_list)
	for t in NODE_TYPES:
		var btn := _make_button(MapConst.get_node_display_name(t), 7)
		btn.toggle_mode = true
		btn.button_pressed = (t == _selected_type)
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(0, 12)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("node_type", t)
		btn.pressed.connect(func(): _on_type_selected(t))
		_type_list.add_child(btn)


func _build_map_list():
	if _map_list == null:
		return
	_clear(_map_list)
	var pools : Array = _get_maps_for_type(_selected_type)

	if pools.is_empty():
		var hint := _make_label("（无候选）", 7)
		hint.modulate = Color(0.6, 0.6, 0.6)
		_map_list.add_child(hint)
		return

	for m in pools:
		if m == null: continue
		var label : String = m.map_name if m.map_name != "" else "（未命名）"
		var btn := _make_button(_truncate(label, 14), 7)
		btn.tooltip_text = label
		btn.toggle_mode = true
		btn.button_pressed = (_selected_map == m)
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(0, 12)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("map_ref", m)
		btn.pressed.connect(func(): _on_map_selected(m))
		_map_list.add_child(btn)


# ============================================================
#  回调
# ============================================================
func _on_type_selected(node_type: MapNode.NodeType):
	_selected_type = node_type
	_selected_map = null

	for child in _type_list.get_children():
		if child is Button:
			var b : Button = child
			var t_meta = b.get_meta("node_type", null)
			b.button_pressed = (t_meta == node_type)

	_build_map_list()
	_notify_status_changed()
	if _on_ready.is_valid():
		_on_ready.call()


func _on_map_selected(map_data: MapData):
	_selected_map = map_data

	for child in _map_list.get_children():
		if child is Button:
			var b : Button = child
			var m_meta = b.get_meta("map_ref", null)
			b.button_pressed = (m_meta == map_data)

	_notify_status_changed()
	if _on_ready.is_valid():
		_on_ready.call()


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
		if res == null or not (res is LevelListResource):
			push_warning("不是有效 LevelList: " + path)
			fd.queue_free()
			return
		_selected_levellist = res
		_levellist_path = path
		_refresh_levellist_btn()
		_build_map_list()
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	_attach_to_root(fd)
	fd.popup_centered(Vector2i(500, 400))


func _on_setup_party():
	GameState.party.clear()
	GameState.current_faction = "王国"
	for key in ["swordsman", "spearman", "axeman"]:
		GameState.party.append(UnitDataManager.create_unit_data(key))
	GameState.main_unit_name = "swordsman"
	_refresh_party_label()
	_notify_status_changed()
	if _on_ready.is_valid():
		_on_ready.call()


# ============================================================
#  启动
# ============================================================
func launch():
	var map_to_use : MapData = _selected_map
	if map_to_use == null:
		map_to_use = MapData.new()
		map_to_use.map_name = "测试地图（%s）" % MapConst.get_node_display_name(_selected_type)
		map_to_use.node_type = _selected_type
		map_to_use.map_size = MapConst.DEFAULT_MAP_SIZE

	# ---------- 非战斗节点：直接弹 UI ----------
	if _selected_type in [
		MapNode.NodeType.SHOP,
		MapNode.NodeType.FORGE,
		MapNode.NodeType.TREASURE,
		MapNode.NodeType.CHAPEL,
	]:
		GameState.current_map_data = map_to_use
		GameState.current_day = _get_day()
		_play_non_combat_music()
		match _selected_type:
			MapNode.NodeType.SHOP:     await _open_shop()
			MapNode.NodeType.FORGE:    await _open_forge()
			MapNode.NodeType.TREASURE: await _open_treasure()
			MapNode.NodeType.CHAPEL:   await _open_chapel()
		MusicManager.play_main_menu_music()
		return

	# ---------- 战斗节点：切 Loading → Battlefield ----------
	set_keep_hidden(true)
	GameState.current_map_data = map_to_use
	GameState.current_day = _get_day()
	GameState.is_map_mode = true
	Globals.is_map_mode = true
	Globals.reset_all_game_state()
	print("[NodeTestPlugin] 启动战斗节点：%s（day=%d）" % [
		MapConst.get_node_display_name(_selected_type), _get_day()
	])
	_change_scene(Config.PATHS.LOADING)


# ============================================================
#  子 UI
# ============================================================
func _play_non_combat_music():
	if MusicManager == null or MusicManager.config == null:
		return
	var stream : AudioStream = null
	if MusicManager.config.non_combat_music:
		stream = MusicManager.config.non_combat_music
	elif MusicManager.config.map_music:
		stream = MusicManager.config.map_music
	if stream:
		MusicManager.play_music(stream)


func _open_shop():
	var config = load(Config.PATHS.EQUIPMENT_CONFIG).instantiate()
	_attach_to_root(config)
	var panel = config.get_node("MainPanel")
	panel.call("init", _get_party_unit_names(), -1, int(EquipmentConfigScript.Mode.SHOP))
	await panel.tree_exited


func _open_forge():
	var config = load(Config.PATHS.EQUIPMENT_CONFIG).instantiate()
	_attach_to_root(config)
	var panel = config.get_node("MainPanel")
	var mode : int = int(EquipmentConfigScript.Mode.MAP_SHOP_REST if _get_day() >= 3 else EquipmentConfigScript.Mode.FORGE)
	panel.call("init", _get_party_unit_names(), -1, mode)
	await panel.tree_exited


func _open_treasure():
	var scene = load(Config.PATHS.TREASURE_UI)
	if not scene: return
	var treasure = scene.instantiate()
	_attach_to_root(treasure)
	treasure.setup(_get_day())
	await treasure.closed


func _open_chapel():
	var scene = load(Config.PATHS.CHAPEL_UI)
	if not scene: return
	var ui = scene.instantiate()
	_attach_to_root(ui)
	await ui.closed


# ============================================================
#  数据查询
# ============================================================
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


func _get_party_unit_names() -> Array[String]:
	var names : Array[String] = []
	for u in GameState.party:
		names.append(u.unit_name)
	return names


func _get_day() -> int:
	if _levellist_path == "":
		return 1
	var fname : String = _levellist_path.get_file().to_lower()
	if "day3" in fname: return 3
	if "day2" in fname: return 2
	return 1


# ============================================================
#  辅助
# ============================================================
func _truncate(s: String, max_len: int) -> String:
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len - 1) + "…"
