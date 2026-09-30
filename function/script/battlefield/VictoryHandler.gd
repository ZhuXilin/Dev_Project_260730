class_name VictoryHandler
extends Node

var _bf : Node2D

const RARE_DROP_CHANCE : Dictionary = {
	MapNode.NodeType.START: 0.05,
	MapNode.NodeType.NORMAL: 0.05,
	MapNode.NodeType.ELITE: 0.25,
	MapNode.NodeType.BOSS: 0.80,
}


func _init(bf: Node2D):
	_bf = bf


# ============================================================
#  SignalBus.request_show_victory 回调
# ============================================================
func on_request_show_victory(winning_team: int) -> void:
	print("=== _on_request_show_victory 被调用, _victory_processed: ", _bf._victory_processed)
	await _bf._wait_for_ui_clear()

	if _bf._victory_processed:
		print("胜利已处理，跳过重复调用")
		return
	_bf._victory_processed = true
	print("胜利处理开始")

	var tree = get_tree()
	if not tree:
		print("错误：无法获取场景树，无法处理胜利")
		_bf._victory_processed = false
		return

	if is_instance_valid(_bf.movement_animator):
		_bf.movement_animator.cancel_movement()
	if is_instance_valid(_bf.camera_controller):
		_bf.camera_controller.cancel_smooth_move()
	if is_instance_valid(_bf.highlight_manager):
		_bf.highlight_manager.clear_highlight()
	_bf._cursor_controller.clear_attack_indicator()
	TurnManager.clear_ai_state()

	# ★ 所有面板走 PanelRevealer 隐藏
	if is_instance_valid(_bf.ui_manager):
		_bf.ui_manager.hide_menu()
	if is_instance_valid(_bf.action_panel):
		PanelRevealer.hide_panel(_bf.action_panel)
	if is_instance_valid(_bf.equip_menu):
		PanelRevealer.hide_panel(_bf.equip_menu)
	if is_instance_valid(_bf.menu_blocker):
		_bf.menu_blocker.visible = false
	if is_instance_valid(_bf.info_panel):
		_bf.info_panel.visible = false
	if is_instance_valid(_bf.setting_panel):
		PanelRevealer.hide_panel(_bf.setting_panel)
	if is_instance_valid(_bf.team_view_panel):
		PanelRevealer.hide_panel(_bf.team_view_panel)
	if is_instance_valid(_bf.setting_menu_panel):
		PanelRevealer.hide_panel(_bf.setting_menu_panel)
	if is_instance_valid(_bf.item_list_panel):
		PanelRevealer.hide_panel(_bf.item_list_panel)

	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	InputManager.current_move_attack_targets = {}

	var is_win = (winning_team == 0)
	var is_last = LevelManager.is_last_level()

	var is_boss = (_bf.current_node_type == MapNode.NodeType.BOSS)
	if not is_boss and GameState.current_map_data:
		is_boss = (GameState.current_map_data.node_type == MapNode.NodeType.BOSS)
	print("is_boss 判断结果：", is_boss, " current_node_type=", _bf.current_node_type)

	var player_units = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			player_units.append(unit)
	GameState.sync_units_from_battlefield(player_units)

	# ============================================================
	# 地图模式
	# ============================================================
	if Globals.is_map_mode:
		print("当前地图节点类型: ", _bf.current_node_type, " 是否为BOSS: ", is_boss)

		if is_win:
			var is_non_combat_node = _bf.current_node_type in [
				MapNode.NodeType.SHOP,
				MapNode.NodeType.TREASURE,
				MapNode.NodeType.FORGE,
			]

			if not is_non_combat_node:
				var reward = EconomyManager.get_battle_reward(_bf.current_node_type, is_boss)
				var gold_gain = reward.gold
				var soul_gain = reward.soul
				var materials = reward.materials

				print("--- 奖励配置 ---")
				print("gold_gain: ", gold_gain)
				print("soul_gain: ", soul_gain)
				print("materials: ", materials)

				GameState.current_reward_gold = gold_gain
				GameState.current_reward_soul = soul_gain
				GameState.current_reward_materials = materials

				EconomyManager.add_temp_gold(gold_gain)
				EconomyManager.add_temp_soul(soul_gain)
				EconomyManager.apply_material_reward(materials)

				GameState.current_reward_rare_datas.clear()
				var rare_drop : Dictionary = roll_rare_drop_for_node(_bf.current_node_type)
				if not rare_drop.is_empty():
					var rare_data : ItemData = apply_rare_drop(rare_drop)
					if rare_data:
						GameState.current_reward_rare_datas.append(rare_data)

				print("--- 资源累加完成 ---")
				print("temp_gold: ", GameState.temp_gold)
				print("temp_soul: ", GameState.temp_soul)
				print("materials: ", GameState.materials)
			else:
				print("非战斗地图，不累加资源")
				GameState.current_reward_gold = 0
				GameState.current_reward_soul = 0
				GameState.current_reward_materials = {}

		if is_win and is_boss:
			GameState.should_advance_day = true

		SignalBus.battle_completed.emit(winning_team, is_boss)

		if is_win:
			if is_last:
				MusicManager.play_win_game_music()
			else:
				MusicManager.play_victory_music()
		else:
			MusicManager.play_defeat_music()

		if is_instance_valid(_bf.ui_manager):
			if is_win:
				if is_last:
					_bf.ui_manager.show_victory("全部胜利！", "回到营地", on_map_victory_continue)
				else:
					_bf.ui_manager.show_victory("战斗胜利！", "继续旅程", on_map_victory_continue)
			else:
				_bf.ui_manager.show_victory("战斗失败", "重启旅程", on_map_defeat_gameover)
		else:
			if is_win:
				tree.change_scene_to_file(Config.PATHS.MAP_SCENE)
			else:
				GameState.reset_all()
				tree.change_scene_to_file(Config.PATHS.UNIT_SELECT_UI)
		return

	# ============================================================
	# 非地图模式
	# ============================================================
	print("非地图模式（旧版流程）")
	if is_win and is_last:
		MusicManager.play_win_game_music()
	elif is_win:
		MusicManager.play_victory_music()
	else:
		MusicManager.play_defeat_music()

	if is_win:
		if is_last:
			_bf.ui_manager.show_victory("全部胜利", "回到营地", LevelManager.on_victory)
		else:
			_bf.ui_manager.show_victory("战斗胜利", "下一关", LevelManager.on_victory)
	else:
		_bf.ui_manager.show_victory("战斗失败", "回到营地", on_non_map_defeat)


# ============================================================
#  地图模式：胜利继续
# ============================================================
func on_map_victory_continue() -> void:
	print("=== _on_map_victory_continue ===")
	print("reward_gold: ", GameState.current_reward_gold)
	print("reward_soul: ", GameState.current_reward_soul)
	print("reward_materials: ", GameState.current_reward_materials)
	print("reward_items: ", GameState.reward_items)
	print("current_node_key: ", GameState.current_node_key)
	print("current_node_type: ", _bf.current_node_type)

	var reward_gold = GameState.current_reward_gold
	var reward_soul = GameState.current_reward_soul
	var reward_materials = GameState.current_reward_materials

	var reward_item_datas: Array = []
	for item_id in GameState.reward_items:
		var data = ItemManager.get_item_data(item_id)
		if data:
			reward_item_datas.append(data)
		else:
			var relic_data = RelicManager.get_relic_data(item_id)
			if not relic_data.is_empty():
				var virtual_data = ItemData.new()
				virtual_data.id = item_id
				virtual_data.name = relic_data.get("name", "未知遗物")
				var icon_path = relic_data.get("icon", "")
				if icon_path != "" and ResourceLoader.exists(icon_path):
					virtual_data.icon = load(icon_path)
				reward_item_datas.append(virtual_data)

	if reward_materials and not reward_materials.is_empty():
		for material_name in reward_materials:
			var amount = reward_materials[material_name]
			if amount > 0:
				var data = ItemData.new()
				data.id = "material_" + material_name
				data.name = material_name + " x" + str(amount)
				data.description = "材料 x" + str(amount)
				reward_item_datas.append(data)
				print("添加材料显示: ", data.name)

	for rare_data in GameState.current_reward_rare_datas:
		if rare_data:
			reward_item_datas.append(rare_data)
			print("添加稀有掉落显示: ", rare_data.name)

	var all_relic_ids : Array = []
	if GameState.current_map_data and GameState.current_map_data.unlock_relics:
		all_relic_ids.append_array(GameState.current_map_data.unlock_relics)
	if GameState.current_node_unlock_relics:
		all_relic_ids.append_array(GameState.current_node_unlock_relics)

	if not all_relic_ids.is_empty():
		var seen : Dictionary = {}
		var unique_relics : Array = []
		for rid in all_relic_ids:
			if rid is String and rid != "" and not seen.has(rid):
				seen[rid] = true
				unique_relics.append(rid)

		var newly : Array = []
		for rid in unique_relics:
			if not RelicManager.is_relic_unlocked(rid):
				newly.append(rid)

		RelicManager.unlock_relics_by_ids(unique_relics)

		for rid in newly:
			var rd : Dictionary = RelicManager.get_relic_data(rid)
			var virtual_data := ItemData.new()
			virtual_data.id = "unlock_relic_" + rid
			virtual_data.name = "★ 新遗物：" + rd.get("name", rid)
			virtual_data.description = rd.get("description", "")
			var icon_path : String = rd.get("icon", "")
			if icon_path != "" and ResourceLoader.exists(icon_path):
				virtual_data.icon = load(icon_path)
			reward_item_datas.append(virtual_data)
		if not newly.is_empty():
			print("[Battlefield] 本节点解锁 %d 个遗物" % newly.size())

	GameState.current_node_unlock_relics.clear()

	var has_reward = (reward_gold > 0 or reward_soul > 0 or not reward_item_datas.is_empty())

	var is_boss = (_bf.current_node_type == MapNode.NodeType.BOSS)
	if not is_boss and GameState.current_map_data:
		is_boss = (GameState.current_map_data.node_type == MapNode.NodeType.BOSS)

	var is_last_day = (GameState.current_day >= 3)

	print("is_boss=", is_boss, " is_last_day=", is_last_day, " has_reward=", has_reward)

	var need_ui_block = has_reward or is_boss
	if need_ui_block:
		_bf._is_reward_ui_active = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_bf.cursor.visible = false

	var summary = null
	if has_reward:
		print("有奖励，弹出结算界面")
		summary = Globals.get_reward_summary()
		if summary:
			summary.setup_reward(reward_gold, reward_soul, reward_item_datas, false, "关卡结算")
			summary.open()
			await summary.confirmed
			print("结算界面已确认，summary 保持可见")
		else:
			push_error("Battlefield: 无法获取 RewardSummaryUI 实例")

	if is_boss:
		GameState.should_advance_day = true
		print("Boss 胜利，设置 should_advance_day = true")

		if is_last_day:
			print("第三天最终Boss，跳过遗物三选一和英灵殿")
		else:
			print("弹出遗物三选一，叠加在结算之上")
			var relic_select_scene = load(Config.PATHS.RELIC_SELECT_UI)
			var relic_select = relic_select_scene.instantiate()
			_bf.add_child(relic_select)

			var owned_ids = []
			for relic in GameState.get_relics_from_passives():
				owned_ids.append(relic.item_id)

			relic_select.setup_options(owned_ids)

			await relic_select.relic_selected
			print("遗物选择完成")

			print("弹出英灵殿")
			var hero_shrine_scene = load(Config.PATHS.HERO_SHRINE_UI)
			if hero_shrine_scene:
				var hero_shrine = hero_shrine_scene.instantiate()
				_bf.add_child(hero_shrine)
				hero_shrine.setup_map(1)
				await hero_shrine.closed
				print("英灵殿关闭")
			else:
				push_warning("HeroShrineUI 场景未找到")

	if summary:
		print("结算界面已关闭")

	if need_ui_block:
		_bf._is_reward_ui_active = false
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_bf.cursor.visible = true

	if GameState.current_node_key != "":
		GameState.visited_nodes[GameState.current_node_key] = true
		GameState.current_node_key = ""

	GameState.reward_items.clear()
	GameState.clear_current_reward()
	SaveManager.auto_save()

	print("切换场景到 MapScene")
	get_tree().change_scene_to_file(Config.PATHS.MAP_SCENE)


# ============================================================
#  放弃战斗 / 重试
# ============================================================
func execute_abandon_battle() -> void:
	Globals.is_transitioning = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _bf.cursor:
		_bf.cursor.visible = false

	GameState.current_node_key = ""
	Globals.is_performing_action = false
	TurnManager.is_game_over = true
	GameState.abandon_and_return_to_camp()


func on_map_defeat_gameover() -> void:
	execute_abandon_battle()


func on_non_map_defeat() -> void:
	execute_abandon_battle()


func on_retry_battle() -> void:
	if GameState.current_node_key != "":
		GameState.visited_nodes.erase(GameState.current_node_key)
		GameState.current_node_key = ""
	get_tree().change_scene_to_file(Config.PATHS.MAP_SCENE)


# ============================================================
#  稀有掉落（保持原样）
# ============================================================
func roll_rare_drop_for_node(node_type: int) -> Dictionary:
	var chance : float = RARE_DROP_CHANCE.get(node_type, 0.0)
	if randf() > chance:
		return {}

	var pool : Array = []

	var owned_relics : Dictionary = {}
	for relic in GameState.get_relics_from_passives():
		owned_relics[relic.item_id] = true
	for rid in RelicManager.get_unlocked_relics():
		if not owned_relics.has(rid):
			pool.append({"type": "relic", "id": rid})

	for ref_id in RefineManager.get_all_ids():
		if RefineManager.is_recipe_unlocked(ref_id):
			pool.append({"type": "refine", "id": ref_id})

	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if not d: continue
		if d.type != "armor": continue
		if d.quality not in ["epic", "legendary"]: continue
		if d.price <= 0: continue
		pool.append({"type": "armor", "id": iid})

	if pool.is_empty():
		return {}
	pool.shuffle()
	return pool[0]


func apply_rare_drop(drop : Dictionary) -> ItemData:
	var rtype : String = drop.get("type", "")
	var rid : String = drop.get("id", "")
	if rid == "":
		return null
	var virtual_data : ItemData = null

	match rtype:
		"relic":
			var rd : Dictionary = RelicManager.get_relic_data(rid)
			if rd.is_empty(): return null
			RelicManager.unlock_relic(rid)
			var inst := ItemInstance.new()
			inst.item_id = rid
			inst.count = 1
			if not GameState.add_relic_to_passive_slot(inst):
				print("[稀有掉落] 遗物 %s 解锁但未入槽（槽满）" % rid)
			virtual_data = ItemData.new()
			virtual_data.id = "rare_relic_" + rid
			virtual_data.name = "★ 遗物：" + rd.get("name", rid)
			virtual_data.description = rd.get("description", "")
			var icon_path : String = rd.get("icon", "")
			if icon_path != "" and ResourceLoader.exists(icon_path):
				virtual_data.icon = load(icon_path)
			print("[稀有掉落] 遗物 %s" % rid)

		"refine":
			var recipe : Dictionary = RefineManager.get_recipe(rid)
			if recipe.is_empty(): return null
			GameState.refined_items[rid] = GameState.refined_items.get(rid, 0) + 1
			virtual_data = ItemData.new()
			virtual_data.id = "rare_refine_" + rid
			virtual_data.name = "★ 精炼：" + recipe.get("name", rid)
			virtual_data.description = recipe.get("description", "")
			print("[稀有掉落] 精炼 %s" % rid)

		"armor":
			var d : ItemData = ItemManager.get_item_data(rid)
			if not d: return null
			var inst2 := ItemInstance.new()
			inst2.item_id = rid
			inst2.count = 1
			GameState.pending_forge_rewards.append(inst2)
			virtual_data = ItemData.new()
			virtual_data.id = "rare_armor_" + rid
			virtual_data.name = "★ " + d.name
			virtual_data.description = d.description
			virtual_data.icon = d.icon
			virtual_data.quality = d.quality
			print("[稀有掉落] 防具 %s" % rid)

	return virtual_data
