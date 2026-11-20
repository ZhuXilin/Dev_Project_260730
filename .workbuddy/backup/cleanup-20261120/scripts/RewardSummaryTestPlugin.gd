extends TestPlugin

var _gold_edit : LineEdit
var _soul_edit : LineEdit
var _items_vbox : VBoxContainer
var _selected_items : Array = []


func get_key() -> String: return "reward_summary"
func get_category() -> String: return "UI 组件"
func get_display_name() -> String: return "结算面板"


func build_params(container: VBoxContainer, on_ready: Callable):
	container.add_child(_make_label("模拟奖励结算面板"))

	# 金币
	var gold_row := HBoxContainer.new()
	gold_row.add_child(_make_label("金币："))
	_gold_edit = LineEdit.new()
	_gold_edit.text = "500"
	_gold_edit.custom_minimum_size = Vector2(80, 0)
	gold_row.add_child(_gold_edit)
	container.add_child(gold_row)

	# 魂
	var soul_row := HBoxContainer.new()
	soul_row.add_child(_make_label("魂："))
	_soul_edit = LineEdit.new()
	_soul_edit.text = "3"
	_soul_edit.custom_minimum_size = Vector2(80, 0)
	soul_row.add_child(_soul_edit)
	container.add_child(soul_row)

	# 物品列表
	container.add_child(_make_label("选择物品（可多选）："))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 80)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_vbox = VBoxContainer.new()
	_items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_items_vbox)
	container.add_child(scroll)

	for item_id in ItemManager.get_all_item_ids():
		var d = ItemManager.get_item_data(item_id)
		if not d: continue
		var cb := CheckBox.new()
		cb.text = d.name
		cb.add_theme_font_size_override("font_size", 7)
		cb.toggled.connect(func(pressed):
			if pressed:
				if item_id not in _selected_items:
					_selected_items.append(item_id)
			else:
				_selected_items.erase(item_id)
		)
		_items_vbox.add_child(cb)

	on_ready.call()


func launch():
	var gold : int = int(_gold_edit.text) if _gold_edit.text.is_valid_int() else 0
	var soul : int = int(_soul_edit.text) if _soul_edit.text.is_valid_int() else 0
	var items : Array = []
	for item_id in _selected_items:
		var d = ItemManager.get_item_data(item_id)
		if d: items.append(d)

	var summary = Globals.get_reward_summary()
	if summary == null:
		push_error("[TestPlugin] RewardSummaryUI 未找到")
		return
	summary.setup_reward(gold, soul, items, false, "测试结算")
	summary.open()
	await summary.confirmed
	summary.close()


func get_status_text() -> String:
	var gold : int = int(_gold_edit.text) if _gold_edit and _gold_edit.text.is_valid_int() else 0
	var soul : int = int(_soul_edit.text) if _soul_edit and _soul_edit.text.is_valid_int() else 0
	return "金币 %d / 魂 %d / 物品 %d" % [gold, soul, _selected_items.size()]
