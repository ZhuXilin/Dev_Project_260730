extends CanvasLayer

signal closed

const SOUL_PER_POINT : int = 3
const SOUL_RESET_COST : int = 20
const GROWTH_TOTAL_CAP : int = 12

const ATTR_KEYS : Array = ["vitality", "strength", "dexterity", "intelligence", "faith", "arcane"]
const ATTR_NAMES : Dictionary = {
	"vitality":     "生命力",
	"strength":     "力量",
	"dexterity":    "灵巧",
	"intelligence": "智力",
	"faith":        "信仰",
	"arcane":       "感应",
}

enum Tab { ATTR, TALENT }
var _current_tab : Tab = Tab.ATTR
var _current_unit_type : String = ""
var _current_talent_id : String = ""


@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var attr_tab_btn : Button = $Panel/VBox/TabBar/AttrTabBtn
@onready var talent_tab_btn : Button = $Panel/VBox/TabBar/TalentTabBtn

@onready var left_title : Label = $Panel/VBox/MainHBox/LeftColumn/LeftTitle
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/LeftColumn/UnitListScroll/UnitList
@onready var unit_sprite : AnimatedSprite2D = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/SpriteContainer/UnitSprite
@onready var unit_name_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitNameLabel
@onready var unit_desc_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitDescLabel
@onready var attr_container : VBoxContainer = $Panel/VBox/MainHBox/InfoPanel/AttrContainer
@onready var point_label : Label = $Panel/VBox/MainHBox/InfoPanel/BottomBar/PointLabel
@onready var reset_btn : Button = $Panel/VBox/MainHBox/InfoPanel/BottomBar/ResetBtn


func _ready():
	MusicManager.play_soul_altar_music()
	_refresh_soul()
	_switch_tab(Tab.ATTR)


func _on_attr_tab_pressed(): _switch_tab(Tab.ATTR)
func _on_talent_tab_pressed(): _switch_tab(Tab.TALENT)

func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()


func _switch_tab(tab: Tab):
	_current_tab = tab
	attr_tab_btn.modulate = Color.WHITE if tab == Tab.ATTR else Color(0.5, 0.5, 0.5, 1)
	talent_tab_btn.modulate = Color.WHITE if tab == Tab.TALENT else Color(0.5, 0.5, 0.5, 1)

	if tab == Tab.ATTR:
		left_title.text = "— 单位 —"
		reset_btn.visible = true
		_build_unit_list()
		_refresh_attr_tab()
	else:
		left_title.text = "— 特技 —"
		reset_btn.visible = false
		_build_talent_list()
		_refresh_talent_detail()


# ============================================================
#  左列 · 单位（加点 tab）
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
		btn.text = UnitDataManager.get_unit_type_display_name(unit_type)
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
		lock_title.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		lock_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		lock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unit_list.add_child(lock_title)

	for unit_type in locked_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 2)

		var name_label = Label.new()
		name_label.text = UnitDataManager.get_unit_type_display_name(unit_type)
		name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
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
		unlock_btn.custom_minimum_size = Vector2(34, 0)
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
	_refresh_attr_tab()
	_show_msg("已解锁：%s" % UnitDataManager.get_unit_type_display_name(unit_type))


func _on_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			if ut != "":
				child.modulate = Color.WHITE if ut == unit_type else Color(0.7, 0.7, 0.7, 1)
	_refresh_attr_tab()


# ============================================================
#  左列 · 特技（特技 tab）
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

	# ---- 已解锁 ----
	if unlocked_list.size() > 0:
		var title1 = Label.new()
		title1.text = "— 已解锁 —"
		title1.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
		title1.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		title1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unit_list.add_child(title1)

		for tid in unlocked_list:
			var data : TalentData = TalentManager.get_talent_data(tid)
			if not data:
				continue
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

	# ---- 未解锁 ----
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
			if not data:
				continue
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

	# ---- 默认选中：优先选已解锁的第一个 ----
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
			if tid == "":
				continue
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
#  右列 · 加点 tab
# ============================================================
func _refresh_attr_tab():
	unit_sprite.visible = true

	if _current_unit_type == "":
		unit_name_label.text = "（未选择单位）"
		unit_name_label.remove_theme_color_override("font_color")
		unit_desc_label.text = ""
		unit_sprite.visible = false
		_clear_attr_container()
		point_label.text = "已分配: 0 / %d" % GROWTH_TOTAL_CAP
		_refresh_reset_btn()
		return

	var display = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	unit_name_label.text = display
	unit_name_label.remove_theme_color_override("font_color")

	var unit_dict = UnitDataManager.get_unit_data(_current_unit_type)
	unit_desc_label.text = unit_dict.get("description", "")
	_load_unit_sprite(_current_unit_type)

	var growth = _get_growth(_current_unit_type)
	var total = _sum_growth(growth)
	var at_cap = (total >= GROWTH_TOTAL_CAP)

	_clear_attr_container()
	for key in ATTR_KEYS:
		attr_container.add_child(_build_attr_row(key, growth.get(key, 0), at_cap))

	point_label.text = "已分配: %d / %d" % [total, GROWTH_TOTAL_CAP]
	_refresh_reset_btn()


func _build_attr_row(attr_key: String, current_points: int, at_cap: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.custom_minimum_size = Vector2(0, 11)

	var name_label = Label.new()
	name_label.text = ATTR_NAMES[attr_key]
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	name_label.custom_minimum_size = Vector2(34, 0)
	row.add_child(name_label)

	var base_dict = UnitDataManager.get_unit_data(_current_unit_type)
	var base_val = 0
	match attr_key:
		"vitality":     base_val = base_dict.get("max_hp", 0)
		"strength":     base_val = base_dict.get("strength", 0)
		"dexterity":    base_val = base_dict.get("dexterity", 0)
		"intelligence": base_dict.get("intelligence", 0)
		"faith":        base_dict.get("faith", 0)
		"arcane":       base_dict.get("arcane", 0)

	var value_label = Label.new()
	value_label.text = "%d (+%d) → %d" % [base_val, current_points, base_val + current_points]
	value_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.clip_text = true
	row.add_child(value_label)

	var add_btn = Button.new()
	add_btn.text = "+3"
	add_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	add_btn.custom_minimum_size = Vector2(28, 0)
	var can_add = (not at_cap) and GameState.soul >= SOUL_PER_POINT
	add_btn.disabled = not can_add
	add_btn.pressed.connect(_on_add_pressed.bind(attr_key))
	row.add_child(add_btn)

	return row


func _on_add_pressed(attr_key: String):
	if _current_unit_type == "":
		return
	var growth = _get_growth(_current_unit_type)
	var total = _sum_growth(growth)
	if total >= GROWTH_TOTAL_CAP:
		_show_msg("该单位已达成长上限")
		return
	if GameState.soul < SOUL_PER_POINT:
		_show_msg("魂不足！需要 %d" % SOUL_PER_POINT)
		return

	GameState.soul -= SOUL_PER_POINT
	if not GameState.unit_growth.has(_current_unit_type):
		GameState.unit_growth[_current_unit_type] = {}
	GameState.unit_growth[_current_unit_type][attr_key] = growth.get(attr_key, 0) + 1
	SaveManager.auto_save()

	_refresh_soul()
	_refresh_attr_tab()


func _on_reset_pressed():
	if _current_unit_type == "":
		return
	var growth = _get_growth(_current_unit_type)
	var total = _sum_growth(growth)
	if total <= 0:
		_show_msg("该单位尚未分配任何点数")
		return
	if GameState.soul < SOUL_RESET_COST:
		_show_msg("魂不足！需要 %d" % SOUL_RESET_COST)
		return

	GameState.soul -= SOUL_RESET_COST
	GameState.unit_growth.erase(_current_unit_type)
	SaveManager.auto_save()

	_refresh_soul()
	_refresh_attr_tab()


func _get_growth(unit_type: String) -> Dictionary:
	if not GameState.unit_growth.has(unit_type):
		return {}
	return GameState.unit_growth[unit_type]


func _sum_growth(growth: Dictionary) -> int:
	var total = 0
	for k in growth:
		total += int(growth[k])
	return total


# ============================================================
#  右列 · 特技 tab
# ============================================================
func _refresh_talent_detail():
	_clear_attr_container()
	unit_sprite.visible = false

	if _current_talent_id == "":
		unit_name_label.text = "（未选择特技）"
		unit_name_label.remove_theme_color_override("font_color")
		unit_desc_label.text = ""
		point_label.text = "魂：%d" % GameState.soul
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

	# ---- 未解锁：显示解锁按钮 ----
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
		point_label.text = "魂：%d" % GameState.soul
		return

	# ---- 已解锁：显示各单位经验 ----
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

	point_label.text = "魂：%d" % GameState.soul


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


func _refresh_reset_btn():
	if _current_unit_type == "":
		reset_btn.disabled = true
		return
	var growth = _get_growth(_current_unit_type)
	var total = _sum_growth(growth)
	reset_btn.disabled = (total <= 0 or GameState.soul < SOUL_RESET_COST)


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
			unit_sprite.position = Vector2(13, 4)
			return
	unit_sprite.visible = false


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"rare":      return Color(0.3, 0.6, 1.0, 1)
		"epic":      return Color(0.7, 0.3, 1.0, 1)
		"legendary": return Color(1.0, 0.7, 0.0, 1)
		_:           return Color.WHITE


func _show_msg(msg: String):
	var original = point_label.text
	point_label.text = msg
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(point_label):
		point_label.text = original
