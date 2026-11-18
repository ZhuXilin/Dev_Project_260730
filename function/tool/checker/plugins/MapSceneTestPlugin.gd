extends TestPlugin

# ============================================================
#  MapSceneTestPlugin — 地图节点链路测试
#
#  直接进入指定天数（1/2/3）的 MapScene，观察当天生成的完整节点链路：
#  起点 → 分支 → 问号 → 精英 → 魂栈 → BOSS。
#  每次启动都会清空地图快照并重新 randomize，便于反复刷问号节点。
# ============================================================

var _day : int = 1
var _day_buttons : Array = []
var _party_label : Label = null
var _on_ready_cb : Callable = Callable()


func get_key() -> String: return "mapscene"
func get_category() -> String: return "地图流程"
func get_display_name() -> String: return "地图测试"


func get_status_text() -> String:
	return "第 %d 天" % _day


func validate() -> String:
	if GameState.party.is_empty():
		return "队伍为空，请先点「准备队伍」"
	return ""


# ============================================================
#  参数区
# ============================================================
func build_params(container: VBoxContainer, on_ready: Callable):
	_on_ready_cb = on_ready

	container.add_child(_make_label("选择天数，进入当天地图节点链路：", 7))

	# 天数选择
	var day_row := HBoxContainer.new()
	day_row.add_theme_constant_override("separation", 4)
	for d in [1, 2, 3]:
		var btn := _make_button("第 %d 天" % d, 8)
		btn.toggle_mode = true
		btn.button_pressed = (d == _day)
		btn.custom_minimum_size = Vector2(48, 0)
		btn.pressed.connect(_on_day_selected.bind(d))
		day_row.add_child(btn)
		_day_buttons.append({"day": d, "btn": btn})
	container.add_child(day_row)

	# 队伍操作
	var party_row := HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 4)
	var party_btn := _make_button("准备队伍", 7)
	party_btn.pressed.connect(_on_setup_party)
	party_row.add_child(party_btn)

	_party_label = _make_label("", 7)
	_party_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_label.clip_text = true
	party_row.add_child(_party_label)
	container.add_child(party_row)

	# 说明
	var hint_text : String = "启动后清空快照并重新生成地图，可反复刷问号节点。\n"
	hint_text += "进入后按 1 键可再次调出本面板换天数。"
	var hint := _make_label(hint_text, 6)
	hint.modulate = Color(0.75, 0.75, 0.75)
	container.add_child(hint)

	_refresh_party_label()
	on_ready.call()


func _on_day_selected(d: int):
	_day = d
	for item in _day_buttons:
		var b = item["btn"] as Button
		if b:
			b.button_pressed = (item["day"] == _day)
	_notify_status_changed()
	if _on_ready_cb.is_valid():
		_on_ready_cb.call()


func _on_setup_party():
	_setup_party()
	_refresh_party_label()
	_notify_status_changed()
	if _on_ready_cb.is_valid():
		_on_ready_cb.call()


func _setup_party():
	GameState.party.clear()
	GameState.current_faction = "王国"
	for key in ["swordsman", "spearman", "axeman"]:
		GameState.party.append(UnitDataManager.create_unit_data(key))
	GameState.main_unit_name = "swordsman"
	# 关卡池按当前阵营加载，测试前同步一次
	LevelManager.current_day = _day - 1
	LevelManager._reload_all_levels()


func _refresh_party_label():
	if _party_label == null:
		return
	if GameState.party.is_empty():
		_party_label.text = "队伍：空"
		return
	var names: Array = []
	for u in GameState.party:
		names.append(u.display_name if u.display_name != "" else u.unit_name)
	_party_label.text = "队伍：%s" % ", ".join(names)


# ============================================================
#  启动：进入 MapScene
# ============================================================
func launch():
	var err: String = validate()
	if err != "":
		return

	# 隐藏测试面板并切场景后不再恢复
	set_keep_hidden(true)
	var harness := _get_harness()
	if harness:
		harness.visible = false

	# 天数与目标状态
	GameState.current_day = _day
	GameState.should_advance_day = false
	GameState.resume_node_id = ""
	GameState.is_map_mode = true
	Globals.is_map_mode = true

	# ★ 关键：清空地图快照 → MapScene 强制重新 generate_map，
	# 这样每次都能看到新 roll 的节点类型（含问号）。
	GameState.map_snapshot.clear()
	GameState.cached_map_level_data = null

	# 关卡池按测试天数就位（current_day 用 0-based 索引）
	LevelManager.current_day = _day - 1
	LevelManager._reload_all_levels()
	LevelManager.is_map_mode = true

	# 清理战场残留单位状态，避免影响地图 UI
	Globals.reset_all_game_state()

	randomize()
	print("[MapSceneTestPlugin] 进入第 %d 天地图节点链路（清快照重生成）" % _day)
	_change_scene(Config.PATHS.MAP_SCENE)
