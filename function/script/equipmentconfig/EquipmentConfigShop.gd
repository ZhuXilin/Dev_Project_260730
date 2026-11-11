class_name EquipmentConfigShop
extends RefCounted

const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")

var panel = null


func _init(p):
	panel = p


# ============================================================
#  商店列表
# ============================================================
func build_shop_items():
	if not panel.shop_manager: return

	var forge_nodes : Array = [
		"ForgeCraftRow", "ForgeUpgradeLabel", "ForgeUpgradeBtn",
		"ForgeUpgradeSpacer1", "ForgeUpgradeSpacer2",
		"ForgeResultLabel", "ForgeBottomSpacer"
	]
	for n_name in forge_nodes:
		var old : Node = panel.right_container.get_node_or_null(n_name)
		if old:
			panel.right_container.remove_child(old)
			old.queue_free()

	# ★ 核心修复：强制关死 ShopScroll 的滚动功能，只留裁切
	if panel.shop_scroll:
		panel.shop_scroll.custom_minimum_size = Vector2.ZERO
		panel.shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.shop_scroll.scroll_vertical = 0
		panel.shop_scroll.scroll_horizontal = 0
		panel.shop_scroll.clip_contents = true

	if panel.shop_container:
		for child in panel.shop_container.get_children():
			panel.shop_container.remove_child(child)
			child.free()

	panel.shop_container.add_theme_constant_override("h_separation", 0)
	panel.shop_container.add_theme_constant_override("v_separation", 0)
	panel.shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.shop_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.shop_container.visible = true

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 6)
	panel.shop_container.add_child(main_vbox)

	var armor_grid = GridContainer.new()
	armor_grid.columns = 3
	armor_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armor_grid.add_theme_constant_override("h_separation", 6)
	armor_grid.add_theme_constant_override("v_separation", 6)
	main_vbox.add_child(armor_grid)

	var items : Array = panel.shop_manager.get_shop_items()
	for i in range(items.size()):
		var entry : Variant = items[i]
		var btn : Button = null
		
		if entry != null:
			var entry_dict : Dictionary = entry
			var item_data : ItemData = entry_dict["item_data"]
			var price : int = entry_dict["price"]
			
			var shop_dir : int = 0
			if item_data.type == "armor" and item_data.enable_direction:
				if panel._shop_direction_cache.has(i):
					shop_dir = panel._shop_direction_cache[i]
				else:
					shop_dir = Direction.roll_drop_direction()
					panel._shop_direction_cache[i] = shop_dir
			
			var temp_inst = ItemInstance.new()
			temp_inst.item_id = item_data.id
			temp_inst.direction = shop_dir
			
			btn = panel._create_item_button(temp_inst, "shop_item", -1, -1, shop_dir, true)
			btn.custom_minimum_size = Style.BTN_SHOP_SIZE
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			
			btn.set_meta("slot_type", "shop_item")
			btn.set_meta("shop_index", i)
			btn.set_meta("item_price", price)
			btn.set_meta("item_id", item_data.id)
			btn.set_meta("shop_direction", shop_dir)
			
			var price_label = Label.new()
			price_label.text = str(price)
			price_label.add_theme_font_size_override("font_size", 6) 
			price_label.add_theme_color_override("font_color", Color.WHITE)
			price_label.add_theme_color_override("font_outline_color", Color.BLACK)
			price_label.add_theme_constant_override("outline_size", 3)
			price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			price_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			price_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			price_label.offset_bottom = 1
			price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(price_label)
			
		else:
			btn = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_SHOP_SIZE)
			btn.expand_icon = true
			btn.clip_text = true
			btn.text = "空位"
			btn.disabled = true
			btn.set_meta("slot_type", "")
			btn.set_meta("shop_index", i)
			
		armor_grid.add_child(btn)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	main_vbox.add_child(spacer)

	if panel._context.get_context_id() != "arena":
		var candidates : Array = GameState.current_aura_candidates.duplicate()
		if not candidates.is_empty():
			var aura_grid = GridContainer.new()
			aura_grid.columns = 3
			aura_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			aura_grid.add_theme_constant_override("h_separation", 6)
			aura_grid.add_theme_constant_override("v_separation", 6)
			main_vbox.add_child(aura_grid)

			for aid in candidates:
				var aura_btn : Button = panel._make_aura_icon_btn(aid, SoulFireManager.current, false, panel._get_first_empty_passive_slot())
				aura_grid.add_child(aura_btn)

	if panel.shop_container:
		panel.shop_container.queue_sort()
		panel.shop_container.call_deferred("queue_sort")


func build_weapon_grid(container: Container):
	for child in container.get_children(): container.remove_child(child); child.free()
	for item_id in Globals.unlocked_items:
		var data : ItemData = ItemManager.get_item_data(item_id)
		if data and data.type == "weapon":
			var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_LIBRARY_SIZE)
			btn.expand_icon = true
			if data.icon:
				btn.icon = data.icon
				btn.text = ""
				btn.tooltip_text = data.name
			else:
				btn.text = data.name
			btn.set_meta("slot_type", "library_weapon")
			btn.set_meta("item_id", item_id)
			btn.mouse_entered.connect(panel._on_button_hover_entered.bind(item_id))
			btn.mouse_exited.connect(panel._on_button_hover_exited)
			container.add_child(btn)


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
		return
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

	var inst : ItemInstance = buy_result["item_instance"]

	if data.has("shop_direction") and inst != null:
		inst.direction = int(data["shop_direction"])

	if item_data.type == "armor":
		var tu2 : UnitData = panel.party[target_unit_idx]
		
		# ★ 新增：处理被覆盖的旧装备
		var old_inst : ItemInstance = tu2.armor_slots[target_slot_idx]
		if old_inst:
			var old_data = ItemManager.get_item_data(old_inst.item_id)
			if old_data and not old_data.no_sell:
				var sell_price = old_inst.get_sell_price()
				panel._context.add_gold(sell_price)
				panel._show_detail_in_zone("替换下旧防具，自动折算 %d 金币" % sell_price)
				
		tu2.armor_slots[target_slot_idx] = inst

	panel._build_unit_columns()
	panel._sync_all()
	panel._update_gold_display()
	panel._schedule_build_ui()


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


func on_reset_shop_pressed():
	if panel.current_tab == "arena_forge":
		if panel.current_mode == panel.Mode.FORGE or panel._is_shop_rest_mode():
			panel._forge.on_forge_clear_pressed()
			return

	if not (panel._is_shop_rest_mode() and panel.current_tab == "arena_shop") \
			and not (panel.current_mode == panel.Mode.FORGE and panel.current_tab == "arena_shop"):
		return
	if not panel.shop_manager: return
	var cost : int = panel.shop_manager.get_reset_cost()
	if panel._context.get_gold() < cost:
		Globals.show_confirm(panel, "金币不足！", "确定", "", func(): pass, func(): pass, false); return
	var spent : int = panel.shop_manager.reset_shop()
	if spent >= 0:
		SoundManager.play_select_sound()
		panel._update_gold_display()
		panel.reset_btn.text = "刷新商店 (" + str(panel.shop_manager.get_reset_cost()) + "G)"
