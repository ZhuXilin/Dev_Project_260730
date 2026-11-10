class_name EquipmentConfigForge
extends RefCounted

const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")

const QUALITY_ORDER : Array = ["common", "rare", "epic", "legendary"]

const FUSION_COST : int = 2000
var REFORGE_COST : int = 500
var REROLL_DIR_COST : int = 120
var MAX_SLOTS : int = 3
var CRAFT_COST : int = 200
var QUALITY_SCORE : Dictionary = {"common": 1, "rare": 3, "epic": 6, "legendary": 10}
var LUCKY_CHANCE : float = 0.05
var BONUS_SCORE_THRESHOLD : int = 10
var BONUS_CHANCE : float = 0.15
var CRAFT_QUALITY_TABLE : Array = []

var panel = null
var forge_slots : Array = []
var _forge_btn_row : HBoxContainer = null
var forge_matched_recipe : String = "" 

func _init(p):
	panel = p
	reload_config()

func reload_config():
	var cfg : Dictionary = GameConfigManager.get_value("economy_config.json", "forge", {})
	MAX_SLOTS = 3 
	CRAFT_COST = int(cfg.get("craft_cost", 200))
	REFORGE_COST = int(cfg.get("reforge_cost", 500))
	QUALITY_SCORE = cfg.get("quality_score", {"common":1,"rare":3,"epic":6,"legendary":10}).duplicate()
	LUCKY_CHANCE = float(cfg.get("lucky_chance", 0.05))
	BONUS_SCORE_THRESHOLD = int(cfg.get("bonus_score_threshold", 10))
	BONUS_CHANCE = float(cfg.get("bonus_chance", 0.15))
	CRAFT_QUALITY_TABLE = cfg.get("craft_quality_table", []).duplicate()
	if CRAFT_QUALITY_TABLE.is_empty():
		CRAFT_QUALITY_TABLE = [
			[0,  [90, 10,  0,  0]],
			[3,  [65, 30,  4,  1]],
			[6,  [40, 40, 15,  5]],
			[10, [20, 40, 30, 10]],
			[16, [10, 30, 40, 20]],
			[25, [ 0, 15, 40, 45]],
		]

func init_slots():
	forge_slots.clear()
	for i in range(MAX_SLOTS):
		forge_slots.append(null)
	_forge_btn_row = null

func has_pending() -> bool:
	for entry in forge_slots:
		if entry != null: return true
	return false

# ============================================================
#  构建铁匠铺 UI
# ============================================================
func build_forge_slots():
	for child in panel.right_container.get_children():
		if "Forge" in child.name:
			panel.right_container.remove_child(child)
			child.queue_free()

	_forge_btn_row = null
	panel._clear_container(panel.shop_container)

	panel.shop_container.visible = true
	panel.shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.shop_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# ★ 核心修复：强制关死 ShopScroll 的滚动功能，只留裁切
	if panel.shop_scroll:
		panel.shop_scroll.custom_minimum_size = Vector2.ZERO
		panel.shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.shop_scroll.scroll_vertical = 0
		panel.shop_scroll.clip_contents = true

	var wrap_vbox = VBoxContainer.new()
	wrap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.shop_container.add_child(wrap_vbox)

	var center_wrap = CenterContainer.new()
	center_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_wrap.custom_minimum_size = Vector2(0, 40) # ★ 缩小原本的 120 高度，定死
	wrap_vbox.add_child(center_wrap)

	var stack_btn : Button = Style.create_styled_button(Style.FONT_SMALL, Vector2(32, 32))
	stack_btn.custom_minimum_size = Vector2(32, 32)
	stack_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack_btn.expand_icon = false 
	stack_btn.set_meta("slot_type", "forge_slot")
	stack_btn.set_meta("forge_slot_index", -1)

	var count = 0
	for entry in forge_slots:
		if entry != null: count += 1
			
	if count > 0:
		stack_btn.text = "已放\n%d件" % count
		stack_btn.add_theme_font_size_override("font_size", 6)
		stack_btn.modulate = Color(1.0, 0.8, 0.4) 
	else:
		stack_btn.text = "放入\n防具"
		stack_btn.add_theme_font_size_override("font_size", 6)
		stack_btn.modulate = Color(0.6, 0.6, 0.6)

	center_wrap.add_child(stack_btn)

	_ensure_forge_craft_row()
	_refresh_forge_action_btns()


func _ensure_forge_craft_row():
	var should_show : bool = panel._is_shop_rest_mode() or panel.is_forge_mode()
	var existing : Node = panel.right_container.get_node_or_null("ForgeCraftRow")

	if not should_show:
		if existing: existing.queue_free()
		_forge_btn_row = null
		return

	_forge_btn_row = existing
	if _forge_btn_row == null:
		_forge_btn_row = HBoxContainer.new()
		_forge_btn_row.name = "ForgeCraftRow"
		_forge_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_forge_btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_forge_btn_row.add_theme_constant_override("separation", 4)
		panel.right_container.add_child(_forge_btn_row)
		var scroll_idx : int = panel.shop_scroll.get_index()
		panel.right_container.move_child(_forge_btn_row, scroll_idx + 1)


func _refresh_forge_action_btns():
	if not _forge_btn_row or not is_instance_valid(_forge_btn_row):
		return
		
	for c in _forge_btn_row.get_children():
		c.queue_free()

	var input_insts : Array = []
	for entry in forge_slots:
		if entry != null:
			input_insts.append(entry["inst"])

	# ★ 核心修改：直接返回，不要输出任何文字
	if input_insts.is_empty():
		return

	var clear_btn := Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	clear_btn.clip_text = true
	clear_btn.custom_minimum_size = Vector2(40, 16)
	clear_btn.text = "清空"
	clear_btn.pressed.connect(on_forge_clear_pressed)
	_forge_btn_row.add_child(clear_btn)

	if input_insts.size() == 1:
		var inst : ItemInstance = input_insts[0]
		var d : ItemData = ItemManager.get_item_data(inst.item_id)
		if d == null: return
		
		# ★ 修改点：只要不是特殊不可附魔防具，都显示“锻造”按钮
		if not d.no_affix:
			var forge_btn := Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
			forge_btn.clip_text = true
			forge_btn.custom_minimum_size = Vector2(45, 16)
			forge_btn.text = "锻造 (%dG)" % REFORGE_COST
			var can_afford : bool = panel._context.get_gold() >= REFORGE_COST
			forge_btn.disabled = not can_afford
			forge_btn.modulate = Color(0.8, 0.6, 1.0) if can_afford else Color(0.5, 0.5, 0.5)
			forge_btn.pressed.connect(_on_forge_action_single.bind(inst))
			_forge_btn_row.add_child(forge_btn)
			
		# ★ 修改点：只有带箭头的防具才显示“调整”按钮
		if inst.direction != Direction.Value.NONE:
			var dir_btn := Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
			dir_btn.clip_text = true
			dir_btn.custom_minimum_size = Vector2(45, 16)
			dir_btn.text = "调整 (%dG)" % REROLL_DIR_COST
			var can_afford_d : bool = panel._context.get_gold() >= REROLL_DIR_COST
			dir_btn.disabled = not can_afford_d
			dir_btn.modulate = Color(0.6, 0.8, 1.0) if can_afford_d else Color(0.5, 0.5, 0.5)
			dir_btn.pressed.connect(_on_forge_action_reroll_dir.bind(inst))
			_forge_btn_row.add_child(dir_btn)
			
		return

	var cost : int = CRAFT_COST
	var txt : String = "锻造 (%dG)" % cost
	
	if input_insts.size() == 2:
		var fusion : Dictionary = _check_fusion(input_insts)
		if fusion.get("ok", false):
			cost = FUSION_COST
			txt = "锻造:熔合(%dG)" % cost
			
	var craft_btn := Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	craft_btn.clip_text = true
	craft_btn.custom_minimum_size = Vector2(80, 16)
	craft_btn.text = txt
	var can_afford_c : bool = panel._context.get_gold() >= cost
	craft_btn.disabled = not can_afford_c
	craft_btn.modulate = Color(1.0, 0.6, 0.2) if can_afford_c else Color(0.5, 0.5, 0.5)
	craft_btn.pressed.connect(_on_forge_action_multi)
	_forge_btn_row.add_child(craft_btn)


# ============================================================
#  操作逻辑
# ============================================================
func _on_forge_action_single(inst : ItemInstance):
	if panel._context.get_gold() < REFORGE_COST:
		panel._show_buy_failure_message("not_enough_gold"); return
	if not panel._context.subtract_gold(REFORGE_COST):
		return

	var d = ItemManager.get_item_data(inst.item_id)
	inst.affixes = AffixManager.roll_affixes(d.quality, d.tags)

	# 直接进待领取区
	GameState.pending_forge_rewards.append(inst)
	for i in range(forge_slots.size()):
		var entry : Variant = forge_slots[i]
		if entry != null and entry["inst"] == inst:
			forge_slots[i] = null
			break

	SaveManager.auto_save()
	panel._sync_all()
	panel._build_unit_columns()
	panel._build_pending_slots()
	panel._update_gold_display()
	panel._show_detail_in_zone("★ %s 已锻造\n（请在上方领取）" % d.name)
	SoundManager.play_select_sound()
	panel._schedule_build_ui()


func _on_forge_action_reroll_dir(inst : ItemInstance):
	if panel._context.get_gold() < REROLL_DIR_COST:
		panel._show_buy_failure_message("not_enough_gold"); return
	if not panel._context.subtract_gold(REROLL_DIR_COST):
		return

	var old_dir := inst.direction
	inst.direction = Direction.reroll_direction(inst.direction)

	# 直接进待领取区
	GameState.pending_forge_rewards.append(inst)
	for i in range(forge_slots.size()):
		var entry : Variant = forge_slots[i]
		if entry != null and entry["inst"] == inst:
			forge_slots[i] = null
			break

	SaveManager.auto_save()
	panel._sync_all()
	panel._build_unit_columns()
	panel._build_pending_slots()
	panel._update_gold_display()
	
	var old_sym := Direction.get_display_symbol(old_dir)
	var new_sym := Direction.get_display_symbol(inst.direction)
	panel._show_detail_in_zone("★ 方向已调整：%s → %s\n（请在上方领取）" % [old_sym, new_sym])
	SoundManager.play_select_sound()
	panel._schedule_build_ui()


func _on_forge_action_multi():
	var input_insts : Array = []
	for entry in forge_slots:
		if entry != null:
			input_insts.append(entry["inst"])

	if input_insts.size() < 2: return
	for inst in input_insts:
		var d : ItemData = ItemManager.get_item_data(inst.item_id)
		if d and d.no_fusion:
			panel._show_detail_in_zone("熔铸防具不可加工")
			return

	if input_insts.size() == 2:
		var fusion : Dictionary = _check_fusion(input_insts)
		if fusion.get("ok", false):
			if panel._context.get_gold() < FUSION_COST:
				panel._show_buy_failure_message("not_enough_gold")
				return
			_do_fusion(fusion["product_id"], FUSION_COST)
			return

	if panel._context.get_gold() < CRAFT_COST:
		panel._show_buy_failure_message("not_enough_gold")
		return

	var input_ids : Array = []
	for inst in input_insts:
		input_ids.append(inst.item_id)

	var matched : String = RecipeManager.match_recipe(input_ids)
	var use_recipe : bool = (matched != "")

	var result : Dictionary = {}
	if use_recipe:
		result = _compute_recipe_result(matched)
	else:
		result = _compute_random_craft(input_insts)

	var out_ids : Array = result["item_ids"]
	if out_ids.is_empty():
		panel._show_detail_in_zone("合成失败：无可产出防具")
		panel._schedule_build_ui()
		return

	panel._context.subtract_gold(CRAFT_COST)

	for i in range(forge_slots.size()):
		forge_slots[i] = null

	# 重铸产物全部放入待领取区，不再优先放入单位
	for item_id in out_ids:
		var inst : ItemInstance = ItemManager.create_instance_with_affixes(item_id)
		if inst == null:
			inst = ItemInstance.new()
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


# ============================================================
#  归还 / 清空
# ============================================================
func _return_armor_to_unit(unit: UnitData, inst: ItemInstance, prefer_slot: int) -> bool:
	var need : int = panel._inst_slots(inst)
	var used : int = panel._used_slots_of(unit)
	if used + need > unit.max_armor_slots:
		return false
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
		
		if entry_dict["origin_unit"] == -1:
			GameState.pending_forge_rewards.append(entry_dict["inst"])
			forge_slots[i] = null
			continue
			
		var ou : UnitData = panel.party[entry_dict["origin_unit"]]
		var origin_slot : int = entry_dict["origin_slot"]
		if _return_armor_to_unit(ou, entry_dict["inst"], origin_slot):
			forge_slots[i] = null
		else:
			unresolved += 1
	return unresolved


func execute_forge_slot_return(_data: Dictionary):
	var unresolved : int = return_all_forge_slots()
	panel._build_unit_columns()
	if unresolved > 0:
		panel._show_detail_in_zone("有 %d 件防具无法归还" % unresolved)
	else:
		panel._show_detail_in_zone("已清空合成槽")
	build_forge_slots()
	panel._schedule_build_ui()


func on_forge_clear_pressed():
	var unresolved_count : int = return_all_forge_slots()
	panel._build_unit_columns()
	if unresolved_count > 0:
		panel._show_detail_in_zone("有 %d 件防具无法归还，已保留在合成槽" % unresolved_count)
	build_forge_slots()
	panel._schedule_build_ui()


# ============================================================
#  拖拽合法性 & 执行
# ============================================================
func is_valid_forge_drop(data: Dictionary, target: Control) -> bool:
	var src_type : String = data.get("slot_type", "")
	var tgt_type : String = target.get_meta("slot_type", "")

	# ★ 新增：待领取防具 → 合成槽（允许再次合成）
	if src_type == "pending_reward" and tgt_type == "forge_slot":
		var count = 0
		for entry in forge_slots:
			if entry != null: count += 1
		if count >= MAX_SLOTS:
			return false
		var pending_idx : int = data.get("pending_idx", -1)
		var pending_src : String = data.get("pending_src", "sacrifice")
		var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice" else GameState.pending_forge_rewards)
		if pending_idx < 0 or pending_idx >= list.size(): return false
		var inst : ItemInstance = list[pending_idx]
		if inst == null: return false
		var idata : ItemData = ItemManager.get_item_data(inst.item_id)
		if idata == null: return false
		if idata.type != "armor": return false
		if idata.no_fusion: return false
		return true

	if src_type == "armor" and tgt_type == "forge_slot":
		var count = 0
		for entry in forge_slots:
			if entry != null: count += 1
		if count >= MAX_SLOTS:
			return false
			
		var uidx2 : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		if uidx2 < 0 or src_slot < 0: return false
		var u2 : UnitData = panel.party[uidx2]
		if u2.is_dead: return false
		if src_slot >= u2.armor_slots.size(): return false
		if u2.armor_slots[src_slot] == null: return false
		return true

	if src_type == "armor" and tgt_type == "armor":
		return panel._check_armor_swap_budget(data, target)

	if src_type == "armor" and target == panel.discard_zone:
		return true

	if src_type == "forge_slot" and target == panel.discard_zone:
		return true 
		
	return false


func execute_forge_drop(data: Dictionary, target: Control):
	var src_type : String = data.get("slot_type", "")
	var tgt_type : String = target.get_meta("slot_type", "")

	if src_type == "armor" and tgt_type == "armor":
		panel._shop.swap_armor(data, target); return

	if target == panel.discard_zone:
		if src_type == "forge_slot":
			return_all_forge_slots()
			panel._build_unit_columns()
			panel._schedule_build_ui(); return
		if src_type == "armor":
			var uidx2 : int = data.get("unit_idx", -1)
			var sidx : int = data.get("slot_idx", -1)
			if uidx2 >= 0 and sidx >= 0:
				var du : UnitData = panel.party[uidx2]
				du.armor_slots[sidx] = null
			panel._build_unit_columns()
			panel._sync_all(); panel._schedule_build_ui(); return
		return

	if src_type == "armor" and tgt_type == "forge_slot":
		var empty_idx = -1
		for i in range(forge_slots.size()):
			if forge_slots[i] == null:
				empty_idx = i
				break
				
		if empty_idx < 0:
			panel._show_detail_in_zone("最多只能放入 %d 件" % MAX_SLOTS)
			return

		var uidx : int = data.get("unit_idx", -1)
		var src_slot : int = data.get("slot_idx", -1)
		if uidx < 0 or src_slot < 0: return
		var u : UnitData = panel.party[uidx]
		var inst : ItemInstance = u.armor_slots[src_slot]
		if inst == null: return
		
		u.armor_slots[src_slot] = null
		forge_slots[empty_idx] = {"inst": inst, "origin_unit": uidx, "origin_slot": src_slot}
		panel._build_unit_columns()
		build_forge_slots()
		panel._schedule_build_ui()
		return


# ============================================================
#  熔合 / 合成计算
# ============================================================
func _check_fusion(input_insts : Array) -> Dictionary:
	if input_insts.size() != 2: return {"ok": false}
	var a : ItemInstance = input_insts[0]
	var b : ItemInstance = input_insts[1]
	var da : ItemData = ItemManager.get_item_data(a.item_id)
	var db : ItemData = ItemManager.get_item_data(b.item_id)
	if not da or not db: return {"ok": false}
	if da.no_fusion or db.no_fusion: return {"ok": false}
	if da.quality != "epic" or db.quality != "epic": return {"ok": false}
	for tag in da.tags:
		if tag in db.tags:
			var product : ItemData = ItemManager.get_fusion_product(tag)
			if product:
				return {"ok": true, "tag": tag, "product_id": product.id}
	return {"ok": false}

func _do_fusion(product_id : String, cost : int):
	if not panel._context.subtract_gold(cost):
		panel._show_buy_failure_message("not_enough_gold")
		return

	for i in range(forge_slots.size()):
		forge_slots[i] = null

	var out_unit_idx : int = -1
	var out_slot : int = -1
	for i in range(panel.party.size()):
		var pu : UnitData = panel.party[i]
		if pu.is_dead: continue
		for s in range(pu.armor_slots.size()):
			if pu.armor_slots[s] == null:
				out_unit_idx = i
				out_slot = s
				break
		if out_unit_idx >= 0: break

	if out_unit_idx >= 0:
		var out_unit : UnitData = panel.party[out_unit_idx]
		var inst : ItemInstance = ItemManager.create_instance_with_affixes(product_id)
		if inst == null:
			inst = ItemInstance.new()
			inst.item_id = product_id
			inst.count = 1
		out_unit.armor_slots[out_slot] = inst
	else:
		var inst : ItemInstance = ItemManager.create_instance_with_affixes(product_id)
		if inst == null:
			inst = ItemInstance.new()
			inst.item_id = product_id
			inst.count = 1
		GameState.pending_forge_rewards.append(inst)

	forge_matched_recipe = ""
	SaveManager.auto_save()
	panel._sync_all()
	panel._build_unit_columns()
	panel._build_pending_slots()
	panel._update_gold_display()
	var out_data : ItemData = ItemManager.get_item_data(product_id)
	var name : String = out_data.name if out_data else product_id
	panel._show_detail_in_zone("★ 熔合成功！\n产出：" + name)
	panel._schedule_build_ui()


func _compute_recipe_result(recipe_id: String) -> Dictionary:
	var out_data : ItemData = ItemManager.get_item_data(recipe_id)
	var quality : String = out_data.quality if out_data else "common"
	return {
		"item_ids": [recipe_id],
		"quality": quality,
		"bonus_count": 0,
		"is_recipe": true,
		"input_score": 0,
		"lucky": false,
	}


func _compute_random_craft(input_insts : Array) -> Dictionary:
	for inst in input_insts:
		var d : ItemData = ItemManager.get_item_data(inst.item_id)
		if d and d.no_fusion:
			push_warning("[Forge] 输入含不可熔合装备 %s" % inst.item_id)
			return {
				"item_ids": [], "quality": "common", "bonus_count": 0,
				"is_recipe": false, "input_score": 0, "lucky": false,
			}
	var score : int = _calc_input_score(input_insts)
	var quality : String = _roll_quality_by_score(score)

	var lucky : bool = false
	if randf() < LUCKY_CHANCE:
		var qi : int = QUALITY_ORDER.find(quality)
		quality = QUALITY_ORDER[mini(qi + 1, QUALITY_ORDER.size() - 1)]
		lucky = true

	var candidates : Array = []
	_collect_armor_candidates(quality, candidates)
	while candidates.is_empty() and QUALITY_ORDER.find(quality) > 0:
		quality = QUALITY_ORDER[QUALITY_ORDER.find(quality) - 1]
		_collect_armor_candidates(quality, candidates)

	if candidates.is_empty():
		for iid in ItemManager.get_all_item_ids():
			var d : ItemData = ItemManager.get_item_data(iid)
			if d and d.type == "armor":
				candidates.append(iid)
				break
	if candidates.is_empty():
		push_warning("[Forge] 没有任何防具可合成")
		return {
			"item_ids": [],
			"quality": "common",
			"bonus_count": 0,
			"is_recipe": false,
			"input_score": score,
			"lucky": false,
		}

	var out_ids : Array = [candidates[randi() % candidates.size()]]

	var bonus_count : int = 0
	if input_insts.size() >= 3 and score >= BONUS_SCORE_THRESHOLD and randf() < BONUS_CHANCE:
		bonus_count = 1
		out_ids.append(candidates[randi() % candidates.size()])

	return {
		"item_ids": out_ids,
		"quality": quality,
		"bonus_count": bonus_count,
		"is_recipe": false,
		"input_score": score,
		"lucky": lucky,
	}


func _calc_input_score(input_insts : Array) -> int:
	var score : int = 0
	for inst in input_insts:
		var data : ItemData = ItemManager.get_item_data(inst.item_id)
		if data:
			score += int(QUALITY_SCORE.get(data.quality, 1))
	return score


func _roll_quality_by_score(score: int) -> String:
	var weights : Array = CRAFT_QUALITY_TABLE[0][1]
	for row in CRAFT_QUALITY_TABLE:
		if score >= row[0]:
			weights = row[1]
		else:
			break

	var total : int = 0
	for w in weights:
		total += w
	if total <= 0:
		return "common"
	var roll : int = randi() % total
	var acc : int = 0
	for i in range(weights.size()):
		acc += weights[i]
		if roll < acc:
			return QUALITY_ORDER[i]
	return "common"


func _collect_armor_candidates(quality: String, out: Array):
	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if not d: continue
		if d.type != "armor": continue
		if d.quality != quality: continue
		if d.price <= 0: continue
		out.append(iid)


func cleanup():
	var n : Node = panel.right_container.get_node_or_null("ForgeCraftRow")
	if n:
		panel.right_container.remove_child(n)
		n.queue_free()
	_forge_btn_row = null
