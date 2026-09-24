class_name ChapelUI
extends CanvasLayer

signal closed

var _chosen : bool = false
var _pending_reward : Dictionary = {}
var _pre_roll_reward : Dictionary = {}

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/Title
@onready var hint_label : Label = $Panel/VBox/Hint
@onready var option_row : HBoxContainer = $Panel/VBox/OptionRow
@onready var item_row : HBoxContainer = $Panel/VBox/ItemRow
@onready var back_btn : Button = $Panel/VBox/BottomBar/BackBtn


func _ready():
	layer = 24
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)
	_build_main_options()


# ============================================================
#  主界面
# ============================================================
func _build_main_options():
	_clear_row(option_row)
	_clear_row(item_row)
	option_row.visible = true
	item_row.visible = false
	back_btn.visible = true

	if title_label:
		title_label.text = "圣坛"
	if hint_label:
		hint_label.text = "选择一项祝福"

	# ★ 预抽一件，按钮上显示道具名
	_pre_roll_reward = _roll_single_reward()
	var item_label : String = "强力道具"
	if not _pre_roll_reward.is_empty():
		item_label = "强力道具：" + _get_reward_display_name(_pre_roll_reward)
	else:
		item_label = "强力道具\n（无可用，+600G）"

	_add_option_button("金币 +600", _on_choose_gold)
	_add_option_button(item_label, _on_choose_item)
	_add_option_button(
		"全队回满 HP" + ("\n+ 复活 1 名阵亡单位" if GameState.has_any_dead_unit() else ""),
		_on_choose_heal
	)


func _add_option_button(text: String, cb: Callable):
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(160, 60)
	btn.add_theme_font_size_override("font_size", 9)
	btn.pressed.connect(cb)
	option_row.add_child(btn)


# ============================================================
#  选项 1：金币
# ============================================================
func _on_choose_gold():
	if _chosen: return
	_chosen = true
	EconomyManager.add_temp_gold(600)
	SaveManager.auto_save()
	print("[圣坛] 获得 600 金币")
	_close()


# ============================================================
#  选项 2：全队回满 + 复活
# ============================================================
func _on_choose_heal():
	if _chosen: return
	_chosen = true
	for ud in GameState.party:
		if ud.is_dead: continue
		ud.hit_points = ud.max_hp
	print("[圣坛] 全队回满 HP")

	if GameState.has_any_dead_unit():
		_show_revive_submenu()
	else:
		SaveManager.auto_save()
		_close()


func _show_revive_submenu():
	_clear_row(option_row)
	if hint_label:
		hint_label.text = "选择一名单位复活"

	var dead_units : Array = GameState.get_dead_party()
	for ud in dead_units:
		var btn := Button.new()
		btn.text = "%s（%s）" % [
			ud.display_name,
			UnitDataManager.get_unit_type_display_name(ud.unit_name)
		]
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_revive_unit.bind(ud.unit_name, ud.display_name))
		option_row.add_child(btn)

	var skip := Button.new()
	skip.text = "不复活"
	skip.custom_minimum_size = Vector2(140, 40)
	skip.add_theme_font_size_override("font_size", 8)
	skip.pressed.connect(func():
		SaveManager.auto_save()
		_close()
	)
	option_row.add_child(skip)


func _on_revive_unit(unit_name: String, display_name: String):
	if GameState.revive_unit(unit_name, display_name):
		SaveManager.auto_save()
		print("[圣坛] 复活 %s" % display_name)
	_close()


# ============================================================
#  选项 3：强力道具（遗物 / 精炼）
# ============================================================
func _on_choose_item():
	if _chosen: return
	_chosen = true

	var picked : Dictionary = _pre_roll_reward
	if picked.is_empty():
		# 无候选 → 补偿金币
		EconomyManager.add_temp_gold(600)
		SaveManager.auto_save()
		print("[圣坛] 无可用道具，改为 600 金币")
		_close()
		return

	_pending_reward = picked
	var slot_idx : int = _find_empty_passive_slot()
	if slot_idx >= 0:
		_place_reward_into_slot(picked, slot_idx)
		_show_reward_popup(picked)
		_pending_reward = {}
		SaveManager.auto_save()
		_close()
	else:
		_show_replace_slot_ui(picked)


## 抽取单件：遗物 / 精炼（均已排除已拥有的）
func _roll_single_reward() -> Dictionary:
	# 已拥有遗物
	var owned_relics : Dictionary = {}
	for p in GameState.get_relics_from_passives():
		owned_relics[p.item_id] = true

	# 已拥有精炼
	var owned_refines : Dictionary = {}
	for p in GameState.get_refines_from_passives():
		var rid : String = p.get("refine_id", "")
		if rid != "":
			owned_refines[rid] = true

	var pool : Array = []

	# ---- 第一层：未拥有的遗物 + 未拥有的精炼 ----
	for rid in RelicManager.get_unlocked_relics():
		if not owned_relics.has(rid):
			pool.append({"type": "relic", "id": rid})
	for ref_id in RefineManager.get_all_ids():
		if not RefineManager.is_recipe_unlocked(ref_id):
			continue
		if owned_refines.has(ref_id):
			continue
		pool.append({"type": "refine", "id": ref_id})

	if not pool.is_empty():
		pool.shuffle()
		return pool[0]

	# ---- 第二层：允许重复的精炼 ----
	for ref_id in RefineManager.get_all_ids():
		if not RefineManager.is_recipe_unlocked(ref_id):
			continue
		pool.append({"type": "refine", "id": ref_id})

	if not pool.is_empty():
		pool.shuffle()
		return pool[0]

	# ---- 第三层：允许重复的遗物 ----
	for rid in RelicManager.get_unlocked_relics():
		pool.append({"type": "relic", "id": rid})

	if not pool.is_empty():
		pool.shuffle()
		return pool[0]

	# 彻底没东西
	return {}
	

func _find_empty_passive_slot() -> int:
	var passives : Array = GameState.get_passives()
	for i in range(passives.size()):
		if passives[i] == null:
			return i
	return -1


func _place_reward_into_slot(reward : Dictionary, slot_idx : int):
	var rtype : String = reward.get("type", "")
	var rid : String = reward.get("id", "")
	if rid == "":
		return
	if rtype == "relic":
		var inst := ItemInstance.new()
		inst.item_id = rid
		inst.count = 1
		RelicManager.unlock_relic(rid)
		GameState.set_passive_at_slot(slot_idx, inst)
		print("[圣坛] 遗物 %s → 槽 %d" % [rid, slot_idx])
	elif rtype == "refine":
		GameState.set_passive_at_slot(slot_idx, {"refine_id": rid, "count": 1})
		print("[圣坛] 精炼 %s → 槽 %d" % [rid, slot_idx])


# ============================================================
#  槽满：横排居中替换界面
# ============================================================
func _show_replace_slot_ui(reward : Dictionary):
	var rname : String = _get_reward_display_name(reward)
	if title_label:
		title_label.text = "选择丢弃的槽位"
	if hint_label:
		hint_label.text = "被动槽已满，点击一个槽位替换为「%s」" % rname

	_clear_row(option_row)
	_clear_row(item_row)
	option_row.visible = true
	item_row.visible = false
	back_btn.visible = false   # 必须选一个（或放弃）

	# option_row 是 HBox + alignment=1（居中），横排 4 个槽位按钮
	var passives : Array = GameState.get_passives()
	for i in range(passives.size()):
		var btn := Button.new()
		btn.text = _format_slot_display(passives[i], i)
		btn.custom_minimum_size = Vector2(80, 40)
		btn.add_theme_font_size_override("font_size", 7)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_replace_slot_picked.bind(i))
		option_row.add_child(btn)

	# 放弃按钮（返还 600 金币）
	var skip := Button.new()
	skip.text = "放弃\n+600G"
	skip.custom_minimum_size = Vector2(80, 40)
	skip.add_theme_font_size_override("font_size", 7)
	skip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skip.modulate = Color(0.7, 0.7, 0.7)
	skip.pressed.connect(_on_give_up_reward)
	option_row.add_child(skip)


func _on_replace_slot_picked(slot_idx : int):
	if _pending_reward.is_empty():
		return
	var reward : Dictionary = _pending_reward
	_pending_reward = {}
	_place_reward_into_slot(reward, slot_idx)
	_show_reward_popup(reward)
	SaveManager.auto_save()
	_close()


func _on_give_up_reward():
	_pending_reward = {}
	EconomyManager.add_temp_gold(600)
	SaveManager.auto_save()
	print("[圣坛] 放弃道具，+600 金币")
	_close()


func _format_slot_display(p : Variant, idx : int) -> String:
	var prefix : String = "槽%d：" % (idx + 1)
	if p == null:
		return prefix + "空"
	if p is ItemInstance:
		var rd : Dictionary = RelicManager.get_relic_data(p.item_id)
		return prefix + rd.get("name", p.item_id)
	if p is Dictionary and p.has("refine_id"):
		var recipe : Dictionary = RefineManager.get_recipe(p.get("refine_id", ""))
		return prefix + recipe.get("name", p.get("refine_id", ""))
	return prefix + "?"


func _get_reward_display_name(reward : Dictionary) -> String:
	var rtype : String = reward.get("type", "")
	var rid : String = reward.get("id", "")
	if rtype == "relic":
		var rd : Dictionary = RelicManager.get_relic_data(rid)
		return rd.get("name", rid)
	if rtype == "refine":
		var recipe : Dictionary = RefineManager.get_recipe(rid)
		return recipe.get("name", rid)
	return rid


# ============================================================
#  弹窗
# ============================================================
func _show_reward_popup(reward : Dictionary):
	if Globals.is_item_get_popup_active:
		return
	var scene = load(Config.PATHS.ITEM_GET_POPUP)
	if not scene:
		return
	var popup = scene.instantiate()
	get_tree().root.add_child(popup)
	var rtype : String = reward.get("type", "")
	var rid : String = reward.get("id", "")
	if rtype == "relic":
		popup.show_relic(rid, 1)
	elif rtype == "refine":
		popup.show_refine(rid, 1)


# ============================================================
#  辅助
# ============================================================
func _clear_row(row: Node):
	if not row: return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()


func _on_back_pressed():
	if _chosen:
		return
	close_without_choice()


func close_without_choice():
	_chosen = true
	SaveManager.auto_save()
	_close()


func _close():
	if not is_inside_tree():
		return
	closed.emit()
	queue_free()
