extends CanvasLayer

signal confirmed

@onready var gold_label = $Panel/VBoxContainer/ResourceContainer/GoldLabel
@onready var soul_label = $Panel/VBoxContainer/ResourceContainer/SoulLabel
@onready var item_list_container = $Panel/VBoxContainer/ItemListContainer
@onready var confirm_button = $Panel/VBoxContainer/ConfirmButton

func _ready():
	# 信号已在场景中连接，不需要再次连接
	# 可以添加其他初始化代码（如果需要）
	pass

func setup_reward(gold: int, soul: int, items: Array):
	gold_label.text = "金币 +" + str(gold)
	soul_label.text = "魂 +" + str(soul)
	
	for child in item_list_container.get_children():
		child.queue_free()
	
	if items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "没有获得物品"
		empty_label.add_theme_font_size_override("font_size", 8)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_list_container.add_child(empty_label)
		return
	
	var item_counts = {}
	for item_data in items:
		if not item_data:
			continue
		var id = ""
		if item_data is ItemData:
			id = item_data.id
		elif item_data is Dictionary:
			id = item_data.get("id", "")
		if id == "":
			continue
		if item_counts.has(id):
			item_counts[id]["count"] += 1
		else:
			item_counts[id] = {
				"data": item_data,
				"count": 1
			}
	
	for key in item_counts:
		var entry = item_counts[key]
		var data = entry["data"]
		var count = entry["count"]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		
		var icon = TextureRect.new()
		var icon_tex = null
		if data is ItemData:
			icon_tex = data.icon
		elif data is Dictionary:
			icon_tex = data.get("icon", null)
		if icon_tex:
			icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.size = Vector2(16, 16)
		hbox.add_child(icon)
		
		var name_label = Label.new()
		var item_name = ""
		if data is ItemData:
			item_name = data.name
		elif data is Dictionary:
			item_name = data.get("name", "未知物品")
		name_label.text = item_name
		name_label.add_theme_font_size_override("font_size", 8)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
		
		if count > 1:
			var count_label = Label.new()
			count_label.text = "x" + str(count)
			count_label.add_theme_font_size_override("font_size", 8)
			hbox.add_child(count_label)
		
		item_list_container.add_child(hbox)

func _on_confirm_pressed():
	confirmed.emit()
	queue_free()
