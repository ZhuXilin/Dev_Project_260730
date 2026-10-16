extends CanvasLayer

# ============================================================
#  TalentUnlockUI — 竞技场通关词条选择面板（v4.1）
#  弹出即模态，玩家必须选中一项才能关闭。
#  按 school 分 tab，只显示未解锁的词条。
# ============================================================

signal closed

const SCHOOLS : Array = ["敏捷", "力量", "智力", "信仰", "感应"]

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/Title
@onready var hint_label : Label = $Panel/VBox/Hint
@onready var tab_bar : HBoxContainer = $Panel/VBox/TabBar
@onready var talent_scroll : ScrollContainer = $Panel/VBox/TalentScroll
@onready var talent_list : VBoxContainer = $Panel/VBox/TalentScroll/TalentList

var _current_school : String = ""
var _tab_buttons : Dictionary = {}


func _ready():
	layer = 28
	if title_label: title_label.text = "选择词条"
	if hint_label: hint_label.text = "解锁一项词条（永久生效）"
	_build_tabs()
	_switch_school(SCHOOLS[0])


# ============================================================
#  Tab 栏
# ============================================================
func _build_tabs():
	for child in tab_bar.get_children():
		tab_bar.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()

	for s in SCHOOLS:
		var btn := Button.new()
		btn.text = s
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_switch_school.bind(s))
		tab_bar.add_child(btn)
		_tab_buttons[s] = btn


func _switch_school(school : String):
	_current_school = school
	for s in _tab_buttons:
		var btn : Button = _tab_buttons[s]
		btn.button_pressed = (s == school)
		btn.modulate = Color.WHITE if s == school else Color(0.55, 0.55, 0.55, 1)
	_refresh_list()


# ============================================================
#  列表
# ============================================================
func _refresh_list():
	for child in talent_list.get_children():
		talent_list.remove_child(child)
		child.queue_free()

	var candidates : Array = _get_candidates(_current_school)
	if candidates.is_empty():
		var lb := Label.new()
		lb.text = "（%s 系已全部解锁）" % _current_school
		lb.add_theme_font_size_override("font_size", 8)
		lb.modulate = Color(0.6, 0.6, 0.6, 1)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		talent_list.add_child(lb)
		return

	for tid in candidates:
		talent_list.add_child(_make_talent_card(tid))


func _get_candidates(school : String) -> Array:
	var result : Array = []
	var school_lower : String = school.to_lower()
	for tid in TalentManager.get_all_talent_ids():
		if tid in Globals.unlocked_talents:
			continue
		var data = TalentManager.get_talent_data(tid)
		if data == null: continue
		if data.school.to_lower() != school_lower: continue
		result.append(tid)
	return result


func _make_talent_card(tid : String) -> Control:
	var data = TalentManager.get_talent_data(tid)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 40)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_font_size_override("font_size", 7)
	card.focus_mode = Control.FOCUS_NONE
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var rarity_cn : String = _rarity_cn(data.rarity)
	var active_tag : String = ""
	if data.is_active_skill:
		active_tag = "  [主动]"
	card.text = "%s  [%s]%s\n%s" % [data.display_name, rarity_cn, active_tag, data.description]

	var color : Color = UIConst.QUALITY_COLORS.get(data.rarity, Color.WHITE)
	card.add_theme_color_override("font_color", color)

	card.pressed.connect(_on_talent_selected.bind(tid))
	return card


func _rarity_cn(r : String) -> String:
	match r:
		"common":    return "普通"
		"rare":      return "稀有"
		"epic":      return "史诗"
		"legendary": return "传说"
	return r


# ============================================================
#  选择
# ============================================================
func _on_talent_selected(tid : String):
	if tid in Globals.unlocked_talents:
		return
	Globals.unlock_talent(tid)
	SaveManager.auto_save()
	# ★ v4.1：数据埋点 — 竞技场词条解锁
	AnalyticsLogger.record_talent_unlock()

	var data = TalentManager.get_talent_data(tid)
	var name : String = data.display_name if data else tid
	print("[竞技场] 解锁词条：%s" % name)

	SoundManager.play_get_item_sound()
	closed.emit()
	queue_free()
