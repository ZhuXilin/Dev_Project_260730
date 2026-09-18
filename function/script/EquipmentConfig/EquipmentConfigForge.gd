class_name EquipmentConfigForge
extends RefCounted

const Style = preload("res://function/script/EquipmentConfig/EquipmentConfigStyle.gd")

const MAX_SLOTS : int = 3
const WEAPON_UPGRADE_MAX : int = 3
const UPGRADE_BASE_COST : int = 50
const UPGRADE_GROWTH : float = 2.0
const CRAFT_COST : int = 50

var panel = null
var forge_slots : Array = []
var forge_matched_recipe : String = ""
var forge_result_label : Label = null
var forge_upgrade_label : Label = null
var forge_upgrade_btn : Button = null
var inline_craft_btn : Button = null


func _init(p):
	panel = p


# ============================================================
#  状态
# ============================================================
func init_slots():
	forge_slots.clear()
	for i in range(MAX_SLOTS):
		forge_slots.append(null)
	forge_matched_recipe = ""


func has_pending() -> bool:
	for entry in forge_slots:
		if entry != null: return true
	return false


# ============================================================
#  UI 构建
# ============================================================
func build_forge_slots():
	panel._clear_container(panel.shop_container)
	inline_craft_btn = null

	panel.shop_container.columns = MAX_SLOTS
	panel.shop_container.visible = true
	panel.shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.shop_container.add_theme_constant_override("h_separation", 2)
	panel.shop_container.add_theme_constant_override("v_separation", 2)

	if panel.shop_scroll:
		panel.shop_scroll.custom_minimum_size = Vector2(0, 22)
		panel.shop_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	_ensure_forge_result_label()

	for i in range(MAX_SLOTS):
		var slot_btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
		slot_btn.set_meta("slot_type", "forge_slot")
		slot_btn.set_meta("forge_slot_index", i)
		slot_btn.text = "空槽 %d" % (i + 1)
		slot_btn.modulate = Color(0.5, 0.5, 0.5)
		var entry : Variant = forge_slots[i] if i < forge_slots.size() else null
		if entry != null:
			var entry_dict : Dictionary = entry
			var inst : ItemInstance = entry_dict["inst"]
			var data : ItemData = ItemManager.get_item_data(inst.item_id)
			slot_btn.text = data.name if data else inst.item_id
			slot_btn.set_meta("item_id", inst.item_id)
			if data:
				slot_btn.modulate = UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE)
			slot_btn.mouse_entered.connect(panel._on_button_hover_entered.bind(inst.item_id))
			slot_btn.mouse_exited.connect(panel._on_button_hover_exited)
		else:
			slot_btn.set_meta("item_id", "")
		panel.shop_container.add_child(slot_btn)

	_update_forge_result_label()
	_ensure_forge_craft_row()
	_ensure_forge_upgrade_ui()
	_refresh_inline_craft_btn()
	_ensure_forge_bottom_spacer()


func _ensure_forge_craft_row():
	var should_show : bool = panel._is_shop_rest_mode() or panel.is_forge_mode()
	var existing : Node = panel.right_container.get_node_or_null("ForgeCraftRow")

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
		panel.right_container.add_child(row)
		var scroll_idx : int = panel.shop_scroll.get_index()
		panel.right_container.move_child(row, scroll_idx + 1)

	for c in row.get_children(): c.queue_free()

	inline_craft_btn = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	inline_craft_btn.custom_minimum_size = Vector2(72, 16)
	inline_craft_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inline_craft_btn.text = "合成"
	inline_craft_btn.set_meta("slot_type", "forge_craft_btn")
	inline_craft_btn.pressed.connect(on_forge_craft_pressed)
	row.add_child(inline_craft_btn)

	_refresh_inline_craft_btn()


func _refresh_inline_craft_btn():
	if not inline_craft_btn or not is_instance_valid(inline_craft_btn): return
	if forge_matched_recipe == "":
		inline_craft_btn.text = "合成"
		inline_craft_btn.disabled = true
		inline_craft_btn.modulate = Color(0.5, 0.5, 0.5)
		return
	if not _is_forge_recipe_available():
		inline_craft_btn.text = "未解锁"
		inline_craft_btn.disabled = true
		inline_craft_btn.modulate = Color(0.5, 0.5, 0.5)
		return
	inline_craft_btn.text = "合成 %dG" % CRAFT_COST
	var can_afford : bool = panel._context.get_gold() >= CRAFT_COST
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
	panel.right_container.add_child(forge_result_label)
	var scroll_idx : int = panel.shop_scroll.get_index()
	panel.right_container.move_child(forge_result_label, scroll_idx + 1)


func display_recipe_info():
	var input_ids : Array = []
	for entry in forge_slots:
		if entry != null:
			var entry_dict : Dictionary = entry
			var inst : ItemInstance = entry_dict["inst"]
			input_ids.append(inst.item_id)
	if input_ids.is_empty():
		panel._show_detail_in_zone("将防具拖入插槽以匹配配方")
		forge_matched_recipe = ""
		_update_forge_result_label()
		return
	forge_matched_recipe = RecipeManager.match_recipe(input_ids)
	if forge_matched_recipe == "":
		var names : Array = []
		for id in input_ids:
			var d : ItemData = ItemManager.get_item_data(id)
			names.append(d.name if d else id)
		panel._show_detail_in_zone("无匹配配方\n\n已放: " + ", ".join(names))
		_update_forge_result_label()
		return

	var recipe : RecipeData = RecipeManager.get_recipe(forge_matched_recipe)
	var out_data : ItemData = ItemManager.get_item_data(forge_matched_recipe)
	var lines : Array = []
	lines.append("匹配配方: " + (out_data.name if out_data else forge_matched_recipe))

	if not _is_forge_recipe_available():
		lines.append("")
		lines.append("⚠ 此配方未解锁")
		lines.append("前往铁砧酒馆 → 武备库 → 防具")
		lines.append("消耗材料解锁后可合成")
		panel._show_detail_in_zone("\n".join(lines))
		_update_forge_result_label()
		return

	lines.append("")
	lines.append("消耗:")
	for id in recipe.inputs:
		var d : ItemData = ItemManager.get_item_data(id)
		lines.append("  " + (d.name if d else id))
	lines.append("")
	lines.append("金币: %dG" % CRAFT_COST)
	lines.append("→ 产物: " + (out_data.name if out_data else forge_matched_recipe))
	panel._show_detail_in_zone("\n".join(lines))
	_update_forge_result_label()


func _update_forge_result_label():
	if not forge_result_label or not is_instance_valid(forge_result_label): return
	if forge_matched_recipe == "":
		forge_result_label.text = "合成结果：—"
		forge_result_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		var out_data : ItemData = ItemManager.get_item_data(forge_matched_recipe)
		var out_name : String = out_data.name if out_data else forge_matched_recipe
		if not _is_forge_recipe_available():
			forge_result_label.text = "合成结果：%s（未解锁）" % out_name
			forge_result_label.modulate = Color(0.5, 0.5, 0.5)
		else:
			forge_result_label.text = "合成结果：%s（%dG）" % [out_name, CRAFT_COST]
			if out_data:
				forge_result_label.modulate = UIConst.QUALITY_COLORS.get(out_data.quality, Color.WHITE)
			else:
				forge_result_label.modulate = Color.WHITE
	_refresh_inline_craft_btn()


func _ensure_forge_upgrade_ui():
	if forge_upgrade_btn and is_instance_valid(forge_upgrade_btn) and forge_upgrade_btn.is_inside_tree():
		refresh_forge_upgrade_ui(); return
	var spacer1 := Control.new()
	spacer1.name = "ForgeUpgradeSpacer1"
	spacer1.custom_minimum_size = Vector2(0, 12)
	panel.right_container.add_child(spacer1)
	forge_upgrade_label = Label.new()
	forge_upgrade_label.name = "ForgeUpgradeLabel"
	forge_upgrade_label.add_theme_font_size_override("font_size", Style.FONT_SMALL)
	forge_upgrade_label.text = "拖拽武器到此升级（上限 +3）"
	forge_upgrade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_upgrade_label.modulate = Color(0.7, 0.7, 0.7)
	panel.right_container.add_child(forge_upgrade_label)
	forge_upgrade_btn = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	forge_upgrade_btn.name = "ForgeUpgradeBtn"
	forge_upgrade_btn.set_meta("slot_type", "forge_upgrade_slot")
	panel.right_container.add_child(forge_upgrade_btn)
	var spacer2 := Control.new()
	spacer2.name = "ForgeUpgradeSpacer2"
	spacer2.custom_minimum_size = Vector2(0, 12)
	panel.right_container.add_child(spacer2)
	var reset_idx : int = panel.reset_btn.get_index()
	panel.right_container.move_child(spacer1, reset_idx + 1)
	panel.right_container.move_child(forge_upgrade_label, reset_idx + 2)
	panel.right_container.move_child(forge_upgrade_btn, reset_idx + 3)
	panel.right_container.move_child(spacer2, reset_idx + 4)
	refresh_forge_upgrade_ui()


func refresh_forge_upgrade_ui():
	if not forge_upgrade_btn or not is_instance_valid(forge_upgrade_btn): return
	if panel.party.size() <= 0:
		forge_upgrade_btn.text = "拖拽武器到此升级"
		forge_upgrade_btn.disabled = false
		forge_upgrade_btn.modulate = Color.WHITE
		return
	var u : UnitData = panel.party[0]
	if u.weapon_slot == null:
		forge_upgrade_btn.text = "拖拽武器到此升级"
		forge_upgrade_btn.disabled = false
		forge_upgrade_btn.modulate = Color.WHITE
		return
	var wname : String = panel._get_item_name(u.weapon_slot)
	var lv : int = u.weapon_slot.upgrade_level
	if lv >= WEAPON_UPGRADE_MAX:
		forge_upgrade_btn.text = "%s 已满级 +%d" % [wname, lv]
		forge_upgrade_btn.disabled = false
		forge_upgrade_btn.modulate = Color(0.5, 0.5, 0.5)
		return
	var cost : int = _get_weapon_upgrade_cost(lv)
	var afford : bool = panel._context.get_gold() >= cost
	forge_upgrade_btn.text = "%s +%d→+%d（%dG）" % [wname, lv, lv + 1, cost]
	forge_upgrade_btn.disabled = false
	forge_upgrade_btn.modulate = Color.WHITE if afford else Color(1.0, 0.6, 0.6)


func update_upgrade_slot_for_drag(unit_idx: int) -> void:
	if not forge_upgrade_btn or not is_instance_valid(forge_upgrade_btn): return
	if unit_idx < 0 or unit_idx >= panel.party.size(): return
	var u : UnitData = panel.party[unit_idx]
	if u.weapon_slot == null: return
	var wname : String = panel._get_item_name(u.weapon_slot)
	var lv : int = u.weapon_slot.upgrade_level
	if lv >= WEAPON_UPGRADE_MAX:
		forge_upgrade_btn.text = "★ %s 已满级 +%d" % [wname, lv]
		forge_upgrade_btn.modulate = Color(0.5, 0.5, 0.5)
		return
	var cost : int = _get_weapon_upgrade_cost(lv)
	var afford : bool = panel._context.get_gold() >= cost
	forge_upgrade_btn.text = "★ %s +%d→+%d（%dG）" % [wname, lv, lv + 1, cost]
	forge_upgrade_btn.modulate = Color.WHITE if afford else Color(1.0, 0.6, 0.6)


func _ensure_forge_bottom_spacer():
	var spacer : Control = panel.right_container.get_node_or_null("ForgeBottomSpacer")
	if spacer == null:
		spacer = Control.new()
		spacer.name = "ForgeBottomSpacer"
		panel.right_container.add_child(spacer)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL


func cleanup():
	for n_name in ["ForgeResultLabel", "ForgeCraftRow", "ForgeUpgradeLabel", "ForgeUpgradeBtn",
					"ForgeUpgradeSpacer1", "ForgeUpgradeSpacer2", "ForgeBottomSpacer"]:
		var n : Node = panel.right_container.get_node_or_null(n_name)
		if n:
			panel.right_container.remove_child(n)
			n.queue_free()
	forge_result_label = null
	forge_upgrade_btn = null
	forge_upgrade_label = null
	inline_craft_btn = null


# ============================================================
#  归还 / 清空
# ============================================================
func _return_armor_to_unit(unit: UnitData, inst: ItemInstance, prefer_slot: int) -> bool:
	var need : int = panel._inst_slots(inst)
	var used : int = panel._used_slots_of(unit)
	if used + need > unit.max_armor_slots: return false
	if prefer_slot >= 0 and prefer_slot < unit.armor_slots.size() and unit.armor_slots[prefer_slot] == null:
		unit.armor_slots[prefer_slot] = inst
		return true
	for i in range(unit.armor_slots.size()):
		if unit.armor_slots[i] == null:
			unit.armor_slots[i] = inst
			return true
	return false


func return_all_forge_slots() -> int:
	var unresolved : int = 0
	for i in range(forge_slots.size()):
		var entry : Variant = forge_slots[i]
		if entry == null: continue
		var entry_dict : Dictionary = entry
		var ou : UnitData = panel.party[entry_dict["origin_unit"]]
		var origin_slot : int = entry_dict["origin_slot"]
		if _return_armor_to_unit(ou, entry_dict["inst"], origin_slot):
			forge_slots[i] = null
		else:
			unresolved += 1
	if unresolved == 0:
		forge_matched_recipe = ""
	return unresolved


func execute_forge_slot_return(data: Dictionary):
	var idx : int = data.get("forge_slot_index", -1)
	if idx < 0 or idx >= forge_slots.size(): return
	var entry : Variant = forge_slots[idx]
	if entry == null:
		display_recipe_info(); panel._schedule_build_ui(); return
	var entry_dict : Dictionary = entry
	var ou : UnitData = panel.party[entry_dict["origin_unit"]]
	var origin_slot : int = entry_dict["origin_slot"]
	if not _return_armor_to_unit(ou, entry_dict["inst"], origin_slot):
		panel._show_detail_in_zone("原槽已被占用且没有空槽，请先腾出空间")
		return
	forge_slots[idx] = null
	panel._build_unit_columns()
	display_recipe_info()
	panel._schedule_build_ui()


func on_forge_clear_pressed():
	var unresolved_count : int = return_all_forge_slots()
	panel._build_unit_columns()
	if unresolved_count > 0:
		panel._show_detail_in_zone("有 %d 件防具无法归还（单位已满），已保留在合成槽" % unresolved_count)
	else:
		display_recipe_info()
	panel._schedule_build_ui()


# ============================================================
#  合成
# ============================================================
func on_forge_craft_pressed():
	if forge_matched_recipe == "": return

	if not _is_forge_recipe_available():
		Globals.show_confirm(panel, "未解锁此配方\n请前往铁砧酒馆解锁", "确定", "", func(): pass, func(): pass, false)
		return

	var recipe : RecipeData = RecipeManager.get_recipe(forge_matched_recipe)
	if not recipe: return

	var entries : Array = []
	for entry in forge_slots:
		if entry != null: entries.append(entry)
	if entries.size() != recipe.inputs.size(): return

	var first_entry : Dictionary = entries[0]
	var check_unit_idx : int = first_entry["origin_unit"]
	var check_unit : UnitData = panel.party[check_unit_idx]

	var input_slots_for_check : Array = []
	for e in entries:
		var e_dict : Dictionary = e
		if e_dict["origin_unit"] == check_unit_idx:
			input_slots_for_check.append(e_dict["origin_slot"])

	var used_after : int = panel._used_slots_excluding(check_unit, input_slots_for_check)
	var out_need : int = panel._inst_slots_for_id(forge_matched_recipe)
	if used_after + out_need > check_unit.max_armor_slots:
		Globals.show_confirm(panel, "合成后防具格数不足！", "确定", "", func(): pass, func(): pass, false)
		return

	if panel._context.get_gold() < CRAFT_COST:
		panel._show_buy_failure_message("not_enough_gold"); return
	if not panel._context.subtract_gold(CRAFT_COST):
		panel._show_buy_failure_message("not_enough_gold"); return

	var out_inst := ItemInstance.new()
	out_inst.item_id = forge_matched_recipe
	out_inst.count = 1
	var first_unit : UnitData = panel.party[first_entry["origin_unit"]]
	first_unit.armor_slots[first_entry["origin_slot"]] = out_inst

	for i in range(1, entries.size()):
		var e_dict : Dictionary = entries[i]
		var eu : UnitData = panel.party[e_dict["origin_unit"]]
		eu.armor_slots[e_dict["origin_slot"]] = null

	forge_slots.clear()
	for i in range(MAX_SLOTS): forge_slots.append(null)
	forge_matched_recipe = ""

	panel._sync_all()
	panel._build_unit_columns()
	panel._update_gold_display()
	panel._schedule_build_ui()


func _get_weapon_upgrade_cost(level: int) -> int:
	return int(UPGRADE_BASE_COST * pow(UPGRADE_GROWTH, level))


func _is_forge_recipe_available() -> bool:
	if forge_matched_recipe == "": return false
	if panel._context.get_context_id() == "arena": return true
	return forge_matched_recipe in GameState.unlocked_recipes


# ============================================================
#  拖拽合法性 / 执行
# ============================================================
func is_valid_forge_drop(data: Dictionary, target: Control) -> bool:
	var src_type : String = data.get("slot_type", "")
	var tgt_type : String = target.get_meta("slot_type", "")

	if src_type == "weapon" and tgt_type == "forge_upgrade_slot":
		var uidx : int = data.get("unit_idx", -1)
		if uidx < 0: return false
		var u : UnitData = panel.party[uidx]
		var weapon_inst : ItemInstance = u.weapon_slot
		if weapon_inst == null: return false
		if weapon_inst.upgrade_level >= WEAPON_UPGRADE_MAX: return false
		return true

	if src_type == "weapon" and tgt_type == "weapon":
		var src_unit : int = data.get("unit_idx", -1)
		var tgt_unit : int = target.get_meta("unit_idx", -1)
		return src_unit >= 0 and tgt_unit >= 0 and src_unit != tgt_unit

	if src_type == "weapon" and target == panel.discard_zone: return false

	if src_type == "armor" and tgt_type == "forge_slot":
		var slot_idx : int = target.get_meta("forge_slot_index", -1)
		if slot_idx < 0: return false
		var uidx2 : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		if uidx2 < 0 or src_slot < 0: return false
		var u2 : UnitData = panel.party[uidx2]
		if u2.armor_slots[src_slot] == null: return false
		var existing : Variant = forge_slots[slot_idx]
		if existing != null:
			var existing_dict : Dictionary = existing
			var old_ou : UnitData = panel.party[existing_dict["origin_unit"]]
			var old_inst : ItemInstance = existing_dict["inst"]
			var need : int = panel._inst_slots(old_inst)
			var used : int = panel._used_slots_of(old_ou)
			if used + need > old_ou.max_armor_slots: return false
		return true

	if src_type == "armor" and tgt_type == "armor":
		return panel._check_armor_swap_budget(data, target)

	if src_type == "armor" and target == panel.discard_zone: return true

	if src_type == "forge_slot":
		if tgt_type == "armor":
			var tu3 : int = target.get_meta("unit_idx", -1)
			var ts3 : int = target.get_meta("slot_idx", -1)
			if tu3 < 0 or ts3 < 0: return false
			var unit3 : UnitData = panel.party[tu3]
			if unit3.armor_slots[ts3] != null: return false
			var idx : int = data.get("forge_slot_index", -1)
			if idx < 0 or idx >= forge_slots.size() or forge_slots[idx] == null: return false
			var entry_dict : Dictionary = forge_slots[idx]
			var inst : ItemInstance = entry_dict["inst"]
			var need : int = panel._inst_slots(inst)
			var used : int = panel._used_slots_excluding(unit3, [ts3])
			return used + need <= unit3.max_armor_slots
		if tgt_type == "forge_slot": return true
		if target == panel.discard_zone: return true
		return false
	return false


func execute_forge_drop(data: Dictionary, target: Control):
	var src_type : String = data.get("slot_type", "")
	var tgt_type : String = target.get_meta("slot_type", "")

	if src_type == "weapon" and tgt_type == "forge_upgrade_slot":
		var uidx : int = data.get("unit_idx", -1)
		if uidx < 0: return
		var u : UnitData = panel.party[uidx]
		var weapon_inst : ItemInstance = u.weapon_slot
		if weapon_inst == null: return
		if weapon_inst.upgrade_level >= WEAPON_UPGRADE_MAX: return
		var lv : int = weapon_inst.upgrade_level
		var cost : int = _get_weapon_upgrade_cost(lv)
		if panel._context.get_gold() < cost:
			panel._show_buy_failure_message("not_enough_gold"); return
		if not panel._context.subtract_gold(cost):
			panel._show_buy_failure_message("not_enough_gold"); return
		weapon_inst.upgrade_level += 1
		refresh_forge_upgrade_ui()
		panel._build_unit_columns()
		panel._sync_all(); panel._update_gold_display(); panel._schedule_build_ui(); return

	if src_type == "weapon" and tgt_type == "weapon":
		panel._swap_weapons(data, target); return
	if src_type == "armor" and tgt_type == "armor":
		panel._swap_armor(data, target); return

	if target == panel.discard_zone:
		if src_type == "forge_slot":
			var src_idx : int = data.get("forge_slot_index", -1)
			if src_idx >= 0 and src_idx < forge_slots.size(): forge_slots[src_idx] = null
			display_recipe_info(); panel._schedule_build_ui(); return
		if src_type == "armor":
			var uidx : int = data.get("unit_idx", -1)
			var sidx : int = data.get("slot_idx", -1)
			if uidx >= 0 and sidx >= 0:
				var du : UnitData = panel.party[uidx]
				du.armor_slots[sidx] = null
			panel._build_unit_columns()
			panel._sync_all(); panel._schedule_build_ui(); return
		return

	if src_type == "forge_slot" and tgt_type == "armor":
		var from_idx : int = data.get("forge_slot_index", -1)
		if from_idx < 0 or from_idx >= forge_slots.size(): return
		var entry : Variant = forge_slots[from_idx]
		if entry == null: return
		var entry_dict : Dictionary = entry
		var tgt_unit : int = target.get_meta("unit_idx", -1)
		var tgt_slot : int = target.get_meta("slot_idx", -1)
		if tgt_unit < 0 or tgt_slot < 0: return
		var tgt_unit_data : UnitData = panel.party[tgt_unit]
		if tgt_unit_data.armor_slots[tgt_slot] != null: return
		tgt_unit_data.armor_slots[tgt_slot] = entry_dict["inst"]
		forge_slots[from_idx] = null
		panel._build_unit_columns()
		display_recipe_info(); panel._schedule_build_ui(); return

	if src_type == "forge_slot" and tgt_type == "forge_slot":
		var from_idx : int = data.get("forge_slot_index", -1)
		var to_idx : int = target.get_meta("forge_slot_index", -1)
		if from_idx < 0 or to_idx < 0 or from_idx == to_idx: return
		var temp : Variant = forge_slots[from_idx]
		forge_slots[from_idx] = forge_slots[to_idx]
		forge_slots[to_idx] = temp
		display_recipe_info(); panel._schedule_build_ui(); return

	if src_type == "armor" and tgt_type == "forge_slot":
		var slot_idx : int = target.get_meta("forge_slot_index", -1)
		if slot_idx < 0 or slot_idx >= forge_slots.size(): return
		var uidx : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		if uidx < 0 or src_slot < 0: return
		var u : UnitData = panel.party[uidx]
		var inst : ItemInstance = u.armor_slots[src_slot]
		if inst == null: return
		var existing : Variant = forge_slots[slot_idx]
		if existing != null:
			var existing_dict : Dictionary = existing
			var old_ou : UnitData = panel.party[existing_dict["origin_unit"]]
			if not _return_armor_to_unit(old_ou, existing_dict["inst"], existing_dict["origin_slot"]):
				panel._show_detail_in_zone("无法替换：原防具无处归还")
				return
		u.armor_slots[src_slot] = null
		forge_slots[slot_idx] = {"inst": inst, "origin_unit": uidx, "origin_slot": src_slot}
		panel._build_unit_columns()
		display_recipe_info(); panel._schedule_build_ui(); return
