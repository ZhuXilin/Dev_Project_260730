extends PanelContainer

@onready var category_container = $VBoxContainer/HBoxContainer/LeftPanel/ScrollContainer/CategoryContainer
@onready var item_icon = $VBoxContainer/HBoxContainer/RightPanel/ItemIcon
@onready var item_name = $VBoxContainer/HBoxContainer/RightPanel/ItemName
@onready var item_detail = $VBoxContainer/HBoxContainer/RightPanel/ItemDetail

func _ready():
	_refresh_list()

func _refresh_list():
	# 清空容器
	for child in category_container.get_children():
		child.queue_free()
	
	# 获取所有已解锁道具
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
	
	# 按类型分组
	var groups = {}
	for data in all_items:
		var type_key = data.type
		if not groups.has(type_key):
			groups[type_key] = []
		groups[type_key].append(data)
	
	# 定义分类显示名称
	var type_names = {
		"weapon": "武器",
		"armor": "防具",
		"accessory": "饰品",
		"relic": "遗物",
		# 可扩展其他类型
	}
	
	# 按固定顺序显示分类
	var order = ["weapon", "armor", "accessory", "relic"]
	for type_key in order:
		if groups.has(type_key):
			var group_data = groups[type_key]
			# 添加分类标题
			var title_label = Label.new()
			title_label.text = type_names.get(type_key, type_key)
			title_label.add_theme_font_size_override("font_size", 9)
			category_container.add_child(title_label)
			
			# 添加该分类下的道具按钮
			for data in group_data:
				var btn = Button.new()
				btn.text = data.name
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				btn.add_theme_font_size_override("font_size", 8)
				btn.pressed.connect(_show_item_detail.bind(data))
				category_container.add_child(btn)

func _show_item_detail(data: ItemData):
	if data.icon:
		item_icon.texture = data.icon
		item_icon.visible = true
	else:
		item_icon.visible = false
	
	item_name.text = data.name
	var detail = ""
	if data.description:
		detail += data.description + "\n"
	if data.stats:
		for key in data.stats:
			detail += "%s: %s\n" % [key.capitalize(), str(data.stats[key])]
	item_detail.text = detail

func _on_back_button_pressed():
	queue_free()
