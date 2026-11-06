extends Control

# ============================================================
#  GameDataEditor — 单位 / 战斗模拟 / 数值 / 套装 / 词条池 / 光环 / 单位解锁 / 校验
#  v4.8：
#    - 单位列表带 idle 缩略图
#    - 头像下拉带图标 + 预览
#    - SpriteFrames 路径行（选择/新建/复制/打开）+ idle 预览
#    - 新建单位支持「空白单位」，可选自动创建空白 SpriteFrames
#    - 重命名 ID：扫描 unit_data / unit_unlock / 地图 .tscn / events.json
#    - 删除单位：列出所有引用
#    - 新增字段：物理减伤/魔法减伤/无视地形/防具槽/特技槽/竞技场经验
#  v4.9（步 5 编辑器同步）：
#    - CAP_MAX_LEVEL 3 → 5
#    - 新增「等级机制（布尔开关）」网格：level_mechanics
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
const EVENT_PATH_FOR_EDITOR : String = "res://content/data/events.json"
const AVATAR_DIR : String = "res://content/images/characters/avatar/"
const MAP_ROOT_DIR : String = "res://content/scenes/maps/"
const SPRITE_FRAMES_DIR : String = "res://content/images/characters/"

const JSON_EDITOR_SCRIPT : String = "res://function/tool/editor/JSONEditorPanel.gd"

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
const CORE_TRAITS : Array = ["", "charge", "dragon_might", "bulwark"]
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
const CAP_MAX_LEVEL : int = 5

const LEVEL_MECHANICS_LIST : Array = [
	{"id": "range_plus_1",                 "label": "射程 +1"},
	{"id": "move_plus_1",                  "label": "移动 +1"},
	{"id": "crit_damage_plus_20",          "label": "暴伤 +20%"},
	{"id": "physical_penetration_plus_10", "label": "物穿 +10%"},
	{"id": "magic_penetration_plus_10",    "label": "法穿 +10%"},
]

const BOSS_TRIGGERS : Array = ["initial", "hp_below", "on_death"]
const BOSS_HP_MODES : Array = ["full", "keep_ratio", "keep_absolute", "custom_ratio"]
const BOSS_MECHANICS : Array = ["", "ash_shield", "soul_drain", "three_forms"]

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
var _events_db : Dictionary = {}
var _current_unit_key : String = ""

var _tab_btns : Array = []
var _tab_panels : Array = []

var _edit_unit_list : VBoxContainer = null
var _edit_status : Label = null
var _edit_name_edit : LineEdit = null
var _edit_faction_edit : LineEdit = null
var _edit_desc_edit : TextEdit = null
var _edit_flavor_edit : TextEdit = null
var _edit_avatar_opt : OptionButton = null
var _edit_hidden_cb : CheckBox = null
var _edit_is_boss_cb : CheckBox = null
var _edit_boss_mechanic_edit : LineEdit = null
var _edit_boss_mechanic_params_edit : LineEdit = null
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
var _edit_mechanics_cbs : Dictionary = {}   # ★ 步 5：mechanic_id -> { level_idx: CheckBox }
var _edit_branches_box : VBoxContainer = null
var _edit_branch_cards : Array = []
var _edit_boss_phases_box : VBoxContainer = null
var _edit_boss_phase_cards : Array = []

# ---- 新增：头像 / SpriteFrames / 战斗属性 ----
var _edit_sprite_frames_path : LineEdit = null
var _edit_sprite_frames_preview : TextureRect = null
var _edit_phys_reduction_spin : SpinBox = null
var _edit_mag_reduction_spin : SpinBox = null
var _edit_ignore_terrain_cb : CheckBox = null
var _edit_max_armor_spin : SpinBox = null
var _edit_max_talent_spin : SpinBox = null
var _edit_arena_exp_spin : SpinBox = null
var _frames_texture_cache : Dictionary = {}

# ---- 战斗模拟 ----
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

var _validator_output : RichTextLabel = null
var _validator_status : Label = null
var _validator_last_errors : int = 0
var _validator_last_warns : int = 0

var _unit_unlock_data : Dictionary = {}
var _unit_unlock_selected : String = ""
var _unit_unlock_list_box : VBoxContainer = null
var _unit_unlock_mapping_box : VBoxContainer = null
var _unit_unlock_status : Label = null
var _unit_unlock_right_title : Label = null
var _unit_db_dirty : bool = false
var _edit_boss_dialogue_opts : Dictionary = {}
var _edit_right_content : VBoxContainer = null
var _validator_raw_log : String = ""


func _ready():
	_apply_compact_theme()
	_load_all_data()
	_build_ui()
	_refresh_unit_list()
	_refresh_sim_unit_lists()
	if _unit_keys.size() > 0:
		_select_edit_unit(_unit_keys[0])
	call_deferred("_auto_validate")


func _apply_compact_theme():
	var t := Theme.new()

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

	t.set_font_size("font_size", "Label", FS_LABEL)
	var label_empty := StyleBoxEmpty.new()
	label_empty.content_margin_left = 0
	label_empty.content_margin_right = 0
	label_empty.content_margin_top = 0
	label_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "Label", label_empty)

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

	t.set_font_size("font_size", "OptionButton", FS_BUTTON)
	t.set_font_size("font_size", "PopupMenu", FS_SMALL)
	t.set_font_size("font_separator_size", "PopupMenu", FS_SMALL)
	t.set_constant("item_start_padding", "PopupMenu", 3)
	t.set_constant("item_end_padding", "PopupMenu", 3)
	t.set_constant("v_separation", "PopupMenu", 0)
	t.set_constant("h_separation", "PopupMenu", 0)
	t.set_constant("icon_max_width", "PopupMenu", 16)

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

	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)
	t.set_font_size("font_size", "TooltipPanel", FS_SMALL)
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = COL_TIP_BG
	tip_sb.content_margin_left = 3
	tip_sb.content_margin_right = 3
	tip_sb.content_margin_top = 1
	tip_sb.content_margin_bottom = 1
	t.set_stylebox("panel", "TooltipPanel", tip_sb)

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

	t.set_font_size("font_size", "SpinBox", FS_BUTTON)
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
	_events_db = _load_json(EVENT_PATH_FOR_EDITOR)

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
#  单位编辑
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

	var refresh_btn := Button.new()
	refresh_btn.text = "🔄 刷新列表"
	refresh_btn.add_theme_font_size_override("font_size", 7)
	refresh_btn.modulate = Color(0.8, 0.9, 1.0)
	refresh_btn.pressed.connect(func():
		_unit_db = _load_json(UNIT_DATA_PATH)
		_unit_keys = _unit_db.keys()
		_unit_keys.sort()
		_frames_texture_cache.clear()
		_refresh_unit_list()
		_refresh_sim_unit_lists()
		_set_edit_status("已从硬盘重载列表")
	)
	left.add_child(refresh_btn)

	var add_unit_btn := Button.new()
	add_unit_btn.text = "+ 新建单位"
	add_unit_btn.add_theme_font_size_override("font_size", 7)
	add_unit_btn.modulate = Color(0.6, 1.0, 0.6)
	add_unit_btn.pressed.connect(_on_add_unit_pressed)
	left.add_child(add_unit_btn)

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
	_edit_right_content = content

	content.add_child(_section("— 基础信息 —"))

	_edit_name_edit = _add_edit_row(content, "显示名")
	_edit_name_edit.text_submitted.connect(func(_t):
		_save_unit_db()
		_edit_name_edit.release_focus()
	)

	_edit_faction_edit = _add_edit_row(content, "阵营")

	_edit_avatar_opt = _add_avatar_option_row(content, "头像")

	content.add_child(_section("— Boss / 分类元字段 —"))

	var flags_row := HBoxContainer.new()
	flags_row.add_theme_constant_override("separation", 8)
	content.add_child(flags_row)
	_edit_hidden_cb = CheckBox.new()
	_edit_hidden_cb.text = "hidden_from_roster"
	flags_row.add_child(_edit_hidden_cb)
	_edit_is_boss_cb = CheckBox.new()
	_edit_is_boss_cb.text = "is_boss"
	flags_row.add_child(_edit_is_boss_cb)

	_edit_boss_mechanic_edit = _add_edit_row(content, "boss_mechanic_id")
	_edit_boss_mechanic_edit.placeholder_text = "ash_shield / soul_drain / three_forms（空=无）"
	_edit_boss_mechanic_params_edit = _add_edit_row(content, "boss_mechanic_params")
	_edit_boss_mechanic_params_edit.placeholder_text = 'JSON，如 {"max_stacks":3,"damage_reduction":0.5}'

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

	content.add_child(_section("— 战斗属性 —"))
	var combat_grid := GridContainer.new()
	combat_grid.columns = 2
	combat_grid.add_theme_constant_override("h_separation", 6)
	combat_grid.add_theme_constant_override("v_separation", 1)
	content.add_child(combat_grid)

	combat_grid.add_child(_lbl("物理减伤", 50))
	_edit_phys_reduction_spin = SpinBox.new()
	_edit_phys_reduction_spin.min_value = 0.0
	_edit_phys_reduction_spin.max_value = 0.75
	_edit_phys_reduction_spin.step = 0.01
	_edit_phys_reduction_spin.custom_minimum_size = Vector2(60, 16)
	combat_grid.add_child(_edit_phys_reduction_spin)
	_style_spin(_edit_phys_reduction_spin)

	combat_grid.add_child(_lbl("魔法减伤", 50))
	_edit_mag_reduction_spin = SpinBox.new()
	_edit_mag_reduction_spin.min_value = 0.0
	_edit_mag_reduction_spin.max_value = 0.75
	_edit_mag_reduction_spin.step = 0.01
	_edit_mag_reduction_spin.custom_minimum_size = Vector2(60, 16)
	combat_grid.add_child(_edit_mag_reduction_spin)
	_style_spin(_edit_mag_reduction_spin)

	combat_grid.add_child(_lbl("无视地形", 50))
	_edit_ignore_terrain_cb = CheckBox.new()
	_edit_ignore_terrain_cb.text = "ignore_terrain_cost"
	combat_grid.add_child(_edit_ignore_terrain_cb)

	combat_grid.add_child(_lbl("防具槽", 50))
	_edit_max_armor_spin = SpinBox.new()
	_edit_max_armor_spin.min_value = 0
	_edit_max_armor_spin.max_value = 10
	_edit_max_armor_spin.step = 1
	_edit_max_armor_spin.custom_minimum_size = Vector2(60, 16)
	combat_grid.add_child(_edit_max_armor_spin)
	_style_spin(_edit_max_armor_spin)

	combat_grid.add_child(_lbl("特技槽", 50))
	_edit_max_talent_spin = SpinBox.new()
	_edit_max_talent_spin.min_value = 0
	_edit_max_talent_spin.max_value = 5
	_edit_max_talent_spin.step = 1
	_edit_max_talent_spin.custom_minimum_size = Vector2(60, 16)
	combat_grid.add_child(_edit_max_talent_spin)
	_style_spin(_edit_max_talent_spin)

	combat_grid.add_child(_lbl("竞技场经验", 50))
	_edit_arena_exp_spin = SpinBox.new()
	_edit_arena_exp_spin.min_value = 0
	_edit_arena_exp_spin.max_value = 999
	_edit_arena_exp_spin.step = 1
	_edit_arena_exp_spin.custom_minimum_size = Vector2(60, 16)
	combat_grid.add_child(_edit_arena_exp_spin)
	_style_spin(_edit_arena_exp_spin)

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

	content.add_child(_section("— 精灵帧 —"))
	var sf_row : Dictionary = _add_sprite_frames_path_row(content, "SpriteFrames")
	_edit_sprite_frames_path = sf_row["le"]
	_edit_sprite_frames_preview = sf_row["preview"]

	content.add_child(HSeparator.new())
	content.add_child(_section("— 属性上限（净增）—"))
	_rebuild_attr_cap_grid(content)

	content.add_child(HSeparator.new())
	content.add_child(_section("— 等级机制（布尔开关）—"))   # ★ 步 5
	_rebuild_level_mechanics_grid(content)

	content.add_child(HSeparator.new())
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

	content.add_child(HSeparator.new())
	var boss_header := HBoxContainer.new()
	boss_header.add_theme_constant_override("separation", 4)
	content.add_child(boss_header)
	boss_header.add_child(_section("— Boss 阶段（phases 新格式）—"))

	var add_boss_btn := Button.new()
	add_boss_btn.text = "+ 添加阶段"
	add_boss_btn.pressed.connect(_add_boss_phase_card)
	boss_header.add_child(add_boss_btn)

	var auto_boss_btn := Button.new()
	auto_boss_btn.text = "一键生成标准三阶段"
	auto_boss_btn.modulate = Color(0.6, 1.0, 0.6)
	auto_boss_btn.pressed.connect(func():
		for c in _edit_boss_phases_box.get_children():
			_edit_boss_phases_box.remove_child(c)
			c.queue_free()
		_edit_boss_phase_cards.clear()
		_add_boss_phase_card_with_data({"trigger": "initial", "hp_mode": "full", "reset_turn_state": true}, false)
		_add_boss_phase_card_with_data({"trigger": "hp_below", "threshold": 0.5, "hp_mode": "full", "preserve_buffs": true}, false)
		_add_boss_phase_card_with_data({"trigger": "hp_below", "threshold": 0.25, "hp_mode": "full", "preserve_buffs": true}, false)
	)
	boss_header.add_child(auto_boss_btn)

	var clear_boss_btn := Button.new()
	clear_boss_btn.text = "清空全部"
	clear_boss_btn.modulate = Color(1.0, 0.6, 0.6)
	clear_boss_btn.pressed.connect(_clear_all_boss_phases)
	boss_header.add_child(clear_boss_btn)

	_edit_boss_phases_box = VBoxContainer.new()
	_edit_boss_phases_box.add_theme_constant_override("separation", 4)
	content.add_child(_edit_boss_phases_box)

	content.add_child(HSeparator.new())
	var dlg_header := HBoxContainer.new()
	dlg_header.add_theme_constant_override("separation", 4)
	content.add_child(dlg_header)
	dlg_header.add_child(_section("— Boss 对话钩子（unit_data.json）—"))

	var dlg_box := VBoxContainer.new()
	dlg_box.add_theme_constant_override("separation", 2)
	content.add_child(dlg_box)

	var hook_types : Array = [
		{"key": "battle_start", "label": "战前对话"},
		{"key": "phase_2", "label": "转阶段 2"},
		{"key": "phase_3", "label": "转阶段 3"},
		{"key": "on_death", "label": "死亡对话"}
	]

	var all_dlg_ids := _get_all_dialogue_ids()

	for h in hook_types:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		dlg_box.add_child(row)

		var lb := Label.new()
		lb.text = h["label"]
		lb.custom_minimum_size = Vector2(80, 0)
		row.add_child(lb)

		var opt := OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt.add_item("（无）", 0)
		opt.set_item_metadata(0, "")
		for i in range(all_dlg_ids.size()):
			opt.add_item(all_dlg_ids[i], i + 1)
			opt.set_item_metadata(i + 1, all_dlg_ids[i])
		row.add_child(opt)
		_edit_boss_dialogue_opts[h["key"]] = opt

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 4)
	right.add_child(btn_row)

	var rename_btn := Button.new()
	rename_btn.text = "重命名 ID"
	rename_btn.modulate = Color(0.9, 0.85, 0.4)
	rename_btn.pressed.connect(_on_rename_unit_pressed)
	btn_row.add_child(rename_btn)

	var delete_btn := Button.new()
	delete_btn.text = "删除单位"
	delete_btn.modulate = Color(1.0, 0.5, 0.5)
	delete_btn.pressed.connect(_on_delete_unit_pressed)
	btn_row.add_child(delete_btn)

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


func _rebuild_attr_cap_grid(parent : Node):
	_edit_cap_spins.clear()
	var grid := GridContainer.new()
	grid.columns = 1 + CAP_MAX_LEVEL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)

	grid.add_child(_lbl("", 30))
	for lv in range(CAP_MAX_LEVEL):
		grid.add_child(_lbl("→Lv%d" % (lv + 2), 40))

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


func _rebuild_level_mechanics_grid(parent : Node):
	_edit_mechanics_cbs.clear()
	var grid := GridContainer.new()
	grid.columns = 1 + CAP_MAX_LEVEL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)

	grid.add_child(_lbl("机制", 80))
	for lv in range(CAP_MAX_LEVEL):
		grid.add_child(_lbl("→Lv%d" % (lv + 2), 40))

	for m in LEVEL_MECHANICS_LIST:
		var mid : String = m["id"]
		grid.add_child(_lbl(m["label"], 80))
		var lv_map : Dictionary = {}
		for lv in range(CAP_MAX_LEVEL):
			var cb := CheckBox.new()
			cb.custom_minimum_size = Vector2(20, 20)
			cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			grid.add_child(cb)
			lv_map[lv] = cb
		_edit_mechanics_cbs[mid] = lv_map


func _read_level_mechanics() -> Array:
	var result : Array = []
	for lv in range(CAP_MAX_LEVEL):
		var d : Dictionary = {}
		for m in LEVEL_MECHANICS_LIST:
			var mid : String = m["id"]
			var cb : CheckBox = _edit_mechanics_cbs.get(mid, {}).get(lv, null)
			if cb and cb.button_pressed:
				d[mid] = true
		result.append(d)
	return result


func _fill_level_mechanics(data : Array):
	for m in LEVEL_MECHANICS_LIST:
		var mid : String = m["id"]
		var lv_map : Dictionary = _edit_mechanics_cbs.get(mid, {})
		for lv in range(CAP_MAX_LEVEL):
			var cb : CheckBox = lv_map.get(lv, null)
			if cb == null: continue
			var v : bool = false
			if lv < data.size() and data[lv] is Dictionary:
				v = bool(data[lv].get(mid, false))
			cb.button_pressed = v


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

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 3)
	vbox.add_child(name_row)
	name_row.add_child(_lbl("职业名", 40))
	var name_edit := LineEdit.new()
	name_edit.text = d.get("name", "")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	card_refs["name"] = name_edit

	var desc_row := HBoxContainer.new()
	desc_row.add_theme_constant_override("separation", 3)
	vbox.add_child(desc_row)
	desc_row.add_child(_lbl("简介", 40))
	var desc_edit := LineEdit.new()
	desc_edit.text = d.get("description", "")
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_row.add_child(desc_edit)
	card_refs["description"] = desc_edit

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

	# SpriteFrames 路径行（含预览）
	var sprite_row_data : Dictionary = _add_sprite_frames_path_row(vbox, "精灵图")
	var sprite_edit : LineEdit = sprite_row_data["le"]
	sprite_edit.text = d.get("sprite_frames_path", "")
	sprite_edit.text_changed.emit(sprite_edit.text)
	card_refs["sprite_frames_path"] = sprite_edit

	var flavor_row := HBoxContainer.new()
	flavor_row.add_theme_constant_override("separation", 3)
	vbox.add_child(flavor_row)
	flavor_row.add_child(_lbl("风味文", 40))
	var flavor_edit := LineEdit.new()
	flavor_edit.text = d.get("flavor", "")
	flavor_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flavor_row.add_child(flavor_edit)
	card_refs["flavor"] = flavor_edit

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
#  Boss 阶段编辑
# ============================================================
func _rebuild_boss_phases(data : Array):
	for c in _edit_boss_phases_box.get_children():
		_edit_boss_phases_box.remove_child(c)
		c.queue_free()
	_edit_boss_phase_cards.clear()
	for phase in data:
		if phase is Dictionary:
			_add_boss_phase_card_with_data(phase, false)


func _add_boss_phase_card():
	_add_boss_phase_card_with_data({
		"form_unit_id": "",
		"trigger": "on_death",
		"threshold": 0.5,
		"hp_mode": "full",
		"min_hp": 1,
		"reset_turn_state": false,
		"preserve_buffs": true,
		"mechanic_id": "",
		"mechanic_params": {},
		"override": {}
	}, true)


func _clear_all_boss_phases():
	if _edit_boss_phase_cards.is_empty():
		return
	Globals.show_confirm(
		self,
		"确定清空该单位的所有 Boss 阶段吗？\n（保存后写入 JSON 生效）",
		"清空", "取消",
		func():
			for c in _edit_boss_phases_box.get_children():
				_edit_boss_phases_box.remove_child(c)
				c.queue_free()
			_edit_boss_phase_cards.clear(),
		func(): pass
	)


func _make_boss_unit_option(current_id : String) -> OptionButton:
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_item("（空：用 override 覆盖当前单位）", 0)
	opt.set_item_metadata(0, "")
	var selected : bool = current_id == ""
	for i in range(_unit_keys.size()):
		var uid : String = _unit_keys[i]
		var ud : Dictionary = _unit_db.get(uid, {})
		var dn : String = str(ud.get("display_name", uid))
		var suffix : String = ""
		if bool(ud.get("hidden_from_roster", false)):
			suffix = " [隐藏]"
		opt.add_item("%s (%s)%s" % [dn, uid, suffix], i + 1)
		opt.set_item_metadata(i + 1, uid)
		if uid == current_id:
			opt.selected = i + 1
			selected = true
	if not selected and current_id != "":
		opt.add_item("（当前）" + current_id, _unit_keys.size() + 1)
		opt.set_item_metadata(_unit_keys.size() + 1, current_id)
		opt.selected = _unit_keys.size() + 1
	return opt


func _add_boss_phase_card_with_data(d : Dictionary, _is_new : bool = false):
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 1)
	sb.border_color = Color(0.35, 0.30, 0.25, 1)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", sb)
	_edit_boss_phases_box.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var card_refs : Dictionary = {}

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	vbox.add_child(head)

	var is_first : bool = _edit_boss_phase_cards.is_empty()

	var title := Label.new()
	title.text = "阶段 #%d %s" % [_edit_boss_phase_cards.size() + 1, "（初始形态）" if is_first else ""]
	title.add_theme_font_size_override("font_size", FS_PANEL)
	title.modulate = Color(0.9, 0.8, 0.6)
	head.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	var del_btn := Button.new()
	del_btn.text = "删除阶段"
	del_btn.modulate = Color(1.0, 0.5, 0.5)
	del_btn.disabled = is_first
	del_btn.pressed.connect(func():
		_edit_boss_phase_cards.erase(card_refs)
		card.queue_free()
	)
	head.add_child(del_btn)

	var form_row := HBoxContainer.new()
	form_row.add_theme_constant_override("separation", 4)
	vbox.add_child(form_row)
	form_row.add_child(_lbl("变身为", 80))
	var form_opt := _make_boss_unit_option(str(d.get("form_unit_id", "")))
	form_opt.disabled = is_first
	form_row.add_child(form_opt)
	card_refs["form_opt"] = form_opt

	var trig_row := HBoxContainer.new()
	trig_row.add_theme_constant_override("separation", 4)
	vbox.add_child(trig_row)
	trig_row.add_child(_lbl("触发条件", 80))

	var trig_text := Label.new()
	trig_text.add_theme_font_size_override("font_size", FS_BUTTON)
	if is_first:
		trig_text.text = "初始状态（出生即生效）"
		trig_text.modulate = Color(0.6, 0.8, 1.0)
		card_refs["trigger_opt"] = null
	else:
		var trig_opt := OptionButton.new()
		trig_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trig_opt.add_item("HP 降至阈值", 0)
		trig_opt.set_item_metadata(0, "hp_below")
		trig_opt.add_item("死亡时", 1)
		trig_opt.set_item_metadata(1, "on_death")
		_select_option_by_meta(trig_opt, str(d.get("trigger", "hp_below")))
		trig_row.add_child(trig_opt)
		card_refs["trigger_opt"] = trig_opt
		trig_text = null

	if trig_text != null:
		trig_row.add_child(trig_text)

	var threshold_row := HBoxContainer.new()
	threshold_row.add_theme_constant_override("separation", 4)
	vbox.add_child(threshold_row)
	threshold_row.add_child(_lbl("血量阈值", 80))

	var threshold_spin := SpinBox.new()
	threshold_spin.min_value = 0.05
	threshold_spin.max_value = 0.95
	threshold_spin.step = 0.05
	threshold_spin.value = float(d.get("threshold", 0.5))
	threshold_spin.custom_minimum_size = Vector2(70, 16)
	threshold_row.add_child(threshold_spin)
	_style_spin(threshold_spin)
	card_refs["threshold_spin"] = threshold_spin
	card_refs["threshold_row"] = threshold_row

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 4)
	vbox.add_child(hp_row)
	hp_row.add_child(_lbl("切换后血量", 80))
	var hp_opt := OptionButton.new()
	hp_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_opt.add_item("回满血", 0)
	hp_opt.set_item_metadata(0, "full")
	hp_opt.add_item("保持当前比例", 1)
	hp_opt.set_item_metadata(1, "keep_ratio")
	hp_opt.add_item("保持当前绝对值", 2)
	hp_opt.set_item_metadata(2, "keep_absolute")
	hp_opt.add_item("自定义比例", 3)
	hp_opt.set_item_metadata(3, "custom_ratio")
	_select_option_by_meta(hp_opt, str(d.get("hp_mode", "full")))
	hp_row.add_child(hp_opt)
	card_refs["hp_mode_opt"] = hp_opt

	var min_hp_row := HBoxContainer.new()
	min_hp_row.add_theme_constant_override("separation", 4)
	vbox.add_child(min_hp_row)
	min_hp_row.add_child(_lbl("保底 HP", 80))
	var min_hp_spin := SpinBox.new()
	min_hp_spin.min_value = 0
	min_hp_spin.max_value = 99999
	min_hp_spin.step = 1
	min_hp_spin.value = int(d.get("min_hp", 1))
	min_hp_spin.custom_minimum_size = Vector2(70, 16)
	min_hp_row.add_child(min_hp_spin)
	_style_spin(min_hp_spin)
	card_refs["min_hp_spin"] = min_hp_spin

	var advanced_cb := CheckBox.new()
	advanced_cb.text = "展开高级设置 (机制/保留状态)"
	advanced_cb.add_theme_font_size_override("font_size", FS_SMALL)
	vbox.add_child(advanced_cb)

	var adv_box := VBoxContainer.new()
	adv_box.visible = false
	adv_box.add_theme_constant_override("separation", 2)
	vbox.add_child(adv_box)

	advanced_cb.toggled.connect(func(pressed): adv_box.visible = pressed)

	var flag_row := HBoxContainer.new()
	flag_row.add_theme_constant_override("separation", 8)
	adv_box.add_child(flag_row)
	var reset_cb := CheckBox.new()
	reset_cb.text = "重置行动"
	reset_cb.button_pressed = bool(d.get("reset_turn_state", false))
	flag_row.add_child(reset_cb)
	card_refs["reset_cb"] = reset_cb

	var preserve_cb := CheckBox.new()
	preserve_cb.text = "保留Buff"
	preserve_cb.button_pressed = bool(d.get("preserve_buffs", true))
	flag_row.add_child(preserve_cb)
	card_refs["preserve_cb"] = preserve_cb

	var mech_row := HBoxContainer.new()
	mech_row.add_theme_constant_override("separation", 4)
	adv_box.add_child(mech_row)
	mech_row.add_child(_lbl("机制ID", 80))
	var mech_opt := OptionButton.new()
	mech_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(BOSS_MECHANICS.size()):
		mech_opt.add_item(BOSS_MECHANICS[i] if BOSS_MECHANICS[i] != "" else "（无）", i)
		mech_opt.set_item_metadata(i, BOSS_MECHANICS[i])
	_select_option_by_meta(mech_opt, str(d.get("mechanic_id", "")))
	mech_row.add_child(mech_opt)
	card_refs["mechanic_opt"] = mech_opt

	var mp_row := HBoxContainer.new()
	mp_row.add_theme_constant_override("separation", 4)
	adv_box.add_child(mp_row)
	mp_row.add_child(_lbl("机制参数", 80))
	var mp_edit := LineEdit.new()
	mp_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_edit.placeholder_text = 'JSON，如 {"max_stacks":3}'
	var mp : Dictionary = d.get("mechanic_params", {})
	if mp is Dictionary and not (mp as Dictionary).is_empty():
		mp_edit.text = JSON.stringify(mp)
	mp_row.add_child(mp_edit)
	card_refs["mechanic_params_edit"] = mp_edit

	var ov_row := HBoxContainer.new()
	ov_row.add_theme_constant_override("separation", 4)
	adv_box.add_child(ov_row)
	ov_row.add_child(_lbl("字段覆盖", 80))
	var ov_edit := LineEdit.new()
	ov_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ov_edit.placeholder_text = 'JSON，如 {"max_hp":200}'
	var ov : Dictionary = d.get("override", {})
	if ov is Dictionary and not (ov as Dictionary).is_empty():
		ov_edit.text = JSON.stringify(ov)
	ov_row.add_child(ov_edit)
	card_refs["override_edit"] = ov_edit

	if card_refs.get("trigger_opt") != null:
		card_refs["trigger_opt"].item_selected.connect(func(idx):
			var meta = card_refs["trigger_opt"].get_item_metadata(idx)
			var is_hp_below = (meta == "hp_below")
			threshold_row.visible = is_hp_below
		)
		var current_trig = card_refs["trigger_opt"].get_item_metadata(card_refs["trigger_opt"].selected)
		threshold_row.visible = (current_trig == "hp_below")
	else:
		threshold_row.visible = false

	_edit_boss_phase_cards.append(card_refs)


func _read_boss_phases() -> Array:
	var result : Array = []
	for card in _edit_boss_phase_cards:
		if not is_instance_valid(card.get("form_opt", null)):
			continue
		var phase : Dictionary = {
			"form_unit_id": str(_get_meta(card["form_opt"])),
			"trigger": str(_get_meta(card["trigger_opt"])) if card.get("trigger_opt") != null else "initial",
			"threshold": float(card["threshold_spin"].value) if card.get("threshold_spin") != null else 0.5,
			"hp_mode": str(_get_meta(card["hp_mode_opt"])),
			"min_hp": int(card["min_hp_spin"].value) if card.has("min_hp_spin") else 1,
			"reset_turn_state": card["reset_cb"].button_pressed,
			"preserve_buffs": card["preserve_cb"].button_pressed,
			"mechanic_id": str(_get_meta(card["mechanic_opt"])),
			"mechanic_params": _parse_json_dict(card["mechanic_params_edit"].text) if card.has("mechanic_params_edit") else {},
			"override": _parse_json_dict(card["override_edit"].text) if card.has("override_edit") else {}
		}
		if result.is_empty():
			phase["trigger"] = "initial"
		result.append(phase)
	return result


func _parse_json_dict(text : String) -> Dictionary:
	var s : String = text.strip_edges()
	if s == "":
		return {}
	var parsed = JSON.parse_string(s)
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	_set_edit_status("JSON 解析失败，已按空字典处理")
	return {}


func _set_edit_status(text : String):
	if _edit_status:
		_edit_status.text = text


# ============================================================
#  单位列表 / 加载 / 保存
# ============================================================
func _refresh_unit_list():
	for c in _edit_unit_list.get_children():
		_edit_unit_list.remove_child(c)
		c.queue_free()
	for key in _unit_keys:
		var d : Dictionary = _unit_db[key]
		var btn := Button.new()
		btn.text = str(d.get("display_name", key))
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.set_meta("unit_key", key)

		var frames_path : String = str(d.get("sprite_frames_path", ""))
		var idle_tex := _get_idle_first_frame(frames_path)
		if idle_tex:
			btn.icon = idle_tex
			btn.add_theme_constant_override("icon_max_width", 16)

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

	_edit_hidden_cb.button_pressed = bool(d.get("hidden_from_roster", false))
	_edit_is_boss_cb.button_pressed = bool(d.get("is_boss", false))
	_edit_boss_mechanic_edit.text = str(d.get("boss_mechanic_id", ""))
	var bmp : Dictionary = d.get("boss_mechanic_params", {})
	if bmp is Dictionary and not (bmp as Dictionary).is_empty():
		_edit_boss_mechanic_params_edit.text = JSON.stringify(bmp)
	else:
		_edit_boss_mechanic_params_edit.text = ""

	if _edit_avatar_opt:
		var cur_avatar : String = str(d.get("avatar", ""))
		_select_option_by_meta(_edit_avatar_opt, cur_avatar)

	for a in EDITABLE_ATTRS:
		_edit_attr_spins[a["key"]].value = d.get(a["key"], 0)

	if _edit_phys_reduction_spin:
		_edit_phys_reduction_spin.value = float(d.get("physical_reduction", 0.0))
	if _edit_mag_reduction_spin:
		_edit_mag_reduction_spin.value = float(d.get("magic_reduction", 0.0))
	if _edit_ignore_terrain_cb:
		_edit_ignore_terrain_cb.button_pressed = bool(d.get("ignore_terrain_cost", false))
	if _edit_max_armor_spin:
		_edit_max_armor_spin.value = int(d.get("max_armor_slots", 2))
	if _edit_max_talent_spin:
		_edit_max_talent_spin.value = int(d.get("max_talent_slots", 1))
	if _edit_arena_exp_spin:
		_edit_arena_exp_spin.value = int(d.get("arena_exp", 30))

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

	if _edit_sprite_frames_path:
		var sf_path : String = str(d.get("sprite_frames_path", ""))
		_edit_sprite_frames_path.text = sf_path
		if _edit_sprite_frames_preview:
			_update_sprite_frames_preview(_edit_sprite_frames_preview, sf_path)

	_fill_attr_cap_levels(d.get("attr_cap_levels", []))
	_fill_level_mechanics(d.get("level_mechanics", []))   # ★ 步 5
	_rebuild_branches(d.get("advanced_branches", []))
	_rebuild_boss_phases(d.get("phases", []))
	var hooks : Dictionary = d.get("boss_dialogue_hooks", {})
	for k in _edit_boss_dialogue_opts:
		var opt : OptionButton = _edit_boss_dialogue_opts[k]
		var target_id = str(hooks.get(k, ""))
		_select_option_by_meta(opt, target_id)


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
	_frames_texture_cache.clear()
	_refresh_unit_list()
	_refresh_sim_unit_lists()
	UnitDataManager.reload_all()
	if _current_unit_key != "" and _unit_db.has(_current_unit_key):
		_select_edit_unit(_current_unit_key)
	_edit_status.text = "已重置"


func _save_unit_db():
	if _current_unit_key == "": return
	var d : Dictionary = _unit_db[_current_unit_key]

	d["unit_name"] = _current_unit_key
	d["display_name"] = _edit_name_edit.text
	d["faction"] = _edit_faction_edit.text
	d["description"] = _edit_desc_edit.text
	d["flavor"] = _edit_flavor_edit.text

	d["hidden_from_roster"] = _edit_hidden_cb.button_pressed
	d["is_boss"] = _edit_is_boss_cb.button_pressed

	var mid : String = _edit_boss_mechanic_edit.text.strip_edges()
	if mid == "":
		d.erase("boss_mechanic_id")
	else:
		d["boss_mechanic_id"] = mid

	var mp : Dictionary = _parse_json_dict(_edit_boss_mechanic_params_edit.text)
	if mp.is_empty():
		d.erase("boss_mechanic_params")
	else:
		d["boss_mechanic_params"] = mp

	if _edit_avatar_opt:
		var a_id = _get_meta(_edit_avatar_opt)
		if a_id != "":
			d["avatar"] = a_id
		else:
			d.erase("avatar")

	for a in EDITABLE_ATTRS:
		d[a["key"]] = int(_edit_attr_spins[a["key"]].value)

	if _edit_phys_reduction_spin:
		d["physical_reduction"] = float(_edit_phys_reduction_spin.value)
	if _edit_mag_reduction_spin:
		d["magic_reduction"] = float(_edit_mag_reduction_spin.value)
	if _edit_ignore_terrain_cb:
		d["ignore_terrain_cost"] = _edit_ignore_terrain_cb.button_pressed
	if _edit_max_armor_spin:
		d["max_armor_slots"] = int(_edit_max_armor_spin.value)
	if _edit_max_talent_spin:
		d["max_talent_slots"] = int(_edit_max_talent_spin.value)
	if _edit_arena_exp_spin:
		d["arena_exp"] = int(_edit_arena_exp_spin.value)

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

	if _edit_sprite_frames_path:
		var sf_path : String = _edit_sprite_frames_path.text.strip_edges()
		if sf_path != "":
			d["sprite_frames_path"] = sf_path
		else:
			d.erase("sprite_frames_path")

	var new_hooks : Dictionary = {}
	for k in _edit_boss_dialogue_opts:
		var opt : OptionButton = _edit_boss_dialogue_opts[k]
		var v = _get_meta(opt)
		if v != "":
			new_hooks[k] = v
	if not new_hooks.is_empty():
		d["boss_dialogue_hooks"] = new_hooks
	else:
		d.erase("boss_dialogue_hooks")

	d["attr_cap_levels"] = _read_attr_cap_levels()
	d["level_mechanics"] = _read_level_mechanics()   # ★ 步 5

	var branches : Array = _read_branches()
	if branches.is_empty():
		d.erase("advanced_branches")
	else:
		d["advanced_branches"] = branches

	var phases : Array = _read_boss_phases()
	if phases.is_empty():
		d.erase("phases")
	else:
		d["phases"] = phases

	var f := FileAccess.open(UNIT_DATA_PATH, FileAccess.WRITE)
	if f == null:
		_edit_status.text = "❌ 保存失败"
		return
	f.store_string(JSON.stringify(_unit_db, "  "))
	f.close()

	UnitDataManager.reload_all()
	_frames_texture_cache.clear()
	_refresh_sim_unit_lists()
	_refresh_unit_list()
	_edit_status.text = "✓ 已保存"

	var warn : String = ""
	var sf_path2 : String = str(d.get("sprite_frames_path", ""))
	if sf_path2 != "":
		if not ResourceLoader.exists(sf_path2):
			warn = "  ⚠ SpriteFrames 路径不存在"
		else:
			var sf = load(sf_path2)
			if not (sf is SpriteFrames):
				warn = "  ⚠ SpriteFrames 类型错误"
			else:
				for anim in ["idle", "down", "up", "side"]:
					if not sf.has_animation(anim) or sf.get_frame_count(anim) == 0:
						warn = "  ⚠ %s 无帧" % anim
						break
	if warn != "":
		_edit_status.text += warn
	print("[GameDataEditor] unit_data.json 已保存")


# ============================================================
#  战斗模拟
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
#  数值编辑
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
#  单位解锁
# ============================================================
func _build_unit_unlock_tab(parent : Control) -> Control:
	var panel := HBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 12)
	parent.add_child(panel)

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
#  校验
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

	var fix_btn := Button.new()
	fix_btn.text = "🪄 一键修复"
	fix_btn.modulate = Color(0.6, 1.0, 1.0)
	fix_btn.pressed.connect(_on_auto_fix_pressed)
	bar.add_child(fix_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.pressed.connect(func():
		if _validator_output: _validator_output.clear()
		if _validator_status: _validator_status.text = ""
	)
	bar.add_child(clear_btn)

	var copy_btn := Button.new()
	copy_btn.text = "复制日志"
	copy_btn.pressed.connect(func():
		if _validator_raw_log != "":
			DisplayServer.clipboard_set(_validator_raw_log)
			_validator_status.text = "✓ 日志已复制到剪贴板"
			_validator_status.modulate = Color(0.6, 1.0, 0.6)
		else:
			_validator_status.text = "（无日志可复制，请先运行校验）"
			_validator_status.modulate = Color(1.0, 0.6, 0.6)
	)
	bar.add_child(copy_btn)

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
	_validator_output.add_theme_font_size_override("normal_font_size", 8)
	_validator_output.add_theme_font_size_override("bold_font_size", 8)
	_validator_output.add_theme_font_size_override("italics_font_size", 8)
	_validator_output.add_theme_font_size_override("mono_font_size", 8)
	scroll.add_child(_validator_output)

	return panel


func _run_validation():
	if _validator_output == null: return
	_validator_output.clear()
	_validator_raw_log = ""
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
		_validator_raw_log = "✓ 全部通过，未发现问题\n"
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
		_validator_raw_log += fname + "\n"
		var entries : Array = by_file[fname]
		for r in entries:
			var path : String = r["path"]
			var msg : String = r["message"]
			if r["level"] == DataValidator.Level.ERROR:
				_validator_output.append_text(
					"  [color=#FF6B6B]✗[/color] [color=#888]%s[/color]  %s\n" % [path, msg])
				_validator_raw_log += "  [X] " + path + "  " + msg + "\n"
			else:
				_validator_output.append_text(
					"  [color=#FFD966]⚠[/color] [color=#888]%s[/color]  %s\n" % [path, msg])
				_validator_raw_log += "  [!] " + path + "  " + msg + "\n"
		_validator_output.append_text("\n")
		_validator_raw_log += "\n"

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
	row.add_child(_lbl(label, 90))
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


func _get_all_dialogue_ids() -> Array:
	var ids : Array = []
	if StoryManager:
		for k in StoryManager._dialogue_index:
			ids.append(k)
	ids.sort()
	return ids


func _clear_container(container: Node):
	if not container: return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _get_meta(opt : OptionButton) -> String:
	if opt == null: return ""
	var idx : int = opt.selected
	if idx < 0: return ""
	var m = opt.get_item_metadata(idx)
	return str(m) if m != null else ""


# ============================================================
#  新建 / 删除 / 重命名
# ============================================================
func _on_add_unit_pressed():
	var existing = get_node_or_null("AddUnitOverlay")
	if existing: return

	var overlay := Control.new()
	overlay.name = "AddUnitOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -190
	panel.offset_right = 190
	panel.offset_top = -140
	panel.offset_bottom = 140

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 1)
	sb.border_color = Color(0.4, 0.4, 0.5, 1)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "新建单位"
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 8)
	vbox.add_child(id_row)
	var id_lb := Label.new()
	id_lb.text = "唯一ID:"
	id_lb.custom_minimum_size = Vector2(60, 0)
	id_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	id_row.add_child(id_lb)
	var le := LineEdit.new()
	le.placeholder_text = "例如: boss_new"
	le.custom_minimum_size = Vector2(0, 24)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.select_all_on_focus = true
	id_row.add_child(le)

	var tpl_row := HBoxContainer.new()
	tpl_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tpl_row)
	var tpl_lb := Label.new()
	tpl_lb.text = "模板:"
	tpl_lb.custom_minimum_size = Vector2(60, 0)
	tpl_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tpl_row.add_child(tpl_lb)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size = Vector2(0, 24)
	opt.add_theme_font_size_override("font_size", 8)
	tpl_row.add_child(opt)

	# ★ 第一项：空白单位
	opt.add_item("★ 空白单位（从零开始）")
	opt.set_item_metadata(opt.item_count - 1, {"type": "blank"})

	for uk in _unit_keys:
		var ud : Dictionary = _unit_db.get(uk, {})
		if ud.is_empty(): continue
		var dn : String = ud.get("display_name", uk)
		opt.add_item("复制：%s (%s)" % [dn, uk])
		opt.set_item_metadata(opt.item_count - 1, {"type": "base", "key": uk})

		var branches : Array = ud.get("advanced_branches", [])
		for b in branches:
			if b is Dictionary and b.get("id", "") != "":
				var bid : String = b.get("id")
				var bname : String = b.get("name", bid)
				opt.add_item("  └ 复制分支：%s (%s)" % [bname, bid])
				opt.set_item_metadata(opt.item_count - 1, {"type": "branch", "base_key": uk, "branch_data": b})

	var create_frames_cb := CheckBox.new()
	create_frames_cb.text = "同时创建空白 SpriteFrames 模板（unit_<id>_frames.tres）"
	create_frames_cb.button_pressed = true
	create_frames_cb.add_theme_font_size_override("font_size", 7)
	vbox.add_child(create_frames_cb)

	var hint := Label.new()
	hint.text = "提示：空白单位所有字段为默认值；创建后请到 Godot 编辑器里补帧、配头像、配默认装备。"
	hint.add_theme_font_size_override("font_size", 7)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.6, 0.6, 0.6)
	vbox.add_child(hint)

	var err_label := Label.new()
	err_label.modulate = Color(1.0, 0.5, 0.5)
	err_label.add_theme_font_size_override("font_size", 8)
	err_label.visible = false
	vbox.add_child(err_label)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	vbox.add_child(btns)

	var ok_btn := Button.new()
	ok_btn.text = "确认创建"
	ok_btn.add_theme_font_size_override("font_size", 9)
	ok_btn.custom_minimum_size = Vector2(90, 24)
	ok_btn.modulate = Color(0.6, 1.0, 0.6)
	btns.add_child(ok_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 9)
	cancel_btn.custom_minimum_size = Vector2(90, 24)
	cancel_btn.pressed.connect(func(): overlay.queue_free())
	btns.add_child(cancel_btn)

	le.grab_focus()
	le.text_submitted.connect(func(_t): ok_btn.emit_signal("pressed"))

	ok_btn.pressed.connect(func():
		var new_key : String = le.text.strip_edges()
		if new_key == "":
			err_label.text = "❌ ID 不能为空"
			err_label.visible = true
			return
		if new_key in _unit_db:
			err_label.text = "❌ ID 已存在，请换一个"
			err_label.visible = true
			return

		var meta = opt.get_item_metadata(opt.selected)
		var new_data: Dictionary = {}

		if meta != null and meta.get("type", "") == "blank":
			new_data = _make_blank_unit_data(new_key)
		elif meta != null and meta.get("type", "") == "base":
			new_data = _unit_db[meta.key].duplicate(true)
		elif meta != null and meta.get("type", "") == "branch":
			new_data = _unit_db[meta.base_key].duplicate(true)
			var br: Dictionary = meta.branch_data
			var sb_dict: Dictionary = br.get("stat_bonus", {})
			for k in sb_dict:
				new_data[k] = int(new_data.get(k, 0)) + int(sb_dict[k])
			var sp: String = br.get("sprite_frames_path", "")
			if sp != "": new_data["sprite_frames_path"] = sp
			var gt: String = br.get("granted_talent", "")
			if gt != "": new_data["default_talents"] = [gt]
			var b_tags: Array = br.get("tags", [])
			if not b_tags.is_empty(): new_data["tags"] = b_tags.duplicate()
			new_data.erase("advanced_branches")
			new_data["advanced_class"] = br.get("id", "")

		new_data["unit_name"] = new_key
		new_data["display_name"] = new_key.replace("_", " ").capitalize()

		if create_frames_cb.button_pressed and str(new_data.get("sprite_frames_path", "")) == "":
			var fname : String = "unit_%s_frames.tres" % new_key
			var full_path : String = SPRITE_FRAMES_DIR + fname
			if not ResourceLoader.exists(full_path):
				var err := _create_blank_sprite_frames(full_path)
				if err == OK:
					new_data["sprite_frames_path"] = full_path

		_unit_db[new_key] = new_data
		_unit_keys.append(new_key)
		_unit_keys.sort()

		var f := FileAccess.open(UNIT_DATA_PATH, FileAccess.WRITE)
		if f == null:
			err_label.text = "❌ 无法写入文件"
			err_label.visible = true
			return
		f.store_string(JSON.stringify(_unit_db, "  "))
		f.close()

		UnitDataManager.reload_all()
		_frames_texture_cache.clear()
		_refresh_unit_list()
		_refresh_sim_unit_lists()
		_select_edit_unit(new_key)
		overlay.queue_free()
	)


func _make_blank_unit_data(unit_key : String) -> Dictionary:
	return {
		"unit_name": unit_key,
		"display_name": unit_key,
		"faction": "",
		"max_hp": 20,
		"strength": 5,
		"dexterity": 5,
		"intelligence": 3,
		"faith": 3,
		"arcane": 3,
		"move_range": 5,
		"ignore_terrain_cost": false,
		"physical_reduction": 0.0,
		"magic_reduction": 0.0,
		"max_armor_slots": 2,
		"max_talent_slots": 1,
		"arena_exp": 30,
		"is_boss": false,
		"hidden_from_roster": false,
		"core_trait": "",
		"tags": [],
		"avatar": "",
		"description": "",
		"flavor": "",
		"sprite_frames_path": "",
		"default_weapon": "",
		"default_armors": [],
		"default_talents": [],
		"attr_cap_levels": [{}, {}, {}, {}, {}],
		"level_mechanics": [{}, {}, {}, {}, {}],
		"advanced_branches": [],
		"phases": [],
		"boss_dialogue_hooks": {},
	}


func _on_delete_unit_pressed():
	if _current_unit_key == "": return
	var check_key = _current_unit_key
	var dn = _unit_db[check_key].get("display_name", check_key)

	var refs = _collect_unit_references(check_key)
	var lines : Array = []
	if refs.total == 0:
		lines.append("（无其他引用）")
	else:
		lines.append("被以下位置引用（删除后需手动修复）：")
		if not refs.phases.is_empty(): lines.append("  unit_data.phases: " + ", ".join(refs.phases))
		if not refs.branches.is_empty(): lines.append("  unit_data.advanced_branches: " + ", ".join(refs.branches))
		if not refs.unlock.is_empty(): lines.append("  unit_unlock: " + ", ".join(refs.unlock))
		if not refs.maps.is_empty(): lines.append("  地图 .tscn: " + ", ".join(refs.maps))
		if not refs.events.is_empty(): lines.append("  events: " + ", ".join(refs.events))
	var refs_text : String = "\n".join(lines)

	Globals.show_confirm(
		self,
		"确定要删除单位【%s (%s)】吗？\n\n%s" % [dn, check_key, refs_text],
		"删除", "取消",
		func():
			_unit_db.erase(check_key)
			_unit_keys.erase(check_key)
			var f := FileAccess.open(UNIT_DATA_PATH, FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(_unit_db, "  "))
				f.close()
			UnitDataManager.reload_all()
			_frames_texture_cache.clear()
			_current_unit_key = ""
			_refresh_unit_list()
			_refresh_sim_unit_lists()
			_set_edit_status("已删除单位: " + check_key)
			if not _unit_keys.is_empty():
				_select_edit_unit(_unit_keys[0])
			else:
				if _edit_right_content:
					_clear_container(_edit_right_content)
					var hint := Label.new()
					hint.text = "（无单位，请新建）"
					hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					_edit_right_content.add_child(hint),
		func(): pass
	)


func _on_rename_unit_pressed():
	if _current_unit_key == "": return
	var old_id : String = _current_unit_key

	var dialog := AcceptDialog.new()
	dialog.title = "重命名单位 ID"
	dialog.dialog_hide_on_ok = false
	dialog.ok_button_text = "扫描引用并重命名"
	dialog.add_cancel_button("取消")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	dialog.add_child(vbox)

	vbox.add_child(_lbl("旧 ID: " + old_id, 8))
	vbox.add_child(_lbl("新 ID:", 8))
	var le := LineEdit.new()
	le.text = old_id
	le.custom_minimum_size = Vector2(320, 24)
	le.select_all_on_focus = true
	vbox.add_child(le)

	var report_scroll := ScrollContainer.new()
	report_scroll.custom_minimum_size = Vector2(280, 100)
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(report_scroll)

	var report := RichTextLabel.new()
	report.bbcode_enabled = true
	report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report.add_theme_font_size_override("normal_font_size", 8)
	report_scroll.add_child(report)

	var refresh_report := func(new_id : String):
		report.clear()
		if new_id.strip_edges() == "" or new_id.strip_edges() == old_id:
			return
		if new_id.strip_edges() in _unit_db:
			report.append_text("[color=#FF6B6B]✗ 新 ID 已存在[/color]\n")
			return
		var refs = _collect_unit_references(old_id)
		report.append_text("[b]将替换以下位置的 %s → %s[/b]\n\n" % [old_id, new_id.strip_edges()])
		if not refs.phases.is_empty():
			report.append_text("[color=#FFD966]unit_data.phases:[/color]\n")
			for r in refs.phases: report.append_text("  · %s\n" % r)
		if not refs.branches.is_empty():
			report.append_text("[color=#FFD966]unit_data.advanced_branches:[/color]\n")
			for r in refs.branches: report.append_text("  · %s\n" % r)
		if not refs.unlock.is_empty():
			report.append_text("[color=#FFD966]unit_unlock:[/color]\n")
			for r in refs.unlock: report.append_text("  · %s\n" % r)
		if not refs.maps.is_empty():
			report.append_text("[color=#FFD966]地图 .tscn:[/color]\n")
			for r in refs.maps: report.append_text("  · %s\n" % r)
		if not refs.events.is_empty():
			report.append_text("[color=#FFD966]events.json:[/color]\n")
			for r in refs.events: report.append_text("  · %s\n" % r)
		report.append_text("\n[color=#7FBF7F]总引用: %d[/color]\n" % refs.total)

	le.text_changed.connect(func(t): refresh_report.call(t))
	refresh_report.call(old_id)

	add_child(dialog)
	dialog.confirmed.connect(func():
		var new_id : String = le.text.strip_edges()
		if new_id == "" or new_id == old_id:
			dialog.queue_free(); return
		if new_id in _unit_db:
			_set_edit_status("❌ 新 ID 已存在")
			return
		_apply_unit_rename(old_id, new_id)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2(320, 200))


func _collect_unit_references(old_id : String) -> Dictionary:
	var result : Dictionary = {
		"phases": [], "branches": [], "unlock": [],
		"maps": [], "events": [], "total": 0
	}
	# 1. unit_data
	for uk in _unit_db:
		var ud : Dictionary = _unit_db[uk]
		var phases : Array = ud.get("phases", [])
		for i in range(phases.size()):
			if phases[i] is Dictionary and str(phases[i].get("form_unit_id", "")) == old_id:
				result["phases"].append("%s.phases[%d]" % [uk, i])
		var branches : Array = ud.get("advanced_branches", [])
		for i in range(branches.size()):
			if branches[i] is Dictionary and str(branches[i].get("standalone_unit_id", "")) == old_id:
				result["branches"].append("%s.advanced_branches[%d]" % [uk, i])
	# 2. unit_unlock
	var dfl : Array = _unit_unlock_data.get("default_unlocked", [])
	for i in range(dfl.size()):
		if str(dfl[i]) == old_id: result["unlock"].append("default_unlocked[%d]" % i)
	var ini : Array = _unit_unlock_data.get("initial_candidates", [])
	for i in range(ini.size()):
		if str(ini[i]) == old_id: result["unlock"].append("initial_candidates[%d]" % i)
	var mu : Array = _unit_unlock_data.get("map_unlock_units", [])
	for i in range(mu.size()):
		if str(mu[i]) == old_id: result["unlock"].append("map_unlock_units[%d]" % i)
	var mp : Dictionary = _unit_unlock_data.get("map_unlock_mapping", {})
	if mp.has(old_id): result["unlock"].append("map_unlock_mapping key")
	for src in mp:
		var arr : Array = mp[src]
		for i in range(arr.size()):
			if str(arr[i]) == old_id: result["unlock"].append("map_unlock_mapping.%s[%d]" % [src, i])
	var costs : Dictionary = _unit_unlock_data.get("unlock_costs", {})
	if costs.has(old_id): result["unlock"].append("unlock_costs key")
	# 3. 地图 .tscn
	_scan_map_tscn_refs(old_id, result["maps"])
	# 4. events
	for eid in _events_db:
		var ev : Dictionary = _events_db[eid]
		var actions : Array = ev.get("actions", [])
		for i in range(actions.size()):
			var a : Dictionary = actions[i]
			if str(a.get("type", "")) == "unlock_unit":
				var us : Array = a.get("units", [])
				for j in range(us.size()):
					if str(us[j]) == old_id:
						result["events"].append("%s.actions[%d].units[%d]" % [eid, i, j])
	result["total"] = result["phases"].size() + result["branches"].size() + result["unlock"].size() + result["maps"].size() + result["events"].size()
	return result


func _scan_map_tscn_refs(old_id : String, out : Array) -> void:
	var dir_stack : Array = [MAP_ROOT_DIR]
	while not dir_stack.is_empty():
		var cur : String = dir_stack.pop_back()
		var dir := DirAccess.open(cur)
		if dir == null: continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if dir.current_is_dir():
				if fname != "." and fname != "..":
					dir_stack.append(cur + fname + "/")
			elif fname.ends_with(".tscn"):
				var path : String = cur + fname
				var f := FileAccess.open(path, FileAccess.READ)
				if f:
					var text : String = f.get_as_text()
					f.close()
					if text.contains('unit_name = "' + old_id + '"'):
						if path not in out:
							out.append(path)
			fname = dir.get_next()
		dir.list_dir_end()


func _apply_unit_rename(old_id : String, new_id : String) -> void:
	var ud : Dictionary = _unit_db.get(old_id, {})
	if ud.is_empty(): return

	# 1. unit_data.json 内部引用
	for uk in _unit_db:
		var d : Dictionary = _unit_db[uk]
		var phases : Array = d.get("phases", [])
		for p in phases:
			if p is Dictionary and str(p.get("form_unit_id", "")) == old_id:
				p["form_unit_id"] = new_id
		var branches : Array = d.get("advanced_branches", [])
		for b in branches:
			if b is Dictionary and str(b.get("standalone_unit_id", "")) == old_id:
				b["standalone_unit_id"] = new_id

	# 2. 主键
	_unit_db.erase(old_id)
	ud["unit_name"] = new_id
	_unit_db[new_id] = ud
	_unit_keys.erase(old_id)
	_unit_keys.append(new_id)
	_unit_keys.sort()

	# 3. unit_unlock.json
	var dfl : Array = _unit_unlock_data.get("default_unlocked", [])
	for i in range(dfl.size()):
		if str(dfl[i]) == old_id: dfl[i] = new_id
	var ini : Array = _unit_unlock_data.get("initial_candidates", [])
	for i in range(ini.size()):
		if str(ini[i]) == old_id: ini[i] = new_id
	var mu : Array = _unit_unlock_data.get("map_unlock_units", [])
	for i in range(mu.size()):
		if str(mu[i]) == old_id: mu[i] = new_id
	var mp : Dictionary = _unit_unlock_data.get("map_unlock_mapping", {})
	if mp.has(old_id):
		var v = mp[old_id]
		mp.erase(old_id)
		mp[new_id] = v
	for src in mp:
		var arr : Array = mp[src]
		for i in range(arr.size()):
			if str(arr[i]) == old_id: arr[i] = new_id
	var costs : Dictionary = _unit_unlock_data.get("unlock_costs", {})
	if costs.has(old_id):
		var v = costs[old_id]
		costs.erase(old_id)
		costs[new_id] = v

	# 4. events.json
	for eid in _events_db:
		var ev : Dictionary = _events_db[eid]
		var actions : Array = ev.get("actions", [])
		for a in actions:
			if a is Dictionary and str(a.get("type", "")) == "unlock_unit":
				var us : Array = a.get("units", [])
				for i in range(us.size()):
					if str(us[i]) == old_id: us[i] = new_id

	# 5. 地图 .tscn
	_rename_in_map_tscn(old_id, new_id)

	# 6. 写盘
	var f1 := FileAccess.open(UNIT_DATA_PATH, FileAccess.WRITE)
	if f1: f1.store_string(JSON.stringify(_unit_db, "  ")); f1.close()
	var f2 := FileAccess.open(UNIT_UNLOCK_PATH, FileAccess.WRITE)
	if f2: f2.store_string(JSON.stringify(_unit_unlock_data, "  ")); f2.close()
	var f3 := FileAccess.open(EVENT_PATH_FOR_EDITOR, FileAccess.WRITE)
	if f3: f3.store_string(JSON.stringify(_events_db, "  ")); f3.close()

	UnitDataManager.reload_all()
	Globals._load_unlock_config()
	_frames_texture_cache.clear()
	_current_unit_key = new_id
	_refresh_unit_list()
	_refresh_sim_unit_lists()
	_select_edit_unit(new_id)
	_set_edit_status("✓ 已重命名: %s → %s" % [old_id, new_id])


func _rename_in_map_tscn(old_id : String, new_id : String) -> void:
	var dir_stack : Array = [MAP_ROOT_DIR]
	while not dir_stack.is_empty():
		var cur : String = dir_stack.pop_back()
		var dir := DirAccess.open(cur)
		if dir == null: continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if dir.current_is_dir():
				if fname != "." and fname != "..":
					dir_stack.append(cur + fname + "/")
			elif fname.ends_with(".tscn"):
				var path : String = cur + fname
				var f := FileAccess.open(path, FileAccess.READ)
				if f:
					var text : String = f.get_as_text()
					f.close()
					if text.contains('unit_name = "' + old_id + '"'):
						text = text.replace('unit_name = "' + old_id + '"', 'unit_name = "' + new_id + '"')
						var wf := FileAccess.open(path, FileAccess.WRITE)
						if wf: wf.store_string(text); wf.close()
			fname = dir.get_next()
		dir.list_dir_end()


# ============================================================
#  头像 / SpriteFrames
# ============================================================
func _add_avatar_option_row(parent : Node, label : String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	row.add_child(_lbl(label, 40))

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", FS_BUTTON)
	# 让按钮上显示的头像图标为 32×32（与原来的预览尺寸一致）
	opt.add_theme_constant_override("icon_max_width", 32)
	var popup := opt.get_popup()
	if popup:
		popup.add_theme_constant_override("icon_max_width", 32)
	opt.add_item("（无）", 0)
	opt.set_item_metadata(0, "")

	for i in range(_avatar_ids.size()):
		var aid : String = _avatar_ids[i]
		var tex : Texture2D = IconManager.get_icon_or_null(aid)
		if tex:
			opt.add_icon_item(tex, aid, i + 1)
		else:
			opt.add_item(aid, i + 1)
		opt.set_item_metadata(i + 1, aid)

	row.add_child(opt)
	return opt

func _add_sprite_frames_path_row(parent : Node, label : String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	row.add_child(_lbl(label, 40))

	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.placeholder_text = "res://content/images/characters/unit_xxx_frames.tres"
	row.add_child(le)

	var pick_btn := Button.new()
	pick_btn.text = "选择"
	pick_btn.custom_minimum_size = Vector2(36, 16)
	pick_btn.add_theme_font_size_override("font_size", 6)
	pick_btn.pressed.connect(_on_pick_sprite_frames.bind(le))
	row.add_child(pick_btn)

	var new_btn := Button.new()
	new_btn.text = "新建"
	new_btn.custom_minimum_size = Vector2(36, 16)
	new_btn.add_theme_font_size_override("font_size", 6)
	new_btn.tooltip_text = "创建一个空白 SpriteFrames（含 idle/down/up/side），之后在 Godot 编辑器里拖帧"
	new_btn.pressed.connect(_on_new_sprite_frames_template.bind(le))
	row.add_child(new_btn)

	var copy_btn := Button.new()
	copy_btn.text = "复制路径"
	copy_btn.custom_minimum_size = Vector2(52, 16)
	copy_btn.add_theme_font_size_override("font_size", 6)
	copy_btn.pressed.connect(func():
		var p : String = le.text.strip_edges()
		if p != "":
			DisplayServer.clipboard_set(p)
			_set_edit_status("已复制路径")
	)
	row.add_child(copy_btn)

	var open_btn := Button.new()
	open_btn.text = "打开目录"
	open_btn.custom_minimum_size = Vector2(52, 16)
	open_btn.add_theme_font_size_override("font_size", 6)
	open_btn.pressed.connect(func():
		var p : String = le.text.strip_edges()
		if p != "" and p.begins_with("res://"):
			OS.shell_show_in_file_manager(ProjectSettings.globalize_path(p.get_base_dir()))
	)
	row.add_child(open_btn)

	var prev_row := HBoxContainer.new()
	prev_row.add_theme_constant_override("separation", 3)
	parent.add_child(prev_row)
	prev_row.add_child(_lbl("预览", 40))

	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(32, 32)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.modulate = Color(0.5, 0.5, 0.5, 1)
	prev_row.add_child(tex_rect)

	le.text_changed.connect(func(t):
		_update_sprite_frames_preview(tex_rect, t)
	)
	return {"le": le, "preview": tex_rect}


func _get_idle_first_frame(frames_path : String) -> Texture2D:
	var path : String = frames_path.strip_edges()
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _frames_texture_cache.has(path):
		return _frames_texture_cache[path]
	var sf = load(path)
	if not (sf is SpriteFrames):
		_frames_texture_cache[path] = null
		return null
	var tex : Texture2D = null
	if sf.has_animation("idle") and sf.get_frame_count("idle") > 0:
		tex = sf.get_frame_texture("idle", 0)
	_frames_texture_cache[path] = tex
	return tex


func _update_sprite_frames_preview(tex_rect : TextureRect, path : String):
	if tex_rect == null or not is_instance_valid(tex_rect): return
	var tex := _get_idle_first_frame(path)
	if tex:
		tex_rect.texture = tex
		tex_rect.modulate = Color.WHITE
	else:
		tex_rect.texture = null
		tex_rect.modulate = Color(0.5, 0.5, 0.5, 1)


func _on_pick_sprite_frames(le : LineEdit):
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.add_filter("*.tres", "SpriteFrames")
	fd.use_native_dialog = true
	fd.current_dir = SPRITE_FRAMES_DIR
	fd.title = "选择 SpriteFrames 资源"
	fd.file_selected.connect(func(path):
		le.text = path
		le.text_changed.emit(path)
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(500, 400))


func _on_new_sprite_frames_template(le : LineEdit):
	var default_name : String = ""
	if _current_unit_key != "":
		default_name = "unit_%s_frames.tres" % _current_unit_key
	else:
		default_name = "unit_new_frames.tres"

	var dialog := AcceptDialog.new()
	dialog.title = "新建 SpriteFrames 模板"
	dialog.dialog_hide_on_ok = false
	dialog.ok_button_text = "创建"
	dialog.add_cancel_button("取消")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	dialog.add_child(vbox)

	vbox.add_child(_lbl("文件名（不含目录）:", 8))
	var name_edit := LineEdit.new()
	name_edit.text = default_name
	name_edit.custom_minimum_size = Vector2(240, 24)
	vbox.add_child(name_edit)

	var hint := Label.new()
	hint.text = "将创建空白 SpriteFrames，含 idle / down / up / side 四个动画（0 帧）。\n保存到 res://content/images/characters/ 后，请到 Godot 编辑器里打开并拖入图集帧。"
	hint.add_theme_font_size_override("font_size", 7)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(240, 40)
	vbox.add_child(hint)

	add_child(dialog)
	dialog.confirmed.connect(func():
		var fname : String = name_edit.text.strip_edges()
		if fname == "":
			return
		if not fname.ends_with(".tres"):
			fname += ".tres"
		var full_path : String = SPRITE_FRAMES_DIR + fname
		if ResourceLoader.exists(full_path):
			_set_edit_status("❌ 文件已存在: " + full_path)
			return
		var err := _create_blank_sprite_frames(full_path)
		if err != OK:
			_set_edit_status("❌ 保存失败: %d" % err)
			return
		le.text = full_path
		le.text_changed.emit(full_path)
		_set_edit_status("✓ 已创建空白 SpriteFrames: " + fname)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2(280, 160))


func _create_blank_sprite_frames(full_path : String) -> int:
	var sf := SpriteFrames.new()
	for anim in ["idle", "down", "up", "side"]:
		if not sf.has_animation(anim):
			sf.add_animation(anim)
		sf.set_animation_speed(anim, 5.0)
		sf.set_animation_loop(anim, true)
	return ResourceSaver.save(sf, full_path)


# ============================================================
#  一键修复
# ============================================================
func _on_auto_fix_pressed():
	var fix_logs : Array = []

	for uk in _unit_db:
		var ud : Dictionary = _unit_db[uk]
		if ud.is_empty(): continue

		var dw : String = str(ud.get("default_weapon", ""))
		if dw != "" and ItemManager.get_item_data(dw) == null:
			fix_logs.append("单位 [%s] 的默认武器不存在 (%s)，将移除该武器" % [uk, dw])
			ud["default_weapon"] = ""

		var armors : Array = ud.get("default_armors", [])
		var valid_armors : Array = []
		var armor_removed = false
		for aid in armors:
			if ItemManager.get_item_data(aid) != null:
				valid_armors.append(aid)
			else:
				armor_removed = true
		if armor_removed:
			ud["default_armors"] = valid_armors
			fix_logs.append("单位 [%s] 的默认防具包含无效引用，已清理" % uk)

		var talents : Array = ud.get("default_talents", [])
		var valid_talents : Array = []
		var talent_removed = false
		for tid in talents:
			if tid in _talent_ids:
				valid_talents.append(tid)
			else:
				talent_removed = true
		if talent_removed:
			ud["default_talents"] = valid_talents
			fix_logs.append("单位 [%s] 的默认特技包含无效引用，已清理" % uk)

		var branches : Array = ud.get("advanced_branches", [])
		for b in branches:
			if b is Dictionary:
				var gt : String = str(b.get("granted_talent", ""))
				if gt != "" and gt not in _talent_ids:
					b["granted_talent"] = ""
					fix_logs.append("单位 [%s] 的转职分支赋予特技不存在 (%s)，已清空" % [uk, gt])

		var phases : Array = ud.get("phases", [])
		for i in range(phases.size()):
			var p : Dictionary = phases[i]
			var fid : String = str(p.get("form_unit_id", ""))
			if fid != "" and fid != "self" and not _unit_db.has(fid):
				p["form_unit_id"] = ""
				fix_logs.append("单位 [%s] 的阶段 %d 指向的变身单位不存在 (%s)，已重置为覆盖模式" % [uk, i + 1, fid])

	if _unit_unlock_data.has("map_unlock_units"):
		var mu : Array = _unit_unlock_data["map_unlock_units"]
		var valid_mu : Array = []
		var mu_removed = false
		for u in mu:
			if _unit_db.has(u): valid_mu.append(u)
			else: mu_removed = true
		if mu_removed:
			_unit_unlock_data["map_unlock_units"] = valid_mu
			fix_logs.append("地图解锁池包含无效单位，已清理")

	if _unit_unlock_data.has("map_unlock_mapping"):
		var mapping : Dictionary = _unit_unlock_data["map_unlock_mapping"]
		var new_mapping : Dictionary = {}
		var map_removed = false
		for k in mapping:
			if not _unit_db.has(k):
				map_removed = true
				continue
			var targets : Array = mapping[k]
			var valid_tg : Array = []
			for tg in targets:
				if _unit_db.has(tg): valid_tg.append(tg)
				else: map_removed = true
			if not valid_tg.is_empty():
				new_mapping[k] = valid_tg
		if map_removed:
			_unit_unlock_data["map_unlock_mapping"] = new_mapping
			fix_logs.append("地图解锁映射包含无效单位，已清理")

	if fix_logs.is_empty():
		Globals.show_confirm(self, "✓ 没有发现可以自动修复的问题。", "确定", "", func(): pass, func(): pass, false)
		return

	var msg = "发现 %d 处可以安全修复的问题：\n\n" % fix_logs.size()
	var show_count = mini(fix_logs.size(), 15)
	for i in range(show_count):
		msg += "· " + fix_logs[i] + "\n"
	if fix_logs.size() > show_count:
		msg += "... (还有 %d 处)\n" % (fix_logs.size() - show_count)
	msg += "\n是否立即执行修复并保存？"

	Globals.show_confirm(
		self,
		msg,
		"执行修复", "取消",
		func():
			var f1 := FileAccess.open(UNIT_DATA_PATH, FileAccess.WRITE)
			if f1:
				f1.store_string(JSON.stringify(_unit_db, "  "))
				f1.close()

			var f2 := FileAccess.open(UNIT_UNLOCK_PATH, FileAccess.WRITE)
			if f2:
				f2.store_string(JSON.stringify(_unit_unlock_data, "  "))
				f2.close()

			UnitDataManager.reload_all()
			Globals._load_unlock_config()
			_frames_texture_cache.clear()
			_refresh_unit_list()
			_refresh_sim_unit_lists()

			if _current_unit_key != "" and _unit_db.has(_current_unit_key):
				_select_edit_unit(_current_unit_key)

			_run_validation()
			_validator_status.text = "✓ 自动修复完成"
			_validator_status.modulate = Color(0.6, 1.0, 0.6),
		func(): pass
	)
