class_name EquipmentConfigShop
extends RefCounted

const Style = preload("res://function/script/EquipmentConfig/EquipmentConfigStyle.gd")

var panel = null


func _init(p):
	panel = p


# ============================================================
#  商店列表
# ============================================================
func build_shop_items():
	if not panel.shop_manager: return

	# ---- 清理铁匠铺残留（含 @xxx@2） ----
	for child in panel.right_container.get_children():
		if "Forge" in child.name:
			panel.right_container.remove_child(child)
			child.queue_free()
	panel._forge.inline_craft_btn = null

	# ---- 强制重置 ShopScroll 布局状态 ----
	if panel.shop_scroll:
		panel.shop_scroll.custom_minimum_size = Vector2.ZERO
		panel.shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.shop_scroll.scroll_vertical = 0
		panel.shop_scroll.scroll_horizontal = 0
		# 强制 Control 系统重排
		panel.shop_scroll.visible = false
		panel.shop_scroll.visible = true

	# ---- 清空容器（用 queue_free 避免立即释放冲突） ----
	panel._clear_container(panel.shop_container)

	# ---- 重置容器属性 ----
	panel.shop_container.columns = 3
	panel.shop_container.add_theme_constant_override("h_separation", 2)
	panel.shop_container.add_theme_constant_override("v_separation", 2)
	panel.shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.shop_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.shop_container.visible = true

	# ---- 生成按钮 ----
	var items : Array = panel.shop_manager.get_shop_items()
	for i in range(items.size()):
		var entry : Variant = items[i]
		var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_SHOP_SIZE)
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
			btn.mouse_entered.connect(panel._on_button_hover_entered.bind(item_data.id))
			btn.mouse_exited.connect(panel._on_button_hover_exited)
		else:
			btn.text = "空位"
			btn.disabled = true
		panel.shop_container.add_child(btn)

	# ---- 立即重排 ----
	if panel.shop_container:
		panel.shop_container.queue_sort()
	if panel.shop_scroll:
		panel.shop_scroll.queue_sort()
		# 下一帧再排一次（应对布局延迟）
		panel.shop_scroll.call_deferred("queue_sort")
	if panel.shop_container:
		panel.shop_container.call_deferred("queue_sort")
		

# ============================================================
#  武器库 / 精炼库网格
# ============================================================
func build_weapon_grid(container: GridContainer):
	for child in container.get_children(): container.remove_child(child); child.free()
	container.columns = 3
	for item_id in Globals.unlocked_items:
		var data : ItemData = ItemManager.get_item_data(item_id)
		if data and data.type == "weapon":
			var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_LIBRARY_SIZE)
			btn.text = data.name
			btn.set_meta("slot_type", "library_weapon")
			btn.set_meta("item_id", item_id)
			btn.mouse_entered.connect(panel._on_button_hover_entered.bind(item_id))
			btn.mouse_exited.connect(panel._on_button_hover_exited)
			container.add_child(btn)


func build_refine_grid(container: GridContainer):
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
		var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_LIBRARY_SIZE)
		var rname : String = recipe.get("name", refine_id)
		btn.text = rname + " ×" + str(count)
		btn.autowrap_mode = TextServer.AUTOWRAP_OFF
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.set_meta("slot_type", "library_refine")
		btn.set_meta("refine_id", refine_id)
		btn.mouse_entered.connect(panel._on_refine_hover_entered.bind(refine_id))
		btn.mouse_exited.connect(panel._on_refine_hover_exited)
		container.add_child(btn)
	if not has_any:
		container.add_child(Style.create_label("暂无精炼道具", Style.FONT_SMALL))


# ============================================================
#  商店购买
# ============================================================
func buy_shop_item(data: Dictionary, target: Control):
	if target == null: return
	if not panel.shop_manager: return
	var shop_index : int = data.get("shop_index", -1)
	if shop_index == -1: return
	var items : Array = panel.shop_manager.get_shop_items()
	if shop_index < 0 or shop_index >= items.size(): return
	var entry : Variant = items[shop_index]
	if entry == null: return
	var entry_dict : Dictionary = entry
	var item_data : ItemData = entry_dict["item_data"]
	if not item_data: return

	var drag_item_id : String = data.get("item_id", "")
	if drag_item_id != "" and drag_item_id != item_data.id:
		SoundManager.play_cancel_sound(); return

	var target_type : String = target.get_meta("slot_type", "")
	var target_unit_idx : int = target.get_meta("unit_idx", -1)
	var target_slot_idx : int = target.get_meta("slot_idx", -1)

	if item_data.type == "weapon":
		if target_type != "weapon": return
		if target_unit_idx < 0: return
	elif item_data.type == "armor":
		if target_type != "armor": return
		if target_unit_idx < 0 or target_slot_idx < 0: return
		if not panel._can_equip_armor_to(target_unit_idx, item_data.id, target_slot_idx):
			Globals.show_confirm(panel, "防具格数不足！", "确定", "", func(): pass, func(): pass, false)
			return

	var buy_result : Dictionary = panel.shop_manager.buy_shop_item(shop_index)
	if not buy_result["success"]:
		panel._show_buy_failure_message(buy_result.get("reason", "unknown"))
		return

	var inst := ItemInstance.new()
	inst.item_id = item_data.id
	inst.count = 1
	if item_data.type == "weapon":
		var tu : UnitData = panel.party[target_unit_idx]
		tu.weapon_slot = inst
	elif item_data.type == "armor":
		var tu2 : UnitData = panel.party[target_unit_idx]
		tu2.armor_slots[target_slot_idx] = inst

	panel._build_unit_columns()
	panel._sync_all()
	panel._update_gold_display()
	panel._schedule_build_ui()


# ============================================================
#  武器库 → 武器槽
# ============================================================
func library_to_weapon(data: Dictionary, target: Control):
	var item_id : String = data["item_id"]
	var unit_idx : int = target.get_meta("unit_idx", -1)
	if unit_idx == -1: return
	var inst := ItemInstance.new()
	inst.item_id = item_id
	inst.count = 1
	var u : UnitData = panel.party[unit_idx]
	u.weapon_slot = inst
	panel._build_unit_columns()
	panel._sync_all(); panel._schedule_build_ui()


# ============================================================
#  交换
# ============================================================
func swap_weapons(data: Dictionary, target: Control):
	var src_unit : int = data["unit_idx"]
	var tgt_unit : int = target.get_meta("unit_idx", -1)
	if tgt_unit == -1: return
	var su : UnitData = panel.party[src_unit]
	var tu : UnitData = panel.party[tgt_unit]
	var temp : ItemInstance = su.weapon_slot
	su.weapon_slot = tu.weapon_slot
	tu.weapon_slot = temp
	panel._build_unit_columns()
	panel._sync_all(); panel._schedule_build_ui()


func swap_armor(data: Dictionary, target: Control):
	var src_unit : int = data["unit_idx"]
	var src_slot : int = data["slot_idx"]
	var tgt_unit : int = target.get_meta("unit_idx", -1)
	var tgt_slot : int = target.get_meta("slot_idx", -1)
	if tgt_unit == -1 or tgt_slot == -1: return
	var su : UnitData = panel.party[src_unit]
	var tu : UnitData = panel.party[tgt_unit]
	var temp : ItemInstance = su.armor_slots[src_slot]
	su.armor_slots[src_slot] = tu.armor_slots[tgt_slot]
	tu.armor_slots[tgt_slot] = temp
	panel._build_unit_columns()
	panel._sync_all(); panel._schedule_build_ui()


# ============================================================
#  商店刷新
# ============================================================
func on_reset_shop_pressed():
	if panel.current_mode == panel.Mode.FORGE:
		panel._forge.on_forge_clear_pressed(); return
	if panel._is_shop_rest_mode():
		if panel.current_tab == "arena_forge":
			panel._forge.on_forge_clear_pressed(); return
	if panel.current_mode != panel.Mode.SHOP and not (panel._is_shop_rest_mode() and panel.current_tab == "arena_shop"): return
	if not panel.shop_manager: return
	var cost : int = panel.shop_manager.get_reset_cost()
	if panel._context.get_gold() < cost:
		Globals.show_confirm(panel, "金币不足！", "确定", "", func(): pass, func(): pass, false); return
	var spent : int = panel.shop_manager.reset_shop()
	if spent >= 0:
		SoundManager.play_select_sound()
		panel._update_gold_display()
		panel.reset_btn.text = "刷新商店 (" + str(panel.shop_manager.get_reset_cost()) + "G)"
