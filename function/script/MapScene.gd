extends CanvasLayer

var current_day: int = 1
var map_data: MapLevelData
var selected_node: MapNode = null
var level_list: Array[MapData] = []

@onready var node_container = $NodeContainer
@onready var info_panel = $InfoPanel
@onready var info_label = $InfoPanel/InfoLabel
@onready var back_button = $BottomBar/BackButton
@onready var day_label = $TopBar/DayLabel
@onready var line_container = $NodeContainer/LineContainer

func _ready():
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
	
	# ---- 播放地图音乐 ----
	if MusicManager.config and MusicManager.config.map_music:
		MusicManager.play_music(MusicManager.config.map_music)

func _safe_connect(source: Object, signal_name: String, target_callable: Callable):
	if source.is_connected(signal_name, target_callable):
		source.disconnect(signal_name, target_callable)
	source.connect(signal_name, target_callable)

func generate_map(day: int):
	map_data = MapGenerator.generate_day(day, level_list)
	_draw_connections()
	_create_node_buttons()
	_update_availability(map_data.root_node)

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
		btn.setup(node)
		node_container.add_child(btn)

func _update_availability(start_node: MapNode):
	for node in map_data.nodes:
		node.is_available = false
	if not start_node.is_visited:
		start_node.is_available = true
	
	var queue = [start_node]
	var visited = []
	while queue:
		var current = queue.pop_front()
		if current in visited:
			continue
		visited.append(current)
		if current.is_visited:
			for conn in current.connected_nodes:
				conn.is_available = true
				queue.append(conn)
	_update_buttons()

func _update_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.setup(child.map_node)

# ---- 点击节点直接进入战斗 ----
func on_node_selected(node: MapNode):
	print("on_node_selected 被调用, 节点:", node.node_type)
	if not node.is_available or node.is_visited:
		print("节点不可选或已访问")
		return
	selected_node = node
	# 直接进入战斗
	_load_combat_for_node(selected_node)

func _load_combat_for_node(node: MapNode):
	var map_to_load = node.map_data
	if not map_to_load:
		if not level_list.is_empty():
			map_to_load = level_list[0]
			print("使用备用地图: ", map_to_load.map_name)
		else:
			print("错误：没有可用的地图数据")
			_on_back_pressed()
			return
	_load_combat(map_to_load)

func _load_combat(map_data_arg: MapData):
	print("加载战斗场景: ", map_data_arg.map_name)
	Globals.current_map_data = map_data_arg
	Globals.reset_all_game_state()
	get_tree().change_scene_to_file("res://content/scenes/levels/Battlefield.tscn")

func _on_back_pressed():
	print("返回主菜单")
	MusicManager.stop_music()
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

func _on_battle_completed(winning_team: int):
	if winning_team == 0:
		if selected_node:
			selected_node.is_completed = true
			selected_node.is_visited = true
			_update_availability(map_data.root_node)
			_update_buttons()
	else:
		print("战斗失败，可重新尝试")
