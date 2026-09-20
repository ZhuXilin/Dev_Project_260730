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
		_forge.init_slots()

	if _is_shop_rest_mode():
		current_tab = "arena_shop"

	_copy_party_data()
	_build_ui()

func _on_shop_updated():
	_update_gold_display()
	_schedule_build_ui()

func _on_close_pressed():
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
			mode_label.text = "装备配置 - 战前准备" if _context.get_title() == "" else _context.get_title()
			close_btn.visible = true
			close_btn.text = "返回"
			confirm_btn.visible = true
			confirm_btn.text = "开始探索"
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
			weapon_tab_btn.visible = true
			weapon_tab_btn.text = "商店"
			talent_tab_btn.visible = true
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "铁匠铺"
			if refine_tab_btn: refine_tab_btn.visible = false
			if current_tab == "" or not current_tab.begins_with("arena_"):
				current_tab = "arena_shop"
			_update_tab_style()
			_forge.cleanup()

			if current_tab == "arena_forge":
				_forge.build_forge_slots()
				shop_container.visible = true
				reset_btn.visible = true
				reset_btn.text = "清空插槽"
				_forge.display_recipe_info()
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
			tab_bar.visible = false
			_forge.build_forge_slots()
			shop_container.visible = true
			reset_btn.visible = true
			reset_btn.text = "清空插槽"
			discard_zone.visible = false
			if left_column: left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_forge.display_recipe_info()

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

		var display_str : String
		if unit.advanced_class != "":
			display_str = unit.display_name + "(★" + AdvancedClassManager.get_display_name(unit.advanced_class) + ")"
		else:
			display_str = unit.display_name + "(" + UnitDataManager.get_unit_type_display_name(unit.unit_name) + ")"
		var name_label : Label = Style.create_label(display_str, Style.FONT_SMALL)
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		name_label.mouse_entered.connect(_on_unit_hover_entered.bind(i))
		name_label.mouse_exited.connect(_on_unit_hover_exited)
		col.add_child(name_label)

		col.add_child(Style.create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))

		var weapon_inst : ItemInstance = unit.weapon_slot
		col.add_child(_create_item_button(weapon_inst, "weapon", i, -1))

		col.add_child(Style.create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))

		for slot_idx in range(unit.armor_slots.size()):
			var armor_btn : Button = _create_item_button(unit.armor_slots[slot_idx], "armor", i, slot_idx)
			if current_mode == Mode.DEPLOY: armor_btn.disabled = true
			col.add_child(armor_btn)

		col.add_child(Style.create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))
		col.add_child(Style.create_label("特技", Style.FONT_SMALL))
		var talent_inst : TalentInstance = unit.talent_slots[0] if unit.talent_slots.size() > 0 else null
		col.add_child(_create_talent_button(talent_inst, i, 0))


func _on_unit_hover_entered(unit_idx: int) -> void:
	if unit_idx < 0 or unit_idx >= party.size(): return
	var unit : UnitData = party[unit_idx]

	var display : String = unit.display_name if unit.display_name != "" else unit.unit_name
	var type_name : String = UnitDataManager.get_unit_type_display_name(unit.unit_name)

	var lines : Array = []
	lines.append("%s（%s）" % [display, type_name])
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

	if source_type == "passive_slot":
		if target_type == "passive_slot": return true
		if discard: return true
		return false
	if target_type == "passive_slot":
		if source_type == "library_refine": return true
		return false

	if current_mode == Mode.FORGE: return _forge.is_valid_forge_drop(data, target)
	if _is_shop_rest_mode() and current_tab == "arena_forge": return _forge.is_valid_forge_drop(data, target)

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
				# ★ 允许覆盖已占用的防具槽（旧装备直接丢弃）
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


# ============================================================
#  执行 drop
# ============================================================
func _execute_drop(data: Dictionary, target: Control):
	if data.get("slot_type", "") == "passive_slot":
		if target == discard_zone: _discard_passive(data); return
		if target.get_meta("slot_type", "") == "passive_slot": _swap_passives(data, target); return
	if data.get("slot_type", "") == "library_refine" and target.get_meta("slot_type", "") == "passive_slot":
		_equip_refine_to_slot(data, target); return
	if current_mode == Mode.FORGE: _forge.execute_forge_drop(data, target); return
	if _is_shop_rest_mode() and current_tab == "arena_forge": _forge.execute_forge_drop(data, target); return

	var discard : bool = target == discard_zone
	var source_type : String = data["slot_type"]
	var target_type : String = target.get_meta("slot_type", "")

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
#  Tab 切换
# ============================================================
func _switch_tab(tab: String):
	if current_tab == tab: return
	if _is_shop_rest_mode() and current_tab == "arena_forge":
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return
	current_tab = tab
	_update_tab_style()
	_clear_container(shop_container)
	var is_forge_tab : bool = (tab == "arena_forge") or (current_mode == Mode.FORGE)
	if not is_forge_tab: _forge.cleanup()
	match tab:
		"weapon": _shop.build_weapon_grid(shop_container)
		"talent": _talent.build_talent_grid(shop_container)
		"refine": _shop.build_refine_grid(shop_container)
		"arena_shop":
			_shop.build_shop_items()
			if reset_btn and shop_manager:
				reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
		"arena_forge":
			_forge.build_forge_slots()
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
#  转发（供 Forge / Drag 调用）
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
