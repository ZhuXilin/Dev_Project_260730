extends CanvasLayer

signal confirmed

@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var gold_label = $Panel/VBoxContainer/ResourceContainer/GoldLabel
@onready var soul_label = $Panel/VBoxContainer/ResourceContainer/SoulLabel
@onready var material_list_container = $Panel/VBoxContainer/MaterialListContainer
@onready var empty_label = $Panel/VBoxContainer/MaterialListContainer/EmptyLabel
@onready var confirm_button = $Panel/VBoxContainer/ConfirmButton

var _confirmed_guard : bool = false
var rating_label : Label = null # ★ 独立的评级标签

func _ready():
	visible = false
	for conn in confirm_button.pressed.get_connections():
		confirm_button.pressed.disconnect(conn.callable)
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button.disabled = false
	confirm_button.focus_mode = Control.FOCUS_NONE # 去除焦点，防止回车误触发
	_confirmed_guard = false
	
	# ★ 动态创建评级标签，并放在物品列表和横线下方
	var vbox = $Panel/VBoxContainer
	rating_label = vbox.get_node_or_null("RatingLabel")
	if not rating_label:
		rating_label = Label.new()
		rating_label.name = "RatingLabel"
		rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rating_label.add_theme_font_size_override("font_size", 10)
		vbox.add_child(rating_label)
		
		# 确保它放在 ConfirmButton 之前（也就是在第三条横线附近）
		var idx = vbox.get_children().find(confirm_button)
		if idx > 0:
			vbox.move_child(rating_label, idx - 1)
	rating_label.visible = false

# ★ 核心修复：拦截回车和空格，防止穿透到底层场景反复触发 open()
func _input(event: InputEvent):
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled() # 吞掉按键，防止穿透
			_on_confirm_pressed()


func setup_reward(gold: int, soul: int, items: Array, hide_gold: bool = false, title: String = "关卡结算"):
	confirm_button.disabled = false
	confirm_button.visible = true   # ★ 修复：强行重置为显示
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

	# ★ 从 items 里挑出评级，不放进物品栏
	var rating_text := ""
	var filtered_items := []
	for item_data in items:
		if not item_data:
			continue
		if item_data.id == "rating":
			rating_text = item_data.name
		else:
			filtered_items.append(item_data)

	# 更新独立的评级标签
	if rating_label:
		if rating_text != "":
			rating_label.text = rating_text
			rating_label.visible = true
		else:
			rating_label.visible = false

	# 处理剩下的物品图标（横向居中排列）
	if filtered_items.is_empty():
		empty_label.visible = false
		return

	var merged_items = {}
	for item_data in filtered_items:
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
		hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		var icon = TextureRect.new()
		if data.icon:
			icon.texture = data.icon
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.custom_minimum_size = Vector2(16, 16)
			hbox.add_child(icon)
		else:
			icon.visible = false
			
		if not data.icon:
			var name_label = Label.new()
			name_label.text = data.name
			name_label.add_theme_font_size_override("font_size", 8)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

			if data.id and data.id.begins_with("material_"):
				var mat_name = data.id.substr("material_".length())
				var color = _get_material_color(mat_name)
				if color:
					name_label.add_theme_color_override("font_color", color)
			elif data.name.begins_with("★ "):
				name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

			hbox.add_child(name_label)

		if count > 1:
			var count_label = Label.new()
			count_label.text = "x" + str(count)
			count_label.add_theme_font_size_override("font_size", 8)
			hbox.add_child(count_label)

		material_list_container.add_child(hbox)


func open():
	confirm_button.disabled = false
	confirm_button.visible = true  # ★ 修复：打开时必定可见
	_confirmed_guard = false
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_reward_summary_active = true


func close():
	visible = false
	confirm_button.disabled = false
	confirm_button.visible = true  # 还原可见
	_confirmed_guard = false
	Globals.is_reward_summary_active = false


func hide_panel():
	visible = false
	Globals.is_reward_summary_active = false


func _on_confirm_pressed():
	if _confirmed_guard:
		return
	_confirmed_guard = true
	visible = false
	Globals.is_reward_summary_active = false
	confirmed.emit()


func set_interactable(enabled: bool):
	confirm_button.disabled = not enabled


func _get_material_color(material_name: String) -> Color:
	match material_name:
		"粗铁": return Color(0.7, 0.6, 0.5, 1.0)
		"精钢": return Color(0.5, 0.7, 0.8, 1.0)
		"秘银": return Color(0.3, 0.8, 0.7, 1.0)
		"龙鳞": return Color(0.8, 0.6, 0.1, 1.0)
		_: return Color.WHITE


func show_simple_item(item_id: String, count: int):
	if rating_label: rating_label.visible = false
	var data = ItemManager.get_item_data(item_id)
	if not data and not RelicManager.get_relic_data(item_id).is_empty():
		var rd = RelicManager.get_relic_data(item_id)
		data = ItemData.new()
		data.id = item_id
		data.name = rd.get("name", item_id)
		data.icon = rd.get("icon") if rd.get("icon") is Texture2D else null
		
	if not data:
		return
		
	title_label.text = "获得道具"
	gold_label.visible = false
	soul_label.visible = false
	
	for child in material_list_container.get_children():
		if child != empty_label:
			child.queue_free()
	empty_label.visible = false
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER 
	
	var icon = TextureRect.new()
	if data.icon:
		icon.texture = data.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.custom_minimum_size = Vector2(24, 24)
		hbox.add_child(icon)
	
	if not data.icon:
		var label = Label.new()
		label.text = data.name + (" x" + str(count) if count > 1 else "")
		label.add_theme_font_size_override("font_size", 10)
		hbox.add_child(label)
	elif count > 1:
		var label = Label.new()
		label.text = "x" + str(count)
		label.add_theme_font_size_override("font_size", 10)
		hbox.add_child(label)
	
	material_list_container.add_child(hbox)
	
	confirm_button.visible = false
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_reward_summary_active = true
	Globals.is_item_get_popup_active = true
	
	await get_tree().create_timer(2.0, true, false, true).timeout
	if is_instance_valid(self) and visible:
		visible = false
		confirm_button.visible = true # ★ 修复：恢复按钮
		Globals.is_reward_summary_active = false
		Globals.is_item_get_popup_active = false
		confirmed.emit()


func show_text(text: String):
	if rating_label: rating_label.visible = false
	title_label.text = "提示"
	gold_label.visible = false
	soul_label.visible = false
	
	for child in material_list_container.get_children():
		if child != empty_label:
			child.queue_free()
	empty_label.visible = false
	
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 9)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_list_container.add_child(label)
	
	confirm_button.visible = false
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_reward_summary_active = true
	Globals.is_item_get_popup_active = true
	
	await get_tree().create_timer(2.0, true, false, true).timeout
	if is_instance_valid(self) and visible:
		visible = false
		confirm_button.visible = true # ★ 修复：恢复按钮
		Globals.is_reward_summary_active = false
		Globals.is_item_get_popup_active = false
		confirmed.emit()
