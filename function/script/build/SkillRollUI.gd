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
# ★ Arena 单单位适配：外部注入单位对象（不注入则回退 GameState.party，主线零改动）
var _unit_override: Array = []
var _roll_count: int = 3


func setup(unit_names: Array, unit_data_override: Array = [], roll_count: int = 3) -> void:
	_unit_names = unit_names.duplicate()
	_unit_override = unit_data_override.duplicate()
	_roll_count = maxi(1, roll_count)
	# 保留一份原本的匹配结果作兜底；玩家停轮后可以改写当前这张
	# ★ v6.16：把注入的单位对象传给 roll_active_skills，用其自身槽位状态判空，
	#   避免 Arena 单单位因 GameState.party 同名单位占格被排除导致空池秒关。
	_skills = BuildManager.roll_active_skills(_unit_names, _roll_count, _unit_override)
	print("[SkillRollUI] setup: units=%s, skills=%d, override=%d" % [
		str(_unit_names), _skills.size(), _unit_override.size()])
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
	# ★ 死锁修复：没有可落位技能时绝不能用空池 setup（轮盘转不起来、
	#   本界面又无退出按钮）。直接跳过剩余次数并正常结束，进入地图。
	var entries: Array = _build_skill_entries()
	if entries.is_empty():
		push_warning("[SkillRollUI] 第 %d 次无可用技能，跳过本次及后续" % (_index + 1))
		_index = _skills.size()
		_finish()
		return
	_current_skill = str(_skills[_index])
	_clear_picks()
	_machine.setup(entries, "主动技能轮盘 · 第 %d 次" % (_index + 1))
	_msg.text = "玩家决定结果：点开始，看准技能图标再点停"
	_msg.add_theme_color_override("font_color", _dim_color)


func _build_skill_entries() -> Array:
	var entries: Array = []
	# ★ v6.18：轮盘池预筛改用 can_place_with_future（全池匹配），
	#   与落位判定口径一致。旧版用固定剩余技能精确覆盖，把池子压得只剩少数技能、
	#   每张卡又只剩 1 个落点 → 1 对 1。现在只要存在一个单位能安全落位即可入池。
	var remaining_names: Array = []
	for uname in _unit_names:
		var u: UnitData = _find_unit(str(uname))
		if u != null and (u.talent_slots.is_empty() or u.talent_slots[0] == null):
			remaining_names.append(str(uname))

	# ★ v6.19：轮盘池优先取"能被至少 2 个剩余单位装备"的技能，
	#   从源头避免转出只对应单一单位的技能卡。仅当这类技能不足时降级到全池。
	var source_pool: Array = BuildManager.build_skill_pool_ranked(remaining_names, 2)
	if source_pool.is_empty():
		source_pool = BuildManager.build_skill_pool(remaining_names)

	var safe_pool: Array = []       # 至少一个单位能安全落位（首选）
	var fallback_pool: Array = []   # 仅兼容但无法保证后续覆盖（兜底）
	for tid in source_pool:
		var sid := str(tid)
		if _placed_skills.has(sid):
			continue
		var has_safe := false
		var has_placeable := false
		for uname in remaining_names:
			var ud: UnitData = _find_unit(str(uname))
			if ud == null:
				continue
			if BuildManager.can_place_skill(ud, sid):
				has_placeable = true
			if BuildManager.can_place_with_future(ud, sid, remaining_names):
				has_safe = true
				break
		if has_safe:
			safe_pool.append(sid)
		elif has_placeable:
			fallback_pool.append(sid)

	var chosen: Array = safe_pool if not safe_pool.is_empty() else fallback_pool
	for sid in chosen:
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
		var entries: Array = _build_skill_entries()
		if entries.is_empty():
			_index = _skills.size()
			_finish()
			return
		_msg.text = "这张已用过，请再转一次"
		_msg.add_theme_color_override("font_color", _dim_color)
		_machine.setup(entries, "主动技能轮盘 · 第 %d 次" % (_index + 1))
		return
	_skills[_index] = tid
	_current_skill = tid
	_msg.text = str(entry.get("desc", ""))
	# ★ 选出的技能说明用正常亮色，不再灰显
	var cv: Variant = entry.get("color", null)
	_msg.add_theme_color_override("font_color", cv if cv is Color else Color.WHITE)
	_show_units(tid)


func _show_units(tid: String) -> void:
	_clear_picks()
	# 收集尚未占用第 1 技能格的单位
	var remaining_names: Array = []
	for uname in _unit_names:
		var u: UnitData = _find_unit(str(uname))
		if u != null and (u.talent_slots.is_empty() or u.talent_slots[0] == null):
			remaining_names.append(str(uname))
	# ★ v6.19：只显示"尚未装备技能"的单位——已落位的单位不再出现在本界面选项里。
	# ★ v6.18：落位判定用 can_place_with_future（全池匹配），取代过紧的 is_safe_placement。
	var any_ok := false
	for uname in remaining_names:
		var ud: UnitData = _find_unit(str(uname))
		if ud == null:
			continue
		var adv := str(ud.advanced_class)
		var compatible := TalentManager.is_talent_compatible_with_unit(tid, ud.unit_name, adv)
		var safe := BuildManager.can_place_with_future(ud, tid, remaining_names)
		var can_pick := compatible and safe

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

		# ★ v6.21：头像下方的流派方向文字，颜色与流派一致。
		#   ① 本次 roll 技能的共鸣流派（让玩家看懂这张技能属于哪个流派方向）；
		#   ② 该单位已觉醒的流派（开局通常为空）。都用各自流派色，方便对应。
		var school_row := HBoxContainer.new()
		school_row.alignment = BoxContainer.ALIGNMENT_CENTER
		school_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		school_row.add_theme_constant_override("separation", 3)

		var resonance := BuildManager.get_school_of_skill(tid)
		var mechs := BuildManager.get_unit_mechanisms(ud)
		if resonance == "" and mechs.is_empty():
			var none_lbl := Label.new()
			none_lbl.text = "无流派"
			none_lbl.add_theme_font_size_override("font_size", FS_SMALL)
			none_lbl.add_theme_color_override("font_color", _dim_color)
			school_row.add_child(none_lbl)
		else:
			if resonance != "":
				var rl := Label.new()
				rl.text = "共鸣·%s" % resonance
				rl.add_theme_font_size_override("font_size", FS_SMALL)
				rl.add_theme_color_override("font_color", BuildManager.get_school_color(resonance))
				school_row.add_child(rl)
			for m in mechs:
				var ml := Label.new()
				ml.text = "%s Lv%d" % [str(m.get("school", "")), int(m.get("level", 1))]
				ml.add_theme_font_size_override("font_size", FS_SMALL)
				ml.add_theme_color_override("font_color", m.get("color", Color.WHITE))
				school_row.add_child(ml)
		card.add_child(school_row)
		_unit_row.add_child(card)

	_skip_btn.visible = not any_ok
	if not any_ok:
		_msg.text = "这张技能当前队伍无人可用，请重转"
		_msg.add_theme_color_override("font_color", _dim_color)


func _find_unit(unit_name: String) -> UnitData:
	# ★ 优先从外部注入的单位对象找（Arena 单单位），否则回退主线 GameState.party
	if not _unit_override.is_empty():
		for ud in _unit_override:
			if ud != null and ud.unit_name == unit_name:
				return ud
		return null
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
		# 无人可用：重新开一轮，不推进次数；但若池已空则直接结束，避免卡死
		var entries: Array = _build_skill_entries()
		if entries.is_empty():
			_index = _skills.size()
			_finish()
			return
		_machine.setup(entries, "主动技能轮盘 · 第 %d 次" % (_index + 1))
		return
	_next()


func _next() -> void:
	_index += 1
	_show_step()


func _finish() -> void:
	SaveManager.auto_save()
	finished.emit()
	queue_free()
