extends Control

# ============================================================
#  GameDataEditor — 单位 / 战斗模拟 / 数值 / 套装 / 词条池 / 光环 / 单位解锁 / 校验
# ============================================================

const UNIT_DATA_PATH : String = "res://content/data/unit_data.json"
const RELIC_DATA_PATH : String = "res://content/data/relic_data.json"
const ITEM_DATA_PATH : String = "res://content/data/item_data.json"
const TALENT_DATA_PATH : String = "res://content/data/talents.json"
const REFINE_DATA_PATH : String = "res://content/data/refine_data.json"
const SET_BONUS_PATH : String = "res://content/data/set_bonuses.json"
const AFFIX_PATH : String = "res://content/data/affixes.json"
const AURA_PATH : String = "res://content/data/auras.json"
const UNIT_UNLOCK_PATH : String = "res://content/data/unit_unlock.json"
const AVATAR_DIR : String = "res://content/images/characters/avatar/"

const JSON_EDITOR_SCRIPT : String = "res://function/tool/editor/JSONEditorPanel.gd"

# ---- 字号（对齐 ChipMusicEditor）----
const FS_BUTTON : int = 6
const FS_LABEL  : int = 6
const FS_SMALL  : int = 5
const FS_TINY   : int = 5
const FS_PANEL  : int = 7
const FS_HINT   : int = 5

const BTN_H : int = 13
const SPIN_H : int = 13
const SPIN_W : int = 24
const ROW_H : int = 13

const COL_BG     : Color = Color(0.08, 0.08, 0.10)
const COL_PANEL  : Color = Color(0.10, 0.10, 0.13)
const COL_VSEP   : Color = Color(0.36, 0.36, 0.42)
const COL_TIP_BG : Color = Color(0.15, 0.15, 0.15, 0.92)

const EDITABLE_ATTRS : Array = [
	{"key": "max_hp",       "label": "生命",   "min": 1, "max": 999},
	{"key": "strength",     "label": "力量",   "min": 0, "max": 99},
	{"key": "dexterity",    "label": "灵巧",   "min": 0, "max": 99},
	{"key": "intelligence", "label": "智力",   "min": 0, "max": 99},
	{"key": "faith",        "label": "信仰",   "min": 0, "max": 99},
	{"key": "arcane",       "label": "感应",   "min": 0, "max": 99},
	{"key": "move_range",   "label": "移动",   "min": 0, "max": 20},
]

const UNIT_TAGS : Array = ["烈焰", "轮回", "灰烬", "守护", "献祭", "余烬"]
const CORE_TRAITS : Array = ["", "蓄力", "龙威", "壁垒"]
const CORE_TRAITS_MAP : Dictionary = {
	"": "（无）",
	"charge": "蓄力",
	"dragon_might": "龙威",
	"bulwark": "壁垒"
}
const SAC_BUFF_TYPES : Array = [
	"", "attack_percent", "crit_damage_bonus", "defense_flat",
	"damage_reduction", "heal_bonus", "counter_damage_bonus"
]
const SAC_BUFF_TYPES_CN : Dictionary = {
	"": "（无）",
	"attack_percent": "全队攻击",
	"crit_damage_bonus": "全队暴伤",
	"defense_flat": "全队防御",
	"damage_reduction": "全队减伤",
	"heal_bonus": "全队治疗",
	"counter_damage_bonus": "全队反击"
}

const CAP_ATTRS : Array = [
	"vitality", "strength", "dexterity",
	"intelligence", "faith", "arcane"
]
const CAP_ATTR_LABELS : Dictionary = {
	"vitality": "生命", "strength": "力量", "dexterity": "灵巧",
	"intelligence": "智力", "faith": "信仰", "arcane": "感应"
}
const BRANCH_STAT_KEYS : Array = [
	"max_hp", "strength", "dexterity",
	"intelligence", "faith", "arcane", "move_range"
]
const BRANCH_STAT_LABELS : Dictionary = {
	"max_hp": "生命", "strength": "力量", "dexterity": "灵巧",
	"intelligence": "智力", "faith": "信仰", "arcane": "感应", "move_range": "移动"
}
const CAP_MAX_LEVEL : int = 3

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
var _avatar_ids : Array = []
var _current_unit_key : String = ""

# ---- 通用 UI ----
var _tab_btns : Array = []
var _tab_panels : Array = []

# ---- 单位编辑 UI ----
var _edit_unit_list : VBoxContainer = null
var _edit_status : Label = null
var _edit_name_edit : LineEdit = null
var _edit_faction_edit : LineEdit = null
var _edit_desc_edit : TextEdit = null
var _edit_flavor_edit : TextEdit = null
var _edit_avatar_opt : OptionButton = null
var _edit_attr_spins : Dictionary = {}
var _edit_weapon_opt : OptionButton = null
var _edit_armor_opts : Array = []
var _edit_talent_opts : Array = []
var _edit_tags_cbs : Dictionary = {}
var _edit_core_opt : OptionButton = null
var _edit_sac_type_opt : OptionButton = null
var _edit_sac_value_spin : SpinBox = null
var _edit_sac_display_edit : LineEdit = null
var _edit_cap_spins : Dictionary = {}
var _edit_branches_box : VBoxContainer = null
var _edit_branch_cards : Array = []

# ---- 战斗模拟 UI ----
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

# ---- 校验 UI ----
var _validator_output : RichTextLabel = null
var _validator_status : Label = null
var _validator_last_errors : int = 0
var _validator_last_warns : int = 0

# ---- 单位解锁 UI ----
var _unit_unlock_data : Dictionary = {}
var _unit_unlock_selected : String = ""
var _unit_unlock_list_box : VBoxContainer = null
var _unit_unlock_mapping_box : VBoxContainer = null
var _unit_unlock_status : Label = null
var _unit_unlock_right_title : Label = null
var _unit_db_dirty : bool = false

func _ready():
	_apply_compact_theme()
	_load_all_data()
	_build_ui()
	_refresh_unit_list()
	_refresh_sim_unit_lists()
	if _unit_keys.size() > 0:
		_select_edit_unit(_unit_keys[0])
	call_deferred("_auto_validate")


# ============================================================
#  全局主题
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

	# ---- LineEdit / TextEdit ----
	t.set_font_size("font_size", "LineEdit", FS_BUTTON)
	t.set_font_size("font_size", "TextEdit", FS_BUTTON)
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
	
	# ---- PopupMenu ----
	t.set_font_size("font_size", "PopupMenu", FS_SMALL)
	t.set_font_size("font_separator_size", "PopupMenu", FS_SMALL)
	t.set_constant("item_start_padding", "PopupMenu", 3)
	t.set_constant("item_end_padding", "PopupMenu", 3)
	t.set_constant("v_separation", "PopupMenu", 0)
	t.set_constant("h_separation", "PopupMenu", 0)
	t.set_constant("icon_max_width", "PopupMenu", 6)

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

	# ---- VSeparator / HSeparator ----
	var sep_sb := StyleBoxLine.new()
	sep_sb.color = COL_VSEP
	sep_sb.thickness = 1
	sep_sb.vertical = true
	sep_sb.grow_begin = 2
	sep_sb.grow_end = 2
	t.set_stylebox("separator", "VSeparator", sep_sb)

	var hsep_sb := StyleBoxLine.new()
	hsep_sb.color = COL_VSEP
	hsep_sb.thickness = 1
	hsep_sb.vertical = false
	t.set_stylebox("separator", "HSeparator", hsep_sb)

	# ---- SpinBox ----
	t.set_font_size("font_size", "SpinBox", FS_BUTTON)

	# ---- CheckBox ----
	t.set_font_size("font_size", "CheckBox", FS_LABEL)

	_setup_scrollbar_theme(t)
	_setup_slider_theme(t)

	theme = t


func _setup_scrollbar_theme(t : Theme):
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.08, 0.10, 1)

	var grab_off := StyleBoxFlat.new()
	grab_off.bg_color = Color(0.32, 0.32, 0.38, 1)
	grab_off.corner_radius_top_left = 2
	grab_off.corner_radius_top_right = 2
	grab_off.corner_radius_bottom_left = 2
	grab_off.corner_radius_bottom_right = 2

	var grab_hl := StyleBoxFlat.new()
	grab_hl.bg_color = Color(0.55, 0.55, 0.65, 1)
	grab_hl.corner_radius_top_left = 2
	grab_hl.corner_radius_top_right = 2
	grab_hl.corner_radius_bottom_left = 2
	grab_hl.corner_radius_bottom_right = 2

	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab_off)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hl)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hl)
	t.set_constant("minimum_grab_size", "VScrollBar", 6)
	t.set_constant("scroll_width", "VScrollBar", 4)

	t.set_stylebox("scroll", "HScrollBar", track)
	t.set_stylebox("scroll_focus", "HScrollBar", track)
	t.set_stylebox("grabber", "HScrollBar", grab_off)
	t.set_stylebox("grabber_highlight", "HScrollBar", grab_hl)
	t.set_stylebox("grabber_pressed", "HScrollBar", grab_hl)
	t.set_constant("minimum_grab_size", "HScrollBar", 6)
	t.set_constant("scroll_height", "HScrollBar", 4)


func _setup_slider_theme(t : Theme):
	var slider_sb := StyleBoxFlat.new()
	slider_sb.bg_color = Color(0.22, 0.22, 0.28, 1.0)
	slider_sb.content_margin_top = 1.5
	slider_sb.content_margin_bottom = 1.5
	t.set_stylebox("slider", "HSlider", slider_sb)

	var grab_sb := StyleBoxFlat.new()
	grab_sb.bg_color = Color(0.55, 0.55, 0.60, 1.0)
	grab_sb.content_margin_top = 1.5
	grab_sb.content_margin_bottom = 1.5
	t.set_stylebox("grabber_area", "HSlider", grab_sb)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab_sb)

	var img := Image.create(2, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.78, 0.78, 0.82, 1.0))
	var tex := ImageTexture.create_from_image(img)
	t.set_icon("grabber", "HSlider", tex)
	t.set_icon("grabber_highlight", "HSlider", tex)
	t.set_icon("grabber_disabled", "HSlider", tex)
	t.set_constant("center_grabber", "HSlider", 1)
	t.set_constant("grabber_offset", "HSlider", 0)


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

	_unit_unlock_data = _load_json(UNIT_UNLOCK_PATH)

	_weapon_ids.clear()
	_armor_ids.clear()
	for iid in ItemManager.get_all_item_ids():
		var d = ItemManager.get_item_data(iid)
		if d == null: continue
		if d.type == "weapon": _weapon_ids.append(iid)
		elif d.type == "armor": _armor_ids.append(iid)
	_weapon_ids.sort()
	_armor_ids.sort()
	_talent_ids = TalentManager.get_all_talent_ids()
	
	_avatar_ids.clear()
	if DirAccess.dir_exists_absolute(AVATAR_DIR):
		var dir = DirAccess.open(AVATAR_DIR)
		if dir:
			dir.list_dir_begin()
			var fname = dir.get_next()
			while fname != "":
				if not dir.current_is_dir() and fname.ends_with(".png"):
					_avatar_ids.append(fname.get_basename())
				fname = dir.get_next()
			dir.list_dir_end()
	_avatar_ids.sort()


func _load_json(path : String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
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
#  主 UI
# ============================================================
func _build_ui():
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 4
	root.offset_top = 3
	root.offset_right = -4
	root.offset_bottom = -3
	root.add_theme_constant_override("separation", 2)
	add_child(root)

	var tab_scroll := ScrollContainer.new()
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.custom_minimum_size = Vector2(0, 20)
	root.add_child(tab_scroll)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 2)
	tab_scroll.add_child(tab_bar)

	var tab_names : Array = ["单位编辑", "战斗模拟", "数值编辑", "套装", "词条池", "光环", "单位解锁", "校验"]
	for i in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", FS_PANEL)
		btn.custom_minimum_size = Vector2(0, 18)
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
	_tab_panels.append(_build_set_bonus_tab(body))
	_tab_panels.append(_build_affix_tab(body))
	_tab_panels.append(_build_aura_tab(body))
	_tab_panels.append(_build_unit_unlock_tab(body))
	_tab_panels.append(_build_validator_tab(body))

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

	left.add_child(_section("— 单位列表 —"))

	var l_scroll := ScrollContainer.new()
	l_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(l_scroll)

	_edit_unit_list = VBoxContainer.new()
	_edit_unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_unit_list.add_theme_constant_override("separation", 1)
	l_scroll.add_child(_edit_unit_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 2)
	panel.add_child(right)

	var r_scroll := ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(r_scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 2)
	r_scroll.add_child(content)

	# ---- 基础信息 ----
	content.add_child(_section("— 基础信息 —"))
	_edit_name_edit = _add_edit_row(content, "显示名")
	_edit_faction_edit = _add_edit_row(content, "阵营")
	_edit_avatar_opt = _add_option_row(content, "头像", _avatar_ids, "（无）")

	var desc_row := HBoxContainer.new()
	desc_row.add_theme_constant_override("separation", 3)
	content.add_child(desc_row)
	desc_row.add_child(_lbl("简介", 40))
	_edit_desc_edit = TextEdit.new()
	_edit_desc_edit.custom_minimum_size = Vector2(0, 40)
	_edit_desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc_row.add_child(_edit_desc_edit)
	
	var flavor_row := HBoxContainer.new()
	flavor_row.add_theme_constant_override("separation", 3)
	content.add_child(flavor_row)
	flavor_row.add_child(_lbl("叙事", 40))
	_edit_flavor_edit = TextEdit.new()
	_edit_flavor_edit.custom_minimum_size = Vector2(0, 60)
	_edit_flavor_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_flavor_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	flavor_row.add_child(_edit_flavor_edit)

	# ---- 属性 ----
	content.add_child(_section("— 基础属性 —"))
	var attr_grid := GridContainer.new()
	attr_grid.columns = 2
	attr_grid.add_theme_constant_override("h_separation", 6)
	attr_grid.add_theme_constant_override("v_separation", 1)
	content.add_child(attr_grid)

	for a in EDITABLE_ATTRS:
		attr_grid.add_child(_lbl(a["label"], 30))
		var sp := SpinBox.new()
		sp.min_value = a["min"]
		sp.max_value = a["max"]
		sp.step = 1
		sp.custom_minimum_size = Vector2(60, 16)
		attr_grid.add_child(sp)
		_style_spin(sp)
		_edit_attr_spins[a["key"]] = sp

	# ---- 标签 ----
	content.add_child(_section("— 单位标签 —"))
	var tag_flow := HFlowContainer.new()
	tag_flow.add_theme_constant_override("h_separation", 8)
	tag_flow.add_theme_constant_override("v_separation", 2)
	content.add_child(tag_flow)
	_edit_tags_cbs.clear()
	for tag in UNIT_TAGS:
		var cb := CheckBox.new()
		cb.text = tag
		tag_flow.add_child(cb)
		_edit_tags_cbs[tag] = cb

	# ---- 核心特性 ----
	content.add_child(_section("— 核心特性 —"))
	var ct_row := HBoxContainer.new()
	ct_row.add_theme_constant_override("separation", 3)
	content.add_child(ct_row)
	ct_row.add_child(_lbl("特性", 40))
	_edit_core_opt = OptionButton.new()
	_edit_core_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(CORE_TRAITS.size()):
		var k = CORE_TRAITS[i]
		_edit_core_opt.add_item(CORE_TRAITS_MAP.get(k, k), i)
		_edit_core_opt.set_item_metadata(i, k)
	ct_row.add_child(_edit_core_opt)

	# ---- 献祭 buff ----
	content.add_child(_section("— 献祭 Buff —"))
	var sac_type_row := HBoxContainer.new()
	sac_type_row.add_theme_constant_override("separation", 3)
	content.add_child(sac_type_row)
	sac_type_row.add_child(_lbl("类型", 40))
	_edit_sac_type_opt = OptionButton.new()
	_edit_sac_type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(SAC_BUFF_TYPES.size()):
		var t = SAC_BUFF_TYPES[i]
		_edit_sac_type_opt.add_item(SAC_BUFF_TYPES_CN.get(t, t), i)
		_edit_sac_type_opt.set_item_metadata(i, t)
	sac_type_row.add_child(_edit_sac_type_opt)

	var sac_val_row := HBoxContainer.new()
	sac_val_row.add_theme_constant_override("separation", 3)
	content.add_child(sac_val_row)
	sac_val_row.add_child(_lbl("数值", 40))
	_edit_sac_value_spin = SpinBox.new()
	_edit_sac_value_spin.min_value = 0.0
	_edit_sac_value_spin.max_value = 1.0
	_edit_sac_value_spin.step = 0.05
	_edit_sac_value_spin.custom_minimum_size = Vector2(80, 16)
	sac_val_row.add_child(_edit_sac_value_spin)
	_style_spin(_edit_sac_value_spin)

	var sac_disp_row := HBoxContainer.new()
	sac_disp_row.add_theme_constant_override("separation", 3)
	content.add_child(sac_disp_row)
	sac_disp_row.add_child(_lbl("提示", 40))
	_edit_sac_display_edit = LineEdit.new()
	_edit_sac_display_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sac_disp_row.add_child(_edit_sac_display_edit)

	# ---- 默认装备 ----
	content.add_child(_section("— 默认装备 —"))
	_edit_weapon_opt = _add_option_row(content, "武器", _weapon_ids, "（无）")

	content.add_child(_section("— 默认防具 —"))
	_edit_armor_opts.clear()
	for i in range(2):
		_edit_armor_opts.append(_add_option_row(content, "防具%d" % (i + 1), _armor_ids, "（无）"))

	content.add_child(_section("— 默认特技 —"))
	_edit_talent_opts.clear()
	for i in range(2):
		_edit_talent_opts.append(_add_option_row(content, "特技%d" % (i + 1), _talent_ids, "（无）"))

	content.add_child(HSeparator.new())

	# ---- 属性上限 ----
	content.add_child(_section("— 属性上限（净增）—"))
	_rebuild_attr_cap_grid(content)

	content.add_child(HSeparator.new())

	# ---- 转职分支 ----
	var branch_header := HBoxContainer.new()
	branch_header.add_theme_constant_override("separation", 4)
	content.add_child(branch_header)
	branch_header.add_child(_section("— 转职分支 —"))

	var add_branch_btn := Button.new()
	add_branch_btn.text = "+ 添加分支"
	add_branch_btn.pressed.connect(_add_branch_card)
	branch_header.add_child(add_branch_btn)

	var clear_branches_btn := Button.new()
	clear_branches_btn.text = "清空全部"
	clear_branches_btn.modulate = Color(1.0, 0.6, 0.6)
	clear_branches_btn.pressed.connect(_clear_all_branches)
	branch_header.add_child(clear_branches_btn)

	_edit_branches_box = VBoxContainer.new()
	_edit_branches_box.add_theme_constant_override("separation", 4)
	content.add_child(_edit_branches_box)

	# ---- 底部按钮 ----
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 4)
	right.add_child(btn_row)

	var reset_btn := Button.new()
	reset_btn.text = "重置"
	reset_btn.pressed.connect(_reset_unit_db)
	btn_row.add_child(reset_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_save_unit_db)
	btn_row.add_child(save_btn)

	_edit_status = Label.new()
	_edit_status.modulate = Color(0.7, 0.9, 0.7)
	btn_row.add_child(_edit_status)

	return panel


# ============================================================
#  属性上限表
# ============================================================
func _rebuild_attr_cap_grid(parent : Node):
	_edit_cap_spins.clear()
	var grid := GridContainer.new()
	grid.columns = 1 + CAP_MAX_LEVEL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)

	grid.add_child(_lbl("", 30))
	for lv in range(CAP_MAX_LEVEL):
		grid.add_child(_lbl("Lv%d" % (lv + 1), 40))

	for attr in CAP_ATTRS:
		grid.add_child(_lbl(CAP_ATTR_LABELS.get(attr, attr), 30))
		var lv_spins : Dictionary = {}
		for lv in range(CAP_MAX_LEVEL):
			var sp := SpinBox.new()
			sp.min_value = 0
			sp.max_value = 9
			sp.step = 1
			sp.value = 0
			sp.custom_minimum_size = Vector2(40, 16)
			grid.add_child(sp)
			_style_spin(sp)
			lv_spins[lv] = sp
		_edit_cap_spins[attr] = lv_spins


func _read_attr_cap_levels() -> Array:
	var result : Array = []
	for lv in range(CAP_MAX_LEVEL):
		var lv_dict : Dictionary = {}
		for attr in CAP_ATTRS:
			var sp : SpinBox = _edit_cap_spins.get(attr, {}).get(lv, null)
			if sp == null: continue
			var v : int = int(sp.value)
			if v > 0:
				lv_dict[attr] = v
		result.append(lv_dict)
	return result


func _fill_attr_cap_levels(data : Array):
	for attr in CAP_ATTRS:
		var lv_spins : Dictionary = _edit_cap_spins.get(attr, {})
		for lv in range(CAP_MAX_LEVEL):
			var sp : SpinBox = lv_spins.get(lv, null)
			if sp == null: continue
			var v : int = 0
			if lv < data.size() and data[lv] is Dictionary:
				v = int(data[lv].get(attr, 0))
			sp.value = v


# ============================================================
#  转职分支卡片
# ============================================================
func _rebuild_branches(data : Array):
	for c in _edit_branches_box.get_children():
		_edit_branches_box.remove_child(c)
		c.queue_free()
	_edit_branch_cards.clear()

	for branch in data:
		if branch is Dictionary:
			_add_branch_card_with_data(branch, false)


func _add_branch_card():
	_add_branch_card_with_data({}, true)


func _clear_all_branches():
	if _edit_branch_cards.is_empty():
		return
	Globals.show_confirm(
		self,
		"确定清空该单位的所有转职分支吗？\n（保存后写入 JSON 生效）",
		"清空", "取消",
		func():
			for c in _edit_branches_box.get_children():
				_edit_branches_box.remove_child(c)
				c.queue_free()
			_edit_branch_cards.clear(),
		func(): pass
	)


func _add_branch_card_with_data(d : Dictionary, is_new : bool = false):
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.16, 1)
	sb.border_color = Color(0.25, 0.25, 0.3, 1)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", sb)
	_edit_branches_box.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var card_refs : Dictionary = {}

	# id
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	vbox.add_child(head)
	head.add_child(_lbl("代码ID:", 40))
	var id_edit := LineEdit.new()
	id_edit.text = d.get("id", "")
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(id_edit)
	card_refs["id"] = id_edit

	var del_btn := Button.new()
	del_btn.text = "删除分支"
	del_btn.modulate = Color(1.0, 0.5, 0.5)
	del_btn.custom_minimum_size = Vector2(50, 16)
	del_btn.pressed.connect(func():
		_edit_branch_cards.erase(card_refs)
		card.queue_free()
	)
	head.add_child(del_btn)

	# name
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 3)
	vbox.add_child(name_row)
	name_row.add_child(_lbl("职业名", 40))
	var name_edit := LineEdit.new()
	name_edit.text = d.get("name", "")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	card_refs["name"] = name_edit

	# desc
	var desc_row := HBoxContainer.new()
	desc_row.add_theme_constant_override("separation", 3)
	vbox.add_child(desc_row)
	desc_row.add_child(_lbl("简介", 40))
	var desc_edit := LineEdit.new()
	desc_edit.text = d.get("description", "")
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_row.add_child(desc_edit)
	card_refs["description"] = desc_edit

	# granted_talent
	var tal_row := HBoxContainer.new()
	tal_row.add_theme_constant_override("separation", 3)
	vbox.add_child(tal_row)
	tal_row.add_child(_lbl("赋予特技", 40))
	var tal_opt := OptionButton.new()
	tal_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tal_opt.add_item("（无）", 0)
	tal_opt.set_item_metadata(0, "")
	for i in range(_talent_ids.size()):
		var tid : String = _talent_ids[i]
		var tdata = TalentManager.get_talent_data(tid)
		var tname : String = tdata.display_name if tdata else tid
		tal_opt.add_item(tname, i + 1)
		tal_opt.set_item_metadata(i + 1, tid)
	var cur_tal : String = d.get("granted_talent", "")
	var matched : bool = false
	for i in range(tal_opt.item_count):
		var m = tal_opt.get_item_metadata(i)
		if m != null and str(m) == cur_tal:
			tal_opt.selected = i
			matched = true
			break
	if is_new and not matched and _talent_ids.size() > 0:
		tal_opt.selected = 1
	tal_row.add_child(tal_opt)
	card_refs["granted_talent"] = tal_opt

	# sprite_frames_path
	var sprite_row := HBoxContainer.new()
	sprite_row.add_theme_constant_override("separation", 3)
	vbox.add_child(sprite_row)
	sprite_row.add_child(_lbl("精灵图", 40))
	var sprite_edit := LineEdit.new()
	sprite_edit.text = d.get("sprite_frames_path", "")
	sprite_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprite_edit.placeholder_text = "res://.../*_frames.tres"
	sprite_row.add_child(sprite_edit)
	card_refs["sprite_frames_path"] = sprite_edit

	# flavor
	var flavor_row := HBoxContainer.new()
	flavor_row.add_theme_constant_override("separation", 3)
	vbox.add_child(flavor_row)
	flavor_row.add_child(_lbl("风味文", 40))
	var flavor_edit := LineEdit.new()
	flavor_edit.text = d.get("flavor", "")
	flavor_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flavor_row.add_child(flavor_edit)
	card_refs["flavor"] = flavor_edit

	# stat_bonus
	vbox.add_child(_section("属性加成 (stat_bonus)"))
	var stat_row := HFlowContainer.new()
	stat_row.add_theme_constant_override("h_separation", 6)
	stat_row.add_theme_constant_override("v_separation", 2)
	vbox.add_child(stat_row)

	var stat_bonus : Dictionary = d.get("stat_bonus", {})
	var stat_spins : Dictionary = {}
	for key in BRANCH_STAT_KEYS:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 2)
		stat_row.add_child(pair)
		pair.add_child(_lbl(BRANCH_STAT_LABELS.get(key, key), 0))
		var sp := SpinBox.new()
		sp.min_value = -20
		sp.max_value = 99
		sp.step = 1
		sp.value = int(stat_bonus.get(key, 0))
		sp.custom_minimum_size = Vector2(40, 16)
		pair.add_child(sp)
		_style_spin(sp)
		stat_spins[key] = sp
	card_refs["stat_spins"] = stat_spins

	# tags
	vbox.add_child(_section("标签 (tags)"))
	var tag_flow := HFlowContainer.new()
	tag_flow.add_theme_constant_override("h_separation", 8)
	tag_flow.add_theme_constant_override("v_separation", 2)
	vbox.add_child(tag_flow)

	var branch_tags : Array = d.get("tags", [])
	var tag_cbs : Dictionary = {}
	for tag in UNIT_TAGS:
		var cb := CheckBox.new()
		cb.text = tag
		cb.button_pressed = tag in branch_tags
		tag_flow.add_child(cb)
		tag_cbs[tag] = cb
	card_refs["tag_cbs"] = tag_cbs

	_edit_branch_cards.append(card_refs)


func _read_branches() -> Array:
	var result : Array = []
	for card in _edit_branch_cards:
		if not is_instance_valid(card.get("id", null)): continue
		var b : Dictionary = {}
		b["id"] = card["id"].text.strip_edges()
		b["name"] = card["name"].text
		b["description"] = card["description"].text
		b["granted_talent"] = _get_meta(card["granted_talent"])
		b["sprite_frames_path"] = card["sprite_frames_path"].text
		b["flavor"] = card["flavor"].text

		var stat_bonus : Dictionary = {}
		for key in card["stat_spins"]:
			var v : int = int(card["stat_spins"][key].value)
			if v != 0:
				stat_bonus[key] = v
		b["stat_bonus"] = stat_bonus

		var tags : Array = []
		for tag in card["tag_cbs"]:
			if card["tag_cbs"][tag].button_pressed:
				tags.append(tag)
		b["tags"] = tags

		if b["id"] != "":
			result.append(b)
	return result


# ============================================================
#  单位列表 / 加载 / 保存
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
	_edit_desc_edit.text = d.get("description", "")
	_edit_flavor_edit.text = d.get("flavor", "")

	if _edit_avatar_opt:
		_select_option_by_meta(_edit_avatar_opt, d.get("avatar", ""))

	for a in EDITABLE_ATTRS:
		_edit_attr_spins[a["key"]].value = d.get(a["key"], 0)

	var unit_tags : Array = d.get("tags", [])
	for tag in UNIT_TAGS:
		_edit_tags_cbs[tag].button_pressed = tag in unit_tags

	var core : String = d.get("core_trait", "")
	_select_option_by_meta(_edit_core_opt, core)

	var sac : Dictionary = d.get("sacrifice_buff", {})
	_select_option_by_meta(_edit_sac_type_opt, sac.get("type", ""))
	_edit_sac_value_spin.value = float(sac.get("value", 0))
	_edit_sac_display_edit.text = sac.get("display", "")

	if _edit_weapon_opt:
		_select_option_by_meta(_edit_weapon_opt, d.get("default_weapon", ""))
	var armor_list : Array = d.get("default_armors", [])
	for i in range(_edit_armor_opts.size()):
		var aid : String = armor_list[i] if i < armor_list.size() else ""
		_select_option_by_meta(_edit_armor_opts[i], aid)
	var talent_list : Array = d.get("default_talents", [])
	for i in range(_edit_talent_opts.size()):
		var tid : String = talent_list[i] if i < talent_list.size() else ""
		_select_option_by_meta(_edit_talent_opts[i], tid)

	_fill_attr_cap_levels(d.get("attr_cap_levels", []))
	_rebuild_branches(d.get("advanced_branches", []))


func _select_option_by_meta(opt : OptionButton, target_id : String):
	if opt == null: return
	opt.selected = 0
	for i in range(opt.item_count):
		var m = opt.get_item_metadata(i)
		if m != null and str(m) == target_id:
			opt.selected = i
			return


func _reset_unit_db():
	_unit_db = _load_json(UNIT_DATA_PATH)
	_unit_keys = _unit_db.keys()
	_unit_keys.sort()
	_refresh_unit_list()
	_refresh_sim_unit_lists()
	UnitDataManager.reload_all()
	if _current_unit_key != "" and _unit_db.has(_current_unit_key):
		_select_edit_unit(_current_unit_key)
	_edit_status.text = "已重置"


func _save_unit_db():
	if _current_unit_key == "": return
	var d : Dictionary = _unit_db[_current_unit_key]

	d["display_name"] = _edit_name_edit.text
	d["faction"] = _edit_faction_edit.text
	d["description"] = _edit_desc_edit.text
	d["flavor"] = _edit_flavor_edit.text
	
	if _edit_avatar_opt:
		var a_id = _get_meta(_edit_avatar_opt)
		if a_id != "":
			d["avatar"] = a_id
		else:
			d.erase("avatar")

	for a in EDITABLE_ATTRS:
		d[a["key"]] = int(_edit_attr_spins[a["key"]].value)

	var tags : Array = []
	for tag in UNIT_TAGS:
		if _edit_tags_cbs[tag].button_pressed:
			tags.append(tag)
	d["tags"] = tags

	var core : String = _get_meta(_edit_core_opt)
	if core != "":
		d["core_trait"] = core
	else:
		d.erase("core_trait")

	var sac_type : String = _get_meta(_edit_sac_type_opt)
	if sac_type != "":
		d["sacrifice_buff"] = {
			"type": sac_type,
			"value": float(_edit_sac_value_spin.value),
			"display": _edit_sac_display_edit.text,
		}
	else:
		d.erase("sacrifice_buff")

	if _edit_weapon_opt:
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

	d["attr_cap_levels"] = _read_attr_cap_levels()

	var branches : Array = _read_branches()
	if branches.is_empty():
		d.erase("advanced_branches")
	else:
		d["advanced_branches"] = branches

	var f := FileAccess.open(UNIT_DATA_PATH, FileAccess.WRITE)
	if f == null:
		_edit_status.text = "❌ 保存失败"
		return
	f.store_string(JSON.stringify(_unit_db, "  "))
	f.close()

	UnitDataManager.reload_all()
	_refresh_sim_unit_lists()

	_edit_status.text = "✓ 已保存"
	print("[GameDataEditor] unit_data.json 已保存")


func _get_meta(opt : OptionButton) -> String:
	if opt == null: return ""
	var idx : int = opt.selected
	if idx < 0: return ""
	var m = opt.get_item_metadata(idx)
	return str(m) if m != null else ""


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

	inner.add_child(_center_label("— %s —" % title))

	var unit_opt := OptionButton.new()
	if is_player: _sim_player_opt = unit_opt
	else: _sim_enemy_opt = unit_opt
	inner.add_child(unit_opt)

	_add_sep_label(inner, "装备")
	var weapon_opt := _add_option_row(inner, "武器", _weapon_ids, "默认")
	var up_lv_opt := _add_int_option_row(inner, "武器强化", 0, 5)
	var a1 := _add_option_row(inner, "防具1", _armor_ids, "默认")
	var a2 := _add_option_row(inner, "防具2", _armor_ids, "默认")

	_add_sep_label(inner, "特技")
	var t1 := _add_option_row(inner, "特技1", _talent_ids, "默认")
	var t2 := _add_option_row(inner, "特技2", _talent_ids, "默认")

	_add_sep_label(inner, "遗物")
	var relic_checks : Array = []
	for i in range(_relic_keys.size()):
		var rid : String = _relic_keys[i]
		var rname : String = _relic_db[rid].get("name", rid)
		var cb := CheckBox.new()
		cb.text = rname
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
	lb.modulate = Color(0.75, 0.8, 0.9)
	parent.add_child(lb)


func _add_int_option_row(parent : Node, label : String, min_v : int, max_v : int) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	row.add_child(_lbl(label, 40))
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	vbox.add_child(_center_label("— 战斗日志 —"))

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 4)
	ctrl.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(ctrl)

	_sim_talent_cb = CheckBox.new()
	_sim_talent_cb.text = "词条生效"
	_sim_talent_cb.button_pressed = true
	ctrl.add_child(_sim_talent_cb)

	_sim_counter_cb = CheckBox.new()
	_sim_counter_cb.text = "开启反击"
	_sim_counter_cb.button_pressed = true
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
	scroll.add_child(_sim_log)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_row)

	var start_btn := Button.new()
	start_btn.text = "开始模拟"
	start_btn.pressed.connect(_run_simulation)
	btn_row.add_child(start_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空日志"
	clear_btn.pressed.connect(func(): _sim_log.clear())
	btn_row.add_child(clear_btn)

	_sim_status = Label.new()
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
	var editor = preload(JSON_EDITOR_SCRIPT).new()
	editor.setup(path)
	return editor


func _build_set_bonus_tab(parent : Control) -> Control:
	var editor = preload(JSON_EDITOR_SCRIPT).new()
	editor.setup(SET_BONUS_PATH, "套装 + 交叉效果")
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(editor)
	return editor


func _build_affix_tab(parent : Control) -> Control:
	var editor = preload(JSON_EDITOR_SCRIPT).new()
	editor.setup(AFFIX_PATH, "防具词条池")
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(editor)
	return editor


func _build_aura_tab(parent : Control) -> Control:
	var editor = preload(JSON_EDITOR_SCRIPT).new()
	editor.setup(AURA_PATH, "光环")
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(editor)
	return editor


# ============================================================
#  Tab 7：单位解锁（地图解锁单位 → 可唤醒单位）
# ============================================================
func _build_unit_unlock_tab(parent : Control) -> Control:
	var panel := HBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 12)
	parent.add_child(panel)

	# ================= 左列：地图解锁池 =================
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(180, 0)
	left.add_theme_constant_override("separation", 4)
	panel.add_child(left)

	var l_title := Label.new()
	l_title.text = "— 地图解锁池 —"
	l_title.add_theme_font_size_override("font_size", FS_PANEL)
	l_title.modulate = Color(0.85, 0.85, 1.0)
	left.add_child(l_title)
	
	var l_hint := Label.new()
	l_hint.text = "只有这里的单位，才能配给地图节点。\n点下方【+ 添加】把新单位放入池中。"
	l_hint.add_theme_font_size_override("font_size", FS_SMALL)
	l_hint.modulate = Color(0.6, 0.6, 0.6)
	l_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(l_hint)

	var l_scroll := ScrollContainer.new()
	l_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(l_scroll)

	_unit_unlock_list_box = VBoxContainer.new()
	_unit_unlock_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_unlock_list_box.add_theme_constant_override("separation", 2)
	l_scroll.add_child(_unit_unlock_list_box)

	var l_btns := HBoxContainer.new()
	l_btns.add_theme_constant_override("separation", 4)
	left.add_child(l_btns)

	var add_btn := Button.new()
	add_btn.text = "+ 添加"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_on_unit_unlock_add)
	l_btns.add_child(add_btn)

	var del_btn := Button.new()
	del_btn.text = "- 移除选中"
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_btn.modulate = Color(1.0, 0.6, 0.6)
	del_btn.pressed.connect(_on_unit_unlock_remove)
	l_btns.add_child(del_btn)

	# ================= 右列：可唤醒单位映射 =================
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	panel.add_child(right)

	_unit_unlock_right_title = Label.new()
	_unit_unlock_right_title.text = "— 选中项 → 节点完成后唤醒列表出现： —"
	_unit_unlock_right_title.add_theme_font_size_override("font_size", FS_PANEL)
	_unit_unlock_right_title.modulate = Color(0.85, 0.85, 1.0)
	right.add_child(_unit_unlock_right_title)

	var r_scroll := ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(r_scroll)

	_unit_unlock_mapping_box = VBoxContainer.new()
	_unit_unlock_mapping_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_unlock_mapping_box.add_theme_constant_override("separation", 4)
	r_scroll.add_child(_unit_unlock_mapping_box)

	var r_btns := HBoxContainer.new()
	r_btns.add_theme_constant_override("separation", 4)
	right.add_child(r_btns)

	_unit_unlock_status = Label.new()
	_unit_unlock_status.modulate = Color(0.7, 0.9, 0.7)
	_unit_unlock_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_unlock_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r_btns.add_child(_unit_unlock_status)

	var reload_btn := Button.new()
	reload_btn.text = "重置"
	reload_btn.pressed.connect(func():
		_unit_unlock_data = _load_json(UNIT_UNLOCK_PATH)
		_unit_unlock_selected = ""
		_refresh_unit_unlock_ui()
		if _unit_unlock_status: _unit_unlock_status.text = "已重载"
	)
	r_btns.add_child(reload_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.modulate = Color(0.7, 1.0, 0.7)
	save_btn.pressed.connect(_save_unit_unlock_config)
	r_btns.add_child(save_btn)

	call_deferred("_refresh_unit_unlock_ui")
	return panel


func _refresh_unit_unlock_ui():
	_refresh_unit_unlock_list()
	_refresh_unit_unlock_mapping()


func _refresh_unit_unlock_list():
	if _unit_unlock_list_box == null: return
	
	for c in _unit_unlock_list_box.get_children():
		_unit_unlock_list_box.remove_child(c)
		c.queue_free()

	if not _unit_unlock_data.has("map_unlock_units"):
		_unit_unlock_data["map_unlock_units"] = []
		
	var map_units: Array = _unit_unlock_data["map_unlock_units"]
	var mapping: Dictionary = _unit_unlock_data.get("map_unlock_mapping", {})

	if map_units.is_empty():
		var hint := Label.new()
		hint.text = "（空）请点下方添加"
		hint.add_theme_font_size_override("font_size", FS_SMALL)
		hint.modulate = Color(0.6, 0.6, 0.6)
		_unit_unlock_list_box.add_child(hint)
		_unit_unlock_selected = ""
		return

	for uid in map_units:
		var dict : Dictionary = UnitDataManager.get_unit_data(uid)
		var display : String = dict.get("display_name", uid)
		var faction : String = dict.get("faction", "无阵营")
		var mapped_count: int = mapping.get(uid, []).size()
		var suffix : String = " [%s]" % faction if mapped_count > 0 else ""
		
		var btn := Button.new()
		btn.text = "%s (%s)%s" % [display, uid, suffix]
		btn.toggle_mode = true
		btn.button_pressed = (uid == _unit_unlock_selected)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_meta("uid", uid)
		btn.pressed.connect(_on_unit_unlock_selected.bind(uid))
		_unit_unlock_list_box.add_child(btn)

	if _unit_unlock_selected == "" or _unit_unlock_selected not in map_units:
		_on_unit_unlock_selected(map_units[0])


func _on_unit_unlock_selected(uid : String):
	_unit_unlock_selected = uid
	for c in _unit_unlock_list_box.get_children():
		if c is Button:
			c.button_pressed = (c.get_meta("uid", "") == uid)
	_refresh_unit_unlock_mapping()


func _refresh_unit_unlock_mapping():
	if _unit_unlock_mapping_box == null: return

	for c in _unit_unlock_mapping_box.get_children():
		_unit_unlock_mapping_box.remove_child(c)
		c.queue_free()

	if _unit_unlock_selected == "":
		_unit_unlock_right_title.text = "— 请先选择左侧单位 —"
		return

	var src_dict : Dictionary = UnitDataManager.get_unit_data(_unit_unlock_selected)
	var display_src : String = src_dict.get("display_name", _unit_unlock_selected)
	var src_faction : String = src_dict.get("faction", "无阵营")
	
	_unit_unlock_right_title.text = "打地图获得「%s」(阵营: %s) 时，唤醒列表出现：" % [display_src, src_faction]

	var mapping: Dictionary = _unit_unlock_data.get("map_unlock_mapping", {})
	var current_list: Array = mapping.get(_unit_unlock_selected, [])

	var assigned_to_other := {}
	for s_uid in mapping:
		if s_uid == _unit_unlock_selected: continue
		for t_uid in mapping[s_uid]:
			assigned_to_other[t_uid] = s_uid

	var available_units := []
	var transferred_units := []
	var all_unit_ids := UnitDataManager.get_all_unit_ids()
	
	for uid in all_unit_ids:
		var other_src = assigned_to_other.get(uid, "")
		var is_checked = uid in current_list
		
		if other_src != "" and not is_checked:
			transferred_units.append({"uid": uid, "by": other_src})
		else:
			available_units.append(uid)

	for uid in available_units:
		var dict : Dictionary = UnitDataManager.get_unit_data(uid)
		var display : String = dict.get("display_name", uid)
		var faction : String = dict.get("faction", "无阵营")
		
		var cb := CheckBox.new()
		cb.add_theme_font_size_override("font_size", FS_LABEL)
		cb.button_pressed = (uid in current_list)
		cb.toggled.connect(_on_mapping_toggled.bind(_unit_unlock_selected, uid))
		
		var is_faction_match : bool = (faction == src_faction)
		if is_faction_match:
			cb.text = "%s (%s) [%s]" % [display, uid, faction]
			cb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		else:
			cb.text = "%s (%s) [%s → %s]" % [display, uid, faction, src_faction]
			cb.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
			cb.tooltip_text = "勾选后，将自动把该单位的阵营同步为「%s」" % src_faction

		_unit_unlock_mapping_box.add_child(cb)

	if transferred_units.size() > 0:
		var sep := HSeparator.new()
		sep.modulate = Color(0.4, 0.4, 0.4)
		_unit_unlock_mapping_box.add_child(sep)

		var lbl := Label.new()
		lbl.text = "↓ 以下单位已被其他地图池单位分配 ↓"
		lbl.add_theme_font_size_override("font_size", FS_SMALL)
		lbl.modulate = Color(0.7, 0.6, 0.6)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_unit_unlock_mapping_box.add_child(lbl)

		for entry in transferred_units:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			
			var lb := Label.new()
			lb.text = "%s (%s)  [已被 %s 分配]" % [
				UnitDataManager.get_display_name(entry.uid), 
				entry.uid, 
				UnitDataManager.get_display_name(entry.by)
			]
			lb.add_theme_font_size_override("font_size", FS_LABEL)
			lb.modulate = Color(0.5, 0.5, 0.5)
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lb)
			
			var steal_btn := Button.new()
			steal_btn.text = "抢占"
			steal_btn.add_theme_font_size_override("font_size", FS_SMALL)
			steal_btn.tooltip_text = "把该单位从「%s」移除，并分配给当前选中项" % UnitDataManager.get_display_name(entry.by)
			steal_btn.pressed.connect(func():
				_on_mapping_toggled(true, _unit_unlock_selected, entry.uid)
			)
			row.add_child(steal_btn)
			_unit_unlock_mapping_box.add_child(row)


func _on_mapping_toggled(pressed : bool, source_unit : String, target_unit : String):
	if not _unit_unlock_data.has("map_unlock_mapping"):
		_unit_unlock_data["map_unlock_mapping"] = {}
	var mapping: Dictionary = _unit_unlock_data["map_unlock_mapping"]
	
	if not mapping.has(source_unit):
		mapping[source_unit] = []
		
	var arr: Variant = mapping[source_unit]
	if not (arr is Array):
		arr = []
		mapping[source_unit] = arr

	if pressed:
		if target_unit not in arr:
			arr.append(target_unit)
			
		var src_faction : String = ""
		if _unit_db.has(source_unit):
			src_faction = _unit_db[source_unit].get("faction", "")
		
		if src_faction != "" and _unit_db.has(target_unit):
			var tgt_faction : String = _unit_db[target_unit].get("faction", "")
			if tgt_faction != src_faction:
				_unit_db[target_unit]["faction"] = src_faction
				_unit_db_dirty = true
				if _unit_unlock_status:
					_unit_unlock_status.text = "⚠ 自动同步：%s 阵营 → %s（未保存）" % [target_unit, src_faction]

		for other_src in mapping.keys():
			if other_src == source_unit: continue
			var other_arr: Variant = mapping[other_src]
			if other_arr is Array and target_unit in other_arr:
				other_arr.erase(target_unit)
	else:
		arr.erase(target_unit)

	mapping[source_unit] = arr
	_unit_unlock_data["map_unlock_mapping"] = mapping
	
	_refresh_unit_unlock_ui()
	
	if _unit_unlock_status and not _unit_unlock_status.text.begins_with("⚠ 自动同步"):
		_unit_unlock_status.text = "已修改（未保存）"


func _on_unit_unlock_add():
	var dialog := AcceptDialog.new()
	dialog.title = "添加单位到地图解锁池"
	dialog.ok_button_text = "关闭"
	
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	var all_unit_ids := UnitDataManager.get_all_unit_ids()
	var current: Array = _unit_unlock_data.get("map_unlock_units", [])
	
	var available := []
	for uid in all_unit_ids:
		if uid not in current:
			available.append(uid)

	if available.is_empty():
		var hint := Label.new()
		hint.text = "（所有单位都已加入地图解锁池）"
		hint.modulate = Color(0.6, 0.6, 0.6)
		list.add_child(hint)
	else:
		for uid in available:
			var display := UnitDataManager.get_display_name(uid)
			var btn := Button.new()
			btn.text = "%s (%s)" % [display, uid]
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", FS_BUTTON)
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(func():
				if not _unit_unlock_data.has("map_unlock_units"):
					_unit_unlock_data["map_unlock_units"] = []
				_unit_unlock_data["map_unlock_units"].append(uid)
				dialog.queue_free()
				_unit_unlock_selected = uid
				_refresh_unit_unlock_ui()
				if _unit_unlock_status:
					_unit_unlock_status.text = "已添加（未保存）"
			)
			list.add_child(btn)

	add_child(dialog)
	dialog.popup_centered(Vector2(320, 420))


func _on_unit_unlock_remove():
	if _unit_unlock_selected == "":
		return
	var current: Array = _unit_unlock_data.get("map_unlock_units", [])
	current.erase(_unit_unlock_selected)
	_unit_unlock_data["map_unlock_units"] = current
	
	var mapping: Dictionary = _unit_unlock_data.get("map_unlock_mapping", {})
	mapping.erase(_unit_unlock_selected)
	_unit_unlock_data["map_unlock_mapping"] = mapping
	
	_unit_unlock_selected = ""
	_refresh_unit_unlock_ui()
	if _unit_unlock_status:
		_unit_unlock_status.text = "已移除（未保存）"


func _save_unit_unlock_config():
	var f := FileAccess.open(UNIT_UNLOCK_PATH, FileAccess.WRITE)
	if f == null:
		if _unit_unlock_status:
			_unit_unlock_status.text = "❌ 保存失败"
		return
	f.store_string(JSON.stringify(_unit_unlock_data, "  "))
	f.close()
	
	if _unit_db_dirty:
		var f2 := FileAccess.open(UNIT_DATA_PATH, FileAccess.WRITE)
		if f2 != null:
			f2.store_string(JSON.stringify(_unit_db, "  "))
			f2.close()
			UnitDataManager.reload_all()
			_unit_db_dirty = false
			if _unit_unlock_status: 
				_unit_unlock_status.text = "✓ 已保存(含阵营同步)"
			Globals._load_unlock_config()
			return

	Globals._load_unlock_config()
	if _unit_unlock_status:
		_unit_unlock_status.text = "✓ 已保存"
	print("[GameDataEditor] unit_unlock.json 已保存")


# ============================================================
#  Tab 8：跨表校验
# ============================================================
func _build_validator_tab(parent : Control) -> Control:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 3)
	parent.add_child(panel)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	panel.add_child(bar)

	var run_btn := Button.new()
	run_btn.text = "运行校验"
	run_btn.pressed.connect(_run_validation)
	bar.add_child(run_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.pressed.connect(func():
		if _validator_output: _validator_output.clear()
		if _validator_status: _validator_status.text = ""
	)
	bar.add_child(clear_btn)

	_validator_status = Label.new()
	_validator_status.modulate = Color(0.85, 0.85, 0.85)
	bar.add_child(_validator_status)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var hint := Label.new()
	hint.text = "红色=错误 · 黄色=警告"
	hint.modulate = Color(0.6, 0.6, 0.6)
	bar.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_validator_output = RichTextLabel.new()
	_validator_output.bbcode_enabled = true
	_validator_output.fit_content = true
	_validator_output.scroll_following = true
	_validator_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_validator_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_validator_output)

	return panel


func _run_validation():
	if _validator_output == null: return
	_validator_output.clear()
	_validator_last_errors = 0
	_validator_last_warns = 0
	if _validator_status:
		_validator_status.text = "校验中..."

	var validator := DataValidator.new()
	var results : Array = validator.validate_all()
	var err_count : int = validator.get_error_count()
	var warn_count : int = validator.get_warn_count()
	_validator_last_errors = err_count
	_validator_last_warns = warn_count

	if results.is_empty():
		_validator_output.append_text("[color=#7FBF7F]✓ 全部通过，未发现问题[/color]\n")
		if _validator_status:
			_validator_status.text = "✓ 0 错误 / 0 警告"
			_validator_status.modulate = Color(0.85, 0.85, 0.85)
		_update_tab_validation_marker()
		return

	var by_file : Dictionary = {}
	for r in results:
		var f : String = r["file"]
		if not by_file.has(f):
			by_file[f] = []
		by_file[f].append(r)

	var files : Array = by_file.keys()
	files.sort()
	for fname in files:
		_validator_output.append_text("[b]%s[/b]\n" % fname)
		var entries : Array = by_file[fname]
		for r in entries:
			var path : String = r["path"]
			var msg : String = r["message"]
			if r["level"] == DataValidator.Level.ERROR:
				_validator_output.append_text(
					"  [color=#FF6B6B]✗[/color] [color=#888]%s[/color]  %s\n" % [path, msg])
			else:
				_validator_output.append_text(
					"  [color=#FFD966]⚠[/color] [color=#888]%s[/color]  %s\n" % [path, msg])
		_validator_output.append_text("\n")

	if _validator_status:
		var msg_text : String = "%d 错误 / %d 警告" % [err_count, warn_count]
		if err_count > 0:
			_validator_status.text = "✗ " + msg_text
			_validator_status.modulate = Color(1.0, 0.6, 0.6)
		else:
			_validator_status.text = "⚠ " + msg_text
			_validator_status.modulate = Color(1.0, 0.85, 0.5)

	_update_tab_validation_marker()


func _auto_validate():
	if _validator_output == null: return
	_run_validation()


func _update_tab_validation_marker():
	if _tab_btns.size() < 8: return
	var tab_idx : int = 7
	var base_name : String = "校验"
	if _validator_last_errors > 0:
		_tab_btns[tab_idx].text = "%s (%d)" % [base_name, _validator_last_errors]
		_tab_btns[tab_idx].modulate = Color(1.0, 0.6, 0.6)
	elif _validator_last_warns > 0:
		_tab_btns[tab_idx].text = "%s (%d)" % [base_name, _validator_last_warns]
		_tab_btns[tab_idx].modulate = Color(1.0, 0.85, 0.5)
	else:
		_tab_btns[tab_idx].text = base_name
		_tab_btns[tab_idx].modulate = Color.WHITE


# ============================================================
#  战斗模拟逻辑
# ============================================================
func _refresh_sim_unit_lists():
	if _sim_player_opt == null or _sim_enemy_opt == null: return
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


# ============================================================
#  通用小工具
# ============================================================
func _section(text : String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FS_PANEL)
	l.modulate = Color(0.7, 0.8, 1.0)
	return l


func _lbl(text : String, min_w : float = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if min_w > 0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l


func _center_label(text : String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _add_edit_row(parent : Node, label : String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	row.add_child(_lbl(label, 40))
	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(le)
	return le


func _add_option_row(parent : Node, label : String, ids : Array, none_text : String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	row.add_child(_lbl(label, 40))

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_item(none_text, 0)
	opt.set_item_metadata(0, "")
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


func _style_spin(sp : SpinBox):
	sp.add_theme_font_size_override("font_size", FS_BUTTON)
	sp.ready.connect(func():
		if not is_instance_valid(sp): return
		var le := sp.get_line_edit()
		if le:
			le.add_theme_font_size_override("font_size", FS_BUTTON)
			le.select_all_on_focus = true
		var btns : Array[Node] = sp.find_children("*", "Button", true, false)
		for b in btns:
			_compact_spin_arrow_button(b as Button)
	, CONNECT_ONE_SHOT)


func _compact_spin_arrow_button(btn : Button):
	btn.custom_minimum_size = Vector2(5, 0)
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.icon_max_width = 4
	btn.icon_max_height = 3
	btn.focus_mode = Control.FOCUS_NONE
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	btn.flat = true
	btn.expand_icon = false

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
