extends CanvasLayer
const BuildUI = preload("res://function/script/build/BuildUI.gd")
## ============================================================
##  BuildViewer — v6 只读 Build 查看器（替代地图装备界面）
## ============================================================
##  玩家只能查看，不能调整装备 / 词条 / 方向 / 单位位置 / 升级。
##  信息按 单位 → 流派机制 → 装备贡献 分层展示。
## ============================================================

signal closed

const FS_TITLE: int = 10
const FS_BODY: int = 7
const FS_SMALL: int = 6

var _root: Panel = null
var _columns: HBoxContainer = null

var _gold_color := Color(0.98, 0.75, 0.25)
var _dim_color := Color(0.55, 0.55, 0.58)
var _bg_color := Color(0.07, 0.07, 0.09, 1.0)
var _panel_color := Color(0.13, 0.13, 0.17, 1.0)


func _ready() -> void:
	layer = 20
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_root = Panel.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.set("theme_override_styles/panel", _make_style(_bg_color))
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Build 总览 · 只读"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", _gold_color)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "流派机制由防具觉醒 / 并入形成，同流派不占额外槽位"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", FS_SMALL)
	hint.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(hint)

	_columns = HBoxContainer.new()
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 4)
	vbox.add_child(_columns)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0, 14)
	close.add_theme_font_size_override("font_size", FS_BODY)
	BuildUI.style_button(close, _gold_color)
	close.pressed.connect(_on_close)
	vbox.add_child(close)


func _refresh() -> void:
	if _columns == null:
		return
	for c in _columns.get_children():
		c.queue_free()

	for ud in GameState.party:
		if ud == null:
			continue
		_columns.add_child(_make_unit_card(ud))


func _make_unit_card(ud: UnitData) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_style(_panel_color))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)

	# 单位名 + 流派槽数
	var head := Label.new()
	var slots := ud.max_armor_slots   # ★ v6.51：当前槽上限（随天数+1）
	var used := BuildManager.get_used_mechanism_slots(ud)
	head.text = "%s   流派槽 %d/%d" % [ud.display_name, used, slots]
	head.add_theme_font_size_override("font_size", FS_BODY)
	head.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(head)

	var line := HSeparator.new()
	vb.add_child(line)

	# 流派机制（分层核心）
	var mechs: Array = BuildManager.get_unit_mechanisms(ud)
	if mechs.is_empty():
		var empty := Label.new()
		empty.text = "（尚未觉醒流派机制）"
		empty.add_theme_font_size_override("font_size", FS_SMALL)
		empty.add_theme_color_override("font_color", _dim_color)
		vb.add_child(empty)
	else:
		for m in mechs:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 3)
			var dot := ColorRect.new()
			dot.color = m["color"]
			dot.custom_minimum_size = Vector2(6, 6)
			row.add_child(dot)
			var ml := Label.new()
			ml.text = BuildManager.get_effective_mechanic_text(ud, str(m["school"]))
			ml.add_theme_font_size_override("font_size", FS_BODY)
			ml.add_theme_color_override("font_color", m["color"])
			row.add_child(ml)
			vb.add_child(row)
			var desc := Label.new()
			desc.text = "  " + str(m["mechanic"])
			desc.add_theme_font_size_override("font_size", FS_SMALL)
			desc.add_theme_color_override("font_color", _dim_color)
			vb.add_child(desc)

	vb.add_child(HSeparator.new())

	# 技能格 2：第 1 格 roll / 第 2 格转职，均只读
	var skill_title := Label.new()
	skill_title.text = "技能词条（锁定）"
	skill_title.add_theme_font_size_override("font_size", FS_SMALL)
	skill_title.add_theme_color_override("font_color", _gold_color)
	vb.add_child(skill_title)
	vb.add_child(_make_skill_label(ud, 0, "roll"))
	vb.add_child(_make_skill_label(ud, 1, "转职"))

	# 遗物 / 转职被动
	var adv := Label.new()
	adv.text = "转职：%s" % (ud.advanced_class if ud.advanced_class != "" else "无")
	adv.add_theme_font_size_override("font_size", FS_SMALL)
	adv.add_theme_color_override("font_color", _dim_color)
	vb.add_child(adv)

	return card


func _make_skill_label(ud: UnitData, slot: int, source: String) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", FS_SMALL)
	var inst = ud.talent_slots[slot] if slot < ud.talent_slots.size() else null
	if slot == 1:
		inst = ud.advanced_talent_inst
	if inst != null:
		var tdata := TalentManager.get_talent_data(inst.talent_id)
		var nm: String = ""
		if tdata != null:
			nm = str(tdata.display_name)
		else:
			nm = str(inst.talent_id)
		lbl.text = "  %d · %s (%s)" % [slot + 1, nm, source]
		lbl.add_theme_color_override("font_color", Color.WHITE)
	else:
		lbl.text = "  %d · —— (%s)" % [slot + 1, source]
		lbl.add_theme_color_override("font_color", _dim_color)
	return lbl


func _make_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	return sb


func _on_close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_close()
