extends Panel

enum Mode { DEPLOY, MAP, FORGE, ARENA_REST, MAP_SHOP_REST }

const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")

var current_mode: Mode = Mode.DEPLOY
var selected_units: Array = []
var target_slot: int = -1
var party: Array = []
var _is_building_ui: bool = false
var _build_ui_pending: bool = false
var _is_closing: bool = false
var _context : EquipContext = null

const MAX_PASSIVE_SLOTS : int = 4

var current_tab: String = "weapon"
var shop_manager = null

var _forge : EquipmentConfigForge = null
var _drag : EquipmentConfigDrag = null
var _detail : EquipmentConfigDetail = null
var _shop : EquipmentConfigShop = null
var _talent : EquipmentConfigTalent = null

var _upgrade_shop_btn : Button = null
var _aura_tab_btn : Button = null
var _auto_config_btn : Button = null

var _forge_enter_done : bool = false

const ShopManagerScript = preload(Config.PATHS.SHOP_MANAGER_SCRIPT)
const DETAIL_ZONE_PATH : String = "VBoxContainer/MainHBox/LeftInfoColumn/DetailZone"
const DIRECTION_REROLL_COST : int = 120

# ★★★ v5.0 连通组悬停高亮：槽位原始样式备份 ★★★
var _armor_btn_default_style : Dictionary = {}

@onready var mode_label = get_node_or_null("VBoxContainer/TopBar/ModeLabel")
@onready var gold_label = get_node_or_null("VBoxContainer/GoldLabel")
@onready var close_btn = get_node_or_null("VBoxContainer/BottomHBox/CloseBtn")
@onready var confirm_btn = get_node_or_null("VBoxContainer/BottomHBox/ConfirmBtn")
@onready var unit_container = get_node_or_null("VBoxContainer/MainHBox/LeftVBox/UnitContainer")

var shop_container: Control = null
var shop_scroll: ScrollContainer = null

@onready var right_container = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer")
@onready var reset_btn = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ResetBtn")
@onready var discard_zone = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/DiscardZone")
@onready var tab_bar = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar")
@onready var weapon_tab_btn = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar/WeaponTabBtn")
@onready var talent_tab_btn = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar/TalentTabBtn")
@onready var relic_section: VBoxContainer = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/RelicSection")
@onready var relic_container: HBoxContainer = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/RelicSection/RelicContainer")
@onready var sacrifice_tab_btn : Button = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar/SacrificeTabBtn")
@onready var furnace_tab_btn : Button = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar/FurnaceTabBtn")

var _pending_section : VBoxContainer = null
var _pending_container : GridContainer = null

var _connectivity_groups : Array = []
var _connected_cells : Dictionary = {}
var _shop_direction_cache : Dictionary = {}


func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var custom_theme := Theme.new()
	custom_theme.set_font_size("font_size", "TooltipLabel", 6)
	custom_theme.set_font_size("font_size", "TooltipPanel", 6)
	
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	tip_sb.content_margin_left = 4
	tip_sb.content_margin_right = 4
	tip_sb.content_margin_top = 2
	tip_sb.content_margin_bottom = 2
	custom_theme.set_stylebox("panel", "TooltipPanel", tip_sb)
	theme = custom_theme
	
	shop_container = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ShopScroll/ShopContainer")
	shop_scroll = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ShopScroll")
	
	if shop_container is GridContainer:
		var old_sc = shop_container
		var new_flow = HFlowContainer.new()
		new_flow.name = old_sc.name
		new_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		new_flow.add_theme_constant_override("h_separation", 4)
		new_flow.add_theme_constant_override("v_separation", 4)
		new_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		old_sc.get_parent().add_child(new_flow)
		old_sc.get_parent().remove_child(old_sc)
		old_sc.queue_free()
		shop_container = new_flow
	
	_forge = EquipmentConfigForge.new(self)
	_drag = EquipmentConfigDrag.new(self)
	_detail = EquipmentConfigDetail.new(self)
	_shop = EquipmentConfigShop.new(self)
	_talent = EquipmentConfigTalent.new(self)
	if weapon_tab_btn:
		weapon_tab_btn.pressed.connect(_on_weapon_tab_pressed)
	if talent_tab_btn:
		talent_tab_btn.pressed.connect(_on_talent_tab_pressed)
	if sacrifice_tab_btn:
		sacrifice_tab_btn.visible = false
	_ensure_aura_tab_btn()

	var detail_label : Label = get_node_or_null(DETAIL_ZONE_PATH + "/DetailLabel")
	if detail_label:
		detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_connectivity_groups.clear()
	_connected_cells.clear()
	_armor_btn_default_style.clear()


func _ensure_aura_tab_btn():
	pass


func _on_aura_tab_pressed():
	_switch_tab("aura")


func is_forge_mode() -> bool:
	return current_mode == Mode.FORGE

func is_shop_rest_mode() -> bool:
	return current_mode == Mode.ARENA_REST or current_mode == Mode.MAP_SHOP_REST

func _is_shop_rest_mode() -> bool:
	return is_shop_rest_mode()


func _on_weapon_tab_pressed():
	if is_shop_rest_mode(): _switch_tab("arena_shop")
	elif current_mode == Mode.FORGE: _switch_tab("arena_shop")
	else: _switch_tab("weapon")


func _on_talent_tab_pressed():
	if is_shop_rest_mode(): _switch_tab("arena_forge")
	elif current_mode == Mode.FORGE: _switch_tab("arena_forge")
	else: _switch_tab("talent")


func _on_sacrifice_tab_pressed(): _switch_tab("sacrifice")


func init(units: Array, slot: int, mode: int, context: EquipContext = null):
	var canvas_layer : Node = get_parent()
	if canvas_layer is CanvasLayer:
		if context != null and context.get_context_id() == "arena":
			(canvas_layer as CanvasLayer).layer = 30
		else:
			(canvas_layer as CanvasLayer).layer = 20

	selected_units = units
	target_slot = slot
	current_mode = mode as Mode
	_context = context if context else MainGameEquipContext.new()

	if current_mode == Mode.FORGE or is_shop_rest_mode():
		GameState.refresh_aura_candidates()

	if is_shop_rest_mode() or mode == Mode.FORGE:
		if not shop_manager:
			shop_manager = ShopManagerScript.new()
			add_child(shop_manager)
			shop_manager.shop_updated.connect(_on_shop_updated)
		shop_manager.set_context(_context)
		shop_manager.generate_shop_items()
		shop_manager.reset_count = 0

	if mode == Mode.FORGE or is_shop_rest_mode():
		_forge.init_slots()

	if is_shop_rest_mode():
		current_tab = "arena_shop"

	if current_mode == Mode.FORGE or current_mode == Mode.MAP_SHOP_REST:
		_forge_enter_done = false
	else:
		_forge_enter_done = true

	_copy_party_data()
	_build_ui()

	if current_mode == Mode.FORGE:
		AnalyticsLogger.begin_forge_session()


func _on_shop_updated():
	_update_gold_display()
	var is_shop_view : bool = (
		current_tab == "arena_shop" and (
			current_mode == Mode.ARENA_REST
			or current_mode == Mode.MAP_SHOP_REST
			or current_mode == Mode.FORGE
		)
	)
	if is_shop_view and shop_container and shop_container.visible:
		_build_shop_items()
	else:
		_schedule_build_ui()


# ============================================================
#  v5.0：只强制检查熔铸奖励（pending_sacrifice_rewards）
#  合成产物 + 阵亡回收的防具（pending_forge_rewards）允许带着离开，
#  玩家可在下次进入 FORGE / MAP_SHOP_REST 时再处理。
# ============================================================
func _on_close_pressed():
	if GameState.has_pending_sacrifice_rewards():
		var total : int = GameState.pending_sacrifice_rewards.size()
		Globals.show_confirm(
			self,
			"还有 %d 件熔铸奖励待领取。\n请先把它们装备到单位防具槽后再离开。" % total,
			"好的", "",
			func(): pass,
			func(): pass,
			false
		)
		return
	_do_close_normal()


func _do_close_with_discard():
	GameState.clear_all_pending_rewards()
	_do_close_normal()


func _do_close_normal():
	if is_shop_rest_mode() and current_tab == "arena_forge":
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return
		if current_mode == Mode.ARENA_REST:
			_switch_tab("arena_shop")
			return

	if current_mode == Mode.FORGE and _forge.has_pending():
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			Globals.show_confirm(self, "有 %d 件防具无法归还，请先腾出空间" % unresolved,
				"确定", "", func(): pass, func(): pass, false)
			return

	_sync_all()
	_context.mark_cancelled()
	_is_closing = true
	if current_mode == Mode.FORGE:
		AnalyticsLogger.finish_forge_session()
	if shop_manager:
		if shop_manager.shop_updated.is_connected(_on_shop_updated):
			shop_manager.shop_updated.disconnect(_on_shop_updated)
		shop_manager.queue_free()
		shop_manager = null
	_context.on_close()
	var canvas_layer : Node = get_parent()
	if canvas_layer: canvas_layer.queue_free()
	else: queue_free()


# ============================================================
#  v5.0：只检查 pending_sacrifice_rewards
# ============================================================
func _check_pending_before_leave() -> bool:
	if GameState.has_pending_sacrifice_rewards():
		_show_detail_in_zone("请先领取熔铸奖励（%d 件）" % GameState.pending_sacrifice_rewards.size())
		return false
	return true


func _build_ui():
	if _is_closing: return
	if _is_building_ui: return
	_is_building_ui = true
	_build_ui_inner()
	_is_building_ui = false
	if current_mode == Mode.FORGE or current_mode == Mode.MAP_SHOP_REST:
		_setup_forge_narrative_ui()


func _build_ui_inner():
	var vbox = $VBoxContainer
	if vbox:
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = 2
		vbox.offset_top = 2
		vbox.offset_right = -2
		vbox.offset_bottom = -2
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 2)

	var top_bar = get_node_or_null("VBoxContainer/TopBar")
	if top_bar:
		top_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top_bar.custom_minimum_size = Vector2(0, 16)

	var gold_lbl = get_node_or_null("VBoxContainer/GoldLabel")
	if gold_lbl:
		gold_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		gold_lbl.custom_minimum_size = Vector2(0, 12)

	var main_hbox = get_node_or_null("VBoxContainer/MainHBox")
	if main_hbox:
		main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.clip_contents = true

	var bottom_hbox = get_node_or_null("VBoxContainer/BottomHBox")
	if bottom_hbox:
		bottom_hbox.size_flags_vertical = Control.SIZE_SHRINK_END
		bottom_hbox.custom_minimum_size = Vector2(0, 20)
		bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var left_info = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn")
	if left_info:
		left_info.custom_minimum_size = Vector2(80, 0) 
		left_info.size_flags_horizontal = Control.SIZE_FILL 
		left_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_info.clip_contents = true

	var detail_zone = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/DetailZone")
	if detail_zone:
		detail_zone.custom_minimum_size = Vector2(80, 150) 
		detail_zone.size_flags_horizontal = Control.SIZE_FILL
		detail_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL 
		detail_zone.clip_contents = true

	var item_info = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/ItemInfoPanel")
	if item_info:
		item_info.custom_minimum_size = Vector2.ZERO 
		item_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_info.clip_contents = true
		var scroll = item_info.get_node_or_null("VBox/Scroll")
		if scroll:
			scroll.custom_minimum_size = Vector2.ZERO
			scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		
		for label_path in ["VBox/NameLabel", "VBox/TypeLabel", "VBox/Scroll/ContentVBox/DescLabel", "VBox/Scroll/ContentVBox/StatsLabel"]:
			var lb = item_info.get_node_or_null(label_path)
			if lb:
				lb.custom_minimum_size = Vector2(0, 0)
				lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lb.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY

	var left_vbox = get_node_or_null("VBoxContainer/MainHBox/LeftVBox")
	if left_vbox:
		left_vbox.custom_minimum_size = Vector2(0, 0)
		left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL 
		left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_vbox.clip_contents = true

	var r_scroll = get_node_or_null("VBoxContainer/MainHBox/RightScroll")
	if r_scroll and r_scroll is ScrollContainer:
		r_scroll.custom_minimum_size = Vector2(110, 0) 
		r_scroll.size_flags_horizontal = Control.SIZE_FILL
		r_scroll.size_flags_vertical = Control.SIZE_FILL
		r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		r_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		r_scroll.clip_contents = true 

	var r_container = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer")
	if r_container:
		r_container.custom_minimum_size = Vector2(0, 0)
		r_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_container.clip_contents = true

	var inner_shop_scroll = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ShopScroll")
	if inner_shop_scroll and inner_shop_scroll is ScrollContainer:
		inner_shop_scroll.custom_minimum_size = Vector2(0, 0)
		inner_shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner_shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inner_shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		inner_shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		inner_shop_scroll.clip_contents = true

	var t_bar = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar")
	if t_bar:
		t_bar.custom_minimum_size = Vector2(0, 16)
		t_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_bar.clip_contents = true
		for child in t_bar.get_children():
			if child is Button:
				child.clip_text = true
				child.custom_minimum_size = Vector2(0, 16) 
				child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				child.add_theme_font_size_override("font_size", 7)

	var d_zone = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/DiscardZone")
	if d_zone:
		d_zone.custom_minimum_size = Vector2(0, 20) 
		var lbl = d_zone.get_node_or_null("DiscardLabel")
		if lbl:
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var show_passive : bool = (_context.get_context_id() != "arena")
	if relic_section: relic_section.visible = show_passive
	if relic_container: 
		relic_container.visible = show_passive
		relic_container.add_theme_constant_override("separation", 2) 
	if show_passive:
		_build_passive_slots()

	var show_pending : bool = false
	if current_mode == Mode.FORGE or current_mode == Mode.MAP_SHOP_REST:
		if current_tab != "arena_shop" and current_tab != "weapon":
			show_pending = true
			
	if show_pending:
		_ensure_pending_section()
		_build_pending_slots()
		if _pending_section:
			_pending_section.visible = true
	else:
		if _pending_section and is_instance_valid(_pending_section):
			var p = _pending_section.get_parent()
			if p: p.remove_child(_pending_section)
			_pending_section.queue_free()
			_pending_section = null
			_pending_container = null

	if not mode_label: return

	_update_gold_display()

	shop_container.visible = false
	tab_bar.visible = false
	right_container.visible = true

	weapon_tab_btn.visible = false
	talent_tab_btn.visible = false
	if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
	if furnace_tab_btn: furnace_tab_btn.visible = false
	if _aura_tab_btn: _aura_tab_btn.visible = false

	match current_mode:
		Mode.DEPLOY:
			mode_label.text = "装备配置 - 战前准备" if _context.get_title() == "" else _context.get_title()
			close_btn.visible = true
			close_btn.text = "返回"
			confirm_btn.visible = true
			confirm_btn.text = "开始探索"
			confirm_btn.disabled = false
			confirm_btn.modulate = Color.WHITE
			gold_label.visible = _context.show_gold()
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = false
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "特技库"
			if current_tab == "weapon" or current_tab == "":
				current_tab = "talent"
			_update_tab_style()
			_build_talent_grid(shop_container)
			shop_container.visible = true

		Mode.MAP:
			mode_label.text = "装备配置"
			close_btn.visible = true
			close_btn.text = "返回"
			confirm_btn.visible = false
			gold_label.visible = false
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = false
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "特技库"
			current_tab = "talent"
			_update_tab_style()
			_build_talent_grid(shop_container)
			shop_container.visible = true

		Mode.ARENA_REST:
			mode_label.text = "魂之竞技场 · 备战"
			gold_label.visible = true
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = true
			weapon_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			weapon_tab_btn.text = "商店"
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "铁匠铺"
			if current_tab == "" or (not current_tab.begins_with("arena_") and current_tab != "sacrifice" and current_tab != "aura"):
				current_tab = "arena_shop"
			_update_tab_style()
			_forge.cleanup()

			close_btn.visible = false
			confirm_btn.visible = true
			confirm_btn.text = "出发"

			if current_tab == "arena_forge":
				confirm_btn.disabled = true
				confirm_btn.modulate = Color(0.5, 0.5, 0.5)
				_forge.build_forge_slots()
				shop_container.visible = true
			else:
				confirm_btn.disabled = false
				confirm_btn.modulate = Color.WHITE
				_build_shop_items()
				shop_container.visible = true

		Mode.MAP_SHOP_REST:
			mode_label.text = "魂栈 · 魂栈侍从"
			close_btn.visible = true
			close_btn.text = "继续探索"
			confirm_btn.visible = false
			gold_label.visible = true
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = true
			weapon_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			weapon_tab_btn.text = "商店"
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "铁匠铺"
			if sacrifice_tab_btn:
				sacrifice_tab_btn.visible = true
				sacrifice_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if _aura_tab_btn:
				_aura_tab_btn.visible = true
				_aura_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			if current_tab == "" or (not current_tab.begins_with("arena_") and current_tab != "sacrifice" and current_tab != "aura"):
				current_tab = "arena_shop"
			_update_tab_style()
			_forge.cleanup()

			match current_tab:
				"arena_forge":
					_forge.build_forge_slots()
					shop_container.visible = true
				"sacrifice":
					_build_sacrifice_panel()
					shop_container.visible = true
				"aura":
					_build_aura_panel()
					shop_container.visible = true
				_:
					_build_shop_items()
					shop_container.visible = true

		Mode.FORGE:
			mode_label.text = "魂栈"
			close_btn.visible = true
			close_btn.text = "继续探索"
			confirm_btn.visible = false
			gold_label.visible = true
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = true
			weapon_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			weapon_tab_btn.text = "商店"
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.text = "铁匠铺"
			if sacrifice_tab_btn:
				sacrifice_tab_btn.visible = true
				sacrifice_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if _aura_tab_btn:
				_aura_tab_btn.visible = true
				_aura_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			if current_tab == "" or (not current_tab in ["arena_shop", "arena_forge", "sacrifice", "aura"]):
				current_tab = "arena_shop"

			_update_tab_style()
			_forge.cleanup()

			match current_tab:
				"arena_shop":
					_build_shop_items()
					shop_container.visible = true
				"arena_forge":
					_forge.build_forge_slots()
					shop_container.visible = true
				"sacrifice":
					_build_sacrifice_panel()
					shop_container.visible = true
				"aura":
					_build_aura_panel()
					shop_container.visible = true

	reset_btn.visible = (current_tab == "arena_shop")
	if reset_btn.visible and shop_manager:
		reset_btn.text = "刷新 (" + str(shop_manager.get_reset_cost()) + "G)"
		
	discard_zone.visible = (current_tab != "arena_forge" and current_tab != "sacrifice" and current_tab != "aura" and current_mode != Mode.DEPLOY)

	if current_mode == Mode.FORGE or is_shop_rest_mode():
		_setup_forge_narrative_ui()

	close_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	confirm_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	
	if reset_btn:
		reset_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
		reset_btn.custom_minimum_size = Vector2(0, 16) 
		reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
		reset_btn.size_flags_vertical = Control.SIZE_SHRINK_END 
		reset_btn.clip_text = true 

	_ensure_upgrade_shop_btn()
	_refresh_upgrade_shop_btn()

	_ensure_auto_config_btn()
	_refresh_connectivity()

	_build_unit_columns()
	visible = true

	if shop_container: shop_container.queue_sort()
	if right_container: right_container.queue_sort()
	if tab_bar: tab_bar.queue_sort()


func _ensure_auto_config_btn():
	if _auto_config_btn and is_instance_valid(_auto_config_btn):
		return
		
	_auto_config_btn = Button.new()
	_auto_config_btn.name = "AutoConfigBtn"
	_auto_config_btn.text = "自动配装"
	_auto_config_btn.add_theme_font_size_override("font_size", 5) # 极小字号
	_auto_config_btn.focus_mode = Control.FOCUS_NONE
	_auto_config_btn.custom_minimum_size = Vector2(40, 14)
	_auto_config_btn.tooltip_text = "根据连通组 + 套装 + 属性，生成 3 个自动配置方案"
	_auto_config_btn.pressed.connect(_open_auto_config_dialog)
	
	add_child(_auto_config_btn)
	_auto_config_btn.z_index = 100 # 顶层防遮挡
	
	_auto_config_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# 强行贴到最右下角的像素位置
	_auto_config_btn.offset_left = -44.0
	_auto_config_btn.offset_top = -18.0
	_auto_config_btn.offset_right = -4.0
	_auto_config_btn.offset_bottom = -4.0


func _refresh_connectivity(silent: bool = false):
	_connectivity_groups.clear()
	_connected_cells.clear()

	if party.is_empty():
		return

	var slots : Array = []
	for i in range(party.size()):
		slots.append(party[i].armor_slots)

	_connectivity_groups = ConnectedGroupCalculator.compute_groups(slots)

	var max_size = 0
	for gi in range(_connectivity_groups.size()):
		var g = _connectivity_groups[gi]
		if g.size() > max_size:
			max_size = g.size()
		for c in g.cells:
			_connected_cells["%d_%d" % [c.unit_index, c.row]] = gi

	if max_size >= 5 and not silent:
		_show_detail_in_zone("★ 形成超级连通网！(%d 件防具连通)" % max_size)


func _get_connectivity_style(unit_idx: int, slot_idx: int) -> StyleBox:
	var key : String = "%d_%d" % [unit_idx, slot_idx]
	if not _connected_cells.has(key):
		return null
		
	var gi = _connected_cells[key]
	var g = _connectivity_groups[gi]
	var group_size = g.size()
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	
	if group_size >= 5:
		sb.border_color = Color(1.0, 0.8, 0.1) 
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
	else:
		sb.border_color = Color(0.9, 0.75, 0.3) 
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


func _build_unit_columns():
	if not unit_container: return
	_refresh_connectivity(true)
	unit_container.alignment = BoxContainer.ALIGNMENT_CENTER
	for child in unit_container.get_children():
		unit_container.remove_child(child); child.free()

	for i in range(party.size()):
		unit_container.add_child(_create_unit_column(i))

	_backup_all_armor_styles()


func _backup_all_armor_styles():
	_armor_btn_default_style.clear()
	if not unit_container: return
	for child in unit_container.get_children():
		_recursive_backup_armor_styles(child)

func _recursive_backup_armor_styles(node: Node):
	if node is Button:
		var b : Button = node
		if b.get_meta("slot_type", "") == "armor":
			var u = int(b.get_meta("unit_idx", -1))
			var s = int(b.get_meta("slot_idx", -1))
			if u >= 0 and s >= 0:
				var key = "%d_%d" % [u, s]
				_armor_btn_default_style[key] = {
					"normal": b.get_theme_stylebox("normal"),
					"hover": b.get_theme_stylebox("hover"),
				}
	for c in node.get_children():
		_recursive_backup_armor_styles(c)

func _on_armor_hover_entered(item_id: String, unit_idx: int, slot_idx: int):
	var key : String = "%d_%d" % [unit_idx, slot_idx]
	var group_size : int = 0
	var unit_count : int = 0
	if _connected_cells.has(key):
		var gi : int = _connected_cells[key]
		if gi >= 0 and gi < _connectivity_groups.size():
			var g = _connectivity_groups[gi]
			group_size = g.size()
			unit_count = g.unit_count()
			_apply_group_highlight(gi)
		else:
			_restore_all_armor_styles()
	else:
		_restore_all_armor_styles()
	_detail.on_button_hover_entered_with_link(item_id, group_size, unit_count)

func _on_armor_hover_exited():
	_detail.on_button_hover_exited()
	_restore_all_armor_styles()

func _apply_group_highlight(group_idx: int):
	_restore_all_armor_styles()
	if group_idx < 0 or group_idx >= _connectivity_groups.size():
		return
	var g = _connectivity_groups[group_idx]
	var hl := StyleBoxFlat.new()
	hl.bg_color = Color(1.0, 0.9, 0.3, 0.25)
	hl.border_color = Color(1.0, 0.9, 0.3)
	hl.set_border_width_all(2)
	hl.corner_radius_top_left = 2
	hl.corner_radius_top_right = 2
	hl.corner_radius_bottom_left = 2
	hl.corner_radius_bottom_right = 2
	hl.content_margin_left = 0
	hl.content_margin_right = 0
	hl.content_margin_top = 0
	hl.content_margin_bottom = 0
	for cell in g.cells:
		var btn = _find_armor_button_at(cell.unit_index, cell.row)
		if btn:
			btn.add_theme_stylebox_override("normal", hl)
			btn.add_theme_stylebox_override("hover", hl)

func _restore_all_armor_styles():
	for key in _armor_btn_default_style:
		var parts : PackedStringArray = String(key).split("_", false)
		if parts.size() != 2: continue
		var u : int = int(parts[0])
		var s : int = int(parts[1])
		var btn = _find_armor_button_at(u, s)
		if btn == null: continue
		var st : Dictionary = _armor_btn_default_style[key]
		var normal_sb = st.get("normal", null)
		var hover_sb = st.get("hover", null)
		if normal_sb != null:
			btn.add_theme_stylebox_override("normal", normal_sb)
		if hover_sb != null:
			btn.add_theme_stylebox_override("hover", hover_sb)

func _find_armor_button_at(unit_idx: int, slot_idx: int) -> Button:
	if not unit_container: return null
	for child in unit_container.get_children():
		var found = _recursive_find_armor(child, unit_idx, slot_idx)
		if found: return found
	return null

func _recursive_find_armor(node: Node, unit_idx: int, slot_idx: int) -> Button:
	if node is Button:
		var b : Button = node
		if b.get_meta("slot_type", "") == "armor" \
				and int(b.get_meta("unit_idx", -1)) == unit_idx \
				and int(b.get_meta("slot_idx", -1)) == slot_idx:
			return b
	for c in node.get_children():
		var found = _recursive_find_armor(c, unit_idx, slot_idx)
		if found: return found
	return null


func _create_unit_column(unit_idx: int, is_preview: bool = false) -> Control:
	var wrapper: PanelContainer = PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if is_preview:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.1, 0.15, 0.9)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.6, 0.6, 0.8)
		wrapper.add_theme_stylebox_override("panel", sb)
	else:
		wrapper.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	wrapper.add_child(col)

	var unit = party[unit_idx]

	var icon_ctrl = _create_unit_icon(unit, unit_idx)
	if unit.is_dead: icon_ctrl.modulate = Color(0.4, 0.4, 0.4, 1)
	col.add_child(icon_ctrl)

	if _is_level_up_enabled():
		var level_btn = _create_level_btn(unit, unit_idx)
		if unit.is_dead: _disable_button(level_btn)
		col.add_child(level_btn)

	var armor_group := VBoxContainer.new()
	armor_group.add_theme_constant_override("separation", 2)
	armor_group.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(armor_group)
	
	for slot_idx in range(unit.armor_slots.size()):
		var armor_btn = _create_item_button(unit.armor_slots[slot_idx], "armor", unit_idx, slot_idx)
		if unit.is_dead: _disable_button(armor_btn)
		var conn_style = _get_connectivity_style(unit_idx, slot_idx)
		if conn_style != null:
			armor_btn.add_theme_stylebox_override("normal", conn_style)
			armor_btn.add_theme_stylebox_override("hover", conn_style)
		armor_group.add_child(armor_btn)

	var talent_inst = unit.talent_slots[0] if unit.talent_slots.size() > 0 else null
	var talent_btn = _create_talent_button(talent_inst, unit_idx, 0)
	if unit.is_dead: _disable_button(talent_btn)
	col.add_child(talent_btn)

	var adv_btn = _create_advanced_talent_button(unit, unit_idx)
	if unit.is_dead: _disable_button(adv_btn)
	col.add_child(adv_btn)

	if is_preview:
		_disable_all_input_recursive(wrapper)
		wrapper.modulate = Color(1, 1, 1, 0.9)

	return wrapper

func _disable_all_input_recursive(node: Node):
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if node is Button:
			node.disabled = true
	for child in node.get_children():
		_disable_all_input_recursive(child)


func _is_level_up_enabled() -> bool:
	return current_mode in [Mode.FORGE, Mode.MAP_SHOP_REST, Mode.ARENA_REST]


func _get_level_up_cost(cur_level: int) -> int:
	var cfg : Dictionary = GameConfigManager.get_file("economy_config.json")
	var costs : Array = cfg.get("unit_level_up_cost", [50, 100, 200, 400, 800])
	var idx : int = cur_level - 1
	if idx < 0 or idx >= costs.size():
		return 999999
	return int(costs[idx])	


func _create_level_btn(unit: UnitData, unit_idx: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Vector2(52, 24))
	btn.set_meta("slot_type", "level_btn")
	btn.set_meta("unit_idx", unit_idx)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	sb.border_color = Color(0.3, 0.3, 0.3)
	sb.border_width_bottom = 1
	sb.border_width_top = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)

	var cap : int = int(GameState.unit_level_cap.get(unit.unit_name, 3))
	var cur : int = int(unit.level)

	if cur >= 6 or cur >= cap:
		btn.text = "L%d\n满级" % cur
		btn.disabled = true
		btn.modulate = Color(0.5, 0.5, 0.5)
		return btn

	var cost : int = _get_level_up_cost(cur)
	var has_gold : bool = _context.get_gold() >= cost
	
	btn.text = "L%d\n%dG" % [cur, cost]
	btn.tooltip_text = ""
	btn.disabled = not has_gold
	btn.modulate = Color.WHITE if has_gold else Color(0.6, 0.5, 0.5)
	
	if has_gold:
		btn.pressed.connect(_on_level_up_pressed.bind(unit_idx))
	return btn


func _on_level_up_pressed(unit_idx: int):
	if unit_idx < 0 or unit_idx >= party.size(): return
	var u : UnitData = party[unit_idx]
	if u.is_dead: return

	var cap : int = int(GameState.unit_level_cap.get(u.unit_name, 3))
	if u.level >= cap: return
	if u.level >= 6: return

	var cost : int = _get_level_up_cost(u.level)
	if not _context.subtract_gold(cost): return

	u.apply_level_up()
	SoundManager.play_get_item_sound()
	_update_gold_display()
	_sync_all()
	
	call_deferred("_build_unit_columns")
	_schedule_build_ui()


func _update_gold_display():
	if gold_label:
		var soul_fire_str: String = ""
		if SoulFireManager:
			soul_fire_str = "    |    魂火: %d/%d" % [SoulFireManager.current, SoulFireManager.get_max_carried()]
		gold_label.text = "金币: " + str(_context.get_gold()) + soul_fire_str


func _build_aura_panel():
	_clear_container(shop_container)
	shop_container.add_theme_constant_override("h_separation", 2)
	shop_container.add_theme_constant_override("v_separation", 2)
	shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN 
	shop_container.visible = true

	if shop_scroll:
		shop_scroll.custom_minimum_size = Vector2(0, 0)
		shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		shop_scroll.scroll_vertical = 0
		shop_scroll.scroll_horizontal = 0

	if _context.get_context_id() == "arena":
		var hint0 := Label.new()
		hint0.text = "竞技场不支持光环\n（光环为局内被动，仅主游戏可用）"
		hint0.add_theme_font_size_override("font_size", 7)
		hint0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint0.modulate = Color(0.7, 0.7, 0.7)
		hint0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		shop_container.add_child(hint0)
		return

	var unlocked : Array = GameState.unlocked_auras.duplicate()
	var equipped : Array = GameState.get_auras_from_passives()
	var candidates : Array = GameState.current_aura_candidates.duplicate()
	var cur_sf : int = SoulFireManager.current
	var empty_slot : int = _get_first_empty_passive_slot()

	if unlocked.is_empty():
		var hint0 := Label.new()
		hint0.text = "暂无解锁光环\n（在灰烬铁匠处研究以解锁）"
		hint0.add_theme_font_size_override("font_size", 7)
		hint0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint0.modulate = Color(0.6, 0.6, 0.6)
		hint0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		shop_container.add_child(hint0)
		return

	for aid in equipped:
		var btn := _make_aura_icon_btn(aid, cur_sf, true, empty_slot)
		shop_container.add_child(btn)

	for aid in candidates:
		var btn := _make_aura_icon_btn(aid, cur_sf, false, empty_slot)
		shop_container.add_child(btn)

	if empty_slot < 0 and not candidates.is_empty():
		var warn := Label.new()
		warn.text = "被动槽已满\n需先卸下光环"
		warn.add_theme_font_size_override("font_size", 6)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.modulate = Color(1.0, 0.6, 0.6)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(40, 0)
		shop_container.add_child(warn)


func _make_aura_icon_btn(aid: String, cur_sf: int, is_equipped: bool, _empty_slot: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_SHOP_SIZE)
	btn.expand_icon = true
	btn.clip_text = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)
	
	var ad : Dictionary = AuraManager.get_aura(aid)
	var icon = ad.get("icon")
	if icon is Texture2D:
		btn.icon = icon
		btn.text = ""
	else:
		btn.text = ad.get("name", aid).substr(0, 2)

	var buy_cost : int = int(ad.get("buy_cost", 0))
	if buy_cost <= 0: buy_cost = 6

	var label = Label.new()
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_bottom = 1
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if is_equipped:
		label.text = "已装"
		label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
		btn.set_meta("slot_type", "aura_equipped")
		btn.set_meta("aura_id", aid)
	else:
		label.text = "%d魂" % buy_cost
		label.add_theme_color_override("font_color", Color.WHITE)
		if cur_sf < buy_cost:
			btn.modulate = Color(0.5, 0.5, 0.5)
			btn.disabled = true
		else:
			btn.set_meta("slot_type", "aura_shop")
			btn.set_meta("aura_id", aid)
			btn.set_meta("aura_price", buy_cost)

	btn.add_child(label)
	
	btn.mouse_entered.connect(_on_aura_hover_entered.bind(aid))
	btn.mouse_exited.connect(_on_aura_hover_exited)
	
	return btn


func _get_first_empty_passive_slot() -> int:
	var passives : Array = _context.get_passives()
	for i in range(passives.size()):
		if passives[i] == null: return i
	return -1


func _on_buy_aura(aid: String, cost: int):
	if not SoulFireManager.spend(cost):
		return
	if not _context.add_aura_to_passive_slot(aid):
		SoulFireManager.add(cost)
		_show_detail_in_zone("被动槽已满")
		return
	GameState.remove_aura_candidate(aid)
	SoundManager.play_select_sound()
	_sync_all()
	_update_gold_display()
	_schedule_build_ui()
	_show_detail_in_zone("已购买光环：%s" % AuraManager.get_display_name(aid))


func _on_unequip_aura(aid: String):
	var passives : Array = _context.get_passives()
	var found_idx : int = -1
	for i in range(passives.size()):
		var p : Variant = passives[i]
		if p is Dictionary and p.get("type", "") == "aura" and p.get("aura_id", "") == aid:
			found_idx = i
			break
	if found_idx < 0:
		return
	_context.remove_passive_at_slot(found_idx)
	SoundManager.play_cancel_sound()
	_sync_all()
	_schedule_build_ui()
	_show_detail_in_zone("已卸下光环：%s\n（不返还魂火，下次进 FORGE 时可能重新抽到）" % AuraManager.get_display_name(aid))


func _ensure_pending_section():
	if _pending_container and is_instance_valid(_pending_container):
		return
	if not right_container: return

	_pending_section = VBoxContainer.new()
	_pending_section.name = "PendingSection"
	_pending_section.add_theme_constant_override("separation", 2)
	_pending_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_section.clip_contents = true
	
	if shop_scroll:
		var sc_idx : int = shop_scroll.get_index()
		right_container.add_child(_pending_section)
		right_container.move_child(_pending_section, sc_idx + 1)
	else:
		right_container.add_child(_pending_section)

	var btn_claim := Style.create_styled_button(Style.FONT_SMALL, Vector2(0, 16))
	btn_claim.name = "PendingTitleBtn"
	btn_claim.text = "一键领取 (0)"
	btn_claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_claim.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	btn_claim.pressed.connect(_on_claim_all_pending)
	_pending_section.add_child(btn_claim)

	var center_wrap := CenterContainer.new()
	center_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_section.add_child(center_wrap)

	_pending_container = GridContainer.new()
	_pending_container.name = "PendingContainer"
	_pending_container.columns = 3
	_pending_container.add_theme_constant_override("h_separation", 4)
	_pending_container.add_theme_constant_override("v_separation", 4)
	_pending_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_wrap.add_child(_pending_container)


func _build_pending_slots():
	if not _pending_container or not is_instance_valid(_pending_container): 
		return
		
	for child in _pending_container.get_children():
		_pending_container.remove_child(child)
		child.free()

	var all_pending : Array = []
	for i in range(GameState.pending_sacrifice_rewards.size()):
		all_pending.append({"inst": GameState.pending_sacrifice_rewards[i], "idx": i, "src": "sacrifice"})
	for i in range(GameState.pending_forge_rewards.size()):
		all_pending.append({"inst": GameState.pending_forge_rewards[i], "idx": i, "src": "forge"})

	var title_btn = _pending_section.get_node_or_null("PendingTitleBtn")
	if title_btn:
		title_btn.text = "一键领取 (%d)" % all_pending.size()
		title_btn.disabled = all_pending.is_empty()

	var MAX_SLOTS : int = 6
	for i in range(MAX_SLOTS):
		if i < all_pending.size():
			var entry = all_pending[i]
			var btn := _create_pending_button(entry["inst"], entry["idx"], entry["src"])
			_pending_container.add_child(btn)
		else:
			var empty_btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
			empty_btn.custom_minimum_size = Style.BTN_ITEM_SIZE
			empty_btn.disabled = true
			empty_btn.modulate = Color(1, 1, 1, 0) 
			_pending_container.add_child(empty_btn)


func _create_pending_button(inst: ItemInstance, idx: int, src: String) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.expand_icon = true
	btn.custom_minimum_size = Style.BTN_ITEM_SIZE
	btn.set_meta("slot_type", "pending_reward")
	btn.set_meta("pending_idx", idx)
	btn.set_meta("pending_src", src)
	btn.clip_text = true
	btn.clip_contents = false

	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)

	if inst:
		var data : ItemData = ItemManager.get_item_data(inst.item_id)
		if data and data.icon:
			btn.icon = data.icon
			btn.text = ""
		else:
			btn.text = data.name if data else inst.item_id
			
		btn.set_meta("item_id", inst.item_id)
		btn.modulate = Color.WHITE 
		
		if inst.direction != Direction.Value.NONE:
			_draw_direction_badges(btn, inst.direction)
			
		var item_id : String = inst.item_id
		btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_button_hover_exited)
	return btn


func _build_sacrifice_panel():
	_clear_container(shop_container)
	shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if GameState.has_pending_sacrifice_rewards():
		var hint := Label.new()
		hint.text = "请先在上方领取熔铸奖励（%d 件）" % GameState.pending_sacrifice_rewards.size()
		hint.add_theme_font_size_override("font_size", 8)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.modulate = Color(1.0, 0.85, 0.3)
		shop_container.add_child(hint)
		return
	
	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 4) 
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	shop_container.add_child(main_vbox)

	var title := Label.new()
	title.text = "熔铸一个单位\n获得该职业专属 buff 防具"
	title.add_theme_font_size_override("font_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(title)

	var drop_zone := PanelContainer.new()
	drop_zone.name = "SacrificeDropZone"
	drop_zone.custom_minimum_size = Vector2(0, 35)
	drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.15, 0.15, 0.2, 0.5)
	stylebox.border_color = Color(0.4, 0.4, 0.5)
	stylebox.set_border_width_all(1)
	drop_zone.add_theme_stylebox_override("panel", stylebox)
	
	var drop_lbl := Label.new()
	drop_lbl.text = "拖拽单位至此确认熔铸"
	drop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_lbl.add_theme_font_size_override("font_size", 7)
	drop_lbl.modulate = Color(0.7, 0.8, 0.9)
	drop_zone.add_child(drop_lbl)
	main_vbox.add_child(drop_zone)

	var warn := Label.new()
	warn.text = "⚠ 熔铸第 3 个单位将导致全灭"
	warn.add_theme_font_size_override("font_size", 6)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.modulate = Color(1.0, 0.5, 0.5)
	main_vbox.add_child(warn)

func _on_open_sacrifice_ui():
	pass


func _trigger_sacrifice_confirm(u: UnitData):
	var melt_id : String = SacrificeHelper.get_melt_item_id(u.unit_name)
	var melt_data : ItemData = ItemManager.get_item_data(melt_id)
	var melt_name : String = melt_data.name if melt_data else "专属防具"
	var equip_count : int = 0
	for s in u.armor_slots:
		if s != null: equip_count += 1
	var alive_count := 0
	for member in party:
		if not member.is_dead: alive_count += 1
		
	var msg : String = ""
	if equip_count > 0:
		msg += "该单位仍有 %d 件防具，熔铸后将被锁定（需通过英灵殿复活取回）。\n\n" % equip_count
	msg += "确定熔铸 %s？\n将获得：【%s】（请在上方领取）" % [u.display_name, melt_name]
	if alive_count <= 1:
		msg += "\n\n⚠ 熔铸后全灭，本局将结束并返回营地。"

	Globals.show_confirm(self, msg, "熔铸", "取消", 
		func(): _do_sacrifice(u, [], 0), func(): pass)


func _do_sacrifice(u: UnitData, _armors_ignored: Array, _discard_count: int):
	var result : Dictionary = SacrificeHelper.do_sacrifice(party, u)

	_sync_all()

	var alive_count := 0
	for member in party:
		if not member.is_dead:
			alive_count += 1
	if alive_count <= 0:
		GameState.abandon_and_return_to_camp()
		return

	_build_unit_columns()
	_build_pending_slots()
	_update_gold_display()

	var msg : String = "已熔铸：%s\n获得：%s（请在上方领取）" % [
		u.display_name, result.get("melt_item_name", "专属防具")
	]
	_show_detail_in_zone(msg)

	_schedule_build_ui()


func _equip_pending_reward(data: Dictionary, target: Control):
	var pending_idx : int = data.get("pending_idx", -1)
	var pending_src : String = data.get("pending_src", "sacrifice")
	var target_type : String = target.get_meta("slot_type", "")
	var unit_idx : int = target.get_meta("unit_idx", -1)
	if unit_idx < 0 or unit_idx >= party.size(): return
	var u : UnitData = party[unit_idx]
	if u.is_dead: return

	var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice"
		else GameState.pending_forge_rewards)
	if pending_idx < 0 or pending_idx >= list.size(): return
	var inst : ItemInstance = list[pending_idx]
	if inst == null: return
	var item_data = ItemManager.get_item_data(inst.item_id)
	if not item_data: return

	if target_type == "weapon":
		return
	elif target_type == "armor":
		if item_data.type != "armor": return
		var slot_idx : int = target.get_meta("slot_idx", -1)
		if slot_idx < 0 or slot_idx >= u.armor_slots.size(): return

		if _is_slot_occupied_by_unsellable(unit_idx, slot_idx):
			_show_detail_in_zone("该槽位是不可丢弃的熔铸防具，无法覆盖")
			return

		var old_inst : ItemInstance = u.armor_slots[slot_idx]
		if old_inst:
			var old_data = ItemManager.get_item_data(old_inst.item_id)
			if old_data and not old_data.no_sell:
				var sell_price = old_inst.get_sell_price()
				_context.add_gold(sell_price)
				_show_detail_in_zone("替换下旧防具，自动折算 %d 金币" % sell_price)

		u.armor_slots[slot_idx] = inst
	else:
		return

	list.erase(inst)
	SaveManager.auto_save()

	_build_unit_columns()
	_build_pending_slots()
	_sync_all()
	_update_gold_display()

	if current_tab == "sacrifice" and shop_container and shop_container.visible:
		_build_sacrifice_panel()


func _discard_pending_reward(data: Dictionary):
	var pending_idx : int = data.get("pending_idx", -1)
	var pending_src : String = data.get("pending_src", "sacrifice")
	var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice"
		else GameState.pending_forge_rewards)
	if pending_idx < 0 or pending_idx >= list.size(): return
	var inst : ItemInstance = list[pending_idx]
	if inst == null: return
	var idata : ItemData = ItemManager.get_item_data(inst.item_id)
	if idata != null and idata.no_sell:
		_show_detail_in_zone("熔铸防具不可丢弃，请装备到单位防具槽")
		return
	
	var sell_price = inst.get_sell_price()
	if sell_price > 0:
		_context.add_gold(sell_price)
		_update_gold_display()
		_show_detail_in_zone("已出售 %s，获得 %d 金币" % [idata.name if idata else inst.item_id, sell_price])

	list.erase(inst)
	SaveManager.auto_save()
	_build_pending_slots()

	if current_tab == "sacrifice" and shop_container and shop_container.visible:
		_build_sacrifice_panel()


func _create_unit_icon(unit: UnitData, unit_idx: int) -> Control:
	var icon_size : float = 32
	var y_offset : float = -8

	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(0, icon_size)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.set_meta("slot_type", "unit_icon")
	wrapper.set_meta("unit_idx", unit_idx)

	var texture_rect = UnitDataManager.create_idle_texture_rect(unit.unit_name, Vector2(icon_size, icon_size), unit.override_sprite_path)
	
	texture_rect.anchor_left = 0.5
	texture_rect.anchor_right = 0.5
	texture_rect.offset_left = -icon_size / 2.0
	texture_rect.offset_right = icon_size / 2.0
	texture_rect.anchor_top = 0.0
	texture_rect.anchor_bottom = 0.0
	texture_rect.offset_top = y_offset
	texture_rect.offset_bottom = y_offset + icon_size
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(texture_rect)

	wrapper.mouse_entered.connect(_on_unit_hover_entered.bind(unit_idx))
	wrapper.mouse_exited.connect(_on_unit_hover_exited)

	return wrapper


func _disable_button(btn: Button):
	btn.disabled = true
	btn.modulate = Color(0.4, 0.4, 0.4, 1)


func _on_unit_hover_entered(unit_idx: int) -> void:
	if unit_idx < 0 or unit_idx >= party.size(): return
	var unit : UnitData = party[unit_idx]
	_detail.show_unit(unit)


func _on_unit_hover_exited() -> void:
	_detail.clear_zone()


func _create_item_button(inst: ItemInstance, slot_type: String, unit_idx: int, slot_idx: int, shop_dir: int = 0, is_shop: bool = false) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.clip_contents = false 
	
	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)
	
	if inst:
		var base_name : String = _get_item_name(inst)
		var data = ItemManager.get_item_data(inst.item_id)
		if data and data.icon:
			btn.icon = data.icon
			btn.text = ""
		else:
			btn.text = base_name

		var dir = inst.direction
		if is_shop:
			dir = shop_dir
			btn.set_meta("shop_direction", shop_dir)

		if dir != Direction.Value.NONE:
			_draw_direction_badges(btn, dir)
			btn.tooltip_text = "可在铁匠铺单件放入重roll方向"

		if unit_idx >= 0 and slot_idx >= 0:
			var key : String = "%d_%d" % [unit_idx, slot_idx]
			if _connected_cells.has(key):
				var gi = _connected_cells[key]
				var g = _connectivity_groups[gi]
				var group_size = g.size()
				
				var star := Label.new()
				star.text = "★"

				if group_size >= 5:
					star.add_theme_font_size_override("font_size", 10)
					star.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
				elif group_size >= 3:
					star.add_theme_font_size_override("font_size", 8)
					star.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
				else:
					star.add_theme_font_size_override("font_size", 7)
					star.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

				star.add_theme_color_override("font_outline_color", Color.BLACK)
				star.add_theme_constant_override("outline_size", 2)
				star.mouse_filter = Control.MOUSE_FILTER_IGNORE

				star.set_anchors_preset(Control.PRESET_FULL_RECT)
				star.offset_left = 0
				star.offset_right = 0
				star.offset_top = 0
				star.offset_bottom = 0
				star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

				btn.add_child(star)

	else:
		btn.text = "空"
	btn.set_meta("slot_type", slot_type)
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	btn.set_meta("item_id", inst.item_id if inst else "")
	if inst and inst.item_id != "":
		var item_id : String = inst.item_id
		# ★★★ v5.0：armor 类型走连通组感知 hover ★★★
		if slot_type == "armor" and unit_idx >= 0 and slot_idx >= 0:
			btn.mouse_entered.connect(_on_armor_hover_entered.bind(item_id, unit_idx, slot_idx))
			btn.mouse_exited.connect(_on_armor_hover_exited)
		else:
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
			btn.mouse_exited.connect(_on_button_hover_exited)
	return btn


func _draw_direction_badges(btn: Button, dir: int):
	var create_arrow := func(text: String, anchor: int, ox: float, oy: float):
		var lbl := Label.new()
		lbl.text = text
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
		lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1, 0.8))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.set_anchors_preset(anchor)
		lbl.offset_left = ox - 4
		lbl.offset_right = ox + 4
		lbl.offset_top = oy - 4
		lbl.offset_bottom = oy + 4
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.add_child(lbl)

	match dir:
		Direction.Value.UP: create_arrow.call("▲", Control.PRESET_CENTER_TOP, 0, 1)
		Direction.Value.DOWN: create_arrow.call("▼", Control.PRESET_CENTER_BOTTOM, 0, -1)
		Direction.Value.LEFT: create_arrow.call("◀", Control.PRESET_CENTER_LEFT, 1, 0)
		Direction.Value.RIGHT: create_arrow.call("▶", Control.PRESET_CENTER_RIGHT, -1, 0)
		Direction.Value.VERTICAL:
			create_arrow.call("▲", Control.PRESET_CENTER_TOP, 0, 1)
			create_arrow.call("▼", Control.PRESET_CENTER_BOTTOM, 0, -1)
		Direction.Value.HORIZONTAL:
			create_arrow.call("◀", Control.PRESET_CENTER_LEFT, 1, 0)
			create_arrow.call("▶", Control.PRESET_CENTER_RIGHT, -1, 0)
		Direction.Value.DIAG_NE_SW:
			create_arrow.call("◥", Control.PRESET_TOP_RIGHT, -2, 2)
			create_arrow.call("◣", Control.PRESET_BOTTOM_LEFT, 2, -2)
		Direction.Value.DIAG_NW_SE:
			create_arrow.call("◤", Control.PRESET_TOP_LEFT, 2, 2)
			create_arrow.call("◢", Control.PRESET_BOTTOM_RIGHT, -2, -2)


func _apply_icon_button_style(btn: Button):
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.clip_text = true
	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)


func _create_talent_button(inst: TalentInstance, unit_idx: int, slot_idx: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_TINY, Style.BTN_ITEM_SIZE)
	_apply_icon_button_style(btn)
	btn.set_meta("slot_type", "talent")
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)

	if inst and inst.is_active:
		var data : TalentData = TalentManager.get_talent_data(inst.talent_id)
		if data:
			var icon : Texture2D = TalentManager.get_talent_icon(inst.talent_id)
			if icon:
				btn.icon = icon
				btn.text = ""
			else:
				btn.text = data.display_name.substr(0, mini(2, data.display_name.length()))
			btn.set_meta("talent_id", inst.talent_id)
			btn.mouse_entered.connect(_on_talent_hover_entered.bind(inst.talent_id))
			btn.mouse_exited.connect(_on_talent_hover_exited)
		else:
			btn.text = "空"
			btn.modulate = Color(0.5, 0.5, 0.5, 1)
			btn.set_meta("talent_id", "")
	else:
		btn.text = "空"
		btn.modulate = Color(0.5, 0.5, 0.5, 1)
		btn.set_meta("talent_id", "")
	return btn


func _build_passive_slots():
	if not relic_container: return
	for child in relic_container.get_children(): relic_container.remove_child(child); child.free()
	var passives : Array = _context.get_passives()
	for i in range(MAX_PASSIVE_SLOTS):
		var inst : Variant = passives[i] if i < passives.size() else null
		var btn : Button = _create_passive_button(inst, i)
		relic_container.add_child(btn)


func _create_passive_button(inst: Variant, slot_index: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.clip_text = true
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.set_meta("slot_type", "passive_slot")
	btn.set_meta("passive_index", slot_index)
	
	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)

	if inst == null:
		btn.text = "空"
		btn.set_meta("item_id", "")
	elif inst is ItemInstance:
		var item_inst : ItemInstance = inst
		var data : Dictionary = RelicManager.get_relic_data(item_inst.item_id)
		if not data.is_empty():
			var prefix : String = "★ " if GameState.is_relic_refined(item_inst.item_id) else ""
			var icon = data.get("icon")
			if icon is Texture2D:
				btn.icon = icon
				btn.text = ""
			else:
				btn.text = prefix + data.get("name", "?")
			btn.set_meta("item_id", item_inst.item_id)
			btn.mouse_entered.connect(_on_relic_hover_entered.bind(item_inst.item_id))
			btn.mouse_exited.connect(_on_relic_hover_exited)
		else:
			btn.text = "?"
			btn.set_meta("item_id", "")
	elif inst is Dictionary and inst.get("type", "") == "aura":
		var aid : String = inst.get("aura_id", "")
		var ad : Dictionary = AuraManager.get_aura(aid)
		var icon = ad.get("icon")
		if icon is Texture2D:
			btn.icon = icon
			btn.text = ""
		else:
			btn.text = "✦ " + ad.get("name", aid)
		btn.set_meta("item_id", "")
		btn.set_meta("aura_id", aid) 
		btn.modulate = Color(0.7, 0.9, 1.0)
	else:
		btn.text = "空"
		btn.set_meta("item_id", "")
	return btn


func _inst_slots(inst: ItemInstance) -> int:
	return 0 if inst == null else 1

func _used_slots_of(unit: UnitData) -> int:
	var used : int = 0
	for slot in unit.armor_slots:
		if slot != null: used += 1
	return used

func _used_slots_excluding(unit: UnitData, exclude_slots: Array) -> int:
	var used : int = 0
	for i in range(unit.armor_slots.size()):
		if i in exclude_slots: continue
		if unit.armor_slots[i] != null: used += 1
	return used

func _can_equip_armor_to(unit_idx: int, item_id: String, exclude_slot_idx: int = -1) -> bool:
	if unit_idx < 0 or unit_idx >= party.size(): return false
	if item_id == "": return true
	var unit : UnitData = party[unit_idx]
	if exclude_slot_idx >= 0 and exclude_slot_idx < unit.armor_slots.size():
		return true
	for s in unit.armor_slots:
		if s == null: return true
	return false

func _is_slot_occupied_by_unsellable(unit_idx: int, slot_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= party.size(): return false
	if slot_idx < 0 or slot_idx >= party[unit_idx].armor_slots.size(): return false
	var inst : ItemInstance = party[unit_idx].armor_slots[slot_idx]
	if inst == null: return false
	var idata : ItemData = ItemManager.get_item_data(inst.item_id)
	return idata != null and idata.no_sell

func _inst_slots_for_id(_item_id: String) -> int:
	return 1

func _get_item_name(inst: ItemInstance) -> String:
	if not inst: return ""
	var data : ItemData = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id


func _is_valid_drop(data: Dictionary, target: Control) -> bool:
	var source_type : String = data["slot_type"]
	var target_type : String = target.get_meta("slot_type", "")
	var discard : bool = target == discard_zone

	if source_type == "unit_icon":
		if target.name == "SacrificeDropZone":
			var uidx = data.get("unit_idx", -1)
			if uidx >= 0 and uidx < party.size():
				return not party[uidx].is_dead
			return false
		return target_type == "unit_icon"

	if discard:
		if source_type == "armor":
			var uidx : int = data.get("unit_idx", -1)
			var sidx : int = data.get("slot_idx", -1)
			if uidx >= 0 and uidx < party.size() and sidx >= 0 and sidx < party[uidx].armor_slots.size():
				var inst : ItemInstance = party[uidx].armor_slots[sidx]
				if inst != null:
					var idata : ItemData = ItemManager.get_item_data(inst.item_id)
					if idata != null and idata.no_sell:
						return false
		elif source_type == "pending_reward":
			var pidx : int = data.get("pending_idx", -1)
			var psrc : String = data.get("pending_src", "sacrifice")
			var plist : Array = (GameState.pending_sacrifice_rewards if psrc == "sacrifice"
				else GameState.pending_forge_rewards)
			if pidx >= 0 and pidx < plist.size():
				var pinst : ItemInstance = plist[pidx]
				if pinst != null:
					var pdata : ItemData = ItemManager.get_item_data(pinst.item_id)
					if pdata != null and pdata.no_sell:
						return false

	if source_type in ["aura_shop", "aura_equipped"]:
		if target_type == "passive_slot":
			var tgt_idx = target.get_meta("passive_index", -1)
			var passives = _context.get_passives()
			if tgt_idx >= 0 and tgt_idx < passives.size() and passives[tgt_idx] == null:
				return true
		return false

	if source_type == "talent" and target_type == "library_talent":
		return true

	var tgt_uidx : int = target.get_meta("unit_idx", -1)
	if tgt_uidx >= 0 and tgt_uidx < party.size():
		if party[tgt_uidx].is_dead:
			return false
	var src_uidx : int = data.get("unit_idx", -1)
	if src_uidx >= 0 and src_uidx < party.size():
		if party[src_uidx].is_dead:
			return false

	if source_type == "pending_reward":
		if discard: return true
		if target_type == "forge_slot":
			return _forge.is_valid_forge_drop(data, target)
		if target_type not in ["weapon", "armor"]: return false
		var tu_p : int = target.get_meta("unit_idx", -1)
		if tu_p < 0 or tu_p >= party.size(): return false
		if party[tu_p].is_dead: return false
		var pending_idx : int = data.get("pending_idx", -1)
		var pending_src : String = data.get("pending_src", "sacrifice")
		var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice"
			else GameState.pending_forge_rewards)
		if pending_idx < 0 or pending_idx >= list.size(): return false
		var inst : ItemInstance = list[pending_idx]
		if inst == null: return false
		var idata = ItemManager.get_item_data(inst.item_id)
		if not idata: return false
		if target_type == "weapon":
			return false
		elif target_type == "armor":
			if idata.type != "armor": return false
			var ts_p : int = target.get_meta("slot_idx", -1)
			if ts_p < 0 or ts_p >= party[tu_p].armor_slots.size(): return false
			if _is_slot_occupied_by_unsellable(tu_p, ts_p): return false
			var need_p : int = _inst_slots(inst)
			var used_p : int = _used_slots_excluding(party[tu_p], [ts_p])
			return used_p + need_p <= party[tu_p].max_armor_slots
		return false

	if source_type == "passive_slot":
		if target_type == "passive_slot": return true
		if discard: return true
		return false
	if target_type == "passive_slot":
		return false

	if current_mode == Mode.FORGE and current_tab != "arena_shop":
		return _forge.is_valid_forge_drop(data, target)
	if is_shop_rest_mode() and current_tab == "arena_forge":
		return _forge.is_valid_forge_drop(data, target)

	if current_mode == Mode.DEPLOY:
		if discard: return false
		if source_type == "library_weapon": return false
		if source_type == "weapon" and target_type == "weapon": return false
		if source_type == "library_talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		return false

	if current_mode == Mode.MAP:
		if discard:
			if source_type == "armor": return true
			return false
		if source_type == "weapon" and target_type == "weapon": return false 
		if source_type == "armor" and target_type == "armor":
			return _check_armor_swap_budget(data, target)
		if source_type == "library_talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		return false

	var is_shop_ctx = (
		(current_mode == Mode.FORGE and current_tab == "arena_shop")
		or (is_shop_rest_mode() and current_tab == "arena_shop")
	)
	if is_shop_ctx:
		if discard:
			if source_type in ["shop_item", "weapon", "library_talent", "talent"]: return false
			return true
		if source_type == "shop_item":
			var item_data : ItemData = data.get("item_data")
			if not item_data: return false
			var tu2 : int = target.get_meta("unit_idx", -1)
			var ts2 : int = target.get_meta("slot_idx", -1)
			if item_data.type == "weapon":
				return false
			elif item_data.type == "armor":
				if target_type != "armor": return false
				if tu2 < 0 or ts2 < 0: return false
				if _is_slot_occupied_by_unsellable(tu2, ts2): return false
				return _can_equip_armor_to(tu2, item_data.id, ts2)
			return false
		if source_type == "weapon" and target_type == "weapon": return false
		if source_type == "armor" and target_type == "armor":
			return _check_armor_swap_budget(data, target)
		return false
	return false


func _check_armor_swap_budget(data: Dictionary, target: Control) -> bool:
	var su : int = data.get("unit_idx", -1)
	var ss : int = data.get("slot_idx", -1)
	var tu : int = target.get_meta("unit_idx", -1)
	var ts : int = target.get_meta("slot_idx", -1)
	if su < 0 or ss < 0 or tu < 0 or ts < 0: return false
	if su == tu and ss == ts: return false
	return true


func _execute_drop(data: Dictionary, target: Control):
	var source_type : String = data.get("slot_type", "")
	var target_type : String = target.get_meta("slot_type", "")

	if source_type == "unit_icon" and target.name == "SacrificeDropZone":
		var uidx = data.get("unit_idx", -1)
		if uidx >= 0 and uidx < party.size():
			_trigger_sacrifice_confirm(party[uidx])
		return

	if source_type == "pending_reward" and target_type == "forge_slot":
		var pending_idx : int = data.get("pending_idx", -1)
		var pending_src : String = data.get("pending_src", "sacrifice")
		var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice" else GameState.pending_forge_rewards)
		if pending_idx >= 0 and pending_idx < list.size():
			var inst : ItemInstance = list[pending_idx]
			list.erase(inst)
			
			var empty_idx = -1
			for i in range(_forge.forge_slots.size()):
				if _forge.forge_slots[i] == null:
					empty_idx = i
					break
			if empty_idx >= 0:
				_forge.forge_slots[empty_idx] = {"inst": inst, "origin_unit": -1, "origin_slot": -1}
				_forge.build_forge_slots()
				_build_pending_slots()
				_sync_all()
				_schedule_build_ui()
		return

	if source_type == "unit_icon" and target_type == "unit_icon":
		var su : int = data.get("unit_idx", -1)
		var tu : int = target.get_meta("unit_idx", -1)
		if su >= 0 and tu >= 0 and su != tu:
			_apply_unit_swap(su, tu)
		return

	if source_type == "aura_shop" and target_type == "passive_slot":
		_buy_and_equip_aura(data, target); return
	if source_type == "aura_equipped" and target_type == "passive_slot":
		_swap_aura(data, target); return

	if source_type == "pending_reward" and target_type in ["weapon", "armor"]:
		_equip_pending_reward(data, target); return
	if source_type == "pending_reward" and target == discard_zone:
		_discard_pending_reward(data); return

	if source_type == "passive_slot":
		if target == discard_zone: _discard_passive(data); return
		if target_type == "passive_slot": _swap_passives(data, target); return

	if current_mode == Mode.FORGE and current_tab != "arena_shop":
		_forge.execute_forge_drop(data, target); return
	if is_shop_rest_mode() and current_tab == "arena_forge":
		_forge.execute_forge_drop(data, target); return

	var discard : bool = target == discard_zone

	if discard and source_type == "talent": _talent.execute_talent_remove(data); return
	if source_type == "talent" and target_type == "library_talent":
		_talent.execute_talent_remove(data); return
	if discard: _discard_item(data); return
	if source_type == "shop_item": _shop.buy_shop_item(data, target); return
	if source_type == "library_talent" and target_type == "talent": _talent.execute_talent_drop(data, target); return
	if source_type == "talent" and target_type == "talent": _talent.execute_talent_drop(data, target); return
	if source_type == "armor" and target_type == "armor": _shop.swap_armor(data, target)


func _buy_and_equip_aura(data: Dictionary, target: Control):
	var aid : String = data.get("aura_id", "")
	var cost : int = data.get("aura_price", 0)
	var tgt_idx : int = target.get_meta("passive_index", -1)
	if tgt_idx < 0 or aid == "": return

	var passives : Array = _context.get_passives()
	if passives[tgt_idx] != null: return

	if not SoulFireManager.spend(cost):
		return

	_context.set_passive_at_slot(tgt_idx, {"type": "aura", "aura_id": aid})
	GameState.remove_aura_candidate(aid)
	_sync_all()
	_update_gold_display()
	_schedule_build_ui()
	_show_detail_in_zone("已购买并装备光环：%s" % AuraManager.get_display_name(aid))

func _swap_aura(data: Dictionary, target: Control):
	var aid : String = data.get("aura_id", "")
	var tgt_idx : int = target.get_meta("passive_index", -1)
	if tgt_idx < 0: return
	
	var passives : Array = _context.get_passives()
	var src_idx : int = -1
	for i in range(passives.size()):
		var p : Variant = passives[i]
		if p is Dictionary and p.get("type", "") == "aura" and p.get("aura_id", "") == aid:
			src_idx = i
			break
			
	if src_idx == -1 or src_idx == tgt_idx: return
	if passives[tgt_idx] != null: return
	
	_context.set_passive_at_slot(tgt_idx, passives[src_idx])
	_context.set_passive_at_slot(src_idx, null)
	SoundManager.play_select_sound()
	_sync_all()
	_schedule_build_ui()


func _discard_passive(data: Dictionary):
	var idx : int = data.get("passive_index", -1)
	if idx < 0: return
	_context.remove_passive_at_slot(idx)
	_sync_all(); _schedule_build_ui()


func _swap_passives(data: Dictionary, target: Control):
	var src_idx : int = data.get("passive_index", -1)
	var tgt_idx : int = target.get_meta("passive_index", -1)
	if src_idx < 0 or tgt_idx < 0 or src_idx == tgt_idx: return
	var passives : Array = _context.get_passives()
	var temp : Variant = passives[src_idx]
	_context.set_passive_at_slot(src_idx, passives[tgt_idx])
	_context.set_passive_at_slot(tgt_idx, temp)
	_sync_all(); _schedule_build_ui()


func _discard_item(data: Dictionary):
	var source_type : String = data["slot_type"]
	if source_type == "library_weapon" or source_type == "weapon": return
	var unit_idx : int = data["unit_idx"]
	var slot_idx : int = data["slot_idx"]
	var u : UnitData = party[unit_idx]
	
	if source_type == "armor":
		var inst : ItemInstance = u.armor_slots[slot_idx]
		if inst != null:
			var sell_price = inst.get_sell_price()
			if sell_price > 0:
				_context.add_gold(sell_price)
				_show_detail_in_zone("出售防具，获得 %d 金币" % sell_price)
		u.armor_slots[slot_idx] = null
	elif source_type == "talent": 
		_talent.discard_talent(data)
		
	_update_gold_display()
	_build_unit_columns()
	_sync_all(); _schedule_build_ui()


func _on_confirm_pressed():
	if not _check_pending_before_leave():
		return

	if current_mode == Mode.FORGE: _forge.on_forge_craft_pressed(); return
	if current_mode == Mode.ARENA_REST:
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return

	var target_units : Array = _context.get_units()
	var target_map : Dictionary = {}
	for tu in target_units:
		var key : String = "%s|%s" % [tu.unit_name, tu.display_name]
		target_map[key] = tu
		
	_sync_all()

	if _context.get_context_id() == "main_game" and selected_units.size() > 0:
		var main_data : Dictionary = UnitDataManager.get_unit_data(selected_units[0])
		var faction : String = main_data.get("faction", "王国")
		_context.set_pending_faction(faction)

	_context.on_confirm()
	_context.auto_save()
	var canvas_layer : Node = get_parent()
	if canvas_layer: canvas_layer.queue_free()
	else: queue_free()


func _copy_party_data():
	party.clear()
	var units : Array = _context.get_units()
	for unit_data in units:
		var ud : UnitData = unit_data
		party.append(UnitData.from_dict(ud.to_dict()))
	
	_ensure_armor_directions()


func _ensure_armor_directions():
	for u in party:
		for slot in u.armor_slots:
			if slot == null: continue
			if slot.direction != Direction.Value.NONE: continue
			var data = ItemManager.get_item_data(slot.item_id)
			if data and data.enable_direction:
				slot.direction = Direction.roll_drop_direction()


func _clear_container(container: Node):
	if not container: return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _sync_all():
	var target_units : Array = _context.get_units()
	var target_map : Dictionary = {}
	for tu in target_units:
		var key : String = "%s|%s" % [tu.unit_name, tu.display_name]
		target_map[key] = tu

	for u in party:
		var armor_target : int = clampi(u.max_armor_slots, 0, 10)
		u.max_armor_slots = armor_target
		u.armor_slots.resize(armor_target)
		var talent_target : int = maxi(u.talent_slots.size(), 1)
		u.talent_slots.resize(talent_target)

		var key : String = "%s|%s" % [u.unit_name, u.display_name]
		if not target_map.has(key):
			continue
		var tu : UnitData = target_map[key]
		if u.is_dead and tu.is_dead:
			continue
		
		tu.armor_slots = _clone_inst_array(u.armor_slots)
		tu.max_armor_slots = u.max_armor_slots
		tu.talent_slots = _clone_talent_array(u.talent_slots)
		tu.is_dead = u.is_dead
		tu.advanced_talent_id = u.advanced_talent_id
		tu.level = u.level
		tu.attack_range_bonus = u.attack_range_bonus
		tu.static_physical_penetration = u.static_physical_penetration
		tu.static_magic_penetration = u.static_magic_penetration
		tu.static_crit_damage_bonus = u.static_crit_damage_bonus
		tu.max_hp = u.max_hp
		tu.hit_points = u.hit_points
		tu.strength = u.strength
		tu.dexterity = u.dexterity
		tu.intelligence = u.intelligence
		tu.faith = u.faith
		tu.move_range = u.move_range

static func _clone_item_inst(src: ItemInstance) -> ItemInstance:
	if src == null: return null
	var inst = ItemInstance.new()
	inst.item_id = src.item_id
	inst.count = src.count
	inst.upgrade_level = src.upgrade_level
	inst.affixes = src.affixes.duplicate(true)
	inst.direction = src.direction
	return inst

static func _clone_inst_array(src: Array) -> Array:
	var out : Array = []
	for s in src: out.append(_clone_item_inst(s))
	return out

static func _clone_talent_inst(src) -> TalentInstance:
	if src == null or not (src is TalentInstance): return null
	var inst := TalentInstance.new()
	inst.talent_id = src.talent_id
	inst.current_stack = src.current_stack
	inst.is_ready = src.is_ready
	inst.is_active = src.is_active
	inst.cooldown_remaining = src.cooldown_remaining
	return inst

static func _clone_talent_array(src: Array) -> Array:
	var out : Array = []
	for s in src: out.append(_clone_talent_inst(s))
	return out


func _switch_tab(tab: String):
	SoundManager.play_select_sound()
	
	if not _check_pending_before_leave():
		return
	if current_tab == tab: return
	
	if (current_mode == Mode.FORGE or is_shop_rest_mode()) and current_tab == "arena_forge":
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return
			
	current_tab = tab
	_update_tab_style()
	_clear_container(shop_container)
	var is_forge_tab : bool = (tab == "arena_forge")
	if not is_forge_tab:
		_forge.cleanup()
		
	var show_pending : bool = false
	if current_mode == Mode.FORGE or is_shop_rest_mode():
		if tab != "arena_shop" and tab != "weapon":
			show_pending = true
			
	if show_pending:
		_ensure_pending_section()
		_build_pending_slots()
		if _pending_section:
			_pending_section.visible = true
	else:
		if _pending_section and is_instance_valid(_pending_section):
			var p = _pending_section.get_parent()
			if p: p.remove_child(_pending_section)
			_pending_section.queue_free()
			_pending_section = null
			_pending_container = null

	match tab:
		"weapon": _shop.build_weapon_grid(shop_container)
		"talent": _talent.build_talent_grid(shop_container)
		"arena_shop":
			if shop_manager and shop_manager.get_shop_items().is_empty():
				shop_manager.generate_shop_items()
			_shop.build_shop_items()
		"arena_forge":
			_forge.build_forge_slots()
		"sacrifice":
			_build_sacrifice_panel()
		"aura":
			_build_aura_panel()
	shop_container.visible = true
	
	reset_btn.visible = (tab == "arena_shop")
	if reset_btn.visible and shop_manager:
		reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
		
	discard_zone.visible = (tab != "arena_forge" and tab != "sacrifice" and tab != "aura" and current_mode != Mode.DEPLOY)
	
	_refresh_bottom_buttons()
	_refresh_upgrade_shop_btn()


func _force_relayout():
	await get_tree().process_frame
	if not is_inside_tree(): return
	if shop_scroll:
		shop_scroll.scroll_vertical = 0
		shop_scroll.scroll_horizontal = 0
		shop_scroll.queue_sort()
	if shop_container:
		shop_container.queue_sort()


func _refresh_bottom_buttons():
	var in_sacrifice : bool = (current_tab == "sacrifice")
	var in_arena_forge : bool = (current_tab == "arena_forge")
	var in_aura : bool = (current_tab == "aura")

	if in_sacrifice or in_arena_forge or in_aura:
		close_btn.disabled = true
		close_btn.modulate = Color(0.5, 0.5, 0.5)
	else:
		close_btn.disabled = false
		close_btn.modulate = Color.WHITE

	if current_mode == Mode.ARENA_REST:
		close_btn.visible = false
		confirm_btn.visible = true
		confirm_btn.text = "出发"
		if current_tab == "arena_forge" or current_tab == "aura":
			confirm_btn.disabled = true
			confirm_btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			confirm_btn.disabled = false
			confirm_btn.modulate = Color.WHITE
		discard_zone.visible = (current_tab != "arena_forge")
	elif current_mode == Mode.MAP_SHOP_REST:
		close_btn.visible = true
		close_btn.text = "继续探索"
		confirm_btn.visible = false
		discard_zone.visible = (current_tab != "arena_forge")


func _update_tab_style():
	if not weapon_tab_btn or not talent_tab_btn:
		return

	if current_mode == Mode.ARENA_REST:
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
		if _aura_tab_btn: _aura_tab_btn.visible = false
		return

	if current_mode == Mode.MAP_SHOP_REST:
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if sacrifice_tab_btn:
			sacrifice_tab_btn.modulate = Color.WHITE if current_tab == "sacrifice" else Color(0.5, 0.5, 0.5)
		if _aura_tab_btn:
			_aura_tab_btn.modulate = Color.WHITE if current_tab == "aura" else Color(0.5, 0.5, 0.5)
		return

	if current_mode == Mode.FORGE:
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if sacrifice_tab_btn:
			sacrifice_tab_btn.modulate = Color.WHITE if current_tab == "sacrifice" else Color(0.5, 0.5, 0.5)
		if _aura_tab_btn:
			_aura_tab_btn.modulate = Color.WHITE if current_tab == "aura" else Color(0.5, 0.5, 0.5)
		return

	weapon_tab_btn.modulate = Color.WHITE if current_tab == "weapon" else Color(0.5, 0.5, 0.5)
	talent_tab_btn.modulate = Color.WHITE if current_tab == "talent" else Color(0.5, 0.5, 0.5)
	if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
	if _aura_tab_btn: _aura_tab_btn.visible = false


func _input(event: InputEvent):
	if _has_active_confirm_ui(): return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _detail != null and _detail.has_hover():
			Globals.toggle_info_mode()
			_detail.refresh()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos : Vector2 = get_global_mouse_position()
		var btn : Control = _drag._find_control_at_position(mouse_pos)
		if btn and (btn is Button or btn.get_meta("slot_type", "") == "unit_icon"):
			_drag.start_drag(btn)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drag.end_drag()
	elif event is InputEventMouseMotion:
		if _drag.is_dragging: _drag.update_drag_preview()


func _process(_delta):
	if _drag.is_dragging: _drag.update_drag_preview()


func _show_buy_failure_message(reason: String):
	var msg : String = ""
	match reason:
		"not_enough_gold": msg = "金币不足！"
		"empty_slot": msg = "该商品已被购买"
		"invalid_index": msg = "无效的商品位置"
		_: msg = "购买失败：" + reason
	Globals.show_confirm(self, msg, "确定", "", func(): pass, func(): pass, false)


func _schedule_build_ui():
	if _build_ui_pending: return
	_build_ui_pending = true
	call_deferred("_do_build_ui")


func _do_build_ui():
	_build_ui_pending = false
	if _is_closing: return
	_build_ui()


func _has_active_confirm_ui() -> bool:
	for child in get_children():
		if child is CanvasLayer:
			var script : Script = child.get_script()
			if script and script.resource_path.ends_with("ConfirmUI.gd"): return true
	return false


func _build_shop_items(): 
	_shop.build_shop_items()

func _build_weapon_grid(container: Container): 
	_shop.build_weapon_grid(container)

func _on_reset_shop_pressed(): 
	_shop_direction_cache.clear()
	_shop.on_reset_shop_pressed()

func _build_talent_grid(container: Container): 
	_talent.build_talent_grid(container)

func _get_talent_display_unit_type() -> String: 
	return _talent._get_talent_display_unit_type()

func _use_context_units() -> Array: 
	return _talent._use_context_units()

func _check_talent_compatibility(data: Dictionary, target: Control) -> bool:
	return _talent.check_talent_compatibility(data, target)

func _is_talent_already_equipped(talent_id: String, exclude_unit_idx: int = -1, exclude_slot_idx: int = -1) -> bool:
	return _talent.is_talent_already_equipped(talent_id, exclude_unit_idx, exclude_slot_idx)

func _get_unit_with_talent(talent_id: String) -> String:
	return _talent.get_unit_with_talent(talent_id)

func _is_talent_equipped_anywhere(talent_id: String) -> bool:
	return _talent.is_talent_equipped_anywhere(talent_id)

func show_item_detail(item_id: String): _detail.show_item(item_id)
func hide_item_detail(): _detail.clear_zone()
func _on_button_hover_entered(item_id: String): _detail.on_button_hover_entered(item_id)
func _on_button_hover_exited(): _detail.on_button_hover_exited()
func _on_talent_hover_entered(talent_id: String): _detail.on_talent_hover_entered(talent_id)
func _on_aura_hover_entered(aura_id: String) -> void:
	if _detail:
		_detail.show_aura(aura_id)
func _on_aura_hover_exited() -> void:
	if _detail:
		_detail.clear_zone()
func _on_talent_hover_exited(): _detail.on_talent_hover_exited()
func _on_relic_hover_entered(relic_id: String): _detail.on_relic_hover_entered(relic_id)
func _on_relic_hover_exited(): _detail.on_relic_hover_exited()
func _show_detail_in_zone(text: String): _detail.show_in_zone(text)
func _clear_detail_zone(): _detail.clear_zone()


func _show_craft_result(result : Dictionary):
	var lines : Array = []
	if result.get("is_recipe", false):
		lines.append("=== 图纸合成 ===")
	else:
		var score : int = result.get("input_score", 0)
		lines.append("=== 通用合成（评分 %d）===" % score)
		if result.get("lucky", false):
			lines.append("★ 幸运暴击！品质 +1")

	for item_id in result["item_ids"]:
		var data = ItemManager.get_item_data(item_id)
		if data:
			lines.append("★ " + data.name)
	lines.append("品质：" + _quality_cn(result["quality"]))
	if result.get("bonus_count", 0) > 0:
		lines.append("[额外] 产出 ×%d" % result["bonus_count"])
	_show_detail_in_zone("\n".join(lines))


func _quality_cn(q : String) -> String:
	match q:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return q


func _ensure_upgrade_shop_btn():
	if _upgrade_shop_btn and is_instance_valid(_upgrade_shop_btn):
		return
	if not reset_btn: return

	_upgrade_shop_btn = Style.create_styled_button(Style.FONT_LARGE, Vector2(100, 16))
	_upgrade_shop_btn.name = "UpgradeShopBtn" 
	_upgrade_shop_btn.custom_minimum_size = Vector2(0, 16)
	_upgrade_shop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_shop_btn.size_flags_vertical = Control.SIZE_SHRINK_END 
	_upgrade_shop_btn.clip_text = true
	_upgrade_shop_btn.pressed.connect(_on_upgrade_shop_pressed)
	
	right_container.add_child(_upgrade_shop_btn)
	var reset_idx : int = reset_btn.get_index()
	right_container.move_child(_upgrade_shop_btn, reset_idx)


func _refresh_upgrade_shop_btn():
	if not _upgrade_shop_btn or not is_instance_valid(_upgrade_shop_btn):
		return
	if not shop_manager:
		_upgrade_shop_btn.visible = false
		return

	var is_shop_tab : bool = (
		(current_mode == Mode.FORGE and current_tab == "arena_shop")
		or (is_shop_rest_mode() and current_tab == "arena_shop")
	)
	if not is_shop_tab:
		_upgrade_shop_btn.visible = false
	else:
		_upgrade_shop_btn.visible = true
		var lv : int = shop_manager.get_shop_level()
		var cost : int = shop_manager.get_upgrade_cost()
		if cost < 0:
			_upgrade_shop_btn.text = "商店 Lv%d（满级）" % lv
			_upgrade_shop_btn.disabled = true
			_upgrade_shop_btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			_upgrade_shop_btn.text = "升级商店 Lv%d→%d（%dG）" % [lv, lv + 1, cost]
			var afford : bool = _context.get_gold() >= cost
			_upgrade_shop_btn.disabled = not afford
			_upgrade_shop_btn.modulate = Color.WHITE if afford else Color(1.0, 0.6, 0.6)


func _on_upgrade_shop_pressed():
	if not shop_manager: return
	if not shop_manager.upgrade_shop():
		_show_buy_failure_message("not_enough_gold")
		return
	SoundManager.play_select_sound()
	_update_gold_display()
	_schedule_build_ui()


func _create_advanced_talent_button(unit: UnitData, unit_idx: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_TINY, Style.BTN_ITEM_SIZE)
	_apply_icon_button_style(btn)
	btn.set_meta("slot_type", "advanced_talent")
	btn.set_meta("unit_idx", unit_idx)
	btn.disabled = true

	if unit.advanced_talent_id == "":
		btn.text = "无"
		btn.modulate = Color(0.5, 0.5, 0.5, 1)
		return btn

	var data : TalentData = TalentManager.get_talent_data(unit.advanced_talent_id)
	if not data:
		btn.text = "?"
		btn.modulate = Color(0.5, 0.5, 0.5, 1)
		return btn

	var icon : Texture2D = TalentManager.get_talent_icon(unit.advanced_talent_id)
	if icon:
		btn.icon = icon
		btn.text = ""
	else:
		btn.text = data.display_name.substr(0, mini(2, data.display_name.length()))

	btn.set_meta("talent_id", unit.advanced_talent_id)
	btn.mouse_entered.connect(_on_talent_hover_entered.bind(unit.advanced_talent_id))
	btn.mouse_exited.connect(_on_talent_hover_exited)
	return btn


func _setup_forge_narrative_ui() -> void:
	if not _forge_enter_done:
		_forge_enter_done = true
		call_deferred("_trigger_forge_enter")


func _trigger_forge_enter() -> void:
	if not is_inside_tree():
		return
	var ctx := {
		"npc_id": "forge",
		"current_day": GameState.current_day,
		"npc_interact_count": StoryManager.get_npc_interact_count("forge"),
	}
	StoryManager.trigger("forge_enter", ctx)


func _swap_units_cyclic(unit_idx: int):
	if unit_idx < 0 or unit_idx >= party.size(): return
	if party.size() <= 1: return

	var next_idx : int = (unit_idx + 1) % party.size()
	_apply_unit_swap(unit_idx, next_idx)


func _apply_unit_swap(a: int, b: int):
	if a == b: return
	if a < 0 or a >= party.size(): return
	if b < 0 or b >= party.size(): return

	if party[a].is_dead or party[b].is_dead:
		Globals.show_confirm(self, "已阵亡的单位无法交换", "确定", "",
			func(): pass, func(): pass, false)
		return

	SoundManager.play_select_sound()

	var name_a : String = party[a].display_name if party[a].display_name != "" else party[a].unit_name
	var name_b : String = party[b].display_name if party[b].display_name != "" else party[b].unit_name

	var temp = party[a]
	party[a] = party[b]
	party[b] = temp

	_refresh_connectivity()
	_build_unit_columns.call_deferred()
	_sync_all.call_deferred()
	_schedule_build_ui.call_deferred()

	_show_detail_in_zone("已交换单位位置：%s ↔ %s" % [name_a, name_b])


func _open_auto_config_dialog():
	if party.is_empty():
		return
	if party.size() < 2:
		Globals.show_confirm(self, "至少需要 2 个单位才能自动配装", "确定", "",
			func(): pass, func(): pass, false)
		return

	var msg : String = "自动配装\n\n将根据「连通组 + 套装 + 属性」生成 3 个方案。\n\n"
	msg += "允许交换单位位置会显著增加搜索空间（耗时 5~10 秒），但结果更优。"

	Globals.show_confirm(
		self, msg,
		"允许交换（慢）", "不交换（快）",
		func(): _run_auto_config(true),
		func(): _run_auto_config(false),
		true
	)


func _run_auto_config(allow_swap_units: bool):
	var progress = Globals.get_reward_summary()
	if progress:
		progress.show_text("自动配装计算中…（%s）" % ("含单位交换" if allow_swap_units else "仅防具"))
		progress.open()
		await get_tree().process_frame

	var options : Array = _generate_auto_options(allow_swap_units)

	if progress:
		progress.close()

	if options.is_empty():
		Globals.show_confirm(self, "自动配装失败（无有效方案）", "确定", "",
			func(): pass, func(): pass, false)
		return

	_show_auto_config_result_dialog(options, allow_swap_units)


func _generate_auto_options(allow_swap_units: bool) -> Array:
	var base_layout := _snapshot_layout()

	var weight_sets : Array = [
		{"name": "攻击流", "atk": 1.0, "def": 0.3, "hp": 0.3},
		{"name": "防御流", "atk": 0.3, "def": 1.0, "hp": 0.8},
		{"name": "平衡流", "atk": 0.6, "def": 0.6, "hp": 0.6},
	]

	var results : Array = []
	for ws in weight_sets:
		var result = _run_simulated_annealing(
			base_layout, allow_swap_units,
			ws["atk"], ws["def"], ws["hp"], 2000)
		if result != null:
			result["weight_name"] = ws["name"]
			results.append(result)

	return results


func _snapshot_layout() -> Dictionary:
	var slots : Array = []
	for i in range(party.size()):
		var unit_slots : Array = []
		for slot in party[i].armor_slots:
			if slot == null:
				unit_slots.append(null)
			else:
				unit_slots.append(_clone_item_inst(slot))
		slots.append(unit_slots)
	var unit_order : Array = []
	for u in party:
		unit_order.append(u)
	return {"slots": slots, "unit_order": unit_order}


func _apply_layout(layout: Dictionary):
	var slots : Array = layout["slots"]
	var unit_order : Array = layout["unit_order"]
	for i in range(party.size()):
		if i >= slots.size(): break
		party[i].armor_slots = slots[i]
	party.clear()
	for u in unit_order:
		party.append(u)


func _evaluate_layout(layout: Dictionary, atk_w: float, def_w: float, hp_w: float) -> float:
	var slots : Array = layout["slots"]
	var groups : Array = ConnectedGroupCalculator.compute_groups(slots)
	var bonus : Dictionary = ConnectedGroupCalculator.evaluate_groups(groups)

	var score : float = 0.0
	score += bonus["attack_pct"] * 10.0 * atk_w
	score += bonus["defense_pct"] * 8.0 * def_w
	score += bonus["hp_pct"] * 5.0 * hp_w
	score += bonus["total_groups"] * 2.0
	score += bonus["cross_3_groups"] * 3.0

	var set_counts : Dictionary = {}
	for unit_slots in slots:
		for slot in unit_slots:
			if slot == null: continue
			var d = ItemManager.get_item_data(slot.item_id)
			if d == null: continue
			for tag in d.tags:
				set_counts[tag] = set_counts.get(tag, 0) + 1
	for tag in set_counts:
		if set_counts[tag] >= 3:
			score += 3.0

	return score


func _run_simulated_annealing(base_layout: Dictionary, allow_swap: bool,
		atk_w: float, def_w: float, hp_w: float, iterations: int) -> Dictionary:
	var current : Dictionary = {
		"slots": base_layout["slots"].duplicate(true),
		"unit_order": base_layout["unit_order"].duplicate(),
	}
	var best : Dictionary = {
		"slots": current["slots"].duplicate(true),
		"unit_order": current["unit_order"].duplicate(),
	}
	var best_score : float = _evaluate_layout(current, atk_w, def_w, hp_w)
	var cur_score : float = best_score

	var T : float = 10.0
	var T_min : float = 0.1
	var alpha : float = 0.997

	for it in range(iterations):
		var neighbor : Dictionary = {
			"slots": current["slots"].duplicate(true),
			"unit_order": current["unit_order"].duplicate(),
		}

		var op_roll : float = randf()
		if op_roll < 0.6 or not allow_swap:
			_swap_items_in_layout(neighbor)
		else:
			_swap_units_in_layout(neighbor)

		var n_score : float = _evaluate_layout(neighbor, atk_w, def_w, hp_w)
		var delta : float = n_score - cur_score

		if delta > 0 or randf() < exp(delta / maxf(T, 0.001)):
			current = neighbor
			cur_score = n_score
			if cur_score > best_score:
				best = {
					"slots": neighbor["slots"].duplicate(true),
					"unit_order": neighbor["unit_order"].duplicate(),
				}
				best_score = cur_score

		T = maxf(T * alpha, T_min)

	return {
		"slots": best["slots"],
		"unit_order": best["unit_order"],
		"score": best_score,
	}


func _swap_items_in_layout(layout: Dictionary):
	var slots : Array = layout["slots"]
	var flat : Array = []
	for u in range(slots.size()):
		for r in range(slots[u].size()):
			flat.append(Vector2i(u, r))
	if flat.size() < 2: return
	var a : Vector2i = flat[randi() % flat.size()]
	var b : Vector2i = flat[randi() % flat.size()]
	if a == b: return
	var tmp = slots[a.x][a.y]
	slots[a.x][a.y] = slots[b.x][b.y]
	slots[b.x][b.y] = tmp


func _swap_units_in_layout(layout: Dictionary):
	var order : Array = layout["unit_order"]
	var slots : Array = layout["slots"]
	if order.size() < 2: return
	var a : int = randi() % order.size()
	var b : int = randi() % order.size()
	if a == b: return
	var t_order = order[a]; order[a] = order[b]; order[b] = t_order
	var t_slots = slots[a]; slots[a] = slots[b]; slots[b] = t_slots


func _show_auto_config_result_dialog(options: Array, allow_swap: bool):
	if options.is_empty(): return

	var overlay := Control.new()
	overlay.name = "AutoConfigOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 1)
	sb.border_color = Color(0.5, 0.5, 0.6, 1)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "自动配装方案（%s）" % ("含单位交换" if allow_swap else "仅防具重排")
	title.add_theme_font_size_override("font_size", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for opt in options:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var info := Label.new()
		info.text = "[%s] 评分 %.1f" % [opt.get("weight_name", "?"), opt.get("score", 0.0)]
		info.add_theme_font_size_override("font_size", 8)
		info.custom_minimum_size = Vector2(150, 0)
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(info)

		var apply_btn := Button.new()
		apply_btn.text = "应用此方案"
		apply_btn.add_theme_font_size_override("font_size", 8)
		apply_btn.custom_minimum_size = Vector2(90, 20)
		apply_btn.pressed.connect(func():
			_apply_layout(opt)
			_refresh_connectivity()
			_build_unit_columns()
			_sync_all()
			_schedule_build_ui()
			SoundManager.play_select_sound()
			overlay.queue_free()
			_show_detail_in_zone("已应用自动配装方案：%s" % opt.get("weight_name", "?"))
		)
		row.add_child(apply_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 8)
	cancel_btn.custom_minimum_size = Vector2(80, 20)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(cancel_btn)


func _on_claim_all_pending():
	var all_pending : Array = []
	for inst in GameState.pending_sacrifice_rewards:
		all_pending.append({"inst": inst, "src": "sacrifice"})
	for inst in GameState.pending_forge_rewards:
		all_pending.append({"inst": inst, "src": "forge"})

	if all_pending.is_empty(): return

	var sold_gold : int = 0
	var kept_count : int = 0

	for entry in all_pending:
		var inst : ItemInstance = entry["inst"]
		var data : ItemData = ItemManager.get_item_data(inst.item_id)
		if not data: continue

		var new_price : int = inst.get_sell_price()
		var is_unsellable : bool = data.no_sell
		var placed : bool = false

		for u in party:
			if u.is_dead: continue
			for i in range(u.armor_slots.size()):
				if u.armor_slots[i] == null:
					u.armor_slots[i] = inst
					placed = true
					break
			if placed: break

		if not placed:
			var worst_u : UnitData = null
			var worst_idx : int = -1
			var worst_price : int = 999999

			for u in party:
				if u.is_dead: continue
				for i in range(u.armor_slots.size()):
					var old_inst : ItemInstance = u.armor_slots[i]
					if old_inst:
						var old_data = ItemManager.get_item_data(old_inst.item_id)
						if old_data and old_data.no_sell:
							continue
						var p : int = old_inst.get_sell_price()
						if p < worst_price:
							worst_price = p
							worst_u = u
							worst_idx = i

			if worst_u != null and not is_unsellable and new_price >= worst_price:
				_context.add_gold(worst_price)
				sold_gold += worst_price
				worst_u.armor_slots[worst_idx] = inst
				placed = true

		if not placed:
			if is_unsellable:
				kept_count += 1
				continue
			_context.add_gold(new_price)
			sold_gold += new_price

		if entry["src"] == "sacrifice":
			GameState.pending_sacrifice_rewards.erase(inst)
		else:
			GameState.pending_forge_rewards.erase(inst)

	_build_unit_columns()
	_build_pending_slots()
	_update_gold_display()
	_sync_all()

	if sold_gold > 0 and kept_count > 0:
		_show_detail_in_zone("一键领取完成。\n替换/多余装备已折算为 %d 金币。\n★ 有 %d 件熔铸防具因无处装备，已保留在待领取区。" % [sold_gold, kept_count])
	elif kept_count > 0:
		_show_detail_in_zone("一键领取完成。\n★ 有 %d 件熔铸防具因无处装备，已保留在待领取区。" % kept_count)
	elif sold_gold > 0:
		_show_detail_in_zone("一键领取完成。\n替换/多余装备已折算为 %d 金币。" % sold_gold)
	else:
		_show_detail_in_zone("已领取所有装备。")
	SoundManager.play_select_sound()
