class_name EquipmentConfigDrag
extends RefCounted

const Style = preload("res://function/script/EquipmentConfig/EquipmentConfigStyle.gd")

var panel = null
var is_dragging : bool = false
var drag_source : Button = null
var drag_meta : Dictionary = {}
var drag_preview : Control = null
var drag_grab_offset : Vector2 = Vector2.ZERO
var target_states : Dictionary = {}


func _init(p):
	panel = p


# ============================================================
#  启动拖拽
# ============================================================
func start_drag(btn: Button):
	var slot_type : String = btn.get_meta("slot_type", "")
	if panel.current_mode == panel.Mode.DEPLOY and slot_type == "armor": return
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
	if slot_type == "pending_reward" and item_id == "": return

	drag_source = btn
	drag_meta = {
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
		"pending_idx": btn.get_meta("pending_idx", -1),
		"pending_src": btn.get_meta("pending_src", ""),
	}
	if slot_type == "shop_item" and panel.shop_manager:
		var shop_idx : int = drag_meta["shop_index"]
		if shop_idx != -1:
			var items : Array = panel.shop_manager.get_shop_items()
			if shop_idx >= 0 and shop_idx < items.size():
				var entry : Variant = items[shop_idx]
				if entry != null:
					var entry_dict : Dictionary = entry
					drag_meta["item_data"] = entry_dict["item_data"]
					drag_meta["item_price"] = entry_dict["price"]
	if slot_type == "weapon" and (panel.current_mode == panel.Mode.FORGE or (panel._is_shop_rest_mode() and panel.current_tab == "arena_forge")):
		panel._forge.update_upgrade_slot_for_drag(btn.get_meta("unit_idx", -1))
	var btn_rect : Rect2 = btn.get_global_rect()
	var btn_center : Vector2 = btn_rect.position + btn_rect.size / 2
	drag_grab_offset = panel.get_global_mouse_position() - btn_center
	_begin_dragging()


func _begin_dragging():
	if is_dragging: return
	is_dragging = true
	var btn : Button = drag_source
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
	drag_preview = Style.create_drag_preview(btn)
	var canvas : Node = panel.get_parent()
	if canvas and canvas is CanvasLayer: canvas.add_child(drag_preview)
	else: panel.add_child(drag_preview)
	update_drag_preview()
	_update_targets_visuals()


func update_drag_preview():
	if not drag_preview: return
	var mouse_pos : Vector2 = panel.get_global_mouse_position()
	var preview_center : Vector2 = mouse_pos - drag_grab_offset
	drag_preview.position = preview_center - drag_preview.size / 2
	drag_preview.z_index = 100


func end_drag():
	if not is_dragging: return
	if panel._has_active_confirm_ui():
		if drag_preview: drag_preview.queue_free(); drag_preview = null
		is_dragging = false
		_reset_targets_visuals(); _restore_drag_source()
		drag_source = null; drag_meta = {}
		return
	var mouse_pos : Vector2 = panel.get_global_mouse_position()
	var target : Control = _get_target_from_position(mouse_pos)
	var valid : bool = (target != null) and panel._is_valid_drop(drag_meta, target)
	var drop_data : Dictionary = drag_meta.duplicate()
	var source_type : String = drop_data.get("slot_type", "")
	if drag_preview: drag_preview.queue_free(); drag_preview = null
	is_dragging = false
	_reset_targets_visuals()
	_restore_drag_source()
	if valid:
		panel._execute_drop.call_deferred(drop_data, target)
		SoundManager.play_select_sound()
	else:
		if (panel.current_mode == panel.Mode.FORGE or (panel._is_shop_rest_mode() and panel.current_tab == "arena_forge")) \
				and source_type == "forge_slot" and target == null:
			panel._forge.execute_forge_slot_return.call_deferred(drop_data)
			SoundManager.play_select_sound()
		else:
			SoundManager.play_cancel_sound()
			if source_type == "shop_item":
				_hint_shop_purchase_failed(drop_data, target)
			panel._schedule_build_ui()
	if source_type == "weapon" and (panel.current_mode == panel.Mode.FORGE or (panel._is_shop_rest_mode() and panel.current_tab == "arena_forge")):
		panel._forge.refresh_forge_upgrade_ui()
	drag_source = null
	drag_meta = {}


func _hint_shop_purchase_failed(data: Dictionary, target: Control) -> void:
	var item_data : ItemData = data.get("item_data")
	if not item_data:
		panel._show_detail_in_zone("无法购买：商品已售罄"); return
	var item_name : String = item_data.name
	if target == null:
		panel._show_detail_in_zone("无法购买 %s\n请拖到左侧单位槽位" % item_name); return
	var ttype : String = target.get_meta("slot_type", "")
	if ttype == "" or target == panel.discard_zone:
		panel._show_detail_in_zone("无法购买 %s\n请拖到左侧单位槽位" % item_name); return
	if ttype == "armor":
		if item_data.type != "armor":
			panel._show_detail_in_zone("无法购买 %s\n该物品不是防具" % item_name); return
		var tu : int = target.get_meta("unit_idx", -1)
		var ts : int = target.get_meta("slot_idx", -1)
		if tu < 0 or ts < 0:
			panel._show_detail_in_zone("无法购买 %s\n目标槽无效" % item_name); return
		var unit : UnitData = panel.party[tu]
		var need : int = panel._inst_slots_for_id(item_data.id)
		var used : int = panel._used_slots_excluding(unit, [ts])
		var free : int = unit.max_armor_slots - used
		panel._show_detail_in_zone("无法购买 %s\n需要 %d 格，单位只剩 %d 格" % [item_name, need, free]); return
	if ttype == "weapon":
		if item_data.type != "weapon":
			panel._show_detail_in_zone("无法购买 %s\n该物品不是武器" % item_name); return
		panel._show_detail_in_zone("无法购买 %s" % item_name); return
	panel._show_detail_in_zone("无法购买 %s\n请拖到对应的单位槽位" % item_name)


func _restore_drag_source():
	if not is_instance_valid(drag_source): return
	drag_source.disabled = drag_source.get_meta("_original_disabled", false)
	var orig_mod : Variant = drag_source.get_meta("_original_modulate", Color.WHITE)
	drag_source.modulate = orig_mod
	var orig_text : Variant = drag_source.get_meta("_original_text", "")
	drag_source.text = orig_text
	var orig_size : Variant = drag_source.get_meta("_original_custom_minimum_size", Vector2.ZERO)
	drag_source.custom_minimum_size = orig_size
	drag_source.remove_meta("_original_disabled")
	drag_source.remove_meta("_original_modulate")
	drag_source.remove_meta("_original_text")
	drag_source.remove_meta("_original_custom_minimum_size")


# ============================================================
#  目标收集
# ============================================================
func _get_all_target_controls() -> Array[Control]:
	var targets : Array[Control] = []
	for col in panel.unit_container.get_children():
		for child in col.get_children():
			if child is Button: targets.append(child)
	if panel.relic_container:
		for btn in panel.relic_container.get_children():
			if btn is Button: targets.append(btn)
	# 待领取区作为丢弃目标
	if panel._pending_container and panel._pending_section and panel._pending_section.visible:
		for btn in panel._pending_container.get_children():
			if btn is Button: targets.append(btn)
	# DEPLOY / MAP
	if (panel.current_mode == panel.Mode.DEPLOY or panel.current_mode == panel.Mode.MAP) and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button and not btn.disabled: targets.append(btn)
	# SHOP 模式
	if panel.current_mode == panel.Mode.SHOP and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button and not btn.disabled: targets.append(btn)
	# Arena shop
	if panel._is_shop_rest_mode() and panel.current_tab == "arena_shop" and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button and not btn.disabled: targets.append(btn)
	# FORGE / arena_forge
	if (panel.current_mode == panel.Mode.FORGE or (panel._is_shop_rest_mode() and panel.current_tab == "arena_forge")) and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button and btn.get_meta("slot_type", "") == "forge_slot":
				targets.append(btn)
	# 武器升级按钮
	if (panel.current_mode == panel.Mode.FORGE or (panel._is_shop_rest_mode() and panel.current_tab == "arena_forge")) \
			and panel._forge.forge_upgrade_btn and is_instance_valid(panel._forge.forge_upgrade_btn):
		if not panel._forge.forge_upgrade_btn.disabled: targets.append(panel._forge.forge_upgrade_btn)
	# 丢弃区
	if panel.discard_zone.visible: targets.append(panel.discard_zone)
	return targets


func _update_targets_visuals():
	if drag_meta.is_empty(): _reset_targets_visuals(); return
	var targets : Array[Control] = _get_all_target_controls()
	target_states.clear()
	for target in targets:
		if target == drag_source: continue
		if not target_states.has(target):
			target_states[target] = target.modulate
		var is_valid : bool = panel._is_valid_drop(drag_meta, target)
		if is_valid: target.modulate = Color.WHITE
		else: target.modulate = Color(0.4, 0.4, 0.4, 1.0)


func _reset_targets_visuals():
	for target in target_states.keys():
		if is_instance_valid(target):
			var original : Variant = target_states[target]
			target.modulate = original
	target_states.clear()


# ============================================================
#  坐标查找
# ============================================================
func _find_control_at_position(pos: Vector2) -> Control:
	const BUFFER : int = 4
	# 单位列
	for col in panel.unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				var b2 : Button = child
				if panel.current_mode == panel.Mode.DEPLOY and b2.get_meta("slot_type", "") == "armor": continue
				if b2.get_global_rect().grow(BUFFER).has_point(pos): return b2
	# 被动槽
	if panel.relic_container:
		for btn in panel.relic_container.get_children():
			if btn is Button:
				var b : Button = btn
				if b.disabled: continue
				if b.get_global_rect().grow(BUFFER).has_point(pos): return b
	# ★ 待领取区（拖拽起点）
	if panel._pending_container and panel._pending_section and panel._pending_section.visible:
		for btn in panel._pending_container.get_children():
			if btn is Button:
				var bp : Button = btn
				if bp.disabled: continue
				if bp.get_global_rect().grow(BUFFER).has_point(pos): return bp
	# DEPLOY / MAP 商店
	if (panel.current_mode == panel.Mode.DEPLOY or panel.current_mode == panel.Mode.MAP) and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				var b4 : Button = btn
				if not b4.disabled and b4.get_global_rect().grow(BUFFER).has_point(pos): return b4
	# SHOP 模式
	if panel.current_mode == panel.Mode.SHOP and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				var b5 : Button = btn
				if not b5.disabled and b5.get_global_rect().grow(BUFFER).has_point(pos): return b5
	# Arena shop
	if panel._is_shop_rest_mode() and panel.current_tab == "arena_shop" and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				var b6 : Button = btn
				if not b6.disabled and b6.get_global_rect().grow(BUFFER).has_point(pos): return b6
	# FORGE / arena_forge：识别 forge_slot；arena_shop：识别 shop_item
	if (panel.current_mode == panel.Mode.FORGE or panel._is_shop_rest_mode()) \
			and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				var b7 : Button = btn
				var st : String = b7.get_meta("slot_type", "")
				if panel.current_tab == "arena_forge" and st == "forge_slot":
					if b7.get_global_rect().grow(BUFFER).has_point(pos): return b7
				elif panel.current_tab == "arena_shop" and st == "shop_item":
					if not b7.disabled and b7.get_global_rect().grow(BUFFER).has_point(pos): return b7
	return null


func _get_target_from_position(global_pos: Vector2) -> Control:
	const BUFFER : int = 4
	# 丢弃区优先
	if panel.discard_zone.visible and panel.discard_zone.get_global_rect().has_point(global_pos): return panel.discard_zone
	# 单位列
	for col in panel.unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				var b : Button = child
				if b.disabled: continue
				if b.get_global_rect().grow(BUFFER).has_point(global_pos): return b
	# 被动槽
	if panel.relic_container:
		for btn in panel.relic_container.get_children():
			if btn is Button:
				var b2 : Button = btn
				if b2.disabled: continue
				if b2.get_global_rect().grow(BUFFER).has_point(global_pos): return b2
	# 待领取区（仅作为丢弃目标，不接收 pending 内部拖拽）
	if panel._pending_container and panel._pending_section and panel._pending_section.visible:
		for btn in panel._pending_container.get_children():
			if btn is Button:
				var bp : Button = btn
				if bp.get_global_rect().grow(BUFFER).has_point(global_pos): return bp
	# DEPLOY / MAP 商店
	if (panel.current_mode == panel.Mode.DEPLOY or panel.current_mode == panel.Mode.MAP) and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				var b4 : Button = btn
				if not b4.disabled and b4.get_global_rect().grow(BUFFER).has_point(global_pos): return b4
	# SHOP 模式
	if panel.current_mode == panel.Mode.SHOP and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				var b5 : Button = btn
				if not b5.disabled and b5.get_global_rect().grow(BUFFER).has_point(global_pos): return b5
	# Arena shop
	if panel._is_shop_rest_mode() and panel.current_tab == "arena_shop" and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				var b6 : Button = btn
				if not b6.disabled and b6.get_global_rect().grow(BUFFER).has_point(global_pos): return b6
	# FORGE 模式
	if panel.current_mode == panel.Mode.FORGE and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				var b7 : Button = btn
				var st : String = b7.get_meta("slot_type", "")
				if panel.current_tab == "arena_shop" and st == "shop_item":
					if not b7.disabled and b7.get_global_rect().grow(BUFFER).has_point(global_pos): return b7
				elif st == "forge_slot":
					if b7.get_global_rect().grow(BUFFER).has_point(global_pos): return b7
	# 武器升级按钮
	if (panel.current_mode == panel.Mode.FORGE or (panel._is_shop_rest_mode() and panel.current_tab == "arena_forge")) \
			and panel._forge.forge_upgrade_btn and is_instance_valid(panel._forge.forge_upgrade_btn) and not panel._forge.forge_upgrade_btn.disabled:
		if panel._forge.forge_upgrade_btn.get_global_rect().grow(BUFFER).has_point(global_pos): return panel._forge.forge_upgrade_btn
	return null
