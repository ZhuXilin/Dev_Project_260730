# RewardSummaryUI.gd
extends CanvasLayer

signal confirmed

@onready var gold_label = $Panel/VBoxContainer/ResourceContainer/GoldLabel
@onready var soul_label = $Panel/VBoxContainer/ResourceContainer/SoulLabel
@onready var material_list_container = $Panel/VBoxContainer/MaterialListContainer
@onready var confirm_button = $Panel/VBoxContainer/ConfirmButton

func setup_reward(gold: int, soul: int, items: Array):
	# ---- 更新金币和魂 ----
	gold_label.text = "金币 +" + str(gold)
	soul_label.text = "魂 +" + str(soul)
	
	# ---- 清空材料列表 ----
	for child in material_list_container.get_children():
		child.queue_free()
	
	# ---- 如果没有获得任何物品 ----
	if items.is_empty():
		var label = Label.new()
		label.text = "没有获得物品"
		label.add_theme_font_size_override("font_size", 8)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		material_list_container.add_child(label)
		return
	
	# ---- 合并相同物品 ----
	var merged_items = {}
	for item_data in items:
		if not item_data:
			continue
		var id = item_data.id
		if merged_items.has(id):
			merged_items[id]["count"] += 1
		else:
			merged_items[id] = {
				"data": item_data,
				"count": 1
			}
	
	# ---- 显示所有物品（包括材料和普通物品） ----
	for key in merged_items:
		var entry = merged_items[key]
		var data = entry["data"]
		var count = entry["count"]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		
		# 图标
		var icon = TextureRect.new()
		if data.icon:
			icon.texture = data.icon
		else:
			# 如果没有图标，使用占位文本
			icon.visible = false
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.size = Vector2(16, 16)
		hbox.add_child(icon)
		
		# 名称（材料显示颜色）
		var name_label = Label.new()
		name_label.text = data.name
		name_label.add_theme_font_size_override("font_size", 8)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# ---- 如果是材料，显示颜色 ----
		if data.id and data.id.begins_with("material_"):
			var color = _get_material_color(data.name)
			if color:
				name_label.add_theme_color_override("font_color", color)
		
		hbox.add_child(name_label)
		
		# 数量
		if count > 1:
			var count_label = Label.new()
			count_label.text = "x" + str(count)
			count_label.add_theme_font_size_override("font_size", 8)
			hbox.add_child(count_label)
		
		material_list_container.add_child(hbox)

# ---- 根据材料名称获取颜色 ----
func _get_material_color(material_name: String) -> Color:
	match material_name:
		"粗铁":
			return Color(0.7, 0.6, 0.5, 1.0)   # 棕色
		"精钢":
			return Color(0.5, 0.7, 0.8, 1.0)   # 钢蓝色
		"秘银":
			return Color(0.3, 0.8, 0.7, 1.0)   # 银蓝色
		"龙鳞":
			return Color(0.8, 0.6, 0.1, 1.0)   # 金色
		_:
			return Color.WHITE

func _on_confirm_pressed():
	confirmed.emit()
	queue_free()
