extends CanvasLayer

signal closed

enum Tab { SOUL_FIRE, ATTR_CAP }

const ATTR_CAP_LEVELS : Array[int] = [0, 2, 5, 8, 12, 16, 20, 25]
const ATTR_CAP_COSTS  : Array[int] = [20, 30, 45, 65, 90, 120, 160, 200]

var _current_tab : Tab = Tab.SOUL_FIRE
var _current_unit_type : String = ""

@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var soul_fire_tab_btn : Button = $Panel/VBox/TabBar/SoulFireTabBtn
@onready var attr_cap_tab_btn : Button = $Panel/VBox/TabBar/AttrCapTabBtn
@onready var left_title : Label = $Panel/VBox/MainHBox/LeftColumn/LeftTitle
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/LeftColumn/UnitListScroll/UnitList
@onready var unit_sprite : AnimatedSprite2D = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/SpriteContainer/UnitSprite
@onready var unit_name_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitNameLabel
@onready var unit_desc_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitDescLabel
@onready var attr_container : VBoxContainer = $Panel/VBox/MainHBox/InfoPanel/AttrScroll/AttrContainer
@onready var hint_label : Label = $Panel/VBox/MainHBox/InfoPanel/BottomBar/HintLabel


func _ready():
	MusicManager.play_soul_altar_music()
	if soul_fire_tab_btn:
		soul_fire_tab_btn.text = "魂火"
	if attr_cap_tab_btn:
		attr_cap_tab_btn.text = "属性上限"
	if hint_label:
		hint_label.visible = false

	if soul_fire_tab_btn and not soul_fire_tab_btn.pressed.is_connected(_on_soul_fire_tab_pressed):
		soul_fire_tab_btn.pressed.connect(_on_soul_fire_tab_pressed)
	if attr_cap_tab_btn and not attr_cap_tab_btn.pressed.is_connected(_on_attr_cap_tab_pressed):
		attr_cap_tab_btn.pressed.connect(_on_attr_cap_tab_pressed)

	_refresh_soul()
	_switch_tab(Tab.SOUL_FIRE)


func _on_soul_fire_tab_pressed(): _switch_tab(Tab.SOUL_FIRE)
func _on_attr_cap_tab_pressed(): _switch_tab(Tab.ATTR_CAP)


func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()


func _switch_tab(tab: Tab):
	_current_tab = tab
	soul_fire_tab_btn.modulate = Color.WHITE if tab == Tab.SOUL_FIRE else Color(0.5, 0.5, 0.5, 1)
	attr_cap_tab_btn.modulate = Color.WHITE if tab == Tab.ATTR_CAP else Color(0.5, 0.5, 0.5, 1)

	if tab == Tab.SOUL_FIRE:
		left_title.text = "— 魂火 —"
		_clear_unit_list()
		_refresh_soul_fire_panel()
	else:
		left_title.text = "— 单位 —"
		_build_unit_list()
		_refresh_attr_cap_panel()


func _clear_unit_list():
	for c in unit_list.get_children():
		unit_list.remove_child(c); c.queue_free()


# ============================================================
#  Tab 1 · 魂火
# ============================================================
func _refresh_soul_fire_panel():
	_clear_attr_container()
	unit_sprite.visible = false
	unit_name_label.text = "魂火祭坛"
	unit_desc_label.text = ""

	var lv : int = SoulFireManager.altar_level
	var max_lv : int = SoulFireManager.MAX_CARRIED_LEVELS.size() - 1
	var cur_max : int = SoulFireManager.get_max_carried()
	var next_max : int = SoulFireManager.MAX_CARRIED_LEVELS[mini(lv + 1, max_lv)]
	var cost : int = SoulFireManager.get_upgrade_cost()

	attr_container.add_child(_make_title("— 携带上限 —"))
	attr_container.add_child(_make_info("当前等级：Lv %d / %d" % [lv, max_lv]))
	attr_container.add_child(_make_info("当前上限：%d 魂火" % cur_max))
	if cost >= 0:
		attr_container.add_child(_make_info("下一级上限：%d 魂火" % next_max))
		attr_container.add_child(_make_upgrade_row("升级上限", cost,
			func(): _on_upgrade_soul_fire_max()))
	else:
		attr_container.add_child(_make_info("已达最高等级"))

	attr_container.add_child(HSeparator.new())

	var init_lv : int = GameState.soul_fire_initial_level
	var init_max : int = SoulFireManager.INITIAL_LEVELS.size() - 1
	var cur_init : int = SoulFireManager.get_initial_soul_fire()
	var init_cost : int = SoulFireManager.get_initial_upgrade_cost()

	attr_container.add_child(_make_title("— 初始魂火 —"))
	attr_container.add_child(_make_info("当前等级：Lv %d / %d" % [init_lv, init_max]))
	attr_container.add_child(_make_info("每局开始携带：%d 魂火" % cur_init))
	if init_cost >= 0:
		var next_init : int = SoulFireManager.INITIAL_LEVELS[init_lv + 1]
		attr_container.add_child(_make_info("下一级：%d 魂火" % next_init))
		attr_container.add_child(_make_upgrade_row("升级初始", init_cost,
			func(): _on_upgrade_soul_fire_initial()))
	else:
		attr_container.add_child(_make_info("已达最高等级"))


func _on_upgrade_soul_fire_max():
	if SoulFireManager.upgrade_altar():
		_refresh_soul()
		_refresh_soul_fire_panel()
		_show_msg("魂火上限已提升")


func _on_upgrade_soul_fire_initial():
	if SoulFireManager.upgrade_initial():
		_refresh_soul()
		_refresh_soul_fire_panel()
		_show_msg("初始魂火已提升")


# ============================================================
#  Tab 2 · 属性上限
# ============================================================
func _build_unit_list():
	for c in unit_list.get_children():
		unit_list.remove_child(c); c.queue_free()

	var all_units = UnitDataManager.get_all_unit_ids()
	for unit_type in all_units:
		if not Globals.is_unit_unlocked(unit_type): continue
		var btn = Button.new()
		var type_display = UnitDataManager.get_unit_type_display_name(unit_type)
		var cap_lv = int(GameState.unit_attr_cap.get(unit_type, 0))
		btn.text = "%s  [上限 Lv%d]" % [type_display, cap_lv]
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE if unit_type == _current_unit_type else Color(0.7, 0.7, 0.7, 1)
		btn.pressed.connect(_on_unit_selected.bind(unit_type))
		unit_list.add_child(btn)

	if _current_unit_type == "" and Globals.get_unlocked_units().size() > 0:
		_current_unit_type = Globals.get_unlocked_units()[0]


func _on_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			if ut != "":
				child.modulate = Color.WHITE if ut == unit_type else Color(0.7, 0.7, 0.7, 1)
	_refresh_attr_cap_panel()


func _refresh_attr_cap_panel():
	_clear_attr_container()
	if _current_unit_type == "":
		unit_name_label.text = "（未选择）"
		unit_desc_label.text = ""
		unit_sprite.visible = false
		return

	var display = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	var cap_lv = int(GameState.unit_attr_cap.get(_current_unit_type, 0))
	var max_lv = ATTR_CAP_LEVELS.size() - 1
	var cur_cap = ATTR_CAP_LEVELS[clampi(cap_lv, 0, max_lv)]
	var next_cap = ATTR_CAP_LEVELS[mini(cap_lv + 1, max_lv)]

	unit_name_label.text = "%s   上限 Lv %d / %d" % [display, cap_lv, max_lv]
	unit_sprite.visible = true
	_load_unit_sprite(_current_unit_type)

	attr_container.add_child(_make_info("当前属性点上限：%d" % cur_cap))
	if cap_lv < max_lv:
		attr_container.add_child(_make_info("下一级上限：%d" % next_cap))
		var cost = ATTR_CAP_COSTS[cap_lv] if cap_lv < ATTR_CAP_COSTS.size() else -1
		if cost > 0:
			attr_container.add_child(_make_upgrade_row("提升上限", cost,
				func(): _on_upgrade_attr_cap()))
	else:
		attr_container.add_child(_make_info("已达最高等级"))

	attr_container.add_child(HSeparator.new())
	var note = Label.new()
	note.text = "属性点实际分配在局内熔炉节点，消耗魂火。"
	note.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.6, 0.6, 0.6, 1)
	attr_container.add_child(note)


func _on_upgrade_attr_cap():
	if _current_unit_type == "": return
	var cap_lv = int(GameState.unit_attr_cap.get(_current_unit_type, 0))
	if cap_lv >= ATTR_CAP_LEVELS.size() - 1: return
	var cost = ATTR_CAP_COSTS[cap_lv] if cap_lv < ATTR_CAP_COSTS.size() else -1
	if cost <= 0 or GameState.soul < cost: return
	GameState.soul -= cost
	GameState.unit_attr_cap[_current_unit_type] = cap_lv + 1
	SaveManager.auto_save()
	_refresh_soul()
	_build_unit_list()
	_refresh_attr_cap_panel()
	_show_msg("上限已提升")


# ============================================================
#  辅助
# ============================================================
func _make_title(text: String) -> Label:
	var lb = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.modulate = Color(0.7, 0.8, 1.0)
	return lb


func _make_info(text: String) -> Label:
	var lb = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return lb


func _make_upgrade_row(label_text: String, cost: int, cb: Callable) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lb = Label.new()
	lb.text = "%s：%d 魂" % [label_text, cost]
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lb)

	var btn = Button.new()
	btn.text = "升级"
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(50, 0)
	btn.disabled = (GameState.soul < cost)
	btn.pressed.connect(cb)
	row.add_child(btn)
	return row


func _refresh_soul():
	soul_label.text = "魂: " + str(GameState.soul)


func _clear_attr_container():
	for c in attr_container.get_children():
		attr_container.remove_child(c); c.queue_free()


func _load_unit_sprite(unit_type: String):
	var path = UnitDataManager.get_sprite_frames_path(unit_type)
	if path != "" and ResourceLoader.exists(path):
		var frames = load(path) as SpriteFrames
		if frames:
			unit_sprite.sprite_frames = frames
			if frames.has_animation("idle"):
				unit_sprite.play("idle")
			unit_sprite.visible = true
			unit_sprite.position = Vector2(13, 8)
			return
	unit_sprite.visible = false


func _show_msg(msg: String):
	if not hint_label: return
	hint_label.visible = true
	hint_label.text = msg
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(hint_label):
		hint_label.visible = false
		hint_label.text = ""
