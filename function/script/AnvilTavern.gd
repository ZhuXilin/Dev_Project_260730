class_name AnvilTavern
extends CanvasLayer

signal closed
enum Tab { WEAPON_UPGRADE, AURA_RESEARCH }

var _entry_tab : int = 0
var _info_panel : Control = null
var _current_hover_data : Dictionary = {} # 记录悬停数据，供右键刷新

# 记录当前悬停的类型和ID
var _hover_type : String = ""
var _hover_id : String = ""

func setup(tab: int) -> void:
	_entry_tab = tab
	if is_node_ready():
		_switch_tab(tab as Tab)

var current_tab : Tab = Tab.WEAPON_UPGRADE

@onready var title_label : Label = $Panel/VBox/TitleBar/TitleLabel
@onready var materials_label : Label = $Panel/VBox/TitleBar/MaterialsLabel
@onready var content_container : VBoxContainer = $Panel/VBox/ContentScroll/ContentContainer

var _sub_tab_bar : HBoxContainer = null
const WEAPON_MAX_LV : int = 5
var _weapon_upgrade_costs : Array = [50, 120, 250, 500, 1000]

func _ready():
	_load_config_from_json()
	_ensure_layout()        # 先造出 hbox
	_ensure_sub_tab_bar()   # 再把 tab 插到 TitleBar 下面
	MusicManager.play_anvil_tavern_music()
	_refresh_resource_label()
	_switch_tab(_entry_tab as Tab)

# ★ 支持右键切换叙事
func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _info_panel and _hover_type != "":
			Globals.toggle_info_mode()
			_refresh_info_panel()
			get_viewport().set_input_as_handled()

func _ensure_layout():
	var vbox : VBoxContainer = $Panel/VBox
	var scroll : ScrollContainer = $Panel/VBox/ContentScroll
	if not scroll or not vbox: return
	if vbox.has_node("MainHBox"): return
	
	# 防止子节点过宽把父容器撑爆
	vbox.clip_contents = true
	# 增加一点全局间距
	vbox.add_theme_constant_override("separation", 8)
	
	var hbox := HBoxContainer.new()
	hbox.name = "MainHBox"
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	
	vbox.remove_child(scroll)
	hbox.add_child(scroll)
	
	# 左侧列表自适应，禁止横向滚动
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED 
	
	# 右侧信息面板
	var info_scene = load("res://content/scenes/ui/components/ItemInfoPanel.tscn")
	if info_scene:
		_info_panel = info_scene.instantiate()
		_info_panel.custom_minimum_size = Vector2(110, 0)
		_info_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
		_info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.add_child(_info_panel)
		if _info_panel.has_method("clear_info"):
			_info_panel.clear_info()
	
	vbox.add_child(hbox)
	
	# ★ 核心修复：精准获取 BackButton 的索引，把 hbox 插在它前面
	var back_btn = vbox.get_node_or_null("BackButton")
	if back_btn:
		vbox.move_child(hbox, back_btn.get_index())
		# 让返回按钮沉底，并设置最小高度防止被挤压
		back_btn.size_flags_vertical = Control.SIZE_SHRINK_END
		back_btn.custom_minimum_size = Vector2(0, 20)
	else:
		vbox.move_child(hbox, 2) # 兜底

func _load_config_from_json():
	var cfg : Dictionary = GameConfigManager.get_value("economy_config.json", "forge", {})
	var tbl : Array = cfg.get("upgrade_cost_table", [])
	if not tbl.is_empty():
		_weapon_upgrade_costs = tbl.duplicate()

func _ensure_sub_tab_bar():
	if _sub_tab_bar and is_instance_valid(_sub_tab_bar): return
	_sub_tab_bar = HBoxContainer.new()
	_sub_tab_bar.name = "SubTabBar"
	_sub_tab_bar.add_theme_constant_override("separation", 4)
	var vbox : VBoxContainer = $Panel/VBox
	vbox.add_child(_sub_tab_bar)
	# 确保它永远在 TitleBar 下方（索引 1 的位置）
	vbox.move_child(_sub_tab_bar, 1)

func _clear_sub_tab_bar():
	if not _sub_tab_bar: return
	for child in _sub_tab_bar.get_children():
		_sub_tab_bar.remove_child(child)
		child.queue_free()

func _refresh_resource_label():
	if materials_label: materials_label.text = "魂: %d" % GameState.soul

func _switch_tab(tab: Tab):
	current_tab = tab
	_clear_content()
	_clear_sub_tab_bar()

	if tab == Tab.WEAPON_UPGRADE: title_label.text = "灰烬铁匠 · 武器升级"
	else: title_label.text = "灰烬铁匠 · 光环研究"

	var wb := Button.new()
	wb.text = "武器升级"
	wb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	wb.modulate = Color.WHITE if tab == Tab.WEAPON_UPGRADE else Color(0.5, 0.5, 0.5, 1)
	wb.pressed.connect(func(): _switch_tab(Tab.WEAPON_UPGRADE))
	_sub_tab_bar.add_child(wb)

	var ab := Button.new()
	ab.text = "光环研究"
	ab.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	ab.modulate = Color.WHITE if tab == Tab.AURA_RESEARCH else Color(0.5, 0.5, 0.5, 1)
	ab.pressed.connect(func(): _switch_tab(Tab.AURA_RESEARCH))
	_sub_tab_bar.add_child(ab)

	if tab == Tab.WEAPON_UPGRADE: _build_weapon_upgrade_list()
	else: _build_aura_research_list()

# ============================================================
#  武器升级列表
# ============================================================
func _build_weapon_upgrade_list():
	var all_units : Array = UnitDataManager.get_all_unit_ids()
	for unit_type in all_units:
		if not Globals.is_unit_unlocked(unit_type): continue
		var weapon_id : String = UnitDataManager.get_default_weapon_id(unit_type)
		if weapon_id == "": continue
		content_container.add_child(_build_weapon_row(unit_type, weapon_id))

func _build_weapon_row(unit_type: String, weapon_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var wdata : ItemData = ItemManager.get_item_data(weapon_id)
	if not wdata: return row

	var current_lv : int = _get_weapon_level(unit_type, weapon_id)

	# ★ 统一图标大小 20x20
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(20, 20)
	icon_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var icon_rect := TextureRect.new()
	if wdata.icon: icon_rect.texture = wdata.icon
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(icon_rect)
	
	icon_wrap.mouse_entered.connect(_on_weapon_hover.bind(weapon_id, current_lv, unit_type))
	icon_wrap.mouse_exited.connect(_on_info_hover_exit)
	row.add_child(icon_wrap)

	var name_label := Label.new()
	name_label.text = wdata.name
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.clip_text = true
	row.add_child(name_label)

	var cost : int = _get_weapon_upgrade_cost(current_lv)
	var is_maxed : bool = (current_lv >= WEAPON_MAX_LV) or (cost < 0)

	var lv_label := Label.new()
	lv_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lv_label.custom_minimum_size = Vector2(50, 0)
	lv_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv_label.text = "Lv %d / %d" % [current_lv, WEAPON_MAX_LV]
	row.add_child(lv_label)

	var upgrade_btn := Button.new()
	upgrade_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	upgrade_btn.custom_minimum_size = Vector2(60, 0)
	upgrade_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if is_maxed:
		upgrade_btn.text = "已满级"
		upgrade_btn.disabled = true
	else:
		upgrade_btn.text = "%d魂" % cost
		upgrade_btn.disabled = (GameState.soul < cost)
		upgrade_btn.pressed.connect(_on_upgrade_weapon.bind(unit_type, weapon_id, cost))
	row.add_child(upgrade_btn)

	return row

func _get_weapon_level(unit_type: String, weapon_id: String) -> int:
	var d = GameState.unit_growth.get(unit_type, {})
	return int(d.get("weapon_lv_" + weapon_id, 0))

func _set_weapon_level(unit_type: String, weapon_id: String, lv: int):
	if not GameState.unit_growth.has(unit_type): GameState.unit_growth[unit_type] = {}
	GameState.unit_growth[unit_type]["weapon_lv_" + weapon_id] = lv

func _get_weapon_upgrade_cost(current_lv: int) -> int:
	if current_lv < 0 or current_lv >= _weapon_upgrade_costs.size(): return -1
	var cost : int = int(_weapon_upgrade_costs[current_lv])
	if StoryManager.get_affinity("blacksmith") >= 10: cost = int(cost * 0.8)
	return cost

func _on_upgrade_weapon(unit_type: String, weapon_id: String, cost: int):
	if cost <= 0 or GameState.soul < cost: return
	GameState.soul -= cost
	_set_weapon_level(unit_type, weapon_id, _get_weapon_level(unit_type, weapon_id) + 1)
	SaveManager.auto_save()
	_refresh_resource_label()
	_switch_tab(Tab.WEAPON_UPGRADE)
	_on_weapon_hover(weapon_id, _get_weapon_level(unit_type, weapon_id), unit_type) # 刷新右侧面板

# ============================================================
#  光环研究列表
# ============================================================
func _build_aura_research_list():
	var all_ids : Array = AuraManager.get_all_ids()
	var active_id : String = GameState.active_aura_research.get("aura_id", "")
	if active_id != "":
		var d : Dictionary = AuraManager.get_aura(active_id)
		var title : Label = Label.new()
		title.text = "— 研究中：%s (%d/%d) —" % [d.get("name", active_id), AuraManager.get_research_progress(active_id), AuraManager.get_research_time(active_id)]
		title.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_container.add_child(title)

		var accel_btn : Button = Button.new()
		accel_btn.text = "加速 1 局（%d 魂）" % AuraManager.ACCEL_COST
		accel_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		accel_btn.custom_minimum_size = Vector2(120, 22)
		accel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		accel_btn.disabled = (GameState.soul < AuraManager.ACCEL_COST)
		accel_btn.pressed.connect(_on_accelerate_research)
		content_container.add_child(accel_btn)

	for aid in all_ids:
		content_container.add_child(_build_aura_row(aid))

func _build_aura_row(aura_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var d : Dictionary = AuraManager.get_aura(aura_id)
	var unlocked : bool = AuraManager.is_unlocked(aura_id)
	var researching : bool = AuraManager.is_researching(aura_id)
	var busy : bool = not GameState.active_aura_research.is_empty()

	# ★ 统一图标大小 20x20
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(20, 20)
	icon_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var icon_rect := TextureRect.new()
	var tex = d.get("icon")
	if tex is Texture2D: icon_rect.texture = tex
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked: icon_rect.modulate = Color(0.5, 0.5, 0.5, 1)
	icon_wrap.add_child(icon_rect)
	
	icon_wrap.mouse_entered.connect(_on_aura_hover.bind(aura_id, unlocked))
	icon_wrap.mouse_exited.connect(_on_info_hover_exit)
	row.add_child(icon_wrap)

	var name_lb := Label.new()
	name_lb.text = d.get("name", aura_id)
	name_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lb.clip_text = true
	if not unlocked: name_lb.modulate = Color(0.5, 0.5, 0.5, 1)
	row.add_child(name_lb)

	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(60, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unlocked:
		btn.text = "已解锁"
		btn.disabled = true
	elif researching:
		btn.text = "研究中"
		btn.disabled = true
	else:
		var cost : int = AuraManager.get_unlock_cost(aura_id)
		btn.text = "%d 魂" % cost
		btn.disabled = busy or (GameState.soul < cost)
		btn.pressed.connect(_on_start_research.bind(aura_id))
	row.add_child(btn)
	return row

# ============================================================
#  信息面板与右键处理
# ============================================================
func _on_weapon_hover(weapon_id: String, lv: int, unit_type: String):
	_hover_type = "weapon"
	_hover_id = weapon_id
	_current_hover_data = {"weapon_id": weapon_id, "lv": lv, "unit_type": unit_type}
	_refresh_info_panel()

func _on_aura_hover(aura_id: String, unlocked: bool):
	_hover_type = "aura"
	_hover_id = aura_id
	_current_hover_data = {"aura_id": aura_id, "unlocked": unlocked}
	_refresh_info_panel()

func _on_info_hover_exit():
	_hover_type = ""
	_hover_id = ""
	if _info_panel and _info_panel.has_method("clear_info"): _info_panel.clear_info()

func _refresh_info_panel():
	if not _info_panel or _hover_type == "": return
	
	var is_narrative = FlavorManager.is_narrative_mode()
	
	if _hover_type == "weapon":
		var weapon_id = _current_hover_data.weapon_id
		var lv = _current_hover_data.lv
		var wdata = ItemManager.get_item_data(weapon_id)
		if not wdata: return
		
		if is_narrative:
			var flavor = FlavorManager.get_flavor("items", weapon_id)
			_info_panel.show_info({"name": wdata.name, "desc": flavor, "icon": wdata.icon})
			return
			
		var stats = "攻击: %d\n射程: %d~%d" % [WeaponUpgradeHelper.get_effective_base_attack(wdata, lv), wdata.min_attack_range, WeaponUpgradeHelper.get_effective_attack_range(wdata, lv)]
		_info_panel.show_info({
			"name": wdata.name, "name_color": UIConst.QUALITY_COLORS.get(wdata.quality, Color.WHITE),
			"desc": wdata.description, "stats": stats, "icon": wdata.icon
		})
		
	elif _hover_type == "aura":
		var aura_id = _current_hover_data.aura_id
		var ad = AuraManager.get_aura(aura_id)
		if is_narrative:
			var flavor = FlavorManager.get_flavor("auras", aura_id)
			_info_panel.show_info({"name": ad.get("name", aura_id), "desc": flavor, "icon": ad.get("icon")})
			return
			
		var stats = "光环 [%s]\n状态: %s" % [ad.get("tag", ""), "已解锁" if _current_hover_data.unlocked else "未解锁"]
		_info_panel.show_info({
			"name": ad.get("name", aura_id), "name_color": Color(0.7, 0.9, 1.0),
			"desc": ad.get("description", ""), "stats": stats, "icon": ad.get("icon")
		})

func _on_start_research(aura_id: String):
	if AuraManager.start_research(aura_id):
		_refresh_resource_label()
		_switch_tab(Tab.AURA_RESEARCH)

func _on_accelerate_research():
	if AuraManager.accelerate_research():
		_refresh_resource_label()
		_switch_tab(Tab.AURA_RESEARCH)

func _clear_content():
	_hover_type = ""
	if _info_panel and _info_panel.has_method("clear_info"): _info_panel.clear_info()
	for child in content_container.get_children():
		content_container.remove_child(child)
		child.queue_free()

func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music: MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()
