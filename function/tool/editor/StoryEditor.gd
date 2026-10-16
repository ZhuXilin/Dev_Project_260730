@tool
extends Control

# ============================================================
#  StoryEditor — NPC 剧情 / 独立对话 / 地图事件 统一编辑器
#  UI 完全对齐 ChipMusicEditor
# ============================================================

const STORY_PATH : String = "res://content/data/stories.json"
const DIALOGUE_PATH : String = "res://content/data/dialogues.json"
const EVENT_PATH : String = "res://content/data/events.json"
const MAP_DIR : String = "res://content/scenes/maps/"

const UNLOCK_TYPES : Array = ["unit", "relic", "aura", "route", "talent", "transform_branch"]
const NUM_CONDITIONS : Array = [
	"min_run_count", "min_altar_level", "min_initial_level",
	"min_weapon_max_level", "min_dispatch_count", "min_arena_clear",
	"min_dialogue_count"
]

const CONDITION_HELP : Dictionary = {
	"min_run_count": "累计通关局数 ≥ N",
	"min_altar_level": "魂火上限等级 ≥ N（0-6）",
	"min_initial_level": "初始魂火等级 ≥ N（0-3）",
	"min_weapon_max_level": "任意单位武器最高等级 ≥ N（0-5）",
	"min_dispatch_count": "累计派遣次数 ≥ N",
	"min_arena_clear": "竞技场通关次数 ≥ N",
	"min_dialogue_count": "与该 NPC 已看对话数 ≥ N",
	"after_dialogue": "必须先看过指定对话",
	"flags": "必须已获得所有 flag（逗号分隔）",
}

# ---- ★ 完全对齐 ChipMusicEditor 的尺寸 ----
const FS_BUTTON : int = 6
const FS_LABEL  : int = 6
const FS_SMALL  : int = 5
const FS_PANEL  : int = 7
const FS_HINT   : int = 5

const BTN_H : int = 13
const SPIN_H : int = 13
const SPIN_W : int = 24
const TAB_H  : int = 18
const TAB_W  : int = 68
const ROW_H  : int = 13

const LEFT_W : int = 90
const MID_W  : int = 170

# ---- 配色（对齐 ChipMusicEditor） ----
const COL_BG        : Color = Color(0.08, 0.08, 0.10)
const COL_PANEL     : Color = Color(0.10, 0.10, 0.13)
const COL_VSEP      : Color = Color(0.36, 0.36, 0.42)
const COL_TIP_BG    : Color = Color(0.15, 0.15, 0.15, 0.92)

# ---- 数据 ----
var _stories : Dictionary = {}
var _dialogues : Dictionary = {}
var _events : Dictionary = {}
var _dirty : bool = false
var _event_usage_cache : Dictionary = {}

var _tab : String = "stories"
var _current_npc : String = ""
var _current_dialogue_id : String = ""
var _current_unlock_idx : int = -1
var _current_flat_id : String = ""
var _current_event_id : String = ""
var _current_action_idx : int = -1

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
	_apply_compact_theme()
	_build_ui()
	_load_all()
	_build_event_usage_cache()
	_switch_tab("stories")


func _setup_window():
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return
	var cur = DisplayServer.window_get_size()
	if cur.x < 900 or cur.y < 500:
		DisplayServer.window_set_size(Vector2i(1100, 640))


# ============================================================
#  ★ 全局 Theme（照搬 ChipMusicEditor）
# ============================================================
func _apply_compact_theme():
	var t := Theme.new()

	# ---- Button ----
	t.set_font_size("font_size", "Button", FS_BUTTON)
	var btn_empty := StyleBoxEmpty.new()
	btn_empty.content_margin_left = 1
	btn_empty.content_margin_right = 1
	btn_empty.content_margin_top = 0
	btn_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "Button", btn_empty)
	t.set_stylebox("hover", "Button", btn_empty)
	t.set_stylebox("pressed", "Button", btn_empty)
	t.set_stylebox("focus", "Button", btn_empty)
	t.set_stylebox("disabled", "Button", btn_empty)

	# ---- Label ----
	t.set_font_size("font_size", "Label", FS_LABEL)
	var label_empty := StyleBoxEmpty.new()
	label_empty.content_margin_left = 0
	label_empty.content_margin_right = 0
	label_empty.content_margin_top = 0
	label_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "Label", label_empty)

	# ---- LineEdit（无边框） ----
	t.set_font_size("font_size", "LineEdit", FS_BUTTON)
	var le_empty := StyleBoxEmpty.new()
	le_empty.content_margin_left = 2
	le_empty.content_margin_right = 2
	le_empty.content_margin_top = 0
	le_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "LineEdit", le_empty)
	t.set_stylebox("focus", "LineEdit", le_empty)
	t.set_stylebox("read_only", "LineEdit", le_empty)

	# ---- OptionButton ----
	t.set_font_size("font_size", "OptionButton", FS_BUTTON)

	# ---- PopupMenu（下拉） ----
	t.set_font_size("font_size", "PopupMenu", FS_SMALL)
	t.set_font_size("font_separator_size", "PopupMenu", FS_SMALL)
	t.set_constant("item_start_padding", "PopupMenu", 3)
	t.set_constant("item_end_padding", "PopupMenu", 3)
	t.set_constant("v_separation", "PopupMenu", 0)
	t.set_constant("h_separation", "PopupMenu", 0)
	t.set_constant("icon_max_width", "PopupMenu", 6)
	t.set_constant("outline_size", "PopupMenu", 0)

	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = Color(0.13, 0.13, 0.16, 1)
	popup_panel.border_color = Color(0.28, 0.28, 0.34, 1)
	popup_panel.border_width_left = 1
	popup_panel.border_width_right = 1
	popup_panel.border_width_top = 1
	popup_panel.border_width_bottom = 1
	popup_panel.content_margin_left = 2
	popup_panel.content_margin_right = 2
	popup_panel.content_margin_top = 2
	popup_panel.content_margin_bottom = 2
	t.set_stylebox("panel", "PopupMenu", popup_panel)

	# ---- Tooltip ----
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)
	t.set_font_size("font_size", "TooltipPanel", FS_SMALL)
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = COL_TIP_BG
	tip_sb.content_margin_left = 3
	tip_sb.content_margin_right = 3
	tip_sb.content_margin_top = 1
	tip_sb.content_margin_bottom = 1
	t.set_stylebox("panel", "TooltipPanel", tip_sb)

	# ---- VSeparator ----
	var sep_sb := StyleBoxLine.new()
	sep_sb.color = COL_VSEP
	sep_sb.thickness = 1
	sep_sb.vertical = true
	sep_sb.grow_begin = 2
	sep_sb.grow_end = 2
	t.set_stylebox("separator", "VSeparator", sep_sb)

	# ---- SpinBox ----
	t.set_font_size("font_size", "SpinBox", FS_BUTTON)

	theme = t


# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var main := VBoxContainer.new()
	main.name = "MainVBox"
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.offset_left = 3
	main.offset_top = 2
	main.offset_right = -3
	main.offset_bottom = -2
	main.add_theme_constant_override("separation", 1)
	add_child(main)

	# ---- TopBar ----
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 0)
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

	top.add_child(_make_vsep())

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)

	var save_btn := _mk_btn("保存", _on_save)
	save_btn.tooltip_text = "Ctrl+S"
	top.add_child(save_btn)

	var reload_btn := _mk_btn("重载", _on_reload)
	top.add_child(reload_btn)

	var quit_btn := _mk_btn("退出", _on_quit)
	top.add_child(quit_btn)

	# ---- Body: 嵌套 HSplit ----
	var outer_split := HSplitContainer.new()
	outer_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_split.split_offset = LEFT_W
	main.add_child(outer_split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(60, 0)
	left.add_theme_constant_override("separation", 0)
	outer_split.add_child(left)

	_left_title = Label.new()
	_left_title.add_theme_font_size_override("font_size", FS_PANEL)
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
	_left_list.add_theme_constant_override("separation", 0)
	left_scroll.add_child(_left_list)

	var inner_split := HSplitContainer.new()
	inner_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner_split.split_offset = MID_W
	outer_split.add_child(inner_split)

	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(80, 0)
	mid.add_theme_constant_override("separation", 0)
	inner_split.add_child(mid)

	_mid_title = Label.new()
	_mid_title.add_theme_font_size_override("font_size", FS_PANEL)
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
	_mid_list.add_theme_constant_override("separation", 0)
	mid_scroll.add_child(_mid_list)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(160, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	inner_split.add_child(right)

	_right_title = Label.new()
	_right_title.add_theme_font_size_override("font_size", FS_PANEL)
	_right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_title.text = "— 编辑区 —"
	_right_title.clip_text = true
	right.add_child(_right_title)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right.add_child(right_scroll)

	_right_container = VBoxContainer.new()
	_right_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_container.add_theme_constant_override("separation", 1)
	right_scroll.add_child(_right_container)

	# ---- StatusBar ----
	var status_bar := PanelContainer.new()
	status_bar.custom_minimum_size = Vector2(0, 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
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
#  控件工厂（完全对齐 ChipMusicEditor）
# ============================================================
func _mk_btn(text : String, cb : Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FS_BUTTON)
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _mk_tab_button(text : String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", FS_PANEL)
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
	le.add_theme_font_size_override("font_size", FS_BUTTON)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.custom_minimum_size = Vector2(0, ROW_H)
	return le


func _mk_spin(value : int, min_v : int, max_v : int, w : int = SPIN_W) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = 1
	sp.value = value
	sp.custom_minimum_size = Vector2(w, SPIN_H)
	sp.size_flags_horizontal = Control.SIZE_SHRINK_END
	sp.add_theme_font_size_override("font_size", FS_BUTTON)
	sp.add_theme_constant_override("separation", 0)
	sp.ready.connect(func(): _setup_spin(sp), CONNECT_ONE_SHOT)
	return sp


## ★ 完全照搬 ChipMusicEditor._setup_spin
func _setup_spin(sp : SpinBox):
	var le := sp.get_line_edit()
	if le:
		le.add_theme_font_size_override("font_size", FS_BUTTON)
		le.custom_minimum_size = Vector2(0, SPIN_H - 2)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.editable = true
		le.select_all_on_focus = true
		le.context_menu_enabled = false
	var btns : Array[Node] = sp.find_children("*", "Button", true, false)
	for b in btns:
		_compact_spin_arrow_button(b as Button)


func _compact_spin_arrow_button(btn : Button):
	btn.custom_minimum_size = Vector2(3, 2)
	btn.icon_max_width = 2
	btn.icon_max_height = 2
	btn.focus_mode = Control.FOCUS_NONE
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 0
	empty.content_margin_right = 0
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.add_theme_stylebox_override("disabled", empty)


func _mk_option_button() -> OptionButton:
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", FS_BUTTON)
	opt.custom_minimum_size = Vector2(60, BTN_H)
	opt.clip_text = true
	return opt


func _mk_checkbox(text : String, pressed : bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FS_LABEL)
	b.clip_text = true
	b.text = ("☑ " if pressed else "☐ ") + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.toggled.connect(func(p):
		b.text = ("☑ " if p else "☐ ") + text
	)
	return b


func _make_vsep() -> Control:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(1, BTN_H)
	return sep


func _mk_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 2)
	row.add_theme_constant_override("v_separation", 1)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func _mk_icon_btn(text : String, warn : bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FS_BUTTON)
	b.custom_minimum_size = Vector2(14, ROW_H)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	if warn:
		b.modulate = Color(1.0, 0.5, 0.5)
	return b


func _clear_container(node : Node):
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _set_status(text : String):
	if _status_label:
		_status_label.text = text


func _stretch_btn(btn : Button):
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _mk_section(text : String) -> Label:
	var l := _mk_label(text, FS_SMALL)
	l.modulate = Color(0.65, 0.75, 0.85)
	return l


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
	_build_event_usage_cache()
	_switch_tab(_tab)


func _on_quit():
	get_tree().quit()


# ============================================================
#  事件反查
# ============================================================
func _build_event_usage_cache():
	_event_usage_cache.clear()
	_scan_dir(MAP_DIR)


func _scan_dir(dir_path : String):
	var dir := DirAccess.open(dir_path)
	if dir == null: return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir():
			if fname != "." and fname != "..":
				_scan_dir(dir_path + fname + "/")
		elif fname.ends_with(".tscn"):
			_scan_tscn(dir_path + fname)
		fname = dir.get_next()
	dir.list_dir_end()


func _scan_tscn(path : String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var text := f.get_as_text()
	f.close()
	for line in text.split("\n"):
		var s : String = line.strip_edges()
		if s.begins_with("event_id") and s.contains("="):
			var v : String = s.substr(s.find("=") + 1).strip_edges()
			v = v.trim_prefix("\"").trim_suffix("\"")
			if v != "":
				if not _event_usage_cache.has(v):
					_event_usage_cache[v] = []
				_event_usage_cache[v].append(path.get_file())


func _get_usages(event_id : String) -> Array:
	return _event_usage_cache.get(event_id, [])


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
		var btn := _mk_btn("%s (%s)" % [npc_id, npc.get("name", "")])
		_stretch_btn(btn)
		btn.toggle_mode = true
		btn.button_pressed = (npc_id == _current_npc)
		btn.modulate = Color.WHITE if npc_id == _current_npc else Color(0.75, 0.75, 0.75, 1)
		btn.pressed.connect(_on_npc_selected.bind(npc_id))
		_left_list.add_child(btn)

	if _current_npc == "" or not _stories.has(_current_npc):
		var fk = _stories.keys()[0] if _stories.size() > 0 else ""
		if fk != "": _on_npc_selected(fk)


func _on_npc_selected(npc_id : String):
	_current_npc = npc_id
	_current_dialogue_id = ""
	_current_unlock_idx = -1

	for c in _left_list.get_children():
		if c is Button:
			c.modulate = Color.WHITE if c.text.begins_with(npc_id + " ") else Color(0.75, 0.75, 0.75, 1)

	_build_mid_list()
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"


func _build_mid_list():
	_clear_container(_mid_list)
	if _current_npc == "" or not _stories.has(_current_npc): return
	var npc : Dictionary = _stories[_current_npc]

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 2)
	_mid_list.add_child(add_row)

	var ad := _mk_btn("+ 对话", _add_new_dialogue)
	ad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(ad)

	var au := _mk_btn("+ 解锁", _add_new_unlock)
	au.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(au)

	_mid_list.add_child(_mk_section("— dialogues —"))

	var dialogues : Array = npc.get("dialogues", [])
	for i in range(dialogues.size()):
		var d : Dictionary = dialogues[i]
		var did : String = d.get("id", "?")
		var pri : int = int(d.get("priority", 0))
		var btn := _mk_btn("%s (p%d)" % [did, pri])
		_stretch_btn(btn)
		btn.toggle_mode = true
		btn.button_pressed = (did == _current_dialogue_id)
		btn.modulate = Color.WHITE if did == _current_dialogue_id else Color(0.8, 0.8, 0.8, 1)
		btn.pressed.connect(_on_dialogue_selected.bind(did))
		_mid_list.add_child(btn)

	_mid_list.add_child(_mk_section("— unlocks —"))

	var unlocks : Array = npc.get("unlocks", [])
	if unlocks.is_empty():
		var lb := _mk_label("（无）")
		lb.modulate = Color(0.55, 0.55, 0.55)
		_mid_list.add_child(lb)
	else:
		for i in range(unlocks.size()):
			var u : Dictionary = unlocks[i]
			var ut : String = u.get("type", "?")
			var ui : String = u.get("id", "?")
			var dn : String = _unlock_display(ut, ui)
			var btn := _mk_btn("[%s] %s" % [ut, dn])
			_stretch_btn(btn)
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

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	_right_container.add_child(head)

	var pv := _mk_btn("▶ 预览")
	pv.pressed.connect(_preview_dialogue.bind(d))
	head.add_child(pv)

	var dl := _mk_btn("删除", _delete_current_dialogue)
	dl.modulate = Color(1.0, 0.6, 0.6)
	head.add_child(dl)

	# ID
	var id_row := _mk_row()
	_right_container.add_child(id_row)
	id_row.add_child(_mk_label("ID:"))
	var id_edit := _mk_line_edit(_current_dialogue_id)
	id_edit.custom_minimum_size = Vector2(80, ROW_H)
	id_edit.tooltip_text = "对话唯一 ID（同 NPC 内不可重复）"
	id_edit.text_submitted.connect(func(n):
		_rename_dialogue(_current_dialogue_id, n)
	)
	id_row.add_child(id_edit)

	# priority
	var pri_row := _mk_row()
	_right_container.add_child(pri_row)
	pri_row.add_child(_mk_label("priority:"))
	var ps := _mk_spin(int(d.get("priority", 0)), -100, 100)
	ps.tooltip_text = "满足 condition 的多个对话中，选 priority 最高的播放"
	ps.value_changed.connect(func(v):
		d["priority"] = int(v)
		_dirty = true
		_build_mid_list()
	)
	pri_row.add_child(ps)
	pri_row.add_child(_mk_label("（大者优先）", FS_SMALL))

	_right_container.add_child(_mk_section("— condition（全部满足才触发）—"))
	_build_condition_editor(d.get("condition", {}), func(nc):
		if nc.is_empty(): d.erase("condition")
		else: d["condition"] = nc
		_dirty = true
	)

	_right_container.add_child(_mk_section("— lines —"))
	_build_lines_editor(d)

	_right_container.add_child(_mk_section("— choices —"))
	_build_choices_editor(d)


func _find_dialogue(npc_id : String, dialogue_id : String) -> Dictionary:
	if not _stories.has(npc_id): return {}
	for d in _stories[npc_id].get("dialogues", []):
		if d is Dictionary and d.get("id", "") == dialogue_id:
			return d
	return {}


func _is_id_taken(npc_id : String, new_id : String, exclude : String) -> bool:
	if not _stories.has(npc_id): return false
	for d in _stories[npc_id].get("dialogues", []):
		if not (d is Dictionary): continue
		var did : String = d.get("id", "")
		if did == new_id and did != exclude: return true
	return false


func _rename_dialogue(old_id : String, new_id : String):
	if new_id == "" or new_id == old_id: return
	if _is_id_taken(_current_npc, new_id, old_id):
		_set_status("✗ ID 已存在：%s" % new_id)
		_build_dialogue_form()
		return
	for d in _stories[_current_npc].get("dialogues", []):
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
	var dlist : Array = _stories[_current_npc].get("dialogues", [])
	for i in range(dlist.size()):
		if dlist[i] is Dictionary and dlist[i].get("id", "") == _current_dialogue_id:
			dlist.remove_at(i)
			_dirty = true
			_current_dialogue_id = ""
			_build_mid_list()
			_clear_container(_right_container)
			_right_title.text = "— 编辑区 —"
			_set_status("已删除对话")
			return


func _add_new_dialogue():
	if _current_npc == "": return
	var npc : Dictionary = _stories[_current_npc]
	if not npc.has("dialogues"): npc["dialogues"] = []
	var base : String = "new_dialogue"
	var nid : String = base
	var n : int = 1
	while _is_id_taken(_current_npc, nid, ""):
		n += 1
		nid = "%s_%d" % [base, n]
	npc["dialogues"].append({
		"id": nid, "priority": 0,
		"lines": [{"speaker": "???", "text": "..."}]
	})
	_dirty = true
	_current_dialogue_id = nid
	_current_unlock_idx = -1
	_build_mid_list()
	_build_dialogue_form()
	_set_status("新建对话：" + nid)


# ============================================================
#  Unlock 编辑
# ============================================================
func _build_unlock_form():
	_clear_container(_right_container)
	if _current_npc == "" or _current_unlock_idx < 0: return
	var unlocks : Array = _stories.get(_current_npc, {}).get("unlocks", [])
	if _current_unlock_idx >= unlocks.size(): return
	var u : Dictionary = unlocks[_current_unlock_idx]

	_right_title.text = "编辑解锁 #%d" % _current_unlock_idx

	var tr := _mk_row()
	_right_container.add_child(tr)
	tr.add_child(_mk_label("type:"))
	var opt := _mk_option_button()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(UNLOCK_TYPES.size()):
		opt.add_item(UNLOCK_TYPES[i], i)
		if UNLOCK_TYPES[i] == u.get("type", ""): opt.selected = i
	opt.item_selected.connect(func(idx):
		u["type"] = UNLOCK_TYPES[idx]
		u["id"] = ""
		_dirty = true
		_build_mid_list()
		_build_unlock_form()
	)
	tr.add_child(opt)

	var ir := _mk_row()
	_right_container.add_child(ir)
	ir.add_child(_mk_label("id:"))
	var ie : Control = _build_unlock_id_editor(u)
	ir.add_child(ie)

	_right_container.add_child(_mk_section("— conditions —"))
	_build_condition_editor(u.get("conditions", {}), func(nc):
		if nc.is_empty(): u.erase("conditions")
		else: u["conditions"] = nc
		_dirty = true
	)

	var del := _mk_btn("删除此解锁", _delete_current_unlock)
	del.modulate = Color(1.0, 0.6, 0.6)
	_right_container.add_child(del)


func _build_unlock_id_editor(u : Dictionary) -> Control:
	var ut : String = u.get("type", "")
	var cands : Array = _candidates(ut)
	var cur : String = str(u.get("id", ""))

	if cands.is_empty():
		var le := _mk_line_edit(cur, "（无候选，手打）")
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_changed.connect(func(t):
			u["id"] = t
			_dirty = true
			_build_mid_list()
		)
		return le

	var opt := _mk_option_button()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_item("（选择…）", 0)
	opt.set_item_metadata(0, "")
	var matched := (cur == "")
	for i in range(cands.size()):
		var c : Dictionary = cands[i]
		var cid : String = str(c.get("id", ""))
		var cname : String = str(c.get("name", cid))
		opt.add_item("%s  (%s)" % [cname, cid], i + 1)
		opt.set_item_metadata(i + 1, cid)
		if cid == cur:
			opt.selected = i + 1
			matched = true
	if not matched and cur != "":
		opt.add_item("（当前）" + cur, cands.size() + 1)
		opt.set_item_metadata(cands.size() + 1, cur)
		opt.selected = cands.size() + 1
	opt.item_selected.connect(func(idx):
		var v = opt.get_item_metadata(idx)
		u["id"] = str(v if v != null else "")
		_dirty = true
		_build_mid_list()
	)
	return opt


func _candidates(ut : String) -> Array:
	var arr : Array = []
	match ut:
		"unit":
			for k in UnitDataManager.get_all_unit_ids():
				arr.append({"id": k, "name": UnitDataManager.get_display_name(k)})
		"relic":
			for r in RelicManager.get_all_relic_ids():
				arr.append({"id": r, "name": RelicManager.get_relic_data(r).get("name", r)})
		"aura":
			for a in AuraManager.get_all_ids():
				arr.append({"id": a, "name": AuraManager.get_display_name(a)})
		"route":
			for r in DispatchManager.ROUTES:
				arr.append({"id": r, "name": DispatchManager.ROUTES[r].get("name", r)})
		"talent":
			for t in TalentManager.get_all_talent_ids():
				var d = TalentManager.get_talent_data(t)
				if d: arr.append({"id": t, "name": d.display_name})
	return arr


func _unlock_display(ut : String, uid : String) -> String:
	match ut:
		"unit": return "%s (%s)" % [UnitDataManager.get_display_name(uid), uid]
		"relic":
			var d : Dictionary = RelicManager.get_relic_data(uid)
			return uid if d.is_empty() else "%s (%s)" % [d.get("name", uid), uid]
		"aura": return "%s (%s)" % [AuraManager.get_display_name(uid), uid]
		"route":
			var r : Dictionary = DispatchManager.ROUTES.get(uid, {})
			return uid if r.is_empty() else "%s (%s)" % [r.get("name", uid), uid]
		"talent":
			var d = TalentManager.get_talent_data(uid)
			return uid if d == null else "%s (%s)" % [d.display_name, uid]
	return uid


func _delete_current_unlock():
	var unlocks : Array = _stories.get(_current_npc, {}).get("unlocks", [])
	if _current_unlock_idx < 0 or _current_unlock_idx >= unlocks.size(): return
	unlocks.remove_at(_current_unlock_idx)
	_dirty = true
	_current_unlock_idx = -1
	_build_mid_list()
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"
	_set_status("已删除解锁")


func _add_new_unlock():
	if _current_npc == "": return
	var npc : Dictionary = _stories[_current_npc]
	if not npc.has("unlocks"): npc["unlocks"] = []
	npc["unlocks"].append({"type": "route", "id": "", "conditions": {}})
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
		var row := _mk_row()
		_right_container.add_child(row)

		var cb := _mk_checkbox(key, work.has(key))
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.tooltip_text = CONDITION_HELP.get(key, "")
		row.add_child(cb)

		var sp := _mk_spin(int(work.get(key, 0)), 0, 999)
		sp.editable = work.has(key)
		sp.value_changed.connect(func(v):
			work[key] = int(v)
			on_change.call(work)
		)
		row.add_child(sp)

		cb.toggled.connect(func(p):
			sp.editable = p
			if p: work[key] = int(sp.value)
			else: work.erase(key)
			on_change.call(work)
		)

	# after_dialogue
	var ad_row := _mk_row()
	_right_container.add_child(ad_row)
	var ad_cb := _mk_checkbox("after_dialogue", work.has("after_dialogue"))
	ad_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ad_cb.tooltip_text = CONDITION_HELP.get("after_dialogue", "")
	ad_row.add_child(ad_cb)

	var ids : Array = []
	if _current_npc != "" and _stories.has(_current_npc):
		for d in _stories[_current_npc].get("dialogues", []):
			if d is Dictionary:
				var did : String = d.get("id", "")
				if did != "": ids.append(did)

	var cur_ad : String = str(work.get("after_dialogue", ""))
	var ad_opt := _mk_option_button()
	ad_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ad_opt.disabled = not work.has("after_dialogue")
	ad_opt.add_item("（选择）", 0)
	ad_opt.set_item_metadata(0, "")
	var m := (cur_ad == "")
	for i in range(ids.size()):
		ad_opt.add_item(ids[i], i + 1)
		ad_opt.set_item_metadata(i + 1, ids[i])
		if ids[i] == cur_ad:
			ad_opt.selected = i + 1
			m = true
	if not m and cur_ad != "":
		ad_opt.add_item("（当前）" + cur_ad, ids.size() + 1)
		ad_opt.set_item_metadata(ids.size() + 1, cur_ad)
		ad_opt.selected = ids.size() + 1
	ad_opt.item_selected.connect(func(idx):
		var v = ad_opt.get_item_metadata(idx)
		work["after_dialogue"] = str(v if v != null else "")
		on_change.call(work)
	)
	ad_row.add_child(ad_opt)
	ad_cb.toggled.connect(func(p):
		ad_opt.disabled = not p
		if p:
			var v = ad_opt.get_item_metadata(ad_opt.selected)
			work["after_dialogue"] = str(v if v != null else "")
		else:
			work.erase("after_dialogue")
		on_change.call(work)
	)

	# flags
	var fl := _mk_label("flags（逗号分隔）:")
	fl.modulate = Color(0.8, 0.8, 0.8)
	fl.tooltip_text = CONDITION_HELP.get("flags", "")
	_right_container.add_child(fl)

	var fr := _mk_row()
	_right_container.add_child(fr)
	var fa : Array = work.get("flags", [])
	var ft : String = ""
	for x in fa: ft += str(x) + ","
	ft = ft.trim_suffix(",")
	var fe := _mk_line_edit(ft, "keeper_asked_why, xxx")
	fe.text_changed.connect(func(t):
		var parts : Array = []
		for p in t.split(",", false):
			var s : String = p.strip_edges()
			if s != "": parts.append(s)
		if parts.is_empty(): work.erase("flags")
		else: work["flags"] = parts
		on_change.call(work)
	)
	fr.add_child(fe)


# ============================================================
#  Lines / Choices 编辑
# ============================================================
func _build_lines_editor(d : Dictionary):
	var lines : Array = d.get("lines", [])
	for i in range(lines.size()):
		var line : Dictionary = lines[i]
		var row := _mk_row()
		_right_container.add_child(row)
		var idx : int = i

		var dl := _mk_icon_btn("-", true)
		dl.tooltip_text = "删除此行"
		dl.pressed.connect(_delete_line.bind(d, idx))
		row.add_child(dl)

		var up := _mk_icon_btn("↑")
		up.pressed.connect(_move_line.bind(d, idx, -1))
		row.add_child(up)

		var dn := _mk_icon_btn("↓")
		dn.pressed.connect(_move_line.bind(d, idx, 1))
		row.add_child(dn)

		var sp := _mk_line_edit(str(line.get("speaker", "")), "说话者")
		sp.custom_minimum_size = Vector2(50, ROW_H)
		sp.size_flags_horizontal = Control.SIZE_FILL
		sp.text_changed.connect(func(t):
			line["speaker"] = t
			_dirty = true
		)
		row.add_child(sp)

		var tx := _mk_line_edit(str(line.get("text", "")), "台词")
		tx.custom_minimum_size = Vector2(100, ROW_H)
		tx.text_changed.connect(func(t):
			line["text"] = t
			_dirty = true
		)
		row.add_child(tx)

	var add := _mk_btn("+ 添加台词")
	add.pressed.connect(func():
		if not d.has("lines"): d["lines"] = []
		d["lines"].append({"speaker": "???", "text": ""})
		_dirty = true
		_build_dialogue_form()
	)
	_right_container.add_child(add)


func _move_line(d : Dictionary, idx : int, dir : int):
	var lines : Array = d.get("lines", [])
	var ni : int = idx + dir
	if ni < 0 or ni >= lines.size(): return
	var t = lines[idx]
	lines[idx] = lines[ni]
	lines[ni] = t
	_dirty = true
	_build_dialogue_form()


func _delete_line(d : Dictionary, idx : int):
	var lines : Array = d.get("lines", [])
	if idx < 0 or idx >= lines.size(): return
	lines.remove_at(idx)
	_dirty = true
	_build_dialogue_form()


func _build_choices_editor(d : Dictionary):
	if not d.has("choices"):
		var init := _mk_btn("+ 添加选项")
		init.pressed.connect(func():
			d["choices"] = [{"text": "", "flag": ""}]
			_dirty = true
			_build_dialogue_form()
		)
		_right_container.add_child(init)
		return
	var choices : Array = d["choices"]
	for i in range(choices.size()):
		var c : Dictionary = choices[i]
		var row := _mk_row()
		_right_container.add_child(row)
		var idx : int = i

		var dl := _mk_icon_btn("-", true)
		dl.pressed.connect(func():
			choices.remove_at(idx)
			if choices.is_empty(): d.erase("choices")
			_dirty = true
			_build_dialogue_form()
		)
		row.add_child(dl)

		var tx := _mk_line_edit(str(c.get("text", "")), "选项文本")
		tx.custom_minimum_size = Vector2(100, ROW_H)
		tx.text_changed.connect(func(t):
			c["text"] = t
			_dirty = true
		)
		row.add_child(tx)

		var fl := _mk_line_edit(str(c.get("flag", "")), "flag")
		fl.custom_minimum_size = Vector2(60, ROW_H)
		fl.size_flags_horizontal = Control.SIZE_FILL
		fl.text_changed.connect(func(t):
			c["flag"] = t
			_dirty = true
		)
		row.add_child(fl)

	var add := _mk_btn("+ 添加选项")
	add.pressed.connect(func():
		choices.append({"text": "", "flag": ""})
		_dirty = true
		_build_dialogue_form()
	)
	_right_container.add_child(add)


# ============================================================
#  Tab 2 · 独立对话
# ============================================================
func _build_flat_id_list():
	for id in _dialogues:
		var btn := _mk_btn(id)
		_stretch_btn(btn)
		btn.toggle_mode = true
		btn.button_pressed = (id == _current_flat_id)
		btn.modulate = Color.WHITE if id == _current_flat_id else Color(0.75, 0.75, 0.75, 1)
		btn.pressed.connect(_on_flat_id_selected.bind(id))
		_left_list.add_child(btn)

	var nb := _mk_btn("+ 新对话", _add_new_flat)
	_left_list.add_child(nb)

	if _current_flat_id == "" or not _dialogues.has(_current_flat_id):
		var fk = _dialogues.keys()[0] if _dialogues.size() > 0 else ""
		if fk != "": _on_flat_id_selected(fk)


func _on_flat_id_selected(id : String):
	_current_flat_id = id
	for c in _left_list.get_children():
		if c is Button:
			c.modulate = Color.WHITE if c.text == id else Color(0.75, 0.75, 0.75, 1)
	_build_flat_form()


func _build_flat_form():
	_clear_container(_right_container)
	if _current_flat_id == "" or not _dialogues.has(_current_flat_id): return

	_right_title.text = "对话：" + _current_flat_id
	var lines : Array = _dialogues[_current_flat_id]

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	_right_container.add_child(head)

	var pv := _mk_btn("▶ 预览")
	pv.pressed.connect(func(): DialogueManager.start_inline_dialogue(lines))
	head.add_child(pv)

	var dl := _mk_btn("删除", _delete_flat)
	dl.modulate = Color(1.0, 0.6, 0.6)
	head.add_child(dl)

	for i in range(lines.size()):
		var line : Dictionary = lines[i]
		var row := _mk_row()
		_right_container.add_child(row)
		var idx : int = i

		var dl2 := _mk_icon_btn("-", true)
		dl2.pressed.connect(func():
			lines.remove_at(idx)
			_dirty = true
			_build_flat_form()
		)
		row.add_child(dl2)

		var sp := _mk_line_edit(str(line.get("speaker", "")), "说话者")
		sp.custom_minimum_size = Vector2(50, ROW_H)
		sp.size_flags_horizontal = Control.SIZE_FILL
		sp.text_changed.connect(func(t):
			line["speaker"] = t
			_dirty = true
		)
		row.add_child(sp)

		var tx := _mk_line_edit(str(line.get("text", "")), "台词")
		tx.custom_minimum_size = Vector2(100, ROW_H)
		tx.text_changed.connect(func(t):
			line["text"] = t
			_dirty = true
		)
		row.add_child(tx)

	var add := _mk_btn("+ 添加台词")
	add.pressed.connect(func():
		lines.append({"speaker": "???", "text": ""})
		_dirty = true
		_build_flat_form()
	)
	_right_container.add_child(add)


func _add_new_flat():
	var base : String = "new_dialogue"
	var nid : String = base
	var n : int = 1
	while _dialogues.has(nid):
		n += 1
		nid = "%s_%d" % [base, n]
	_dialogues[nid] = [{"speaker": "???", "text": "..."}]
	_dirty = true
	_current_flat_id = nid
	_clear_container(_left_list)
	_build_flat_id_list()
	_build_flat_form()
	_set_status("新建独立对话：" + nid)


func _delete_flat():
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
		var us : Array = _get_usages(eid)
		var suf : String = ("  [%d]" % us.size()) if not us.is_empty() else ""
		var btn := _mk_btn(eid + suf)
		_stretch_btn(btn)
		btn.toggle_mode = true
		btn.button_pressed = (eid == _current_event_id)
		btn.modulate = Color.WHITE if eid == _current_event_id else Color(0.75, 0.75, 0.75, 1)
		btn.tooltip_text = "被引用：" + (", ".join(us) if not us.is_empty() else "（无）")
		btn.pressed.connect(_on_event_selected.bind(eid))
		_left_list.add_child(btn)

	_left_list.add_child(_mk_btn("+ 新事件", _add_new_event))

	if _current_event_id == "" or not _events.has(_current_event_id):
		var fk = _events.keys()[0] if _events.size() > 0 else ""
		if fk != "": _on_event_selected(fk)


func _on_event_selected(event_id : String):
	_current_event_id = event_id
	_current_action_idx = -1
	for c in _left_list.get_children():
		if c is Button:
			c.modulate = Color.WHITE if c.text.begins_with(event_id) else Color(0.75, 0.75, 0.75, 1)
	_build_event_action_list()
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"


func _build_event_action_list():
	_clear_container(_mid_list)
	if _current_event_id == "" or not _events.has(_current_event_id): return
	var ev : Dictionary = _events[_current_event_id]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_mid_list.add_child(row)

	var aa := _mk_btn("+ action", _add_new_action)
	aa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(aa)

	var oc := _mk_checkbox("once", bool(ev.get("once", true)))
	oc.tooltip_text = "勾选后此事件只触发一次"
	oc.toggled.connect(func(p):
		ev["once"] = p
		_dirty = true
	)
	row.add_child(oc)

	_mid_list.add_child(_mk_section("— actions —"))

	var actions : Array = ev.get("actions", [])
	for i in range(actions.size()):
		var a : Dictionary = actions[i]
		var at : String = a.get("type", "?")
		var ex : String = ""
		if at == "dialog": ex = a.get("dialog_id", "")
		elif at == "give_item": ex = a.get("item_id", "")
		elif at == "heal" or at == "damage": ex = str(a.get("amount", 0))
		elif at == "unlock_unit":
			var us : Array = a.get("units", [])
			ex = ",".join(us) if not us.is_empty() else ""
		var btn := _mk_btn("%d. [%s] %s" % [i, at, ex])
		_stretch_btn(btn)
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
	if not ev.has("actions"): ev["actions"] = []
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

	var us : Array = _get_usages(_current_event_id)
	var ut : String = "（无地图引用）"
	if not us.is_empty(): ut = "被 %d 张地图引用：%s" % [us.size(), ", ".join(us)]
	var ul := _mk_label(ut, FS_SMALL)
	ul.modulate = Color(0.7, 0.9, 0.7) if not us.is_empty() else Color(0.7, 0.5, 0.5)
	_right_container.add_child(ul)

	_right_title.text = "action #%d" % _current_action_idx

	var tr := _mk_row()
	_right_container.add_child(tr)
	tr.add_child(_mk_label("type:"))
	var opt := _mk_option_button()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ct : String = a.get("type", "dialog")
	var matched := false
	for i in range(ACTION_TYPES.size()):
		opt.add_item(ACTION_TYPES[i], i)
		if ACTION_TYPES[i] == ct:
			opt.selected = i
			matched = true
	if not matched:
		opt.add_item(ct + "（自定义）", ACTION_TYPES.size())
		opt.selected = ACTION_TYPES.size()
	opt.item_selected.connect(func(idx):
		if idx < ACTION_TYPES.size(): a["type"] = ACTION_TYPES[idx]
		_dirty = true
		_build_event_action_list()
		_build_action_form()
	)
	tr.add_child(opt)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	_right_container.add_child(head)

	var ub := _mk_btn("↑ 上移")
	ub.pressed.connect(_move_action.bind(-1))
	head.add_child(ub)

	var db := _mk_btn("↓ 下移")
	db.pressed.connect(_move_action.bind(1))
	head.add_child(db)

	var dl := _mk_btn("删除", _delete_current_action)
	dl.modulate = Color(1.0, 0.6, 0.6)
	head.add_child(dl)

	_right_container.add_child(_mk_section("— 字段 —"))
	_build_dynamic_fields(a)


func _move_action(dir : int):
	var actions : Array = _events.get(_current_event_id, {}).get("actions", [])
	var ni : int = _current_action_idx + dir
	if ni < 0 or ni >= actions.size(): return
	var t = actions[_current_action_idx]
	actions[_current_action_idx] = actions[ni]
	actions[ni] = t
	_current_action_idx = ni
	_dirty = true
	_build_event_action_list()
	_build_action_form()


func _delete_current_action():
	var actions : Array = _events.get(_current_event_id, {}).get("actions", [])
	if _current_action_idx < 0 or _current_action_idx >= actions.size(): return
	actions.remove_at(_current_action_idx)
	_dirty = true
	_current_action_idx = -1
	_build_event_action_list()
	_clear_container(_right_container)
	_right_title.text = "— 编辑区 —"
	_set_status("已删除 action")


func _build_dynamic_fields(a : Dictionary):
	var priority : Array = [
		"dialog_id", "item_id", "count", "equip",
		"amount", "seconds",
		"units", "talent_id", "relic_id", "relic_ids", "music"
	]
	var visited : Dictionary = {"type": true}
	for k in priority:
		if a.has(k):
			_build_one_field(a, k)
			visited[k] = true
	for k in a:
		if not visited.has(k):
			_build_one_field(a, k)

	_right_container.add_child(_mk_section("— 添加字段 —"))
	var ar := _mk_row()
	_right_container.add_child(ar)

	var ke := _mk_line_edit("", "字段名")
	ke.custom_minimum_size = Vector2(60, ROW_H)
	ke.size_flags_horizontal = Control.SIZE_FILL
	ar.add_child(ke)

	var ve := _mk_line_edit("", "值")
	ve.custom_minimum_size = Vector2(80, ROW_H)
	ar.add_child(ve)

	var ab := _mk_icon_btn("+")
	ab.pressed.connect(func():
		var k : String = ke.text.strip_edges()
		if k == "" or k == "type": return
		a[k] = _parse_value(ve.text)
		_dirty = true
		_build_event_action_list()
		_build_action_form()
	)
	ar.add_child(ab)


func _parse_value(v : String) -> Variant:
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


func _build_one_field(a : Dictionary, key : String):
	var value : Variant = a[key]
	var row := _mk_row()
	_right_container.add_child(row)

	var dl := _mk_icon_btn("-", true)
	dl.pressed.connect(func():
		a.erase(key)
		_dirty = true
		_build_event_action_list()
		_build_action_form()
	)
	row.add_child(dl)

	var lb := _mk_label(key)
	lb.custom_minimum_size = Vector2(60, 0)
	lb.tooltip_text = key
	row.add_child(lb)

	var t : int = typeof(value)
	if t == TYPE_BOOL:
		var cb := _mk_checkbox("", bool(value))
		cb.toggled.connect(func(p):
			a[key] = p
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
		le.custom_minimum_size = Vector2(60, ROW_H)
		le.text_changed.connect(func(s):
			if s.is_valid_float(): a[key] = float(s)
			_dirty = true
		)
		row.add_child(le)
	elif t == TYPE_ARRAY:
		var txt : String = ""
		for x in value: txt += str(x) + ","
		txt = txt.trim_suffix(",")
		var le := _mk_line_edit(txt, "逗号分隔")
		le.custom_minimum_size = Vector2(80, ROW_H)
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
		le.custom_minimum_size = Vector2(80, ROW_H)
		le.text_changed.connect(func(s):
			a[key] = s
			_dirty = true
			_build_event_action_list()
		)
		row.add_child(le)


func _add_new_event():
	var base : String = "new_event"
	var nid : String = base
	var n : int = 1
	while _events.has(nid):
		n += 1
		nid = "%s_%d" % [base, n]
	_events[nid] = {"actions": [{"type": "dialog", "dialog_id": ""}], "once": true}
	_dirty = true
	_current_event_id = nid
	_current_action_idx = -1
	_clear_container(_left_list)
	_build_event_id_list()
	_build_event_action_list()
	_set_status("新建事件：" + nid)


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
