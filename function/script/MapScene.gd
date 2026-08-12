extends CanvasLayer

# ---- 变量声明 ----
var current_day: int = 1
var map_data: MapLevelData
var selected_node: MapNode = null
var level_list: Array[MapData] = []

# ---- 节点引用（与场景结构严格对应） ----
@onready var node_container = $NodeContainer
@onready var line_container = $NodeContainer/LineContainer
@onready var info_panel = $InfoPanel
@onready var info_label = $InfoPanel/InfoLabel
@onready var day_label = $TopBar/DayLabel
@onready var soul_label = $TopBar/SoulLabel
@onready var gold_label = $TopBar/GoldLabel
@onready var interrupt_btn = $BottomBar/InterruptButton
@onready var abandon_btn = $BottomBar/AbandonButton

func _ready():
	print("=== MapScene _ready 开始 ===")
	print("当前 temp_gold=", GameState.temp_gold, " temp_soul=", GameState.temp_soul)

	if GameState.party.is_empty():
		print("队伍为空，返回营地")
		GameState.cached_map_level_data = null
		GameState.current_map_data = null
		GameState.interrupt_state = 1
		SaveManager.save_game(SaveManager.current_slot, false)
		get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")
		return

	# ---- 确保信号连接（关键） ----
	if not SignalBus.battle_completed.is_connected(_on_battle_completed):
		SignalBus.battle_completed.connect(_on_battle_completed)
		print("MapScene 已连接 battle_completed 信号")
	
	# 同步天数
	LevelManager.current_day = GameState.current_day - 1

	# ---- 1. 优先处理 Boss 胜利后的天数推进 ----
	if GameState.should_advance_day:
		GameState.should_advance_day = false
		GameState.resume_node_id = ""
		print("检测到 Boss 胜利，推进天数")
		var has_next = LevelManager.advance_day()
		if not has_next:
			# 三天完成，合并资源并重置
			GameState.finish_cycle()
			GameState.reset_for_new_cycle()
			GameState.interrupt_state = 1
			_save_game()
			var dialog = AcceptDialog.new()
			dialog.dialog_text = "恭喜完成所有冒险！\n获得魂：%d" % GameState.soul
			add_child(dialog)
			dialog.popup_centered()
			dialog.confirmed.connect(_on_cycle_complete)
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

	# 检查缓存地图
	if GameState.cached_map_level_data and GameState.cached_day == GameState.current_day:
		print("使用缓存地图数据恢复，天数：", GameState.current_day)
		map_data = GameState.cached_map_level_data

		# 检测连接是否丢失
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

		if GameState.resume_node_id != "":
			_select_node_by_id(GameState.resume_node_id)
			GameState.resume_node_id = ""
	else:
		print("生成新地图，天数：", current_day)
		generate_map(current_day)

	# 中断状态设为地图
	GameState.interrupt_state = 2
	_save_game()
	_setup_ui()
	update_all_displays()
	print("MapScene _ready: temp_soul=", GameState.temp_soul, " temp_gold=", GameState.temp_gold)
	
func _save_game():
	if Globals.pending_save_slot != -1:
		SaveManager.save_game(Globals.pending_save_slot)
		Globals.pending_save_slot = -1
	else:
		SaveManager.auto_save()

func update_all_displays():
	if soul_label:
		soul_label.text = "魂:" + str(GameState.temp_soul)
		print("update_all_displays: 设置 soul_label 为 ", soul_label.text)
	else:
		print("警告：soul_label 为 null，请检查节点名称")
	
	if gold_label:
		gold_label.text = "金币:" + str(GameState.temp_gold)
		print("update_all_displays: 设置 gold_label 为 ", gold_label.text)
	else:
		print("警告：gold_label 为 null，请检查节点名称")

func update_gold_display():
	gold_label.text = "金币:" + str(GameState.temp_gold)

func update_soul_display():
	soul_label.text = "魂:" + str(GameState.soul)

# ---- 按钮回调 ----
func _on_interrupt_pressed():
	GameState.interrupt_state = 2
	_save_game()
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

# AbandonButton 逻辑不变
func _on_abandon_pressed():
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "确定放弃本局游戏吗？进度将丢失，已获得的临时资源将丢弃。"
	confirm.ok_button_text = "放弃"
	confirm.cancel_button_text = "取消"
	add_child(confirm)
	confirm.popup_centered()
	confirm.confirmed.connect(_on_abandon_confirmed)

func _on_abandon_confirmed():
	GameState.abandon_cycle()
	GameState.reset_all()
	GameState.interrupt_state = 1
	_save_game()
	get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")

# ---- 战斗完成回调 ----
# MapScene.gd
func _on_battle_completed(winning_team: int, is_boss: bool = false):
	print("=== MapScene._on_battle_completed 被触发 ===")
	print("winning_team=", winning_team, " is_boss=", is_boss)

	if not is_boss and GameState.current_map_data:
		is_boss = (GameState.current_map_data.node_type == MapNode.NodeType.BOSS)

	if winning_team == 0:
		# ---- 玩家胜利 ----
		# 资源已在 Battlefield 中累加，此处只需更新显示和保存
		update_all_displays()
		_save_game()

		if is_boss:
			# =========================================================
			# ★★★ Boss 胜利分支 ★★★
			# =========================================================
			print("检测到 Boss 胜利，推进天数")
			# 清除推进标记，防止重复触发
			GameState.should_advance_day = false

			var has_next = LevelManager.advance_day()
			if not has_next:
				# ---- 三天全部完成 ----
				GameState.finish_cycle()          # 将临时资源转入永久
				GameState.reset_for_new_cycle()   # 重置进度（保留永久资源）
				GameState.interrupt_state = 1
				_save_game()
				var dialog = AcceptDialog.new()
				dialog.dialog_text = "恭喜完成所有冒险！\n获得魂：%d" % GameState.soul
				add_child(dialog)
				dialog.popup_centered()
				dialog.confirmed.connect(_on_cycle_complete)
				return

			# ---- 还有下一天 ----
			var new_day = LevelManager.current_day + 1
			current_day = new_day
			GameState.current_day = new_day
			level_list = LevelManager.get_current_day_levels()

			# ★ 单位解锁由事件驱动，不再在这里调用 Globals.apply_day_unlocks ★

			# 生成新地图
			generate_map(new_day)
			_setup_ui()
			update_all_displays()      # 刷新资源显示
			_save_game()               # 保存进度（含解锁状态）
			print("Boss 胜利：进入第 ", new_day, " 天")
			return

		# ---- 普通战斗胜利 ----
		if map_data and map_data.root_node:
			_update_availability(map_data.root_node)
			_save_game()
	else:
		print("战斗失败，可重新尝试")

func _on_cycle_complete():
	GameState.interrupt_state = 1
	_save_game()
	get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")

# ---- 地图绘制与节点管理 ----
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

func _draw_connections():
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

func _create_node_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.queue_free()
	if not map_data:
		return
	for node in map_data.nodes:
		var btn = MapNodeButton.new()
		btn.setup(node, self)
		node_container.add_child(btn)

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

func _update_buttons():
	for child in node_container.get_children():
		if child is MapNodeButton:
			child.setup(child.map_node, self)

func generate_map(day: int):
	print("=== generate_map 开始，day=", day, " temp_gold=", GameState.temp_gold)
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
	update_all_displays()
	print("=== generate_map 结束，temp_gold=", GameState.temp_gold)

func _setup_ui():
	Globals.reset_battle_turn()
	info_panel.visible = false
	day_label.text = "第 %d 天" % current_day
	if MusicManager.config and MusicManager.config.map_music:
		MusicManager.play_music(MusicManager.config.map_music)

# ---- 节点选择与战斗加载 ----
func _select_node_by_id(node_id: String):
	for child in node_container.get_children():
		if child is MapNodeButton and child.map_node and child.map_node.node_id == node_id:
			on_node_selected(child.map_node)
			break

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

func _load_combat_for_node(node: MapNode):
	var map_to_load = node.map_data
	if not map_to_load:
		if not level_list.is_empty():
			map_to_load = level_list[0]
			print("使用备用地图：", map_to_load.map_name)
		else:
			print("错误：没有可用的地图数据，回到营地")
			GameState.interrupt_state = 1
			_save_game()
			get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")
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

# ---- 获取选中节点ID（用于存档） ----
func get_selected_node_id() -> String:
	if selected_node:
		return selected_node.node_id
	return ""
