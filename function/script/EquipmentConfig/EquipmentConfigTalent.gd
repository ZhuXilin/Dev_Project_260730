class_name EquipmentConfigTalent
extends RefCounted

const Style = preload("res://function/script/EquipmentConfig/EquipmentConfigStyle.gd")

var panel = null


func _init(p):
	panel = p


# ============================================================
#  特技库网格
# ============================================================
func build_talent_grid(container: GridContainer):
	for child in container.get_children():
		container.remove_child(child)
		child.free()

	var display_unit_type : String = _get_talent_display_unit_type()

	var unlocked : Array = Globals.get_unlocked_talents()
	if unlocked.is_empty():
		container.add_child(Style.create_label("暂无解锁特技", Style.FONT_SMALL))
		return
	for talent_id in unlocked:
		var data : TalentData = TalentManager.get_talent_data(talent_id)
		if not data:
			continue
		var is_equipped : bool = is_talent_equipped_anywhere(talent_id)
		var btn : Button = Style.create_styled_button(Style.FONT_TINY, Style.BTN_TALENT_SIZE)

		if display_unit_type != "":
			var lv : int = TalentManager.get_talent_level(display_unit_type, talent_id)
			if TalentManager.is_talent_max_level(display_unit_type, talent_id):
				btn.text = "%s Lv%d MAX" % [data.display_name, lv]
			else:
				var cur_exp : int = TalentManager.get_talent_exp_in_level(display_unit_type, talent_id)
				var need_exp : int = TalentManager.get_level_required_exp(display_unit_type, talent_id)
				btn.text = "%s Lv%d %d/%d" % [data.display_name, lv, cur_exp, need_exp]
		else:
			btn.text = data.display_name

		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.set_meta("talent_id", talent_id)
		btn.set_meta("slot_type", "library_talent")
		var rarity_color : Color = Style.get_rarity_color(data.rarity)
		if is_equipped:
			btn.modulate = Color(0.65, 0.65, 0.65, 1.0)
			btn.disabled = true
			btn.add_theme_color_override("font_color", rarity_color)
		else:
			btn.modulate = Color.WHITE
			btn.add_theme_color_override("font_color", rarity_color)
			btn.disabled = false
		btn.mouse_entered.connect(panel._on_talent_hover_entered.bind(talent_id))
		btn.mouse_exited.connect(panel._on_talent_hover_exited)
		container.add_child(btn)


func _get_talent_display_unit_type() -> String:
	var units : Array = _use_context_units()
	if units.size() == 1:
		return units[0].unit_name
	return ""


func _use_context_units() -> Array:
	if panel._context:
		return panel._context.get_units()
	return []


# ============================================================
#  特技装 / 卸
# ============================================================
func execute_talent_drop(data: Dictionary, target: Control):
	var source_type : String = data.get("slot_type", "")
	var target_type : String = target.get_meta("slot_type", "")
	if source_type == "library_talent" and target_type == "talent":
		var talent_id : String = data.get("talent_id", "")
		if talent_id == "": return
		var unit_idx : int = target.get_meta("unit_idx", -1)
		var slot_idx : int = target.get_meta("slot_idx", -1)
		if unit_idx == -1 or slot_idx == -1: return
		if not Globals.is_talent_unlocked(talent_id): return
		if is_talent_already_equipped(talent_id, unit_idx, slot_idx):
			var equipped_unit : String = get_unit_with_talent(talent_id)
			Globals.show_confirm(panel, "特技已被 %s 装备" % equipped_unit, "确定", "", func(): pass, func(): pass, false); return
		if panel._context.get_context_id() == "arena" and panel.current_mode != panel.Mode.DEPLOY:
			var cost : int = panel._context.get_talent_swap_cost()
			if not panel._context.can_swap_talent():
				Globals.show_confirm(panel, "金币不足（需要 %d）" % cost, "确定", "", func(): pass, func(): pass, false); return
			if not panel._context.consume_talent_swap(): return
			panel._context.lock_talent(talent_id); panel._update_gold_display()
		elif panel._context.get_context_id() == "arena":
			panel._context.lock_talent(talent_id)
		var inst := TalentInstance.new()
		inst.talent_id = talent_id
		inst.is_active = true
		var u : UnitData = panel.party[unit_idx]
		u.talent_slots[slot_idx] = inst
		panel._sync_all(); panel._schedule_build_ui(); return

	if source_type == "talent" and target_type == "talent":
		var src_unit : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		var tgt_unit : int = target.get_meta("unit_idx", -1)
		var tgt_slot : int = target.get_meta("slot_idx", -1)
		if src_unit == -1 or tgt_unit == -1: return
		var su : UnitData = panel.party[src_unit]
		var tu : UnitData = panel.party[tgt_unit]
		var src_inst : TalentInstance = su.talent_slots[src_slot]
		var tgt_inst : TalentInstance = tu.talent_slots[tgt_slot]
		var src_tid : String = src_inst.talent_id if src_inst and src_inst.is_active else ""
		var tgt_tid : String = tgt_inst.talent_id if tgt_inst and tgt_inst.is_active else ""
		if src_tid == "" and tgt_tid == "": return
		if tgt_tid == "":
			if is_talent_already_equipped(src_tid, tgt_unit, tgt_slot): return
			tu.talent_slots[tgt_slot] = src_inst
			su.talent_slots[src_slot] = null
		elif src_tid == "":
			if is_talent_already_equipped(tgt_tid, src_unit, src_slot): return
			su.talent_slots[src_slot] = tgt_inst
			tu.talent_slots[tgt_slot] = null
		else:
			if is_talent_already_equipped(tgt_tid, src_unit, src_slot): return
			if is_talent_already_equipped(src_tid, tgt_unit, tgt_slot): return
			var temp : TalentInstance = su.talent_slots[src_slot]
			su.talent_slots[src_slot] = tu.talent_slots[tgt_slot]
			tu.talent_slots[tgt_slot] = temp
		panel._sync_all(); panel._schedule_build_ui(); return


func execute_talent_remove(data: Dictionary):
	var unit_idx : int = data.get("unit_idx", -1)
	var slot_idx : int = data.get("slot_idx", -1)
	if unit_idx == -1 or slot_idx == -1: return
	var u : UnitData = panel.party[unit_idx]
	u.talent_slots[slot_idx] = null
	panel._sync_all(); panel._schedule_build_ui()


func discard_talent(data: Dictionary):
	var source_type : String = data.get("slot_type", "")
	if source_type == "library_talent": return
	if source_type == "talent":
		var unit_idx : int = data.get("unit_idx", -1)
		var slot_idx : int = data.get("slot_idx", -1)
		if unit_idx == -1 or slot_idx == -1: return
		var u : UnitData = panel.party[unit_idx]
		u.talent_slots[slot_idx] = null
		panel._sync_all(); panel._schedule_build_ui()


# ============================================================
#  兼容性
# ============================================================
func check_talent_compatibility(data: Dictionary, target: Control) -> bool:
	var source_type : String = data.get("slot_type", "")
	var talent_id : String = data.get("talent_id", "")
	if talent_id == "": return false
	var target_unit_idx : int = target.get_meta("unit_idx", -1)
	var target_slot_idx : int = target.get_meta("slot_idx", -1)
	if target_unit_idx == -1: return false
	var target_unit : UnitData = panel.party[target_unit_idx]
	if not TalentManager.is_talent_compatible_with_unit(talent_id, target_unit.unit_name): return false
	if source_type == "library_talent":
		if is_talent_already_equipped(talent_id, -1, -1): return false
	elif source_type == "talent":
		var src_unit_idx : int = data.get("unit_idx", -1)
		var src_slot_idx : int = data.get("slot_idx", -1)
		var tgt_inst : TalentInstance = target_unit.talent_slots[target_slot_idx]
		var tgt_tid : String = tgt_inst.talent_id if tgt_inst and tgt_inst.is_active else ""
		if tgt_tid == "":
			if is_talent_already_equipped(talent_id, target_unit_idx, target_slot_idx): return false
		else:
			if is_talent_already_equipped(tgt_tid, src_unit_idx, src_slot_idx): return false
			if is_talent_already_equipped(talent_id, target_unit_idx, target_slot_idx): return false
	return true


func is_talent_already_equipped(talent_id: String, exclude_unit_idx: int = -1, exclude_slot_idx: int = -1) -> bool:
	for i in range(panel.party.size()):
		if i == exclude_unit_idx: continue
		var u : UnitData = panel.party[i]
		for slot_idx in range(u.talent_slots.size()):
			if slot_idx == exclude_slot_idx and i == exclude_unit_idx: continue
			var inst : TalentInstance = u.talent_slots[slot_idx]
			if inst and inst.is_active and inst.talent_id == talent_id: return true
	return false


func get_unit_with_talent(talent_id: String) -> String:
	for i in range(panel.party.size()):
		var u : UnitData = panel.party[i]
		for inst in u.talent_slots:
			if inst and inst.is_active and inst.talent_id == talent_id:
				return u.display_name
	return ""


func is_talent_equipped_anywhere(talent_id: String) -> bool:
	for i in range(panel.party.size()):
		var u : UnitData = panel.party[i]
		for inst in u.talent_slots:
			if inst and inst.is_active and inst.talent_id == talent_id: return true
		# ★ 也查职业特技
		if u.advanced_talent_id == talent_id:
			return true
	return false
