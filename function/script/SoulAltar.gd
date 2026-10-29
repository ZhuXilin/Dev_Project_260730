extends CanvasLayer

signal closed

enum Tab { SOUL_FIRE, ATTR_CAP, UNIT_UNLOCK, RELIC_REFINE }

const ATTR_CAP_COSTS : Array[int] = [20, 50, 120, 250, 500]

var _current_tab : Tab = Tab.SOUL_FIRE
var _current_unit_type : String = ""
var unit_unlock_tab_btn : Button = null
var relic_refine_tab_btn : Button = null

var _unit_info_panel : Control = null
var _item_info_panel : Control = null

var _hover_type : String = ""
var _hover_id : String = ""
var _current_hover_data : Dictionary = {}

@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var soul_fire_tab_btn : Button = $Panel/VBox/TabBar/SoulFireTabBtn
@onready var attr_cap_tab_btn : Button = $Panel/VBox/TabBar/AttrCapTabBtn
@onready var left_title : Label = $Panel/VBox/MainHBox/LeftColumn/LeftTitle
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/LeftColumn/UnitListScroll/UnitList
@onready var unit_sprite : AnimatedSprite2D = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/SpriteContainer/UnitSprite
@onready var unit_name_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitNameLabel
@onready var unit_desc_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitDescLabel
@onready var attr_container : VBoxContainer = $Panel/VBox/MainHBox/InfoPanel/AttrScroll/AttrContainer
@onready var hint_label : Label = $Panel/VBox/MainHBox/InfoPanel/BottomBar/HintLabel

func _ready():
	MusicManager.play_soul_altar_music()
	if soul_fire_tab_btn: soul_fire_tab_btn.text = "魂火"
	if attr_cap_tab_btn: attr_cap_tab_btn.text = "属性上限"
	if hint_label: hint_label.visible = false

	var scroll = get_node_or_null("Panel/VBox/MainHBox/InfoPanel/AttrScroll")
	if scroll and scroll is ScrollContainer:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER

	if soul_fire_tab_btn and not soul_fire_tab_btn.pressed.is_connected(_on_soul_fire_tab_pressed):
		soul_fire_tab_btn.pressed.connect(_on_soul_fire_tab_pressed)
	if attr_cap_tab_btn and not attr_cap_tab_btn.pressed.is_connected(_on_attr_cap_tab_pressed):
		attr_cap_tab_btn.pressed.connect(_on_attr_cap_tab_pressed)

	var tab_bar : HBoxContainer = $Panel/VBox/TabBar
	if tab_bar:
		tab_bar.offset_right = -140
		tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
		tab_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		
		unit_unlock_tab_btn = Button.new()
		unit_unlock_tab_btn.text = "唤醒残魂"
		unit_unlock_tab_btn.add_theme_font_size_override("font_size", 7)
		tab_bar.add_child(unit_unlock_tab_btn)
		unit_unlock_tab_btn.pressed.connect(_on_unit_unlock_tab_pressed)

		relic_refine_tab_btn = Button.new()
		relic_refine_tab_btn.text = "遗物精炼"
		relic_refine_tab_btn.add_theme_font_size_override("font_size", 7)
		tab_bar.add_child(relic_refine_tab_btn)
		relic_refine_tab_btn.pressed.connect(_on_relic_refine_tab_pressed)
		
		for child in tab_bar.get_children():
			if child is Button:
				child.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				child.custom_minimum_size = Vector2(58, 20)

	var title_bar = $Panel/VBox/TitleBar
	if title_bar and soul_label:
		title_bar.remove_child(soul_label)
		var new_soul_label = Label.new()
		new_soul_label.name = "CenterSoulLabel"
		new_soul_label.text = "魂: 0"
		new_soul_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		new_soul_label.add_theme_font_size_override("font_size", 9)
		new_soul_label.modulate = Color(0.9, 0.8, 0.6)
		
		var main_vbox = $Panel/VBox
		main_vbox.add_child(new_soul_label)
		var tab_bar_node = $Panel/VBox/TabBar
		if tab_bar_node:
			main_vbox.move_child(new_soul_label, tab_bar_node.get_index() + 1)
		
		soul_label.queue_free()
		soul_label = new_soul_label

	if unit_name_label: unit_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if unit_desc_label: 
		unit_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		unit_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_setup_hover_manager()
	_ensure_layout()
	_refresh_soul()
	_switch_tab(Tab.SOUL_FIRE)

func _setup_hover_manager():
	var main_hbox = $Panel/VBox/MainHBox
	if main_hbox:
		main_hbox.offset_right = -140

# ★ 核心修复：严格按照 UnitSelectUI 里的锚点配置，让面板大小一致
func _ensure_layout():
	var info_scene = load("res://content/scenes/ui/components/UnitInfoPanel.tscn")
	if info_scene and not _unit_info_panel:
		_unit_info_panel = info_scene.instantiate()
		_unit_info_panel.name = "RightUnitInfo"
		
		_unit_info_panel.anchor_left = 1.0
		_unit_info_panel.anchor_right = 1.0
		_unit_info_panel.anchor_top = 0.5
		_unit_info_panel.anchor_bottom = 0.5
		_unit_info_panel.offset_left = -112.0
		_unit_info_panel.offset_right = -8.0
		_unit_info_panel.offset_top = -112.0
		_unit_info_panel.offset_bottom = 112.0
		_unit_info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_unit_info_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		
		_unit_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_unit_info_panel.z_index = 100 
		$Panel.add_child(_unit_info_panel)
		_unit_info_panel.visible = false 
		if _unit_info_panel.has_method("clear_info"): _unit_info_panel.clear_info()

	var item_scene = load("res://content/scenes/ui/components/ItemInfoPanel.tscn")
	if item_scene and not _item_info_panel:
		_item_info_panel = item_scene.instantiate()
		_item_info_panel.name = "RightItemInfo"
		
		_item_info_panel.anchor_left = 1.0
		_item_info_panel.anchor_right = 1.0
		_item_info_panel.anchor_top = 0.5
		_item_info_panel.anchor_bottom = 0.5
		_item_info_panel.offset_left = -96.0
		_item_info_panel.offset_right = -8.0
		_item_info_panel.offset_top = -72.0
		_item_info_panel.offset_bottom = 72.0
		_item_info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_item_info_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		
		_item_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_item_info_panel.z_index = 100
		$Panel.add_child(_item_info_panel)
		_item_info_panel.visible = false 
		if _item_info_panel.has_method("clear_info"): _item_info_panel.clear_info()

func _on_icon_hover_entered(unit_id: String, _info_panel: Control):
	_hover_type = "unit"
	_hover_id = unit_id
	_refresh_info_panel()

func _on_icon_hover_exited(_info_panel: Control):
	pass 

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _hover_type != "":
			Globals.toggle_info_mode()
			_refresh_info_panel()
			get_viewport().set_input_as_handled()

func _refresh_info_panel():
	if _current_tab == Tab.ATTR_CAP or _current_tab == Tab.UNIT_UNLOCK:
		if not _unit_info_panel: return
		if _hover_type == "": 
			_unit_info_panel.visible = false
			return
		
		_unit_info_panel.visible = true 
		
		var u_data = UnitDataManager.get_unit_data(_hover_id)
		if u_data.is_empty(): return
		
		var is_narrative = FlavorManager.is_narrative_mode()
		var display = u_data.get("display_name", _hover_id)
		
		var avatar_id = u_data.get("avatar", "")
		var icon = IconManager.get_icon_or_null(avatar_id)
		
		if is_narrative:
			var flavor = FlavorManager.get_flavor("units", _hover_id)
			if flavor == "": flavor = "（暂无叙事）"
			_unit_info_panel.show_info({"name": display, "desc": flavor, "icon": icon})
			return
			
		var stats = []
		stats.append("HP: %d" % u_data.get("max_hp", 0))
		stats.append("力量 %d | 灵巧 %d" % [u_data.get("strength", 0), u_data.get("dexterity", 0)])
		stats.append("智力 %d | 信仰 %d" % [u_data.get("intelligence", 0), u_data.get("faith", 0)])
		stats.append("移动力: %d" % u_data.get("move_range", 0))
		
		var desc = u_data.get("description", "")
		_unit_info_panel.show_info({
			"name": display, "type_str": UnitDataManager.get_unit_type_display_name(_hover_id), "desc": desc,
			"stats": "\n".join(stats), "icon": icon
		})

	elif _current_tab == Tab.RELIC_REFINE:
		if not _item_info_panel: return
		if _hover_type == "": 
			_item_info_panel.visible = false
			return
			
		_item_info_panel.visible = true 
		
		var rid = _hover_id
		var is_refined = _current_hover_data.get("is_refined", false)
		var rd = RelicManager.get_relic_data(rid)
		
		if FlavorManager.is_narrative_mode():
			var flavor = FlavorManager.get_flavor("relics", rid)
			_item_info_panel.show_info({"name": rd.get("name", rid), "desc": flavor, "icon": rd.get("icon")})
			return
			
		var desc = rd.get("description", "")
		if is_refined: desc += "\n\n★ 已精炼强化"
		_item_info_panel.show_info({
			"name": rd.get("name", rid), "name_color": Color(1.0, 0.85, 0.3),
			"desc": desc, "icon": rd.get("icon")
		})

func _on_relic_hover(rid: String, is_refined: bool):
	_hover_type = "relic"
	_hover_id = rid
	_current_hover_data = {"rid": rid, "is_refined": is_refined}
	_refresh_info_panel()

func _on_soul_fire_tab_pressed(): _switch_tab(Tab.SOUL_FIRE)
func _on_attr_cap_tab_pressed(): _switch_tab(Tab.ATTR_CAP)
func _on_unit_unlock_tab_pressed(): _switch_tab(Tab.UNIT_UNLOCK)
func _on_relic_refine_tab_pressed(): _switch_tab(Tab.RELIC_REFINE)

func _switch_tab(tab: Tab):
	_current_tab = tab
	soul_fire_tab_btn.modulate = Color.WHITE if tab == Tab.SOUL_FIRE else Color(0.5, 0.5, 0.5, 1)
	attr_cap_tab_btn.modulate = Color.WHITE if tab == Tab.ATTR_CAP else Color(0.5, 0.5, 0.5, 1)
	if unit_unlock_tab_btn:
		unit_unlock_tab_btn.modulate = Color.WHITE if tab == Tab.UNIT_UNLOCK else Color(0.5, 0.5, 0.5, 1)
	if relic_refine_tab_btn:
		relic_refine_tab_btn.modulate = Color.WHITE if tab == Tab.RELIC_REFINE else Color(0.5, 0.5, 0.5, 1)

	_hover_type = ""
	if _unit_info_panel: 
		_unit_info_panel.visible = false
		if _unit_info_panel.has_method("clear_info"): _unit_info_panel.clear_info()
	if _item_info_panel: 
		_item_info_panel.visible = false
		if _item_info_panel.has_method("clear_info"): _item_info_panel.clear_info()

	if tab == Tab.SOUL_FIRE:
		left_title.text = "— 魂火 —"
		_clear_unit_list()
		_refresh_soul_fire_panel()
	elif tab == Tab.ATTR_CAP:
		left_title.text = "— 单位 —"
		_build_unit_list()
		_refresh_attr_cap_panel()
		if _current_unit_type != "": _on_unit_selected(_current_unit_type)
	elif tab == Tab.UNIT_UNLOCK:
		left_title.text = "— 残魂 —"
		_build_locked_unit_list()
		_refresh_unit_unlock_panel()
		if _current_unit_type != "": _on_locked_unit_selected(_current_unit_type)
	else:
		left_title.text = "— 遗物 —"
		_clear_unit_list()
		_build_relic_refine_panel()

func _clear_unit_list():
	for c in unit_list.get_children():
		unit_list.remove_child(c); c.queue_free()

func _build_unit_list():
	for c in unit_list.get_children():
		unit_list.remove_child(c); c.queue_free()

	var all_units = UnitDataManager.get_all_unit_ids()
	for unit_type in all_units:
		if not Globals.is_unit_unlocked(unit_type): continue
		if not UnitDataManager.has_attr_cap_levels(unit_type): continue

		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size = Vector2(0, 36)
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var btn = UnitDataManager.create_unit_icon_button(unit_type, Vector2(32, 32))
		btn.custom_minimum_size = Vector2(32, 32)
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE if unit_type == _current_unit_type else Color(0.4, 0.4, 0.4, 1)
		
		UnitDataManager.bind_unit_icon_hover(btn, unit_type, _unit_info_panel, self, _on_unit_selected.bind(unit_type))
		
		hbox.add_child(btn)
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer)
		unit_list.add_child(hbox)

	if _current_unit_type == "" or not _is_unit_in_list(_current_unit_type):
		for child in unit_list.get_children():
			if child.get_child_count() > 0 and child.get_child(0) is Button:
				var ut = child.get_child(0).get_meta("unit_type", "")
				if ut != "":
					_current_unit_type = ut
					break

func _is_unit_in_list(unit_type: String) -> bool:
	for child in unit_list.get_children():
		if child.get_child_count() > 0 and child.get_child(0) is Button:
			if child.get_child(0).get_meta("unit_type", "") == unit_type:
				return true
	return false

func _on_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	for child in unit_list.get_children():
		if child.get_child_count() > 0 and child.get_child(0) is Button:
			var btn = child.get_child(0)
			var ut = btn.get_meta("unit_type", "")
			if ut != "":
				btn.modulate = Color.WHITE if ut == unit_type else Color(0.4, 0.4, 0.4, 1)
	_refresh_attr_cap_panel()
	
	_hover_type = "unit"
	_hover_id = unit_type
	_refresh_info_panel()

func _build_locked_unit_list():
	for c in unit_list.get_children():
		unit_list.remove_child(c); c.queue_free()

	var initial : Array = Globals.get_initial_candidates()
	var eligible : Array = Globals.get_eligible_units()
	var all_candidates : Array = []
	for k in initial:
		if k not in all_candidates: all_candidates.append(k)
	for k in eligible:
		if k not in all_candidates: all_candidates.append(k)

	var locked : Array = []
	for unit_type in all_candidates:
		if Globals.is_unit_unlocked(unit_type): continue
		if UnitDataManager.get_unit_data(unit_type).is_empty(): continue
		locked.append(unit_type)

	if locked.is_empty():
		var lb := Label.new()
		lb.text = "（所有残魂已唤醒）"
		lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		lb.modulate = Color(0.6, 0.6, 0.6, 1)
		unit_list.add_child(lb)
		return

	for unit_type in locked:
		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size = Vector2(0, 36)
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var btn = UnitDataManager.create_unit_icon_button(unit_type, Vector2(32, 32))
		btn.custom_minimum_size = Vector2(32, 32)
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE if unit_type == _current_unit_type else Color(0.4, 0.4, 0.4, 1)
		
		UnitDataManager.bind_unit_icon_hover(btn, unit_type, _unit_info_panel, self, _on_locked_unit_selected.bind(unit_type))
		
		hbox.add_child(btn)
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer)
		unit_list.add_child(hbox)

	if _current_unit_type == "" or Globals.is_unit_unlocked(_current_unit_type):
		if locked.size() > 0:
			_current_unit_type = locked[0]
		else:
			_current_unit_type = ""

func _on_locked_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	for child in unit_list.get_children():
		if child.get_child_count() > 0 and child.get_child(0) is Button:
			var btn = child.get_child(0)
			var ut = btn.get_meta("unit_type", "")
			if ut != "":
				btn.modulate = Color.WHITE if ut == unit_type else Color(0.4, 0.4, 0.4, 1)
	_refresh_unit_unlock_panel()
	
	_hover_type = "unit"
	_hover_id = unit_type
	_refresh_info_panel()

func _refresh_attr_cap_panel():
	_clear_attr_container()
	if _current_unit_type == "":
		unit_name_label.text = "（未选择）"
		unit_desc_label.text = ""
		unit_sprite.visible = false
		return

	var display : String = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	var dict : Dictionary = UnitDataManager.get_unit_data(_current_unit_type)
	var cur_lv : int = int(GameState.unit_attr_cap.get(_current_unit_type, 0))
	var max_lv : int = ATTR_CAP_COSTS.size()

	unit_name_label.text = "%s   上限 Lv %d / %d" % [display, cur_lv, max_lv]
	unit_desc_label.text = dict.get("description", "")
	unit_sprite.visible = false

	attr_container.add_child(_make_title("— 已获得加成 —"))
	var total : Dictionary = UnitDataManager.get_attr_cap_total_bonus(_current_unit_type, cur_lv)
	if total.is_empty():
		attr_container.add_child(_make_info("（尚无，升级后生效）"))
	else:
		attr_container.add_child(_make_info(_format_bonus_dict(total)))

	if cur_lv < max_lv:
		var current_total := UnitDataManager.get_attr_cap_total_bonus(_current_unit_type, cur_lv)
		var next_total := UnitDataManager.get_attr_cap_total_bonus(_current_unit_type, cur_lv + 1)
		var diff : Dictionary = {}
		for k in next_total:
			var d = next_total[k] - current_total.get(k, 0)
			if d > 0:
				diff[k] = d
				
		attr_container.add_child(_make_title("— 下一级 Lv%d 预览 —" % (cur_lv + 1)))
		attr_container.add_child(_make_info(_format_bonus_dict(diff)))

		var cost : int = ATTR_CAP_COSTS[cur_lv] if cur_lv < ATTR_CAP_COSTS.size() else 1000
		if cost > 0:
			attr_container.add_child(_make_upgrade_row("升级", cost, func(): _on_upgrade_attr_cap()))
	else:
		attr_container.add_child(_make_title("— 已达最高等级 —"))

func _clear_attr_container():
	for c in attr_container.get_children():
		attr_container.remove_child(c); c.queue_free()

func _refresh_soul_fire_panel():
	_clear_attr_container()
	unit_sprite.visible = false
	unit_name_label.text = "魂火祭坛"
	unit_desc_label.text = ""

	var lv : int = SoulFireManager.altar_level
	var max_lv : int = SoulFireManager.MAX_CARRIED_LEVELS.size() - 1
	var cur_max : int = SoulFireManager.get_max_carried()
	var next_max : int = SoulFireManager.MAX_CARRIED_LEVELS[mini(lv + 1, max_lv)]
	var cost : int = SoulFireManager.get_upgrade_cost()

	attr_container.add_child(_make_title("— 携带上限 —"))
	attr_container.add_child(_make_info("Lv %d/%d  |  上限 %d 魂火" % [lv, max_lv, cur_max]))
	
	if cost >= 0:
		attr_container.add_child(_make_upgrade_row("升级上限 (下一级 %d)" % next_max, cost, func(): _on_upgrade_soul_fire_max()))
	else:
		attr_container.add_child(_make_info("已达最高等级"))

	var init_lv : int = GameState.soul_fire_initial_level
	var init_max : int = SoulFireManager.INITIAL_LEVELS.size() - 1
	var cur_init : int = SoulFireManager.get_initial_soul_fire()
	var init_cost : int = SoulFireManager.get_initial_upgrade_cost()

	attr_container.add_child(_make_title("— 初始魂火 —"))
	attr_container.add_child(_make_info("Lv %d/%d  |  开局 %d 魂火" % [init_lv, init_max, cur_init]))
	
	if init_cost >= 0:
		var next_init : int = SoulFireManager.INITIAL_LEVELS[init_lv + 1]
		attr_container.add_child(_make_upgrade_row("升级初始 (下一级 %d)" % next_init, init_cost, func(): _on_upgrade_soul_fire_initial()))
	else:
		attr_container.add_child(_make_info("已达最高等级"))

func _on_upgrade_soul_fire_max():
	if SoulFireManager.upgrade_altar():
		_refresh_soul()
		_refresh_soul_fire_panel()
		_show_msg("魂火上限已提升")

func _on_upgrade_soul_fire_initial():
	if SoulFireManager.upgrade_initial():
		_refresh_soul()
		_refresh_soul_fire_panel()
		_show_msg("初始魂火已提升")

func _refresh_unit_unlock_panel():
	_clear_attr_container()
	var initial : Array = Globals.get_initial_candidates()
	var eligible : Array = Globals.get_eligible_units()

	var all_candidates : Array = []
	for k in initial:
		if k not in all_candidates: all_candidates.append(k)
	for k in eligible:
		if k not in all_candidates: all_candidates.append(k)

	var any_locked : bool = false
	for unit_type in all_candidates:
		if Globals.is_unit_unlocked(unit_type): continue
		if UnitDataManager.get_unit_data(unit_type).is_empty(): continue
		any_locked = true
		break

	if not any_locked:
		unit_sprite.visible = false
		unit_name_label.text = "所有残魂已唤醒"
		unit_desc_label.text = "守火者的火光照亮了每一个角落。"
		attr_container.add_child(_make_info("—— 无待唤醒的残魂 ——"))
		return

	if _current_unit_type == "" or Globals.is_unit_unlocked(_current_unit_type):
		for unit_type in all_candidates:
			if not Globals.is_unit_unlocked(unit_type):
				if UnitDataManager.get_unit_data(unit_type).is_empty(): continue
				_current_unit_type = unit_type
				break

	if _current_unit_type == "":
		return

	var display : String = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	var dict : Dictionary = UnitDataManager.get_unit_data(_current_unit_type)
	var cost : int = Globals.get_unit_unlock_cost(_current_unit_type)
	var can_afford : bool = GameState.soul >= cost

	unit_name_label.text = "%s   （未唤醒）" % display
	unit_desc_label.text = dict.get("description", "")
	unit_sprite.visible = false

	attr_container.add_child(_make_title("— 残魂信息 —"))
	attr_container.add_child(_make_info("HP：%d" % int(dict.get("max_hp", 0))))
	attr_container.add_child(_make_info("力 %d | 灵 %d | 智 %d | 信 %d" % [
		int(dict.get("strength", 0)), int(dict.get("dexterity", 0)), 
		int(dict.get("intelligence", 0)), int(dict.get("faith", 0))]))
	attr_container.add_child(_make_info("移动力：%d" % int(dict.get("move_range", 0))))

	attr_container.add_child(HSeparator.new())
	attr_container.add_child(_make_info("需要魂：%d   (当前: %d)" % [cost, GameState.soul]))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_make_info("唤醒此残魂？"))
	var btn := Button.new()
	btn.text = "唤醒"
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(50, 0)
	btn.disabled = not can_afford
	if can_afford:
		btn.pressed.connect(_on_unlock_unit_pressed)
	row.add_child(btn)
	attr_container.add_child(row)

func _on_upgrade_attr_cap():
	if _current_unit_type == "": return
	var cur_lv : int = int(GameState.unit_attr_cap.get(_current_unit_type, 0))
	if cur_lv >= ATTR_CAP_COSTS.size(): return
	
	var cost : int = ATTR_CAP_COSTS[cur_lv] if cur_lv < ATTR_CAP_COSTS.size() else -1
	if cost <= 0 or GameState.soul < cost: return

	GameState.soul -= cost
	GameState.unit_attr_cap[_current_unit_type] = cur_lv + 1
	SaveManager.auto_save()

	_refresh_soul()
	_build_unit_list()
	_refresh_attr_cap_panel()
	_show_msg("%s 已升至 Lv%d" % [UnitDataManager.get_unit_type_display_name(_current_unit_type), cur_lv + 1])

func _on_unlock_unit_pressed():
	if _current_unit_type == "": return
	var cost : int = Globals.get_unit_unlock_cost(_current_unit_type)
	if GameState.soul < cost: return
	if Globals.is_unit_unlocked(_current_unit_type): return

	GameState.soul -= cost
	Globals.unlock_unit(_current_unit_type)
	SaveManager.auto_save()

	_refresh_soul()
	_show_msg("★ %s 已唤醒！" % UnitDataManager.get_unit_type_display_name(_current_unit_type))

	_current_unit_type = ""
	_build_locked_unit_list()
	_refresh_unit_unlock_panel()

func _on_refine_relic(rid: String):
	if GameState.refine_relic(rid):
		_refresh_soul()
		_build_relic_refine_panel()
		_show_msg("★ %s 已精炼" % RelManagerName(rid))

func RelManagerName(rid): return RelicManager.get_relic_data(rid).get("name", rid)

func _make_title(text: String) -> Label:
	var lb = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lb.modulate = Color(0.7, 0.8, 1.0)
	return lb

func _make_info(text: String) -> Label:
	var lb = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return lb

func _make_upgrade_row(label_text: String, cost: int, cb: Callable) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lb = Label.new()
	lb.text = "%s (%d 魂)" % [label_text, cost]
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN 
	row.add_child(lb)

	var btn = Button.new()
	btn.text = "升级"
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(40, 16)
	btn.disabled = (GameState.soul < cost)
	btn.pressed.connect(cb)
	row.add_child(btn)
	return row

func _refresh_soul():
	if soul_label:
		soul_label.text = "魂: " + str(GameState.soul)

func _show_msg(msg: String):
	if not hint_label: return
	hint_label.visible = true
	hint_label.text = msg
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(hint_label):
		hint_label.visible = false
		hint_label.text = ""

func _attr_cn(key: String) -> String:
	match key:
		"vitality":     return "HP"
		"strength":     return "力量"
		"dexterity":    return "灵巧"
		"intelligence": return "智力"
		"faith":        return "信仰"
		"move_range":   return "移动"
		_: return key

func _format_bonus_dict(dict : Dictionary) -> String:
	var parts : Array = []
	var order : Array = ["strength", "dexterity", "intelligence", "faith", "vitality"]
	for k in order:
		if dict.has(k):
			parts.append("%s +%d" % [_attr_cn(k), int(dict[k])])
	return "  ".join(parts)

func _build_relic_refine_panel():
	_clear_attr_container()
	unit_sprite.visible = false
	unit_name_label.text = "遗物精炼"
	unit_desc_label.text = "每件遗物限精炼一次"
	attr_container.add_child(_make_info("当前魂：%d" % GameState.soul))
	attr_container.add_child(HSeparator.new())

	var unlocked : Array = RelicManager.get_unlocked_relics()
	if unlocked.is_empty():
		attr_container.add_child(_make_info("（暂无可精炼遗物）"))
		return

	var first_rid = ""
	var first_refined = false

	for rid in unlocked:
		var rd : Dictionary = RelicManager.get_relic_data(rid)
		if rd.is_empty(): continue
		
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var is_refined : bool = GameState.is_relic_refined(rid)
		if first_rid == "":
			first_rid = rid
			first_refined = is_refined
		
		var icon_wrap := Control.new()
		icon_wrap.custom_minimum_size = Vector2(20, 20)
		icon_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var icon_rect = TextureRect.new()
		if rd.get("icon") is Texture2D: icon_rect.texture = rd.get("icon")
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_wrap.add_child(icon_rect)
		
		icon_wrap.mouse_entered.connect(_on_relic_hover.bind(rid, is_refined))
		row.add_child(icon_wrap)
		
		var name_lb := Label.new()
		name_lb.text = ("★ " if is_refined else "") + rd.get("name", rid)
		name_lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_lb)
		
		if is_refined:
			var tag := Label.new()
			tag.text = "已精炼"
			tag.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
			tag.modulate = Color(0.7, 1.0, 0.7)
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tag)
		else:
			var btn := Button.new()
			btn.text = "精炼(%d)" % GameState.REFINE_COST
			btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
			btn.custom_minimum_size = Vector2(60, 16)
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.disabled = GameState.soul < GameState.REFINE_COST
			if not btn.disabled: btn.pressed.connect(_on_refine_relic.bind(rid))
			row.add_child(btn)
			
		attr_container.add_child(row)

	if first_rid != "":
		_on_relic_hover(first_rid, first_refined)

func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()
