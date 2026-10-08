extends Control

# ============================================================
#  UnitBattleSimulator — 单位编辑 + 战斗模拟 + 数值编辑
# ============================================================

const UNIT_DATA_PATH : String = "res://content/data/unit_data.json"
const RELIC_DATA_PATH : String = "res://content/data/relic_data.json"
const REFINE_DATA_PATH : String = "res://content/data/refine_recipes.json"
const ITEM_DATA_PATH : String = "res://content/data/item_data.json"
const TALENT_DATA_PATH : String = "res://content/data/talents.json"

const EDITABLE_ATTRS : Array = [
	{"key": "max_hp",       "label": "HP",   "min": 1, "max": 999},
	{"key": "strength",     "label": "力",   "min": 0, "max": 99},
	{"key": "dexterity",    "label": "灵",   "min": 0, "max": 99},
	{"key": "intelligence", "label": "智",   "min": 0, "max": 99},
	{"key": "faith",        "label": "信",   "min": 0, "max": 99},
	{"key": "arcane",       "label": "感",   "min": 0, "max": 99},
	{"key": "move_range",   "label": "移",   "min": 0, "max": 20},
]

# ---- 数据 ----
var _unit_db : Dictionary = {}
var _unit_keys : Array = []
var _relic_db : Dictionary = {}
var _relic_keys : Array = []
var _refine_db : Dictionary = {}
var _refine_keys : Array = []
var _weapon_ids : Array = []
var _armor_ids : Array = []
var _talent_ids : Array = []
var _current_unit_key : String = ""

# ---- UI ----
var _tab_btns : Array = []
var _tab_panels : Array = []
var _edit_unit_list : VBoxContainer = null
var _edit_status : Label = null
var _edit_attr_spins : Dictionary = {}
var _edit_name_edit : LineEdit = null
var _edit_faction_edit : LineEdit = null
var _edit_weapon_opt : OptionButton = null
var _edit_armor_opts : Array = []
var _edit_talent_opts : Array = []

var _sim_player_opt : OptionButton = null
var _sim_enemy_opt : OptionButton = null
var _sim_log : RichTextLabel = null
var _sim_status : Label = null
var _sim_p_weapon : OptionButton = null
var _sim_p_weapon_lv : OptionButton = null
var _sim_p_armor1 : OptionButton = null
var _sim_p_armor2 : OptionButton = null
var _sim_p_talent1 : OptionButton = null
var _sim_p_talent2 : OptionButton = null
var _sim_p_relics : Array = []
var _sim_p_refines : Array = []
var _sim_p_skills : Array = []

var _sim_e_weapon : OptionButton = null
var _sim_e_weapon_lv : OptionButton = null
var _sim_e_armor1 : OptionButton = null
var _sim_e_armor2 : OptionButton = null
var _sim_e_talent1 : OptionButton = null
var _sim_e_talent2 : OptionButton = null
var _sim_e_relics : Array = []
var _sim_e_refines : Array = []
var _sim_e_skills : Array = []

var _sim_talent_cb : CheckBox = null
var _sim_counter_cb : CheckBox = null

var _cfg_tab_panels : Dictionary = {}


func _ready():
	_load_all_data()
	_build_ui()
	_refresh_unit_list()
	_refresh_sim_unit_lists()
	if _unit_keys.size() > 0:
		_select_edit_unit(_unit_keys[0])


# ============================================================
#  数据加载
# ============================================================
func _load_all_data():
	_unit_db = _load_json(UNIT_DATA_PATH)
	_unit_keys = _unit_db.keys()
	_unit_keys.sort()

	_relic_db = _load_json(RELIC_DATA_PATH)
	_relic_keys = _relic_db.keys()
	_relic_keys.sort()

	_refine_db = _load_json(REFINE_DATA_PATH)
	_refine_keys = _refine_db.keys()
	_refine_keys.sort()

	for iid in ItemManager.get_all_item_ids():
		var d = ItemManager.get_item_data(iid)
		if d == null: continue
		if d.type == "weapon": _weapon_ids.append(iid)
		elif d.type == "armor": _armor_ids.append(iid)
	_weapon_ids.sort()
	_armor_ids.sort()
	_talent_ids = TalentManager.get_all_talent_ids()


func _load_json(path : String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("文件不存在: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var text : String = f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		push_warning("解析失败: " + path)
		return {}
	return data


# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 4
	root.offset_top = 4
	root.offset_right = -4
	root.offset_bottom = -4
	root.add_theme_constant_override("separation", 3)
	add_child(root)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 3)
	root.add_child(tab_bar)

	var tab_names : Array = ["单位编辑", "战斗模拟", "数值编辑"]
	for i in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 7)
		btn.pressed.connect(func(): _switch_tab(i))
		tab_bar.add_child(btn)
		_tab_btns.append(btn)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_tab_panels.clear()
	_tab_panels.append(_build_edit_tab(body))
	_tab_panels.append(_build_sim_tab(body))
	_tab_panels.append(_build_cfg_tab(body))

	_switch_tab(0)


func _switch_tab(idx : int):
	for i in range(_tab_btns.size()):
		_tab_btns[i].button_pressed = (i == idx)
	for i in range(_tab_panels.size()):
		_tab_panels[i].visible = (i == idx)


# ============================================================
#  Tab 1：单位编辑
# ============================================================
func _build_edit_tab(parent : Control) -> Control:
	var panel := HBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 4)
	parent.add_child(panel)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(90, 0)
	left.add_theme_constant_override("separation", 1)
	panel.add_child(left)

	var llb := Label.new()
	llb.text = "— 单位 —"
	llb.add_theme_font_size_override("font_size", 7)
	llb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(llb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_edit_unit_list = VBoxContainer.new()
	_edit_unit_list.add_theme_constant_override("separation", 1)
	_edit_unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_edit_unit_list)

	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(160, 0)
	mid.add_theme_constant_override("separation", 2)
	panel.add_child(mid)

	var mlb := Label.new()
	mlb.text = "— 属性 —"
	mlb.add_theme_font_size_override("font_size", 7)
	mlb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(mlb)

	_edit_name_edit = _add_edit_row(mid, "名字")
	_edit_faction_edit = _add_edit_row(mid, "阵营")

	for a in EDITABLE_ATTRS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		mid.add_child(row)

		var lb := Label.new()
		lb.text = a["label"]
		lb.custom_minimum_size = Vector2(30, 0)
		lb.add_theme_font_size_override("font_size", 7)
		row.add_child(lb)

		var sp := SpinBox.new()
		sp.min_value = a["min"]
		sp.max_value = a["max"]
		sp.step = 1
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		_style_spin(sp, 7)
		_edit_attr_spins[a["key"]] = sp

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 2)
	panel.add_child(right)

	var rlb := Label.new()
	rlb.text = "— 默认装备 / 特技 —"
	rlb.add_theme_font_size_override("font_size", 7)
	rlb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(rlb)

	_edit_weapon_opt = _add_option_row(right, "武器", _weapon_ids, "无")
	_edit_armor_opts.append(_add_option_row(right, "防具1", _armor_ids, "无"))
	_edit_armor_opts.append(_add_option_row(right, "防具2", _armor_ids, "无"))
	_edit_talent_opts.append(_add_option_row(right, "特技1", _talent_ids, "无"))
	_edit_talent_opts.append(_add_option_row(right, "特技2", _talent_ids, "无"))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 3)
	right.add_child(btn_row)

	# ★ 重置（从当前 JSON 重新读取）
	var reset_btn := Button.new()
	reset_btn.text = "重置"
	reset_btn.add_theme_font_size_override("font_size", 7)
	reset_btn.pressed.connect(_reset_unit_db)
	btn_row.add_child(reset_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.add_theme_font_size_override("font_size", 7)
	save_btn.pressed.connect(_save_unit_db)
	btn_row.add_child(save_btn)

	_edit_status = Label.new()
	_edit_status.add_theme_font_size_override("font_size", 6)
	_edit_status.modulate = Color(0.7, 0.9, 0.7)
	right.add_child(_edit_status)

	return panel


func _add_edit_row(parent : Node, label : String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	lb.text = label
	lb.custom_minimum_size = Vector2(30, 0)
	lb.add_theme_font_size_override("font_size", 7)
	row.add_child(lb)

	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", 7)
	row.add_child(le)
	return le


func _add_option_row(parent : Node, label : String, ids : Array, none_text : String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	lb.text = label
	lb.custom_minimum_size = Vector2(40, 0)
	lb.add_theme_font_size_override("font_size", 7)
	row.add_child(lb)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", 7)
	opt.add_item(none_text, 0)
	for i in range(ids.size()):
		var iid : String = ids[i]
		opt.add_item(_get_display_name(iid), i + 1)
		opt.set_item_metadata(i + 1, iid)
	row.add_child(opt)
	return opt


func _get_display_name(iid : String) -> String:
	var item = ItemManager.get_item_data(iid)
	if item: return item.name
	var talent = TalentManager.get_talent_data(iid)
	if talent: return talent.display_name
	var relic = _relic_db.get(iid, {})
	if not relic.is_empty(): return relic.get("name", iid)
	return iid


# ============================================================
#  Tab 2：战斗模拟
# ============================================================
func _build_sim_tab(parent : Control) -> Control:
	var panel := HBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 4)
	parent.add_child(panel)

	panel.add_child(_build_sim_side("我方", true))
	panel.add_child(_build_sim_center())
	panel.add_child(_build_sim_side("敌方", false))

	return panel


func _build_sim_side(title : String, is_player : bool) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(150, 0)
	vbox.add_theme_constant_override("separation", 1)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 1)
	scroll.add_child(inner)

	var lb := Label.new()
	lb.text = "— %s —" % title
	lb.add_theme_font_size_override("font_size", 7)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(lb)

	var unit_opt := OptionButton.new()
	unit_opt.add_theme_font_size_override("font_size", 7)
	if is_player: _sim_player_opt = unit_opt
	else: _sim_enemy_opt = unit_opt
	inner.add_child(unit_opt)

	_add_sep_label(inner, "装备")
	var weapon_opt := _add_option_row(inner, "武器", _weapon_ids, "默认")
	var up_lv_opt := _add_int_option_row(inner, "武器+", 0, 5)
	var a1 := _add_option_row(inner, "防1", _armor_ids, "默认")
	var a2 := _add_option_row(inner, "防2", _armor_ids, "默认")

	_add_sep_label(inner, "特技")
	var t1 := _add_option_row(inner, "特1", _talent_ids, "默认")
	var t2 := _add_option_row(inner, "特2", _talent_ids, "默认")

	_add_sep_label(inner, "遗物")
	var relic_checks : Array = []
	for i in range(_relic_keys.size()):
		var rid : String = _relic_keys[i]
		var rname : String = _relic_db[rid].get("name", rid)
		var cb := CheckBox.new()
		cb.text = rname
		cb.add_theme_font_size_override("font_size", 6)
		cb.set_meta("rid", rid)
		inner.add_child(cb)
		relic_checks.append(cb)

	_add_sep_label(inner, "精炼")
	var refine_checks : Array = []
	for i in range(_refine_keys.size()):
		var fid : String = _refine_keys[i]
		var fname : String = _refine_db[fid].get("name", fid)
		var cb := CheckBox.new()
		cb.text = fname
		cb.add_theme_font_size_override("font_size", 6)
		cb.set_meta("fid", fid)
		inner.add_child(cb)
		refine_checks.append(cb)

	_add_sep_label(inner, "主动技能")
	var skill_checks : Array = []
	for tid in _talent_ids:
		var tdata = TalentManager.get_talent_data(tid)
		if not tdata or not tdata.is_active_skill: continue
		var cb := CheckBox.new()
		cb.text = tdata.display_name
		cb.add_theme_font_size_override("font_size", 6)
		cb.set_meta("tid", tid)
		inner.add_child(cb)
		skill_checks.append(cb)

	if is_player:
		_sim_p_weapon = weapon_opt
		_sim_p_weapon_lv = up_lv_opt
		_sim_p_armor1 = a1; _sim_p_armor2 = a2
		_sim_p_talent1 = t1; _sim_p_talent2 = t2
		_sim_p_relics = relic_checks
		_sim_p_refines = refine_checks
		_sim_p_skills = skill_checks
	else:
		_sim_e_weapon = weapon_opt
		_sim_e_weapon_lv = up_lv_opt
		_sim_e_armor1 = a1; _sim_e_armor2 = a2
		_sim_e_talent1 = t1; _sim_e_talent2 = t2
		_sim_e_relics = relic_checks
		_sim_e_refines = refine_checks
		_sim_e_skills = skill_checks

	return vbox


func _add_sep_label(parent : Node, text : String):
	var sep := HSeparator.new()
	sep.modulate = Color(0.35, 0.35, 0.35)
	parent.add_child(sep)
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", 6)
	lb.modulate = Color(0.75, 0.8, 0.9)
	parent.add_child(lb)


func _add_int_option_row(parent : Node, label : String, min_v : int, max_v : int) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	lb.text = label
	lb.custom_minimum_size = Vector2(40, 0)
	lb.add_theme_font_size_override("font_size", 7)
	row.add_child(lb)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", 7)
	for v in range(min_v, max_v + 1):
		opt.add_item("+%d" % v, v - min_v)
		opt.set_item_metadata(v - min_v, v)
	opt.selected = 0
	row.add_child(opt)
	return opt


func _build_sim_center() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)

	var lb := Label.new()
	lb.text = "— 战斗日志 —"
	lb.add_theme_font_size_override("font_size", 7)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lb)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 4)
	ctrl.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(ctrl)

	_sim_talent_cb = CheckBox.new()
	_sim_talent_cb.text = "词条"
	_sim_talent_cb.button_pressed = true
	_sim_talent_cb.add_theme_font_size_override("font_size", 7)
	ctrl.add_child(_sim_talent_cb)

	_sim_counter_cb = CheckBox.new()
	_sim_counter_cb.text = "反击"
	_sim_counter_cb.button_pressed = true
	_sim_counter_cb.add_theme_font_size_override("font_size", 7)
	ctrl.add_child(_sim_counter_cb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_sim_log = RichTextLabel.new()
	_sim_log.bbcode_enabled = true
	_sim_log.fit_content = true
	_sim_log.scroll_following = true
	_sim_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sim_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sim_log.add_theme_font_size_override("normal_font_size", 7)
	scroll.add_child(_sim_log)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_row)

	var start_btn := Button.new()
	start_btn.text = "开始模拟"
	start_btn.add_theme_font_size_override("font_size", 7)
	start_btn.pressed.connect(_run_simulation)
	btn_row.add_child(start_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.add_theme_font_size_override("font_size", 7)
	clear_btn.pressed.connect(func(): _sim_log.clear())
	btn_row.add_child(clear_btn)

	_sim_status = Label.new()
	_sim_status.add_theme_font_size_override("font_size", 6)
	_sim_status.modulate = Color(0.7, 0.9, 0.7)
	_sim_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_sim_status)

	return vbox


# ============================================================
#  Tab 3：数值编辑
# ============================================================
func _build_cfg_tab(parent : Control) -> Control:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 3)
	parent.add_child(panel)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3)
	panel.add_child(bar)

	var cfg_files : Array = [
		{"name": "遗物", "path": RELIC_DATA_PATH},
		{"name": "精炼", "path": REFINE_DATA_PATH},
		{"name": "武器防具", "path": ITEM_DATA_PATH},
		{"name": "特技", "path": TALENT_DATA_PATH},
	]
	_cfg_tab_panels.clear()
	var btns : Array = []
	for i in range(cfg_files.size()):
		var btn := Button.new()
		btn.text = cfg_files[i]["name"]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 7)
		bar.add_child(btn)
		btns.append(btn)

	var container := Control.new()
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(container)

	for i in range(cfg_files.size()):
		var editor := _build_json_editor(cfg_files[i]["path"])
		editor.set_anchors_preset(Control.PRESET_FULL_RECT)
		editor.visible = false
		container.add_child(editor)
		_cfg_tab_panels[cfg_files[i]["path"]] = editor

	for i in range(btns.size()):
		var idx : int = i
		btns[i].pressed.connect(func():
			for j in range(btns.size()):
				btns[j].button_pressed = (j == idx)
			for path in _cfg_tab_panels:
				_cfg_tab_panels[path].visible = (path == cfg_files[idx]["path"])
		)

	btns[0].button_pressed = true
	_cfg_tab_panels[cfg_files[0]["path"]].visible = true

	return panel


func _build_json_editor(path : String) -> Control:
	var editor = preload("res://function/tool/simulator/JSONEditorPanel.gd").new()
	editor.setup(path)
	return editor


# ============================================================
#  单位编辑逻辑
# ============================================================
func _refresh_unit_list():
	for c in _edit_unit_list.get_children():
		_edit_unit_list.remove_child(c)
		c.queue_free()
	for key in _unit_keys:
		var btn := Button.new()
		btn.text = _unit_db[key].get("display_name", key)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 7)
		btn.clip_text = true
		btn.set_meta("unit_key", key)
		btn.pressed.connect(func(): _select_edit_unit(key))
		_edit_unit_list.add_child(btn)


func _select_edit_unit(key : String):
	if not _unit_db.has(key): return
	_current_unit_key = key
	var d : Dictionary = _unit_db[key]

	for btn in _edit_unit_list.get_children():
		var k : String = btn.get_meta("unit_key", "")
		btn.button_pressed = (k == key)
		btn.modulate = Color.WHITE if k == key else Color(0.7, 0.7, 0.7)

	_edit_name_edit.text = d.get("display_name", key)
	_edit_faction_edit.text = d.get("faction", "")
	for a in EDITABLE_ATTRS:
		_edit_attr_spins[a["key"]].value = d.get(a["key"], 0)

	_select_option_by_meta(_edit_weapon_opt, d.get("default_weapon", ""))
	var armor_list : Array = d.get("default_armors", [])
	for i in range(_edit_armor_opts.size()):
		var aid : String = armor_list[i] if i < armor_list.size() else ""
		_select_option_by_meta(_edit_armor_opts[i], aid)
	var talent_list : Array = d.get("default_talents", [])
	for i in range(_edit_talent_opts.size()):
		var tid : String = talent_list[i] if i < talent_list.size() else ""
		_select_option_by_meta(_edit_talent_opts[i], tid)


func _select_option_by_meta(opt : OptionButton, target_id : String):
	opt.selected = 0
	for i in range(opt.item_count):
		var m = opt.get_item_metadata(i)
		if m != null and str(m) == target_id:
			opt.selected = i
			return


## ★ 重置：从磁盘重新读取 unit_data.json，放弃未保存的编辑
func _reset_unit_db():
	_unit_db = _load_json(UNIT_DATA_PATH)
	_unit_keys = _unit_db.keys()
	_unit_keys.sort()
	_refresh_unit_list()
	_refresh_sim_unit_lists()
	if _current_unit_key != "" and _unit_db.has(_current_unit_key):
		_select_edit_unit(_current_unit_key)
	_edit_status.text = "已重置（未保存的修改已丢弃）"


func _save_unit_db():
	if _current_unit_key == "": return
	var d : Dictionary = _unit_db[_current_unit_key]
	d["display_name"] = _edit_name_edit.text
	d["faction"] = _edit_faction_edit.text
	for a in EDITABLE_ATTRS:
		d[a["key"]] = int(_edit_attr_spins[a["key"]].value)
	d["default_weapon"] = _get_meta(_edit_weapon_opt)

	var armor_ids : Array = []
	for opt in _edit_armor_opts:
		var aid : String = _get_meta(opt)
		if aid != "": armor_ids.append(aid)
	d["default_armors"] = armor_ids

	var talent_ids : Array = []
	for opt in _edit_talent_opts:
		var tid : String = _get_meta(opt)
		if tid != "": talent_ids.append(tid)
	d["default_talents"] = talent_ids

	var f := FileAccess.open(UNIT_DATA_PATH, FileAccess.WRITE)
	if f == null:
		_edit_status.text = "❌ 保存失败"
		return
	f.store_string(JSON.stringify(_unit_db, "  "))
	f.close()
	_edit_status.text = "✓ 已保存"
	print("[UnitSim] unit_data.json 已保存")


func _get_meta(opt : OptionButton) -> String:
	var idx : int = opt.selected
	if idx <= 0: return ""
	var m = opt.get_item_metadata(idx)
	return str(m) if m != null else ""


# ============================================================
#  战斗模拟逻辑
# ============================================================
func _refresh_sim_unit_lists():
	_sim_player_opt.clear()
	_sim_enemy_opt.clear()
	for i in range(_unit_keys.size()):
		var key : String = _unit_keys[i]
		var display_name : String = _unit_db[key].get("display_name", key)
		_sim_player_opt.add_item(display_name, i)
		_sim_enemy_opt.add_item(display_name, i)
		_sim_player_opt.set_item_metadata(i, key)
		_sim_enemy_opt.set_item_metadata(i, key)
	if _unit_keys.size() >= 2:
		_sim_player_opt.selected = 0
		_sim_enemy_opt.selected = 1


func _run_simulation():
	var p_key : String = str(_sim_player_opt.get_item_metadata(_sim_player_opt.selected))
	var e_key : String = str(_sim_enemy_opt.get_item_metadata(_sim_enemy_opt.selected))
	if p_key == "" or e_key == "":
		_sim_status.text = "请选择双方单位"
		return

	var p_lv : int = _get_option_int(_sim_p_weapon_lv)
	var e_lv : int = _get_option_int(_sim_e_weapon_lv)

	var p : UnitData = _build_runtime_unit(p_key,
		_get_meta(_sim_p_weapon), p_lv,
		_collect_armors(_sim_p_armor1, _sim_p_armor2),
		_collect_talents(_sim_p_talent1, _sim_p_talent2),
		_collect_checked(_sim_p_relics),
		_collect_checked(_sim_p_refines),
		_collect_checked(_sim_p_skills))

	var e : UnitData = _build_runtime_unit(e_key,
		_get_meta(_sim_e_weapon), e_lv,
		_collect_armors(_sim_e_armor1, _sim_e_armor2),
		_collect_talents(_sim_e_talent1, _sim_e_talent2),
		_collect_checked(_sim_e_relics),
		_collect_checked(_sim_e_refines),
		_collect_checked(_sim_e_skills))

	if p == null or e == null:
		_sim_status.text = "单位数据错误"
		return

	var engine = BattleSimEngine.new()
	engine.set_manual_triggers(_collect_checked(_sim_p_skills), _collect_checked(_sim_e_skills))
	engine.set_talent_mode("auto" if _sim_talent_cb.button_pressed else "disabled")
	engine.set_counter_enabled(_sim_counter_cb.button_pressed)
	var lines : Array = engine.run(p, e)

	_sim_log.clear()
	for line in lines:
		_sim_log.append_text(line + "\n")

	_sim_status.text = "模拟完成：" + engine.get_result_text()


func _get_option_int(opt : OptionButton) -> int:
	if opt == null: return 0
	var m = opt.get_item_metadata(opt.selected)
	return int(m) if m != null else 0


func _collect_armors(o1 : OptionButton, o2 : OptionButton) -> Array:
	var result : Array = []
	var a1 : String = _get_meta(o1)
	var a2 : String = _get_meta(o2)
	if a1 != "": result.append(a1)
	if a2 != "": result.append(a2)
	return result


func _collect_talents(o1 : OptionButton, o2 : OptionButton) -> Array:
	var result : Array = []
	var t1 : String = _get_meta(o1)
	var t2 : String = _get_meta(o2)
	if t1 != "": result.append(t1)
	if t2 != "": result.append(t2)
	return result


func _collect_checked(checks : Array) -> Array:
	var result : Array = []
	for cb in checks:
		if cb.button_pressed:
			var k : String = ""
			if cb.has_meta("rid"): k = str(cb.get_meta("rid"))
			elif cb.has_meta("fid"): k = str(cb.get_meta("fid"))
			elif cb.has_meta("tid"): k = str(cb.get_meta("tid"))
			if k != "": result.append(k)
	return result


func _build_runtime_unit(key : String, weapon_override : String, weapon_upgrade : int,
		armors_override : Array, talents_override : Array, relic_ids : Array,
		refine_ids : Array, _active_skills : Array) -> UnitData:
	if not _unit_db.has(key): return null
	var base : Dictionary = _unit_db[key]
	var ud : UnitData = UnitData.from_dict(base)
	ud.hit_points = ud.max_hp

	if weapon_override != "":
		var inst := ItemInstance.new()
		inst.item_id = weapon_override
		inst.count = 1
		inst.upgrade_level = weapon_upgrade
		ud.weapon_slot = inst

	if not armors_override.is_empty():
		ud.armor_slots.clear()
		for aid in armors_override:
			var inst := ItemInstance.new()
			inst.item_id = aid
			inst.count = 1
			ud.armor_slots.append(inst)
		ud.max_armor_slots = ud.armor_slots.size()

	ud.talent_slots.clear()
	if not talents_override.is_empty():
		for tid in talents_override:
			var tinst := TalentInstance.new()
			tinst.talent_id = tid
			tinst.is_active = true
			var tdata = TalentManager.get_talent_data(tid)
			if tdata and tdata.is_active_skill:
				tinst.is_ready = true
			ud.talent_slots.append(tinst)
	else:
		var def_talents : Array = base.get("default_talents", [])
		for tid in def_talents:
			var tinst := TalentInstance.new()
			tinst.talent_id = tid
			tinst.is_active = true
			var tdata = TalentManager.get_talent_data(tid)
			if tdata and tdata.is_active_skill:
				tinst.is_ready = true
			ud.talent_slots.append(tinst)

	_apply_relics(ud, relic_ids)
	_apply_refines(ud, refine_ids)

	return ud


func _apply_relics(ud : UnitData, relic_ids : Array):
	for rid in relic_ids:
		var rdata : Dictionary = _relic_db.get(rid, {})
		if rdata.is_empty(): continue
		var effects : Dictionary = rdata.get("effects", {})
		if effects.get("first_attack_crit", false):
			ud.relic_first_attack_crit_available = true
		if effects.has("low_hp_damage_reduce"):
			ud.relic_low_hp_damage_reduce = float(effects["low_hp_damage_reduce"])
		if effects.has("kill_grants_extra_move"):
			ud.relic_kill_grants_extra_move = int(effects["kill_grants_extra_move"])
		if effects.get("first_spell_free", false):
			ud.relic_first_spell_free_available = true
		if effects.has("turn_first_hit_regen"):
			ud.relic_turn_first_hit_regen = float(effects["turn_first_hit_regen"])
		if effects.has("strength_scale_damage"):
			ud.relic_strength_scale_damage = float(effects["strength_scale_damage"])
		if effects.has("counter_damage_bonus"):
			ud.relic_counter_damage_bonus = float(effects["counter_damage_bonus"])
		if effects.has("heal_bonus"):
			ud.relic_heal_bonus = float(effects["heal_bonus"])
		if effects.get("auto_revive_once", false):
			ud.relic_auto_revive_available = true


func _apply_refines(ud : UnitData, refine_ids : Array):
	for fid in refine_ids:
		var rdata : Dictionary = _refine_db.get(fid, {})
		if rdata.is_empty(): continue
		var effect : Dictionary = rdata.get("effect", {})
		var etype : String = effect.get("type", "")
		var val : float = float(effect.get("value", 0))
		match etype:
			"attack_percent":
				ud.buff_attack_percent += val
			"crit_damage_bonus":
				ud.buff_crit_damage_bonus += val
			"defense_flat":
				ud.buff_defense_flat += int(val)
			"damage_reduction":
				ud.buff_damage_reduction += val


func _style_spin(sp : SpinBox, font_px : int):
	sp.add_theme_font_size_override("font_size", font_px)
	sp.ready.connect(func():
		if not is_instance_valid(sp): return
		var le := sp.get_line_edit()
		if le:
			le.add_theme_font_size_override("font_size", font_px)
		var up = sp.get_node_or_null("up")
		var dn = sp.get_node_or_null("down")
		if up: up.custom_minimum_size = Vector2(5, 4)
		if dn: dn.custom_minimum_size = Vector2(5, 4)
	, CONNECT_ONE_SHOT)
