class_name AnvilTavern
extends CanvasLayer

signal closed

enum Tab { WEAPON_UPGRADE, AURA_RESEARCH }

var _entry_tab : int = 0

func setup(tab: int) -> void:
	_entry_tab = tab
	if is_node_ready():
		_switch_tab(tab as Tab)

var current_tab : Tab = Tab.WEAPON_UPGRADE

@onready var title_label : Label = $Panel/VBox/TitleBar/TitleLabel
@onready var materials_label : Label = $Panel/VBox/TitleBar/MaterialsLabel
@onready var content_container : VBoxContainer = $Panel/VBox/ContentScroll/ContentContainer

var _sub_tab_bar : HBoxContainer = null

func _ready():
	_ensure_sub_tab_bar()
	MusicManager.play_anvil_tavern_music()
	_refresh_resource_label()
	_switch_tab(_entry_tab as Tab)

func _ensure_sub_tab_bar():
	if _sub_tab_bar and is_instance_valid(_sub_tab_bar): return
	_sub_tab_bar = HBoxContainer.new()
	_sub_tab_bar.name = "SubTabBar"
	_sub_tab_bar.add_theme_constant_override("separation", 4)
	var vbox : VBoxContainer = $Panel/VBox
	vbox.add_child(_sub_tab_bar)
	vbox.move_child(_sub_tab_bar, 1)

func _clear_sub_tab_bar():
	if not _sub_tab_bar: return
	for child in _sub_tab_bar.get_children():
		_sub_tab_bar.remove_child(child); child.queue_free()

func _refresh_resource_label():
	if materials_label:
		materials_label.text = "魂: %d" % GameState.soul

func _switch_tab(tab: Tab):
	current_tab = tab
	_clear_content()
	_clear_sub_tab_bar()
	if tab == Tab.WEAPON_UPGRADE:
		title_label.text = "灰烬铁匠 · 武器升级"
	else:
		title_label.text = "灰烬铁匠 · 光环研究"

	# 子 Tab 按钮
	var wb = Button.new()
	wb.text = "武器升级"
	wb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	wb.modulate = Color.WHITE if tab == Tab.WEAPON_UPGRADE else Color(0.5,0.5,0.5,1)
	wb.pressed.connect(func(): _switch_tab(Tab.WEAPON_UPGRADE))
	_sub_tab_bar.add_child(wb)

	var ab = Button.new()
	ab.text = "光环研究"
	ab.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	ab.modulate = Color.WHITE if tab == Tab.AURA_RESEARCH else Color(0.5,0.5,0.5,1)
	ab.pressed.connect(func(): _switch_tab(Tab.AURA_RESEARCH))
	_sub_tab_bar.add_child(ab)

	if tab == Tab.WEAPON_UPGRADE:
		_build_weapon_upgrade_list()
	else:
		_build_aura_research_list()

# ============================================================
#  Tab 1: 武器升级（消耗魂）
# ============================================================
func _build_weapon_upgrade_list():
	var all_units = UnitDataManager.get_all_unit_ids()
	var found_any : bool = false
	for unit_type in all_units:
		if not Globals.is_unit_unlocked(unit_type): continue
		var weapon_id = UnitDataManager.get_default_weapon_id(unit_type)
		if weapon_id == "": continue
		found_any = true
		content_container.add_child(_build_weapon_row(unit_type, weapon_id))
	if not found_any:
		content_container.add_child(_make_hint("（暂无可升级武器）"))

func _build_weapon_row(unit_type: String, weapon_id: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var wdata : ItemData = ItemManager.get_item_data(weapon_id)
	if not wdata: return row

	var unit_display = UnitDataManager.get_unit_type_display_name(unit_type)
	var current_lv : int = _get_weapon_level(unit_type, weapon_id)
	var max_lv : int = 5   # 7.2 规定：上限 5 级

	var name_label = Label.new()
	name_label.text = "%s · %s" % [unit_display, wdata.name]
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)

	var lv_label = Label.new()
	lv_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lv_label.custom_minimum_size = Vector2(60, 0)
	lv_label.text = "Lv %d / %d" % [current_lv, max_lv]
	row.add_child(lv_label)

	var cost_label = Label.new()
	cost_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cost : int = _get_weapon_upgrade_cost(current_lv)
	if current_lv >= max_lv:
		cost_label.text = "已满级"
	else:
		cost_label.text = "消耗：%d 魂" % cost
	row.add_child(cost_label)

	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(60, 0)
	if current_lv >= max_lv:
		btn.text = "已满级"
		btn.disabled = true
	else:
		btn.text = "升级"
		btn.disabled = (GameState.soul < cost)
		btn.pressed.connect(_on_upgrade_weapon.bind(unit_type, weapon_id, cost))
	row.add_child(btn)

	return row

func _get_weapon_level(unit_type: String, weapon_id: String) -> int:
	var d = GameState.unit_growth.get(unit_type, {})
	return int(d.get("weapon_lv_" + weapon_id, 0))

func _set_weapon_level(unit_type: String, weapon_id: String, lv: int):
	if not GameState.unit_growth.has(unit_type):
		GameState.unit_growth[unit_type] = {}
	GameState.unit_growth[unit_type]["weapon_lv_" + weapon_id] = lv

func _get_weapon_upgrade_cost(current_lv: int) -> int:
	# 1→2: 50, 2→3: 120, 3→4: 250, 4→5: 500（与 v3.0 §7.2 对齐）
	var costs = [50, 120, 250, 500]
	if current_lv < 0 or current_lv >= costs.size(): return -1
	return costs[current_lv]

func _on_upgrade_weapon(unit_type: String, weapon_id: String, cost: int):
	if GameState.soul < cost: return
	GameState.soul -= cost
	var lv = _get_weapon_level(unit_type, weapon_id)
	_set_weapon_level(unit_type, weapon_id, lv + 1)
	SaveManager.auto_save()
	_refresh_resource_label()
	_switch_tab(Tab.WEAPON_UPGRADE)

# ============================================================
#  Tab 2: 光环研究（占位，见 C-9）
# ============================================================
func _build_aura_research_list():
	content_container.add_child(_make_hint("（光环研究待实现 — 见 AuraResearchManager）"))

# ============================================================
#  辅助
# ============================================================
func _clear_content():
	for child in content_container.get_children():
		content_container.remove_child(child); child.queue_free()

func _make_hint(text: String) -> Label:
	var lb = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.modulate = Color(0.6, 0.6, 0.6, 1)
	return lb

func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()
