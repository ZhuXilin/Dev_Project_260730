extends CanvasLayer

signal confirmed

@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var gold_label = $Panel/VBoxContainer/ResourceContainer/GoldLabel
@onready var soul_label = $Panel/VBoxContainer/ResourceContainer/SoulLabel
@onready var material_list_container = $Panel/VBoxContainer/MaterialListContainer
@onready var empty_label = $Panel/VBoxContainer/MaterialListContainer/EmptyLabel
@onready var confirm_button = $Panel/VBoxContainer/ConfirmButton

var _confirmed_guard : bool = false


func _ready():
	visible = false
	for conn in confirm_button.pressed.get_connections():
		confirm_button.pressed.disconnect(conn.callable)
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button.disabled = false
	_confirmed_guard = false


func setup_reward(gold: int, soul: int, items: Array, hide_gold: bool = false, title: String = "关卡结算"):
	confirm_button.disabled = false
	_confirmed_guard = false

	title_label.text = title

	if hide_gold:
		gold_label.visible = false
	else:
		gold_label.visible = true
		gold_label.text = "金币 +" + str(gold)

	soul_label.text = "魂 +" + str(soul)

	for child in material_list_container.get_children():
		if child != empty_label:
			child.queue_free()

	empty_label.visible = true

	if items.is_empty():
		return

	var merged_items = {}
	for item_data in items:
		if not item_data:
			continue
		var id = item_data.id
		if merged_items.has(id):
			merged_items[id]["count"] += 1
		else:
			merged_items[id] = {"data": item_data, "count": 1}

	empty_label.visible = false

	for key in merged_items:
		var entry = merged_items[key]
		var data = entry["data"]
		var count = entry["count"]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var icon = TextureRect.new()
		if data.icon:
			icon.texture = data.icon
		else:
			icon.visible = false
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.size = Vector2(16, 16)
		hbox.add_child(icon)

		var name_label = Label.new()
		name_label.text = data.name
		name_label.add_theme_font_size_override("font_size", 8)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		if data.id and data.id.begins_with("material_"):
			var mat_name = data.id.substr("material_".length())
			var color = _get_material_color(mat_name)
			if color:
				name_label.add_theme_color_override("font_color", color)

		hbox.add_child(name_label)

		if count > 1:
			var count_label = Label.new()
			count_label.text = "x" + str(count)
			count_label.add_theme_font_size_override("font_size", 8)
			hbox.add_child(count_label)

		material_list_container.add_child(hbox)


func open():
	confirm_button.disabled = false
	_confirmed_guard = false
	visible = true
	# ---- 保护性断言：显示时按钮必须是可点的 ----
	if confirm_button.disabled:
		push_warning("[RewardSummaryUI] open() 后按钮仍 disabled，检查调用方")


func close():
	visible = false
	confirm_button.disabled = false
	_confirmed_guard = false


func hide_panel():
	visible = false


func _on_confirm_pressed():
	if _confirmed_guard:
		return
	_confirmed_guard = true
	visible = false
	confirmed.emit()


func set_interactable(enabled: bool):
	confirm_button.disabled = not enabled
	# ---- 记录调用来源，方便排查 ----
	if not enabled:
		print("[RewardSummaryUI] set_interactable(false) 被调用，堆栈：")
		print_stack()


func _get_material_color(material_name: String) -> Color:
	match material_name:
		"粗铁": return Color(0.7, 0.6, 0.5, 1.0)
		"精钢": return Color(0.5, 0.7, 0.8, 1.0)
		"秘银": return Color(0.3, 0.8, 0.7, 1.0)
		"龙鳞": return Color(0.8, 0.6, 0.1, 1.0)
		_: return Color.WHITE
