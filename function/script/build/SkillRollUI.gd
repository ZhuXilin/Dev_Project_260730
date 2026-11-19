extends CanvasLayer
const BuildUI = preload("res://function/script/build/BuildUI.gd")
## ============================================================
##  SkillRollUI — v6 开局主动技能 roll（老虎机式落位）
## ============================================================
##  选完 3 单位后：
##   - roll 池 = 已选单位 compatible_units 并集
##   - roll 3 次，每次出 1 张技能卡
##   - 玩家点单位落位（不兼容 / 技能格已满者灰显）
##   - 3 次结束进入地图；技能锁定、不可重掷、不可互换
## ============================================================

signal finished

const FS_TITLE: int = 10
const FS_BODY: int = 7
const FS_SMALL: int = 6

var _unit_names: Array = []
var _skills: Array = []
var _index: int = 0
var _gold_color := Color(0.98, 0.75, 0.25)
var _dim_color := Color(0.5, 0.5, 0.53)

var _title: Label = null
var _progress: Label = null
var _card: PanelContainer = null
var _card_text: Label = null
var _unit_box: VBoxContainer = null
var _skip_btn: Button = null


func setup(unit_names: Array) -> void:
	_unit_names = unit_names.duplicate()
	_skills = BuildManager.roll_active_skills(_unit_names, 3)
	_index = 0
	_build_ui()
	_show_step()


func _ready() -> void:
	layer = 30


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := Panel.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	_title = Label.new()
	_title.text = "开局技能抉择"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", FS_TITLE)
	_title.add_theme_color_override("font_color", _gold_color)
	vbox.add_child(_title)

	_progress = Label.new()
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.add_theme_font_size_override("font_size", FS_SMALL)
	_progress.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(_progress)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(0, 34)
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.16, 0.22)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.5, 0.42, 0.2)
	_card.add_theme_stylebox_override("panel", sb)
	_card_text = Label.new()
	_card_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_text.add_theme_font_size_override("font_size", FS_BODY)
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_card_text)
	vbox.add_child(_card)

	var pick := Label.new()
	pick.text = "选择落位单位（选定离手，不可撤销）"
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick.add_theme_font_size_override("font_size", FS_SMALL)
	pick.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(pick)

	_unit_box = VBoxContainer.new()
	_unit_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unit_box.add_theme_constant_override("separation", 3)
	vbox.add_child(_unit_box)

	_skip_btn = Button.new()
	_skip_btn.text = "放弃这张"
	_skip_btn.add_theme_font_size_override("font_size", FS_SMALL)
	BuildUI.style_button(_skip_btn)
	_skip_btn.pressed.connect(_on_skip)
	vbox.add_child(_skip_btn)


func _show_step() -> void:
	_progress.text = "第 %d / %d 次" % [mini(_index + 1, _skills.size()), maxi(_skills.size(), 1)]
	if _index >= _skills.size():
		_finish()
		return

	var tid := str(_skills[_index])
	var data := TalentManager.get_talent_data(tid)
	var name := data.display_name if data else tid
	var desc := data.description if data else ""
	var cost := 0
	if data:
		cost = int(data.effect_params.get("soul_fire_cost", data.soul_cost))
	_card_text.text = "【%s】\n%s\n消耗 %d 魂火" % [name, desc, cost]

	for c in _unit_box.get_children():
		c.queue_free()
	# 剩余单位（尚未占用第 1 技能格）与剩余技能（含当前这张）
	var remaining_units: Array = []
	for uname in _unit_names:
		var u: UnitData = _find_unit(str(uname))
		if u != null and (u.talent_slots.is_empty() or u.talent_slots[0] == null):
			remaining_units.append(str(uname))
	var remaining_skills: Array = _skills.slice(_index)

	var any_ok := false
	for uname in _unit_names:
		var ud: UnitData = _find_unit(str(uname))
		if ud == null:
			continue
		var btn := Button.new()
		var adv := str(ud.advanced_class)
		var compatible := TalentManager.is_talent_compatible_with_unit(tid, ud.unit_name, adv)
		var slot_empty := ud.talent_slots.is_empty() or ud.talent_slots[0] == null
		# ★ 关键：落位后必须保证剩余单位仍有技能可装，杜绝"选错单位→后续单位无技能"
		var safe := slot_empty and compatible and BuildManager.is_safe_placement(ud, tid, remaining_units, remaining_skills)
		if safe:
			btn.text = "%s  ← 落位" % ud.display_name
			btn.disabled = false
			btn.pressed.connect(_on_pick.bind(ud, tid))
			any_ok = true
		else:
			var why := "技能格已满"
			if not compatible:
				why = "不可装备此技能"
			elif slot_empty and not remaining_units.is_empty():
				why = "会导致其他单位无技能"
			btn.text = "%s  (%s)" % [ud.display_name, why]
			btn.disabled = true
		btn.add_theme_font_size_override("font_size", FS_BODY)
		BuildUI.style_button(btn, _gold_color if safe else Color(0.3, 0.3, 0.34, 1.0))
		_unit_box.add_child(btn)

	# 匹配算法保证一定存在可行落位；此按钮仅作极端兜底（如数据在运行时被改坏）
	_skip_btn.visible = not any_ok
	_skip_btn.text = "无人可落位 · 跳过"


func _find_unit(unit_name: String) -> UnitData:
	for ud in GameState.party:
		if ud != null and ud.unit_name == unit_name:
			return ud
	return null


func _on_pick(ud: UnitData, tid: String) -> void:
	BuildManager.place_skill(ud, tid)
	_next()


func _on_skip() -> void:
	_next()


func _next() -> void:
	_index += 1
	_show_step()


func _finish() -> void:
	SaveManager.auto_save()
	finished.emit()
	queue_free()
