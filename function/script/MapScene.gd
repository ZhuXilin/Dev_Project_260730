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
	# 确保容器节点存在（若场景缺失则动态创建）
	if not node_container:
		node_container = Node2D.new()
		node_container.name = "NodeContainer"
		add_child(node_container)
	if not line_container:
		line_container = Node2D.new()
		line_container.name = "LineContainer"
		node_container.add_child(line_container)
	if not info_panel:
		info_panel = Panel.new()
		info_panel.name = "InfoPanel"
		add_child(info_panel)
		info_label = Label.new()
		info_label.name = "InfoLabel"
		info_panel.add_child(info_label)
	
	# 获取当前天数和关卡列表
	current_day = LevelManager.current_level_index + 1
	level_list = LevelManager.get_levels_for_day(current_day)
	
	if level_list.is_empty():
		print("警告：当前天没有关卡数据，使用默认地图")
		var default_map = MapData.new()
		default_map.map_name = "默认战斗"
		level_list.append(default_map)
	
	generate_map(current_day)
	
	info_panel.visible = false
	day_label.text = "第 %d 天" % current_day
	
	_safe_connect(back_button, "pressed", Callable(self, "_on_back_pressed"))
	
	if not SignalBus.battle_completed.is_connected(_on_battle_completed):
		SignalBus.battle_completed.connect(_on_battle_completed)
	
	# 播放地图音乐
	if MusicManager.config and MusicManager.config.map_music:
		MusicManager.play_music(MusicManager.config.map_music)

# ---- 安全连接（避免重复连接） ----
func _safe_connect(source: Object, signal_name: String, target_callable: Callable):
	if source.is_connected(signal_name, target_callable):
		source.disconnect(signal_name, target_callable)
	source.connect(signal_name, target_callable)

# ---- 生成地图 ----
func generate_map(day: int):
	print("=== 生成地图，关卡数量：", level_list.size())
	for i in range(level_list.size()):
		print("  地图 ", i, "：", level_list[i].map_name)
	
	map_data = MapGenerator.generate_day(day, level_list)
	print("总节点数：", map_data.nodes.size())
	for node in map_data.nodes:
		print("  节点类型:", node.node_type, " 位置:", node.position)
	
	# 恢复已访问状态（从 Globals 读取）
	for node in map_data.nodes:
		var key = "%d_%d" % [node.position.x, node.position.y]
		if Globals.visited_nodes.has(key):
			node.is_visited = true
			node.is_available = false
			print("恢复已访问节点:", node.node_type, " 位置:", node.position)
	
	_draw_connections()
	_create_node_buttons()
	_update_availability(map_data.root_node)

# ---- 绘制连接线 ----
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

# ---- 创建节点按钮 ----
func _create_node_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.queue_free()
	for node in map_data.nodes:
		var btn = MapNodeButton.new()
		btn.setup(node, self)
		node_container.add_child(btn)

# ---- 更新节点可用性（核心解锁逻辑） ----
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
	else:
		# 否则，解锁下一层（max_visited_layer + 1）
		var next_layer = max_visited_layer + 1
		for node in map_data.nodes:
			if node.layer == next_layer and not node.is_visited:
				node.is_available = true
				print("解锁节点: ", node.custom_label, " 层: ", node.layer)

	# 4. 刷新按钮
	_update_buttons()

# ---- 刷新所有按钮状态 ----
func _update_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.setup(child.map_node, self)

# ---- 玩家点击节点（由 MapNodeButton 触发） ----
func on_node_selected(node: MapNode):
	if not node.is_available or node.is_visited:
		print("节点不可选或已访问")
		return
	
	print("选择节点：", node.node_type, " 位置：", node.position)
	
	# 标记为已访问并保存到全局
	var key = "%d_%d" % [node.position.x, node.position.y]
	Globals.visited_nodes[key] = true
	node.is_visited = true
	node.is_available = false
	
	# 进入战斗
	_load_combat_for_node(node)

# ---- 加载节点对应的战斗 ----
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

# ---- 真正切换到战斗场景（通过 Loading 过渡） ----
func _load_combat(map_data_arg: MapData):
	if not map_data_arg:
		print("错误：地图数据为空，使用备用地图")
		map_data_arg = _create_default_map()
	elif not map_data_arg.scene and map_data_arg.unit_configs.is_empty():
		print("警告：地图数据缺少场景和单位配置，使用备用地图")
		map_data_arg = _create_default_map()
	
	print("加载战斗场景：", map_data_arg.map_name)
	Globals.current_map_data = map_data_arg
	Globals.reset_all_game_state()  # 清理战斗相关状态，但保留 visited_nodes
	get_tree().change_scene_to_file("res://content/scenes/ui/Loading.tscn")

# ---- 创建备用地图（当原始数据无效时使用） ----
func _create_default_map() -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	var cfg = UnitConfig.new()
	cfg.unit_name = "剑士"
	cfg.team_id = 0
	cfg.position = Vector2i(10, 10)
	map.unit_configs.append(cfg)
	var enemy_cfg = UnitConfig.new()
	enemy_cfg.unit_name = "斧兵"
	enemy_cfg.team_id = 1
	enemy_cfg.position = Vector2i(5, 5)
	map.unit_configs.append(enemy_cfg)
	return map

# ---- 返回主菜单 ----
func _on_back_pressed():
	print("返回主菜单，清空地图进度")
	Globals.visited_nodes.clear()
	MusicManager.stop_music()
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

# ---- 战斗结束回调（由 SignalBus 触发） ----
func _on_battle_completed(winning_team: int):
	if winning_team == 0:
		print("战斗胜利，重新计算地图可用性")
		if map_data and map_data.root_node:
			_update_availability(map_data.root_node)
	else:
		print("战斗失败，可重新尝试")
		# 失败时不更新状态，玩家可重试
