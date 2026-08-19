extends PanelContainer

# ---- 三列容器引用 ----
@onready var weapon_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/WeaponScroll/WeaponList
@onready var armor_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/ArmorScroll/ArmorList
@onready var relic_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/RelicScroll/RelicList

# ---- 右侧详情面板引用 ----
@onready var item_icon = $VBoxContainer/HBoxContainer/RightPanel/ItemIcon
@onready var item_name = $VBoxContainer/HBoxContainer/RightPanel/ItemName
@onready var item_detail = $VBoxContainer/HBoxContainer/RightPanel/ItemDetail

func _ready():
	_refresh_list()

func _refresh_list():
	# 清空所有列表
	for list in [weapon_list, armor_list, relic_list]:
		for child in list.get_children():
			child.queue_free()
	
	# ---- 武器列：所有已解锁武器 ----
	_fill_weapon_column()
	
	# ---- 防具列：所有已解锁防具 ----
	_fill_armor_column()
	
	# ---- 遗物列：所有已解锁遗物（含未获得） ----
	_fill_relic_column()

func _fill_weapon_column():
	var title = Label.new()
	title.text = "武器"
	title.add_theme_font_size_override("font_size", 9)
	weapon_list.add_child(title)
	
	var weapon_items = []
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "weapon":
			weapon_items.append(data)
	
	if weapon_items.is_empty():
		_add_empty_label(weapon_list)
		return
	
	for data in weapon_items:
		var btn = Button.new()
		btn.text = data.name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 8)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_show_item_detail.bind(data))
		weapon_list.add_child(btn)

func _fill_armor_column():
	var title = Label.new()
	title.text = "防具"
	title.add_theme_font_size_override("font_size", 9)
	armor_list.add_child(title)
	
	var armor_items = []
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type in ["armor", "accessory"]:
			armor_items.append(data)
	
	if armor_items.is_empty():
		_add_empty_label(armor_list)
		return
	
	for data in armor_items:
		var btn = Button.new()
		btn.text = data.name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 8)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_show_item_detail.bind(data))
		armor_list.add_child(btn)

func _fill_relic_column():
	var title = Label.new()
	title.text = "遗物"
	title.add_theme_font_size_override("font_size", 9)
	relic_list.add_child(title)
	
	# 获取所有已解锁遗物 ID
	var unlocked_ids = RelicManager.get_unlocked_relics()
	if unlocked_ids.is_empty():
		_add_empty_label(relic_list)
		return
	
	# 获取已获得的遗物 ID 列表
	var owned_ids = []
	for relic in GameState.get_global_relics():
		owned_ids.append(relic.item_id)
	
	for relic_id in unlocked_ids:
		var data = RelicManager.get_relic_data(relic_id)
		if data.is_empty():
			continue
		var btn = Button.new()
		btn.text = data.name
		if relic_id in owned_ids:
			btn.text += " ✅"
			btn.modulate = Color(0.7, 1.0, 0.7)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 8)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_show_relic_detail.bind(data, relic_id))
		relic_list.add_child(btn)

func _add_empty_label(list_container: VBoxContainer):
	var label = Label.new()
	label.text = "（暂无）"
	label.add_theme_font_size_override("font_size", 7)
	label.modulate = Color(0.5, 0.5, 0.5)
	list_container.add_child(label)

func _show_item_detail(data: ItemData):
	if data.icon:
		item_icon.texture = data.icon
		item_icon.visible = true
	else:
		item_icon.visible = false
	item_name.text = data.name
	item_detail.text = data.description if data.description else "无描述"

func _show_relic_detail(data: Dictionary, relic_id: String):
	item_icon.visible = false
	item_name.text = data.get("name", "")
	var detail = data.get("description", "无描述")
	var stats = data.get("stats", {})
	if not stats.is_empty():
		detail += "\n\n属性加成："
		for key in stats:
			detail += "\n" + _get_stat_display_name(key) + ": +" + str(stats[key])
	# 检查是否已获得
	var has_relic = false
	for relic in GameState.get_global_relics():
		if relic.item_id == relic_id:
			has_relic = true
			break
	if has_relic:
		detail += "\n\n状态：已获得 ✅"
	else:
		detail += "\n\n状态：未获得"
	item_detail.text = detail

func _get_stat_display_name(key: String) -> String:
	var names = {
		"attack": "攻击",
		"defense": "防御",
		"magic_attack": "魔法攻击",
		"move_range": "移动力"
	}
	return names.get(key, key)

func _on_back_button_pressed():
	queue_free()
