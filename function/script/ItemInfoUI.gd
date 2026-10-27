extends PanelContainer

@onready var weapon_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/WeaponScroll/WeaponList
@onready var armor_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/ArmorScroll/ArmorList
@onready var relic_list = $VBoxContainer/HBoxContainer/LeftPanel/HBoxContainer/RelicScroll/RelicList
@onready var info_panel = $VBoxContainer/HBoxContainer/InfoPanel

var _current_filter : String = ""

func _ready():
	_build_filter_bar()
	_refresh_list()

func _build_filter_bar():
	if $VBoxContainer.has_node("FilterBar"):
		return
	var filter_bar = HBoxContainer.new()
	filter_bar.name = "FilterBar"
	filter_bar.add_theme_constant_override("separation", 4)

	var options = [["全部", ""], ["普通", "common"], ["稀有", "rare"], ["史诗", "epic"], ["传说", "legendary"]]
	for opt in options:
		var btn = Button.new()
		btn.text = opt[0]
		btn.add_theme_font_size_override("font_size", 6)
		btn.pressed.connect(_on_filter_pressed.bind(opt[1]))
		filter_bar.add_child(btn)

	var vbox = $VBoxContainer
	vbox.add_child(filter_bar)
	vbox.move_child(filter_bar, 1)

func _on_filter_pressed(quality: String):
	_current_filter = quality
	_refresh_list()

func _matches_filter(data) -> bool:
	if _current_filter == "": return true
	var q = data.get("quality", "") if data is Dictionary else data.quality
	return q == _current_filter

func _refresh_list():
	for list in [weapon_list, armor_list, relic_list]:
		if list:
			for child in list.get_children(): child.queue_free()

	_fill_weapon_column()
	_fill_armor_column()
	_fill_relic_column()

func _fill_weapon_column():
	var title = Label.new(); title.text = "武器"; title.add_theme_font_size_override("font_size", 9)
	weapon_list.add_child(title)
	for item_id in ItemManager._item_db.keys():
		var data = ItemManager.get_item_data(item_id)
		if not data or data.type != "weapon" or not _matches_filter(data): continue
		weapon_list.add_child(_make_item_button(data, true))

func _fill_armor_column():
	var title = Label.new(); title.text = "防具"; title.add_theme_font_size_override("font_size", 9)
	armor_list.add_child(title)
	for item_id in ItemManager._item_db.keys():
		var data = ItemManager.get_item_data(item_id)
		if not data or data.type != "armor" or not _matches_filter(data): continue
		armor_list.add_child(_make_item_button(data, true))

func _fill_relic_column():
	var title = Label.new(); title.text = "遗物"; title.add_theme_font_size_override("font_size", 9)
	relic_list.add_child(title)
	for relic_id in RelicManager.get_all_relic_ids():
		var data = RelicManager.get_relic_data(relic_id)
		if data.is_empty() or not _matches_filter(data): continue
		relic_list.add_child(_make_relic_button(relic_id, data, true))

func _make_item_button(data, unlocked: bool) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(20, 20)
	btn.expand_icon = true
	if data.icon:
		btn.icon = data.icon
		btn.tooltip_text = data.name
	else:
		btn.text = data.name
	btn.add_theme_font_size_override("font_size", 8)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(_show_item_detail.bind(data))
	btn.mouse_entered.connect(_show_item_detail.bind(data))
	return btn

func _make_relic_button(relic_id: String, data: Dictionary, unlocked: bool) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(20, 20)
	btn.expand_icon = true
	var icon = data.get("icon")
	if icon is Texture2D:
		btn.icon = icon
		btn.tooltip_text = data.get("name", relic_id)
	else:
		var prefix : String = "★ " if GameState.is_relic_refined(relic_id) else ""
		btn.text = prefix + data.get("name", relic_id)
	btn.add_theme_font_size_override("font_size", 8)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(_show_relic_detail.bind(relic_id))
	btn.mouse_entered.connect(_show_relic_detail.bind(relic_id))
	return btn

func _show_item_detail(data):
	if not info_panel: return
	var type_str = ""
	if data.quality: type_str += _quality_display(data.quality) + " "
	if data.tags: type_str += "[" + "/".join(data.tags) + "]"

	var stats_arr : Array = []
	if data.type == "weapon":
		stats_arr.append("攻击: %d" % data.base_attack)
		stats_arr.append("射程: %d~%d" % [data.min_attack_range, data.attack_range])
	elif data.type == "armor":
		if data.defense > 0: stats_arr.append("防御: +%d" % data.defense)

	info_panel.show_info({
		"name": data.name,
		"name_color": UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE),
		"type_str": type_str,
		"desc": data.description,
		"stats": "\n".join(stats_arr),
		"icon": data.icon
	})

func _show_relic_detail(relic_id: String):
	if not info_panel: return
	var data = RelicManager.get_relic_data(relic_id)
	var prefix : String = "★ " if GameState.is_relic_refined(relic_id) else ""
	var icon = null
	var path = data.get("icon", "")
	if path != "" and ResourceLoader.exists(path): icon = load(path)

	info_panel.show_info({
		"name": prefix + data.get("name", relic_id),
		"name_color": Color(1.0, 0.85, 0.3),
		"type_str": "遗物",
		"desc": data.get("description", ""),
		"stats": "",
		"icon": icon
	})

func _quality_display(q: String) -> String:
	match q:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
	return q

func _on_back_button_pressed():
	queue_free()
