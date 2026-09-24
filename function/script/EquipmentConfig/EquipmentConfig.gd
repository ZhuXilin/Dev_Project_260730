extends Panel

enum Mode { DEPLOY, MAP, SHOP, FORGE, ARENA_REST, MAP_SHOP_REST }

const Style = preload("res://function/script/EquipmentConfig/EquipmentConfigStyle.gd")

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

const ShopManagerScript = preload(Config.PATHS.SHOP_MANAGER_SCRIPT)

@onready var mode_label = $VBoxContainer/TopBar/ModeLabel
@onready var gold_label = $VBoxContainer/GoldLabel
@onready var close_btn = $VBoxContainer/BottomHBox/CloseBtn
@onready var confirm_btn = $VBoxContainer/BottomHBox/ConfirmBtn
@onready var unit_container = $VBoxContainer/MainHBox/LeftVBox/UnitContainer
@onready var right_container = $VBoxContainer/MainHBox/RightContainer
@onready var shop_scroll: ScrollContainer = $VBoxContainer/MainHBox/RightContainer/ShopScroll
@onready var shop_container: GridContainer = $VBoxContainer/MainHBox/RightContainer/ShopScroll/ShopContainer
@onready var reset_btn = $VBoxContainer/MainHBox/RightContainer/ResetBtn
@onready var discard_zone = $VBoxContainer/MainHBox/RightContainer/DiscardZone
@onready var tab_bar = $VBoxContainer/MainHBox/RightContainer/TabBar
@onready var weapon_tab_btn = $VBoxContainer/MainHBox/RightContainer/TabBar/WeaponTabBtn
@onready var talent_tab_btn = $VBoxContainer/MainHBox/RightContainer/TabBar/TalentTabBtn
@onready var relic_section: VBoxContainer = $VBoxContainer/MainHBox/LeftInfoColumn/RelicSection
@onready var relic_container: HBoxContainer = $VBoxContainer/MainHBox/LeftInfoColumn/RelicSection/RelicContainer
@onready var refine_tab_btn : Button = $VBoxContainer/MainHBox/RightContainer/TabBar/RefineTabBtn
@onready var sacrifice_tab_btn : Button = $VBoxContainer/MainHBox/RightContainer/TabBar/SacrificeTabBtn

# ---- 待领取区（动态创建到 RightContainer） ----
var _pending_section : VBoxContainer = null
var _pending_container : HBoxContainer = null
var _revive_btn : Button = null


func _ready():
	_forge = EquipmentConfigForge.new(self)
	_drag = EquipmentConfigDrag.new(self)
	_detail = EquipmentConfigDetail.new(self)
	_shop = EquipmentConfigShop.new(self)
	_talent = EquipmentConfigTalent.new(self)
	if weapon_tab_btn:
		weapon_tab_btn.pressed.connect(_on_weapon_tab_pressed)
	if talent_tab_btn:
		talent_tab_btn.pressed.connect(_on_talent_tab_pressed)
	if refine_tab_btn:
		refine_tab_btn.pressed.connect(_on_refine_tab_pressed)
		refine_tab_btn.visible = false
	if sacrifice_tab_btn:
		sacrifice_tab_btn.visible = false


# ============================================================
#  模式 / Tab 判断辅助
# ============================================================
func _is_shop_rest_mode() -> bool:
	return current_mode == Mode.ARENA_REST or current_mode == Mode.MAP_SHOP_REST

func is_forge_mode() -> bool:
	return current_mode == Mode.FORGE

func is_shop_rest_mode() -> bool:
	return _is_shop_rest_mode()

func _on_refine_tab_pressed(): _switch_tab("refine")
func _on_weapon_tab_pressed():
	if _is_shop_rest_mode(): _switch_tab("arena_shop")
	elif current_mode == Mode.FORGE: _switch_tab("arena_shop")
	else: _switch_tab("weapon")
func _on_talent_tab_pressed():
	if _is_shop_rest_mode(): _switch_tab("arena_forge")
	elif current_mode == Mode.FORGE: _switch_tab("arena_forge")
	else: _switch_tab("talent")
func _on_sacrifice_tab_pressed(): _switch_tab("sacrifice")


func init(units: Array, slot: int, mode: Mode, context: EquipContext = null):
	var canvas_layer : Node = get_parent()
	if canvas_layer is CanvasLayer:
		if context != null and context.get_context_id() == "arena":
			(canvas_layer as CanvasLayer).layer = 30
		else:
			(canvas_layer as CanvasLayer).layer = 20

	selected_units = units
	target_slot = slot
	current_mode = mode
	_context = context if context else MainGameEquipContext.new()

	if mode == Mode.SHOP or _is_shop_rest_mode() or mode == Mode.FORGE:
		if not shop_manager:
			shop_manager = ShopManagerScript.new()
			add_child(shop_manager)
			shop_manager.shop_updated.connect(_on_shop_updated)
		shop_manager.set_context(_context)
		shop_manager.generate_shop_items()
		shop_manager.reset_count = 0

	if mode == Mode.FORGE or _is_shop_rest_mode():
		_forge.init_slots()

	if _is_shop_rest_mode():
		current_tab = "arena_shop"

	_copy_party_data()
	_build_ui()

func _on_shop_updated():
	_update_gold_display()
	_schedule_build_ui()

func _on_close_pressed():
	if not _check_pending_before_leave():
		return

	if _is_shop_rest_mode() and current_tab == "arena_forge":
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
#  待领取检查
# ============================================================
func _check_pending_before_leave() -> bool:
	if GameState.has_pending_sacrifice_rewards():
		_show_detail_in_zone("请先领取熔铸奖励（%d 件）" % GameState.pending_sacrifice_rewards.size())
		return false
	if GameState.has_pending_forge_rewards():
		_show_detail_in_zone("请先领取合成产出（%d 件）" % GameState.pending_forge_rewards.size())
		return false
	return true


# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	if _is_closing: return
	if _is_building_ui: return
	_is_building_ui = true
	_build_ui_inner()
	_is_building_ui = false

func _build_ui_inner():
	var main_hbox = $VBoxContainer/MainHBox
	var bottom_hbox = $VBoxContainer/BottomHBox
	if main_hbox:
		main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if bottom_hbox:
		bottom_hbox.custom_minimum_size = Vector2(0, 40)
		bottom_hbox.size_flags_vertical = Control.SIZE_FILL
		bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

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
	discard_zone.visible = false
	reset_btn.visible = false
	tab_bar.visible = false
	right_container.visible = true

	weapon_tab_btn.visible = false
	talent_tab_btn.visible = false
	if refine_tab_btn: refine_tab_btn.visible = false
	if sacrifice_tab_btn: sacrifice_tab_btn.visible = false

	var left_column : VBoxContainer = $VBoxContainer/MainHBox/LeftVBox
	if left_column:
		left_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER

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
			weapon_tab_btn.visible = true
			weapon_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			weapon_tab_btn.text = "武器库"
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "特技库"
			if refine_tab_btn:
				refine_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				refine_tab_btn.visible = (_context.get_context_id() == "main_game")
			if current_tab == "" or current_tab.begins_with("arena_") or current_tab == "sacrifice":
				current_tab = "weapon"
			_update_tab_style()
			if current_tab == "weapon": _build_weapon_grid(shop_container)
			elif current_tab == "talent": _build_talent_grid(shop_container)
			else: _build_refine_grid(shop_container)
			shop_container.visible = true
			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_ensure_revive_button()
			_refresh_revive_button()

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
			if refine_tab_btn:
				refine_tab_btn.visible = true
				refine_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				refine_tab_btn.text = "精炼库"
			current_tab = "talent"
			_update_tab_style()
			_build_talent_grid(shop_container)
			shop_container.visible = true
			discard_zone.visible = true
			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_ensure_revive_button()
			_refresh_revive_button()

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
			if refine_tab_btn: refine_tab_btn.visible = false
			if current_tab == "" or (not current_tab.begins_with("arena_") and current_tab != "sacrifice"):
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
				reset_btn.visible = true
				reset_btn.text = "清空插槽"
				_forge.display_recipe_info()
				discard_zone.visible = false
			else:
				confirm_btn.disabled = false
				confirm_btn.modulate = Color.WHITE
				_build_shop_items()
				shop_container.visible = true
				reset_btn.visible = true
				if shop_manager:
					reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
				discard_zone.visible = true

			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

		Mode.MAP_SHOP_REST:
			mode_label.text = "铁匠商店"
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
			if refine_tab_btn: refine_tab_btn.visible = false
			if sacrifice_tab_btn:
				sacrifice_tab_btn.visible = true
				sacrifice_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			if current_tab == "" or (not current_tab.begins_with("arena_") and current_tab != "sacrifice"):
				current_tab = "arena_shop"
			_update_tab_style()
			_forge.cleanup()

			match current_tab:
				"arena_forge":
					_forge.build_forge_slots()
					shop_container.visible = true
					reset_btn.visible = true
					reset_btn.text = "清空插槽"
					_forge.display_recipe_info()
					discard_zone.visible = true          # ★ 铁匠铺也显示
				"sacrifice":
					_build_sacrifice_panel()
					shop_container.visible = true
					reset_btn.visible = false
					discard_zone.visible = true          # ★ 熔铸也显示
				_:
					_build_shop_items()
					shop_container.visible = true
					reset_btn.visible = true
					if shop_manager:
						reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
					discard_zone.visible = true
			_refresh_bottom_buttons()
			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

		Mode.SHOP:
			mode_label.text = "商店"
			close_btn.visible = true
			close_btn.text = "继续探索"
			confirm_btn.visible = false
			gold_label.visible = true
			tab_bar.visible = false
			_build_shop_items()
			shop_container.visible = true
			reset_btn.visible = true
			if shop_manager:
				reset_btn.text = "重置商店 (" + str(shop_manager.get_reset_cost()) + "G)"
			discard_zone.visible = true
			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

		Mode.FORGE:
			mode_label.text = "铁匠铺"
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
			if refine_tab_btn: refine_tab_btn.visible = false
			if sacrifice_tab_btn:
				sacrifice_tab_btn.visible = true
				sacrifice_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			if current_tab == "" or (not current_tab in ["arena_shop", "arena_forge", "sacrifice"]):
				current_tab = "arena_forge"

			_update_tab_style()
			_forge.cleanup()

			match current_tab:
				"arena_shop":
					_build_shop_items()
					shop_container.visible = true
					reset_btn.visible = true
					if shop_manager:
						reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
					discard_zone.visible = true          # ★ 铁匠铺商店也显示
				"arena_forge":
					_forge.build_forge_slots()
					shop_container.visible = true
					reset_btn.visible = true
					reset_btn.text = "清空插槽"
					discard_zone.visible = true          # ★ 铁匠铺也显示
					_forge.display_recipe_info()
				"sacrifice":
					_build_sacrifice_panel()
					shop_container.visible = true
					reset_btn.visible = false
					discard_zone.visible = true          # ★ 熔铸也显示

			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	close_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	confirm_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	reset_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)

	_build_unit_columns()
	visible = true

	# ★ 强制重排（解决切换标签后按钮不显示）
	if shop_container:
		shop_container.queue_sort()
	if right_container:
		right_container.queue_sort()
	if tab_bar:
		tab_bar.queue_sort()

func _update_gold_display():
	if gold_label:
		gold_label.text = "金币: " + str(_context.get_gold())


# ============================================================
#  待领取区（加到 RightContainer，TabBar 之后）
# ============================================================
func _ensure_pending_section():
	if _pending_container and is_instance_valid(_pending_container):
		return
	if not right_container: return

	_pending_section = VBoxContainer.new()
	_pending_section.name = "PendingSection"
	_pending_section.add_theme_constant_override("separation", 2)
	_pending_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_container.add_child(_pending_section)

	# 移到 TabBar 之后
	if tab_bar:
		var tab_idx : int = tab_bar.get_index()
		right_container.move_child(_pending_section, tab_idx + 1)

	var title := Label.new()
	title.name = "PendingTitle"
	title.text = "待领取"                              # ★ 短标题
	title.add_theme_font_size_override("font_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # ★ 允许换行
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # ★ 撑满，不强制宽度
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
	# ★ 立即 free，避免 queue_free 残留
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
	btn.set_meta("slot_type", "pending_reward")
	btn.set_meta("pending_idx", idx)
	btn.set_meta("pending_src", src)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if inst:
		var data : ItemData = ItemManager.get_item_data(inst.item_id)
		btn.text = data.name if data else inst.item_id
		btn.set_meta("item_id", inst.item_id)
		if data:
			btn.modulate = UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE)
		var item_id : String = inst.item_id
		btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_button_hover_exited)
	return btn


# ============================================================
#  复活圣油按钮
# ============================================================
func _ensure_revive_button():
	if _revive_btn and is_instance_valid(_revive_btn):
		_revive_btn.visible = (current_mode == Mode.MAP or current_mode == Mode.DEPLOY)
		return
	if current_mode != Mode.MAP and current_mode != Mode.DEPLOY:
		return
	var left_col : VBoxContainer = $VBoxContainer/MainHBox/LeftInfoColumn
	if not left_col: return
	_revive_btn = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	_revive_btn.custom_minimum_size = Vector2(80, 16)
	_revive_btn.pressed.connect(_on_revive_pressed)
	left_col.add_child(_revive_btn)
	var relic_idx : int = relic_section.get_index() if relic_section else 0
	left_col.move_child(_revive_btn, relic_idx + 1)


func _refresh_revive_button():
	if not _revive_btn or not is_instance_valid(_revive_btn):
		return
	var count : int = RefineManager.get_count("revive_potion")
	if count <= 0:
		_revive_btn.visible = false
		return
	_revive_btn.visible = true
	var dead_count : int = GameState.get_dead_party().size()
	if dead_count <= 0:
		_revive_btn.text = "复活圣油 ×%d（无阵亡）" % count
		_revive_btn.disabled = true
		_revive_btn.modulate = Color(0.5, 0.5, 0.5)
	else:
		_revive_btn.text = "使用复活圣油 ×%d" % count
		_revive_btn.disabled = false
		_revive_btn.modulate = Color.WHITE


func _on_revive_pressed():
	if RefineManager.get_count("revive_potion") <= 0:
		return
	var dead : Array = GameState.get_dead_party()
	if dead.is_empty():
		return
	_open_revive_target_selector(dead)


func _open_revive_target_selector(dead_units: Array):
	var dlg := AcceptDialog.new()
	dlg.title = "选择要复活的单位"
	for ud in dead_units:
		var btn := Button.new()
		btn.text = "%s（%s）" % [ud.display_name, UnitDataManager.get_unit_type_display_name(ud.unit_name)]
		btn.pressed.connect(_confirm_revive.bind(ud.unit_name, ud.display_name, dlg))
		dlg.add_child(btn)
	add_child(dlg)
	dlg.popup_centered(Vector2(260, 180))


func _confirm_revive(unit_name: String, display_name: String, dlg: Window):
	dlg.queue_free()
	if RefineManager.get_count("revive_potion") <= 0:
		return
	if GameState.revive_unit(unit_name, display_name):
		GameState.refined_items["revive_potion"] -= 1
		if GameState.refined_items["revive_potion"] <= 0:
			GameState.refined_items.erase("revive_potion")
		SaveManager.auto_save()
		_sync_all()
		_build_unit_columns()
		_refresh_revive_button()
		_show_detail_in_zone("已复活：%s" % display_name)


# ============================================================
#  熔铸标签
# ============================================================
func _build_sacrifice_panel():
	_clear_container(shop_container)
	shop_container.columns = 1
	shop_container.add_theme_constant_override("h_separation", 4)
	shop_container.add_theme_constant_override("v_separation", 4)
	shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ★ 熔铸面板：ShopScroll 撑满，不让内容溢出
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

	# ★ 标题：自动换行，不强制宽度
	var title := Label.new()
	title.text = "熔铸一个单位\n获得 1000 金币 + 3 件史诗防具"
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


# ============================================================
#  熔铸核心逻辑
# ============================================================
func _do_sacrifice(u: UnitData, _armors_ignored: Array, _discard_count: int):
	u.is_dead = true
	u.hit_points = 0

	EconomyManager.add_temp_gold(1000)

	var rewards : Array = _generate_sacrifice_rewards(3)
	for inst in rewards:
		GameState.pending_sacrifice_rewards.append(inst)

	print("[熔铸] %s 被冻结，获得 1000 金币 + %d 件史诗防具" % [u.display_name, rewards.size()])

	SaveManager.auto_save()

	_sync_all()
	_build_unit_columns()
	_build_pending_slots()
	_update_gold_display()
	_show_detail_in_zone("已熔铸：%s\n获得 1000 金币 + %d 件史诗防具\n请在上方领取" % [u.display_name, rewards.size()])


func _generate_sacrifice_rewards(count: int) -> Array:
	var result : Array = []
	var candidates : Array = []
	for item_id in ItemManager.get_all_item_ids():
		var item_data = ItemManager.get_item_data(item_id)
		if not item_data: continue
		if item_data.type != "armor": continue
		if item_data.quality != "epic": continue
		candidates.append(item_id)

	if candidates.is_empty():
		for item_id in ItemManager.get_all_item_ids():
			var item_data = ItemManager.get_item_data(item_id)
			if not item_data: continue
			if item_data.type != "armor": continue
			if item_data.quality != "rare": continue
			candidates.append(item_id)

	if candidates.is_empty():
		return result

	for i in range(count):
		var pick : String = candidates[randi() % candidates.size()]
		var inst := ItemInstance.new()
		inst.item_id = pick
		inst.count = 1
		result.append(inst)
	return result


# ============================================================
#  领取待领取奖励
# ============================================================
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
		if item_data.type != "weapon": return
		u.weapon_slot = inst
	elif target_type == "armor":
		if item_data.type != "armor": return
		var slot_idx : int = target.get_meta("slot_idx", -1)
		if slot_idx < 0 or slot_idx >= u.armor_slots.size(): return
		u.armor_slots[slot_idx] = inst
	else:
		return

	# ★ 用 erase(inst)，不依赖索引（避免错位）
	list.erase(inst)

	SaveManager.auto_save()

	_build_unit_columns()
	_build_pending_slots()
	_sync_all()
	_show_detail_in_zone("已装备：%s → %s" % [item_data.name, u.display_name])


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


# ============================================================
#  单位图标（含 idle 动画）
# ============================================================
func _create_unit_icon(unit: UnitData, unit_idx: int) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP

	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(0, 28)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var frames_path = UnitDataManager.get_sprite_frames_path(unit.unit_name)
	if unit.override_sprite_path != "":
		frames_path = unit.override_sprite_path
	if frames_path != "" and ResourceLoader.exists(frames_path):
		var frames = load(frames_path) as SpriteFrames
		if frames and frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
			texture_rect.texture = frames.get_frame_texture("idle", 0)
			_attach_idle_animator(texture_rect, frames)
	wrapper.add_child(texture_rect)

	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 5)
	if unit.is_dead:
		name_label.modulate = Color(0.4, 0.4, 0.4, 1)
	wrapper.add_child(name_label)

	wrapper.mouse_entered.connect(_on_unit_hover_entered.bind(unit_idx))
	wrapper.mouse_exited.connect(_on_unit_hover_exited)

	return wrapper


func _attach_idle_animator(tex_rect: TextureRect, frames: SpriteFrames):
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	tex_rect.add_child(timer)

	var frame_count := frames.get_frame_count("idle")
	var idx := {"value": 0}
	timer.timeout.connect(func():
		if not is_instance_valid(tex_rect):
			return
		idx["value"] = (idx["value"] + 1) % frame_count
		var t = frames.get_frame_texture("idle", idx["value"])
		if t:
			tex_rect.texture = t
	)


# ============================================================
#  单位列
# ============================================================
func _build_unit_columns():
	for child in unit_container.get_children():
		unit_container.remove_child(child); child.free()

	for i in range(party.size()):
		var unit : UnitData = party[i]
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		unit_container.add_child(col)

		var icon_ctrl : Control = _create_unit_icon(unit, i)
		if unit.is_dead:
			icon_ctrl.modulate = Color(0.4, 0.4, 0.4, 1)
		col.add_child(icon_ctrl)

		col.add_child(Style.create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))

		var weapon_inst : ItemInstance = unit.weapon_slot
		var weapon_btn : Button = _create_item_button(weapon_inst, "weapon", i, -1)
		if unit.is_dead: _disable_button(weapon_btn)
		col.add_child(weapon_btn)

		col.add_child(Style.create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))

		for slot_idx in range(unit.armor_slots.size()):
			var armor_btn : Button = _create_item_button(unit.armor_slots[slot_idx], "armor", i, slot_idx)
			if current_mode == Mode.DEPLOY: armor_btn.disabled = true
			if unit.is_dead: _disable_button(armor_btn)
			col.add_child(armor_btn)

		col.add_child(Style.create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))
		col.add_child(Style.create_label("特技", Style.FONT_SMALL))
		var talent_inst : TalentInstance = unit.talent_slots[0] if unit.talent_slots.size() > 0 else null
		var talent_btn : Button = _create_talent_button(talent_inst, i, 0)
		if unit.is_dead: _disable_button(talent_btn)
		col.add_child(talent_btn)


func _disable_button(btn: Button):
	btn.disabled = true
	btn.modulate = Color(0.4, 0.4, 0.4, 1)


func _on_unit_hover_entered(unit_idx: int) -> void:
	if unit_idx < 0 or unit_idx >= party.size(): return
	var unit : UnitData = party[unit_idx]

	var display : String = unit.display_name if unit.display_name != "" else unit.unit_name
	var type_name : String = UnitDataManager.get_unit_type_display_name(unit.unit_name)

	var lines : Array = []
	lines.append("%s（%s）" % [display, type_name])
	if unit.is_dead:
		lines.append("【已冻结】可通过圣坛或复活圣油解冻")
	lines.append("")

	lines.append("HP: %d / %d" % [unit.hit_points, unit.max_hp])
	lines.append("力量: %d    灵巧: %d" % [unit.strength, unit.dexterity])
	lines.append("智力: %d    信仰: %d" % [unit.intelligence, unit.faith])
	lines.append("感应: %d    移动力: %d" % [unit.arcane, unit.move_range])

	lines.append("")
	if unit.weapon_slot:
		var wdata : ItemData = ItemManager.get_item_data(unit.weapon_slot.item_id)
		if wdata:
			var lv_txt : String = ""
			if unit.weapon_slot.upgrade_level > 0:
				lv_txt = "+%d" % unit.weapon_slot.upgrade_level
			lines.append("武器: %s%s" % [wdata.name, lv_txt])
			if wdata.type == "weapon":
				lines.append("  攻击 %d  射程 %d~%d" % [
					wdata.base_attack, wdata.min_attack_range, wdata.attack_range])
	else:
		lines.append("武器: 无")

	var armor_names : Array = []
	for s in unit.armor_slots:
		if s:
			var adata : ItemData = ItemManager.get_item_data(s.item_id)
			if adata:
				armor_names.append(adata.name)
	if armor_names.size() > 0:
		lines.append("防具: " + ", ".join(armor_names))
	else:
		lines.append("防具: 无")

	var talent_names : Array = []
	for t in unit.talent_slots:
		if t and t.is_active:
			var tdata : TalentData = TalentManager.get_talent_data(t.talent_id)
			if tdata:
				talent_names.append(tdata.display_name)
	if talent_names.size() > 0:
		lines.append("特技: " + ", ".join(talent_names))

	_show_detail_in_zone("\n".join(lines))


func _on_unit_hover_exited() -> void:
	_detail.clear_zone()

func _create_item_button(inst: ItemInstance, slot_type: String, unit_idx: int, slot_idx: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	if inst:
		var base_name : String = _get_item_name(inst)
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

func _create_talent_button(inst: TalentInstance, unit_idx: int, slot_idx: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_TINY, Style.BTN_TALENT_SIZE)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.set_meta("slot_type", "talent")
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	if inst and inst.is_active:
		var data : TalentData = TalentManager.get_talent_data(inst.talent_id)
		if data:
			var unit_name : String = ""
			if unit_idx >= 0 and unit_idx < party.size():
				unit_name = party[unit_idx].unit_name
			if unit_name != "":
				var lv : int = TalentManager.get_talent_level(unit_name, inst.talent_id)
				if TalentManager.is_talent_max_level(unit_name, inst.talent_id):
					btn.text = "%s Lv%d MAX" % [data.display_name, lv]
				else:
					var cur_exp : int = TalentManager.get_talent_exp_in_level(unit_name, inst.talent_id)
					var need_exp : int = TalentManager.get_level_required_exp(unit_name, inst.talent_id)
					btn.text = "%s Lv%d %d/%d" % [data.display_name, lv, cur_exp, need_exp]
			else:
				btn.text = data.display_name
			btn.modulate = Style.get_rarity_color(data.rarity)
			btn.set_meta("talent_id", inst.talent_id)
			btn.mouse_entered.connect(_on_talent_hover_entered.bind(inst.talent_id))
			btn.mouse_exited.connect(_on_talent_hover_exited)
		else:
			btn.text = "空"; btn.modulate = Color(0.5, 0.5, 0.5, 1); btn.set_meta("talent_id", "")
	else:
		btn.text = "空"; btn.modulate = Color(0.5, 0.5, 0.5, 1); btn.set_meta("talent_id", "")
	return btn


# ============================================================
#  被动槽
# ============================================================
func _build_passive_slots():
	if not relic_container: return
	for child in relic_container.get_children(): relic_container.remove_child(child); child.free()
	var passives : Array = _context.get_passives()
	for i in range(MAX_PASSIVE_SLOTS):
		var inst : Variant = passives[i] if i < passives.size() else null
		var btn : Button = _create_passive_button(inst, i)
		relic_container.add_child(btn)

func _create_passive_button(inst: Variant, slot_index: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_RELIC_SIZE)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.set_meta("slot_type", "passive_slot")
	btn.set_meta("passive_index", slot_index)
	if inst == null:
		btn.text = "空"; btn.set_meta("item_id", ""); btn.set_meta("refine_id", "")
	elif inst is ItemInstance:
		var item_inst : ItemInstance = inst
		var data : Dictionary = RelicManager.get_relic_data(item_inst.item_id)
		if not data.is_empty():
			btn.text = data.get("name", "?")
			btn.set_meta("item_id", item_inst.item_id); btn.set_meta("refine_id", "")
			btn.mouse_entered.connect(_on_relic_hover_entered.bind(item_inst.item_id))
			btn.mouse_exited.connect(_on_relic_hover_exited)
		else:
			btn.text = "?"; btn.set_meta("item_id", ""); btn.set_meta("refine_id", "")
	elif inst is Dictionary:
		var inst_dict : Dictionary = inst
		var refine_id : String = inst_dict.get("refine_id", "")
		var recipe : Dictionary = RefineManager.get_recipe(refine_id)
		if not recipe.is_empty():
			btn.text = recipe.get("name", refine_id)
			btn.set_meta("item_id", ""); btn.set_meta("refine_id", refine_id)
			btn.mouse_entered.connect(_on_refine_hover_entered.bind(refine_id))
			btn.mouse_exited.connect(_on_refine_hover_exited)
		else:
			btn.text = "?"; btn.set_meta("item_id", ""); btn.set_meta("refine_id", "")
	return btn


# ============================================================
#  格数预算辅助
# ============================================================
func _inst_slots(inst: ItemInstance) -> int:
	if inst == null: return 0
	var data : ItemData = ItemManager.get_item_data(inst.item_id)
	if not data: return 1
	var sc : int = data.slot_count
	return max(1, sc)

func _used_slots_of(unit: UnitData) -> int:
	var used : int = 0
	for slot in unit.armor_slots:
		if slot == null: continue
		used += _inst_slots(slot)
	return used

func _used_slots_excluding(unit: UnitData, exclude_slots: Array) -> int:
	var used : int = 0
	for i in range(unit.armor_slots.size()):
		if i in exclude_slots: continue
		used += _inst_slots(unit.armor_slots[i])
	return used

func _can_equip_armor_to(unit_idx: int, item_id: String, exclude_slot_idx: int = -1) -> bool:
	if unit_idx < 0 or unit_idx >= party.size(): return false
	if item_id == "": return true
	var data : ItemData = ItemManager.get_item_data(item_id)
	if not data: return false
	var need : int = _inst_slots_for_id(item_id)
	var unit : UnitData = party[unit_idx]
	var exclude : Array = []
	if exclude_slot_idx >= 0: exclude.append(exclude_slot_idx)
	var used : int = _used_slots_excluding(unit, exclude)
	return used + need <= unit.max_armor_slots

func _inst_slots_for_id(item_id: String) -> int:
	var data : ItemData = ItemManager.get_item_data(item_id)
	if not data: return 1
	var sc : int = data.slot_count
	return max(1, sc)

func _get_item_name(inst: ItemInstance) -> String:
	if not inst: return ""
	var data : ItemData = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id


# ============================================================
#  合法性
# ============================================================
func _is_valid_drop(data: Dictionary, target: Control) -> bool:
	var source_type : String = data["slot_type"]
	var target_type : String = target.get_meta("slot_type", "")
	var discard : bool = target == discard_zone

	var tgt_uidx : int = target.get_meta("unit_idx", -1)
	if tgt_uidx >= 0 and tgt_uidx < party.size():
		if party[tgt_uidx].is_dead:
			return false
	var src_uidx : int = data.get("unit_idx", -1)
	if src_uidx >= 0 and src_uidx < party.size():
		if party[src_uidx].is_dead:
			return false

	# ★ 待领取 → 单位槽
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
			return idata.type == "weapon"
		elif target_type == "armor":
			if idata.type != "armor": return false
			var ts_p : int = target.get_meta("slot_idx", -1)
			if ts_p < 0 or ts_p >= party[tu_p].armor_slots.size(): return false
			var need_p : int = _inst_slots(inst)
			var used_p : int = _used_slots_excluding(party[tu_p], [ts_p])
			return used_p + need_p <= party[tu_p].max_armor_slots
		return false

	# 被动槽
	if source_type == "passive_slot":
		if target_type == "passive_slot": return true
		if discard: return true
		return false
	if target_type == "passive_slot":
		if source_type == "library_refine": return true
		return false

	if current_mode == Mode.FORGE and current_tab != "arena_shop":
		return _forge.is_valid_forge_drop(data, target)
	if _is_shop_rest_mode() and current_tab == "arena_forge":
		return _forge.is_valid_forge_drop(data, target)

	if discard and source_type in ["library_talent", "talent"]: return false

	if current_mode == Mode.DEPLOY:
		if discard: return false
		if source_type == "library_weapon": return target_type == "weapon"
		if source_type == "weapon" and target_type == "weapon": return true
		if source_type == "library_talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		return false

	if current_mode == Mode.MAP:
		if discard:
			if source_type == "armor": return true
			return false
		if source_type == "weapon" and target_type == "weapon": return true
		if source_type == "armor" and target_type == "armor":
			return _check_armor_swap_budget(data, target)
		if source_type == "library_talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		return false

	var is_shop_ctx = (
		current_mode == Mode.SHOP
		or (current_mode == Mode.FORGE and current_tab == "arena_shop")
		or (_is_shop_rest_mode() and current_tab == "arena_shop")
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
				if target_type != "weapon": return false
				if tu2 < 0: return false
				return true
			elif item_data.type == "armor":
				if target_type != "armor": return false
				if tu2 < 0 or ts2 < 0: return false
				return _can_equip_armor_to(tu2, item_data.id, ts2)
			return false
		if source_type == "weapon" and target_type == "weapon": return true
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

	if su == tu:
		var unit : UnitData = party[su]
		var src_inst : ItemInstance = unit.armor_slots[ss]
		var tgt_inst : ItemInstance = unit.armor_slots[ts]
		var exclude : Array = [ss, ts]
		var rest : int = _used_slots_excluding(unit, exclude)
		var need : int = _inst_slots(src_inst) + _inst_slots(tgt_inst)
		return rest + need <= unit.max_armor_slots
	else:
		var src_unit : UnitData = party[su]
		var tgt_unit : UnitData = party[tu]
		var src_inst : ItemInstance = src_unit.armor_slots[ss]
		var tgt_inst : ItemInstance = tgt_unit.armor_slots[ts]
		var su_used : int = _used_slots_excluding(src_unit, [ss])
		var su_need : int = _inst_slots(tgt_inst)
		if su_used + su_need > src_unit.max_armor_slots: return false
		var tu_used : int = _used_slots_excluding(tgt_unit, [ts])
		var tu_need : int = _inst_slots(src_inst)
		if tu_used + tu_need > tgt_unit.max_armor_slots: return false
		return true


# ============================================================
#  执行 drop
# ============================================================
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
	if source_type == "library_refine" and target_type == "passive_slot":
		_equip_refine_to_slot(data, target); return

	if current_mode == Mode.FORGE and current_tab != "arena_shop":
		_forge.execute_forge_drop(data, target); return
	if _is_shop_rest_mode() and current_tab == "arena_forge":
		_forge.execute_forge_drop(data, target); return

	var discard : bool = target == discard_zone

	if discard and source_type == "talent": _talent.execute_talent_remove(data); return
	if discard: _discard_item(data); return
	if source_type == "shop_item": _shop.buy_shop_item(data, target); return
	if source_type == "library_weapon": _shop.library_to_weapon(data, target); return
	if source_type == "library_talent" and target_type == "talent": _talent.execute_talent_drop(data, target); return
	if source_type == "talent" and target_type == "talent": _talent.execute_talent_drop(data, target); return
	if source_type == "weapon" and target_type == "weapon": _shop.swap_weapons(data, target)
	elif source_type == "armor" and target_type == "armor": _shop.swap_armor(data, target)


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

func _equip_refine_to_slot(data: Dictionary, target: Control):
	var refine_id : String = data.get("refine_id", "")
	var slot_idx : int = target.get_meta("passive_index", -1)
	if refine_id == "" or slot_idx < 0: return
	if RefineManager.get_count(refine_id) <= 0: return
	var passives : Array = _context.get_passives()
	for p in passives:
		if p != null and p is Dictionary:
			var p_dict : Dictionary = p
			if p_dict.get("refine_id", "") == refine_id: return
	GameState.refined_items[refine_id] -= 1
	_context.set_passive_at_slot(slot_idx, {"refine_id": refine_id, "count": 1})
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


# ============================================================
#  确认
# ============================================================
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
	for i in range(min(party.size(), target_units.size())):
		var u : UnitData = party[i]
		var tu : UnitData = target_units[i]
		if u.is_dead and tu.is_dead:
			continue
		tu.weapon_slot = _clone_item_inst(u.weapon_slot)
		tu.armor_slots = _clone_inst_array(u.armor_slots)
		tu.max_armor_slots = u.max_armor_slots
		tu.talent_slots = u.talent_slots.duplicate()
		tu.is_dead = u.is_dead

	if _context.get_context_id() == "main_game" and selected_units.size() > 0:
		var main_data : Dictionary = UnitDataManager.get_unit_data(selected_units[0])
		var faction : String = main_data.get("faction", "王国")
		_context.set_pending_faction(faction)

	_context.on_confirm()
	_context.auto_save()
	var canvas_layer : Node = get_parent()
	if canvas_layer: canvas_layer.queue_free()
	else: queue_free()


# ============================================================
#  数据拷贝 / 同步
# ============================================================
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
	for i in range(party.size()):
		var u : UnitData = party[i]
		var armor_target : int = clampi(u.max_armor_slots, 0, 10)
		u.max_armor_slots = armor_target
		u.armor_slots.resize(armor_target)
		var talent_target : int = maxi(u.talent_slots.size(), 1)
		u.talent_slots.resize(talent_target)

		if i < target_units.size():
			var tu : UnitData = target_units[i]
			if u.is_dead and tu.is_dead:
				continue
			tu.weapon_slot = _clone_item_inst(u.weapon_slot)
			tu.armor_slots = _clone_inst_array(u.armor_slots)
			tu.max_armor_slots = u.max_armor_slots
			tu.talent_slots = u.talent_slots.duplicate()
			tu.is_dead = u.is_dead


# ============================================================
#  深拷贝辅助
# ============================================================
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


# ============================================================
#  Tab 切换
# ============================================================
func _switch_tab(tab: String):
	if not _check_pending_before_leave():
		return
	if current_tab == tab: return
	if (current_mode == Mode.FORGE or _is_shop_rest_mode()) and current_tab == "arena_forge":
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return
	current_tab = tab
	_update_tab_style()
	_clear_container(shop_container)
	# ★ 修复：只有 arena_forge 保留 forge UI，其它全部 cleanup
	var is_forge_tab : bool = (tab == "arena_forge")
	if not is_forge_tab:
		_forge.cleanup()
	match tab:
		"weapon": _shop.build_weapon_grid(shop_container)
		"talent": _talent.build_talent_grid(shop_container)
		"refine": _shop.build_refine_grid(shop_container)
		"arena_shop":
			if shop_manager and shop_manager.get_shop_items().is_empty():
				shop_manager.generate_shop_items()
			_shop.build_shop_items()
			if reset_btn and shop_manager:
				reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
		"arena_forge":
			_forge.build_forge_slots()
			if reset_btn: reset_btn.text = "清空插槽"
		"sacrifice":
			_build_sacrifice_panel()
			if reset_btn: reset_btn.visible = false
	shop_container.visible = true
	if _is_shop_rest_mode():
		discard_zone.visible = true
	_refresh_bottom_buttons()


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
	# ★ 熔铸 / 铁匠铺下灰化"继续探索"
	var in_sacrifice : bool = (current_tab == "sacrifice")
	var in_arena_forge : bool = (current_tab == "arena_forge")

	if in_sacrifice or in_arena_forge:
		close_btn.disabled = true
		close_btn.modulate = Color(0.5, 0.5, 0.5)
	else:
		close_btn.disabled = false
		close_btn.modulate = Color.WHITE

	if current_mode == Mode.ARENA_REST:
		close_btn.visible = false
		confirm_btn.visible = true
		confirm_btn.text = "出发"
		if current_tab == "arena_forge":
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
		discard_zone.visible = true

func _update_tab_style():
	if not weapon_tab_btn or not talent_tab_btn:
		return

	if current_mode == Mode.ARENA_REST:
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if refine_tab_btn: refine_tab_btn.visible = false
		if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
		return

	if current_mode == Mode.MAP_SHOP_REST:
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if sacrifice_tab_btn:
			sacrifice_tab_btn.modulate = Color.WHITE if current_tab == "sacrifice" else Color(0.5, 0.5, 0.5)
		if refine_tab_btn: refine_tab_btn.visible = false
		return

	if current_mode == Mode.FORGE:
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if sacrifice_tab_btn:
			sacrifice_tab_btn.modulate = Color.WHITE if current_tab == "sacrifice" else Color(0.5, 0.5, 0.5)
		if refine_tab_btn: refine_tab_btn.visible = false
		return

	weapon_tab_btn.modulate = Color.WHITE if current_tab == "weapon" else Color(0.5, 0.5, 0.5)
	talent_tab_btn.modulate = Color.WHITE if current_tab == "talent" else Color(0.5, 0.5, 0.5)
	if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
	if refine_tab_btn:
		refine_tab_btn.modulate = Color.WHITE if current_tab == "refine" else Color(0.5, 0.5, 0.5)


# ============================================================
#  输入
# ============================================================
func _input(event: InputEvent):
	if _has_active_confirm_ui(): return
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


# ============================================================
#  通用辅助
# ============================================================
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


# ============================================================
#  转发
# ============================================================
func _build_shop_items(): _shop.build_shop_items()
func _build_weapon_grid(container: GridContainer): _shop.build_weapon_grid(container)
func _build_refine_grid(container: GridContainer): _shop.build_refine_grid(container)
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
func _on_talent_hover_exited(): _detail.on_talent_hover_exited()
func _on_relic_hover_entered(relic_id: String): _detail.on_relic_hover_entered(relic_id)
func _on_relic_hover_exited(): _detail.on_relic_hover_exited()
func _on_refine_hover_entered(refine_id: String): _detail.on_refine_hover_entered(refine_id)
func _on_refine_hover_exited(): _detail.on_refine_hover_exited()
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
		lines.append("🎲 额外产出 ×%d" % result["bonus_count"])
	_show_detail_in_zone("\n".join(lines))


func _quality_cn(q : String) -> String:
	match q:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return q
