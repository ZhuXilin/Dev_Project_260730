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
	
	# 按类型分组，合并 armor 和 accessory 为 "armor_accessory"
	var groups = {}
	for data in all_items:
		var type_key = data.type
		if type_key in ["armor", "accessory"]:
			type_key = "armor_accessory"
		if not groups.has(type_key):
			groups[type_key] = []
		groups[type_key].append(data)
	
	# 定义分类显示名称（中文）和顺序
	var type_names = {
		"weapon": "武器",
		"armor_accessory": "防具/饰品",
		"relic": "遗物",
	}
	var order = ["weapon", "armor_accessory", "relic"]
	
	# 始终显示三个分类
	for type_key in order:
		# 添加分类标题
		var title_label = Label.new()
		title_label.text = type_names.get(type_key, type_key)
		title_label.add_theme_font_size_override("font_size", 9)
		category_container.add_child(title_label)
		
		# 获取该分类下的道具
		var group_data = groups.get(type_key, [])
		if group_data.is_empty():
			# 没有道具，显示灰色提示
			var empty_label = Label.new()
			empty_label.text = "（暂无）"
			empty_label.add_theme_font_size_override("font_size", 7)
			empty_label.modulate = Color(0.5, 0.5, 0.5)
			category_container.add_child(empty_label)
		else:
			for data in group_data:
				var btn = Button.new()
				btn.text = data.name
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				btn.add_theme_font_size_override("font_size", 8)
				btn.alignment = HORIZONTAL_ALIGNMENT_LEFT   # 左对齐
				btn.pressed.connect(_show_item_detail.bind(data))
				category_container.add_child(btn)

func _show_item_detail(data: ItemData):
	if data.icon:
		item_icon.texture = data.icon
		item_icon.visible = true
	else:
		item_icon.visible = false
	
	item_name.text = data.name
	# 只显示 description，不再重复显示英文 stats
	item_detail.text = data.description if data.description else "无描述"

func _on_back_button_pressed():
	queue_free()
