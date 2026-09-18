extends Panel

enum Mode { DEPLOY, MAP, SHOP, FORGE, ARENA_REST, MAP_SHOP_REST }

class Style:
	const FONT_TINY = 4
	const FONT_SMALL = 6
	const FONT_NORMAL = 6
	const FONT_LARGE = 6
	const BTN_ITEM_SIZE = Vector2(28, 16)
	const BTN_TALENT_SIZE = Vector2(28, 18)
	const BTN_SHOP_SIZE = Vector2(28, 16)
	const BTN_LIBRARY_SIZE = Vector2(28, 16)
	const BTN_RELIC_SIZE = Vector2(22, 16)
	const SEPARATOR_TEXT = "──────"

var current_mode: Mode = Mode.DEPLOY
var selected_units: Array = []
var target_slot: int = -1
var party: Array = []
var _is_building_ui: bool = false
var _build_ui_pending: bool = false
var _is_closing: bool = false
var _context : EquipContext = null

const MAX_PASSIVE_SLOTS : int = 4
const FORGE_MAX_SLOTS : int = 3
const FORGE_WEAPON_UPGRADE_MAX : int = 3     # ★ 恢复上限
const WEAPON_UPGRADE_BASE_COST : int = 50
const WEAPON_UPGRADE_GROWTH : float = 2.0
const FORGE_CRAFT_COST : int = 50

var _forge_slots : Array = []
var _forge_matched_recipe : String = ""
var forge_result_label : Label = null
var forge_upgrade_label : Label = null
var forge_upgrade_btn : Button = null
var inline_craft_btn : Button = null

const ShopManagerScript = preload(Config.PATHS.SHOP_MANAGER_SCRIPT)

var _is_dragging: bool = false
var _drag_source: Button = null
var _drag_meta: Dictionary = {}
var _drag_preview: Control = null
var _drag_grab_offset: Vector2 = Vector2.ZERO
var _target_states: Dictionary = {}

var current_tab: String = "weapon"
var shop_manager = null

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


func _ready():
	if weapon_tab_btn:
		weapon_tab_btn.pressed.connect(_on_weapon_tab_pressed)
	if talent_tab_btn:
		talent_tab_btn.pressed.connect(_on_talent_tab_pressed)
	if refine_tab_btn:
		refine_tab_btn.pressed.connect(_on_refine_tab_pressed)
		refine_tab_btn.visible = false


# ============================================================
#  模式 / Tab 判断辅助
# ============================================================
func _is_shop_rest_mode() -> bool:
	return current_mode == Mode.ARENA_REST or current_mode == Mode.MAP_SHOP_REST


func _on_refine_tab_pressed(): _switch_tab("refine")
func _on_weapon_tab_pressed():
	if _is_shop_rest_mode(): _switch_tab("arena_shop")
	else: _switch_tab("weapon")
func _on_talent_tab_pressed():
	if _is_shop_rest_mode(): _switch_tab("arena_forge")
	else: _switch_tab("talent")

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

	if mode == Mode.SHOP or _is_shop_rest_mode():
		if not shop_manager:
			shop_manager = ShopManagerScript.new()
			add_child(shop_manager)
			shop_manager.shop_updated.connect(_on_shop_updated)
		shop_manager.set_context(_context)
		shop_manager.generate_shop_items()
		shop_manager.reset_count = 0

	if mode == Mode.FORGE or _is_shop_rest_mode():
		_forge_slots.clear()
		for i in range(FORGE_MAX_SLOTS):
			_forge_slots.append(null)
		_forge_matched_recipe = ""

	if _is_shop_rest_mode():
		current_tab = "arena_shop"

	_copy_party_data()
	_build_ui()

func _on_shop_updated():
	_update_gold_display()
	_schedule_build_ui()

func _on_close_pressed():
	if _is_shop_rest_mode() and current_tab == "arena_forge":
		var unresolved : int = _return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return
		if current_mode == Mode.ARENA_REST:
			_switch_tab("arena_shop")
			return
		# MAP_SHOP_REST：继续往下走关闭

	if current_mode == Mode.FORGE and _has_forge_pending():
		var unresolved : int = _return_all_forge_slots()
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
#  UI 构建
# ============================================================
func _build_ui():
	if _is_closing: return
	if _is_building_ui: return
	_is_building_ui = true
	_build_ui_inner()
	_is_building_ui = false

func _build_ui_inner():
	var show_passive : bool = (_context.get_context_id() != "arena")
	if relic_section: relic_section.visible = show_passive
	if relic_container: relic_container.visible = show_passive
	if show_passive: _build_passive_slots()

	if not mode_label: return

	_update_gold_display()

	shop_container.visible = false
	discard_zone.visible = false
	reset_btn.visible = false
	tab_bar.visible = false
	right_container.visible = true

	var left_column : VBoxContainer = $VBoxContainer/MainHBox/LeftVBox
	if left_column:
		left_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	match current_mode:
		Mode.DEPLOY:
			mode_label.text = "装备配置 - 出战准备" if _context.get_title() == "" else _context.get_title()
			close_btn.visible = true
			close_btn.text = "返回"
			confirm_btn.visible = true
			confirm_btn.text = "出发"
			confirm_btn.disabled = false
			confirm_btn.modulate = Color.WHITE
			gold_label.visible = _context.show_gold()
			tab_bar.visible = true
			weapon_tab_btn.visible = true
			weapon_tab_btn.text = "武器库"
			talent_tab_btn.visible = true
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "特技库"
			if refine_tab_btn:
				refine_tab_btn.visible = (_context.get_context_id() == "main_game")
			if current_tab == "" or current_tab.begins_with("arena_"):
				current_tab = "weapon"
			_update_tab_style()
			if current_tab == "weapon": _build_weapon_grid(shop_container)
			elif current_tab == "talent": _build_talent_grid(shop_container)
			else: _build_refine_grid(shop_container)
			shop_container.visible = true
			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

		Mode.MAP:
			# ★ 局内配置：特技库 + 丢弃区（无武器库 / 精炼库）
			mode_label.text = "装备配置"
			close_btn.visible = true
			close_btn.text = "返回"
			confirm_btn.visible = false
			gold_label.visible = false
			tab_bar.visible = true
			weapon_tab_btn.visible = false
			talent_tab_btn.visible = true
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "特技库"
			if refine_tab_btn:
				refine_tab_btn.visible = false
			# ★ 强制切到特技库（避免残留 weapon/refine 状态）
			current_tab = "talent"
			_update_tab_style()
			_build_talent_grid(shop_container)
			shop_container.visible = true
			discard_zone.visible = true
			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

		Mode.ARENA_REST:
			mode_label.text = "魂之竞技场 · 备战"
			gold_label.visible = true
			tab_bar.visible = true
			weapon_tab_btn.visible = true
			weapon_tab_btn.text = "商店"
			talent_tab_btn.visible = true
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "铁匠铺"
			if refine_tab_btn: refine_tab_btn.visible = false
			if current_tab == "" or not current_tab.begins_with("arena_"):
				current_tab = "arena_shop"
			_update_tab_style()
			_cleanup_forge_ui()

			close_btn.visible = false
			confirm_btn.visible = true
			confirm_btn.text = "出发"

			if current_tab == "arena_forge":
				confirm_btn.disabled = true
				confirm_btn.modulate = Color(0.5, 0.5, 0.5)
				_build_forge_slots()
				shop_container.visible = true
				reset_btn.visible = true
				reset_btn.text = "清空插槽"
				_display_forge_recipe_info()
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
			# ★ 第 3 天第一个节点：铁匠商店（商店 + 铁匠铺）
			mode_label.text = "铁匠商店"
			close_btn.visible = true
			close_btn.text = "出发"
			confirm_btn.visible = false
			gold_label.visible = true
			tab_bar.visible = true
			weapon_tab_btn.visible = true
			weapon_tab_btn.text = "商店"
			talent_tab_btn.visible = true
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "铁匠铺"
			if refine_tab_btn: refine_tab_btn.visible = false
			if current_tab == "" or not current_tab.begins_with("arena_"):
				current_tab = "arena_shop"
			_update_tab_style()
			_cleanup_forge_ui()

			if current_tab == "arena_forge":
				_build_forge_slots()
				shop_container.visible = true
				reset_btn.visible = true
				reset_btn.text = "清空插槽"
				_display_forge_recipe_info()
				discard_zone.visible = false
			else:
				_build_shop_items()
				shop_container.visible = true
				reset_btn.visible = true
				if shop_manager:
					reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
				discard_zone.visible = true

			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

		Mode.SHOP:
			mode_label.text = "商店"
			close_btn.visible = true
			close_btn.text = "出发"
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
			mode_label.text = "铁匠铺"                 # ★ "铁匠铺 - 防具合成" → "铁匠铺"
			close_btn.visible = true
			close_btn.text = "出发"
			confirm_btn.visible = false
			gold_label.visible = true
			tab_bar.visible = false
			_build_forge_slots()
			shop_container.visible = true
			reset_btn.visible = true
			reset_btn.text = "清空插槽"
			discard_zone.visible = false
			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_display_forge_recipe_info()

	close_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	confirm_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	reset_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)

	_build_unit_columns()
	visible = true

func _update_gold_display():
	if gold_label:
		gold_label.text = "金币: " + str(_context.get_gold())


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

		# ★ 单位名字：可 hover
		var name_label : Label = _create_label(
			unit.display_name + "(" + UnitDataManager.get_unit_type_display_name(unit.unit_name) + ")",
			Style.FONT_SMALL)
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		name_label.mouse_entered.connect(_on_unit_hover_entered.bind(i))
		name_label.mouse_exited.connect(_on_unit_hover_exited)
		col.add_child(name_label)

		col.add_child(_create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))

		var weapon_inst : ItemInstance = unit.weapon_slot
		col.add_child(_create_item_button(weapon_inst, "weapon", i, -1))

		col.add_child(_create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))

		for slot_idx in range(unit.armor_slots.size()):
			var armor_btn : Button = _create_item_button(unit.armor_slots[slot_idx], "armor", i, slot_idx)
			if current_mode == Mode.DEPLOY: armor_btn.disabled = true
			col.add_child(armor_btn)

		col.add_child(_create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))
		col.add_child(_create_label("特技", Style.FONT_SMALL))
		var talent_inst : TalentInstance = unit.talent_slots[0] if unit.talent_slots.size() > 0 else null
		col.add_child(_create_talent_button(talent_inst, i, 0))


# ★ 新增：单位 hover 显示详情
func _on_unit_hover_entered(unit_idx: int) -> void:
	if unit_idx < 0 or unit_idx >= party.size(): return
	var unit : UnitData = party[unit_idx]

	var display : String = unit.display_name if unit.display_name != "" else unit.unit_name
	var type_name : String = UnitDataManager.get_unit_type_display_name(unit.unit_name)

	var lines : Array = []
	lines.append("%s（%s）" % [display, type_name])
	lines.append("")

	# 属性
	lines.append("HP: %d / %d" % [unit.hit_points, unit.max_hp])
	lines.append("力量: %d    灵巧: %d" % [unit.strength, unit.dexterity])
	lines.append("智力: %d    信仰: %d" % [unit.intelligence, unit.faith])
	lines.append("感应: %d    移动力: %d" % [unit.arcane, unit.move_range])

	# 武器
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

	# 防具
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

	# 特技
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
	_clear_detail_zone()

func _create_item_button(inst: ItemInstance, slot_type: String, unit_idx: int, slot_idx: int) -> Button:
	var btn : Button = _create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
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
	var btn : Button = _create_styled_button(Style.FONT_TINY, Style.BTN_TALENT_SIZE)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.set_meta("slot_type", "talent")
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	if inst and inst.is_active:
		var data : TalentData = TalentManager.get_talent_data(inst.talent_id)
		if data:
			btn.text = data.display_name
			btn.modulate = _get_rarity_color(data.rarity)
			btn.set_meta("talent_id", inst.talent_id)
			btn.mouse_entered.connect(_on_talent_hover_entered.bind(inst.talent_id))
			btn.mouse_exited.connect(_on_talent_hover_exited)
		else:
			btn.text = "空"; btn.modulate = Color(0.5, 0.5, 0.5, 1); btn.set_meta("talent_id", "")
	else:
		btn.text = "空"; btn.modulate = Color(0.5, 0.5, 0.5, 1); btn.set_meta("talent_id", "")
	return btn


# ============================================================
#  商店
# ============================================================
func _build_shop_items():
	if not shop_manager: return
	var row : Node = right_container.get_node_or_null("ForgeCraftRow")
	if row: row.queue_free()
	var spacer : Node = right_container.get_node_or_null("ForgeBottomSpacer")
	if spacer: spacer.queue_free()
	inline_craft_btn = null

	if shop_scroll:
		shop_scroll.custom_minimum_size = Vector2(0, 0)
		shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_clear_container(shop_container)
	shop_container.columns = 3
	shop_container.add_theme_constant_override("h_separation", 2)
	shop_container.add_theme_constant_override("v_separation", 2)
	shop_container.visible = true

	var items : Array = shop_manager.get_shop_items()
	for i in range(items.size()):
		var entry : Variant = items[i]
		var btn : Button = _create_styled_button(Style.FONT_SMALL, Style.BTN_SHOP_SIZE)
		btn.autowrap_mode = TextServer.AUTOWRAP_OFF
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if entry != null:
			var entry_dict : Dictionary = entry
			var item_data : ItemData = entry_dict["item_data"]
			var price : int = entry_dict["price"]
			btn.text = item_data.name + " " + str(price) + "G"
			if item_data.icon: btn.icon = item_data.icon
			btn.set_meta("shop_index", i)
			btn.set_meta("slot_type", "shop_item")
			btn.set_meta("item_price", price)
			btn.set_meta("item_id", item_data.id)
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_data.id))
			btn.mouse_exited.connect(_on_button_hover_exited)
		else:
			btn.text = "空位"; btn.disabled = true
		shop_container.add_child(btn)

func _build_weapon_grid(container: GridContainer):
	for child in container.get_children(): container.remove_child(child); child.free()
	container.columns = 3
	for item_id in Globals.unlocked_items:
		var data : ItemData = ItemManager.get_item_data(item_id)
		if data and data.type == "weapon":
			var btn : Button = _create_styled_button(Style.FONT_SMALL, Style.BTN_LIBRARY_SIZE)
			btn.text = data.name
			btn.set_meta("slot_type", "library_weapon")
			btn.set_meta("item_id", item_id)
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
			btn.mouse_exited.connect(_on_button_hover_exited)
			container.add_child(btn)

func _build_talent_grid(container: GridContainer):
	for child in container.get_children(): container.remove_child(child); child.free()
	var unlocked : Array = Globals.get_unlocked_talents()
	if unlocked.is_empty():
		container.add_child(_create_label("暂无解锁特技", Style.FONT_SMALL))
		return
	for talent_id in unlocked:
		var data : TalentData = TalentManager.get_talent_data(talent_id)
		if not data: continue
		var is_equipped : bool = _is_talent_equipped_anywhere(talent_id)
		var btn : Button = _create_styled_button(Style.FONT_TINY, Style.BTN_TALENT_SIZE)
		btn.text = data.display_name
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.set_meta("talent_id", talent_id)
		btn.set_meta("slot_type", "library_talent")
		var rarity_color : Color = _get_rarity_color(data.rarity)
		if is_equipped:
			btn.modulate = Color(0.4, 0.4, 0.4, 1.0); btn.disabled = true
		else:
			btn.modulate = Color.WHITE
			btn.add_theme_color_override("font_color", rarity_color)
			btn.disabled = false
		btn.mouse_entered.connect(_on_talent_hover_entered.bind(talent_id))
		btn.mouse_exited.connect(_on_talent_hover_exited)
		container.add_child(btn)

func _build_refine_grid(container: GridContainer):
	for child in container.get_children(): container.remove_child(child); child.free()
	container.columns = 3
	var all_ids : Array = RefineManager.get_all_ids()
	var has_any : bool = false
	for refine_id in all_ids:
		if not RefineManager.is_recipe_unlocked(refine_id): continue
		var count : int = RefineManager.get_count(refine_id)
		if count <= 0: continue
		has_any = true
		var recipe : Dictionary = RefineManager.get_recipe(refine_id)
		var btn : Button = _create_styled_button(Style.FONT_SMALL, Style.BTN_LIBRARY_SIZE)
		var rname : String = recipe.get("name", refine_id)
		btn.text = rname + " ×" + str(count)
		btn.autowrap_mode = TextServer.AUTOWRAP_OFF
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.set_meta("slot_type", "library_refine")
		btn.set_meta("refine_id", refine_id)
		btn.mouse_entered.connect(_on_refine_hover_entered.bind(refine_id))
		btn.mouse_exited.connect(_on_refine_hover_exited)
		container.add_child(btn)
	if not has_any:
		container.add_child(_create_label("暂无精炼道具", Style.FONT_SMALL))

func _get_item_name(inst: ItemInstance) -> String:
	if not inst: return ""
	var data : ItemData = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id


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
	var btn : Button = _create_styled_button(Style.FONT_SMALL, Style.BTN_RELIC_SIZE)
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


# ============================================================
#  FORGE
# ============================================================
func _build_forge_slots():
	_clear_container(shop_container)
	inline_craft_btn = null

	shop_container.columns = FORGE_MAX_SLOTS
	shop_container.visible = true
	shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_container.add_theme_constant_override("h_separation", 2)
	shop_container.add_theme_constant_override("v_separation", 2)

	if shop_scroll:
		shop_scroll.custom_minimum_size = Vector2(0, 22)
		shop_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	_ensure_forge_result_label()

	for i in range(FORGE_MAX_SLOTS):
		var slot_btn : Button = _create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
		slot_btn.set_meta("slot_type", "forge_slot")
		slot_btn.set_meta("forge_slot_index", i)
		slot_btn.text = "空槽 %d" % (i + 1)
		slot_btn.modulate = Color(0.5, 0.5, 0.5)
		var entry : Variant = _forge_slots[i] if i < _forge_slots.size() else null
		if entry != null:
			var entry_dict : Dictionary = entry
			var inst : ItemInstance = entry_dict["inst"]
			var data : ItemData = ItemManager.get_item_data(inst.item_id)
			slot_btn.text = data.name if data else inst.item_id
			slot_btn.set_meta("item_id", inst.item_id)
			if data:
				slot_btn.modulate = UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE)
			slot_btn.mouse_entered.connect(_on_button_hover_entered.bind(inst.item_id))
			slot_btn.mouse_exited.connect(_on_button_hover_exited)
		else:
			slot_btn.set_meta("item_id", "")
		shop_container.add_child(slot_btn)

	_update_forge_result_label()
	_ensure_forge_craft_row()
	_ensure_forge_upgrade_ui()
	_refresh_inline_craft_btn()
	_ensure_forge_bottom_spacer()


func _ensure_forge_craft_row():
	var should_show : bool = _is_shop_rest_mode() or (current_mode == Mode.FORGE)
	var existing : Node = right_container.get_node_or_null("ForgeCraftRow")

	if not should_show:
		if existing: existing.queue_free()
		inline_craft_btn = null
		return

	var row : HBoxContainer = existing
	if row == null:
		row = HBoxContainer.new()
		row.name = "ForgeCraftRow"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_container.add_child(row)
		var scroll_idx : int = shop_scroll.get_index()
		right_container.move_child(row, scroll_idx + 1)

	for c in row.get_children(): c.queue_free()

	inline_craft_btn = _create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	inline_craft_btn.custom_minimum_size = Vector2(72, 16)
	inline_craft_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inline_craft_btn.text = "合成"
	inline_craft_btn.set_meta("slot_type", "forge_craft_btn")
	inline_craft_btn.pressed.connect(_on_forge_craft_pressed)
	row.add_child(inline_craft_btn)

	_refresh_inline_craft_btn()


func _refresh_inline_craft_btn():
	if not inline_craft_btn or not is_instance_valid(inline_craft_btn): return
	if _forge_matched_recipe == "":
		inline_craft_btn.text = "合成"
		inline_craft_btn.disabled = true
		inline_craft_btn.modulate = Color(0.5, 0.5, 0.5)
		return
	if not _is_forge_recipe_available():
		inline_craft_btn.text = "未解锁"
		inline_craft_btn.disabled = true
		inline_craft_btn.modulate = Color(0.5, 0.5, 0.5)
		return
	inline_craft_btn.text = "合成 %dG" % FORGE_CRAFT_COST
	var can_afford : bool = _context.get_gold() >= FORGE_CRAFT_COST
	inline_craft_btn.disabled = not can_afford
	inline_craft_btn.modulate = Color.WHITE if can_afford else Color(0.5, 0.5, 0.5)


func _ensure_forge_result_label():
	if forge_result_label and is_instance_valid(forge_result_label) and forge_result_label.is_inside_tree():
		return
	forge_result_label = Label.new()
	forge_result_label.name = "ForgeResultLabel"
	forge_result_label.add_theme_font_size_override("font_size", Style.FONT_SMALL)
	forge_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_result_label.modulate = Color(0.5, 0.5, 0.5)
	forge_result_label.text = "合成结果：—"
	right_container.add_child(forge_result_label)
	var scroll_idx : int = shop_scroll.get_index()
	right_container.move_child(forge_result_label, scroll_idx + 1)

func _display_forge_recipe_info():
	var input_ids : Array = []
	for entry in _forge_slots:
		if entry != null:
			var entry_dict : Dictionary = entry
			var inst : ItemInstance = entry_dict["inst"]
			input_ids.append(inst.item_id)
	if input_ids.is_empty():
		_show_detail_in_zone("将防具拖入插槽以匹配配方")
		_forge_matched_recipe = ""
		_update_forge_result_label()
		return
	_forge_matched_recipe = RecipeManager.match_recipe(input_ids)
	if _forge_matched_recipe == "":
		var names : Array = []
		for id in input_ids:
			var d : ItemData = ItemManager.get_item_data(id)
			names.append(d.name if d else id)
		_show_detail_in_zone("无匹配配方\n\n已放: " + ", ".join(names))
		_update_forge_result_label()
		return

	var recipe : RecipeData = RecipeManager.get_recipe(_forge_matched_recipe)
	var out_data : ItemData = ItemManager.get_item_data(_forge_matched_recipe)
	var lines : Array = []
	lines.append("匹配配方: " + (out_data.name if out_data else _forge_matched_recipe))

	# ★ 主游戏未解锁提示
	if not _is_forge_recipe_available():
		lines.append("")
		lines.append("⚠ 此配方未解锁")
		lines.append("前往铁砧酒馆 → 武备库 → 防具")
		lines.append("消耗材料解锁后可合成")
		_show_detail_in_zone("\n".join(lines))
		_update_forge_result_label()
		return

	lines.append("")
	lines.append("消耗:")
	for id in recipe.inputs:
		var d : ItemData = ItemManager.get_item_data(id)
		lines.append("  " + (d.name if d else id))
	lines.append("")
	lines.append("金币: %dG" % FORGE_CRAFT_COST)
	lines.append("→ 产物: " + (out_data.name if out_data else _forge_matched_recipe))
	_show_detail_in_zone("\n".join(lines))
	_update_forge_result_label()

func _update_forge_result_label():
	if not forge_result_label or not is_instance_valid(forge_result_label): return
	if _forge_matched_recipe == "":
		forge_result_label.text = "合成结果：—"
		forge_result_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		var out_data : ItemData = ItemManager.get_item_data(_forge_matched_recipe)
		var out_name : String = out_data.name if out_data else _forge_matched_recipe
		if not _is_forge_recipe_available():
			forge_result_label.text = "合成结果：%s（未解锁）" % out_name
			forge_result_label.modulate = Color(0.5, 0.5, 0.5)
		else:
			forge_result_label.text = "合成结果：%s（%dG）" % [out_name, FORGE_CRAFT_COST]
			if out_data:
				forge_result_label.modulate = UIConst.QUALITY_COLORS.get(out_data.quality, Color.WHITE)
			else:
				forge_result_label.modulate = Color.WHITE
	_refresh_inline_craft_btn()

func _ensure_forge_upgrade_ui():
	if forge_upgrade_btn and is_instance_valid(forge_upgrade_btn) and forge_upgrade_btn.is_inside_tree():
		_refresh_forge_upgrade_ui(); return
	var spacer1 := Control.new()
	spacer1.name = "ForgeUpgradeSpacer1"
	spacer1.custom_minimum_size = Vector2(0, 12)
	right_container.add_child(spacer1)
	forge_upgrade_label = Label.new()
	forge_upgrade_label.name = "ForgeUpgradeLabel"
	forge_upgrade_label.add_theme_font_size_override("font_size", Style.FONT_SMALL)
	forge_upgrade_label.text = "拖拽武器到此升级（上限 +3）"
	forge_upgrade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_upgrade_label.modulate = Color(0.7, 0.7, 0.7)
	right_container.add_child(forge_upgrade_label)
	forge_upgrade_btn = _create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	forge_upgrade_btn.name = "ForgeUpgradeBtn"
	forge_upgrade_btn.set_meta("slot_type", "forge_upgrade_slot")
	right_container.add_child(forge_upgrade_btn)
	var spacer2 := Control.new()
	spacer2.name = "ForgeUpgradeSpacer2"
	spacer2.custom_minimum_size = Vector2(0, 12)
	right_container.add_child(spacer2)
	var reset_idx : int = reset_btn.get_index()
	right_container.move_child(spacer1, reset_idx + 1)
	right_container.move_child(forge_upgrade_label, reset_idx + 2)
	right_container.move_child(forge_upgrade_btn, reset_idx + 3)
	right_container.move_child(spacer2, reset_idx + 4)
	_refresh_forge_upgrade_ui()

func _refresh_forge_upgrade_ui():
	if not forge_upgrade_btn or not is_instance_valid(forge_upgrade_btn): return
	# 默认：显示 party[0] 武器的升级信息（拖拽时会被覆盖）
	if party.size() <= 0:
		forge_upgrade_btn.text = "拖拽武器到此升级"
		forge_upgrade_btn.disabled = false
		forge_upgrade_btn.modulate = Color.WHITE
		return
	var u : UnitData = party[0]
	if u.weapon_slot == null:
		forge_upgrade_btn.text = "拖拽武器到此升级"
		forge_upgrade_btn.disabled = false
		forge_upgrade_btn.modulate = Color.WHITE
		return
	var wname : String = _get_item_name(u.weapon_slot)
	var lv : int = u.weapon_slot.upgrade_level
	if lv >= FORGE_WEAPON_UPGRADE_MAX:
		forge_upgrade_btn.text = "%s 已满级 +%d" % [wname, lv]
		forge_upgrade_btn.disabled = false
		forge_upgrade_btn.modulate = Color(0.5, 0.5, 0.5)
		return
	var cost : int = _get_weapon_upgrade_cost(lv)
	var afford : bool = _context.get_gold() >= cost
	forge_upgrade_btn.text = "%s +%d→+%d（%dG）" % [wname, lv, lv + 1, cost]
	forge_upgrade_btn.disabled = false
	forge_upgrade_btn.modulate = Color.WHITE if afford else Color(1.0, 0.6, 0.6)

# ★ 拖拽武器时，把该武器的升级费用显示到升级槽
func _update_upgrade_slot_for_drag(unit_idx: int) -> void:
	if not forge_upgrade_btn or not is_instance_valid(forge_upgrade_btn): return
	if unit_idx < 0 or unit_idx >= party.size(): return
	var u : UnitData = party[unit_idx]
	if u.weapon_slot == null: return
	var wname : String = _get_item_name(u.weapon_slot)
	var lv : int = u.weapon_slot.upgrade_level
	if lv >= FORGE_WEAPON_UPGRADE_MAX:
		forge_upgrade_btn.text = "★ %s 已满级 +%d" % [wname, lv]
		forge_upgrade_btn.modulate = Color(0.5, 0.5, 0.5)
		return
	var cost : int = _get_weapon_upgrade_cost(lv)
	var afford : bool = _context.get_gold() >= cost
	forge_upgrade_btn.text = "★ %s +%d→+%d（%dG）" % [wname, lv, lv + 1, cost]
	forge_upgrade_btn.modulate = Color.WHITE if afford else Color(1.0, 0.6, 0.6)

func _ensure_forge_bottom_spacer():
	var spacer : Control = right_container.get_node_or_null("ForgeBottomSpacer")
	if spacer == null:
		spacer = Control.new()
		spacer.name = "ForgeBottomSpacer"
		right_container.add_child(spacer)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _get_weapon_upgrade_cost(level: int) -> int:
	return int(WEAPON_UPGRADE_BASE_COST * pow(WEAPON_UPGRADE_GROWTH, level))


# ---- 归还 ----
func _return_armor_to_unit(unit: UnitData, inst: ItemInstance, prefer_slot: int) -> bool:
	var need : int = _inst_slots(inst)
	var used : int = _used_slots_of(unit)
	if used + need > unit.max_armor_slots: return false
	if prefer_slot >= 0 and prefer_slot < unit.armor_slots.size() and unit.armor_slots[prefer_slot] == null:
		unit.armor_slots[prefer_slot] = inst
		return true
	for i in range(unit.armor_slots.size()):
		if unit.armor_slots[i] == null:
			unit.armor_slots[i] = inst
			return true
	return false

func _return_all_forge_slots() -> int:
	var unresolved : int = 0
	for i in range(_forge_slots.size()):
		var entry : Variant = _forge_slots[i]
		if entry == null: continue
		var entry_dict : Dictionary = entry
		var ou : UnitData = party[entry_dict["origin_unit"]]
		var origin_slot : int = entry_dict["origin_slot"]
		if _return_armor_to_unit(ou, entry_dict["inst"], origin_slot):
			_forge_slots[i] = null
		else:
			unresolved += 1
	if unresolved == 0:
		_forge_matched_recipe = ""
	return unresolved

func _execute_forge_slot_return(data: Dictionary):
	var idx : int = data.get("forge_slot_index", -1)
	if idx < 0 or idx >= _forge_slots.size(): return
	var entry : Variant = _forge_slots[idx]
	if entry == null:
		_display_forge_recipe_info(); _schedule_build_ui(); return
	var entry_dict : Dictionary = entry
	var ou : UnitData = party[entry_dict["origin_unit"]]
	var origin_slot : int = entry_dict["origin_slot"]
	if not _return_armor_to_unit(ou, entry_dict["inst"], origin_slot):
		_show_detail_in_zone("原槽已被占用且没有空槽，请先腾出空间")
		return
	_forge_slots[idx] = null
	_build_unit_columns()
	_display_forge_recipe_info()
	_schedule_build_ui()

func _on_forge_clear_pressed():
	var unresolved_count : int = _return_all_forge_slots()
	_build_unit_columns()
	if unresolved_count > 0:
		_show_detail_in_zone("有 %d 件防具无法归还（单位已满），已保留在合成槽" % unresolved_count)
	else:
		_display_forge_recipe_info()
	_schedule_build_ui()

func _on_forge_craft_pressed():
	if _forge_matched_recipe == "": return

	# ★ 主游戏需解锁
	if not _is_forge_recipe_available():
		Globals.show_confirm(self, "未解锁此配方\n请前往铁砧酒馆解锁", "确定", "", func(): pass, func(): pass, false)
		return

	var recipe : RecipeData = RecipeManager.get_recipe(_forge_matched_recipe)
	if not recipe: return

	var entries : Array = []
	for entry in _forge_slots:
		if entry != null: entries.append(entry)
	if entries.size() != recipe.inputs.size(): return

	var first_entry : Dictionary = entries[0]
	var check_unit_idx : int = first_entry["origin_unit"]
	var check_unit : UnitData = party[check_unit_idx]

	var input_slots_for_check : Array = []
	for e in entries:
		var e_dict : Dictionary = e
		if e_dict["origin_unit"] == check_unit_idx:
			input_slots_for_check.append(e_dict["origin_slot"])

	var used_after : int = _used_slots_excluding(check_unit, input_slots_for_check)
	var out_need : int = _inst_slots_for_id(_forge_matched_recipe)
	if used_after + out_need > check_unit.max_armor_slots:
		Globals.show_confirm(self, "合成后防具格数不足！", "确定", "", func(): pass, func(): pass, false)
		return

	if _context.get_gold() < FORGE_CRAFT_COST:
		_show_buy_failure_message("not_enough_gold"); return
	if not _context.subtract_gold(FORGE_CRAFT_COST):
		_show_buy_failure_message("not_enough_gold"); return

	var out_inst := ItemInstance.new()
	out_inst.item_id = _forge_matched_recipe
	out_inst.count = 1
	var first_unit : UnitData = party[first_entry["origin_unit"]]
	first_unit.armor_slots[first_entry["origin_slot"]] = out_inst

	for i in range(1, entries.size()):
		var e_dict : Dictionary = entries[i]
		var eu : UnitData = party[e_dict["origin_unit"]]
		eu.armor_slots[e_dict["origin_slot"]] = null

	_forge_slots.clear()
	for i in range(FORGE_MAX_SLOTS): _forge_slots.append(null)
	_forge_matched_recipe = ""

	_sync_all()
	_build_unit_columns()
	_update_gold_display()
	_schedule_build_ui()

func _has_forge_pending() -> bool:
	for entry in _forge_slots:
		if entry != null: return true
	return false


# ============================================================
#  详情
# ============================================================
func show_item_detail(item_id: String):
	var relic_data : Dictionary = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		_show_relic_detail_in_zone(relic_data); return
	var data : ItemData = ItemManager.get_item_data(item_id)
	if not data: return
	var lines : Array = []
	lines.append(data.name)
	if data.quality and data.quality != "":
		lines.append("品质: " + _get_quality_display_name(data.quality))
	if data.description and data.description != "":
		lines.append(data.description)
	if data.type == "weapon":
		lines.append("基础攻击: " + str(data.base_attack))
		lines.append("射程: " + str(data.min_attack_range) + "~" + str(data.attack_range))
		if data.modifier and not data.modifier.is_empty():
			var mod_str : String = ""
			for key in data.modifier:
				var v : Variant = data.modifier[key]
				mod_str += _get_attr_display_name(key) + "+" + str(v) + " "
			lines.append("补正: " + mod_str.strip_edges())
	elif data.type == "armor":
		if data.defense > 0: lines.append("防御: +" + str(data.defense))
		if data.slot_count > 0: lines.append("占用格数: " + str(data.slot_count))
		if data.modifier and not data.modifier.is_empty():
			var mod_str : String = ""
			for key in data.modifier:
				var v : Variant = data.modifier[key]
				mod_str += _get_attr_display_name(key) + "+" + str(v) + " "
			lines.append("属性加成: " + mod_str.strip_edges())
	if data.price > 0: lines.append("价格: " + str(data.price) + "G")
	_show_detail_in_zone("\n".join(lines))

func _show_relic_detail_in_zone(data: Dictionary):
	var lines : Array = []
	lines.append(data.get("name", "未知遗物"))
	lines.append(data.get("description", ""))
	var stats : Dictionary = data.get("stats", {})
	if not stats.is_empty():
		lines.append("")
		lines.append("— 属性加成 —")
		for key in stats:
			var v : Variant = stats[key]
			lines.append(_get_attr_display_name(key) + ": +" + str(v))
	_show_detail_in_zone("\n".join(lines))

func _get_quality_display_name(quality: String) -> String:
	match quality:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return quality

func _get_attr_display_name(attr: String) -> String:
	match attr:
		"strength": return "力量"
		"dexterity": return "灵巧"
		"intelligence": return "智力"
		"faith": return "信仰"
		"arcane": return "感应"
		"attack": return "攻击"
		"defense": return "防御"
		"magic_attack": return "魔法攻击"
		"move_range": return "移动力"
		"max_hp": return "最大HP"
		_: return attr

func hide_item_detail(): _clear_detail_zone()
func _on_button_hover_entered(item_id: String): show_item_detail(item_id)
func _on_button_hover_exited(): hide_item_detail()

func _on_talent_hover_entered(talent_id: String):
	var data : TalentData = TalentManager.get_talent_data(talent_id)
	if data: _show_talent_detail(data)
func _on_talent_hover_exited(): _clear_detail_zone()

func _show_talent_detail(data: TalentData):
	var lines : Array = []
	lines.append(data.display_name)
	lines.append(data.description)
	lines.append("稀有度: " + data.rarity)
	lines.append("流派: " + data.school)
	lines.append("积累: " + str(data.accumulation_threshold) + "回合")
	var compatible_units : Array = data.compatible_units if data.compatible_units != null else []
	if not compatible_units.is_empty():
		var unit_names : Array = []
		for unit_key in compatible_units:
			var display : String = UnitDataManager.get_unit_type_display_name(unit_key)
			if display != "": unit_names.append(display)
		lines.append("可装备: " + "/".join(unit_names))
	else:
		lines.append("可装备: 全部")
	_show_detail_in_zone("\n".join(lines))

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(1.0, 1.0, 1.0, 1.0)
		"rare": return Color(0.3, 0.6, 1.0, 1.0)
		"epic": return Color(0.7, 0.3, 1.0, 1.0)
		"legendary": return Color(1.0, 0.7, 0.0, 1.0)
		_: return Color.WHITE


# ============================================================
#  Tab 切换
# ============================================================
func _switch_tab(tab: String):
	if current_tab == tab: return
	if _is_shop_rest_mode() and current_tab == "arena_forge":
		var unresolved : int = _return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return
	current_tab = tab
	_update_tab_style()
	_clear_container(shop_container)
	var is_forge_tab : bool = (tab == "arena_forge") or (current_mode == Mode.FORGE)
	if not is_forge_tab: _cleanup_forge_ui()
	match tab:
		"weapon": _build_weapon_grid(shop_container)
		"talent": _build_talent_grid(shop_container)
		"refine": _build_refine_grid(shop_container)
		"arena_shop":
			_build_shop_items()
			if reset_btn and shop_manager:
				reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
		"arena_forge":
			_build_forge_slots()
			if reset_btn: reset_btn.text = "清空插槽"
	shop_container.visible = true
	if _is_shop_rest_mode():
		discard_zone.visible = (tab != "arena_forge")
	_refresh_bottom_buttons()

func _refresh_bottom_buttons():
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
		close_btn.text = "返回"
		confirm_btn.visible = false
		discard_zone.visible = (current_tab != "arena_forge")

func _update_tab_style():
	if not weapon_tab_btn or not talent_tab_btn: return
	if _is_shop_rest_mode():
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if refine_tab_btn: refine_tab_btn.visible = false
		return
	weapon_tab_btn.modulate = Color.WHITE if current_tab == "weapon" else Color(0.5, 0.5, 0.5)
	talent_tab_btn.modulate = Color.WHITE if current_tab == "talent" else Color(0.5, 0.5, 0.5)
	if refine_tab_btn:
		refine_tab_btn.modulate = Color.WHITE if current_tab == "refine" else Color(0.5, 0.5, 0.5)


# ============================================================
#  拖拽目标收集
# ============================================================
func _get_all_target_controls() -> Array[Control]:
	var targets : Array[Control] = []
	for btn in relic_container.get_children():
		if btn is Button: targets.append(btn)
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button: targets.append(child)
	if (current_mode == Mode.DEPLOY or current_mode == Mode.MAP) and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled: targets.append(btn)
	if current_mode == Mode.SHOP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled: targets.append(btn)
	if _is_shop_rest_mode() and current_tab == "arena_shop" and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled: targets.append(btn)
	if (current_mode == Mode.FORGE or (_is_shop_rest_mode() and current_tab == "arena_forge")) and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and btn.get_meta("slot_type", "") == "forge_slot":
				targets.append(btn)
	if (current_mode == Mode.FORGE or (_is_shop_rest_mode() and current_tab == "arena_forge")) \
			and forge_upgrade_btn and is_instance_valid(forge_upgrade_btn):
		if not forge_upgrade_btn.disabled: targets.append(forge_upgrade_btn)
	if discard_zone.visible: targets.append(discard_zone)
	return targets

func _update_targets_visuals():
	if _drag_meta.is_empty(): _reset_targets_visuals(); return
	var targets : Array[Control] = _get_all_target_controls()
	_target_states.clear()
	for target in targets:
		if target == _drag_source: continue
		if not _target_states.has(target):
			_target_states[target] = target.modulate
		var is_valid : bool = _is_valid_drop(_drag_meta, target)
		if is_valid: target.modulate = Color.WHITE
		else: target.modulate = Color(0.4, 0.4, 0.4, 1.0)

func _reset_targets_visuals():
	for target in _target_states.keys():
		if is_instance_valid(target):
			var original : Variant = _target_states[target]
			target.modulate = original
	_target_states.clear()


func _find_control_at_position(pos: Vector2) -> Control:
	const BUFFER : int = 4
	for btn in relic_container.get_children():
		if btn is Button:
			var b : Button = btn
			if b.disabled: continue
			if b.get_global_rect().grow(BUFFER).has_point(pos): return b
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				var b2 : Button = child
				if current_mode == Mode.DEPLOY and b2.get_meta("slot_type", "") == "armor": continue
				if b2.get_global_rect().grow(BUFFER).has_point(pos): return b2
	if (current_mode == Mode.DEPLOY or current_mode == Mode.MAP) and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button:
				var b3 : Button = btn
				if not b3.disabled and b3.get_global_rect().grow(BUFFER).has_point(pos): return b3
	if current_mode == Mode.SHOP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button:
				var b4 : Button = btn
				if not b4.disabled and b4.get_global_rect().grow(BUFFER).has_point(pos): return b4
	if _is_shop_rest_mode() and current_tab == "arena_shop" and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button:
				var b5 : Button = btn
				if not b5.disabled and b5.get_global_rect().grow(BUFFER).has_point(pos): return b5
	if (current_mode == Mode.FORGE or (_is_shop_rest_mode() and current_tab == "arena_forge")) and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button:
				var b6 : Button = btn
				if b6.get_meta("slot_type", "") == "forge_slot" and b6.get_global_rect().grow(BUFFER).has_point(pos): return b6
	return null


func _get_target_from_position(global_pos: Vector2) -> Control:
	const BUFFER : int = 4
	if discard_zone.visible and discard_zone.get_global_rect().has_point(global_pos): return discard_zone
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				var b : Button = child
				if b.disabled: continue
				if b.get_global_rect().grow(BUFFER).has_point(global_pos): return b
	for btn in relic_container.get_children():
		if btn is Button:
			var b2 : Button = btn
			if b2.disabled: continue
			if b2.get_global_rect().grow(BUFFER).has_point(global_pos): return b2
	if (current_mode == Mode.DEPLOY or current_mode == Mode.MAP) and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button:
				var b3 : Button = btn
				if not b3.disabled and b3.get_global_rect().grow(BUFFER).has_point(global_pos): return b3
	if current_mode == Mode.SHOP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button:
				var b4 : Button = btn
				if not b4.disabled and b4.get_global_rect().grow(BUFFER).has_point(global_pos): return b4
	if _is_shop_rest_mode() and current_tab == "arena_shop" and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button:
				var b5 : Button = btn
				if not b5.disabled and b5.get_global_rect().grow(BUFFER).has_point(global_pos): return b5
	if (current_mode == Mode.FORGE or (_is_shop_rest_mode() and current_tab == "arena_forge")) and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button:
				var b6 : Button = btn
				if b6.get_meta("slot_type", "") == "forge_slot" and b6.get_global_rect().grow(BUFFER).has_point(global_pos): return b6
	if (current_mode == Mode.FORGE or (_is_shop_rest_mode() and current_tab == "arena_forge")) \
			and forge_upgrade_btn and is_instance_valid(forge_upgrade_btn) and not forge_upgrade_btn.disabled:
		if forge_upgrade_btn.get_global_rect().grow(BUFFER).has_point(global_pos): return forge_upgrade_btn
	return null


# ============================================================
#  合法性
# ============================================================
func _is_valid_drop(data: Dictionary, target: Control) -> bool:
	var source_type : String = data["slot_type"]
	var target_type : String = target.get_meta("slot_type", "")
	var discard : bool = target == discard_zone

	if source_type == "passive_slot":
		if target_type == "passive_slot": return true
		if discard: return true
		return false
	if target_type == "passive_slot":
		if source_type == "library_refine": return true
		return false

	if current_mode == Mode.FORGE: return _is_valid_forge_drop(data, target)
	if _is_shop_rest_mode() and current_tab == "arena_forge": return _is_valid_forge_drop(data, target)

	if discard and source_type in ["library_talent", "talent"]: return false

	if current_mode == Mode.DEPLOY:
		if discard: return false
		if source_type == "library_weapon": return target_type == "weapon"
		if source_type == "weapon" and target_type == "weapon": return true
		if source_type == "library_talent" and target_type == "talent": return _check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent": return _check_talent_compatibility(data, target)
		return false

	if current_mode == Mode.MAP:
		# ★ 丢弃区：只允许丢防具
		if discard:
			if source_type == "armor": return true
			return false
		# 只允许特技相关操作
		if source_type == "library_talent" and target_type == "talent": return _check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent": return _check_talent_compatibility(data, target)
		return false

	if current_mode == Mode.SHOP or (_is_shop_rest_mode() and current_tab == "arena_shop"):
		if discard:
			if source_type in ["shop_item", "weapon", "library_talent", "talent"]: return false
			return true
		if source_type == "shop_item":
			var item_data : ItemData = data.get("item_data")
			if not item_data: return false
			var tu : int = target.get_meta("unit_idx", -1)
			var ts : int = target.get_meta("slot_idx", -1)
			if item_data.type == "weapon":
				if target_type != "weapon": return false
				if tu < 0: return false
				return true
			elif item_data.type == "armor":
				if target_type != "armor": return false
				if tu < 0 or ts < 0: return false
				var tu_data : UnitData = party[tu]
				if tu_data.armor_slots[ts] != null: return false
				return _can_equip_armor_to(tu, item_data.id, ts)
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

func _is_valid_forge_drop(data: Dictionary, target: Control) -> bool:
	var src_type : String = data.get("slot_type", "")
	var tgt_type : String = target.get_meta("slot_type", "")

	# 武器升级：有上限 3
	if src_type == "weapon" and tgt_type == "forge_upgrade_slot":
		var uidx : int = data.get("unit_idx", -1)
		if uidx < 0: return false
		var u : UnitData = party[uidx]
		var weapon_inst : ItemInstance = u.weapon_slot
		if weapon_inst == null: return false
		if weapon_inst.upgrade_level >= FORGE_WEAPON_UPGRADE_MAX: return false
		return true

	if src_type == "weapon" and tgt_type == "weapon":
		var src_unit : int = data.get("unit_idx", -1)
		var tgt_unit : int = target.get_meta("unit_idx", -1)
		return src_unit >= 0 and tgt_unit >= 0 and src_unit != tgt_unit

	if src_type == "weapon" and target == discard_zone: return false

	if src_type == "armor" and tgt_type == "forge_slot":
		var slot_idx : int = target.get_meta("forge_slot_index", -1)
		if slot_idx < 0: return false
		var uidx2 : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		if uidx2 < 0 or src_slot < 0: return false
		var u2 : UnitData = party[uidx2]
		if u2.armor_slots[src_slot] == null: return false
		var existing : Variant = _forge_slots[slot_idx]
		if existing != null:
			var existing_dict : Dictionary = existing
			var old_ou : UnitData = party[existing_dict["origin_unit"]]
			var old_inst : ItemInstance = existing_dict["inst"]
			var need : int = _inst_slots(old_inst)
			var used : int = _used_slots_of(old_ou)
			if used + need > old_ou.max_armor_slots: return false
		return true

	if src_type == "armor" and tgt_type == "armor":
		return _check_armor_swap_budget(data, target)

	if src_type == "armor" and target == discard_zone: return true

	if src_type == "forge_slot":
		if tgt_type == "armor":
			var tu3 : int = target.get_meta("unit_idx", -1)
			var ts3 : int = target.get_meta("slot_idx", -1)
			if tu3 < 0 or ts3 < 0: return false
			var unit3 : UnitData = party[tu3]
			if unit3.armor_slots[ts3] != null: return false
			var idx : int = data.get("forge_slot_index", -1)
			if idx < 0 or idx >= _forge_slots.size() or _forge_slots[idx] == null: return false
			var entry_dict : Dictionary = _forge_slots[idx]
			var inst : ItemInstance = entry_dict["inst"]
			var need : int = _inst_slots(inst)
			var used : int = _used_slots_excluding(unit3, [ts3])
			return used + need <= unit3.max_armor_slots
		if tgt_type == "forge_slot": return true
		if target == discard_zone: return true
		return false
	return false


# ============================================================
#  执行 drop
# ============================================================
func _execute_drop(data: Dictionary, target: Control):
	if data.get("slot_type", "") == "passive_slot":
		if target == discard_zone: _discard_passive(data); return
		if target.get_meta("slot_type", "") == "passive_slot": _swap_passives(data, target); return
	if data.get("slot_type", "") == "library_refine" and target.get_meta("slot_type", "") == "passive_slot":
		_equip_refine_to_slot(data, target); return
	if current_mode == Mode.FORGE: _execute_forge_drop(data, target); return
	if _is_shop_rest_mode() and current_tab == "arena_forge": _execute_forge_drop(data, target); return

	var discard : bool = target == discard_zone
	var source_type : String = data["slot_type"]
	var target_type : String = target.get_meta("slot_type", "")

	if discard and source_type == "talent": _execute_talent_remove(data); return
	if discard: _discard_item(data); return
	if source_type == "shop_item": _buy_shop_item(data, target); return
	if source_type == "library_weapon": _library_to_weapon(data, target); return
	if source_type == "library_talent" and target_type == "talent": _execute_talent_drop(data, target); return
	if source_type == "talent" and target_type == "talent": _execute_talent_drop(data, target); return
	if source_type == "weapon" and target_type == "weapon": _swap_weapons(data, target)
	elif source_type == "armor" and target_type == "armor": _swap_armor(data, target)

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
	elif source_type == "talent": _discard_talent(data)
	_build_unit_columns()
	_sync_all(); _schedule_build_ui()


# ============================================================
#  商店购买
# ============================================================
func _buy_shop_item(data: Dictionary, target: Control):
	if target == null: return
	if not shop_manager: return
	var shop_index : int = data.get("shop_index", -1)
	if shop_index == -1: return
	var items : Array = shop_manager.get_shop_items()
	if shop_index < 0 or shop_index >= items.size(): return
	var entry : Variant = items[shop_index]
	if entry == null: return
	var entry_dict : Dictionary = entry
	var item_data : ItemData = entry_dict["item_data"]
	if not item_data: return

	var drag_item_id : String = data.get("item_id", "")
	if drag_item_id != "" and drag_item_id != item_data.id:
		SoundManager.play_cancel_sound(); return

	var target_unit_idx : int = target.get_meta("unit_idx", -1)
	var target_slot_idx : int = target.get_meta("slot_idx", -1)

	if item_data.type == "weapon":
		if target_unit_idx < 0: return
	elif item_data.type == "armor":
		if target_unit_idx < 0 or target_slot_idx < 0: return
		var tu_data : UnitData = party[target_unit_idx]
		if tu_data.armor_slots[target_slot_idx] != null:
			Globals.show_confirm(self, "目标槽已有防具，请先清空", "确定", "", func(): pass, func(): pass, false)
			return
		if not _can_equip_armor_to(target_unit_idx, item_data.id, target_slot_idx):
			Globals.show_confirm(self, "防具格数不足！", "确定", "", func(): pass, func(): pass, false)
			return

	var result : Dictionary = shop_manager.buy_shop_item(shop_index)
	if not result["success"]:
		var reason : String = result.get("reason", "unknown")
		_show_buy_failure_message(reason); return

	var inst := ItemInstance.new()
	inst.item_id = item_data.id
	inst.count = 1
	if item_data.type == "weapon":
		var tu : UnitData = party[target_unit_idx]
		tu.weapon_slot = inst
	elif item_data.type == "armor":
		var tu2 : UnitData = party[target_unit_idx]
		tu2.armor_slots[target_slot_idx] = inst

	_build_unit_columns()
	_sync_all()
	_update_gold_display()
	_schedule_build_ui()

func _library_to_weapon(data: Dictionary, target: Control):
	var item_id : String = data["item_id"]
	var unit_idx : int = target.get_meta("unit_idx", -1)
	if unit_idx == -1: return
	var inst := ItemInstance.new()
	inst.item_id = item_id
	inst.count = 1
	var u : UnitData = party[unit_idx]
	u.weapon_slot = inst
	_build_unit_columns()
	_sync_all(); _schedule_build_ui()

func _swap_weapons(data: Dictionary, target: Control):
	var src_unit : int = data["unit_idx"]
	var tgt_unit : int = target.get_meta("unit_idx", -1)
	if tgt_unit == -1: return
	var su : UnitData = party[src_unit]
	var tu : UnitData = party[tgt_unit]
	var temp : ItemInstance = su.weapon_slot
	su.weapon_slot = tu.weapon_slot
	tu.weapon_slot = temp
	_build_unit_columns()
	_sync_all(); _schedule_build_ui()

func _swap_armor(data: Dictionary, target: Control):
	var src_unit : int = data["unit_idx"]
	var src_slot : int = data["slot_idx"]
	var tgt_unit : int = target.get_meta("unit_idx", -1)
	var tgt_slot : int = target.get_meta("slot_idx", -1)
	if tgt_unit == -1 or tgt_slot == -1: return
	var su : UnitData = party[src_unit]
	var tu : UnitData = party[tgt_unit]
	var temp : ItemInstance = su.armor_slots[src_slot]
	su.armor_slots[src_slot] = tu.armor_slots[tgt_slot]
	tu.armor_slots[tgt_slot] = temp
	_build_unit_columns()
	_sync_all(); _schedule_build_ui()


# ============================================================
#  特技
# ============================================================
func _execute_talent_drop(data: Dictionary, target: Control):
	var source_type : String = data.get("slot_type", "")
	var target_type : String = target.get_meta("slot_type", "")
	if source_type == "library_talent" and target_type == "talent":
		var talent_id : String = data.get("talent_id", "")
		if talent_id == "": return
		var unit_idx : int = target.get_meta("unit_idx", -1)
		var slot_idx : int = target.get_meta("slot_idx", -1)
		if unit_idx == -1 or slot_idx == -1: return
		if not Globals.is_talent_unlocked(talent_id): return
		if _is_talent_already_equipped(talent_id, unit_idx, slot_idx):
			var equipped_unit : String = _get_unit_with_talent(talent_id)
			Globals.show_confirm(self, "特技已被 %s 装备" % equipped_unit, "确定", "", func(): pass, func(): pass, false); return
		if _context.get_context_id() == "arena" and current_mode != Mode.DEPLOY:
			var cost : int = _context.get_talent_swap_cost()
			if not _context.can_swap_talent():
				Globals.show_confirm(self, "金币不足（需要 %d）" % cost, "确定", "", func(): pass, func(): pass, false); return
			if not _context.consume_talent_swap(): return
			_context.lock_talent(talent_id); _update_gold_display()
		elif _context.get_context_id() == "arena":
			_context.lock_talent(talent_id)
		var inst := TalentInstance.new()
		inst.talent_id = talent_id
		inst.is_active = true
		var u : UnitData = party[unit_idx]
		u.talent_slots[slot_idx] = inst
		_sync_all(); _refresh_after_talent_change(); return

	if source_type == "talent" and target_type == "talent":
		var src_unit : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		var tgt_unit : int = target.get_meta("unit_idx", -1)
		var tgt_slot : int = target.get_meta("slot_idx", -1)
		if src_unit == -1 or tgt_unit == -1: return
		var su : UnitData = party[src_unit]
		var tu : UnitData = party[tgt_unit]
		var src_inst : TalentInstance = su.talent_slots[src_slot]
		var tgt_inst : TalentInstance = tu.talent_slots[tgt_slot]
		var src_tid : String = src_inst.talent_id if src_inst and src_inst.is_active else ""
		var tgt_tid : String = tgt_inst.talent_id if tgt_inst and tgt_inst.is_active else ""
		if src_tid == "" and tgt_tid == "": return
		if tgt_tid == "":
			if _is_talent_already_equipped(src_tid, tgt_unit, tgt_slot): return
			tu.talent_slots[tgt_slot] = src_inst
			su.talent_slots[src_slot] = null
		elif src_tid == "":
			if _is_talent_already_equipped(tgt_tid, src_unit, src_slot): return
			su.talent_slots[src_slot] = tgt_inst
			tu.talent_slots[tgt_slot] = null
		else:
			if _is_talent_already_equipped(tgt_tid, src_unit, src_slot): return
			if _is_talent_already_equipped(src_tid, tgt_unit, tgt_slot): return
			var temp : TalentInstance = su.talent_slots[src_slot]
			su.talent_slots[src_slot] = tu.talent_slots[tgt_slot]
			tu.talent_slots[tgt_slot] = temp
		_sync_all(); _refresh_after_talent_change(); return

func _refresh_after_talent_change(): _schedule_build_ui()

func _discard_talent(data: Dictionary):
	var source_type : String = data.get("slot_type", "")
	if source_type == "library_talent": return
	if source_type == "talent":
		var unit_idx : int = data.get("unit_idx", -1)
		var slot_idx : int = data.get("slot_idx", -1)
		if unit_idx == -1 or slot_idx == -1: return
		var u : UnitData = party[unit_idx]
		u.talent_slots[slot_idx] = null
		_sync_all(); _refresh_after_talent_change()


# ============================================================
#  执行 forge drop
# ============================================================
func _execute_forge_drop(data: Dictionary, target: Control):
	var src_type : String = data.get("slot_type", "")
	var tgt_type : String = target.get_meta("slot_type", "")

	# 武器升级（上限 3）
	if src_type == "weapon" and tgt_type == "forge_upgrade_slot":
		var uidx : int = data.get("unit_idx", -1)
		if uidx < 0: return
		var u : UnitData = party[uidx]
		var weapon_inst : ItemInstance = u.weapon_slot
		if weapon_inst == null: return
		if weapon_inst.upgrade_level >= FORGE_WEAPON_UPGRADE_MAX: return
		var lv : int = weapon_inst.upgrade_level
		var cost : int = _get_weapon_upgrade_cost(lv)
		if _context.get_gold() < cost:
			_show_buy_failure_message("not_enough_gold"); return
		if not _context.subtract_gold(cost):
			_show_buy_failure_message("not_enough_gold"); return
		weapon_inst.upgrade_level += 1
		_refresh_forge_upgrade_ui()
		_build_unit_columns()
		_sync_all(); _update_gold_display(); _schedule_build_ui(); return

	if src_type == "weapon" and tgt_type == "weapon":
		_swap_weapons(data, target); return
	if src_type == "armor" and tgt_type == "armor":
		_swap_armor(data, target); return

	if target == discard_zone:
		if src_type == "forge_slot":
			var src_idx : int = data.get("forge_slot_index", -1)
			if src_idx >= 0 and src_idx < _forge_slots.size(): _forge_slots[src_idx] = null
			_display_forge_recipe_info(); _schedule_build_ui(); return
		if src_type == "armor":
			var uidx : int = data.get("unit_idx", -1)
			var sidx : int = data.get("slot_idx", -1)
			if uidx >= 0 and sidx >= 0:
				var du : UnitData = party[uidx]
				du.armor_slots[sidx] = null
			_build_unit_columns()
			_sync_all(); _schedule_build_ui(); return
		return

	if src_type == "forge_slot" and tgt_type == "armor":
		var from_idx : int = data.get("forge_slot_index", -1)
		if from_idx < 0 or from_idx >= _forge_slots.size(): return
		var entry : Variant = _forge_slots[from_idx]
		if entry == null: return
		var entry_dict : Dictionary = entry
		var tgt_unit : int = target.get_meta("unit_idx", -1)
		var tgt_slot : int = target.get_meta("slot_idx", -1)
		if tgt_unit < 0 or tgt_slot < 0: return
		var tgt_unit_data : UnitData = party[tgt_unit]
		if tgt_unit_data.armor_slots[tgt_slot] != null: return
		tgt_unit_data.armor_slots[tgt_slot] = entry_dict["inst"]
		_forge_slots[from_idx] = null
		_build_unit_columns()
		_display_forge_recipe_info(); _schedule_build_ui(); return

	if src_type == "forge_slot" and tgt_type == "forge_slot":
		var from_idx : int = data.get("forge_slot_index", -1)
		var to_idx : int = target.get_meta("forge_slot_index", -1)
		if from_idx < 0 or to_idx < 0 or from_idx == to_idx: return
		var temp : Variant = _forge_slots[from_idx]
		_forge_slots[from_idx] = _forge_slots[to_idx]
		_forge_slots[to_idx] = temp
		_display_forge_recipe_info(); _schedule_build_ui(); return

	if src_type == "armor" and tgt_type == "forge_slot":
		var slot_idx : int = target.get_meta("forge_slot_index", -1)
		if slot_idx < 0 or slot_idx >= _forge_slots.size(): return
		var uidx : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		if uidx < 0 or src_slot < 0: return
		var u : UnitData = party[uidx]
		var inst : ItemInstance = u.armor_slots[src_slot]
		if inst == null: return
		var existing : Variant = _forge_slots[slot_idx]
		if existing != null:
			var existing_dict : Dictionary = existing
			var old_ou : UnitData = party[existing_dict["origin_unit"]]
			if not _return_armor_to_unit(old_ou, existing_dict["inst"], existing_dict["origin_slot"]):
				_show_detail_in_zone("无法替换：原防具无处归还")
				return
		u.armor_slots[src_slot] = null
		_forge_slots[slot_idx] = {"inst": inst, "origin_unit": uidx, "origin_slot": src_slot}
		_build_unit_columns()
		_display_forge_recipe_info(); _schedule_build_ui(); return


# ============================================================
#  输入
# ============================================================
func _input(event: InputEvent):
	if _has_active_confirm_ui(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos : Vector2 = get_global_mouse_position()
		var btn : Control = _find_control_at_position(mouse_pos)
		if btn and btn is Button: _start_drag(btn as Button)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_end_drag()
	elif event is InputEventMouseMotion:
		if _is_dragging: _update_drag_preview()

func _start_drag(btn: Button):
	var slot_type : String = btn.get_meta("slot_type", "")
	if current_mode == Mode.DEPLOY and slot_type == "armor": return
	var item_id : String = btn.get_meta("item_id", "")
	var talent_id : String = btn.get_meta("talent_id", "")
	var refine_id : String = btn.get_meta("refine_id", "")
	if slot_type == "passive_slot" and item_id == "" and refine_id == "": return
	if slot_type in ["library_talent", "talent"] and talent_id == "": return
	if slot_type in ["library_weapon", "weapon"] and item_id == "": return
	if slot_type == "shop_item" and item_id == "": return
	if slot_type == "forge_slot" and item_id == "": return
	if slot_type == "library_refine" and refine_id == "": return
	if slot_type == "armor" and item_id == "": return

	_drag_source = btn
	_drag_meta = {
		"slot_type": slot_type,
		"unit_idx": btn.get_meta("unit_idx", -1),
		"slot_idx": btn.get_meta("slot_idx", -1),
		"item_id": item_id,
		"source_control": btn,
		"shop_index": btn.get_meta("shop_index", -1),
		"talent_id": talent_id,
		"passive_index": btn.get_meta("passive_index", -1),
		"item_price": btn.get_meta("item_price", 0),
		"forge_slot_index": btn.get_meta("forge_slot_index", -1),
		"refine_id": refine_id,
	}
	if slot_type == "shop_item" and shop_manager:
		var shop_idx : int = _drag_meta["shop_index"]
		if shop_idx != -1:
			var items : Array = shop_manager.get_shop_items()
			if shop_idx >= 0 and shop_idx < items.size():
				var entry : Variant = items[shop_idx]
				if entry != null:
					var entry_dict : Dictionary = entry
					_drag_meta["item_data"] = entry_dict["item_data"]
					_drag_meta["item_price"] = entry_dict["price"]
	# ★ 拖拽武器时，把费用显示在升级槽
	if slot_type == "weapon" and (current_mode == Mode.FORGE or (_is_shop_rest_mode() and current_tab == "arena_forge")):
		_update_upgrade_slot_for_drag(btn.get_meta("unit_idx", -1))
	var btn_rect : Rect2 = btn.get_global_rect()
	var btn_center : Vector2 = btn_rect.position + btn_rect.size / 2
	_drag_grab_offset = get_global_mouse_position() - btn_center
	_begin_dragging()

func _begin_dragging():
	if _is_dragging: return
	_is_dragging = true
	var btn : Button = _drag_source
	if not btn: return
	btn.set_meta("_original_disabled", btn.disabled)
	btn.set_meta("_original_modulate", btn.modulate)
	btn.set_meta("_original_text", btn.text)
	btn.set_meta("_original_custom_minimum_size", btn.custom_minimum_size)
	var current_size : Vector2 = btn.custom_minimum_size
	if current_size == Vector2.ZERO or current_size.y < 10: current_size = btn.size
	if current_size.y < 10: current_size.y = 16
	btn.custom_minimum_size = current_size
	btn.disabled = true
	btn.modulate = Color(0.3, 0.3, 0.3, 1.0)
	btn.text = "空"
	_drag_preview = _create_drag_preview(btn)
	var canvas : Node = get_parent()
	if canvas and canvas is CanvasLayer: canvas.add_child(_drag_preview)
	else: add_child(_drag_preview)
	_update_drag_preview()
	_update_targets_visuals()

func _update_drag_preview():
	if not _drag_preview: return
	var mouse_pos : Vector2 = get_global_mouse_position()
	var preview_center : Vector2 = mouse_pos - _drag_grab_offset
	_drag_preview.position = preview_center - _drag_preview.size / 2
	_drag_preview.z_index = 100

func _end_drag():
	if not _is_dragging: return
	if _has_active_confirm_ui():
		if _drag_preview: _drag_preview.queue_free(); _drag_preview = null
		_is_dragging = false
		_reset_targets_visuals(); _restore_drag_source()
		_drag_source = null; _drag_meta = {}
		return
	var mouse_pos : Vector2 = get_global_mouse_position()
	var target : Control = _get_target_from_position(mouse_pos)
	var valid : bool = (target != null) and _is_valid_drop(_drag_meta, target)
	var drop_data : Dictionary = _drag_meta.duplicate()
	var source_type : String = drop_data.get("slot_type", "")
	if _drag_preview: _drag_preview.queue_free(); _drag_preview = null
	_is_dragging = false
	_reset_targets_visuals()
	_restore_drag_source()
	if valid:
		_execute_drop.call_deferred(drop_data, target)
		SoundManager.play_select_sound()
	else:
		if (current_mode == Mode.FORGE or (_is_shop_rest_mode() and current_tab == "arena_forge")) \
				and source_type == "forge_slot" and target == null:
			_execute_forge_slot_return.call_deferred(drop_data)
			SoundManager.play_select_sound()
		else:
			SoundManager.play_cancel_sound()
			if source_type == "shop_item":
				_hint_shop_purchase_failed(drop_data, target)
			_schedule_build_ui()
	# ★ 拖拽结束后恢复升级槽
	if source_type == "weapon" and (current_mode == Mode.FORGE or (_is_shop_rest_mode() and current_tab == "arena_forge")):
		_refresh_forge_upgrade_ui()
	_drag_source = null
	_drag_meta = {}

func _hint_shop_purchase_failed(data: Dictionary, target: Control) -> void:
	var item_data : ItemData = data.get("item_data")
	if not item_data:
		_show_detail_in_zone("无法购买：商品已售罄"); return
	var item_name : String = item_data.name
	if target == null:
		_show_detail_in_zone("无法购买 %s\n请拖到左侧单位槽位" % item_name); return
	var ttype : String = target.get_meta("slot_type", "")
	if ttype == "" or target == discard_zone:
		_show_detail_in_zone("无法购买 %s\n请拖到左侧单位槽位" % item_name); return
	if ttype == "armor":
		if item_data.type != "armor":
			_show_detail_in_zone("无法购买 %s\n该物品不是防具" % item_name); return
		var tu : int = target.get_meta("unit_idx", -1)
		var ts : int = target.get_meta("slot_idx", -1)
		if tu < 0 or ts < 0:
			_show_detail_in_zone("无法购买 %s\n目标槽无效" % item_name); return
		var unit : UnitData = party[tu]
		if unit.armor_slots[ts] != null:
			_show_detail_in_zone("无法购买 %s\n目标槽已有防具，请拖到空槽" % item_name); return
		var need : int = _inst_slots_for_id(item_data.id)
		var used : int = _used_slots_excluding(unit, [ts])
		var free : int = unit.max_armor_slots - used
		_show_detail_in_zone("无法购买 %s\n需要 %d 格，单位只剩 %d 格" % [item_name, need, free]); return
	if ttype == "weapon":
		if item_data.type != "weapon":
			_show_detail_in_zone("无法购买 %s\n该物品不是武器" % item_name); return
		_show_detail_in_zone("无法购买 %s" % item_name); return
	_show_detail_in_zone("无法购买 %s\n请拖到对应的单位槽位" % item_name)

func _restore_drag_source():
	if not is_instance_valid(_drag_source): return
	_drag_source.disabled = _drag_source.get_meta("_original_disabled", false)
	var orig_mod : Variant = _drag_source.get_meta("_original_modulate", Color.WHITE)
	_drag_source.modulate = orig_mod
	var orig_text : Variant = _drag_source.get_meta("_original_text", "")
	_drag_source.text = orig_text
	var orig_size : Variant = _drag_source.get_meta("_original_custom_minimum_size", Vector2.ZERO)
	_drag_source.custom_minimum_size = orig_size
	_drag_source.remove_meta("_original_disabled")
	_drag_source.remove_meta("_original_modulate")
	_drag_source.remove_meta("_original_text")
	_drag_source.remove_meta("_original_custom_minimum_size")

func _process(_delta):
	if _is_dragging: _update_drag_preview()


# ============================================================
#  底部按钮
# ============================================================
func _on_reset_shop_pressed():
	if current_mode == Mode.FORGE: _on_forge_clear_pressed(); return
	if _is_shop_rest_mode():
		if current_tab == "arena_forge": _on_forge_clear_pressed(); return
	if current_mode != Mode.SHOP and not (_is_shop_rest_mode() and current_tab == "arena_shop"): return
	if not shop_manager: return
	var cost : int = shop_manager.get_reset_cost()
	if _context.get_gold() < cost:
		Globals.show_confirm(self, "金币不足！", "确定", "", func(): pass, func(): pass, false); return
	var spent : int = shop_manager.reset_shop()
	if spent >= 0:
		SoundManager.play_select_sound()
		_update_gold_display()
		reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"

func _on_confirm_pressed():
	if current_mode == Mode.FORGE: _on_forge_craft_pressed(); return
	if current_mode == Mode.ARENA_REST:
		var unresolved : int = _return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return

	var target_units : Array = _context.get_units()
	for i in range(min(party.size(), target_units.size())):
		var u : UnitData = party[i]
		var tu : UnitData = target_units[i]
		tu.weapon_slot = u.weapon_slot
		tu.armor_slots = u.armor_slots.duplicate()
		tu.max_armor_slots = u.max_armor_slots
		tu.talent_slots = u.talent_slots.duplicate()

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
	for child in container.get_children(): container.remove_child(child); child.free()

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
			tu.weapon_slot = u.weapon_slot
			tu.armor_slots = u.armor_slots.duplicate()
			tu.max_armor_slots = u.max_armor_slots
			tu.talent_slots = u.talent_slots.duplicate()


# ============================================================
#  特技兼容
# ============================================================
func _check_talent_compatibility(data: Dictionary, target: Control) -> bool:
	var source_type : String = data.get("slot_type", "")
	var talent_id : String = data.get("talent_id", "")
	if talent_id == "": return false
	var target_unit_idx : int = target.get_meta("unit_idx", -1)
	var target_slot_idx : int = target.get_meta("slot_idx", -1)
	if target_unit_idx == -1: return false
	var target_unit : UnitData = party[target_unit_idx]
	if not TalentManager.is_talent_compatible_with_unit(talent_id, target_unit.unit_name): return false
	if source_type == "library_talent":
		if _is_talent_already_equipped(talent_id, -1, -1): return false
	elif source_type == "talent":
		var src_unit_idx : int = data.get("unit_idx", -1)
		var src_slot_idx : int = data.get("slot_idx", -1)
		var tgt_inst : TalentInstance = target_unit.talent_slots[target_slot_idx]
		var tgt_tid : String = tgt_inst.talent_id if tgt_inst and tgt_inst.is_active else ""
		if tgt_tid == "":
			if _is_talent_already_equipped(talent_id, target_unit_idx, target_slot_idx): return false
		else:
			if _is_talent_already_equipped(tgt_tid, src_unit_idx, src_slot_idx): return false
			if _is_talent_already_equipped(talent_id, target_unit_idx, target_slot_idx): return false
	return true

func _is_talent_already_equipped(talent_id: String, exclude_unit_idx: int = -1, exclude_slot_idx: int = -1) -> bool:
	for i in range(party.size()):
		if i == exclude_unit_idx: continue
		var u : UnitData = party[i]
		for slot_idx in range(u.talent_slots.size()):
			if slot_idx == exclude_slot_idx and i == exclude_unit_idx: continue
			var inst : TalentInstance = u.talent_slots[slot_idx]
			if inst and inst.is_active and inst.talent_id == talent_id: return true
	return false

func _get_unit_with_talent(talent_id: String) -> String:
	for i in range(party.size()):
		var u : UnitData = party[i]
		for inst in u.talent_slots:
			if inst and inst.is_active and inst.talent_id == talent_id:
				return u.display_name
	return ""

func _is_talent_equipped_anywhere(talent_id: String) -> bool:
	for i in range(party.size()):
		var u : UnitData = party[i]
		for inst in u.talent_slots:
			if inst and inst.is_active and inst.talent_id == talent_id: return true
	return false


# ============================================================
#  样式
# ============================================================
func _create_drag_preview(btn: Button) -> Label:
	var preview := Label.new()
	var orig_text : Variant = btn.get_meta("_original_text", "")
	preview.text = orig_text
	var font_size : int = btn.get_theme_font_size("font_size")
	if font_size > 0: preview.add_theme_font_size_override("font_size", font_size)
	preview.autowrap_mode = btn.autowrap_mode
	preview.horizontal_alignment = btn.alignment
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font_color : Color = btn.get_theme_color("font_color")
	if font_color: preview.add_theme_color_override("font_color", font_color)
	var orig_mod : Variant = btn.get_meta("_original_modulate", Color.WHITE)
	preview.modulate = orig_mod
	var preview_size : Vector2 = btn.custom_minimum_size
	if preview_size == Vector2.ZERO or preview_size.y < 10: preview_size = btn.size
	if preview_size == Vector2.ZERO or preview_size.y < 10: preview_size = Vector2(50, 20)
	if preview_size.y < 14: preview_size.y = 14
	preview.size = preview_size
	var original_style : StyleBox = btn.get_theme_stylebox("normal")
	if original_style:
		var new_style := StyleBoxFlat.new()
		if original_style is StyleBoxFlat:
			var fs : StyleBoxFlat = original_style
			new_style.bg_color = fs.bg_color
			new_style.border_width_left = fs.border_width_left
			new_style.border_width_right = fs.border_width_right
			new_style.border_width_top = fs.border_width_top
			new_style.border_width_bottom = fs.border_width_bottom
			new_style.border_color = fs.border_color
		else:
			new_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
			new_style.border_width_left = 1
			new_style.border_width_right = 1
			new_style.border_width_top = 1
			new_style.border_width_bottom = 1
			new_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		preview.add_theme_stylebox_override("normal", new_style)
	preview.text_overrun_behavior = btn.text_overrun_behavior
	preview.clip_text = btn.clip_text
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview

func _create_styled_button(font_size: int, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn

func _create_label(text: String, font_size: int, center: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if center:
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _show_detail_in_zone(text: String):
	var detail_label : Label = $VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/DetailLabel
	if detail_label: detail_label.text = text

func _clear_detail_zone():
	var detail_label : Label = $VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/DetailLabel
	if detail_label: detail_label.text = "选中物品详情"

func _execute_talent_remove(data: Dictionary):
	var unit_idx : int = data.get("unit_idx", -1)
	var slot_idx : int = data.get("slot_idx", -1)
	if unit_idx == -1 or slot_idx == -1: return
	var u : UnitData = party[unit_idx]
	u.talent_slots[slot_idx] = null
	_sync_all(); _refresh_after_talent_change()

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

func _on_relic_hover_entered(relic_id: String):
	var data : Dictionary = RelicManager.get_relic_data(relic_id)
	if not data.is_empty(): _show_relic_detail_in_zone(data)
func _on_relic_hover_exited(): _clear_detail_zone()

func _on_refine_hover_entered(refine_id: String):
	var recipe : Dictionary = RefineManager.get_recipe(refine_id)
	if recipe.is_empty(): return
	var lines : Array = []
	lines.append(recipe.get("name", refine_id))
	lines.append(recipe.get("description", ""))
	_show_detail_in_zone("\n".join(lines))
func _on_refine_hover_exited(): _clear_detail_zone()

func _cleanup_forge_ui():
	for n_name in ["ForgeResultLabel", "ForgeCraftRow", "ForgeUpgradeLabel", "ForgeUpgradeBtn",
					"ForgeUpgradeSpacer1", "ForgeUpgradeSpacer2", "ForgeBottomSpacer"]:
		var n : Node = right_container.get_node_or_null(n_name)
		if n:
			right_container.remove_child(n)
			n.queue_free()
	forge_result_label = null
	forge_upgrade_btn = null
	forge_upgrade_label = null
	inline_craft_btn = null

func _is_forge_recipe_available() -> bool:
	if _forge_matched_recipe == "": return false
	if _context.get_context_id() == "arena": return true
	return _forge_matched_recipe in GameState.unlocked_recipes
