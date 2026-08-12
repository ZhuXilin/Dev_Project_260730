extends Node

signal event_completed(event_id: String)

const ItemGetPopupScene = preload("res://content/scenes/ui/ItemGetPopup.tscn")

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

# EventManager.gd
func trigger_event(event_id: String, unit: Unit = null, default_music: AudioStream = null):
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
				print("非战斗地图完成事件触发")
				SignalBus.non_combat_complete.emit()
				await get_tree().process_frame

			"dialog":
				var dialog_id = action.get("dialog_id", "")
				var music_stream = action.get("music", default_music)
				if dialog_id != "":
					if DialogueManager.is_active:
						print("对话已激活，跳过: ", dialog_id)
					else:
						DialogueManager.start_dialogue(dialog_id, music_stream)
						await DialogueManager.dialogue_finished
				else:
					push_error("对话动作缺少 dialog_id")

			"give_item":
				if unit == null:
					print("警告: 无单位，跳过 give_item")
					continue
				var item_id = action.get("item_id", "")
				var count = action.get("count", 1)
				if item_id != "":
					if unit.add_item(item_id, count):
						await show_item_get_popup(item_id, count)
					else:
						print("道具获得失败，背包已满，弹出丢弃界面")
						var ui_mgr = _get_ui_manager()
						if ui_mgr:
							ui_mgr.show_drop_menu_with_choice(
								unit,
								item_id,
								count,
								Callable(self, "_on_give_item_drop_success").bind(unit, item_id, count),
								Callable(self, "_on_give_item_drop_cancel")
							)
						else:
							print("无法获取 UIManager，放弃获得道具")
				else:
					push_error("give_item 动作缺少 item_id")

			"heal":
				if unit == null:
					print("警告: 无单位，跳过 heal")
					continue
				var amount = action.get("amount", 0)
				if amount > 0:
					unit.hit_points = min(unit.hit_points + amount, unit.unit_stats.max_hp)
					unit.update_hp_label()
					SignalBus.request_damage_popup.emit(unit.global_position, amount, false, false, true)
					SoundManager.play_heal_sound()
					await get_tree().create_timer(0.3).timeout

			"damage":
				if unit == null:
					print("警告: 无单位，跳过 damage")
					continue
				var amount = action.get("amount", 0)
				if amount < 0:
					unit.hit_points = max(unit.hit_points + amount, 0)
					unit.update_hp_label()
					SignalBus.request_damage_popup.emit(unit.global_position, abs(amount), false, false, false)
					SoundManager.play_hit_sound()
					await get_tree().create_timer(0.3).timeout
					if unit.hit_points <= 0:
						UnitManager.unregister_unit(unit)
						unit.queue_free()
						TurnManager.check_victory()

			"wait":
				var seconds = action.get("seconds", 0.5)
				await get_tree().create_timer(seconds).timeout

			"unlock_unit":
				var units = action.get("units", [])
				if units is String:
					units = [units]
				var unlocked = []
				for u in units:
					if u != "" and u != null:
						Globals.unlock_unit(u)
						unlocked.append(u)
				if unlocked.size() > 0:
					show_unit_unlock_popup(unlocked)
			_:
				push_error("未知动作类型: ", action_type)

	if event_def.get("once", true):
		mark_event_completed(event_id)

# EventManager.gd
func show_item_get_popup(item_id: String, count: int):
	var root = get_tree().current_scene
	if not root:
		return
	Globals.is_item_get_popup_active = true
	MusicManager.pause_and_save()
	SoundManager.play_get_item_sound()
	var popup = ItemGetPopupScene.instantiate()
	root.add_child(popup)
	popup.show_item(item_id, count)
	await get_tree().create_timer(2.0).timeout
	Globals.is_item_get_popup_active = false
	MusicManager.resume_saved()

func clear_completed():
	_completed.clear()
	print("EventManager 已完成事件记录已清空")

# ============================================================
#  辅助方法
# ============================================================
func _get_ui_manager() -> UIManager:
	var battlefield = get_node("/root/Battlefield")
	if battlefield and battlefield.ui_manager:
		return battlefield.ui_manager
	return null

func _on_give_item_drop_success(unit: Unit, item_id: String, count: int):
	if unit.add_item(item_id, count):
		show_item_get_popup(item_id, count)
		print("丢弃后成功获得道具: ", item_id)
	else:
		print("丢弃后仍然无法获得道具，放弃获得: ", item_id)

func _on_give_item_drop_cancel():
	print("用户取消获得道具")

func show_unit_unlock_popup(units: Array):
	var root = get_tree().current_scene
	if not root:
		return
	# 防止多个弹窗重叠
	if Globals.is_item_get_popup_active:
		return
	Globals.is_item_get_popup_active = true
	MusicManager.pause_and_save()
	SoundManager.play_get_item_sound()

	var popup = CanvasLayer.new()
	popup.layer = 30
	root.add_child(popup)

	var panel = Panel.new()
	panel.size = Vector2(200, 100)
	var viewport_size = root.get_viewport().get_visible_rect().size
	panel.position = viewport_size / 2 - panel.size / 2
	var stylebox = load("res://content/resource/stylebox/8bit_style_box_flat.tres")
	if stylebox:
		panel.add_theme_stylebox_override("panel", stylebox)
	popup.add_child(panel)

	var label = Label.new()
	var text = "解锁单位：\n" + ", ".join(units)
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = panel.size - Vector2(20, 20)
	label.position = Vector2(10, 10)
	panel.add_child(label)

	await get_tree().create_timer(2.0).timeout

	Globals.is_item_get_popup_active = false
	MusicManager.resume_saved()
	popup.queue_free()
