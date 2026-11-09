class_name EquipmentConfigDrag
extends RefCounted

const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")

var panel = null
var is_dragging : bool = false
var drag_source : Control = null # 改为 Control 以支持单位图标
var drag_meta : Dictionary = {}
var drag_preview : Control = null
var drag_grab_offset : Vector2 = Vector2.ZERO
var target_states : Dictionary = {}


func _init(p):
	panel = p


# ============================================================
#  启动拖拽
# ============================================================
func start_drag(btn: Control):
	if btn is Button and btn.disabled: return
	var slot_type : String = btn.get_meta("slot_type", "")
	
	# ★ 拦截武器相关拖拽
	if slot_type == "weapon" or slot_type == "library_weapon":
		return
		
	if panel.current_mode == panel.Mode.DEPLOY and slot_type == "armor": return
	
	var item_id : String = btn.get_meta("item_id", "")
	var talent_id : String = btn.get_meta("talent_id", "")
	var refine_id : String = btn.get_meta("refine_id", "")
	
	# ★ 单位图标拖拽
	if slot_type == "unit_icon":
		drag_source = btn
		drag_meta = {
			"slot_type": slot_type,
			"unit_idx": btn.get_meta("unit_idx", -1),
			"source_control": btn,
			"col_node": btn.get_parent() # 记录整列，以便生成整列预览
		}
		# 抓取偏移基于整列的左上角，这样拖拽时鼠标能对上整列
		var col : Control = drag_meta["col_node"]
		drag_grab_offset = panel.get_global_mouse_position() - col.global_position
		_begin_dragging()
		return

	# ★ 光环拖拽
	if slot_type in ["aura_shop", "aura_equipped"]:
		drag_source = btn
		drag_meta = {
			"slot_type": slot_type,
			"aura_id": btn.get_meta("aura_id", ""),
			"aura_price": btn.get_meta("aura_price", 0),
			"source_control": btn,
		}
		var btn_rect2 : Rect2 = btn.get_global_rect()
		drag_grab_offset = panel.get_global_mouse_position() - btn_rect2.position
		_begin_dragging()
		return
		
	if slot_type == "passive_slot" and item_id == "" and refine_id == "": return
	if slot_type in ["library_talent", "talent"] and talent_id == "": return
	if slot_type == "shop_item" and item_id == "": return
	if slot_type == "forge_slot" and item_id == "": return
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
		"pending_idx": btn.get_meta("pending_idx", -1),
		"pending_src": btn.get_meta("pending_src", ""),
	}
	
	# ★ 修复：如果拖拽的是商店物品，记录它的方向，防止购买时节点被释放导致读不到
	if slot_type == "shop_item":
		drag_meta["shop_direction"] = btn.get_meta("shop_direction", 0)
		
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
					
	var btn_rect3 : Rect2 = btn.get_global_rect()
	drag_grab_offset = panel.get_global_mouse_position() - btn_rect3.position
	_begin_dragging()


func _begin_dragging():
	if is_dragging: return
	is_dragging = true
	var btn : Control = drag_source
	if not btn: return
	
	var slot_type : String = drag_meta.get("slot_type", "")
	
	if slot_type == "unit_icon":
		var col : Control = drag_meta.get("col_node")
		var u_idx : int = drag_meta.get("unit_idx", -1)
		if col and u_idx >= 0 and u_idx < panel.party.size():
			# ★ 直接复用原版的列生成，生成完美预览
			drag_preview = panel._create_unit_column(u_idx, true)
			drag_preview.custom_minimum_size = col.size
			drag_preview.size = col.size
			
			var canvas : Node = panel.get_parent()
			if canvas and canvas is CanvasLayer: canvas.add_child(drag_preview)
			else: panel.add_child(drag_preview)
			
			# ★ 修复占位塌陷：改变透明度而不是隐藏，保住原有布局空间
			btn.set_meta("_original_modulate", col.modulate)
			col.modulate = Color(1, 1, 1, 0.15)
	else:
		# 原有普通拖拽逻辑
		var btn_as_button := btn as Button
		if btn_as_button:
			drag_preview = Style.create_drag_preview(btn_as_button)
			var canvas : Node = panel.get_parent()
			if canvas and canvas is CanvasLayer: canvas.add_child(drag_preview)
			else: panel.add_child(drag_preview)
			btn.set_meta("_original_modulate", btn.modulate)
			btn.modulate = Color(0.3, 0.3, 0.3, 1.0) 
	
	update_drag_preview()
	_update_targets_visuals()


func _restore_drag_source():
	if not is_instance_valid(drag_source): return
	
	if slot_type_is_unit_icon():
		var col : Control = drag_meta.get("col_node")
		if is_instance_valid(col):
			col.modulate = Color(1, 1, 1, 1)
	else:
		if drag_source.has_meta("_original_modulate"):
			drag_source.modulate = drag_source.get_meta("_original_modulate")
			drag_source.remove_meta("_original_modulate")


func slot_type_is_unit_icon() -> bool:
	return drag_meta.get("slot_type", "") == "unit_icon"


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
	
	# 清理拖拽视觉
	if drag_preview: drag_preview.queue_free(); drag_preview = null
	is_dragging = false
	_reset_targets_visuals()
	_restore_drag_source()
	
	if valid:
		panel._execute_drop.call_deferred(drop_data, target)
		SoundManager.play_select_sound()
	else:
		if source_type == "talent" and target == null:
			panel._talent.execute_talent_remove.call_deferred(drop_data)
			SoundManager.play_select_sound()
		elif (panel.current_mode == panel.Mode.FORGE or (panel._is_shop_rest_mode() and panel.current_tab == "arena_forge")) \
				and source_type == "forge_slot" and target == null:
			panel._forge.execute_forge_slot_return.call_deferred(drop_data)
			SoundManager.play_select_sound()
		else:
			SoundManager.play_cancel_sound()
			if source_type == "shop_item":
				_hint_shop_purchase_failed(drop_data, target)
			
	if source_type == "weapon" and (panel.current_mode == panel.Mode.FORGE or (panel._is_shop_rest_mode() and panel.current_tab == "arena_forge")):
		panel._forge.refresh_forge_upgrade_ui()
		
	drag_source = null
	drag_meta = {}


func update_drag_preview():
	if not drag_preview: return
	drag_preview.global_position = panel.get_global_mouse_position() - drag_grab_offset
	drag_preview.z_index = 100


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
		panel._show_detail_in_zone("无法购买 %s\n该物品不是防具，且不支持武器" % item_name); return
	panel._show_detail_in_zone("无法购买 %s\n请拖到对应的单位槽位" % item_name)


# ============================================================
#  目标收集（按优先级从"具体"到"一般"）
# ============================================================
func _collect_targets() -> Array:
	var targets : Array = []

	# ---- 1. 丢弃区（最具体区域）----
	if panel.discard_zone and panel.discard_zone.visible:
		targets.append(panel.discard_zone)

	# ---- 2. 单位列（递归收集，防嵌套遗漏）----
	if panel.unit_container:
		_collect_controls_recursive(panel.unit_container, targets)

	# ---- 3. 被动槽 ----
	if panel.relic_container:
		for btn in panel.relic_container.get_children():
			if btn is Button:
				targets.append(btn)

	# ---- 4. 待领取区 ----
	if panel._pending_container and panel._pending_section and panel._pending_section.visible:
		for btn in panel._pending_container.get_children():
			if btn is Button:
				targets.append(btn)

	# ---- 5. 商店容器（一般目标）----
	if panel.shop_container and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button:
				targets.append(btn)

	return targets

# ★ 新增：递归收集子节点
func _collect_controls_recursive(node: Node, out: Array):
	if node is Control and (node is Button or node.get_meta("slot_type", "") == "unit_icon"):
		out.append(node)
	for child in node.get_children():
		_collect_controls_recursive(child, out)


# ============================================================
#  目标收集
# ============================================================
func _get_all_target_controls() -> Array[Control]:
	var targets : Array[Control] = []
	
	if panel.unit_container:
		_collect_controls_recursive(panel.unit_container, targets)
		
	if panel.relic_container:
		for btn in panel.relic_container.get_children():
			if btn is Button: targets.append(btn)
			
	if panel._pending_container and panel._pending_section and panel._pending_section.visible:
		for btn in panel._pending_container.get_children():
			if btn is Button: targets.append(btn)
			
	if (panel.current_mode == panel.Mode.DEPLOY or panel.current_mode == panel.Mode.MAP) and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button and not btn.disabled: targets.append(btn)
			
	if panel._is_shop_rest_mode() and panel.current_tab == "arena_shop" and panel.shop_container.visible:
		for btn in panel.shop_container.get_children():
			if btn is Button and not btn.disabled: targets.append(btn)
			
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
	for t in _collect_targets():
		if t == null or not is_instance_valid(t):
			continue
		if t is Button:
			var b : Button = t
			if b.disabled:
				continue
		if t.get_global_rect().grow(BUFFER).has_point(pos):
			return t
	return null


func _get_target_from_position(global_pos: Vector2) -> Control:
	const BUFFER : int = 4
	for t in _collect_targets():
		if t == null or not is_instance_valid(t):
			continue
		if t is Button:
			var b : Button = t
			var st : String = b.get_meta("slot_type", "")
			var allow_disabled : bool = (st == "forge_slot")
			if b.disabled and not allow_disabled:
				continue
		if t.get_global_rect().grow(BUFFER).has_point(global_pos):
			return t
	return null
