extends CanvasLayer
const BuildUI = preload("res://function/script/build/BuildUI.gd")
const SlotMachineUI = preload("res://function/script/build/SlotMachineUI.gd")
## ============================================================
##  SkillRollUI — v6.3 开局主动技能轮盘（玩家开始 / 停止选技能）
## ============================================================
##  选完 3 单位后：
##   - 轮盘池 = 已选单位 compatible_units 并集（已扩充技能池）
##   - 玩家点「开始旋转」，看准图标点「停！」决定这张技能
##   - 再点单位落位；不兼容 / 会导致死路的单位灰显
##   - 3 次结束进入地图；技能锁定、不可重掷、不可互换
## ============================================================

signal finished

const FS_TITLE: int = 10
const FS_BODY: int = 7
const FS_SMALL: int = 6

var _unit_names: Array = []
var _skills: Array = []
var _index: int = 0
var _placed_skills: Array = []
var _current_skill: String = ""

var _gold_color := Color(0.98, 0.75, 0.25)
var _dim_color := Color(0.5, 0.5, 0.53)

var _title: Label = null
var _progress: Label = null
var _machine = null
var _unit_row: HBoxContainer = null
var _skip_btn: Button = null
var _msg: Label = null
var _safe_picks: Array = []


func setup(unit_names: Array) -> void:
	_unit_names = unit_names.duplicate()
	# 保留一份原本的匹配结果作兜底；玩家停轮后可以改写当前这张
	_skills = BuildManager.roll_active_skills(_unit_names, 3)
	_index = 0
	_placed_skills.clear()
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
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
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

	# ★ 技能说明放到标题区（参考图的黄框位置），不再压在转轮与单位按钮之间
	_msg = Label.new()
	_msg.text = ""
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(0, 24)
	_msg.add_theme_font_size_override("font_size", FS_SMALL)
	_msg.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(_msg)

	_machine = SlotMachineUI.new()
	_machine.custom_minimum_size = Vector2(0, 96)
	vbox.add_child(_machine)
	_machine.stopped.connect(_on_machine_stopped)

	var pick := Label.new()
	pick.text = "停下后选落位单位（选定离手，不可撤销）"
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick.add_theme_font_size_override("font_size", FS_SMALL)
	pick.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(pick)

	_unit_row = HBoxContainer.new()
	_unit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_unit_row.add_theme_constant_override("separation", 8)
	_unit_row.custom_minimum_size = Vector2(0, 46)
	vbox.add_child(_unit_row)

	_skip_btn = Button.new()
	_skip_btn.text = "无人可落位 · 重转"
	_skip_btn.add_theme_font_size_override("font_size", FS_SMALL)
	BuildUI.style_button(_skip_btn)
	_skip_btn.pressed.connect(_on_skip)
	_skip_btn.visible = false
	vbox.add_child(_skip_btn)


func _show_step() -> void:
	_progress.text = "第 %d / %d 次" % [mini(_index + 1, _skills.size()), maxi(_skills.size(), 1)]
	if _index >= _skills.size():
		_finish()
		return
	_current_skill = str(_skills[_index])
	_clear_picks()
	_machine.setup(_build_skill_entries(), "主动技能轮盘 · 第 %d 次" % (_index + 1))
	_msg.text = "玩家决定结果：点开始，看准技能图标再点停"


func _build_skill_entries() -> Array:
	var entries: Array = []
	# ★ 轮盘池 = 当前尚未落位单位能装备的全部技能（尽量多给选择）。
	#   不再用「后续是否还能完美匹配」把池子压小；真正落位时仍由 _show_units 校验，
	#   若这张无人可用则提供「重转」，不推进次数。
	var remaining_names: Array = []
	for uname in _unit_names:
		var u: UnitData = _find_unit(str(uname))
		if u != null and (u.talent_slots.is_empty() or u.talent_slots[0] == null):
			remaining_names.append(str(uname))
	for tid in BuildManager.build_skill_pool(remaining_names):
		var sid := str(tid)
		if _placed_skills.has(sid):
			continue
		var placeable := false
		for uname in remaining_names:
			var ud: UnitData = _find_unit(str(uname))
			if ud == null:
				continue
			var adv := str(ud.advanced_class)
			if TalentManager.is_talent_compatible_with_unit(sid, ud.unit_name, adv):
				placeable = true
				break
		if not placeable:
			continue
		var data := TalentManager.get_talent_data(sid)
		if data == null:
			continue
		var school := BuildManager.get_school_of_skill(sid)
		var color := Color(0.85, 0.85, 0.9)
		if school != "":
			color = BuildManager.get_school_color(school)
		var desc := data.description
		var cost := int(data.effect_params.get("soul_fire_cost", data.soul_cost))
		desc += "｜消耗 %d 魂火" % cost
		if school != "":
			desc += "｜共鸣 %s" % school
		entries.append({
			"id": sid,
			"name": data.display_name,
			"desc": desc,
			"color": color,
			"icon": TalentManager.get_talent_icon(sid),
		})
	return entries


func _clear_picks() -> void:
	for c in _unit_row.get_children():
		c.queue_free()
	_safe_picks.clear()
	_skip_btn.visible = false


func _on_machine_stopped(entry: Dictionary) -> void:
	var tid := str(entry.get("id", ""))
	if tid == "" or _placed_skills.has(tid):
		_msg.text = "这张已用过，请再转一次"
		_machine.setup(_build_skill_entries(), "主动技能轮盘 · 第 %d 次" % (_index + 1))
		return
	_skills[_index] = tid
	_current_skill = tid
	_msg.text = str(entry.get("desc", ""))
	_show_units(tid)


func _show_units(tid: String) -> void:
	_clear_picks()
	# 三个单位头像横向排开；不可装备的 gray out，但仍显示，方便玩家知道选择范围
	var any_ok := false
	for uname in _unit_names:
		var ud: UnitData = _find_unit(str(uname))
		if ud == null:
			continue
		var slot_empty := ud.talent_slots.is_empty() or ud.talent_slots[0] == null
		var adv := str(ud.advanced_class)
		var compatible := TalentManager.is_talent_compatible_with_unit(tid, ud.unit_name, adv)
		var can_pick := slot_empty and compatible

		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.size_flags_vertical = Control.SIZE_FILL
		card.add_theme_constant_override("separation", 1)
		card.custom_minimum_size = Vector2(64, 0)
		# 头像按钮自带画框，不再额外套 PanelContainer，避免双层边框
		var avatar := UnitDataManager.create_unit_avatar_button(
			ud.unit_name, Vector2(46, 46), Vector2(40, 40))
		avatar.disabled = not can_pick
		avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if can_pick:
			avatar.pressed.connect(_on_pick.bind(ud, tid))
			any_ok = true
			_safe_picks.append({"ud": ud, "tid": tid})
		else:
			avatar.modulate = Color(0.35, 0.35, 0.38)
		card.add_child(avatar)

		var name_lbl := Label.new()
		name_lbl.text = ud.display_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.custom_minimum_size = Vector2(64, 12)
		name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		name_lbl.clip_text = true
		name_lbl.add_theme_font_size_override("font_size", FS_SMALL)
		name_lbl.add_theme_color_override("font_color", _gold_color if can_pick else _dim_color)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_lbl)
		_unit_row.add_child(card)

	_skip_btn.visible = not any_ok
	if not any_ok:
		_msg.text = "这张技能当前队伍无人可用，请重转"


func _find_unit(unit_name: String) -> UnitData:
	for ud in GameState.party:
		if ud != null and ud.unit_name == unit_name:
			return ud
	return null


func _on_pick(ud: UnitData, tid: String) -> void:
	BuildManager.place_skill(ud, tid)
	_placed_skills.append(tid)
	_next()


func _on_skip() -> void:
	if _safe_picks.is_empty():
		# 无人可用：重新开一轮，不推进次数
		_machine.setup(_build_skill_entries(), "主动技能轮盘 · 第 %d 次" % (_index + 1))
		return
	_next()


func _next() -> void:
	_index += 1
	_show_step()


func _finish() -> void:
	SaveManager.auto_save()
	finished.emit()
	queue_free()
