extends CanvasLayer
const BuildUI = preload("res://function/script/build/BuildUI.gd")
const SlotMachineUI = preload("res://function/script/build/SlotMachineUI.gd")
## ============================================================
##  ArmorRollUI — v6 战后防具 roll + 领取台
## ============================================================
##  战后结算确认后弹出：
##   - 花金币 roll 防具（100G 起，每次 +50G，离开界面重置）
##   - 可花金币升级 roll 品质等级
##   - 领取台：装备 / 并入 / 重铸流派 / 覆盖 / 放弃
##   - 满流派槽时必须覆盖或放弃；覆盖二次确认
##  战斗不再直接送防具，所有防具都从这里获取。
## ============================================================

signal closed

const FS_TITLE: int = 10
const FS_BODY: int = 7
const FS_SMALL: int = 6

var _gold_color := Color(0.98, 0.75, 0.25)
var _dim_color := Color(0.55, 0.55, 0.58)

var _roll_count: int = 0
var _quality_level: int = 0
var _current: Dictionary = {}          # 当前待领取防具 {item_id,quality,school,name,mechanic}
var _reforge_school: String = ""       # 重铸后的流派（空=用原流派）

var _root: Panel = null
var _gold_label: Label = null
var _quality_label: Label = null
var _machine = null
var _cost_label: Label = null
var _upgrade_btn: Button = null
var _result_box: VBoxContainer = null
var _msg: Label = null
var _closing: bool = false   # ★ 防两个关闭按钮同帧重复触发

# ★ Arena 统一：注入单单位 + 独立金币（主线不调用则完全走 GameState/EconomyManager）
var _arena_mode: bool = false
var _unit_override: Array = []
var _get_gold_cb: Callable = Callable()
var _set_gold_cb: Callable = Callable()


## Arena 模式：用竞技场单单位与独立金币，界面与主线完全共用。
## 必须在 add_child 之前调用（_ready 会 _build_ui/_refresh）。
func setup_for_arena(unit: UnitData, get_gold: Callable, set_gold: Callable) -> void:
	_arena_mode = true
	_unit_override = [unit] if unit != null else []
	_get_gold_cb = get_gold
	_set_gold_cb = set_gold


func _gold() -> int:
	if _arena_mode and _get_gold_cb.is_valid():
		return maxi(0, int(_get_gold_cb.call()))
	return EconomyManager.get_temp_gold()


func _spend(amount: int) -> void:
	if _arena_mode and _set_gold_cb.is_valid():
		_set_gold_cb.call(maxi(0, _gold() - amount))
	else:
		EconomyManager.subtract_temp_gold(amount)


func _get_units() -> Array:
	if _arena_mode:
		return _unit_override
	return GameState.party


func _ready() -> void:
	layer = 30
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_root = Panel.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var root_sb := StyleBoxFlat.new()
	root_sb.bg_color = Color(0.06, 0.06, 0.09, 0.98)
	root_sb.set_border_width_all(0)
	root_sb.content_margin_left = 2.0
	root_sb.content_margin_right = 2.0
	_root.add_theme_stylebox_override("panel", root_sb)
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "竞技场 · 防具抽取" if _arena_mode else "战后 · 防具抽取"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", _gold_color)
	vbox.add_child(title)

	_gold_label = Label.new()
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", FS_BODY)
	vbox.add_child(_gold_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_cost_label = Label.new()
	_cost_label.add_theme_font_size_override("font_size", FS_SMALL)
	_cost_label.add_theme_color_override("font_color", _gold_color)
	btn_row.add_child(_cost_label)

	_machine = SlotMachineUI.new()
	_machine.custom_minimum_size = Vector2(0, 96)
	vbox.add_child(_machine)
	_machine.stopped.connect(_on_machine_stopped)
	_machine.started.connect(_on_spin_started)

	_upgrade_btn = Button.new()
	_upgrade_btn.add_theme_font_size_override("font_size", FS_BODY)
	BuildUI.style_button(_upgrade_btn)
	_upgrade_btn.pressed.connect(_on_upgrade_quality)
	btn_row.add_child(_upgrade_btn)

	# ★ 顶部常驻返回键：金币不足、无法继续 roll 时也能退出
	var back := Button.new()
	back.text = "离开竞技场" if _arena_mode else "返回地图"
	back.add_theme_font_size_override("font_size", FS_SMALL)
	BuildUI.style_button(back, _gold_color)
	back.pressed.connect(_on_close)
	btn_row.add_child(back)

	_quality_label = Label.new()
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quality_label.add_theme_font_size_override("font_size", FS_SMALL)
	_quality_label.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(_quality_label)

	_msg = Label.new()
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", FS_SMALL)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_msg)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 130)
	vbox.add_child(scroll)
	_result_box = VBoxContainer.new()
	_result_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_box.add_theme_constant_override("separation", 1)
	scroll.add_child(_result_box)

	var close := Button.new()
	close.text = "结束抽取 · 离开竞技场" if _arena_mode else "结束抽取 · 返回地图"
	close.add_theme_font_size_override("font_size", FS_BODY)
	BuildUI.style_button(close)
	close.pressed.connect(_on_close)
	vbox.add_child(close)


func _refresh() -> void:
	var gold := _gold()
	_gold_label.text = "金币：%d" % gold
	var cost := BuildManager.get_roll_cost(_roll_count)
	_cost_label.text = "本次抽取 %dG" % cost
	_machine.set_start_enabled(gold >= cost)
	if gold < cost and _msg.text == "":
		_msg.text = "金币不足，可点右上角按钮结束抽取"
	var up := BuildManager.get_upgrade_cost(_quality_level)
	if up < 0:
		_upgrade_btn.text = "品质已满"
		_upgrade_btn.disabled = true
	else:
		_upgrade_btn.text = "升级品质（%dG）" % up
		_upgrade_btn.disabled = gold < up
	_quality_label.text = "当前品质等级 %d/5：%s" % [_quality_level, _quality_desc()]

	_render_result()
	if _current.is_empty():
		_prepare_spin()


func _prepare_spin() -> void:
	if _machine == null or _machine.is_spinning():
		return
	_machine.setup(BuildManager.get_armor_roll_pool(_quality_level, 8),
		"防具轮盘 · 下一次（%dG）" % BuildManager.get_roll_cost(_roll_count))


func _quality_desc() -> String:
	match _quality_level:
		0: return "common 为主"
		1: return "rare 概率提升"
		2: return "epic 概率提升"
		3: return "legendary 出现"
		4: return "高品几率大幅提升"
		_: return "legendary 高概率"


func _on_upgrade_quality() -> void:
	var up := BuildManager.get_upgrade_cost(_quality_level)
	if up < 0:
		return
	if _gold() < up:
		_msg.text = "金币不足"
		return
	_spend(up)
	_quality_level += 1
	_msg.text = "品质等级提升至 %d" % _quality_level
	_refresh()


func _on_spin_started() -> void:
	var cost := BuildManager.get_roll_cost(_roll_count)
	if _gold() < cost:
		_msg.text = "金币不足"
		_machine.request_stop()
		return
	_spend(cost)
	_roll_count += 1
	_current = {}
	_reforge_school = ""
	_msg.text = "点「停！」选择这次抽到的防具"
	_refresh()


func _on_machine_stopped(entry: Dictionary) -> void:
	var iid := str(entry.get("item_id", ""))
	if iid == "":
		_msg.text = "抽取失败（防具池为空）"
		return
	_current = {
		"item_id": iid,
		"quality": str(entry.get("quality", "common")),
		"school": str(entry.get("school", "")),
		"name": str(entry.get("name", iid)),
		"mechanic": str(entry.get("mechanic", "")),
	}
	_reforge_school = ""
	_msg.text = "抽到：%s（%s）" % [_current.get("name", ""), _current.get("quality", "")]
	_refresh()


func _render_result() -> void:
	if _result_box == null:
		return
	for c in _result_box.get_children():
		c.queue_free()
	if _current.is_empty():
		return

	var school := _effective_school()
	var quality := str(_current.get("quality", "common"))
	var cap := BuildManager.get_quality_cap(quality)
	var line := Label.new()
	line.text = "【%s】品质 %s · 流派 %s（机制 Lv 上限 %d）" % [
		_current.get("name", ""), quality, school if school != "" else "无", cap]
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", FS_BODY)
	line.add_theme_color_override("font_color", BuildManager.get_school_color(school))
	_result_box.add_child(line)
	var mech := Label.new()
	mech.text = "机制：%s" % (BuildManager.get_school_mechanic(school) if school != "" else "无流派 · 仅属性")
	mech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mech.add_theme_font_size_override("font_size", FS_SMALL)
	mech.add_theme_color_override("font_color", _dim_color)
	_result_box.add_child(mech)

	# 落位动作：三个单位头像横排，与技能 roll 界面一致
	var actions := Label.new()
	actions.text = "选择落位单位（点击头像决定给谁）："
	actions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions.add_theme_font_size_override("font_size", FS_SMALL)
	_result_box.add_child(actions)

	var unit_row := HBoxContainer.new()
	unit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	unit_row.add_theme_constant_override("separation", 8)
	_result_box.add_child(unit_row)

	var school_color := BuildManager.get_school_color(school)
	for ud in _get_units():
		if ud == null:
			continue
		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.add_theme_constant_override("separation", 1)
		card.custom_minimum_size = Vector2(96, 0)
		var avatar := UnitDataManager.create_unit_avatar_button(
			ud.unit_name, Vector2(46, 46), Vector2(40, 40))
		avatar.disabled = ud.is_dead
		avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if ud.is_dead:
			avatar.modulate = Color(0.35, 0.35, 0.38)
		else:
			avatar.pressed.connect(_on_place.bind(ud))
		card.add_child(avatar)
		var name_lbl := Label.new()
		# ★ v6.15：单位名 + Lv + 已有防具数/槽位数 + 现有防具对应流派
		var armor_used: int = ud.count_used_armor_slots()
		var armor_slots: int = ud.max_armor_slots
		var mechs := BuildManager.get_unit_mechanisms(ud)
		var school_parts := PackedStringArray()
		for m in mechs:
			school_parts.append("%s%d" % [str(m.get("school", "")), int(m.get("level", 1))])
		var school_txt: String = " ".join(school_parts) if not school_parts.is_empty() else "无流派"
		name_lbl.text = "%s Lv%d\n防具 %d/%d\n%s" % [
			ud.display_name, int(ud.level), armor_used, armor_slots, school_txt]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.custom_minimum_size = Vector2(96, 30)
		name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		name_lbl.clip_text = false
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.add_theme_font_size_override("font_size", FS_SMALL)
		name_lbl.add_theme_color_override("font_color", _dim_color if ud.is_dead else school_color)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_lbl)
		unit_row.add_child(card)

	# 重铸 / 放弃
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var reforge := Button.new()
	reforge.text = "重铸流派（%dG）" % BuildManager.get_reforge_cost()
	reforge.add_theme_font_size_override("font_size", FS_SMALL)
	BuildUI.style_button(reforge)
	reforge.pressed.connect(_on_reforge)
	if school == "":
		reforge.disabled = true
	row.add_child(reforge)
	var discard := Button.new()
	discard.text = "放弃"
	discard.add_theme_font_size_override("font_size", FS_SMALL)
	BuildUI.style_button(discard)
	discard.pressed.connect(_on_discard)
	row.add_child(discard)
	_result_box.add_child(row)


func _effective_school() -> String:
	if _reforge_school != "":
		return _reforge_school
	return str(_current.get("school", ""))


func _on_reforge() -> void:
	var cost := BuildManager.get_reforge_cost()
	if _gold() < cost:
		_msg.text = "金币不足，无法重铸"
		return
	_spend(cost)
	_reforge_school = BuildManager.reforge_school(_effective_school())
	_msg.text = "重铸为流派：%s" % _reforge_school
	_render_result()


func _on_discard() -> void:
	_current = {}
	_reforge_school = ""
	_msg.text = "已放弃该防具"
	_render_result()


func _on_place(ud: UnitData) -> void:
	var item_id := str(_current.get("item_id", ""))
	var quality := str(_current.get("quality", "common"))
	# ★ v6.8：同流派并入升 Lv 收 200G（文档 6.2 / 5.5）。
	#   在 apply_armor 之前预判是否 merge 并扣费，避免合并已执行却扣不起。
	var school: String = _reforge_school if _reforge_school != "" else BuildManager.get_school_of_item(item_id)
	var will_merge: bool = school != "" and BuildManager.has_school(ud, school)
	if will_merge:
		var merge_cost := BuildManager.get_merge_cost_instance()
		if _gold() < merge_cost:
			_msg.text = "金币不足，并入 %s 需 %dG" % [school, merge_cost]
			return
		_spend(merge_cost)
	var result := BuildManager.apply_armor(ud, item_id, quality, _reforge_school)
	match str(result.get("result", "")):
		"awaken", "merge", "plain":
			school = str(result.get("school", ""))
			if school == "":
				_msg.text = "%s 装备了普通防具" % ud.display_name
			elif str(result.get("result")) == "merge":
				_msg.text = "%s 并入 %s → Lv%d（花 %dG）" % [
					ud.display_name, school, int(result.get("level", 1)),
					BuildManager.get_merge_cost_instance()]
			else:
				_msg.text = "%s 觉醒【%s】" % [ud.display_name, school]
			_current = {}
			_reforge_school = ""
			_refresh()
		"full":
			_show_overwrite_choices(ud)
		_:
			_msg.text = "无法落位"


func _show_overwrite_choices(ud: UnitData) -> void:
	for c in _result_box.get_children():
		c.queue_free()
	var warn := Label.new()
	warn.text = "%s 的流派槽已满，选择覆盖一个机制或放弃" % ud.display_name
	warn.add_theme_font_size_override("font_size", FS_BODY)
	warn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	_result_box.add_child(warn)
	for m in BuildManager.get_unit_mechanisms(ud):
		var b := Button.new()
		b.text = "覆盖 %s Lv%d" % [m["school"], int(m["level"])]
		b.add_theme_font_size_override("font_size", FS_BODY)
		BuildUI.style_button(b, m["color"])
		b.pressed.connect(_on_confirm_overwrite.bind(ud, str(m["school"])))
		_result_box.add_child(b)
	var cancel := Button.new()
	cancel.text = "放弃这件防具"
	cancel.add_theme_font_size_override("font_size", FS_BODY)
	BuildUI.style_button(cancel)
	cancel.pressed.connect(_on_discard)
	_result_box.add_child(cancel)


func _on_confirm_overwrite(ud: UnitData, school_to_remove: String) -> void:
	Globals.show_confirm(self,
		"确定用这件防具替换【%s】？原机制将消失。" % school_to_remove,
		"覆盖", "取消",
		func(): _do_overwrite(ud, school_to_remove), func(): _render_result())


func _do_overwrite(ud: UnitData, school_to_remove: String) -> void:
	var result := BuildManager.overwrite_school(ud, school_to_remove,
		str(_current.get("item_id", "")), str(_current.get("quality", "common")), _reforge_school)
	_msg.text = "已用 %s 覆盖【%s】" % [str(result.get("school", "")), school_to_remove]
	_current = {}
	_reforge_school = ""
	_refresh()


func _on_close() -> void:
	if _closing:
		return
	_closing = true
	SaveManager.auto_save()
	closed.emit()
	queue_free()
