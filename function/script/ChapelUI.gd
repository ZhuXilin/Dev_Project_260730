class_name ChapelUI
extends CanvasLayer

signal closed

var _chosen : bool = false
var _item_options : Array = []   # 3 个候选 ItemInstance
var _item_pending : bool = false # 是否在"道具选择"子界面

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

	# 三个选项
	_add_option_button("金币 +600", _on_choose_gold)
	_add_option_button("强力道具（3 选 1）", _on_choose_item)
	_add_option_button("全队回满 HP" + ("\n+ 复活 1 名阵亡单位" if GameState.has_any_dead_unit() else ""), _on_choose_heal)


func _add_option_button(text: String, cb: Callable):
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(160, 60)
	btn.add_theme_font_size_override("font_size", 9)
	btn.pressed.connect(cb)
	option_row.add_child(btn)


func _on_choose_gold():
	if _chosen: return
	_chosen = true
	EconomyManager.add_temp_gold(600)
	SaveManager.auto_save()
	print("[圣坛] 获得 600 金币")
	_close()


func _on_choose_heal():
	if _chosen: return
	# 回血在 _apply 里做（因为要弹复活选择）
	_chosen = true
	# 全队回满
	for ud in GameState.party:
		if ud.is_dead: continue
		ud.hit_points = ud.max_hp
	print("[圣坛] 全队回满 HP")

	# 如果有阵亡，弹复活选择
	if GameState.has_any_dead_unit():
		_show_revive_submenu()
	else:
		SaveManager.auto_save()
		_close()


func _show_revive_submenu():
	_clear_row(option_row)
	_clear_row(item_row)
	if hint_label:
		hint_label.text = "选择一名单位复活"

	var dead_units : Array = GameState.get_dead_party()
	for ud in dead_units:
		var btn := Button.new()
		btn.text = "%s（%s）" % [ud.display_name, UnitDataManager.get_unit_type_display_name(ud.unit_name)]
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_revive_unit.bind(ud.unit_name, ud.display_name))
		option_row.add_child(btn)

	# 放弃复活（只回血）
	var skip := Button.new()
	skip.text = "不复活（仅回血）"
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


func _on_choose_item():
	if _chosen: return
	# 生成 3 个候选装备
	_item_options = _roll_item_options()
	if _item_options.is_empty():
		# 没候选 → 直接给金币做补偿
		EconomyManager.add_temp_gold(600)
		SaveManager.auto_save()
		print("[圣坛] 无可用道具，改为 600 金币")
		_chosen = true
		_close()
		return

	_item_pending = true
	_clear_row(option_row)
	_clear_row(item_row)
	option_row.visible = false
	item_row.visible = true
	back_btn.visible = true

	if title_label:
		title_label.text = "选择一件装备"
	if hint_label:
		hint_label.text = "三选一"

	for inst in _item_options:
		var data : ItemData = ItemManager.get_item_data(inst.item_id)
		if not data:
			var rd : Dictionary = RelicManager.get_relic_data(inst.item_id)
			if not rd.is_empty():
				# 遗物：临时构造显示
				var btn := Button.new()
				btn.text = "%s\n（遗物）" % rd.get("name", inst.item_id)
				btn.custom_minimum_size = Vector2(120, 60)
				btn.add_theme_font_size_override("font_size", 8)
				btn.pressed.connect(_on_item_chosen.bind(inst))
				item_row.add_child(btn)
			continue
		var btn := Button.new()
		btn.text = "%s\n[%s]" % [data.name, _quality_cn(data.quality)]
		btn.custom_minimum_size = Vector2(120, 60)
		btn.add_theme_font_size_override("font_size", 8)
		btn.modulate = UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE)
		btn.pressed.connect(_on_item_chosen.bind(inst))
		item_row.add_child(btn)


func _on_item_chosen(inst: ItemInstance):
	if not _item_pending: return
	var data : ItemData = ItemManager.get_item_data(inst.item_id)
	# 遗物
	if data == null:
		var rd : Dictionary = RelicManager.get_relic_data(inst.item_id)
		if not rd.is_empty():
			RelicManager.unlock_relic(inst.item_id)
			GameState.add_relic_to_passive_slot(inst)
			print("[圣坛] 获得遗物：%s" % rd.get("name", inst.item_id))
	else:
		# 武器 / 防具 → 直接进第一个能装的单位
		var placed := _try_place_equipment(inst)
		if not placed:
			# 没地方装 → 进待领取区
			GameState.pending_sacrifice_rewards.append(inst)
			print("[圣坛] 装备进待领取区：%s" % data.name)

	SaveManager.auto_save()
	_chosen = true
	_close()


func _try_place_equipment(inst: ItemInstance) -> bool:
	var data : ItemData = ItemManager.get_item_data(inst.item_id)
	if not data: return false
	for u in GameState.party:
		if u.is_dead: continue
		if data.type == "weapon" and u.weapon_slot == null:
			u.weapon_slot = inst
			return true
		if data.type == "armor":
			for i in range(u.armor_slots.size()):
				if u.armor_slots[i] == null:
					u.armor_slots[i] = inst
					return true
	return false


func _roll_item_options() -> Array:
	var result : Array = []

	# 池子：未拥有的遗物 / epic 武器 / epic 防具
	var owned_relics : Dictionary = {}
	for p in GameState.get_relics_from_passives():
		owned_relics[p.item_id] = true

	var pool : Array = []  # 元素：{"type": "...", "id": "..."}

	# 遗物
	for rid in RelicManager.get_unlocked_relics():
		if not owned_relics.has(rid):
			pool.append({"type": "relic", "id": rid})

	# epic 武器
	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if d and d.type == "weapon" and d.quality == "epic" and d.price > 0:
			pool.append({"type": "weapon", "id": iid})

	# epic 防具
	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if d and d.type == "armor" and d.quality == "epic" and d.price > 0:
			pool.append({"type": "armor", "id": iid})

	if pool.is_empty(): return result

	pool.shuffle()
	for i in range(mini(3, pool.size())):
		var e : Dictionary = pool[i]
		var inst := ItemInstance.new()
		inst.item_id = e["id"]
		inst.count = 1
		result.append(inst)
	return result


func _clear_row(row: Node):
	if not row: return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()


func _quality_cn(q: String) -> String:
	match q:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return q


func _on_back_pressed():
	if _item_pending:
		# 从子界面返回主选项
		_item_pending = false
		_item_options.clear()
		_build_main_options()
		return
	# 主界面：放弃圣坛（不选）
	close_without_choice()


func close_without_choice():
	_chosen = true
	SaveManager.auto_save()
	_close()


func _close():
	if _chosen == false:
		SaveManager.auto_save()
	closed.emit()
	queue_free()
