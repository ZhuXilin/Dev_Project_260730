extends CanvasLayer

# ---- 变量声明 ----
var current_day: int = 1
var map_data: MapLevelData
var selected_node: MapNode = null
var level_list: Array[MapData] = []

# ---- 节点引用 ----
@onready var node_container = $NodeContainer
@onready var info_panel = $InfoPanel
@onready var info_label = $InfoPanel/InfoLabel
@onready var back_button = $BottomBar/BackButton
@onready var day_label = $TopBar/DayLabel
@onready var line_container = $NodeContainer/LineContainer

func _ready():
	# ---- 优先处理 Boss 胜利后的天数推进 ----
	if GameState.should_advance_day:
		GameState.should_advance_day = false
		print("检测到 Boss 胜利，推进天数")
		# 清空 resume_node_id，防止自动进入节点
		GameState.resume_node_id = ""
		var has_next = LevelManager.advance_day()
		if not has_next:
			get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")
			return
		current_day = LevelManager.current_day + 1
		GameState.current_day = current_day
		level_list = LevelManager.get_current_day_levels()
		generate_map(current_day)
		SaveManager.auto_save()
		_setup_ui()
		return

	# ---- 检查是否从存档恢复 ----
	if GameState.cached_map_level_data and GameState.cached_day == GameState.current_day:
		print("使用缓存地图数据恢复，天数：", GameState.current_day)
		current_day = GameState.current_day
		map_data = GameState.cached_map_level_data

		# 检查 Boss 是否已击败（用于恢复时自动推进）
		var boss_defeated = false
		for node in map_data.nodes:
			if node.node_type == MapNode.NodeType.BOSS and node.is_visited:
				boss_defeated = true
				break

		if boss_defeated:
			print("Boss 已击败，自动推进天数")
			GameState.resume_node_id = ""
			var has_next = LevelManager.advance_day()
			if not has_next:
				get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")
				return
			current_day = LevelManager.current_day + 1
			GameState.current_day = current_day
			level_list = LevelManager.get_current_day_levels()
			generate_map(current_day)
			SaveManager.auto_save()
			_setup_ui()
			return

		# 否则正常恢复地图（未击败 Boss）
		_draw_connections()
		_create_node_buttons()
		if map_data and map_data.root_node:
			_update_availability(map_data.root_node)
		else:
			_update_buttons()
		if GameState.resume_node_id != "":
			_select_node_by_id(GameState.resume_node_id)
		SaveManager.auto_save()
		_setup_ui()
		return

	# ---- 正常生成地图（首次进入或非恢复） ----
	current_day = LevelManager.current_day + 1
	level_list = LevelManager.get_current_day_levels()
	if level_list.is_empty():
		print("警告：当前天没有关卡数据，使用默认地图")
		var default_map = MapData.new()
		default_map.map_name = "默认战斗"
		level_list.append(default_map)

	if GameState.cached_map_level_data and GameState.cached_day == GameState.current_day:
		# 如果有缓存（例如从自动存档恢复），直接使用
		print("使用缓存地图数据，天数：", GameState.current_day)
		map_data = GameState.cached_map_level_data
		_draw_connections()
		_create_node_buttons()
		if map_data and map_data.root_node:
			_update_availability(map_data.root_node)
		else:
			_update_buttons()
		if GameState.resume_node_id != "":
			_select_node_by_id(GameState.resume_node_id)
	else:
		print("生成新地图，天数：", current_day)
		generate_map(current_day)
		# 生成后自动存档
		SaveManager.auto_save()

	_setup_ui()

# ---- 辅助函数 ----
func _setup_ui():
	Globals.reset_battle_turn()   # 进入地图时重置单局回合数
	info_panel.visible = false
	day_label.text = "第 %d 天" % current_day
	_safe_connect(back_button, "pressed", Callable(self, "_on_back_pressed"))
	if not SignalBus.battle_completed.is_connected(_on_battle_completed):
		SignalBus.battle_completed.connect(_on_battle_completed)
	if MusicManager.config and MusicManager.config.map_music:
		MusicManager.play_music(MusicManager.config.map_music)

# ---- 根据 ID 选择节点 ----
func _select_node_by_id(node_id: String):
	for child in node_container.get_children():
		if child is MapNodeButton and child.map_node and child.map_node.node_id == node_id:
			on_node_selected(child.map_node)
			break

func _safe_connect(source: Object, signal_name: String, target_callable: Callable):
	if source.is_connected(signal_name, target_callable):
		source.disconnect(signal_name, target_callable)
	source.connect(signal_name, target_callable)

func generate_map(day: int):
	print("=== 生成地图，天数：", day)
	map_data = MapGenerator.generate_day(day, level_list)
	# 缓存
	GameState.cached_map_level_data = map_data
	GameState.cached_day = day
	# 恢复访问状态
	for node in map_data.nodes:
		var key = "%d_%d" % [node.position.x, node.position.y]
		if GameState.visited_nodes.has(key):
			node.is_visited = true
			node.is_available = false
	_draw_connections()
	_create_node_buttons()
	_update_availability(map_data.root_node)
	day_label.text = "第 %d 天" % day

func _draw_connections():
	for child in line_container.get_children():
		child.queue_free()
	for node in map_data.nodes:
		for conn in node.connected_nodes:
			var line = Line2D.new()
			line.add_point(node.position)
			line.add_point(conn.position)
			line.width = 2
			line.default_color = Color(0.5, 0.5, 0.5, 0.6)
			line_container.add_child(line)

func _create_node_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.queue_free()
	for node in map_data.nodes:
		var btn = MapNodeButton.new()
		btn.setup(node, self)
		node_container.add_child(btn)

func _update_availability(start_node: MapNode):
	# 1. 计算当前最大已访问层
	var max_visited_layer = -1
	for node in map_data.nodes:
		if node.is_visited and node.layer > max_visited_layer:
			max_visited_layer = node.layer
	print("最大已访问层: ", max_visited_layer)

	# 2. 重置所有节点为不可用
	for node in map_data.nodes:
		node.is_available = false

	# 3. 如果起点未访问，则起点可用
	if not start_node.is_visited:
		start_node.is_available = true
		print("起点未访问，设为可用")
	else:
		# 否则，解锁下一层（max_visited_layer + 1）
		var next_layer = max_visited_layer + 1
		for node in map_data.nodes:
			if node.layer == next_layer and not node.is_visited:
				node.is_available = true
				print("解锁节点: ", node.custom_label, " 层: ", node.layer)

	# 4. 刷新按钮
	_update_buttons()

func _update_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.setup(child.map_node, self)

func on_node_selected(node: MapNode):
	if not node.is_available or node.is_visited:
		print("节点不可选或已访问")
		return
	var key = "%d_%d" % [node.position.x, node.position.y]
	GameState.visited_nodes[key] = true
	node.is_visited = true
	node.is_available = false

	# 保存节点类型
	GameState.last_selected_node_type = node.node_type
	print("保存节点类型: ", node.node_type, " (BOSS=", MapNode.NodeType.BOSS, ")")

	# 所有节点都进入地图
	_load_combat_for_node(node)

func _on_battle_completed(winning_team: int, is_boss: bool = false):
	# 备选：如果信号参数未正确传递，则从 GameState 读取
	if not is_boss and GameState.current_map_data:
		is_boss = (GameState.current_map_data.node_type == MapNode.NodeType.BOSS)
		print("从 GameState 读取的节点类型: ", GameState.current_map_data.node_type, " 是否为BOSS: ", is_boss)

	if winning_team == 0:
		if is_boss:
			print("Boss 战胜利，进入下一天")
			var has_next = LevelManager.advance_day()
			if not has_next:
				get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")
				return
			var new_day = LevelManager.current_day + 1
			current_day = new_day
			GameState.current_day = new_day
			level_list = LevelManager.get_current_day_levels()
			generate_map(new_day)
			SaveManager.auto_save()
			return
		if map_data and map_data.root_node:
			_update_availability(map_data.root_node)
			# 普通战斗后自动存档
			SaveManager.auto_save()
	else:
		print("战斗失败，可重新尝试")

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
	GameState.current_map_data = map_data_arg   # 改为 GameState
	Globals.reset_all_game_state()
	get_tree().change_scene_to_file("res://content/scenes/ui/Loading.tscn")

func _create_default_map() -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	map.map_size = Vector2i(20, 15)
	return map

func _on_back_pressed():
	print("返回主菜单，清空地图进度")
	GameState.visited_nodes.clear()
	MusicManager.stop_music()
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

func get_selected_node_id() -> String:
	if selected_node:
		return selected_node.node_id
	return ""
