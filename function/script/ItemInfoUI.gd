extends PanelContainer

@onready var category_container = $VBoxContainer/HBoxContainer/LeftPanel/ScrollContainer/CategoryContainer
@onready var item_icon = $VBoxContainer/HBoxContainer/RightPanel/ItemIcon
@onready var item_name = $VBoxContainer/HBoxContainer/RightPanel/ItemName
@onready var item_detail = $VBoxContainer/HBoxContainer/RightPanel/ItemDetail

func _ready():
	_refresh_list()

# ItemInfoUI.gd

func _refresh_list():
	for child in category_container.get_children():
		child.queue_free()
	
	var all_items = []
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data:
			all_items.append(data)
	
	if all_items.is_empty():
		var label = Label.new()
		label.text = "暂无已解锁的道具"
		label.add_theme_font_size_override("font_size", 8)
		category_container.add_child(label)
		return
	
	var groups = {}
	for data in all_items:
		var type_key = data.type
		if type_key in ["armor", "accessory"]:
			type_key = "armor"
		if not groups.has(type_key):
			groups[type_key] = []
		groups[type_key].append(data)
	
	var type_names = {
		"weapon": "武器",
		"armor": "防具",
		"relic": "遗物",
	}
	var order = ["weapon", "armor", "relic"]
	
	for type_key in order:
		if not groups.has(type_key):
			var title_label = Label.new()
			title_label.text = type_names.get(type_key, type_key)
			title_label.add_theme_font_size_override("font_size", 9)
			category_container.add_child(title_label)
			var empty_label = Label.new()
			empty_label.text = "（暂无）"
			empty_label.add_theme_font_size_override("font_size", 7)
			empty_label.modulate = Color(0.5, 0.5, 0.5)
			category_container.add_child(empty_label)
			continue
		
		var group_data = groups[type_key]
		var title_label = Label.new()
		title_label.text = type_names.get(type_key, type_key)
		title_label.add_theme_font_size_override("font_size", 9)
		category_container.add_child(title_label)
		
		for data in group_data:
			var btn = Button.new()
			btn.text = data.name
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 8)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			
			if data.type == "relic":
				var has_relic = false
				for relic in GameState.get_global_relics():
					if relic.item_id == data.id:
						has_relic = true
						break
				if has_relic:
					btn.text += " ✅"
					btn.modulate = Color(0.7, 1.0, 0.7)
			
			btn.pressed.connect(_show_item_detail.bind(data))
			category_container.add_child(btn)

func _show_item_detail(data: ItemData):
	if data.icon:
		item_icon.texture = data.icon
		item_icon.visible = true
	else:
		item_icon.visible = false
	
	item_name.text = data.name
	item_detail.text = data.description if data.description else "无描述"
	
	if data.type == "relic":
		var has_relic = false
		for relic in GameState.get_global_relics():
			if relic.item_id == data.id:
				has_relic = true
				break
		if has_relic:
			item_detail.text += "\n\n状态：已获得 ✅"
		else:
			item_detail.text += "\n\n状态：未获得"

func _on_back_button_pressed():
	queue_free()
