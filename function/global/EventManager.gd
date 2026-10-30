extends Node

signal event_completed(event_id: String)

var _events: Dictionary = {}
var _completed: Dictionary = {}

func _ready():
	load_events()

func load_events():
	var path = Config.PATHS.EVENT_DATA
	if not FileAccess.file_exists(path):
		print("事件文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("事件 JSON 解析失败")
		return
	_events = data
	print("成功加载 ", _events.size(), " 个事件")

func has_event(event_id: String) -> bool:
	return _events.has(event_id)

func get_event(event_id: String) -> Dictionary:
	return _events.get(event_id, {})

func is_event_completed(event_id: String) -> bool:
	return _completed.get(event_id, false)

func mark_event_completed(event_id: String):
	if _events.has(event_id) and _events[event_id].get("once", true):
		_completed[event_id] = true
		event_completed.emit(event_id)

func register_event(event_id: String, event_def: Dictionary):
	if not _events.has(event_id):
		_events[event_id] = event_def
		print("注册动态事件: ", event_id)
	else:
		print("事件已存在，跳过注册: ", event_id)


func trigger_event(event_id: String, unit: Unit = null, _default_music: AudioStream = null):
	if not _events.has(event_id):
		push_error("未知事件: ", event_id)
		return
	if is_event_completed(event_id):
		print("事件已触发，跳过: ", event_id)
		return

	var event_def = _events[event_id]
	var actions = event_def.get("actions", [])
	print("触发事件: ", event_id, " 动作数: ", actions.size())

	for action in actions:
		var action_type = action.get("type", "")
		match action_type:
			"complete":
				SignalBus.non_combat_complete.emit()
				await get_tree().process_frame

			"dialog":
				var dialog_id: String = str(action.get("dialog_id", ""))
				if dialog_id != "":
					if StoryManager.play_dialogue_by_id(dialog_id):
						await DialogueManager.dialogue_finished

			"give_item":
				if unit == null:
					continue
				var item_id: String = str(action.get("item_id", ""))
				var count: int = int(action.get("count", 1))
				var equip: bool = bool(action.get("equip", false))
				if item_id == "":
					continue
				var relic_data: Dictionary = RelicManager.get_relic_data(item_id)
				if not relic_data.is_empty():
					RelicManager.unlock_relic(item_id)
					GameState.add_reward_item(item_id)
					var inst := ItemInstance.new()
					inst.item_id = item_id
					inst.count = 1
					GameState.add_relic_to_passive_slot(inst)
					await show_item_get_popup(item_id, count)
					continue
				var item_data = ItemManager.get_item_data(item_id)
				if not item_data:
					continue
				if item_data.type in ["heal", "cure", "buff", "attack"]:
					continue
				if item_data.type in ["weapon", "armor"]:
					Globals.unlock_item(item_id)
					GameState.add_reward_item(item_id)
				if equip:
					var inst2 := ItemInstance.new()
					inst2.item_id = item_id
					inst2.count = 1
					if item_data.equipment_slot == "weapon":
						unit.weapon_slot = inst2
					elif item_data.equipment_slot == "armor":
						for i in range(unit.armor_slots.size()):
							if unit.armor_slots[i] == null:
								unit.armor_slots[i] = inst2
								break
				await show_item_get_popup(item_id, count)

			"heal":
				if unit == null:
					continue
				var amt: int = int(action.get("amount", 0))
				var is_pct_h : bool = bool(action.get("percent", false))
				if amt > 0:
					var heal_val : int = amt
					if is_pct_h:
						heal_val = maxi(1, int(unit.unit_stats.max_hp * float(amt) / 100.0))
					unit.hit_points = min(unit.hit_points + heal_val, unit.unit_stats.max_hp)
					unit.update_hp_label()
					SignalBus.request_damage_popup.emit(unit.global_position, heal_val, false, false, true)
					SoundManager.play_heal_sound()
					await get_tree().create_timer(0.3).timeout

			"damage":
				if unit == null:
					continue
				var amt2: int = int(action.get("amount", 0))
				var is_pct_d : bool = bool(action.get("percent", false))
				if amt2 < 0:
					var dmg_val : int = abs(amt2)
					if is_pct_d:
						dmg_val = maxi(1, int(unit.unit_stats.max_hp * float(dmg_val) / 100.0))
					unit.hit_points = max(unit.hit_points - dmg_val, 0)
					unit.update_hp_label()
					SignalBus.request_damage_popup.emit(unit.global_position, dmg_val, false, false, false)
					SoundManager.play_hit_sound()
					await get_tree().create_timer(0.3).timeout
					if unit.hit_points <= 0:
						UnitManager.unregister_unit(unit)
						unit.queue_free()
						TurnManager.check_victory()

			"gold":
				var g: int = int(action.get("amount", 0))
				if g > 0:
					EconomyManager.add_temp_gold(g)
					SoundManager.play_get_item_sound()
				elif g < 0:
					EconomyManager.subtract_temp_gold(-g)
				await get_tree().create_timer(0.2).timeout

			"soul":
				var s: int = int(action.get("amount", 0))
				if s > 0:
					GameState.soul += s
				elif s < 0:
					GameState.soul = maxi(0, GameState.soul + s)
				SaveManager.auto_save()
				await get_tree().create_timer(0.2).timeout

			"wait":
				await get_tree().create_timer(float(action.get("seconds", 0.5))).timeout

			"unlock_unit":
				var units_arr : Array = action.get("units", [])
				for u in units_arr:
					var uk : String = str(u)
					if uk != "":
						Globals.make_unit_eligible(uk)
				await get_tree().create_timer(0.2).timeout

			"unlock_talent":
				var tid : String = str(action.get("talent_id", ""))
				if tid != "":
					Globals.unlock_talent(tid)
				await get_tree().create_timer(0.2).timeout

			"unlock_equipment":
				var iid : String = str(action.get("item_id", ""))
				if iid != "":
					Globals.unlock_item(iid)
				await get_tree().create_timer(0.2).timeout

			"unlock_relics":
				var rids : Array = action.get("relics", [])
				if not rids.is_empty():
					RelicManager.unlock_relics_by_ids(rids)
				await get_tree().create_timer(0.2).timeout

			"unlock_avatar":
				var target_unit : String = str(action.get("unit_name", ""))
				var new_avatar : String = str(action.get("avatar_id", ""))
				if target_unit != "" and new_avatar != "":
					GameState.set_unit_avatar(target_unit, new_avatar)
					print("[Event] 单位 %s 头像已更新为 %s" % [target_unit, new_avatar])
				await get_tree().create_timer(0.2).timeout

			"unlock_npc_avatar":
				var target_npc : String = str(action.get("npc_id", ""))
				var new_avatar : String = str(action.get("avatar_id", ""))
				if target_npc != "" and new_avatar != "":
					GameState.set_npc_avatar(target_npc, new_avatar)
					print("[Event] NPC %s 头像已更新为 %s" % [target_npc, new_avatar])
				await get_tree().create_timer(0.2).timeout

			_:
				push_warning("[EventManager] 未知 action: " + action_type)

	if event_def.get("once", true):
		mark_event_completed(event_id)


# ============================================================
#  辅助方法
# ============================================================
func _get_ui_manager() -> UIManager:
	var battlefield = get_node("/root/Battlefield")
	if battlefield and battlefield.ui_manager:
		return battlefield.ui_manager
	return null
	

func show_item_get_popup(item_id: String, count: int):
	if Globals.is_item_get_popup_active:
		return
	var summary = Globals.get_reward_summary()
	if summary:
		summary.show_simple_item(item_id, count)

func show_unit_unlock_popup(units: Array):
	if Globals.is_item_get_popup_active:
		return
	var summary = Globals.get_reward_summary()
	if summary:
		summary.show_text("★ 解锁单位：\n" + ", ".join(units))

func show_unit_eligible_popup(units: Array):
	if Globals.is_item_get_popup_active:
		return
	var summary = Globals.get_reward_summary()
	if summary:
		summary.show_text("★ 新残魂资格：\n" + ", ".join(units))
