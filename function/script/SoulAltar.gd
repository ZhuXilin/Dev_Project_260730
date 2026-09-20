extends CanvasLayer

signal closed

const SOUL_WEAPON_COST : int = 500

enum Tab { BLESSING, TALENT, SOUL_FORGE }
var _current_tab : Tab = Tab.BLESSING
var _current_unit_type : String = ""
var _current_talent_id : String = ""


@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var attr_tab_btn : Button = $Panel/VBox/TabBar/AttrTabBtn
@onready var talent_tab_btn : Button = $Panel/VBox/TabBar/TalentTabBtn
@onready var soul_forge_tab_btn : Button = $Panel/VBox/TabBar/SoulForgeTabBtn

@onready var left_title : Label = $Panel/VBox/MainHBox/LeftColumn/LeftTitle
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/LeftColumn/UnitListScroll/UnitList
@onready var unit_sprite : AnimatedSprite2D = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/SpriteContainer/UnitSprite
@onready var unit_name_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitNameLabel
@onready var unit_desc_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitDescLabel
@onready var attr_container : VBoxContainer = $Panel/VBox/MainHBox/InfoPanel/AttrScroll/AttrContainer
@onready var point_label : Label = $Panel/VBox/MainHBox/InfoPanel/BottomBar/PointLabel
@onready var reset_btn : Button = $Panel/VBox/MainHBox/InfoPanel/BottomBar/ResetBtn


func _ready():
	MusicManager.play_soul_altar_music()
	if attr_tab_btn:
		attr_tab_btn.text = "祝福"
	if reset_btn:
		reset_btn.visible = false
	if point_label:
		point_label.visible = false    # ★ 平时隐藏，仅消息提示时显示
	if soul_forge_tab_btn and not soul_forge_tab_btn.pressed.is_connected(_on_soul_forge_tab_pressed):
		soul_forge_tab_btn.pressed.connect(_on_soul_forge_tab_pressed)
	_refresh_soul()
	_switch_tab(Tab.BLESSING)


func _on_attr_tab_pressed(): _switch_tab(Tab.BLESSING)
func _on_talent_tab_pressed(): _switch_tab(Tab.TALENT)
func _on_soul_forge_tab_pressed(): _switch_tab(Tab.SOUL_FORGE)

func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()


func _switch_tab(tab: Tab):
	_current_tab = tab
	if attr_tab_btn:
		attr_tab_btn.modulate = Color.WHITE if tab == Tab.BLESSING else Color(0.5, 0.5, 0.5, 1)
	if talent_tab_btn:
		talent_tab_btn.modulate = Color.WHITE if tab == Tab.TALENT else Color(0.5, 0.5, 0.5, 1)
	if soul_forge_tab_btn:
		soul_forge_tab_btn.modulate = Color.WHITE if tab == Tab.SOUL_FORGE else Color(0.5, 0.5, 0.5, 1)

	if tab == Tab.BLESSING:
		left_title.text = "— 单位 —"
		_build_unit_list()
		_refresh_blessing_panel()
	elif tab == Tab.TALENT:
		left_title.text = "— 特技 —"
		_build_talent_list()
		_refresh_talent_detail()
	else:
		left_title.text = "— 单位 —"
		_build_unit_list()
		_refresh_soul_forge_panel()


# ============================================================
#  左列 · 单位列表
# ============================================================
func _build_unit_list():
	for child in unit_list.get_children():
		unit_list.remove_child(child)
		child.queue_free()

	var all_units = UnitDataManager.get_all_unit_ids()
	var unlocked_list : Array = []
	var locked_list : Array = []
	for unit_type in all_units:
		if Globals.is_unit_unlocked(unit_type):
			unlocked_list.append(unit_type)
		else:
			locked_list.append(unit_type)

	for unit_type in unlocked_list:
		var btn = Button.new()
		var type_display = UnitDataManager.get_unit_type_display_name(unit_type)
		if _current_tab == Tab.BLESSING:
			var rank = BlessingManager.get_blessing_rank(unit_type)
			var max_rank = BlessingManager.get_max_blessing_rank(unit_type)
			btn.text = "%s  [祝福 %d/%d]" % [type_display, rank, max_rank]
		elif _current_tab == Tab.SOUL_FORGE:
			var soul_weapon : String = UnitDataManager.get_unit_data(unit_type).get("soul_weapon", "")
			if soul_weapon != "" and Globals.is_item_unlocked(soul_weapon):
				btn.text = "%s  [已铸]" % type_display
			else:
				btn.text = type_display
		else:
			btn.text = type_display
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_color_hover", Color.WHITE)
		btn.add_theme_color_override("font_color_pressed", Color.WHITE)
		btn.add_theme_color_override("font_color_focus", Color.WHITE)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE if unit_type == _current_unit_type else Color(0.7, 0.7, 0.7, 1)
		btn.pressed.connect(_on_unit_selected.bind(unit_type))
		unit_list.add_child(btn)

	if locked_list.size() > 0:
		var sep = HSeparator.new()
		sep.modulate = Color(0.4, 0.4, 0.4, 1)
		unit_list.add_child(sep)
		var lock_title = Label.new()
		lock_title.text = "— 未解锁 —"
		lock_title.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
		lock_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		lock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unit_list.add_child(lock_title)

	for unit_type in locked_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 2)

		var name_label = Label.new()
		name_label.text = UnitDataManager.get_unit_type_display_name(unit_type)
		name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		name_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(name_label)

		var cost : int = Globals.get_unit_unlock_cost(unit_type)
		var unlock_btn = Button.new()
		unlock_btn.text = "%d魂" % cost
		unlock_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
		unlock_btn.add_theme_color_override("font_color", Color.WHITE)
		unlock_btn.add_theme_color_override("font_color_hover", Color.WHITE)
		unlock_btn.add_theme_color_override("font_color_pressed", Color.WHITE)
		unlock_btn.add_theme_color_override("font_color_disabled", Color(0.5, 0.5, 0.5, 1))
		unlock_btn.custom_minimum_size = Vector2(44, 0)
		unlock_btn.disabled = GameState.soul < cost
		unlock_btn.pressed.connect(_on_unlock_unit.bind(unit_type))
		row.add_child(unlock_btn)

		unit_list.add_child(row)

	if _current_unit_type == "" and unlocked_list.size() > 0:
		_current_unit_type = unlocked_list[0]


func _on_unlock_unit(unit_type: String):
	var cost : int = Globals.get_unit_unlock_cost(unit_type)
	if GameState.soul < cost:
		_show_msg("魂不足！需要 %d" % cost)
		return
	GameState.soul -= cost
	Globals.unlock_unit(unit_type)
	SaveManager.auto_save()
	_refresh_soul()
	_build_unit_list()
	if _current_tab == Tab.BLESSING:
		_refresh_blessing_panel()
	elif _current_tab == Tab.SOUL_FORGE:
		_refresh_soul_forge_panel()
	_show_msg("已解锁：%s" % UnitDataManager.get_unit_type_display_name(unit_type))


func _on_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			if ut != "":
				child.modulate = Color.WHITE if ut == unit_type else Color(0.7, 0.7, 0.7, 1)
	if _current_tab == Tab.BLESSING:
		_refresh_blessing_panel()
	elif _current_tab == Tab.SOUL_FORGE:
		_refresh_soul_forge_panel()


# ============================================================
#  右列 · 属性总览（新增）
# ============================================================
func _build_stats_overview(unit_type: String) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var title = Label.new()
	title.text = "—— 属性 ——"
	title.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.6, 0.6, 0.6, 1)
	box.add_child(title)

	var dict : Dictionary = UnitDataManager.get_unit_data(unit_type)
	var attrs : Array = [
		{"key": "max_hp",       "display": "HP"},
		{"key": "strength",     "display": "力量"},
		{"key": "dexterity",    "display": "灵巧"},
		{"key": "intelligence", "display": "智力"},
		{"key": "faith",        "display": "信仰"},
		{"key": "arcane",       "display": "感应"},
		{"key": "move_range",   "display": "移动力"},
	]
	for a in attrs:
		var base : int = int(dict.get(a["key"], 0))
		var bonus : int = _get_blessing_bonus_for_attr(unit_type, a["key"])
		box.add_child(_build_stat_line(a["display"], base, bonus))
	return box


func _get_blessing_bonus_for_attr(unit_type: String, attr_key: String) -> int:
	var total : int = 0
	for b in BlessingManager.get_all():
		if b["attr"] == attr_key:
			total += BlessingManager.get_bonus(unit_type, b["id"])
	return total


func _build_stat_line(display: String, base: int, bonus: int) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0, 11)

	var name_lb = Label.new()
	name_lb.text = display
	name_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	name_lb.custom_minimum_size = Vector2(52, 0)
	row.add_child(name_lb)

	var val_lb = Label.new()
	val_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	val_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lb.clip_text = true
	if bonus > 0:
		val_lb.text = "%d  +%d → %d" % [base, bonus, base + bonus]
		val_lb.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 1))
	else:
		val_lb.text = "%d" % base
		val_lb.modulate = Color(0.75, 0.75, 0.75, 1)
	row.add_child(val_lb)

	return row


# ============================================================
#  右列 · 祝福面板
# ============================================================
func _refresh_blessing_panel():
	_clear_attr_container()
	point_label.visible = false
	unit_sprite.visible = true

	if _current_unit_type == "":
		unit_name_label.text = "（未选择单位）"
		unit_name_label.remove_theme_color_override("font_color")
		unit_desc_label.text = ""
		unit_sprite.visible = false
		return

	var display = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	var rank = BlessingManager.get_blessing_rank(_current_unit_type)
	var max_rank = BlessingManager.get_max_blessing_rank(_current_unit_type)
	unit_name_label.text = "%s   祝福 %d/%d" % [display, rank, max_rank]
	unit_name_label.remove_theme_color_override("font_color")

	var unit_dict = UnitDataManager.get_unit_data(_current_unit_type)
	unit_desc_label.text = unit_dict.get("description", "")
	_load_unit_sprite(_current_unit_type)

	# ★ 属性总览
	attr_container.add_child(_build_stats_overview(_current_unit_type))

	var sep0 = HSeparator.new()
	sep0.modulate = Color(0.4, 0.4, 0.4, 1)
	attr_container.add_child(sep0)

	# 祝福列表
	var available : Array = BlessingManager.get_available_for_unit(_current_unit_type)
	for b in available:
		attr_container.add_child(_build_blessing_row(b))

	var all_b : Array = BlessingManager.get_all()
	if available.size() < all_b.size():
		var hint = Label.new()
		hint.text = "（该单位仅可加以上 %d 种祝福）" % available.size()
		hint.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.modulate = Color(0.5, 0.5, 0.5, 1)
		attr_container.add_child(hint)


func _build_blessing_row(b : Dictionary) -> HBoxContainer:
	var blessing_id : String = b["id"]
	var lv : int = BlessingManager.get_level(_current_unit_type, blessing_id)
	var bonus : int = BlessingManager.get_bonus(_current_unit_type, blessing_id)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0, 14)

	var name_label = Label.new()
	name_label.text = b["name"]
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	name_label.custom_minimum_size = Vector2(52, 0)
	row.add_child(name_label)

	var value_label = Label.new()
	value_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.clip_text = true
	if lv > 0:
		value_label.text = "Lv%d  +%d" % [lv, bonus]
		value_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 1))
	else:
		value_label.text = "Lv0"
		value_label.modulate = Color(0.6, 0.6, 0.6, 1)
	row.add_child(value_label)

	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(80, 0)

	var next_cost : int = BlessingManager.get_next_cost(_current_unit_type, blessing_id)
	if next_cost < 0:
		btn.text = "MAX"
		btn.disabled = true
	else:
		btn.text = "%d 魂" % next_cost
		var can : bool = BlessingManager.can_upgrade(_current_unit_type, blessing_id)
		btn.disabled = not can
		btn.pressed.connect(_on_blessing_upgrade.bind(blessing_id))

	row.add_child(btn)
	return row


func _on_blessing_upgrade(blessing_id: String):
	if _current_unit_type == "":
		return
	if BlessingManager.upgrade(_current_unit_type, blessing_id):
		SaveManager.auto_save()
		_refresh_soul()
		_build_unit_list()
		_refresh_blessing_panel()


# ============================================================
#  右列 · 魂铸面板
# ============================================================
func _refresh_soul_forge_panel():
	_clear_attr_container()
	point_label.visible = false
	unit_sprite.visible = true

	if _current_unit_type == "":
		unit_name_label.text = "（未选择单位）"
		unit_name_label.remove_theme_color_override("font_color")
		unit_desc_label.text = ""
		unit_sprite.visible = false
		return

	var display = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	unit_name_label.text = display + " · 魂铸武器"
	unit_name_label.remove_theme_color_override("font_color")

	var unit_dict = UnitDataManager.get_unit_data(_current_unit_type)
	unit_desc_label.text = unit_dict.get("description", "")
	_load_unit_sprite(_current_unit_type)

	var soul_weapon_id : String = unit_dict.get("soul_weapon", "")
	if soul_weapon_id == "":
		var hint = Label.new()
		hint.text = "该单位暂无魂铸武器"
		hint.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.modulate = Color(0.6, 0.6, 0.6, 1)
		attr_container.add_child(hint)
		return

	var wdata : ItemData = ItemManager.get_item_data(soul_weapon_id)
	if not wdata:
		var hint = Label.new()
		hint.text = "魂铸武器数据缺失：" + soul_weapon_id
		hint.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		hint.modulate = Color(1.0, 0.4, 0.4, 1)
		attr_container.add_child(hint)
		return

	var name_lb = Label.new()
	name_lb.text = "★ " + wdata.name
	name_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
	name_lb.add_theme_color_override("font_color", Color(1.0, 0.7, 0.0, 1))
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attr_container.add_child(name_lb)

	var desc_lb = Label.new()
	desc_lb.text = wdata.description
	desc_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	desc_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lb.modulate = Color(0.75, 0.75, 0.75, 1)
	attr_container.add_child(desc_lb)

	var sep1 = HSeparator.new()
	sep1.modulate = Color(0.4, 0.4, 0.4, 1)
	attr_container.add_child(sep1)

	var stat_lines : Array = []
	if wdata.type == "weapon":
		if wdata.base_attack > 0:
			stat_lines.append("基础攻击：%d" % wdata.base_attack)
		if not wdata.heal_effect.is_empty():
			stat_lines.append("治疗：+%d" % wdata.heal_effect.get("base_heal", 0))
		stat_lines.append("射程：%d~%d" % [wdata.min_attack_range, wdata.attack_range])
		if not wdata.modifier.is_empty():
			var mod_parts : Array = []
			for key in wdata.modifier:
				mod_parts.append("%s+%.1f" % [_attr_display(key), float(wdata.modifier[key])])
			stat_lines.append("补正：" + "  ".join(mod_parts))
		if not wdata.magic_attack.is_empty():
			if wdata.magic_attack.get("ignore_defense", false):
				stat_lines.append("★ 无视防御")

	var stat_lb = Label.new()
	stat_lb.text = "\n".join(stat_lines)
	stat_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	stat_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attr_container.add_child(stat_lb)

	var sep2 = HSeparator.new()
	sep2.modulate = Color(0.4, 0.4, 0.4, 1)
	attr_container.add_child(sep2)

	var unlocked : bool = Globals.is_item_unlocked(soul_weapon_id)

	if unlocked:
		var done_lb = Label.new()
		done_lb.text = "已铸"
		done_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
		done_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done_lb.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
		attr_container.add_child(done_lb)
	else:
		var cost_lb = Label.new()
		cost_lb.text = "铸造消耗：%d 魂" % SOUL_WEAPON_COST
		cost_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		cost_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		attr_container.add_child(cost_lb)

		var btn = Button.new()
		btn.text = "铸造"
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.custom_minimum_size = Vector2(0, 22)
		var can_afford : bool = GameState.soul >= SOUL_WEAPON_COST
		if not can_afford:
			btn.text = "魂不足"
			btn.disabled = true
			btn.modulate = Color(0.55, 0.55, 0.55, 1)
		else:
			btn.pressed.connect(_on_forge_soul_weapon.bind(soul_weapon_id, wdata.name))
		attr_container.add_child(btn)


func _on_forge_soul_weapon(item_id: String, weapon_name: String):
	if GameState.soul < SOUL_WEAPON_COST:
		return
	GameState.soul -= SOUL_WEAPON_COST
	Globals.unlock_item(item_id)
	SaveManager.auto_save()
	_refresh_soul()
	_build_unit_list()
	_refresh_soul_forge_panel()
	_show_msg("已铸：" + weapon_name)


# ============================================================
#  左列 · 特技列表
# ============================================================
func _build_talent_list():
	for child in unit_list.get_children():
		unit_list.remove_child(child)
		child.queue_free()

	var all_ids = TalentManager.get_all_talent_ids()
	var unlocked_list : Array = []
	var locked_list : Array = []
	for tid in all_ids:
		if Globals.is_talent_unlocked(tid):
			unlocked_list.append(tid)
		else:
			locked_list.append(tid)

	if unlocked_list.size() > 0:
		var title1 = Label.new()
		title1.text = "— 已解锁 —"
		title1.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
		title1.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		title1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unit_list.add_child(title1)

		for tid in unlocked_list:
			var data : TalentData = TalentManager.get_talent_data(tid)
			if not data: continue
			var btn = Button.new()
			btn.text = data.display_name
			btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.add_theme_color_override("font_color_hover", Color.WHITE)
			btn.add_theme_color_override("font_color_pressed", Color.WHITE)
			btn.add_theme_color_override("font_color_focus", Color.WHITE)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.set_meta("talent_id", tid)
			btn.modulate = Color.WHITE if tid == _current_talent_id else Color(0.7, 0.7, 0.7, 1)
			btn.pressed.connect(_on_talent_selected.bind(tid))
			unit_list.add_child(btn)

	if locked_list.size() > 0:
		var sep = HSeparator.new()
		sep.modulate = Color(0.4, 0.4, 0.4, 1)
		unit_list.add_child(sep)
		var title2 = Label.new()
		title2.text = "— 未解锁 —"
		title2.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
		title2.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		title2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unit_list.add_child(title2)

		for tid in locked_list:
			var data : TalentData = TalentManager.get_talent_data(tid)
			if not data: continue
			var btn = Button.new()
			btn.text = data.display_name
			btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
			btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
			btn.add_theme_color_override("font_color_hover", Color(0.8, 0.8, 0.8, 1))
			btn.add_theme_color_override("font_color_pressed", Color(0.9, 0.9, 0.9, 1))
			btn.add_theme_color_override("font_color_focus", Color(0.6, 0.6, 0.6, 1))
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.set_meta("talent_id", tid)
			if tid == _current_talent_id:
				btn.modulate = Color(0.85, 0.85, 0.85, 1)
			else:
				btn.modulate = Color(0.5, 0.5, 0.5, 1)
			btn.pressed.connect(_on_talent_selected.bind(tid))
			unit_list.add_child(btn)

	if _current_talent_id == "":
		if unlocked_list.size() > 0:
			_current_talent_id = unlocked_list[0]
		elif locked_list.size() > 0:
			_current_talent_id = locked_list[0]


func _on_talent_selected(talent_id: String):
	_current_talent_id = talent_id
	for child in unit_list.get_children():
		if child is Button:
			var tid : String = child.get_meta("talent_id", "")
			if tid == "": continue
			var is_unlocked = Globals.is_talent_unlocked(tid)
			if not is_unlocked:
				if tid == talent_id:
					child.modulate = Color(0.85, 0.85, 0.85, 1)
				else:
					child.modulate = Color(0.5, 0.5, 0.5, 1)
			else:
				child.modulate = Color.WHITE if tid == talent_id else Color(0.7, 0.7, 0.7, 1)
	_refresh_talent_detail()


# ============================================================
#  右列 · 特技详情
# ============================================================
func _refresh_talent_detail():
	_clear_attr_container()
	point_label.visible = false
	unit_sprite.visible = false

	if _current_talent_id == "":
		unit_name_label.text = "（未选择特技）"
		unit_name_label.remove_theme_color_override("font_color")
		unit_desc_label.text = ""
		return

	var data : TalentData = TalentManager.get_talent_data(_current_talent_id)
	if not data:
		unit_name_label.text = "?"
		unit_desc_label.text = ""
		return

	var is_unlocked = Globals.is_talent_unlocked(_current_talent_id)

	unit_name_label.text = data.display_name
	unit_name_label.add_theme_color_override("font_color", _rarity_color(data.rarity))

	var desc_lines : Array = []
	desc_lines.append(data.description)
	desc_lines.append("稀有度: %s   流派: %s   积累: %d 回合" % [
		data.rarity, data.school, data.accumulation_threshold])
	var compatible : Array = data.compatible_units if data.compatible_units != null else []
	if compatible.is_empty():
		desc_lines.append("可装备: 全部单位")
	else:
		var names : Array = []
		for key in compatible:
			names.append(UnitDataManager.get_unit_type_display_name(key))
		desc_lines.append("可装备: " + " / ".join(names))
	unit_desc_label.text = "\n".join(desc_lines)

	if not is_unlocked:
		var unlock_btn = Button.new()
		unlock_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		unlock_btn.custom_minimum_size = Vector2(0, 22)
		var cost : int = Globals.get_talent_soul_cost(_current_talent_id)
		if cost > 0:
			unlock_btn.text = "解锁（%d 魂）" % cost
			unlock_btn.disabled = not Globals.can_soul_unlock_talent(_current_talent_id)
			unlock_btn.pressed.connect(_on_unlock_talent.bind(_current_talent_id))
		else:
			unlock_btn.text = "剧情获取 / 不可解锁"
			unlock_btn.disabled = true
		attr_container.add_child(unlock_btn)
		return

	var title = Label.new()
	title.text = "—— 各单位经验 ——"
	title.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.7, 0.7, 0.7, 1)
	attr_container.add_child(title)

	var units_to_show : Array = []
	if compatible.is_empty():
		for ut in Globals.get_unlocked_units():
			units_to_show.append(ut)
	else:
		for key in compatible:
			if Globals.is_unit_unlocked(key):
				units_to_show.append(key)

	if units_to_show.is_empty():
		var empty_lb = Label.new()
		empty_lb.text = "（无已解锁的兼容单位）"
		empty_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		empty_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lb.modulate = Color(0.6, 0.6, 0.6, 1)
		attr_container.add_child(empty_lb)
	else:
		for ut in units_to_show:
			attr_container.add_child(_build_talent_exp_row(ut))


func _build_talent_exp_row(unit_type: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 11)

	var name_lb = Label.new()
	name_lb.text = UnitDataManager.get_unit_type_display_name(unit_type)
	name_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	name_lb.custom_minimum_size = Vector2(44, 0)
	row.add_child(name_lb)

	var exp_lb = Label.new()
	exp_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	exp_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if TalentManager.is_talent_max_level(unit_type, _current_talent_id):
		exp_lb.text = "Lv%d   MAX" % TalentManager.get_talent_level(unit_type, _current_talent_id)
	else:
		var lv = TalentManager.get_talent_level(unit_type, _current_talent_id)
		var cur = TalentManager.get_talent_exp_in_level(unit_type, _current_talent_id)
		var need = TalentManager.get_level_required_exp(unit_type, _current_talent_id)
		exp_lb.text = "Lv%d   %d / %d" % [lv, cur, need]
	row.add_child(exp_lb)

	return row


func _on_unlock_talent(talent_id: String):
	if Globals.soul_unlock_talent(talent_id):
		_refresh_soul()
		_build_talent_list()
		_refresh_talent_detail()


# ============================================================
#  通用辅助
# ============================================================
func _refresh_soul():
	soul_label.text = "魂: " + str(GameState.soul)


func _clear_attr_container():
	for child in attr_container.get_children():
		attr_container.remove_child(child)
		child.queue_free()


func _load_unit_sprite(unit_type: String):
	var path = UnitDataManager.get_sprite_frames_path(unit_type)
	if path != "" and ResourceLoader.exists(path):
		var frames = load(path) as SpriteFrames
		if frames:
			unit_sprite.sprite_frames = frames
			if frames.has_animation("idle"):
				unit_sprite.play("idle")
			else:
				var anims = frames.get_animation_names()
				if anims.size() > 0:
					unit_sprite.play(anims[0])
			unit_sprite.visible = true
			unit_sprite.position = Vector2(13, 8)
			return
	unit_sprite.visible = false


func _attr_display(key: String) -> String:
	match key:
		"strength":     return "力量"
		"dexterity":    return "灵巧"
		"intelligence": return "智力"
		"faith":        return "信仰"
		"arcane":       return "感应"
		"attack":       return "攻击"
		"defense":      return "防御"
		"magic_attack": return "魔法攻击"
		"move_range":   return "移动力"
		"max_hp":       return "最大HP"
		_:              return key


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"rare":      return Color(0.3, 0.6, 1.0, 1)
		"epic":      return Color(0.7, 0.3, 1.0, 1)
		"legendary": return Color(1.0, 0.7, 0.0, 1)
		_:           return Color.WHITE


func _show_msg(msg: String):
	if not point_label:
		return
	point_label.visible = true
	point_label.text = msg
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(point_label):
		point_label.visible = false
		point_label.text = ""
