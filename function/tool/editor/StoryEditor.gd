@tool
extends Control

# ============================================================
#  StoryEditor — NPC 剧情 / 独立对话 / 地图事件 统一编辑器
# ============================================================
#
#  [NPC 剧情]  → stories.json
#  [独立对话]  → dialogues.json
#  [地图事件]  → events.json
#
#  快捷键：Ctrl+S 保存 / Esc 退出
# ============================================================

const STORY_PATH : String = "res://content/data/stories.json"
const DIALOGUE_PATH : String = "res://content/data/dialogues.json"
const EVENT_PATH : String = "res://content/data/events.json"

const UNLOCK_TYPES : Array = ["unit", "relic", "aura", "route", "talent", "transform_branch"]
const NUM_CONDITIONS : Array = [
	"min_run_count", "min_altar_level", "min_initial_level",
	"min_weapon_max_level", "min_dispatch_count", "min_arena_clear",
	"min_dialogue_count"
]

# ---- ★ 全局尺寸（大幅压缩）----
const FS_BTN   : int = 6
const FS_TAB   : int = 7
const FS_LABEL : int = 6
const FS_SECT  : int = 6
const FS_HINT  : int = 5

const BTN_H    : int = 14
const ROW_H    : int = 14
const SPIN_W   : int = 40
const TAB_W    : int = 64
const TAB_H    : int = 20
const LEFT_W   : int = 90
const MID_W    : int = 140

# ---- 数据 ----
var _stories : Dictionary = {}
var _dialogues : Dictionary = {}
var _events : Dictionary = {}
var _dirty : bool = false

# ---- 当前选中 ----
var _tab : String = "stories"
var _current_npc : String = ""
var _current_dialogue_id : String = ""
var _current_unlock_idx : int = -1
var _current_flat_id : String = ""
var _current_event_id : String = ""
var _current_action_idx : int = -1

# ---- UI 引用 ----
var _tab_stories_btn : Button
var _tab_dialogues_btn : Button
var _tab_events_btn : Button
var _status_label : Label
var _left_title : Label
var _left_list : VBoxContainer
var _mid_title : Label
var _mid_list : VBoxContainer
var _right_title : Label
var _right_container : VBoxContainer


# ============================================================
#  生命周期
# ============================================================
func _ready():
	_setup_window()
	_build_ui()
	_load_all()
	_switch_tab("stories")


func _setup_window():
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return
	var cur_size = DisplayServer.window_get_size()
	if cur_size.x < 900 or cur_size.y < 500:
		DisplayServer.window_set_size(Vector2i(1100, 640))


func _build_ui():
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.10, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var main := VBoxContainer.new()
	main.name = "MainVBox"
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.offset_left = 4
	main.offset_top = 4
	main.offset_right = -4
	main.offset_bottom = -4
	main.add_theme_constant_override("separation", 3)
	add_child(main)

	# ----- TopBar -----
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.add_theme_constant_override("separation", 4)
	main.add_child(top)

	_tab_stories_btn = _mk_tab_button("NPC 剧情")
	_tab_stories_btn.pressed.connect(_switch_tab.bind("stories"))
	top.add_child(_tab_stories_btn)

	_tab_dialogues_btn = _mk_tab_button("独立对话")
	_tab_dialogues_btn.pressed.connect(_switch_tab.bind("dialogues"))
	top.add_child(_tab_dialogues_btn)

	_tab_events_btn = _mk_tab_button("地图事件")
	_tab_events_btn.pressed.connect(_switch_tab.bind("events"))
	top.add_child(_tab_events_btn)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)

	var save_btn := _mk_button("保存")
	save_btn.tooltip_text = "Ctrl+S"
	save_btn.custom_minimum_size = Vector2(40, BTN_H)
	save_btn.pressed.connect(_on_save)
	top.add_child(save_btn)

	var reload_btn := _mk_button("重载")
	reload_btn.custom_minimum_size = Vector2(40, BTN_H)
	reload_btn.pressed.connect(_on_reload)
	top.add_child(reload_btn)

	var quit_btn := _mk_button("退出")
	quit_btn.custom_minimum_size = Vector2(40, BTN_H)
	quit_btn.pressed.connect(_on_quit)
	top.add_child(quit_btn)

	# ----- Body: 嵌套 HSplitContainer -----
	var outer_split := HSplitContainer.new()
	outer_split.name = "OuterSplit"
	outer_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_split.split_offset = LEFT_W
	main.add_child(outer_split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(60, 0)
	left.add_theme_constant_override("separation", 2)
	outer_split.add_child(left)

	_left_title = Label.new()
	_left_title.add_theme_font_size_override("font_size", FS_SECT)
	_left_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left_title.text = "— —"
	left.add_child(_left_title)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(left_scroll)

	_left_list = VBoxContainer.new()
	_left_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_list.add_theme_constant_override("separation", 1)
	left_scroll.add_child(_left_list)

	var inner_split := HSplitContainer.new()
	inner_split.name = "InnerSplit"
	inner_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner_split.split_offset = MID_W
	outer_split.add_child(inner_split)

	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(80, 0)
	mid.add_theme_constant_override("separation", 2)
	inner_split.add_child(mid)

	_mid_title = Label.new()
	_mid_title.add_theme_font_size_override("font_size", FS_SECT)
	_mid_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mid_title.text = "— —"
	mid.add_child(_mid_title)

	var mid_scroll := ScrollContainer.new()
	mid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(mid_scroll)

	_mid_list = VBoxContainer.new()
	_mid_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mid_list.add_theme_constant_override("separation", 1)
	mid_scroll.add_child(_mid_list)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	right.add_theme_constant_override("separation", 2)
	inner_split.add_child(right)

	_right_title = Label.new()
	_right_title.add_theme_font_size_override("font_size", FS_SECT)
	_right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_title.text = "— 编辑区 —"
	_right_title.clip_text = true
	right.add_child(_right_title)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(right_scroll)

	_right_container = VBoxContainer.new()
	_right_container.name = "RightContainer"
	_right_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_container.add_theme_constant_override("separation", 3)
	right_scroll.add_child(_right_container)

	# ----- StatusBar -----
	var status_bar := PanelContainer.new()
	status_bar.custom_minimum_size = Vector2(0, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	status_bar.add_theme_stylebox_override("panel", sb)
	main.add_child(status_bar)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", FS_HINT)
	_status_label.modulate = Color(0.75, 0.9, 0.75)
	_status_label.text = "就绪"
	status_bar.add_child(_status_label)


# ============================================================
#  小工具
# ============================================================
func _mk_button(text : String, fs : int = FS_BTN) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", fs)
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 3
	empty.content_margin_right = 3
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("focus", empty)
	return b


func _mk_tab_button(text : String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", FS_TAB)
	b.custom_minimum_size = Vector2(TAB_W, TAB_H)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _mk_label(text : String, fs : int = FS_LABEL) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.clip_text = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _mk_line_edit(text : String, placeholder : String = "") -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.placeholder_text = placeholder
	le.add_theme_font_size_override("font_size", FS_BTN)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.custom_minimum_size = Vector2(30, ROW_H)
	return le


func _mk_spin(value : int, min_v : int, max_v : int) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = 1
	sp.value = value
	sp.custom_minimum_size = Vector2(SPIN_W, ROW_H)
	sp.size_flags_horizontal = Control.SIZE_SHRINK_END
	sp.add_theme_font_size_override("font_size", FS_BTN)
	sp.add_theme_constant_override("separation", 0)
	# ★ 立即 + 延迟双保险
	_setup_spin_internal(sp)
	sp.call_deferred("_ensure_internal_style") if false else null
	call_deferred("_setup_spin_internal", sp)
	return sp


func _setup_spin_internal(sp : SpinBox):
	if not is_instance_valid(sp): return
	var le := sp.get_line_edit()
	if le:
		le.add_theme_font_size_override("font_size", FS_BTN)
		le.custom_minimum_size = Vector2(0, ROW_H - 2)
		le.select_all_on_focus = true
		le.context_menu_enabled = false
	# 上下箭头压缩
	for path in ["up", "down"]:
		var btn : Control = sp.get_node_or_null(path)
		if btn:
			btn.custom_minimum_size = Vector2(8, ROW_H / 2)
			btn.size = Vector2(8, ROW_H / 2)


func _mk_checkbox(text : String, pressed : bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = pressed
	cb.add_theme_font_size_override("font_size", FS_LABEL)
	cb.clip_text = true
	cb.focus_mode = Control.FOCUS_NONE
	return cb


func _clear_container(node : Node):
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _set_status(text : String):
	if _status_label:
		_status_label.text = text


func _stretch_row_button(btn : Button):
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


# ============================================================
#  数据加载 / 保存
# ============================================================
func _load_all():
	_stories = _load_json(STORY_PATH)
	_dialogues = _load_json(DIALOGUE_PATH)
	_events = _load_json(EVENT_PATH)
	_dirty = false
	_set_status("已加载：%d NPC / %d 对话 / %d 事件" % [_stories.size(), _dialogues.size(), _events.size()])


func _load_json(path : String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if not (data is Dictionary): return {}
	return data


func _on_save():
	var ok := true
	if not _save_json(STORY_PATH, _stories): ok = false
	if not _save_json(DIALOGUE_PATH, _dialogues): ok = false
	if not _save_json(EVENT_PATH, _events): ok = false
	if ok:
		_dirty = false
		_set_status("✓ 已保存")


func _save_json(path : String, data : Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_set_status("✗ 无法写入：%s" % path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


func _on_reload():
	_load_all()
	_switch_tab(_tab)


func _on_quit():
	get_tree().quit()


# ============================================================
#  Tab 切换
# ============================================================
func _switch_tab(tab : String):
	_tab = tab
	_tab_stories_btn.button_pressed = (tab == "stories")
	_tab_dialogues_btn.button_pressed = (tab == "dialogues")
	_tab_events_btn.button_pressed = (tab == "events")
	_tab_stories_btn.modulate = Color.WHITE if tab == "stories" else Color(0.55, 0.55, 0.55, 1)
	_tab_dialogues_btn.modulate = Color.WHITE if tab == "dialogues" else Color(0.55, 0.55, 0.55, 1)
	_tab_events_btn.modulate = Color.WHITE if tab == "events" else Color(0.55, 0.55, 0.55, 1)

	_clear_container(_left_list)
	_clear_container(_mid_list)
	_clear_container(_right_container)

	match tab:
		"stories":
			_left_title.text = "NPC"
			_mid_title.text = "对话 / 解锁"
			_right_title.text = "— 编辑区 —"
			_build_npc_list()
		"dialogues":
			_left_title.text = "对话 ID"
			_mid_title.text = "—"
			_right_title.text = "— 编辑区 —"
			_build_flat_id_list()
		"events":
			_left_title.text = "事件 ID"
			_mid_title.text = "actions"
			_right_title.text = "— 编辑区 —"
			_build_event_id_list()


# ============================================================
#  Tab 1 · NPC 剧情
# ============================================================
func _build_npc_list():
	for npc_id in _stories:
		var npc : Dictionary = _stories[npc_id]
		var btn := _mk_button("%s (%s)" % [npc_id, npc.get("name", "")])
		_stretch_row_button(btn)
		btn.toggle_mode = true
		btn.button_pressed = (npc_id == _current_npc)
		btn.modulate = Color.WHITE if npc_id == _current_npc else Color(0.75, 0.75, 0.75, 1)
		btn.pressed.connect(_on_npc_selected.bind(npc_id))
		_left_list.add_child(btn)

	if _current_npc == "" or not _stories.has(_current_npc):
		var first_key = _stories.keys()[0] if _stories.size() > 0 else ""
		if first_key != "":
			_on_npc_selected(first_key)


func _on_npc_selected(npc_id : String):
	_current_npc = npc_id
	_current_dialogue_id = ""
	_current_unlock_idx = -1

	for child in _left_list.get_children():
		if child is Button:
			var t : String = child.text
			child.modulate = Color.WHITE if t.begins_with(npc_id + " ") else Color(0.75, 0.75, 0.75, 1)

	_build_mid_list()
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"


func _build_mid_list():
	_clear_container(_mid_list)
	if _current_npc == "" or not _stories.has(_current_npc): return
	var npc : Dictionary = _stories[_current_npc]

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 3)
	_mid_list.add_child(add_row)

	var add_dlg := _mk_button("+ 对话")
	add_dlg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_dlg.pressed.connect(_add_new_dialogue)
	add_row.add_child(add_dlg)

	var add_unlock := _mk_button("+ 解锁")
	add_unlock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_unlock.pressed.connect(_add_new_unlock)
	add_row.add_child(add_unlock)

	var dlg_title := _mk_label("— dialogues —", FS_SECT)
	dlg_title.modulate = Color(0.6, 0.7, 0.9)
	_mid_list.add_child(dlg_title)

	var dialogues : Array = npc.get("dialogues", [])
	for i in range(dialogues.size()):
		var d : Dictionary = dialogues[i]
		var did : String = d.get("id", "?")
		var pri : int = int(d.get("priority", 0))
		var btn := _mk_button("%s (p%d)" % [did, pri])
		_stretch_row_button(btn)
		btn.toggle_mode = true
		btn.button_pressed = (did == _current_dialogue_id)
		btn.modulate = Color.WHITE if did == _current_dialogue_id else Color(0.8, 0.8, 0.8, 1)
		btn.pressed.connect(_on_dialogue_selected.bind(did))
		_mid_list.add_child(btn)

	var unl_title := _mk_label("— unlocks —", FS_SECT)
	unl_title.modulate = Color(0.9, 0.7, 0.5)
	_mid_list.add_child(unl_title)

	var unlocks : Array = npc.get("unlocks", [])
	if unlocks.is_empty():
		var lb := _mk_label("（无）")
		lb.modulate = Color(0.55, 0.55, 0.55)
		_mid_list.add_child(lb)
	else:
		for i in range(unlocks.size()):
			var u : Dictionary = unlocks[i]
			var utype : String = u.get("type", "?")
			var uid : String = u.get("id", "?")
			var display : String = _get_unlock_display_name(utype, uid)
			var btn := _mk_button("[%s] %s" % [utype, display])
			_stretch_row_button(btn)
			btn.toggle_mode = true
			btn.button_pressed = (i == _current_unlock_idx)
			btn.modulate = Color.WHITE if i == _current_unlock_idx else Color(0.8, 0.8, 0.8, 1)
			btn.pressed.connect(_on_unlock_selected.bind(i))
			_mid_list.add_child(btn)


func _on_dialogue_selected(dialogue_id : String):
	_current_dialogue_id = dialogue_id
	_current_unlock_idx = -1
	_build_mid_list()
	_build_dialogue_form()


func _on_unlock_selected(idx : int):
	_current_unlock_idx = idx
	_current_dialogue_id = ""
	_build_mid_list()
	_build_unlock_form()


# ============================================================
#  Dialogue 编辑
# ============================================================
func _build_dialogue_form():
	_clear_container(_right_container)
	if _current_npc == "" or _current_dialogue_id == "": return

	var d : Dictionary = _find_dialogue(_current_npc, _current_dialogue_id)
	if d.is_empty(): return

	_right_title.text = "编辑：" + _current_dialogue_id

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 3)
	_right_container.add_child(head_row)

	var preview_btn := _mk_button("▶ 预览")
	preview_btn.pressed.connect(_preview_dialogue.bind(d))
	head_row.add_child(preview_btn)

	var delete_btn := _mk_button("× 删除")
	delete_btn.modulate = Color(1.0, 0.6, 0.6)
	delete_btn.pressed.connect(_delete_current_dialogue)
	head_row.add_child(delete_btn)

	var id_row := _mk_row("ID")
	var id_edit := _mk_line_edit(_current_dialogue_id)
	id_edit.text_submitted.connect(func(new_id):
		_rename_dialogue_id(_current_dialogue_id, new_id)
	)
	id_row.add_child(id_edit)

	var pri_row := _mk_row("priority")
	var pri_spin := _mk_spin(int(d.get("priority", 0)), -100, 100)
	pri_spin.value_changed.connect(func(v):
		d["priority"] = int(v)
		_dirty = true
		_build_mid_list()
	)
	pri_row.add_child(pri_spin)

	_right_container.add_child(_mk_section_label("— condition —"))
	_build_condition_editor(d.get("condition", {}), func(new_cond):
		if new_cond.is_empty():
			d.erase("condition")
		else:
			d["condition"] = new_cond
		_dirty = true
	)

	_right_container.add_child(_mk_section_label("— lines —"))
	_build_lines_editor(d)

	_right_container.add_child(_mk_section_label("— choices —"))
	_build_choices_editor(d)


func _mk_row(label_text : String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_right_container.add_child(row)
	var lb := _mk_label(label_text, FS_LABEL)
	lb.custom_minimum_size = Vector2(55, 0)
	row.add_child(lb)
	return row


func _mk_section_label(text : String) -> Label:
	var l := _mk_label(text, FS_SECT)
	l.modulate = Color(0.75, 0.85, 0.95)
	return l


func _find_dialogue(npc_id : String, dialogue_id : String) -> Dictionary:
	if not _stories.has(npc_id): return {}
	var dialogues : Array = _stories[npc_id].get("dialogues", [])
	for d in dialogues:
		if d is Dictionary and d.get("id", "") == dialogue_id:
			return d
	return {}


func _rename_dialogue_id(old_id : String, new_id : String):
	if new_id == "" or new_id == old_id: return
	if not _stories.has(_current_npc): return
	var dialogues : Array = _stories[_current_npc].get("dialogues", [])
	for d in dialogues:
		if d is Dictionary and d.get("id", "") == old_id:
			d["id"] = new_id
			_current_dialogue_id = new_id
			_dirty = true
			_set_status("重命名：%s → %s" % [old_id, new_id])
			_build_mid_list()
			_build_dialogue_form()
			return


func _delete_current_dialogue():
	if _current_npc == "" or _current_dialogue_id == "": return
	if not _stories.has(_current_npc): return
	var dialogues : Array = _stories[_current_npc].get("dialogues", [])
	for i in range(dialogues.size()):
		if dialogues[i] is Dictionary and dialogues[i].get("id", "") == _current_dialogue_id:
			dialogues.remove_at(i)
			_dirty = true
			_current_dialogue_id = ""
			_build_mid_list()
			_clear_container(_right_container)
			_right_title.text = "— 编辑区 —"
			_set_status("已删除对话")
			return


func _add_new_dialogue():
	if _current_npc == "": return
	if not _stories.has(_current_npc): return
	var npc : Dictionary = _stories[_current_npc]
	if not npc.has("dialogues"):
		npc["dialogues"] = []
	var new_id : String = "new_dialogue_%d" % (Time.get_ticks_msec() % 100000)
	npc["dialogues"].append({
		"id": new_id,
		"priority": 0,
		"lines": [{"speaker": "???", "text": "..."}]
	})
	_dirty = true
	_current_dialogue_id = new_id
	_current_unlock_idx = -1
	_build_mid_list()
	_build_dialogue_form()
	_set_status("新建对话：" + new_id)


# ============================================================
#  Unlock 编辑
# ============================================================
func _build_unlock_form():
	_clear_container(_right_container)
	if _current_npc == "" or _current_unlock_idx < 0: return
	var npc : Dictionary = _stories.get(_current_npc, {})
	var unlocks : Array = npc.get("unlocks", [])
	if _current_unlock_idx >= unlocks.size(): return
	var u : Dictionary = unlocks[_current_unlock_idx]

	_right_title.text = "编辑解锁 #%d" % _current_unlock_idx

	var type_row := _mk_row("type")
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", FS_BTN)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size = Vector2(70, ROW_H)
	for i in range(UNLOCK_TYPES.size()):
		opt.add_item(UNLOCK_TYPES[i], i)
		if UNLOCK_TYPES[i] == u.get("type", ""):
			opt.selected = i
	opt.item_selected.connect(func(idx):
		u["type"] = UNLOCK_TYPES[idx]
		u["id"] = ""
		_dirty = true
		_build_mid_list()
		_build_unlock_form()
	)
	type_row.add_child(opt)

	var id_row := _mk_row("id")
	var id_editor : Control = _build_unlock_id_editor(u)
	id_row.add_child(id_editor)

	_right_container.add_child(_mk_section_label("— conditions —"))
	_build_condition_editor(u.get("conditions", {}), func(new_cond):
		if new_cond.is_empty():
			u.erase("conditions")
		else:
			u["conditions"] = new_cond
		_dirty = true
	)

	var delete_btn := _mk_button("× 删除此解锁")
	delete_btn.modulate = Color(1.0, 0.6, 0.6)
	delete_btn.pressed.connect(_delete_current_unlock)
	_right_container.add_child(delete_btn)


func _build_unlock_id_editor(u : Dictionary) -> Control:
	var utype : String = u.get("type", "")
	var candidates : Array = _get_candidates_for_type(utype)
	var cur_id : String = str(u.get("id", ""))

	if candidates.is_empty():
		var le := _mk_line_edit(cur_id, "（无候选，手打）")
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_changed.connect(func(t):
			u["id"] = t
			_dirty = true
			_build_mid_list()
		)
		return le

	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", FS_BTN)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size = Vector2(70, ROW_H)
	opt.clip_text = true

	opt.add_item("（选择…）", 0)
	opt.set_item_metadata(0, "")
	var matched : bool = (cur_id == "")

	for i in range(candidates.size()):
		var c : Dictionary = candidates[i]
		var cid : String = str(c.get("id", ""))
		var cname : String = str(c.get("name", cid))
		var text : String = "%s  (%s)" % [cname, cid]
		opt.add_item(text, i + 1)
		opt.set_item_metadata(i + 1, cid)
		if cid == cur_id:
			opt.selected = i + 1
			matched = true

	if not matched and cur_id != "":
		opt.add_item("（当前）" + cur_id, candidates.size() + 1)
		opt.set_item_metadata(candidates.size() + 1, cur_id)
		opt.selected = candidates.size() + 1

	opt.item_selected.connect(func(idx):
		var new_id = opt.get_item_metadata(idx)
		if new_id == null: new_id = ""
		u["id"] = str(new_id)
		_dirty = true
		_build_mid_list()
	)
	return opt


func _get_candidates_for_type(utype : String) -> Array:
	var arr : Array = []
	match utype:
		"unit":
			for key in UnitDataManager.get_all_unit_ids():
				arr.append({"id": key, "name": UnitDataManager.get_display_name(key)})
		"relic":
			for rid in RelicManager.get_all_relic_ids():
				var d : Dictionary = RelicManager.get_relic_data(rid)
				arr.append({"id": rid, "name": d.get("name", rid)})
		"aura":
			for aid in AuraManager.get_all_ids():
				arr.append({"id": aid, "name": AuraManager.get_display_name(aid)})
		"route":
			for rid in DispatchManager.ROUTES:
				var route : Dictionary = DispatchManager.ROUTES[rid]
				arr.append({"id": rid, "name": route.get("name", rid)})
		"talent":
			for tid in TalentManager.get_all_talent_ids():
				var d = TalentManager.get_talent_data(tid)
				if d:
					arr.append({"id": tid, "name": d.display_name})
		"transform_branch":
			for unit_key in UnitDataManager.get_all_unit_ids():
				var data : Dictionary = UnitDataManager.get_unit_data(unit_key)
				var branches : Variant = data.get("advanced_branches", [])
				if branches is Array:
					for b in branches:
						if b is Dictionary:
							arr.append({
								"id": b.get("id", ""),
								"name": "%s (%s)" % [b.get("name", "?"), unit_key]
							})
	return arr


func _get_unlock_display_name(utype : String, uid : String) -> String:
	match utype:
		"unit":
			return "%s (%s)" % [UnitDataManager.get_display_name(uid), uid]
		"relic":
			var d : Dictionary = RelicManager.get_relic_data(uid)
			if d.is_empty(): return uid
			return "%s (%s)" % [d.get("name", uid), uid]
		"aura":
			return "%s (%s)" % [AuraManager.get_display_name(uid), uid]
		"route":
			var r : Dictionary = DispatchManager.ROUTES.get(uid, {})
			if r.is_empty(): return uid
			return "%s (%s)" % [r.get("name", uid), uid]
		"talent":
			var d = TalentManager.get_talent_data(uid)
			if d == null: return uid
			return "%s (%s)" % [d.display_name, uid]
		"transform_branch":
			return uid
	return uid


func _delete_current_unlock():
	if _current_npc == "" or _current_unlock_idx < 0: return
	var npc : Dictionary = _stories.get(_current_npc, {})
	var unlocks : Array = npc.get("unlocks", [])
	if _current_unlock_idx >= unlocks.size(): return
	unlocks.remove_at(_current_unlock_idx)
	_dirty = true
	_current_unlock_idx = -1
	_build_mid_list()
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"
	_set_status("已删除解锁")


func _add_new_unlock():
	if _current_npc == "": return
	if not _stories.has(_current_npc): return
	var npc : Dictionary = _stories[_current_npc]
	if not npc.has("unlocks"):
		npc["unlocks"] = []
	npc["unlocks"].append({
		"type": "route",
		"id": "",
		"conditions": {}
	})
	_dirty = true
	_current_unlock_idx = npc["unlocks"].size() - 1
	_current_dialogue_id = ""
	_build_mid_list()
	_build_unlock_form()
	_set_status("新建解锁")


# ============================================================
#  Condition 编辑器
# ============================================================
func _build_condition_editor(cond : Dictionary, on_change : Callable):
	var work : Dictionary = cond.duplicate(true)

	for key in NUM_CONDITIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		_right_container.add_child(row)

		var cb := _mk_checkbox(key, work.has(key))
		cb.custom_minimum_size = Vector2(110, ROW_H)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cb)

		var sp := _mk_spin(int(work.get(key, 0)), 0, 999)
		sp.editable = work.has(key)
		sp.value_changed.connect(func(v):
			work[key] = int(v)
			on_change.call(work)
		)
		row.add_child(sp)

		cb.toggled.connect(func(pressed):
			sp.editable = pressed
			if pressed:
				work[key] = int(sp.value)
			else:
				work.erase(key)
			on_change.call(work)
		)

	# after_dialogue
	var ad_row := HBoxContainer.new()
	ad_row.add_theme_constant_override("separation", 3)
	_right_container.add_child(ad_row)

	var ad_cb := _mk_checkbox("after_dialogue", work.has("after_dialogue"))
	ad_cb.custom_minimum_size = Vector2(110, ROW_H)
	ad_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ad_row.add_child(ad_cb)

	var dialogue_ids : Array = []
	if _current_npc != "" and _stories.has(_current_npc):
		var dlist : Array = _stories[_current_npc].get("dialogues", [])
		for d in dlist:
			if d is Dictionary:
				var did : String = d.get("id", "")
				if did != "": dialogue_ids.append(did)

	var cur_ad : String = str(work.get("after_dialogue", ""))

	var ad_opt := OptionButton.new()
	ad_opt.add_theme_font_size_override("font_size", FS_BTN)
	ad_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ad_opt.custom_minimum_size = Vector2(70, ROW_H)
	ad_opt.clip_text = true
	ad_opt.disabled = not work.has("after_dialogue")

	ad_opt.add_item("（选择）", 0)
	ad_opt.set_item_metadata(0, "")
	var matched : bool = (cur_ad == "")
	for i in range(dialogue_ids.size()):
		var did : String = dialogue_ids[i]
		ad_opt.add_item(did, i + 1)
		ad_opt.set_item_metadata(i + 1, did)
		if did == cur_ad:
			ad_opt.selected = i + 1
			matched = true
	if not matched and cur_ad != "":
		ad_opt.add_item("（当前）" + cur_ad, dialogue_ids.size() + 1)
		ad_opt.set_item_metadata(dialogue_ids.size() + 1, cur_ad)
		ad_opt.selected = dialogue_ids.size() + 1

	ad_opt.item_selected.connect(func(idx):
		var new_id = ad_opt.get_item_metadata(idx)
		if new_id == null: new_id = ""
		work["after_dialogue"] = str(new_id)
		on_change.call(work)
	)
	ad_row.add_child(ad_opt)

	ad_cb.toggled.connect(func(pressed):
		ad_opt.disabled = not pressed
		if pressed:
			var sel = ad_opt.get_item_metadata(ad_opt.selected)
			if sel == null: sel = ""
			work["after_dialogue"] = str(sel)
		else:
			work.erase("after_dialogue")
		on_change.call(work)
	)

	# flags
	var flags_label := _mk_label("flags（逗号分隔）:")
	flags_label.modulate = Color(0.8, 0.8, 0.8)
	_right_container.add_child(flags_label)

	var flags_row := HBoxContainer.new()
	flags_row.add_theme_constant_override("separation", 3)
	_right_container.add_child(flags_row)

	var flags_arr : Array = work.get("flags", [])
	var flags_text : String = ""
	for f in flags_arr: flags_text += str(f) + ","
	flags_text = flags_text.trim_suffix(",")

	var flags_edit := _mk_line_edit(flags_text, "keeper_asked_why, xxx")
	flags_edit.text_changed.connect(func(t):
		var parts : Array = []
		for p in t.split(",", false):
			var s : String = p.strip_edges()
			if s != "": parts.append(s)
		if parts.is_empty():
			work.erase("flags")
		else:
			work["flags"] = parts
		on_change.call(work)
	)
	flags_row.add_child(flags_edit)


# ============================================================
#  Lines 编辑
# ============================================================
func _build_lines_editor(d : Dictionary):
	var lines : Array = d.get("lines", [])

	for i in range(lines.size()):
		var line : Dictionary = lines[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_right_container.add_child(row)

		var speaker_edit := _mk_line_edit(str(line.get("speaker", "")), "说话者")
		speaker_edit.custom_minimum_size = Vector2(40, ROW_H)
		speaker_edit.size_flags_horizontal = Control.SIZE_FILL
		speaker_edit.text_changed.connect(func(t):
			line["speaker"] = t
			_dirty = true
		)
		row.add_child(speaker_edit)

		var text_edit := _mk_line_edit(str(line.get("text", "")), "台词")
		text_edit.text_changed.connect(func(t):
			line["text"] = t
			_dirty = true
		)
		row.add_child(text_edit)

		var idx : int = i
		var up := _mk_button("↑")
		up.custom_minimum_size = Vector2(16, ROW_H)
		up.pressed.connect(_move_line.bind(d, idx, -1))
		row.add_child(up)

		var dn := _mk_button("↓")
		dn.custom_minimum_size = Vector2(16, ROW_H)
		dn.pressed.connect(_move_line.bind(d, idx, 1))
		row.add_child(dn)

		var del := _mk_button("×")
		del.custom_minimum_size = Vector2(16, ROW_H)
		del.modulate = Color(1.0, 0.6, 0.6)
		del.pressed.connect(_delete_line.bind(d, idx))
		row.add_child(del)

	var add_line_btn := _mk_button("+ 添加台词")
	add_line_btn.pressed.connect(func():
		if not d.has("lines"): d["lines"] = []
		d["lines"].append({"speaker": "???", "text": ""})
		_dirty = true
		_build_dialogue_form()
	)
	_right_container.add_child(add_line_btn)


func _move_line(d : Dictionary, idx : int, dir : int):
	var lines : Array = d.get("lines", [])
	var new_idx : int = idx + dir
	if new_idx < 0 or new_idx >= lines.size(): return
	var tmp = lines[idx]
	lines[idx] = lines[new_idx]
	lines[new_idx] = tmp
	_dirty = true
	_build_dialogue_form()


func _delete_line(d : Dictionary, idx : int):
	var lines : Array = d.get("lines", [])
	if idx < 0 or idx >= lines.size(): return
	lines.remove_at(idx)
	_dirty = true
	_build_dialogue_form()


# ============================================================
#  Choices 编辑
# ============================================================
func _build_choices_editor(d : Dictionary):
	if not d.has("choices"):
		var init_btn := _mk_button("+ 添加选项")
		init_btn.pressed.connect(func():
			d["choices"] = [{"text": "", "flag": ""}]
			_dirty = true
			_build_dialogue_form()
		)
		_right_container.add_child(init_btn)
		return

	var choices : Array = d["choices"]
	for i in range(choices.size()):
		var c : Dictionary = choices[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_right_container.add_child(row)

		var text_edit := _mk_line_edit(str(c.get("text", "")), "选项文本")
		text_edit.text_changed.connect(func(t):
			c["text"] = t
			_dirty = true
		)
		row.add_child(text_edit)

		var flag_edit := _mk_line_edit(str(c.get("flag", "")), "flag")
		flag_edit.custom_minimum_size = Vector2(70, ROW_H)
		flag_edit.size_flags_horizontal = Control.SIZE_FILL
		flag_edit.text_changed.connect(func(t):
			c["flag"] = t
			_dirty = true
		)
		row.add_child(flag_edit)

		var idx : int = i
		var del := _mk_button("×")
		del.custom_minimum_size = Vector2(16, ROW_H)
		del.modulate = Color(1.0, 0.6, 0.6)
		del.pressed.connect(func():
			choices.remove_at(idx)
			if choices.is_empty(): d.erase("choices")
			_dirty = true
			_build_dialogue_form()
		)
		row.add_child(del)

	var add_choice_btn := _mk_button("+ 添加选项")
	add_choice_btn.pressed.connect(func():
		choices.append({"text": "", "flag": ""})
		_dirty = true
		_build_dialogue_form()
	)
	_right_container.add_child(add_choice_btn)


# ============================================================
#  Tab 2 · 独立对话
# ============================================================
func _build_flat_id_list():
	for id in _dialogues:
		var btn := _mk_button(id)
		_stretch_row_button(btn)
		btn.toggle_mode = true
		btn.button_pressed = (id == _current_flat_id)
		btn.modulate = Color.WHITE if id == _current_flat_id else Color(0.75, 0.75, 0.75, 1)
		btn.pressed.connect(_on_flat_id_selected.bind(id))
		_left_list.add_child(btn)

	var new_btn := _mk_button("+ 新对话")
	new_btn.pressed.connect(_add_new_flat_dialogue)
	_left_list.add_child(new_btn)

	if _current_flat_id == "" or not _dialogues.has(_current_flat_id):
		var first_key = _dialogues.keys()[0] if _dialogues.size() > 0 else ""
		if first_key != "":
			_on_flat_id_selected(first_key)


func _on_flat_id_selected(id : String):
	_current_flat_id = id
	for child in _left_list.get_children():
		if child is Button:
			child.modulate = Color.WHITE if child.text == id else Color(0.75, 0.75, 0.75, 1)
	_build_flat_form()


func _build_flat_form():
	_clear_container(_right_container)
	if _current_flat_id == "" or not _dialogues.has(_current_flat_id): return

	_right_title.text = "对话：" + _current_flat_id

	var lines : Array = _dialogues[_current_flat_id]

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 3)
	_right_container.add_child(head_row)

	var preview_btn := _mk_button("▶ 预览")
	preview_btn.pressed.connect(func():
		DialogueManager.start_inline_dialogue(lines)
	)
	head_row.add_child(preview_btn)

	var del_dlg := _mk_button("× 删除此对话")
	del_dlg.modulate = Color(1.0, 0.6, 0.6)
	del_dlg.pressed.connect(_delete_flat_dialogue)
	head_row.add_child(del_dlg)

	for i in range(lines.size()):
		var line : Dictionary = lines[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_right_container.add_child(row)

		var sp_edit := _mk_line_edit(str(line.get("speaker", "")), "说话者")
		sp_edit.custom_minimum_size = Vector2(40, ROW_H)
		sp_edit.size_flags_horizontal = Control.SIZE_FILL
		sp_edit.text_changed.connect(func(t):
			line["speaker"] = t
			_dirty = true
		)
		row.add_child(sp_edit)

		var tx_edit := _mk_line_edit(str(line.get("text", "")), "台词")
		tx_edit.text_changed.connect(func(t):
			line["text"] = t
			_dirty = true
		)
		row.add_child(tx_edit)

		var idx : int = i
		var del := _mk_button("×")
		del.custom_minimum_size = Vector2(16, ROW_H)
		del.modulate = Color(1.0, 0.6, 0.6)
		del.pressed.connect(func():
			lines.remove_at(idx)
			_dirty = true
			_build_flat_form()
		)
		row.add_child(del)

	var add_line_btn := _mk_button("+ 添加台词")
	add_line_btn.pressed.connect(func():
		lines.append({"speaker": "???", "text": ""})
		_dirty = true
		_build_flat_form()
	)
	_right_container.add_child(add_line_btn)


func _add_new_flat_dialogue():
	var new_id : String = "new_dialogue_%d" % (Time.get_ticks_msec() % 100000)
	_dialogues[new_id] = [{"speaker": "???", "text": "..."}]
	_dirty = true
	_current_flat_id = new_id
	_clear_container(_left_list)
	_build_flat_id_list()
	_build_flat_form()
	_set_status("新建独立对话：" + new_id)


func _delete_flat_dialogue():
	if _current_flat_id == "": return
	_dialogues.erase(_current_flat_id)
	_dirty = true
	_current_flat_id = ""
	_clear_container(_left_list)
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"
	_build_flat_id_list()


# ============================================================
#  Tab 3 · 地图事件
# ============================================================
func _build_event_id_list():
	for eid in _events:
		var btn := _mk_button(eid)
		_stretch_row_button(btn)
		btn.toggle_mode = true
		btn.button_pressed = (eid == _current_event_id)
		btn.modulate = Color.WHITE if eid == _current_event_id else Color(0.75, 0.75, 0.75, 1)
		btn.pressed.connect(_on_event_selected.bind(eid))
		_left_list.add_child(btn)

	var new_btn := _mk_button("+ 新事件")
	new_btn.pressed.connect(_add_new_event)
	_left_list.add_child(new_btn)

	if _current_event_id == "" or not _events.has(_current_event_id):
		var first_key = _events.keys()[0] if _events.size() > 0 else ""
		if first_key != "":
			_on_event_selected(first_key)


func _on_event_selected(event_id : String):
	_current_event_id = event_id
	_current_action_idx = -1
	for child in _left_list.get_children():
		if child is Button:
			child.modulate = Color.WHITE if child.text == event_id else Color(0.75, 0.75, 0.75, 1)
	_build_event_action_list()
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"


func _build_event_action_list():
	_clear_container(_mid_list)
	if _current_event_id == "" or not _events.has(_current_event_id): return
	var ev : Dictionary = _events[_current_event_id]

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 3)
	_mid_list.add_child(add_row)

	var add_action_btn := _mk_button("+ action")
	add_action_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_action_btn.pressed.connect(_add_new_action)
	add_row.add_child(add_action_btn)

	var once_cb := _mk_checkbox("once", bool(ev.get("once", true)))
	once_cb.toggled.connect(func(pressed):
		ev["once"] = pressed
		_dirty = true
	)
	add_row.add_child(once_cb)

	var act_title := _mk_label("— actions —", FS_SECT)
	act_title.modulate = Color(0.6, 0.7, 0.9)
	_mid_list.add_child(act_title)

	var actions : Array = ev.get("actions", [])
	for i in range(actions.size()):
		var a : Dictionary = actions[i]
		var atype : String = a.get("type", "?")
		var extra : String = ""
		if atype == "dialog": extra = a.get("dialog_id", "")
		elif atype == "give_item": extra = a.get("item_id", "")
		elif atype == "heal" or atype == "damage": extra = str(a.get("amount", 0))
		elif atype == "unlock_unit":
			var units : Array = a.get("units", [])
			extra = ",".join(units) if not units.is_empty() else ""
		var btn := _mk_button("%d. [%s] %s" % [i, atype, extra])
		_stretch_row_button(btn)
		btn.toggle_mode = true
		btn.button_pressed = (i == _current_action_idx)
		btn.modulate = Color.WHITE if i == _current_action_idx else Color(0.8, 0.8, 0.8, 1)
		btn.pressed.connect(_on_action_selected.bind(i))
		_mid_list.add_child(btn)


func _on_action_selected(idx : int):
	_current_action_idx = idx
	_build_event_action_list()
	_build_action_form()


func _add_new_action():
	if _current_event_id == "": return
	var ev : Dictionary = _events[_current_event_id]
	if not ev.has("actions"):
		ev["actions"] = []
	ev["actions"].append({"type": "dialog", "dialog_id": ""})
	_dirty = true
	_current_action_idx = ev["actions"].size() - 1
	_build_event_action_list()
	_build_action_form()
	_set_status("新建 action")


const ACTION_TYPES : Array = [
	"dialog", "give_item", "heal", "damage", "wait",
	"complete", "unlock_unit", "unlock_talent",
	"unlock_equipment", "unlock_relics",
]

func _build_action_form():
	_clear_container(_right_container)
	if _current_event_id == "" or _current_action_idx < 0: return
	var ev : Dictionary = _events.get(_current_event_id, {})
	var actions : Array = ev.get("actions", [])
	if _current_action_idx >= actions.size(): return
	var a : Dictionary = actions[_current_action_idx]

	_right_title.text = "action #%d" % _current_action_idx

	var type_row := _mk_row("type")
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", FS_BTN)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size = Vector2(70, ROW_H)
	var cur_type : String = a.get("type", "dialog")
	var matched : bool = false
	for i in range(ACTION_TYPES.size()):
		opt.add_item(ACTION_TYPES[i], i)
		if ACTION_TYPES[i] == cur_type:
			opt.selected = i
			matched = true
	if not matched:
		opt.add_item(cur_type + "（自定义）", ACTION_TYPES.size())
		opt.selected = ACTION_TYPES.size()
	opt.item_selected.connect(func(idx):
		if idx < ACTION_TYPES.size():
			a["type"] = ACTION_TYPES[idx]
		_dirty = true
		_build_event_action_list()
		_build_action_form()
	)
	type_row.add_child(opt)

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 3)
	_right_container.add_child(head_row)

	var up_btn := _mk_button("↑ 上移")
	up_btn.pressed.connect(_move_action.bind(-1))
	head_row.add_child(up_btn)

	var dn_btn := _mk_button("↓ 下移")
	dn_btn.pressed.connect(_move_action.bind(1))
	head_row.add_child(dn_btn)

	var del_btn := _mk_button("× 删除")
	del_btn.modulate = Color(1.0, 0.6, 0.6)
	del_btn.pressed.connect(_delete_current_action)
	head_row.add_child(del_btn)

	_right_container.add_child(_mk_section_label("— 字段 —"))
	_build_dynamic_fields_editor(a)


func _move_action(dir : int):
	if _current_event_id == "" or _current_action_idx < 0: return
	var ev : Dictionary = _events[_current_event_id]
	var actions : Array = ev.get("actions", [])
	var new_idx : int = _current_action_idx + dir
	if new_idx < 0 or new_idx >= actions.size(): return
	var tmp = actions[_current_action_idx]
	actions[_current_action_idx] = actions[new_idx]
	actions[new_idx] = tmp
	_current_action_idx = new_idx
	_dirty = true
	_build_event_action_list()
	_build_action_form()


func _delete_current_action():
	if _current_event_id == "" or _current_action_idx < 0: return
	var ev : Dictionary = _events[_current_event_id]
	var actions : Array = ev.get("actions", [])
	if _current_action_idx >= actions.size(): return
	actions.remove_at(_current_action_idx)
	_dirty = true
	_current_action_idx = -1
	_build_event_action_list()
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"
	_set_status("已删除 action")


func _build_dynamic_fields_editor(a : Dictionary):
	var priority : Array = [
		"dialog_id", "item_id", "count", "equip",
		"amount", "seconds",
		"units", "talent_id", "relic_id", "relic_ids",
		"music"
	]
	var visited : Dictionary = {"type": true}
	for key in priority:
		if a.has(key):
			_build_one_field_row(a, key)
			visited[key] = true
	for key in a:
		if not visited.has(key):
			_build_one_field_row(a, key)

	_right_container.add_child(_mk_section_label("— 添加字段 —"))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 3)
	_right_container.add_child(add_row)

	var key_edit := _mk_line_edit("", "字段名")
	key_edit.custom_minimum_size = Vector2(60, ROW_H)
	key_edit.size_flags_horizontal = Control.SIZE_FILL
	add_row.add_child(key_edit)

	var val_edit := _mk_line_edit("", "值")
	add_row.add_child(val_edit)

	var add_btn := _mk_button("+")
	add_btn.custom_minimum_size = Vector2(20, ROW_H)
	add_btn.pressed.connect(func():
		var k : String = key_edit.text.strip_edges()
		var v : String = val_edit.text
		if k == "" or k == "type": return
		a[k] = _auto_parse_value(v)
		_dirty = true
		_build_event_action_list()
		_build_action_form()
	)
	add_row.add_child(add_btn)


func _auto_parse_value(v : String) -> Variant:
	var s : String = v.strip_edges()
	if s == "": return ""
	if s == "true": return true
	if s == "false": return false
	if s.is_valid_int(): return int(s)
	if s.is_valid_float(): return float(s)
	if s.contains(","):
		var arr : Array = []
		for p in s.split(",", false):
			var ps : String = p.strip_edges()
			if ps == "": continue
			if ps.is_valid_int(): arr.append(int(ps))
			else: arr.append(ps)
		return arr
	return s


func _build_one_field_row(a : Dictionary, key : String):
	var value : Variant = a[key]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_right_container.add_child(row)

	var lb := _mk_label(key, FS_LABEL)
	lb.custom_minimum_size = Vector2(60, 0)
	lb.tooltip_text = key
	row.add_child(lb)

	var t : int = typeof(value)
	if t == TYPE_BOOL:
		var cb := _mk_checkbox("", bool(value))
		cb.toggled.connect(func(pressed):
			a[key] = pressed
			_dirty = true
		)
		row.add_child(cb)
	elif t == TYPE_INT:
		var sp := _mk_spin(int(value), -99999, 99999)
		sp.value_changed.connect(func(v):
			a[key] = int(v)
			_dirty = true
			_build_event_action_list()
		)
		row.add_child(sp)
	elif t == TYPE_FLOAT:
		var le := _mk_line_edit(str(value))
		le.text_changed.connect(func(s):
			if s.is_valid_float(): a[key] = float(s)
			_dirty = true
		)
		row.add_child(le)
	elif t == TYPE_ARRAY:
		var arr_text : String = ""
		for x in value: arr_text += str(x) + ","
		arr_text = arr_text.trim_suffix(",")
		var le := _mk_line_edit(arr_text, "逗号分隔")
		le.text_changed.connect(func(s):
			var parts : Array = []
			for p in s.split(",", false):
				var ps : String = p.strip_edges()
				if ps == "": continue
				if ps.is_valid_int(): parts.append(int(ps))
				else: parts.append(ps)
			a[key] = parts
			_dirty = true
			_build_event_action_list()
		)
		row.add_child(le)
	else:
		var le := _mk_line_edit(str(value))
		le.text_changed.connect(func(s):
			a[key] = s
			_dirty = true
			_build_event_action_list()
		)
		row.add_child(le)

	var del := _mk_button("×")
	del.custom_minimum_size = Vector2(16, ROW_H)
	del.modulate = Color(1.0, 0.6, 0.6)
	del.pressed.connect(func():
		a.erase(key)
		_dirty = true
		_build_event_action_list()
		_build_action_form()
	)
	row.add_child(del)


func _add_new_event():
	var new_id : String = "new_event_%d" % (Time.get_ticks_msec() % 100000)
	_events[new_id] = {
		"actions": [{"type": "dialog", "dialog_id": ""}],
		"once": true
	}
	_dirty = true
	_current_event_id = new_id
	_current_action_idx = -1
	_clear_container(_left_list)
	_build_event_id_list()
	_build_event_action_list()
	_set_status("新建事件：" + new_id)


# ============================================================
#  预览
# ============================================================
func _preview_dialogue(d : Dictionary):
	var lines : Array = d.get("lines", [])
	var choices : Array = d.get("choices", [])
	if lines.is_empty():
		_set_status("预览失败：无台词")
		return
	if choices.is_empty():
		DialogueManager.start_inline_dialogue(lines)
	else:
		DialogueManager.start_inline_dialogue_with_choices(lines, choices)
	_set_status("▶ 预览中：" + str(d.get("id", "?")))


# ============================================================
#  快捷键
# ============================================================
func _input(event : InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ke : InputEventKey = event
	if ke.ctrl_pressed and ke.keycode == KEY_S:
		_on_save()
		get_viewport().set_input_as_handled()
	elif ke.keycode == KEY_ESCAPE:
		_on_quit()
		get_viewport().set_input_as_handled()
