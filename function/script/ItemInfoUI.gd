extends PanelContainer

# ---- 三列容器 ----
@onready var weapon_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/WeaponScroll/WeaponList
@onready var armor_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/ArmorScroll/ArmorList
@onready var relic_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/RelicScroll/RelicList

# ---- 右侧详情 ----
@onready var item_icon = $VBoxContainer/HBoxContainer/RightPanel/ItemIcon
@onready var item_name = $VBoxContainer/HBoxContainer/RightPanel/ItemName
@onready var item_detail = $VBoxContainer/HBoxContainer/RightPanel/ItemDetail

# ---- 筛选 ----
var _current_filter : String = ""   # ""=全部 / common / rare / epic / legendary

func _ready():
	_build_filter_bar()
	_refresh_list()

# ============================================================
#  筛选栏
# ============================================================
func _build_filter_bar():
	# 避免重复创建
	if $VBoxContainer.has_node("FilterBar"):
		return

	var filter_bar = HBoxContainer.new()
	filter_bar.name = "FilterBar"
	filter_bar.add_theme_constant_override("separation", 4)

	var options = [
		["全部", ""],
		["普通", "common"],
		["稀有", "rare"],
		["史诗", "epic"],
		["传说", "legendary"],
	]
	for opt in options:
		var btn = Button.new()
		btn.text = opt[0]
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		btn.pressed.connect(_on_filter_pressed.bind(opt[1]))
		filter_bar.add_child(btn)

	# 插到 Title 之后
	var vbox = $VBoxContainer
	vbox.add_child(filter_bar)
	vbox.move_child(filter_bar, 1)

func _on_filter_pressed(quality: String):
	_current_filter = quality
	_refresh_list()

func _matches_filter(data) -> bool:
	if _current_filter == "":
		return true
	var q = ""
	if data is Dictionary:
		q = data.get("quality", "")
	else:
		q = data.quality if "quality" in data else ""
	return q == _current_filter

# ============================================================
#  列表刷新
# ============================================================
func _refresh_list():
	for list in [weapon_list, armor_list, relic_list]:
		if list:
			for child in list.get_children():
				child.queue_free()

	_fill_weapon_column()
	_fill_armor_column()
	_fill_relic_column()

func _fill_weapon_column():
	var title = Label.new()
	title.text = "武器"
	title.add_theme_font_size_override("font_size", 9)
	weapon_list.add_child(title)

	var item_ids = []
	for item_id in ItemManager._item_db.keys():
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "weapon":
			item_ids.append(item_id)

	for item_id in item_ids:
		var data = ItemManager.get_item_data(item_id)
		if not _matches_filter(data):
			continue
		var unlocked = Globals.is_item_unlocked(item_id)
		weapon_list.add_child(_make_item_button(data, unlocked))

func _fill_armor_column():
	var title = Label.new()
	title.text = "防具"
	title.add_theme_font_size_override("font_size", 9)
	armor_list.add_child(title)

	var item_ids = []
	for item_id in ItemManager._item_db.keys():
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "armor":
			item_ids.append(item_id)

	for item_id in item_ids:
		var data = ItemManager.get_item_data(item_id)
		if not _matches_filter(data):
			continue
		var unlocked = Globals.is_item_unlocked(item_id)
		armor_list.add_child(_make_item_button(data, unlocked))

func _fill_relic_column():
	var title = Label.new()
	title.text = "遗物"
	title.add_theme_font_size_override("font_size", 9)
	relic_list.add_child(title)

	var all_ids = RelicManager.get_all_relic_ids()
	for relic_id in all_ids:
		var data = RelicManager.get_relic_data(relic_id)
		if data.is_empty():
			continue
		if not _matches_filter(data):
			continue
		var unlocked = RelicManager.is_relic_unlocked(relic_id)
		relic_list.add_child(_make_relic_button(relic_id, data, unlocked))

# ============================================================
#  按钮构建
# ============================================================
func _make_item_button(data, unlocked: bool) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 8)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if unlocked:
		btn.text = data.name
		btn.pressed.connect(_show_item_detail.bind(data))
	else:
		btn.text = "？？？"
		btn.modulate = Color(0.4, 0.4, 0.4)
		btn.disabled = true

	return btn

func _make_relic_button(relic_id: String, data: Dictionary, unlocked: bool) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 8)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if unlocked:
		btn.text = data.get("name", relic_id)
		btn.pressed.connect(_show_relic_detail.bind(data, relic_id))
	else:
		btn.text = "？？？"
		btn.modulate = Color(0.4, 0.4, 0.4)
		btn.disabled = true

	return btn

# ============================================================
#  详情显示（增强）
# ============================================================
func _show_item_detail(data):
	# ---- 图标 ----
	if data.icon:
		item_icon.texture = data.icon
		item_icon.visible = true
	else:
		item_icon.visible = false

	# ---- 名称 + 品质颜色 ----
	item_name.text = data.name
	var q_color = UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE)
	item_name.add_theme_color_override("font_color", q_color)

	# ---- 详情 ----
	var lines = []
	lines.append("品质: " + _quality_display(data.quality))
	if data.description:
		lines.append(data.description)

	if data.type == "weapon":
		lines.append("基础攻击: " + str(data.base_attack))
		lines.append("射程: " + str(data.min_attack_range) + "~" + str(data.attack_range))
		if data.modifier and not data.modifier.is_empty():
			var parts = []
			for key in data.modifier:
				parts.append(_attr_display(key) + "+" + str(data.modifier[key]))
			lines.append("补正: " + " ".join(parts))
	elif data.type == "armor":
		if data.defense > 0:
			lines.append("防御: +" + str(data.defense))

	item_detail.text = "\n".join(lines)

func _show_relic_detail(data: Dictionary, _relic_id: String):
	item_icon.visible = false
	item_name.text = data.get("name", "")
	item_name.remove_theme_color_override("font_color")

	var lines = []
	lines.append(data.get("description", "无描述"))
	var stats = data.get("stats", {})
	if not stats.is_empty():
		lines.append("")
		lines.append("属性加成：")
		for key in stats:
			lines.append("  " + _attr_display(key) + " +" + str(stats[key]))
	item_detail.text = "\n".join(lines)

# ============================================================
#  辅助
# ============================================================
func _quality_display(q: String) -> String:
	match q:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return q

func _attr_display(key: String) -> String:
	var names = {
		"strength": "力量", "dexterity": "灵巧", "intelligence": "智力",
		"faith": "信仰", "arcane": "感应",
		"attack": "攻击", "defense": "防御", "magic_attack": "魔法攻击",
		"move_range": "移动力",
	}
	return names.get(key, key)

func _on_back_button_pressed():
	queue_free()
