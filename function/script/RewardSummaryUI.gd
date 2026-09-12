extends CanvasLayer

signal confirmed

@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var gold_label = $Panel/VBoxContainer/ResourceContainer/GoldLabel
@onready var soul_label = $Panel/VBoxContainer/ResourceContainer/SoulLabel
@onready var material_list_container = $Panel/VBoxContainer/MaterialListContainer
@onready var empty_label = $Panel/VBoxContainer/MaterialListContainer/EmptyLabel
@onready var confirm_button = $Panel/VBoxContainer/ConfirmButton

func _ready():
	# 初始隐藏（等待外部 setup + open）
	visible = false
	# 防重复连接（场景中可能已连）
	if not confirm_button.pressed.is_connected(_on_confirm_pressed):
		confirm_button.pressed.connect(_on_confirm_pressed)

# ---- 刷新内容（可重复调用） ----
func setup_reward(gold: int, soul: int, items: Array, hide_gold: bool = false, title: String = "关卡结算"):
	# 标题
	title_label.text = title
	
	# 金币显示（可选择隐藏）
	if hide_gold:
		gold_label.visible = false
	else:
		gold_label.visible = true
		gold_label.text = "金币 +" + str(gold)
	
	# 魂
	soul_label.text = "魂 +" + str(soul)
	
	# 清空材料列表（保留 EmptyLabel）
	for child in material_list_container.get_children():
		if child != empty_label:
			child.queue_free()
	
	empty_label.visible = true
	
	if items.is_empty():
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
	
	empty_label.visible = false
	
	for key in merged_items:
		var entry = merged_items[key]
		var data = entry["data"]
		var count = entry["count"]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# 图标
		var icon = TextureRect.new()
		if data.icon:
			icon.texture = data.icon
		else:
			icon.visible = false
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.size = Vector2(16, 16)
		hbox.add_child(icon)
		
		# 名称
		var name_label = Label.new()
		name_label.text = data.name
		name_label.add_theme_font_size_override("font_size", 8)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		# 材料颜色（从 id 提取材料名，因为 name 可能带 "xN"）
		if data.id and data.id.begins_with("material_"):
			var mat_name = data.id.substr("material_".length())
			var color = _get_material_color(mat_name)
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

# ---- 打开面板 ----
func open():
	visible = true

# ---- 手动隐藏（外部强制） ----
func hide_panel():
	visible = false

func _get_material_color(material_name: String) -> Color:
	match material_name:
		"粗铁": return Color(0.7, 0.6, 0.5, 1.0)
		"精钢": return Color(0.5, 0.7, 0.8, 1.0)
		"秘银": return Color(0.3, 0.8, 0.7, 1.0)
		"龙鳞": return Color(0.8, 0.6, 0.1, 1.0)
		_: return Color.WHITE

# ---- 确认按钮：只隐藏，不销毁（可复用） ----
func _on_confirm_pressed():
	visible = false
	confirmed.emit()
