# RewardSummaryUI.gd 完整版

extends CanvasLayer

signal confirmed

@onready var gold_label = $Panel/VBoxContainer/ResourceContainer/GoldLabel
@onready var soul_label = $Panel/VBoxContainer/ResourceContainer/SoulLabel
@onready var item_list_container = $Panel/VBoxContainer/ItemListContainer
@onready var material_list_container = $Panel/VBoxContainer/MaterialListContainer
@onready var confirm_button = $Panel/VBoxContainer/ConfirmButton

func _ready():
	# 信号已在场景中连接，不需要再次连接
	pass

func setup_reward(gold: int, soul: int, items: Array):
	# ---- 更新金币和魂 ----
	gold_label.text = "金币 +" + str(gold)
	soul_label.text = "魂 +" + str(soul)
	
	# ---- 清空物品列表 ----
	for child in item_list_container.get_children():
		child.queue_free()
	
	# ---- 清空材料列表 ----
	for child in material_list_container.get_children():
		child.queue_free()
	
	# ---- 如果没有物品和材料 ----
	if items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "没有获得物品或材料"
		empty_label.add_theme_font_size_override("font_size", 8)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_list_container.add_child(empty_label)
		return
	
	# ---- 分离材料和普通物品 ----
	var normal_items: Array = []
	var material_items: Array = []
	
	for item_data in items:
		if not item_data:
			continue
		# 检查是否为材料（通过 id 前缀或类型判断）
		var is_material = false
		if item_data.id and item_data.id.begins_with("material_"):
			is_material = true
		elif item_data.type == "material":
			is_material = true
		
		if is_material:
			material_items.append(item_data)
		else:
			normal_items.append(item_data)
	
	# ---- 合并相同物品（普通物品按 ID 合并） ----
	var merged_items = {}
	for item_data in normal_items:
		var id = item_data.id
		if merged_items.has(id):
			merged_items[id]["count"] += 1
		else:
			merged_items[id] = {
				"data": item_data,
				"count": 1
			}
	
	# ---- 合并相同材料（材料按名称合并） ----
	var merged_materials = {}
	for item_data in material_items:
		var id = item_data.id
		if merged_materials.has(id):
			merged_materials[id]["count"] += 1
		else:
			merged_materials[id] = {
				"data": item_data,
				"count": 1
			}
	
	# ---- 显示普通物品 ----
	if not merged_items.is_empty():
		for key in merged_items:
			var entry = merged_items[key]
			var data = entry["data"]
			var count = entry["count"]
			var hbox = HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 4)
			
			# 图标
			var icon = TextureRect.new()
			if data.icon:
				icon.texture = data.icon
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.size = Vector2(16, 16)
			hbox.add_child(icon)
			
			# 名称
			var name_label = Label.new()
			name_label.text = data.name
			name_label.add_theme_font_size_override("font_size", 8)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(name_label)
			
			# 数量
			if count > 1:
				var count_label = Label.new()
				count_label.text = "x" + str(count)
				count_label.add_theme_font_size_override("font_size", 8)
				hbox.add_child(count_label)
			
			item_list_container.add_child(hbox)
	
	# ---- 显示材料（单独放在 MaterialListContainer） ----
	if not merged_materials.is_empty():
		var material_title = Label.new()
		material_title.text = "— 获得材料 —"
		material_title.add_theme_font_size_override("font_size", 7)
		material_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		material_list_container.add_child(material_title)
		
		for key in merged_materials:
			var entry = merged_materials[key]
			var data = entry["data"]
			var count = entry["count"]
			var hbox = HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 4)
			hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			
			# 材料名称（带颜色）
			var name_label = Label.new()
			var material_name = data.name
			# 移除 "材料 " 前缀（如果有）
			if material_name.begins_with("材料 "):
				material_name = material_name.substr(3)
			name_label.text = material_name
			name_label.add_theme_font_size_override("font_size", 8)
			# 根据材料类型设置颜色
			var color = _get_material_color(material_name)
			if color:
				name_label.add_theme_color_override("font_color", color)
			hbox.add_child(name_label)
			
			# 数量
			var count_label = Label.new()
			count_label.text = "x" + str(count)
			count_label.add_theme_font_size_override("font_size", 8)
			hbox.add_child(count_label)
			
			material_list_container.add_child(hbox)
	
	# ---- 如果只有材料没有普通物品，显示提示 ----
	if merged_items.is_empty() and not merged_materials.is_empty():
		var hint_label = Label.new()
		hint_label.text = "（仅获得材料）"
		hint_label.add_theme_font_size_override("font_size", 7)
		hint_label.modulate = Color(0.6, 0.6, 0.6)
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_list_container.add_child(hint_label)
	
	# ---- 如果只有普通物品没有材料 ----
	if not merged_items.is_empty() and merged_materials.is_empty():
		var hint_label = Label.new()
		hint_label.text = "（无材料获得）"
		hint_label.add_theme_font_size_override("font_size", 7)
		hint_label.modulate = Color(0.6, 0.6, 0.6)
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		material_list_container.add_child(hint_label)

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
