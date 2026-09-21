extends CanvasLayer

const FONT_SIZE = 8
const EquipmentConfig = preload(Config.PATHS.EQUIPMENT_CONFIG_SCRIPT)

# ---- 变量声明 ----
var current_day: int = 1
var map_data: MapLevelData
var selected_node: MapNode = null
var level_list: Array[MapData] = []
var _equipment_config_instance = null   # 防止重复实例化
var _detail_popup = null
var _ready_guard : bool = false

# ---- 节点引用 ----
@onready var node_container = $NodeContainer
@onready var line_container = $NodeContainer/LineContainer
@onready var info_panel = $InfoPanel
@onready var info_label = $InfoPanel/InfoLabel
@onready var interrupt_btn = $BottomBar/InterruptButton
@onready var abandon_btn = $BottomBar/AbandonButton
@onready var day_label = $TopBar/DayLabel
@onready var soul_label = $TopBar/SoulLabel
@onready var gold_label = $TopBar/GoldLabel
@onready var materials_container = $TopBar/MaterialsContainer

func _ready():
	if _ready_guard:
		print("警告：MapScene._ready 被重复调用，忽略")
		return
	_ready_guard = true

	print("=== MapScene _ready 开始 ===")
	
	# ---- 确保地图模式标志为 true ----
	Globals.is_map_mode = true
	
	# ---- 调试：打印 GameState.party 装备状态 ----
	print("=== MapScene: GameState.party 装备状态 ===")
	for i in range(GameState.party.size()):
		var u = GameState.party[i]
		var weapon_id = u.weapon_slot.item_id if u.weapon_slot else "无"
		print("单位 ", i, ": ", u.unit_name, " 武器: ", weapon_id)
		for j in range(u.armor_slots.size()):
			var slot = u.armor_slots[j]
			var slot_id = slot.item_id if slot else "空"
			print("  防具槽", j, ": ", slot_id)
	print("==========================================")
	
	print("当前 temp_gold=", GameState.temp_gold, " temp_soul=", GameState.temp_soul)
	print("visited_nodes: ", GameState.visited_nodes)
	print("current_node_key: ", GameState.current_node_key)
	print("map_snapshot 节点数: ", GameState.map_snapshot.get("nodes", []).size() if not GameState.map_snapshot.is_empty() else 0)

	if GameState.party.is_empty():
		print("队伍为空，返回营地")
		GameState.cached_map_level_data = null
		GameState.current_map_data = null
		GameState.map_snapshot.clear()
		GameState.interrupt_state = GameState.InterruptState.CAMP
		_save_game()
		get_tree().change_scene_to_file(Config.PATHS.CAMP)
		return
	
	# 同步天数
	LevelManager.current_day = GameState.current_day - 1

	# ---- 1. 优先处理 Boss 胜利后的天数推进 ----
	if GameState.should_advance_day:
		GameState.should_advance_day = false
		GameState.resume_node_id = ""
		print("检测到 Boss 胜利，推进天数")
		var has_next = LevelManager.advance_day()
		print("advance_day 返回：", has_next)
		if not has_next:
			# ---- 合并本轮资源 ----
			GameState.finish_cycle()
			
			# ---- 计算本三天累计获得（在 reset_for_new_cycle 前） ----
			var earned_soul = max(0, GameState.soul - GameState.cycle_start_soul)
			var earned_materials = {}
			for key in GameState.materials:
				var before = GameState.cycle_start_materials.get(key, 0)
				var earned = GameState.materials[key] - before
				if earned > 0:
					earned_materials[key] = earned
			
			# ---- 重置本轮数据 ----
			GameState.reset_for_new_cycle()
			GameState.map_snapshot.clear()
			GameState.interrupt_state = GameState.InterruptState.CAMP
			_save_game()
			
			# ---- 弹出三天结算界面 ----
			await _show_cycle_reward(earned_soul, earned_materials)
			return
		
		# ---- 进入新的一天 ----
		current_day = LevelManager.current_day + 1
		GameState.current_day = current_day
		GameState.finish_day()
		
		# ---- 新的一天，清空旧的地图快照 ----
		GameState.map_snapshot.clear()
		print("新的一天，清空地图快照")
		
		level_list = LevelManager.get_current_day_levels()
		print("新的一天，当前 day=", current_day, " 关卡数：", level_list.size())
		
		# ---- 生成新一天的地图（会同时保存新的快照） ----
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

	# ---- 优先从快照恢复地图，否则生成新地图 ----
	if not GameState.map_snapshot.is_empty() \
			and GameState.map_snapshot.get("day", -1) == current_day:
		print("从快照恢复地图，天数：", current_day)
		_restore_map_from_snapshot()
	else:
		print("生成新地图，天数：", current_day)
		generate_map(current_day)

	# 中断状态设为地图
	GameState.interrupt_state = GameState.InterruptState.MAP
	_save_game()
	_setup_ui()
	update_all_displays()
	print("MapScene _ready: temp_soul=", GameState.temp_soul, " temp_gold=", GameState.temp_gold)
	
	# ---- 创建详情弹窗（隐藏） ----
	_detail_popup = load(Config.PATHS.ITEM_DETAIL_POPUP).instantiate()
	add_child(_detail_popup)
	_detail_popup.visible = false

func _save_game():
	if Globals.pending_save_slot != -1:
		SaveManager.save_game(Globals.pending_save_slot)
		Globals.pending_save_slot = -1
	else:
		SaveManager.auto_save()

func update_all_displays():
	# ---- 统一字体大小 ----
	if day_label:
		day_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if soul_label:
		soul_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if gold_label:
		gold_label.add_theme_font_size_override("font_size", FONT_SIZE)
	
	# 分区标题也统一
	var local_label = $TopBar/LocalResourcesLabel
	if local_label:
		local_label.add_theme_font_size_override("font_size", FONT_SIZE)
	var perm_label = $TopBar/PermanentResourcesLabel
	if perm_label:
		perm_label.add_theme_font_size_override("font_size", FONT_SIZE)
	
	# ---- 更新金币 ----
	if gold_label:
		gold_label.text = "金币: " + str(EconomyManager.get_temp_gold())
	
	# ---- 更新魂 ----
	if soul_label:
		soul_label.text = "魂: " + str(EconomyManager.get_soul() + EconomyManager.get_temp_soul())
	
	# ---- 更新材料（永久资源） ----
	_update_materials_display()

func _update_materials_display():
	for child in materials_container.get_children():
		child.queue_free()
	
	var materials = GameState.get_all_materials()
	var has_material = false
	
	var order = ["粗铁", "精钢", "秘银", "龙鳞"]
	for material_name in order:
		var count = materials.get(material_name, 0)
		if count > 0:
			has_material = true
			var label = Label.new()
			label.text = material_name + ": " + str(count)
			label.add_theme_font_size_override("font_size", FONT_SIZE)
			var color = _get_material_color(material_name)
			if color:
				label.add_theme_color_override("font_color", color)
			materials_container.add_child(label)
	
	if not has_material:
		var label = Label.new()
		label.text = "材料: 无"
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.modulate = Color(0.6, 0.6, 0.6)
		materials_container.add_child(label)

func _get_material_color(material_name: String) -> Color:
	match material_name:
		"粗铁": return Color(0.7, 0.6, 0.5)
		"精钢": return Color(0.5, 0.7, 0.8)
		"秘银": return Color(0.3, 0.8, 0.7)
		"龙鳞": return Color(0.8, 0.6, 0.1)
		_: return Color.WHITE

func update_gold_display():
	gold_label.text = "金币:" + str(EconomyManager.get_temp_gold())

func update_soul_display():
	soul_label.text = "魂:" + str(EconomyManager.get_soul())

# ---- 按钮回调 ----
func _on_interrupt_pressed():
	# ---- 额外保存地图数据到独立文件（兜底） ----
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
			line.width = MapConst.MAP_LINE_WIDTH
			line.default_color = MapConst.MAP_LINE_COLOR
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
	map_data = MapGenerator.generate_day(day, level_list)
	GameState.cached_map_level_data = map_data
	GameState.cached_day = day
	
	# ---- ✨ 生成后立即保存快照 ----
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

# ---- 节点选择与战斗加载 ----
func _select_node_by_id(node_id: String):
	for child in node_container.get_children():
		if child is MapNodeButton and child.map_node and child.map_node.node_id == node_id:
			on_node_selected(child.map_node)
			break

func on_node_selected(node: MapNode):
	if not node.is_available or node.is_visited:
		return
	var key = "%d_%d" % [node.position.x, node.position.y]
	GameState.last_selected_node_type = node.node_type
	print("进入节点: ", key, " 类型: ", node.node_type)
	# ---- 只有战斗节点才记 current_node_key（用于中途退出撤销） ----
	if node.node_type in [
		MapNode.NodeType.START,
		MapNode.NodeType.NORMAL,
		MapNode.NodeType.ELITE,
		MapNode.NodeType.BOSS,
	]:
		GameState.current_node_key = key
	_load_combat_for_node(node)

func _load_combat_for_node(node: MapNode):
	match node.node_type:
		MapNode.NodeType.SHOP:
			_open_shop(node)
			return
		MapNode.NodeType.FORGE:
			_open_forge(node)
			return
		MapNode.NodeType.EVENT:
			_open_treasure(node)
			return

	# 战斗节点：走原流程
	var map_to_load = node.map_data
	if not map_to_load:
		if not level_list.is_empty():
			map_to_load = level_list[0]
			print("使用备用地图：", map_to_load.map_name)
		else:
			print("错误：没有可用的地图数据，回到营地")
			GameState.interrupt_state = GameState.InterruptState.CAMP
			_save_game()
			get_tree().change_scene_to_file(Config.PATHS.CAMP)
			return
	_load_combat(map_to_load)


# ============================================================
#  铁匠铺节点
# ============================================================
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

	# ★ 区分：第 3 天用"铁匠商店"（商店+铁匠铺）；第 1/2 天用"铁匠铺"（仅合成）
	if GameState.current_day >= 3:
		panel.init(unit_names, slot, EquipmentConfig.Mode.MAP_SHOP_REST)
	else:
		panel.init(unit_names, slot, EquipmentConfig.Mode.FORGE)

	await panel.tree_exited

	print("铁匠铺已关闭")
	GameState.current_node_key = ""
	_save_game()
	update_all_displays()
	_update_availability(map_data.root_node)

# ============================================================
#  宝箱 / 事件节点
# ============================================================
func _open_treasure(node: MapNode):
	print("=== 打开宝箱/事件 ===")

	var key = "%d_%d" % [node.position.x, node.position.y]
	GameState.visited_nodes[key] = true
	node.is_visited = true
	node.is_available = false
	# 注意：不设 GameState.current_node_key（非战斗节点，关闭后不可重进）

	info_panel.visible = false
	_update_availability(map_data.root_node)
	_save_game()

	var treasure_scene = load(Config.PATHS.TREASURE_UI)
	if not treasure_scene:
		push_error("Treasure UI 未找到: " + Config.PATHS.TREASURE_UI)
		return
	var treasure = treasure_scene.instantiate()
	add_child(treasure)
	treasure.setup(node.reward)
	await treasure.closed

	print("宝箱/事件已关闭")
	_save_game()
	update_all_displays()
	_update_availability(map_data.root_node)

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

# ---- 获取选中节点ID（用于存档） ----
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
	# 可选：统计已访问节点数
	var visited_count = 0
	for node in map_data.nodes:
		if node.is_visited:
			visited_count += 1
	print("实际已访问节点数：", visited_count)

func _on_config_btn_pressed():
	# ---- 防止重复实例化 ----
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
	
	# 面板销毁时清除引用
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

func _open_shop(node: MapNode):
	print("=== 打开商店 ===")
	
	# ---- 标记节点已访问 ----
	var key = "%d_%d" % [node.position.x, node.position.y]
	GameState.visited_nodes[key] = true
	node.is_visited = true
	node.is_available = false
	
	# ---- 关闭地图交互 ----
	info_panel.visible = false
	_update_availability(map_data.root_node)
	_save_game()
	
	# ---- 弹出商店界面 ----
	var config = load(Config.PATHS.EQUIPMENT_CONFIG).instantiate()
	add_child(config)
	var panel = config.get_node("MainPanel")
	
	var unit_names: Array[String] = []
	for unit_data in GameState.party:
		unit_names.append(unit_data.unit_name)
	
	var slot = SaveManager.current_slot
	if slot == -1:
		slot = SaveManager.find_empty_slot()
	
	panel.init(unit_names, slot, EquipmentConfig.Mode.SHOP)
	
	# ---- 等待商店关闭 ----
	await panel.tree_exited
	
	# ---- 商店关闭后刷新 ----
	print("商店已关闭")
	_save_game()
	update_all_displays()
	_update_availability(map_data.root_node)

# ---- 统一字体大小 ----
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

	# ---- 新增：恢复后重新随机分配地图（丢弃快照里的旧 map_data） ----
	MapGenerator._assign_map_data_to_all_nodes(map_data.nodes)

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

# ---- 三天结算（复用全局 RewardSummaryUI） ----
func _show_cycle_reward(earned_soul: int, earned_materials: Dictionary):
	# ---- 材料转 ItemData（每项 name 带数量，id 用于颜色提取） ----
	var reward_items: Array = []
	var order = ["粗铁", "精钢", "秘银", "龙鳞"]
	for mat_name in order:
		if not earned_materials.has(mat_name):
			continue
		var count = earned_materials[mat_name]
		if count <= 0:
			continue
		var data = ItemData.new()
		data.id = "material_" + mat_name
		data.name = mat_name + " x" + str(count)
		data.description = ""
		reward_items.append(data)
	
	# ---- 复用全局实例 ----
	var summary = Globals.get_reward_summary()
	if not summary:
		push_error("MapScene: 无法获取 RewardSummaryUI 实例，直接进营地")
		_on_cycle_complete()
		return
	
	# ---- 刷新内容为"本轮结算" ----
	summary.setup_reward(0, earned_soul, reward_items, true, "本轮结算")
	summary.open()
	await summary.confirmed
	summary.close()
	
	# ---- 结算完成，进营地 ----
	_on_cycle_complete()

# ============================================================
#  节点信息悬浮显示（MapNodeButton 悬停时调用）
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
	match node.node_type:
		MapNode.NodeType.START:
			return "起始点\n进入战斗"
		MapNode.NodeType.NORMAL:
			return "普通战斗"
		MapNode.NodeType.ELITE:
			return "精英战斗\n敌人更强，奖励更好"
		MapNode.NodeType.SHOP:
			return "商店\n可购买武器与防具"
		MapNode.NodeType.FORGE:
			return "铁匠铺\n合成防具 / 升级武器"
		MapNode.NodeType.EVENT:
			return "宝箱 / 事件"
		MapNode.NodeType.BOSS:
			return "首领战"
		_:
			return "未知节点"
