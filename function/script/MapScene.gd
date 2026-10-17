extends CanvasLayer

# ============================================================
#  MapScene — 局内地图
#  v4.3：ChipMusicEditor 风格主题 + 细滚动条 + 节点点击防抖
#  v4.4：修复 CanvasLayer 无 theme 属性的问题
# ============================================================

const FONT_SIZE = 8

# ---- ChipMusicEditor 风格字号 ----
const FS_BUTTON : int = 6
const FS_LABEL  : int = 6
const FS_SMALL  : int = 5
const FS_PANEL  : int = 7
const FS_HINT   : int = 5

const COL_BG     : Color = Color(0.08, 0.08, 0.10)
const COL_PANEL  : Color = Color(0.10, 0.10, 0.13)
const COL_VSEP   : Color = Color(0.36, 0.36, 0.42)
const COL_TIP_BG : Color = Color(0.15, 0.15, 0.15, 0.92)

const EquipmentConfig = preload(Config.PATHS.EQUIPMENT_CONFIG_SCRIPT)

var current_day: int = 1
var map_data: MapLevelData
var selected_node: MapNode = null
var level_list: Array[MapData] = []
var _equipment_config_instance = null
var _detail_popup = null
var _ready_guard : bool = false

# ★ 节点点击防抖
var _is_loading_combat : bool = false

@onready var node_container = $NodeContainer
@onready var line_container = $NodeContainer/LineContainer
@onready var info_panel = $InfoPanel
@onready var info_label = $InfoPanel/InfoLabel
@onready var interrupt_btn = $BottomBar/InterruptButton
@onready var abandon_btn = $BottomBar/AbandonButton
@onready var day_label = $TopBar/DayLabel
@onready var soul_label = $TopBar/SoulLabel
@onready var gold_label = $TopBar/GoldLabel
@onready var soul_fire_label = $TopBar/SoulFireLabel
@onready var state_label = $TopBar/StateLabel
@onready var resonance_label = $TopBar/ResonanceLabel


# ============================================================
#  ★ 全局主题（ChipMusicEditor 风格）
#  ★ 修复：CanvasLayer 没有 theme 属性，改为递归给所有 Control 子节点设 theme
# ============================================================
func _apply_compact_theme():
	var t := Theme.new()

	t.set_font_size("font_size", "Button", FS_BUTTON)
	var btn_empty := StyleBoxEmpty.new()
	btn_empty.content_margin_left = 1
	btn_empty.content_margin_right = 1
	btn_empty.content_margin_top = 0
	btn_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "Button", btn_empty)
	t.set_stylebox("hover", "Button", btn_empty)
	t.set_stylebox("pressed", "Button", btn_empty)
	t.set_stylebox("focus", "Button", btn_empty)
	t.set_stylebox("disabled", "Button", btn_empty)

	t.set_font_size("font_size", "Label", FS_LABEL)
	var label_empty := StyleBoxEmpty.new()
	t.set_stylebox("normal", "Label", label_empty)

	t.set_font_size("font_size", "LineEdit", FS_BUTTON)
	t.set_font_size("font_size", "OptionButton", FS_BUTTON)
	t.set_font_size("font_size", "PopupMenu", FS_SMALL)
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)
	t.set_font_size("font_size", "TooltipPanel", FS_SMALL)

	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = COL_TIP_BG
	tip_sb.content_margin_left = 3
	tip_sb.content_margin_right = 3
	tip_sb.content_margin_top = 1
	tip_sb.content_margin_bottom = 1
	t.set_stylebox("panel", "TooltipPanel", tip_sb)

	# 细滚动条
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.08, 0.10, 1)
	var grab_off := StyleBoxFlat.new()
	grab_off.bg_color = Color(0.32, 0.32, 0.38, 1)
	grab_off.corner_radius_top_left = 2
	grab_off.corner_radius_top_right = 2
	grab_off.corner_radius_bottom_left = 2
	grab_off.corner_radius_bottom_right = 2
	var grab_hl := StyleBoxFlat.new()
	grab_hl.bg_color = Color(0.55, 0.55, 0.65, 1)
	grab_hl.corner_radius_top_left = 2
	grab_hl.corner_radius_top_right = 2
	grab_hl.corner_radius_bottom_left = 2
	grab_hl.corner_radius_bottom_right = 2

	# OptionButton 小箭头
	var arrow_img := Image.create(7, 4, false, Image.FORMAT_RGBA8)
	arrow_img.fill(Color(0, 0, 0, 0))
	for y in range(4):
		for x in range(7):
			var half : float = float(y) * 0.5
			if float(x) >= half and float(x) <= 6.0 - half:
				arrow_img.set_pixel(x, y, Color(0.72, 0.72, 0.78, 1.0))
	var arrow_tex := ImageTexture.create_from_image(arrow_img)
	t.set_icon("arrow", "OptionButton", arrow_tex)
	t.set_constant("arrow_margin", "OptionButton", 2)

	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab_off)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hl)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hl)
	t.set_constant("minimum_grab_size", "VScrollBar", 6)
	t.set_constant("scroll_width", "VScrollBar", 4)

	t.set_stylebox("scroll", "HScrollBar", track)
	t.set_stylebox("scroll_focus", "HScrollBar", track)
	t.set_stylebox("grabber", "HScrollBar", grab_off)
	t.set_stylebox("grabber_highlight", "HScrollBar", grab_hl)
	t.set_stylebox("grabber_pressed", "HScrollBar", grab_hl)
	t.set_constant("minimum_grab_size", "HScrollBar", 6)
	t.set_constant("scroll_height", "HScrollBar", 4)

	# ★ 修复：CanvasLayer 没有 theme 属性，递归应用到所有 Control 子节点
	_apply_theme_to_all_controls(self, t)


# ★ 新增：递归把所有 Control 子节点的 theme 设置成同一个，模拟全局主题
func _apply_theme_to_all_controls(node: Node, t: Theme) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).theme = t
		_apply_theme_to_all_controls(child, t)


func _ready():
	if _ready_guard:
		print("警告：MapScene._ready 被重复调用，忽略")
		return
	_ready_guard = true

	_apply_compact_theme()

	print("=== MapScene _ready 开始 ===")
	Globals.is_map_mode = true

	if GameState.party.is_empty():
		print("队伍为空，返回营地")
		GameState.cached_map_level_data = null
		GameState.current_map_data = null
		GameState.map_snapshot.clear()
		GameState.interrupt_state = GameState.InterruptState.CAMP
		_save_game()
		get_tree().change_scene_to_file(Config.PATHS.CAMP)
		return

	LevelManager.current_day = GameState.current_day - 1

	if GameState.should_advance_day:
		GameState.should_advance_day = false
		GameState.resume_node_id = ""
		print("检测到 Boss 胜利，推进天数")
		var has_next = LevelManager.advance_day()
		print("advance_day 返回：", has_next)
		if not has_next:
			GameState.finish_cycle()

			var earned_soul = max(0, GameState.soul - GameState.cycle_start_soul)

			GameState.reset_for_new_cycle()
			GameState.map_snapshot.clear()
			GameState.interrupt_state = GameState.InterruptState.CAMP
			_save_game()

			await _show_cycle_reward(earned_soul)
			return

		current_day = LevelManager.current_day + 1
		GameState.current_day = current_day
		GameState.finish_day()

		GameState.map_snapshot.clear()
		print("新的一天，清空地图快照")

		level_list = LevelManager.get_current_day_levels()
		print("新的一天，当前 day=", current_day, " 关卡数：", level_list.size())

		generate_map(current_day)
		_save_game()
		_setup_ui()
		AnalyticsLogger.record_day_reached(current_day)
		return

	var day_to_load = GameState.current_day
	if day_to_load <= 0:
		day_to_load = LevelManager.current_day + 1
		GameState.current_day = day_to_load

	current_day = day_to_load
	level_list = LevelManager.get_current_day_levels()
	if level_list.is_empty():
		print("警告：当前天没有关卡数据，使用默认地图")
		var default_map = MapData.new()
		default_map.map_name = "默认战斗"
		level_list.append(default_map)

	if not GameState.map_snapshot.is_empty() \
			and GameState.map_snapshot.get("day", -1) == current_day:
		print("从快照恢复地图，天数：", current_day)
		_restore_map_from_snapshot()
	else:
		print("生成新地图，天数：", current_day)
		generate_map(current_day)

	GameState.interrupt_state = GameState.InterruptState.MAP
	_save_game()
	_setup_ui()
	update_all_displays()
	AnalyticsLogger.record_day_reached(current_day)
	print("MapScene _ready: temp_gold=", GameState.temp_gold)

	_detail_popup = load(Config.PATHS.ITEM_DETAIL_POPUP).instantiate()
	add_child(_detail_popup)
	_detail_popup.visible = false

	if not SoulFireManager.soul_fire_changed.is_connected(_on_soul_fire_changed):
		SoulFireManager.soul_fire_changed.connect(_on_soul_fire_changed)


func _save_game():
	if Globals.pending_save_slot != -1:
		SaveManager.save_game(Globals.pending_save_slot)
		Globals.pending_save_slot = -1
	else:
		SaveManager.auto_save()


func update_all_displays():
	if day_label:
		day_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if soul_label:
		soul_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if gold_label:
		gold_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if soul_fire_label:
		soul_fire_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if state_label:
		state_label.add_theme_font_size_override("font_size", FONT_SIZE)

	var local_label = $TopBar/LocalResourcesLabel
	if local_label:
		local_label.add_theme_font_size_override("font_size", FONT_SIZE)
	var perm_label = $TopBar/PermanentResourcesLabel
	if perm_label:
		perm_label.add_theme_font_size_override("font_size", FONT_SIZE)

	if gold_label:
		gold_label.text = "金币: " + str(EconomyManager.get_temp_gold())

	if soul_label:
		soul_label.text = "魂: " + str(GameState.soul)

	_update_soul_fire_display()


func update_gold_display():
	gold_label.text = "金币:" + str(EconomyManager.get_temp_gold())


func update_soul_display():
	soul_label.text = "魂:" + str(GameState.soul)


# ---- 按钮回调 ----
func _on_interrupt_pressed():
	if GameState.cached_map_level_data:
		var err = ResourceSaver.save(GameState.cached_map_level_data, "user://map_cache.tres")
		print("保存地图缓存: ", "成功" if err == OK else "失败")

	GameState.interrupt_state = GameState.InterruptState.MAP
	_save_game()
	get_tree().change_scene_to_file(Config.PATHS.MAIN_MENU)


func _on_abandon_pressed():
	GameState.show_abandon_confirmation(self)


func _on_abandon_confirmed():
	GameState.abandon_and_return_to_camp()


func _on_cycle_complete():
	GameState.interrupt_state = GameState.InterruptState.CAMP
	_save_game()
	get_tree().change_scene_to_file(Config.PATHS.CAMP)


func _draw_connections():
	for child in line_container.get_children():
		child.queue_free()
	if not map_data: return
	var pos_map : Dictionary = _compute_node_positions()
	for node in map_data.nodes:
		var from_pos : Vector2 = pos_map.get(node, node.position)
		for conn in node.connected_nodes:
			var to_pos : Vector2 = pos_map.get(conn, conn.position)
			_create_directed_line(from_pos, to_pos)


func _create_directed_line(from_pos: Vector2, to_pos: Vector2):
	var dir : Vector2 = to_pos - from_pos
	var dist : float = dir.length()
	if dist < 1.0:
		return
	dir = dir / dist
	var perp : Vector2 = Vector2(-dir.y, dir.x)

	var hw : float = MapConst.MAP_NODE_SIZE.x * 0.5
	var hh : float = MapConst.MAP_NODE_SIZE.y * 0.5
	var gap : float = _exit_gap_distance(dir, hw, hh) + 2.0
	var line_end : Vector2 = to_pos - dir * gap
	if (line_end - from_pos).dot(dir) <= 0.0:
		line_end = from_pos + dir * (dist * 0.5)

	var line := Line2D.new()
	line.add_point(from_pos)
	line.add_point(line_end)
	line.width = MapConst.MAP_LINE_WIDTH
	line.default_color = MapConst.MAP_LINE_COLOR
	line_container.add_child(line)

	var arrow_length : float = 5.0
	var arrow_width  : float = 3.5
	var tip : Vector2 = line_end
	var base_center : Vector2 = line_end - dir * arrow_length
	var left : Vector2 = base_center + perp * arrow_width * 0.5
	var right : Vector2 = base_center - perp * arrow_width * 0.5

	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([tip, left, right])
	arrow.color = MapConst.MAP_LINE_COLOR.lightened(0.3)
	line_container.add_child(arrow)


func _exit_gap_distance(dir: Vector2, hw: float, hh: float) -> float:
	var ax : float = abs(dir.x)
	var ay : float = abs(dir.y)
	if ax < 0.001:
		return hh
	if ay < 0.001:
		return hw
	return min(hw / ax, hh / ay)


func _create_node_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.queue_free()
	if not map_data: return
	var pos_map : Dictionary = _compute_node_positions()
	for node in map_data.nodes:
		var btn = MapNodeButton.new()
		btn.setup(node, self, pos_map.get(node, node.position))
		node_container.add_child(btn)


func _get_node_layout_width() -> float:
	if not is_inside_tree(): return 400.0
	var vp_node : Viewport = get_viewport()
	if vp_node == null: return 400.0
	var vp : Vector2 = vp_node.get_visible_rect().size
	return maxf(vp.x - 80.0, 200.0)


func _update_availability(_start_node: MapNode):
	var max_visited_layer = -1
	for node in map_data.nodes:
		if node.is_visited and node.layer > max_visited_layer:
			max_visited_layer = node.layer
	print("最大已访问层: ", max_visited_layer)

	for node in map_data.nodes:
		node.is_available = false

	if max_visited_layer == -1:
		for node in map_data.nodes:
			if node.layer == 0:
				node.is_available = true
		print("初始节点层：layer 0 全部可用")
	else:
		var next_layer = max_visited_layer + 1
		for node in map_data.nodes:
			if node.layer == next_layer and not node.is_visited:
				node.is_available = true
				print("解锁节点: ", node.custom_label, " 层: ", node.layer)

	_update_buttons()


func _update_buttons():
	if not map_data: return
	if not is_inside_tree(): return
	var pos_map : Dictionary = _compute_node_positions()
	if pos_map.is_empty(): return
	for child in node_container.get_children():
		if child is MapNodeButton:
			var btn : MapNodeButton = child
			btn.setup(btn.map_node, self, pos_map.get(btn.map_node, btn.map_node.position))


func generate_map(day: int):
	print("=== generate_map 开始，day=", day, " temp_gold=", GameState.temp_gold)
	var layout : MapLayout = LevelManager.get_current_layout()
	map_data = MapGenerator.generate_day(day, layout, level_list)

	if map_data == null:
		push_error("[MapScene] 地图布局缺失，返回营地")
		GameState.interrupt_state = GameState.InterruptState.CAMP
		_save_game()
		get_tree().change_scene_to_file(Config.PATHS.CAMP)
		return

	GameState.cached_map_level_data = map_data
	GameState.cached_day = day

	GameState.map_snapshot = MapSnapshot.serialize(map_data)
	print("地图快照已保存，节点数：", GameState.map_snapshot.get("nodes", []).size())

	_apply_visited_state()
	_draw_connections()
	_create_node_buttons()
	_update_availability(map_data.root_node)
	day_label.text = "第 %d 天" % day
	update_all_displays()
	_save_game()
	print("=== generate_map 结束，temp_gold=", GameState.temp_gold)


func _setup_ui():
	Globals.reset_battle_turn()
	info_panel.visible = false
	day_label.text = "第 %d 天" % current_day
	if MusicManager.config and MusicManager.config.map_music:
		MusicManager.play_music(MusicManager.config.map_music)
	_update_soul_fire_display()
	_show_resonance_hint()


func _restore_map_music():
	if not is_inside_tree(): return
	if MusicManager == null: return
	if MusicManager.config == null: return
	var mm : AudioStream = MusicManager.config.map_music
	if mm == null: return
	var player : AudioStreamPlayer = MusicManager.player
	if player == null: return
	if not player.is_inside_tree(): return
	if player.playing and player.stream == mm:
		return
	MusicManager.play_music(mm)


func _select_node_by_id(node_id: String):
	for child in node_container.get_children():
		if child is MapNodeButton and child.map_node and child.map_node.node_id == node_id:
			on_node_selected(child.map_node)
			break


# ============================================================
#  ★ 节点点击防抖
# ============================================================
func on_node_selected(node: MapNode):
	if _is_loading_combat:
		return
	if not node.is_available or node.is_visited:
		return

	_is_loading_combat = true

	var key = "%d_%d" % [node.position.x, node.position.y]
	
	var real_type : int = node.node_type
	if node.node_type == MapNode.NodeType.QUESTION and node.hidden_node_type != -1:
		real_type = node.hidden_node_type
		
	GameState.last_selected_node_type = real_type
	print("进入节点: ", key, " 类型: ", real_type)
	
	if real_type in [
		MapNode.NodeType.START,
		MapNode.NodeType.NORMAL,
		MapNode.NodeType.ELITE,
		MapNode.NodeType.BOSS,
	]:
		GameState.current_node_key = key
	GameState.current_node_unlock_relics = node.unlock_relics.duplicate()
	GameState.current_node_unlock_units = node.unlock_units.duplicate()
	_load_combat_for_node(node)


func _load_combat_for_node(node: MapNode):
	var real_type : int = node.node_type
	if node.node_type == MapNode.NodeType.QUESTION and node.hidden_node_type != -1:
		real_type = node.hidden_node_type
		print("[MapScene] 问号节点解析为: ", real_type)

	match real_type:
		MapNode.NodeType.FORGE:
			_open_forge(node)
			return
		MapNode.NodeType.TREASURE:
			_open_treasure(node)
			return
		MapNode.NodeType.CHAPEL:
			_open_chapel(node)
			return

	var map_to_load = node.map_data
	if not map_to_load:
		# ... (保留原逻辑)
		return
	_load_combat(map_to_load)


func _open_forge(node: MapNode):
	print("=== 打开铁匠铺 ===")

	var key = "%d_%d" % [node.position.x, node.position.y]
	GameState.visited_nodes[key] = true
	node.is_visited = true
	node.is_available = false

	info_panel.visible = false
	_update_availability(map_data.root_node)
	_save_game()

	var config = load(Config.PATHS.EQUIPMENT_CONFIG).instantiate()
	add_child(config)
	var panel = config.get_node("MainPanel")

	var unit_names: Array[String] = []
	for unit_data in GameState.party:
		unit_names.append(unit_data.unit_name)

	var slot = SaveManager.current_slot
	if slot == -1:
		slot = SaveManager.find_empty_slot()

	if GameState.current_day >= 3:
		panel.init(unit_names, slot, EquipmentConfig.Mode.MAP_SHOP_REST)
	else:
		panel.init(unit_names, slot, EquipmentConfig.Mode.FORGE)

	await panel.tree_exited

	if not is_inside_tree():
		return

	print("铁匠铺已关闭")
	_restore_map_music()
	GameState.current_node_key = ""
	_save_game()
	update_all_displays()
	_update_availability(map_data.root_node)
	_is_loading_combat = false


func _open_treasure(node: MapNode):
	print("=== 打开宝箱/事件 ===")

	var key = "%d_%d" % [node.position.x, node.position.y]
	GameState.visited_nodes[key] = true
	node.is_visited = true
	node.is_available = false

	info_panel.visible = false
	_update_availability(map_data.root_node)
	_save_game()

	var treasure_scene = load(Config.PATHS.TREASURE_UI)
	if not treasure_scene:
		push_error("Treasure UI 未找到: " + Config.PATHS.TREASURE_UI)
		_is_loading_combat = false
		return
	var treasure = treasure_scene.instantiate()
	add_child(treasure)
	treasure.setup(GameState.current_day)
	await treasure.closed

	if not is_inside_tree():
		return

	print("宝箱已关闭")
	_restore_map_music()
	_save_game()
	update_all_displays()
	_update_availability(map_data.root_node)
	_is_loading_combat = false


func _open_chapel(node: MapNode):
	print("=== 打开圣坛 ===")

	var key = "%d_%d" % [node.position.x, node.position.y]
	GameState.visited_nodes[key] = true
	node.is_visited = true
	node.is_available = false

	info_panel.visible = false
	_update_availability(map_data.root_node)
	_save_game()

	var scene = load(Config.PATHS.CHAPEL_UI)
	if not scene:
		push_error("ChapelUI 未找到")
		_is_loading_combat = false
		return
	var ui = scene.instantiate()
	add_child(ui)
	await ui.closed

	if not is_inside_tree():
		return

	_restore_map_music()
	_save_game()
	update_all_displays()
	_update_availability(map_data.root_node)
	_is_loading_combat = false


func _open_chapel_revive_dialog(dead_units: Array, healed_count: int):
	var dlg := AcceptDialog.new()
	dlg.title = "圣坛 · 复活"
	dlg.dialog_hide_on_ok = true
	dlg.ok_button_text = "离开"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	dlg.add_child(vbox)

	var title := Label.new()
	var hint_text : String = "全队 HP 已回满"
	if healed_count > 0:
		hint_text += "（%d 人受益）" % healed_count
	title.text = hint_text + "\n选择要复活的一名单位（HP 回满）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	for ud in dead_units:
		var btn := Button.new()
		btn.text = "%s（%s）" % [ud.display_name, UnitDataManager.get_unit_type_display_name(ud.unit_name)]
		btn.pressed.connect(_on_chapel_revive_unit.bind(ud.unit_name, ud.display_name, dlg))
		vbox.add_child(btn)

	add_child(dlg)
	dlg.popup_centered(Vector2(300, 220))


func _on_chapel_revive_unit(unit_name: String, display_name: String, dlg: Window):
	if GameState.revive_unit(unit_name, display_name):
		SaveManager.auto_save()
		if is_instance_valid(dlg):
			dlg.queue_free()
		Globals.show_confirm(
			self,
			"%s 已在圣坛的祝福中复活！\nHP 全满。" % display_name,
			"确定",
			"",
			func(): pass,
			func(): pass,
			false
		)
		update_all_displays()


func _load_combat(map_data_arg: MapData):
	if not map_data_arg:
		map_data_arg = _create_default_map()
	elif not map_data_arg.scene:
		map_data_arg = _create_default_map()
	print("加载战斗场景: ", map_data_arg.map_name)
	GameState.current_map_data = map_data_arg
	Globals.reset_all_game_state()
	get_tree().change_scene_to_file(Config.PATHS.LOADING)


func _create_default_map() -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	map.map_size = MapConst.DEFAULT_MAP_SIZE
	return map


func get_selected_node_id() -> String:
	if selected_node:
		return selected_node.node_id
	return ""


func _apply_visited_state():
	print("_apply_visited_state 被调用，visited_nodes 大小：", GameState.visited_nodes.size())
	if not map_data:
		print("map_data 为空")
		return
	var visited_keys = GameState.visited_nodes.keys()
	print("visited_keys: ", visited_keys)
	for node in map_data.nodes:
		var key = "%d_%d" % [node.position.x, node.position.y]
		if GameState.visited_nodes.has(key):
			node.is_visited = true
			node.is_available = false
			print("标记节点", key, "为已访问")
		else:
			node.is_visited = false
			node.is_available = false
	var visited_count = 0
	for node in map_data.nodes:
		if node.is_visited:
			visited_count += 1
	print("实际已访问节点数：", visited_count)


func _on_config_btn_pressed():
	if _equipment_config_instance != null:
		_equipment_config_instance.show()
		_equipment_config_instance.move_to_front()
		return

	var config = load(Config.PATHS.EQUIPMENT_CONFIG).instantiate()
	add_child(config)
	_equipment_config_instance = config
	var panel = config.get_node("MainPanel")

	var unit_names: Array[String] = []
	for unit_data in GameState.party:
		unit_names.append(unit_data.unit_name)

	var slot = SaveManager.current_slot
	if slot == -1:
		slot = SaveManager.find_empty_slot()

	panel.init(unit_names, slot, EquipmentConfig.Mode.MAP)

	config.tree_exited.connect(func():
		_equipment_config_instance = null
	)


func show_item_detail(item_id: String):
	if _detail_popup:
		_detail_popup.show_item(item_id)
		_detail_popup.visible = true


func hide_item_detail():
	if _detail_popup:
		_detail_popup.visible = false


func _apply_unified_font_size():
	if day_label:
		day_label.add_theme_font_size_override("font_size", FONT_SIZE)
	var local_label = $TopBar/LocalResourcesLabel
	if local_label:
		local_label.add_theme_font_size_override("font_size", FONT_SIZE)
	var perm_label = $TopBar/PermanentResourcesLabel
	if perm_label:
		perm_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if soul_label:
		soul_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if gold_label:
		gold_label.add_theme_font_size_override("font_size", FONT_SIZE)


func _restore_map_from_snapshot():
	map_data = MapSnapshot.deserialize(GameState.map_snapshot)
	if not map_data:
		print("快照恢复失败，生成新地图")
		generate_map(current_day)
		return

	_validate_restored_map_data(map_data)

	GameState.cached_map_level_data = map_data
	GameState.cached_day = current_day
	_apply_visited_state()
	_draw_connections()
	_create_node_buttons()
	if map_data and map_data.root_node:
		_update_availability(map_data.root_node)
	else:
		_update_buttons()

	if GameState.resume_node_id != "":
		_select_node_by_id(GameState.resume_node_id)
		GameState.resume_node_id = ""

	day_label.text = "第 %d 天" % current_day
	update_all_displays()
	_save_game()


func _validate_restored_map_data(md: MapLevelData):
	if md == null:
		return

	var level_pool : Dictionary = {}
	for m in LevelManager.get_current_day_levels():
		if m and m.map_name != "":
			level_pool[m.map_name] = m

	for node in md.nodes:
		if node.node_type in [
			MapNode.NodeType.FORGE,
			MapNode.NodeType.TREASURE,
			MapNode.NodeType.CHAPEL,
		]:
			continue

		if node.map_data == null:
			var fallback = _find_map_by_type(node.node_type)
			if fallback:
				node.map_data = fallback
				print("[MapScene] 节点 %s 无地图，补默认：%s" % [node.node_id, fallback.map_name])
			continue

		if node.map_data.scene != null:
			continue

		var map_name : String = node.map_data.map_name
		if map_name != "" and level_pool.has(map_name):
			node.map_data = level_pool[map_name]
			print("[MapScene] 节点 %s 补全地图：%s" % [node.node_id, map_name])
		else:
			print("[MapScene] 警告：节点 %s 地图缺失且无法找回（%s）" % [node.node_id, map_name])


func _find_map_by_type(node_type: int) -> MapData:
	for m in LevelManager.get_current_day_levels():
		if m and m.node_type == node_type:
			return m
	for m in LevelManager.get_current_day_levels():
		if m and m.node_type == MapNode.NodeType.NORMAL:
			return m
	return null


# ============================================================
#  三天结算
# ============================================================
func _show_cycle_reward(earned_soul: int):
	var reward_items: Array = []

	var summary = Globals.get_reward_summary()
	if not summary:
		push_error("MapScene: 无法获取 RewardSummaryUI 实例，直接进营地")
		_on_cycle_complete()
		return

	summary.setup_reward(0, earned_soul, reward_items, true, "本轮结算")
	summary.open()
	await summary.confirmed
	summary.close()

	_on_cycle_complete()


# ============================================================
#  节点信息悬浮
# ============================================================
func show_node_info(node: MapNode) -> void:
	if not info_panel or not info_label:
		return
	if not node:
		return
	info_label.text = _get_node_description(node)
	info_panel.visible = true


func hide_node_info() -> void:
	if info_panel:
		info_panel.visible = false


func _get_node_description(node: MapNode) -> String:
	if node.node_type == MapNode.NodeType.QUESTION:
		return "未知领域\n进入后随机触发事件"

	var base : String = ""
	match node.node_type:
		MapNode.NodeType.START:
			base = "起始点\n进入战斗"
		MapNode.NodeType.NORMAL:
			base = "普通战斗"
		MapNode.NodeType.ELITE:
			base = "精英战斗\n敌人更强，奖励更好"
		MapNode.NodeType.FORGE:
			base = "铁匠铺\n合成防具 / 升级武器"
		MapNode.NodeType.TREASURE:
			base = "宝箱"
		MapNode.NodeType.BOSS:
			base = "首领战"
		MapNode.NodeType.CHAPEL:
			base = "圣坛\n全队回满 HP，复活一名阵亡单位"
		_:
			base = "未知节点"

	# ★ v4.4：显示目标类型
	if node.map_data and node.map_data.objective_type != MapData.ObjectiveType.ANNIHILATE:
		base += "\n★ 目标：" + _objective_display_name(node.map_data.objective_type)

	# ★ v4.5：显示波次/增援
	if node.map_data and node.map_data.max_waves > 1:
		base += "\n波次：" + str(node.map_data.max_waves)
		if node.map_data.reinforcement_count > 0:
			base += "（每波增援 " + str(node.map_data.reinforcement_count) + "）"

	return base


func _objective_display_name(t: int) -> String:
	match t:
		MapData.ObjectiveType.CAPTURE: return "占领"
		MapData.ObjectiveType.FLAG: return "夺旗"
		MapData.ObjectiveType.ASSAULT: return "突进"
		_: return "全灭"


func _compute_node_positions() -> Dictionary:
	var pos_map : Dictionary = {}
	if not map_data: return pos_map
	if not is_inside_tree(): return pos_map
	var vp_node : Viewport = get_viewport()
	if vp_node == null: return pos_map

	var max_layer : int = 0
	for n in map_data.nodes:
		max_layer = maxi(max_layer, n.layer)

	var vp : Vector2 = vp_node.get_visible_rect().size
	var canvas_width : float = _get_node_layout_width()
	var layer_count : int = max_layer + 1

	var top_margin : float = 40.0
	var bottom_margin : float = 50.0
	var available_h : float = vp.y - top_margin - bottom_margin

	var layer_height : float = available_h / float(layer_count)
	layer_height = clampf(layer_height, 40.0, 200.0)

	var total_h : float = layer_count * layer_height
	var top_offset : float = top_margin + (available_h - total_h) / 2.0

	var by_layer : Dictionary = {}
	for n in map_data.nodes:
		if not by_layer.has(n.layer):
			by_layer[n.layer] = []
		by_layer[n.layer].append(n)

	for layer_key in by_layer:
		var arr : Array = by_layer[layer_key]
		for i in range(arr.size()):
			var n : MapNode = arr[i]
			var ratio : float = float(i + 1) / float(arr.size() + 1)
			var px : float = canvas_width * ratio
			var py : float = top_offset + (max_layer - n.layer + 0.5) * layer_height
			pos_map[n] = Vector2(px, py)
	return pos_map


func _on_soul_fire_changed(_c: int, _m: int):
	_update_soul_fire_display()


func _update_soul_fire_display():
	if not soul_fire_label: return
	var cur : int = SoulFireManager.current
	var mx : int = SoulFireManager.get_max_carried()
	soul_fire_label.text = "魂火: %d / %d" % [cur, mx]
	if state_label:
		match SoulFireManager.get_state():
			SoulFireManager.State.BURNING:
				state_label.text = "[燃烧]"
				state_label.modulate = Color(1.0, 0.6, 0.2, 1)
			SoulFireManager.State.DEPLETED:
				state_label.text = "[枯竭]"
				state_label.modulate = Color(0.7, 0.3, 1.0, 1)
			SoulFireManager.State.ZERO:
				state_label.text = "[归零]"
				state_label.modulate = Color(1.0, 0.3, 0.3, 1)
			_:
				state_label.text = ""
				state_label.modulate = Color.WHITE


func _show_resonance_hint():
	var r : Dictionary = LevelManager.current_resonance
	if resonance_label:
		resonance_label.text = "" if r.is_empty() else "★ 共鸣：" + str(r.get("display", ""))
	if r.is_empty(): return
	_show_floating_toast("火焰共鸣：%s" % r.get("display", ""))


func _show_floating_toast(text : String):
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 10)
	toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 3)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.size = Vector2(400, 20)
	toast.position = Vector2(0, 60)
	add_child(toast)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(toast, "modulate:a", 0.0, 0.3).set_delay(2.0)
	tw.tween_callback(func():
		if is_instance_valid(toast): toast.queue_free()
	)
