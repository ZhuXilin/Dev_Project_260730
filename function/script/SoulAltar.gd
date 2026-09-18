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


@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var attr_tab_btn : Button = $Panel/VBox/TabBar/AttrTabBtn
@onready var talent_tab_btn : Button = $Panel/VBox/TabBar/TalentTabBtn

@onready var unit_list_scroll : ScrollContainer = $Panel/VBox/MainHBox/UnitListScroll
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/UnitListScroll/UnitList
@onready var unit_sprite : AnimatedSprite2D = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/SpriteContainer/UnitSprite
@onready var unit_name_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitNameLabel
@onready var unit_desc_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitDescLabel
@onready var attr_container : VBoxContainer = $Panel/VBox/MainHBox/InfoPanel/AttrScroll/AttrContainer
@onready var point_label : Label = $Panel/VBox/MainHBox/InfoPanel/BottomBar/PointLabel
@onready var reset_btn : Button = $Panel/VBox/MainHBox/InfoPanel/BottomBar/ResetBtn


func _ready():
	MusicManager.play_soul_altar_music()
	_build_unit_list()
	_refresh_soul()
	_refresh_reset_btn()
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
		unit_list_scroll.visible = true
		reset_btn.visible = true        # ★ 加点 tab 显示
		_refresh_all()
	else:
		unit_list_scroll.visible = false
		reset_btn.visible = false       # ★ 特技 tab 隐藏
		_build_talent_tab()


# ============================================================
#  单位列表
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

	# ---- 已解锁：普通按钮 ----
	for unit_type in unlocked_list:
		var btn = Button.new()
		btn.text = UnitDataManager.get_unit_type_display_name(unit_type)
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE
		btn.pressed.connect(_on_unit_selected.bind(unit_type))
		unit_list.add_child(btn)

	# ---- 未解锁：真名 + 解锁按钮 ----
	for unit_type in locked_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label = Label.new()
		name_label.text = UnitDataManager.get_unit_type_display_name(unit_type)
		name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.modulate = Color(0.5, 0.5, 0.5, 1)
		row.add_child(name_label)

		var cost : int = Globals.get_unit_unlock_cost(unit_type)
		var unlock_btn = Button.new()
		unlock_btn.text = "%d 魂" % cost
		unlock_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		unlock_btn.custom_minimum_size = Vector2(60, 0)
		unlock_btn.disabled = GameState.soul < cost
		unlock_btn.pressed.connect(_on_unlock_unit.bind(unit_type))
		row.add_child(unlock_btn)

		unit_list.add_child(row)

	if unlocked_list.size() > 0:
		_on_unit_selected(unlocked_list[0])


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
	_show_msg("已解锁：%s" % UnitDataManager.get_unit_type_display_name(unit_type))

# ★ 新增：解锁费用表
const UNIT_UNLOCK_COSTS : Dictionary = {
	"archer":     30,
	"pegasus":    50,
	"mage":       60,
	"cleric":     40,
	"dragonborn": 150,
	"armored":    120,
}

func _get_unit_unlock_cost(unit_type: String) -> int:
	return UNIT_UNLOCK_COSTS.get(unit_type, 50)

func _on_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			child.modulate = Color.WHITE if ut == unit_type else Color(0.6, 0.6, 0.6, 1)
	_refresh_all()

# ============================================================
#  Tab 1 · 加点
# ============================================================
func _refresh_all():
	if _current_tab != Tab.ATTR:
		return

	if _current_unit_type == "":
		unit_name_label.text = "（未选择单位）"
		unit_desc_label.text = ""
		unit_sprite.visible = false
		_clear_attr_container()
		point_label.text = "已分配: 0 / %d" % GROWTH_TOTAL_CAP
		_refresh_reset_btn()
		return

	var display = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	unit_name_label.text = display

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
			unit_sprite.position = Vector2(8, 8)
			return
	unit_sprite.visible = false


func _clear_attr_container():
	for child in attr_container.get_children():
		attr_container.remove_child(child)
		child.queue_free()


func _build_attr_row(attr_key: String, current_points: int, at_cap: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label = Label.new()
	name_label.text = ATTR_NAMES[attr_key]
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	name_label.custom_minimum_size = Vector2(50, 0)
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

	# ★ 1:1 —— 所有属性加成 = 点数
	var bonus_val : int = current_points
	var final_val : int = base_val + bonus_val

	var value_label = Label.new()
	value_label.text = "%d  (+%d) → %d" % [base_val, bonus_val, final_val]
	value_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)

	var add_btn = Button.new()
	add_btn.text = "+  (3魂)"
	add_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
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
	_refresh_all()


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
	_refresh_all()


func _get_growth(unit_type: String) -> Dictionary:
	if not GameState.unit_growth.has(unit_type):
		return {}
	return GameState.unit_growth[unit_type]


func _sum_growth(growth: Dictionary) -> int:
	var total = 0
	for k in growth:
		total += int(growth[k])
	return total


func _refresh_soul():
	soul_label.text = "魂: " + str(GameState.soul)


func _refresh_reset_btn():
	if _current_unit_type == "":
		reset_btn.disabled = true
		return
	var growth = _get_growth(_current_unit_type)
	var total = _sum_growth(growth)
	if total <= 0 or GameState.soul < SOUL_RESET_COST:
		reset_btn.disabled = true
	else:
		reset_btn.disabled = false


# ============================================================
#  Tab 2 · 特技
# ============================================================
func _build_talent_tab():
	_clear_attr_container()
	unit_name_label.text = "特技库"
	unit_desc_label.text = "消耗魂解锁特技"
	unit_sprite.visible = false
	point_label.text = "魂：%d" % GameState.soul
	reset_btn.disabled = true

	var all_ids = TalentManager.get_all_talent_ids()
	for talent_id in all_ids:
		var data = TalentManager.get_talent_data(talent_id)
		if not data:
			continue
		attr_container.add_child(_build_talent_row(talent_id, data))


func _build_talent_row(talent_id: String, data) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var unlocked = Globals.is_talent_unlocked(talent_id)
	var story_locked = Globals.is_talent_story_locked(talent_id)
	var soul_cost = Globals.get_talent_soul_cost(talent_id)
	var is_soul_unlockable = (soul_cost > 0)

	# ---- 名称（未解锁也显示真名） ----
	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
	name_label.custom_minimum_size = Vector2(90, 0)
	name_label.text = data.display_name
	if unlocked:
		name_label.add_theme_color_override("font_color", _rarity_color(data.rarity))
	elif story_locked:
		name_label.modulate = Color(0.4, 0.4, 0.4, 1)
	else:
		name_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(name_label)

	# ---- 状态 ----
	var status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	status_label.custom_minimum_size = Vector2(80, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if unlocked:
		status_label.text = "已解锁"
		status_label.modulate = Color(0.5, 0.5, 0.5, 1)
	elif story_locked:
		status_label.text = "剧情获取"
		status_label.modulate = Color(0.7, 0.7, 0.5, 1)
	elif is_soul_unlockable:
		status_label.text = "%d 魂" % soul_cost
		status_label.modulate = Color.WHITE if GameState.soul >= soul_cost else Color(1.0, 0.4, 0.4, 1)
	else:
		status_label.text = "—"
	row.add_child(status_label)

	# ---- 描述（全部显示真描述） ----
	var desc_label = Label.new()
	desc_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	desc_label.modulate = Color(0.7, 0.7, 0.7, 1)
	desc_label.text = data.description
	row.add_child(desc_label)

	# ---- 按钮 ----
	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(60, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if unlocked:
		btn.text = "已解锁"
		btn.disabled = true
	elif story_locked:
		btn.text = "剧情获取"
		btn.disabled = true
	elif is_soul_unlockable:
		btn.text = "解锁"
		btn.disabled = not Globals.can_soul_unlock_talent(talent_id)
		btn.pressed.connect(_on_unlock_talent.bind(talent_id))
	else:
		btn.text = "—"
		btn.disabled = true
	row.add_child(btn)

	return row


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"rare":      return Color(0.3, 0.6, 1.0, 1)
		"epic":      return Color(0.7, 0.3, 1.0, 1)
		"legendary": return Color(1.0, 0.7, 0.0, 1)
		_:           return Color.WHITE


func _on_unlock_talent(talent_id: String):
	if Globals.soul_unlock_talent(talent_id):
		_refresh_soul()
		_switch_tab(Tab.TALENT)


# ============================================================
#  辅助
# ============================================================
func _show_msg(msg: String):
	var original = point_label.text
	point_label.text = msg
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(point_label):
		point_label.text = original
