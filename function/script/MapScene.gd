extends CanvasLayer

# ---- 变量声明 ----
var current_day: int = 1
var map_data: MapLevelData
var selected_node: MapNode = null
var level_list: Array[MapData] = []

# ---- 节点引用（动态创建） ----
var node_container: Node2D
var line_container: Node2D
var info_panel: Panel
var info_label: Label
var back_button: Button
var day_label: Label

func _ready():
	# ---- 如果队伍为空，强制跳转到单位选择界面 ----
	if GameState.party.is_empty():
		print("队伍为空，跳转到单位选择界面")
		# 清除可能残留的地图数据
		GameState.current_map_data = null
		GameState.cached_map_level_data = null
		get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")
		return

	# 确保 LevelManager 天数与 GameState 同步
	LevelManager.current_day = GameState.current_day - 1

	# 确保所有必需节点存在（动态创建）
	_ensure_nodes_exist()

	# ---- 1. 优先处理 Boss 胜利后的天数推进 ----
	if GameState.should_advance_day:
		GameState.should_advance_day = false
		GameState.resume_node_id = ""
		print("检测到 Boss 胜利，推进天数")
		var has_next = LevelManager.advance_day()
		if not has_next:
			# 所有天数完成，重置存档并回到单位选择
			print("所有天数完成，重置存档并回到单位选择界面")
			GameState.reset_all()
			if SaveManager.current_slot != -1:
				SaveManager.save_game(SaveManager.current_slot, false)
			get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")
			return
		current_day = LevelManager.current_day + 1
		GameState.current_day = current_day
		level_list = LevelManager.get_current_day_levels()
		generate_map(current_day)
		_save_game()
		_setup_ui()
		return

	# ---- 2. 从存档恢复或首次进入 ----
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

	# 检查是否有缓存地图（从存档恢复）
	if GameState.cached_map_level_data and GameState.cached_day == GameState.current_day:
		print("使用缓存地图数据恢复，天数：", GameState.current_day)
		map_data = GameState.cached_map_level_data

		# ---- 检测连接是否丢失，若丢失则重建 ----
		var need_rebuild = false
		for node in map_data.nodes:
			if node.connected_nodes.is_empty() and map_data.nodes.size() > 1:
				need_rebuild = true
				break
		if need_rebuild:
			print("检测到连接丢失，根据层数重建连接")
			_rebuild_connections_by_layer(map_data)

		_draw_connections()
		_create_node_buttons()
		if map_data and map_data.root_node:
			_update_availability(map_data.root_node)
		else:
			_update_buttons()

		# 如果存档中保存了选中的节点 ID，则自动进入该节点（战斗）
		if GameState.resume_node_id != "":
			_select_node_by_id(GameState.resume_node_id)
			GameState.resume_node_id = ""   # 清空，防止重复进入
	else:
		# ---- 没有缓存，生成新地图 ----
		print("生成新地图，天数：", current_day)
		generate_map(current_day)

	# ---- 保存当前进度（自动存档到当前槽或新槽） ----
	_save_game()

	# ---- 设置 UI ----
	_setup_ui()

# ---- 保存辅助函数 ----
func _save_game():
	if Globals.pending_save_slot != -1:
		SaveManager.save_game(Globals.pending_save_slot)
		Globals.pending_save_slot = -1
	else:
		SaveManager.auto_save()

# ---- 确保所有必要节点存在 ----
func _ensure_nodes_exist():
	node_container = get_node_or_null("NodeContainer")
	if not node_container:
		node_container = Node2D.new()
		node_container.name = "NodeContainer"
		add_child(node_container)
		node_container.position = Vector2.ZERO

	line_container = get_node_or_null("NodeContainer/LineContainer")
	if not line_container:
		line_container = Node2D.new()
		line_container.name = "LineContainer"
		node_container.add_child(line_container)
		line_container.position = Vector2.ZERO
		node_container.move_child(line_container, 0)

	info_panel = get_node_or_null("InfoPanel")
	if not info_panel:
		info_panel = Panel.new()
		info_panel.name = "InfoPanel"
		add_child(info_panel)
		info_label = Label.new()
		info_label.name = "InfoLabel"
		info_panel.add_child(info_label)
	else:
		info_label = info_panel.get_node_or_null("InfoLabel")
		if not info_label:
			info_label = Label.new()
			info_label.name = "InfoLabel"
			info_panel.add_child(info_label)

	var bottom_bar = get_node_or_null("BottomBar")
	if bottom_bar:
		back_button = bottom_bar.get_node_or_null("BackButton")
	if not back_button:
		back_button = Button.new()
		back_button.name = "BackButton"
		back_button.text = "返回"
		add_child(back_button)
		back_button.anchors_preset = Control.PRESET_CENTER
		back_button.position = Vector2(-40, -20)

	var top_bar = get_node_or_null("TopBar")
	if top_bar:
		day_label = top_bar.get_node_or_null("DayLabel")
	if not day_label:
		day_label = Label.new()
		day_label.name = "DayLabel"
		add_child(day_label)
		day_label.position = Vector2(10, 10)
		day_label.add_theme_font_size_override("font_size", 10)

# ---- 重建连接（根据层数） ----
func _rebuild_connections_by_layer(map_level_data: MapLevelData):
	if not map_level_data or map_level_data.nodes.is_empty():
		return
	for node in map_level_data.nodes:
		node.connected_nodes.clear()
	
	var layer_nodes = {}
	for node in map_level_data.nodes:
		if not layer_nodes.has(node.layer):
			layer_nodes[node.layer] = []
		layer_nodes[node.layer].append(node)
	
	var day = map_level_data.day
	if day == 1 or day == 2:
		for i in range(0, 5):
			if layer_nodes.has(i) and layer_nodes.has(i+1):
				for node_a in layer_nodes[i]:
					for node_b in layer_nodes[i+1]:
						if not node_a.connected_nodes.has(node_b) and not node_b.connected_nodes.has(node_a):
							node_a.connected_nodes.append(node_b)
							node_b.connected_nodes.append(node_a)
	elif day == 3:
		if layer_nodes.has(0) and layer_nodes.has(1):
			for node_a in layer_nodes[0]:
				for node_b in layer_nodes[1]:
					if not node_a.connected_nodes.has(node_b) and not node_b.connected_nodes.has(node_a):
						node_a.connected_nodes.append(node_b)
						node_b.connected_nodes.append(node_a)
	else:
		var sorted_layers = layer_nodes.keys()
		sorted_layers.sort()
		for i in range(sorted_layers.size() - 1):
			for node_a in layer_nodes[sorted_layers[i]]:
				for node_b in layer_nodes[sorted_layers[i+1]]:
					if not node_a.connected_nodes.has(node_b) and not node_b.connected_nodes.has(node_a):
						node_a.connected_nodes.append(node_b)
						node_b.connected_nodes.append(node_a)
	print("重建连接完成，节点数：", map_level_data.nodes.size())

# ---- 绘制连线 ----
func _draw_connections():
	if not line_container:
		print("错误：line_container 为空")
		return
	for child in line_container.get_children():
		child.queue_free()
	if not map_data:
		return
	for node in map_data.nodes:
		for conn in node.connected_nodes:
			var line = Line2D.new()
			line.add_point(node.position)
			line.add_point(conn.position)
			line.width = 2
			line.default_color = Color(0.5, 0.5, 0.5, 0.6)
			line_container.add_child(line)

# ---- 创建节点按钮 ----
func _create_node_buttons():
	if not node_container:
		return
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.queue_free()
	if not map_data:
		return
	for node in map_data.nodes:
		var btn = MapNodeButton.new()
		btn.setup(node, self)
		node_container.add_child(btn)

# ---- 更新节点可用性 ----
func _update_availability(start_node: MapNode):
	var max_visited_layer = -1
	for node in map_data.nodes:
		if node.is_visited and node.layer > max_visited_layer:
			max_visited_layer = node.layer
	print("最大已访问层: ", max_visited_layer)
	for node in map_data.nodes:
		node.is_available = false
	if not start_node.is_visited:
		start_node.is_available = true
		print("起点未访问，设为可用")
	else:
		var next_layer = max_visited_layer + 1
		for node in map_data.nodes:
			if node.layer == next_layer and not node.is_visited:
				node.is_available = true
				print("解锁节点: ", node.custom_label, " 层: ", node.layer)
	_update_buttons()

# ---- 刷新按钮 ----
func _update_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.setup(child.map_node, self)

# ---- 生成地图 ----
func generate_map(day: int):
	print("=== 生成地图，天数：", day)
	map_data = MapGenerator.generate_day(day, level_list)
	GameState.cached_map_level_data = map_data
	GameState.cached_day = day
	for node in map_data.nodes:
		var key = "%d_%d" % [node.position.x, node.position.y]
		if GameState.visited_nodes.has(key):
			node.is_visited = true
			node.is_available = false
	_draw_connections()
	_create_node_buttons()
	_update_availability(map_data.root_node)
	day_label.text = "第 %d 天" % day

# ---- UI 设置 ----
func _setup_ui():
	Globals.reset_battle_turn()
	info_panel.visible = false
	day_label.text = "第 %d 天" % current_day
	
	if back_button:
		var bottom_bar = get_node_or_null("BottomBar")
		if bottom_bar:
			back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		else:
			back_button.anchors_preset = Control.PRESET_CENTER
			back_button.position = Vector2(-40, -20)
	
	_safe_connect(back_button, "pressed", Callable(self, "_on_back_pressed"))
	if not SignalBus.battle_completed.is_connected(_on_battle_completed):
		SignalBus.battle_completed.connect(_on_battle_completed)
	if MusicManager.config and MusicManager.config.map_music:
		MusicManager.play_music(MusicManager.config.map_music)

# ---- 安全连接 ----
func _safe_connect(source: Object, signal_name: String, target_callable: Callable):
	if source.is_connected(signal_name, target_callable):
		source.disconnect(signal_name, target_callable)
	source.connect(signal_name, target_callable)

# ---- 根据 ID 选择节点 ----
func _select_node_by_id(node_id: String):
	for child in node_container.get_children():
		if child is MapNodeButton and child.map_node and child.map_node.node_id == node_id:
			on_node_selected(child.map_node)
			break

# ---- 节点被选中 ----
func on_node_selected(node: MapNode):
	if not node.is_available or node.is_visited:
		print("节点不可选或已访问")
		return
	var key = "%d_%d" % [node.position.x, node.position.y]
	GameState.visited_nodes[key] = true
	node.is_visited = true
	node.is_available = false
	GameState.last_selected_node_type = node.node_type
	print("保存节点类型: ", node.node_type, " (BOSS=", MapNode.NodeType.BOSS, ")")
	_load_combat_for_node(node)

# ---- 战斗完成回调 ----
func _on_battle_completed(winning_team: int, is_boss: bool = false):
	if not is_boss and GameState.current_map_data:
		is_boss = (GameState.current_map_data.node_type == MapNode.NodeType.BOSS)
		print("从 GameState 读取的节点类型: ", GameState.current_map_data.node_type, " 是否为BOSS: ", is_boss)

	if winning_team == 0:
		if is_boss:
			print("Boss 战胜利，进入下一天")
			var has_next = LevelManager.advance_day()
			if not has_next:
				print("所有天数完成，重置存档并回到单位选择界面")
				# 重置所有游戏数据
				GameState.reset_all()
				# 清除当前地图数据，防止残留
				GameState.current_map_data = null
				# 重置 LevelManager
				LevelManager.reset()
				# 覆盖保存到当前槽
				if SaveManager.current_slot != -1:
					SaveManager.save_game(SaveManager.current_slot, false)
				# 立即切换到单位选择界面
				get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")
				return
		if map_data and map_data.root_node:
			_update_availability(map_data.root_node)
			_save_game()
	else:
		print("战斗失败，可重新尝试")

# ---- 加载战斗 ----
func _load_combat_for_node(node: MapNode):
	var map_to_load = node.map_data
	if not map_to_load:
		if not level_list.is_empty():
			map_to_load = level_list[0]
			print("使用备用地图：", map_to_load.map_name)
		else:
			print("错误：没有可用的地图数据")
			_on_back_pressed()
			return
	_load_combat(map_to_load)

func _load_combat(map_data_arg: MapData):
	if not map_data_arg:
		map_data_arg = _create_default_map()
	elif not map_data_arg.scene:
		map_data_arg = _create_default_map()
	print("加载战斗场景: ", map_data_arg.map_name)
	GameState.current_map_data = map_data_arg
	Globals.reset_all_game_state()
	get_tree().change_scene_to_file("res://content/scenes/ui/Loading.tscn")

func _create_default_map() -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	map.map_size = Vector2i(20, 15)
	return map

# ---- 返回主菜单 ----
func _on_back_pressed():
	print("返回主菜单，清空地图进度")
	GameState.visited_nodes.clear()
	MusicManager.stop_music()
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

# ---- 获取当前选中的节点ID（用于存档） ----
func get_selected_node_id() -> String:
	if selected_node:
		return selected_node.node_id
	return ""
