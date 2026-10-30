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

var _forge_enter_done : bool = false

const ShopManagerScript = preload(Config.PATHS.SHOP_MANAGER_SCRIPT)
const DETAIL_ZONE_PATH : String = "VBoxContainer/MainHBox/LeftInfoColumn/DetailZone"

@onready var mode_label = get_node_or_null("VBoxContainer/TopBar/ModeLabel")
@onready var gold_label = get_node_or_null("VBoxContainer/GoldLabel")
@onready var close_btn = get_node_or_null("VBoxContainer/BottomHBox/CloseBtn")
@onready var confirm_btn = get_node_or_null("VBoxContainer/BottomHBox/ConfirmBtn")
@onready var unit_container = get_node_or_null("VBoxContainer/MainHBox/LeftVBox/UnitContainer")

@onready var right_container = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer")
@onready var shop_scroll: ScrollContainer = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ShopScroll")
@onready var shop_container: GridContainer = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ShopScroll/ShopContainer")
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
var _pending_container : HBoxContainer = null


func _ready():
	# ★ 强制自身铺满全屏，防止被其他容器拉伸或超出
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
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


func _ensure_aura_tab_btn():
	if _aura_tab_btn and is_instance_valid(_aura_tab_btn):
		return
	if not sacrifice_tab_btn:
		return
	var parent : Node = sacrifice_tab_btn.get_parent()
	if not parent:
		return
	_aura_tab_btn = Button.new()
	_aura_tab_btn.name = "AuraTabBtn"
	_aura_tab_btn.text = "光环"
	_aura_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aura_tab_btn.add_theme_font_size_override("font_size", 8)
	_aura_tab_btn.focus_mode = Control.FOCUS_NONE
	_aura_tab_btn.visible = false
	_aura_tab_btn.clip_text = true
	_aura_tab_btn.pressed.connect(_on_aura_tab_pressed)
	parent.add_child(_aura_tab_btn)
	parent.move_child(_aura_tab_btn, sacrifice_tab_btn.get_index() + 1)


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


func _on_close_pressed():
	if GameState.has_any_pending_rewards():
		var total : int = (
			GameState.pending_sacrifice_rewards.size()
			+ GameState.pending_forge_rewards.size()
		)
		Globals.show_confirm(
			self,
			"还有 %d 件待领取奖励，离开将丢失。\n确定吗？" % total,
			"丢弃并离开", "取消",
			func(): _do_close_with_discard(),
			func(): pass
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


func _check_pending_before_leave() -> bool:
	if GameState.has_pending_sacrifice_rewards():
		_show_detail_in_zone("请先领取熔铸奖励（%d 件）" % GameState.pending_sacrifice_rewards.size())
		return false
	if GameState.has_pending_forge_rewards():
		_show_detail_in_zone("请先领取合成产出（%d 件）" % GameState.pending_forge_rewards.size())
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


# ============ EquipmentConfig.gd ============

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
		main_hbox.custom_minimum_size = Vector2(0, 0) 
		main_hbox.clip_contents = true

	var bottom_hbox = get_node_or_null("VBoxContainer/BottomHBox")
	if bottom_hbox:
		bottom_hbox.size_flags_vertical = Control.SIZE_SHRINK_END
		bottom_hbox.custom_minimum_size = Vector2(0, 20)
		bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# ★ 修复：锁死左侧信息栏宽度，防止文字变长挤爆中间
	var left_info = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn")
	if left_info:
		left_info.custom_minimum_size = Vector2(130, 0) 
		left_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_info.size_flags_horizontal = Control.SIZE_FILL

	var detail_zone = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/DetailZone")
	if detail_zone:
		# ★ 修复：锁死左侧面板高度，防止换行文字把整个 HBox 撑高
		detail_zone.custom_minimum_size = Vector2(130, 150) 
		detail_zone.size_flags_vertical = Control.SIZE_FILL 
		detail_zone.clip_contents = true

	var left_vbox = get_node_or_null("VBoxContainer/MainHBox/LeftVBox")
	if left_vbox:
		left_vbox.custom_minimum_size = Vector2(0, 0)
		# ★ 修复：限制单位栏不能无限撑高，防止整体 UI 上下被挤出
		left_vbox.size_flags_vertical = Control.SIZE_FILL 
		left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_vbox.clip_contents = true

	# ★ 锁死右侧信息栏宽度，解决切换 Tab 导致的左右抖动
	var right_scroll = get_node_or_null("VBoxContainer/MainHBox/RightScroll")
	if right_scroll and right_scroll is ScrollContainer:
		right_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right_scroll.custom_minimum_size = Vector2(140, 0) 
		right_scroll.size_flags_horizontal = Control.SIZE_FILL
		
	if right_container:
		right_container.custom_minimum_size = Vector2(0, 0)
		right_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right_container.size_flags_horizontal = Control.SIZE_FILL

	if shop_scroll:
		shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_scroll.custom_minimum_size = Vector2(0, 0)

	if tab_bar:
		tab_bar.size_flags_horizontal = Control.SIZE_FILL
		for child in tab_bar.get_children():
			if child is Button:
				child.clip_text = false 
				child.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if reset_btn:
		reset_btn.custom_minimum_size = Vector2(120, 20)
		reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reset_btn.size_flags_vertical = Control.SIZE_SHRINK_END
		reset_btn.clip_text = false 
		
	if discard_zone:
		discard_zone.size_flags_vertical = Control.SIZE_SHRINK_END
		discard_zone.custom_minimum_size = Vector2(0, 20)

	var show_passive : bool = (_context.get_context_id() != "arena")
	if relic_section: relic_section.visible = show_passive
	if relic_container: relic_container.visible = show_passive
	if show_passive:
		_build_passive_slots()

	_ensure_pending_section()
	_build_pending_slots()

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
				_forge.display_recipe_info()
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
					_forge.display_recipe_info()
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
					_forge.display_recipe_info()
				"sacrifice":
					_build_sacrifice_panel()
					shop_container.visible = true
				"aura":
					_build_aura_panel()
					shop_container.visible = true

	reset_btn.visible = (current_tab == "arena_shop")
	if reset_btn.visible and shop_manager:
		reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
		
	discard_zone.visible = (current_tab != "arena_forge" and current_tab != "sacrifice" and current_tab != "aura")

	if current_mode == Mode.FORGE or is_shop_rest_mode():
		_setup_forge_narrative_ui()

	close_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	confirm_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	reset_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)

	if reset_btn:
		reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reset_btn.clip_text = false

	_ensure_upgrade_shop_btn()
	_refresh_upgrade_shop_btn()

	_build_unit_columns()
	visible = true

	if shop_container: shop_container.queue_sort()
	if right_container: right_container.queue_sort()
	if tab_bar: tab_bar.queue_sort()


func _build_unit_columns():
	if not unit_container: return
	unit_container.alignment = BoxContainer.ALIGNMENT_CENTER
	for child in unit_container.get_children():
		unit_container.remove_child(child); child.free()

	for i in range(party.size()):
		var unit : UnitData = party[i]
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# ★ 修复：强制从顶部排列，不撑高，防止 UI 溢出
		col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN 
		col.add_theme_constant_override("separation", 2) # ★ 从 6 改小为 2，压缩高度
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		unit_container.add_child(col)

		var icon_ctrl : Control = _create_unit_icon(unit, i)
		if unit.is_dead: icon_ctrl.modulate = Color(0.4, 0.4, 0.4, 1)
		col.add_child(icon_ctrl)

		var weapon_inst : ItemInstance = unit.weapon_slot
		var weapon_btn : Button = _create_item_button(weapon_inst, "weapon", i, -1)
		if unit.is_dead: _disable_button(weapon_btn)
		col.add_child(weapon_btn)

		col.add_child(Style.create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))

		var armor_group := VBoxContainer.new()
		armor_group.add_theme_constant_override("separation", 2) # ★ 从 6 改小为 2
		armor_group.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(armor_group)
		
		for slot_idx in range(unit.armor_slots.size()):
			var armor_btn : Button = _create_item_button(unit.armor_slots[slot_idx], "armor", i, slot_idx)
			if unit.is_dead: _disable_button(armor_btn)
			armor_group.add_child(armor_btn)

		var talent_inst : TalentInstance = unit.talent_slots[0] if unit.talent_slots.size() > 0 else null
		var talent_btn : Button = _create_talent_button(talent_inst, i, 0)
		if unit.is_dead: _disable_button(talent_btn)
		col.add_child(talent_btn)

		var adv_btn : Button = _create_advanced_talent_button(unit, i)
		if unit.is_dead: _disable_button(adv_btn)
		col.add_child(adv_btn)


func _update_gold_display():
	if gold_label:
		gold_label.text = "金币: " + str(_context.get_gold())


func _build_aura_panel():
	_clear_container(shop_container)
	# ★ 改为和商店一致的 3 列网格布局
	shop_container.columns = 3
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

	# 1. 已装备的光环（点击可卸下）
	for aid in equipped:
		var btn := _make_aura_icon_btn(aid, cur_sf, true, empty_slot)
		shop_container.add_child(btn)

	# 2. 候选购买的光环（点击购买）
	for aid in candidates:
		var btn := _make_aura_icon_btn(aid, cur_sf, false, empty_slot)
		shop_container.add_child(btn)

	# 3. 提示信息（如果满槽且还有候选）
	if empty_slot < 0 and not candidates.is_empty():
		var warn := Label.new()
		warn.text = "被动槽已满\n需先卸下光环"
		warn.add_theme_font_size_override("font_size", 6)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.modulate = Color(1.0, 0.6, 0.6)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(40, 0)
		shop_container.add_child(warn)


func _make_aura_icon_btn(aid: String, cur_sf: int, is_equipped: bool, empty_slot: int) -> Button:
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

	# 价格 / 状态文字
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
		btn.pressed.connect(_on_unequip_aura.bind(aid))
	else:
		label.text = "%d魂" % buy_cost
		label.add_theme_color_override("font_color", Color.WHITE)
		# 如果钱不够或者槽满，不可点击且变灰
		if cur_sf < buy_cost or empty_slot < 0:
			btn.modulate = Color(0.5, 0.5, 0.5)
			btn.disabled = true
		else:
			btn.pressed.connect(_on_buy_aura.bind(aid, buy_cost))

	btn.add_child(label)
	
	# 悬停触发右侧信息面板
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
	SoundManager.play_get_item_sound()
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
	right_container.add_child(_pending_section)

	if tab_bar:
		var tab_idx : int = tab_bar.get_index()
		right_container.move_child(_pending_section, tab_idx + 1)

	var title := Label.new()
	title.name = "PendingTitle"
	title.text = "待领取"
	title.add_theme_font_size_override("font_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.modulate = Color(1.0, 0.85, 0.3)
	_pending_section.add_child(title)

	_pending_container = HBoxContainer.new()
	_pending_container.name = "PendingContainer"
	_pending_container.add_theme_constant_override("separation", 3)
	_pending_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_pending_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_section.add_child(_pending_container)


func _build_pending_slots():
	if not _pending_container: return
	for child in _pending_container.get_children():
		_pending_container.remove_child(child)
		child.free()

	var all_pending : Array = []
	for i in range(GameState.pending_sacrifice_rewards.size()):
		all_pending.append({"inst": GameState.pending_sacrifice_rewards[i], "idx": i, "src": "sacrifice"})
	for i in range(GameState.pending_forge_rewards.size()):
		all_pending.append({"inst": GameState.pending_forge_rewards[i], "idx": i, "src": "forge"})

	if all_pending.is_empty():
		if _pending_section: _pending_section.visible = false
		return

	if _pending_section: _pending_section.visible = true

	var title = _pending_section.get_node_or_null("PendingTitle")
	if title:
		title.text = "待领取（%d）" % all_pending.size()

	for entry in all_pending:
		var btn := _create_pending_button(entry["inst"], entry["idx"], entry["src"])
		_pending_container.add_child(btn)


func _create_pending_button(inst: ItemInstance, idx: int, src: String) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.expand_icon = true
	btn.set_meta("slot_type", "pending_reward")
	btn.set_meta("pending_idx", idx)
	btn.set_meta("pending_src", src)
	btn.clip_text = true
	
	if inst:
		var data : ItemData = ItemManager.get_item_data(inst.item_id)
		if data and data.icon:
			btn.icon = data.icon
			btn.text = ""
		else:
			btn.text = data.name if data else inst.item_id
			
		btn.set_meta("item_id", inst.item_id)
		if data:
			btn.modulate = UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE)
		var item_id : String = inst.item_id
		btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_button_hover_exited)
	return btn


func _build_sacrifice_panel():
	_clear_container(shop_container)
	shop_container.columns = 1
	shop_container.add_theme_constant_override("h_separation", 4)
	shop_container.add_theme_constant_override("v_separation", 4)
	shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if shop_scroll:
		shop_scroll.custom_minimum_size = Vector2(0, 0)
		shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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

	var next_count : int = GameState.sacrifice_count + 1
	var preview : Dictionary = SacrificeHelper.get_reward_preview(next_count)
	var preview_text : String = "熔铸一个单位（第 %d 次）\n获得 %d 魂火" % [
		next_count, preview["soul_fire"]
	]
	if preview["relic"]:
		preview_text += "\n★ 额外获得 1 件遗物"

	var title := Label.new()
	title.text = preview_text
	title.add_theme_font_size_override("font_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_container.add_child(title)

	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.text = "熔铸单位"
	btn.custom_minimum_size = Vector2(120, 24)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_on_open_sacrifice_ui)
	shop_container.add_child(btn)


func _on_open_sacrifice_ui():
	if GameState.has_any_pending_rewards():
		_show_detail_in_zone("请先领取所有待领取奖励")
		return
	var scene = load(Config.PATHS.SACRIFICE_UI)
	if not scene:
		push_error("SacrificeUI 未找到")
		return
	var ui = scene.instantiate()
	add_child(ui)
	ui.setup(party, self)
	ui.closed.connect(func():
		_build_unit_columns()
		_build_pending_slots()
		_update_gold_display()
		_schedule_build_ui()
	)


func _do_sacrifice(u: UnitData, _armors_ignored: Array, _discard_count: int):
	var result : Dictionary = SacrificeHelper.do_sacrifice(party, u)

	_sync_all()
	_build_unit_columns()
	_build_pending_slots()
	_update_gold_display()

	var msg : String = "已熔铸：%s\n获得 %d 魂火（实收 %d）" % [
		u.display_name, result["soul_fire"], result["actual_soul_fire"]
	]
	if result["buff_display"] != "":
		msg += "\n★ 全队获得：" + result["buff_display"]
	if result["relic_id"] != "":
		var rd : Dictionary = RelicManager.get_relic_data(result["relic_id"])
		msg += "\n★ 额外遗物：%s" % rd.get("name", result["relic_id"])
	msg += "\n请在上方领取"
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
		u.armor_slots[slot_idx] = inst
	else:
		return

	list.erase(inst)

	SaveManager.auto_save()

	_build_unit_columns()
	_build_pending_slots()
	_sync_all()
	_show_detail_in_zone("已装备：%s → %s" % [item_data.name, u.display_name])

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

	var texture_rect = UnitDataManager.create_idle_texture_rect(unit.unit_name, Vector2(icon_size, icon_size), unit.override_sprite_path)
	
	texture_rect.anchor_left = 0.5
	texture_rect.anchor_right = 0.5
	texture_rect.offset_left = -icon_size / 2.0
	texture_rect.offset_right = icon_size / 2.0
	texture_rect.anchor_top = 0.0
	texture_rect.anchor_bottom = 0.0
	texture_rect.offset_top = y_offset
	texture_rect.offset_bottom = y_offset + icon_size
	
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


func _create_item_button(inst: ItemInstance, slot_type: String, unit_idx: int, slot_idx: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# ★ 核心修复：统一去除默认内边距，让图标能像商店一样撑满 20x20 的框
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
			if slot_type == "weapon" and inst.upgrade_level > 0:
				btn.text = base_name + "+" + str(inst.upgrade_level)
			else:
				btn.text = base_name
	else:
		btn.text = "空"
	btn.set_meta("slot_type", slot_type)
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	btn.set_meta("item_id", inst.item_id if inst else "")
	if inst and inst.item_id != "":
		var item_id : String = inst.item_id
		btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_button_hover_exited)
	return btn


# 与 _create_item_button 完全一致的图标按钮基础样式
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
				# 兜底：极端情况下没有图标，取前两个字，避免完全空白
				btn.text = data.display_name.substr(0, mini(2, data.display_name.length()))
			# ★ 不染色，保留图标原色（与防具图标一致）
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
	# 强制使用和其他防具相同的 BTN_ITEM_SIZE (20x20)
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.clip_text = true
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.set_meta("slot_type", "passive_slot")
	btn.set_meta("passive_index", slot_index)
	
	# ★ 核心修复：清除默认内边距，让图标撑满 20x20
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
		if discard:
			return true
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
	if source_type == "library_weapon": _shop.library_to_weapon(data, target); return
	if source_type == "library_talent" and target_type == "talent": _talent.execute_talent_drop(data, target); return
	if source_type == "talent" and target_type == "talent": _talent.execute_talent_drop(data, target); return
	if source_type == "armor" and target_type == "armor": _shop.swap_armor(data, target)


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
	if source_type == "armor": u.armor_slots[slot_idx] = null
	elif source_type == "talent": _talent.discard_talent(data)
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

	for u in party:
		var key : String = "%s|%s" % [u.unit_name, u.display_name]
		if not target_map.has(key):
			continue
		var tu : UnitData = target_map[key]
		if u.is_dead and tu.is_dead:
			continue
		tu.weapon_slot = _clone_item_inst(u.weapon_slot)
		tu.armor_slots = _clone_inst_array(u.armor_slots)
		tu.max_armor_slots = u.max_armor_slots
		tu.talent_slots = u.talent_slots.duplicate()
		tu.is_dead = u.is_dead
		tu.advanced_talent_id = u.advanced_talent_id

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
		tu.weapon_slot = _clone_item_inst(u.weapon_slot)
		tu.armor_slots = _clone_inst_array(u.armor_slots)
		tu.max_armor_slots = u.max_armor_slots
		tu.talent_slots = u.talent_slots.duplicate()
		tu.is_dead = u.is_dead
		tu.advanced_talent_id = u.advanced_talent_id


static func _clone_item_inst(src: ItemInstance) -> ItemInstance:
	if src == null: return null
	var inst = ItemInstance.new()
	inst.item_id = src.item_id
	inst.count = src.count
	inst.upgrade_level = src.upgrade_level
	return inst


static func _clone_inst_array(src: Array) -> Array:
	var out : Array = []
	for s in src: out.append(_clone_item_inst(s))
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
	
	# ★ 确保按钮在正确的 tab 显示
	reset_btn.visible = (tab == "arena_shop")
	if reset_btn.visible and shop_manager:
		reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
		
	discard_zone.visible = (tab != "arena_forge" and tab != "sacrifice" and tab != "aura")
	
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
		if btn and btn is Button: _drag.start_drag(btn as Button)
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


func _build_shop_items(): _shop.build_shop_items()
func _build_weapon_grid(container: GridContainer): _shop.build_weapon_grid(container)
func _on_reset_shop_pressed(): _shop.on_reset_shop_pressed()

func _build_talent_grid(container: GridContainer): _talent.build_talent_grid(container)
func _get_talent_display_unit_type() -> String: return _talent._get_talent_display_unit_type()
func _use_context_units() -> Array: return _talent._use_context_units()
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

	_upgrade_shop_btn = Style.create_styled_button(Style.FONT_LARGE, Vector2(120, 24))
	_upgrade_shop_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_upgrade_shop_btn.size_flags_vertical = Control.SIZE_SHRINK_END
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
	# ★ 保留 disabled：转职专属词条不可替换/拖拽（功能不变）
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

	# ★ 不染色；disabled 状态由引擎自动做暗化，视觉上就能区分"不可操作"
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
