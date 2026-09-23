class_name EquipmentConfigForge
extends RefCounted

const Style = preload("res://function/script/EquipmentConfig/EquipmentConfigStyle.gd")

# 品质升级映射
const QUALITY_ORDER : Array = ["common", "rare", "epic", "legendary"]

const MAX_SLOTS : int = 9
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
var _last_drag_unit_idx : int = -1

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
	# ★ 强制清理所有 forge 相关子节点（含 Godot 自动改名的 @xxx@2 残留）
	for child in panel.right_container.get_children():
		if "Forge" in child.name:
			panel.right_container.remove_child(child)
			child.queue_free()
	forge_result_label = null
	forge_upgrade_btn = null
	forge_upgrade_label = null
	inline_craft_btn = null

	panel._clear_container(panel.shop_container)
	inline_craft_btn = null

	panel.shop_container.columns = 3
	panel.shop_container.visible = true
	panel.shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.shop_container.add_theme_constant_override("h_separation", 2)
	panel.shop_container.add_theme_constant_override("v_separation", 2)

	# ★ 铁匠铺：ShopScroll 恢复初始尺寸
	if panel.shop_scroll:
		panel.shop_scroll.custom_minimum_size = Vector2(0, 60)
		panel.shop_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		panel.shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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

	# ★ 强制重建升级 UI（避免 cleanup 残留导致消失）
	if not forge_upgrade_btn or not is_instance_valid(forge_upgrade_btn) or not forge_upgrade_btn.is_inside_tree():
		forge_upgrade_btn = null
		forge_upgrade_label = null
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
	# 存在且在树里 → refresh
	if forge_upgrade_btn and is_instance_valid(forge_upgrade_btn) and forge_upgrade_btn.is_inside_tree():
		refresh_forge_upgrade_ui()
		return

	# 引用存在但已失效 → 清空重来
	if forge_upgrade_btn != null and not is_instance_valid(forge_upgrade_btn):
		forge_upgrade_btn = null
	if forge_upgrade_label != null and not is_instance_valid(forge_upgrade_label):
		forge_upgrade_label = null

	# 清理残留在 right_container 里的同名节点
	for n_name in ["ForgeUpgradeLabel", "ForgeUpgradeBtn", "ForgeUpgradeSpacer1", "ForgeUpgradeSpacer2"]:
		var old = panel.right_container.get_node_or_null(n_name)
		if old:
			panel.right_container.remove_child(old)
			old.queue_free()

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

	if panel.tab_bar and is_instance_valid(panel.tab_bar):
		var tab_idx : int = panel.tab_bar.get_index()
		panel.right_container.move_child(spacer1, tab_idx + 1)
		panel.right_container.move_child(forge_upgrade_label, tab_idx + 2)
		panel.right_container.move_child(forge_upgrade_btn, tab_idx + 3)
		panel.right_container.move_child(spacer2, tab_idx + 4)

	refresh_forge_upgrade_ui()


func refresh_forge_upgrade_ui():
	if not forge_upgrade_btn or not is_instance_valid(forge_upgrade_btn): return
	if panel.party.size() <= 0:
		forge_upgrade_btn.text = "拖拽武器到此升级"
		forge_upgrade_btn.disabled = true
		forge_upgrade_btn.modulate = Color(0.5, 0.5, 0.5)
		return

	# ★ 优先显示"最近拖拽的单位"的武器
	var idx : int = _last_drag_unit_idx
	if idx < 0 or idx >= panel.party.size():
		idx = -1
		for i in range(panel.party.size()):
			if panel.party[i].weapon_slot != null and not panel.party[i].is_dead:
				idx = i
				break
	if idx < 0:
		forge_upgrade_btn.text = "拖拽武器到此升级"
		forge_upgrade_btn.disabled = true
		forge_upgrade_btn.modulate = Color(0.5, 0.5, 0.5)
		return

	var u : UnitData = panel.party[idx]
	if u.weapon_slot == null or u.is_dead:
		forge_upgrade_btn.text = "拖拽武器到此升级"
		forge_upgrade_btn.disabled = true
		forge_upgrade_btn.modulate = Color(0.5, 0.5, 0.5)
		return

	var wname : String = panel._get_item_name(u.weapon_slot)
	var lv : int = u.weapon_slot.upgrade_level
	if lv >= WEAPON_UPGRADE_MAX:
		forge_upgrade_btn.text = "%s 已满级 +%d" % [wname, lv]
		forge_upgrade_btn.disabled = true
		forge_upgrade_btn.modulate = Color(0.5, 0.5, 0.5)
		return

	var cost : int = _get_weapon_upgrade_cost(lv)
	var afford : bool = panel._context.get_gold() >= cost
	forge_upgrade_btn.text = "%s +%d→+%d（%dG）" % [wname, lv, lv + 1, cost]
	forge_upgrade_btn.disabled = not afford
	forge_upgrade_btn.modulate = Color.WHITE if afford else Color(1.0, 0.6, 0.6)


func update_upgrade_slot_for_drag(unit_idx: int) -> void:
	_last_drag_unit_idx = unit_idx
	refresh_forge_upgrade_ui()


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
	if used + need > unit.max_armor_slots: return false      # ← 必须是 false
	if prefer_slot >= 0 and prefer_slot < unit.armor_slots.size() and unit.armor_slots[prefer_slot] == null:
		unit.armor_slots[prefer_slot] = inst
		return true                                          # ← 必须是 true
	for i in range(unit.armor_slots.size()):
		if unit.armor_slots[i] == null:
			unit.armor_slots[i] = inst
			return true                                      # ← 必须是 true
	return false                                             # ← 必须有兜底


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
	# 收集输入
	var input_insts : Array = []
	for entry in forge_slots:
		if entry != null:
			var entry_dict : Dictionary = entry
			input_insts.append(entry_dict["inst"])

	if input_insts.size() == 0:
		Globals.show_confirm(panel, "请先放入防具", "确定", "", func(): pass, func(): pass, false)
		return

	# 检查金币
	var craft_cost : int = CRAFT_COST
	if panel._context.get_gold() < craft_cost:
		panel._show_buy_failure_message("not_enough_gold")
		return

	# ---- 计算结果 ----
	var result : Dictionary = _compute_craft_result(input_insts)

	# ---- 扣金币 ----
	panel._context.subtract_gold(craft_cost)

	# ---- 归还所有输入防具（清空插槽） ----
	for i in range(forge_slots.size()):
		var entry : Variant = forge_slots[i]
		if entry != null:
			var entry_dict : Dictionary = entry
			var ou : UnitData = panel.party[entry_dict["origin_unit"]]
			_force_return_armor_to_unit(ou, entry_dict["inst"], entry_dict["origin_slot"])
			forge_slots[i] = null

	# ---- 产出防具：优先放单位空槽，放不下则进待领取区 ----
	var out_ids : Array = result["item_ids"]

	# 找单位空槽
	var target_unit_idx : int = -1
	var target_slot : int = -1
	for i in range(panel.party.size()):
		var pu : UnitData = panel.party[i]
		if pu.is_dead: continue
		for s in range(pu.armor_slots.size()):
			if pu.armor_slots[s] == null:
				target_unit_idx = i
				target_slot = s
				break
		if target_unit_idx >= 0:
			break

	# 计算单位还能放几件
	var can_place_in_unit : int = 0
	if target_unit_idx >= 0:
		var pu : UnitData = panel.party[target_unit_idx]
		for s in range(target_slot, pu.armor_slots.size()):
			if pu.armor_slots[s] == null:
				can_place_in_unit += 1

	if can_place_in_unit >= out_ids.size():
		# 全部能放单位
		var out_unit : UnitData = panel.party[target_unit_idx]
		for item_id in out_ids:
			if target_slot >= out_unit.armor_slots.size(): break
			var inst := ItemInstance.new()
			inst.item_id = item_id
			inst.count = 1
			if out_unit.armor_slots[target_slot] == null:
				out_unit.armor_slots[target_slot] = inst
				target_slot += 1
	else:
		# 全部进待领取区
		for item_id in out_ids:
			var inst := ItemInstance.new()
			inst.item_id = item_id
			inst.count = 1
			GameState.pending_forge_rewards.append(inst)

	forge_matched_recipe = ""
	SaveManager.auto_save()
	panel._sync_all()
	panel._build_unit_columns()
	panel._build_pending_slots()
	panel._update_gold_display()
	panel._show_craft_result(result)
	panel._schedule_build_ui()


## 计算合成结果
func _compute_craft_result(input_insts : Array) -> Dictionary:
	var count : int = input_insts.size()

	# 输入平均品质
	var quality_sum : int = 0
	for inst in input_insts:
		var data = ItemManager.get_item_data(inst.item_id)
		if data:
			quality_sum += QUALITY_ORDER.find(data.quality)
	var avg_quality_idx : int = quality_sum / max(1, count)
	avg_quality_idx = clampi(avg_quality_idx, 0, QUALITY_ORDER.size() - 1)

	# 品质 +1 概率
	var up_prob : float = 0.0
	if count >= 9:
		up_prob = 0.45
	elif count >= 6:
		up_prob = 0.30
	elif count >= 3:
		up_prob = 0.15

	var final_quality_idx : int = avg_quality_idx
	if randf() < up_prob:
		final_quality_idx = mini(final_quality_idx + 1, QUALITY_ORDER.size() - 1)
	var final_quality : String = QUALITY_ORDER[final_quality_idx]

	# 选一件该品质的防具
	var candidates : Array = []
	for item_id in ItemManager.get_all_item_ids():
		var data = ItemManager.get_item_data(item_id)
		if not data or data.type != "armor":
			continue
		if data.quality == final_quality and data.price > 0:
			candidates.append(item_id)

	# 该品质没候选 → 降级
	while candidates.is_empty() and final_quality_idx > 0:
		final_quality_idx -= 1
		final_quality = QUALITY_ORDER[final_quality_idx]
		for item_id in ItemManager.get_all_item_ids():
			var data = ItemManager.get_item_data(item_id)
			if not data or data.type != "armor":
				continue
			if data.quality == final_quality and data.price > 0:
				candidates.append(item_id)

	if candidates.is_empty():
		candidates = ["wooden_shield"]  # 兜底

	var out_ids : Array = []
	out_ids.append(candidates[randi() % candidates.size()])

	# 9 件时 30% 概率额外产出
	var bonus_count : int = 0
	if count >= 9 and randf() < 0.30:
		bonus_count = 1 + (randi() % 2)  # 1 或 2
		for _i in range(bonus_count):
			out_ids.append(candidates[randi() % candidates.size()])

	return {
		"item_ids": out_ids,
		"quality": final_quality,
		"bonus_count": bonus_count,
	}


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

	# ---- 武器 → 升级槽 ----
	if src_type == "weapon" and tgt_type == "forge_upgrade_slot":
		var uidx : int = data.get("unit_idx", -1)
		if uidx < 0: return false
		if uidx >= panel.party.size(): return false
		var u : UnitData = panel.party[uidx]
		if u.is_dead: return false
		var weapon_inst : ItemInstance = u.weapon_slot
		if weapon_inst == null: return false
		if weapon_inst.upgrade_level >= WEAPON_UPGRADE_MAX: return false
		return true

	# ---- 武器 ↔ 武器 ----
	if src_type == "weapon" and tgt_type == "weapon":
		var src_unit : int = data.get("unit_idx", -1)
		var tgt_unit : int = target.get_meta("unit_idx", -1)
		if src_unit < 0 or tgt_unit < 0: return false
		if src_unit == tgt_unit: return false
		return true

	# ---- 武器 → 丢弃区 ----
	if src_type == "weapon" and target == panel.discard_zone:
		return false

	# ---- 防具 → forge_slot ----
	if src_type == "armor" and tgt_type == "forge_slot":
		var slot_idx : int = target.get_meta("forge_slot_index", -1)
		if slot_idx < 0: return false
		var uidx2 : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		if uidx2 < 0 or src_slot < 0: return false
		if uidx2 >= panel.party.size(): return false
		var u2 : UnitData = panel.party[uidx2]
		if u2.is_dead: return false
		if src_slot >= u2.armor_slots.size(): return false
		if u2.armor_slots[src_slot] == null: return false
		# 检查被替换的防具能否归还
		var existing : Variant = forge_slots[slot_idx]
		if existing != null:
			var existing_dict : Dictionary = existing
			var old_ou_idx : int = existing_dict.get("origin_unit", -1)
			if old_ou_idx < 0 or old_ou_idx >= panel.party.size(): return false
			var old_ou : UnitData = panel.party[old_ou_idx]
			var old_inst : ItemInstance = existing_dict["inst"]
			var need : int = panel._inst_slots(old_inst)
			var used : int = panel._used_slots_of(old_ou)
			if used + need > old_ou.max_armor_slots: return false
		return true

	# ---- 防具 ↔ 防具 ----
	if src_type == "armor" and tgt_type == "armor":
		return panel._check_armor_swap_budget(data, target)

	# ---- 防具 → 丢弃区 ----
	if src_type == "armor" and target == panel.discard_zone:
		return true

	# ---- forge_slot 作为拖拽源 ----
	if src_type == "forge_slot":
		# → 单位防具槽
		if tgt_type == "armor":
			var tu3 : int = target.get_meta("unit_idx", -1)
			var ts3 : int = target.get_meta("slot_idx", -1)
			if tu3 < 0 or ts3 < 0: return false
			if tu3 >= panel.party.size(): return false
			var unit3 : UnitData = panel.party[tu3]
			if unit3.is_dead: return false
			if ts3 >= unit3.armor_slots.size(): return false
			if unit3.armor_slots[ts3] != null: return false
			var idx : int = data.get("forge_slot_index", -1)
			if idx < 0 or idx >= forge_slots.size(): return false
			if forge_slots[idx] == null: return false
			var entry_dict : Dictionary = forge_slots[idx]
			var inst : ItemInstance = entry_dict["inst"]
			var need : int = panel._inst_slots(inst)
			var used : int = panel._used_slots_excluding(unit3, [ts3])
			return used + need <= unit3.max_armor_slots
		# → 另一个 forge_slot
		if tgt_type == "forge_slot":
			return true
		# → 丢弃区
		if target == panel.discard_zone:
			return true
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


func _force_return_armor_to_unit(unit: UnitData, inst: ItemInstance, prefer_slot: int) -> bool:
	if prefer_slot >= 0 and prefer_slot < unit.armor_slots.size() and unit.armor_slots[prefer_slot] == null:
		unit.armor_slots[prefer_slot] = inst
		return true
	for i in range(unit.armor_slots.size()):
		if unit.armor_slots[i] == null:
			unit.armor_slots[i] = inst
			return true
	return false

func _try_upgrade_weapon(unit_idx: int):
	if unit_idx < 0 or unit_idx >= panel.party.size(): return
	var u : UnitData = panel.party[unit_idx]
	if u.is_dead: return
	if u.weapon_slot == null: return
	if u.weapon_slot.upgrade_level >= WEAPON_UPGRADE_MAX: return

	var lv : int = u.weapon_slot.upgrade_level
	var cost : int = _get_weapon_upgrade_cost(lv)
	if panel._context.get_gold() < cost:
		panel._show_buy_failure_message("not_enough_gold"); return
	if not panel._context.subtract_gold(cost):
		panel._show_buy_failure_message("not_enough_gold"); return

	u.weapon_slot.upgrade_level += 1
	print("[铁匠铺] %s 升级 → +%d（花费 %dG）" % [panel._get_item_name(u.weapon_slot), u.weapon_slot.upgrade_level, cost])

	refresh_forge_upgrade_ui()
	panel._build_unit_columns()
	panel._sync_all()
	panel._update_gold_display()
	panel._schedule_build_ui()
