extends Node
class_name UIManager

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

# ---- UI 节点引用 ----
var action_menu : CanvasLayer
var action_panel : PanelContainer
var move_btn : Button
var attack_btn : Button
var wait_btn : Button
var item_btn : Button
var victory_panel : Panel
var victory_label : Label
var victory_button : Button
var equip_menu : PanelContainer
var equip_container : VBoxContainer
var equip_btn : Button
var weapon_select_menu : PanelContainer = null
var weapon_select_container : VBoxContainer = null
var item_action_panel: CanvasLayer
var panel_unit: Unit = null
var _panel_container: Control
var _buttons_container: VBoxContainer
var _panel_background: ColorRect = null

# ============================================================
#  初始化
# ============================================================
func initialize(ui_nodes: Dictionary):
	action_menu = ui_nodes.get("action_menu")
	action_panel = ui_nodes.get("action_panel")
	move_btn = ui_nodes.get("move_btn")
	attack_btn = ui_nodes.get("attack_btn")
	wait_btn = ui_nodes.get("wait_btn")
	item_btn = ui_nodes.get("item_btn")
	victory_panel = ui_nodes.get("victory_panel")
	victory_label = ui_nodes.get("victory_label")
	victory_button = ui_nodes.get("victory_button")
	equip_menu = ui_nodes.get("equip_menu")
	if equip_menu:
		equip_container = equip_menu.get_node("ItemsContainer") as VBoxContainer
	equip_btn = ui_nodes.get("equip_btn")
	weapon_select_menu = ui_nodes.get("weapon_select_menu")
	if weapon_select_menu:
		weapon_select_container = weapon_select_menu.get_node("WeaponSelectContainer") as VBoxContainer
		weapon_select_menu.visible = false

	item_action_panel = ui_nodes.get("ItemActionPanel")
	if item_action_panel:
		_panel_container = item_action_panel.get_node("Panel")
		_buttons_container = _panel_container.get_node("ActionButtons")
		
# ============================================================
#  行动菜单
# ============================================================
func show_menu(unit: Unit):
	hide_equip_menu()
	hide_weapon_select_menu()
	if TurnManager.current_turn_team != 0 or TurnManager.is_game_over or TurnManager.all_acted:
		return
	if not action_menu or not unit:
		return

	SoundManager.play_select_sound()
	print("=== 菜单显示 ===")
	print("单位: ", unit.unit_stats.unit_name)
	print("剩余移动: ", unit.remaining_move)
	print("已攻击: ", unit.has_attacked)

	if unit.remaining_move > 0:
		var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.remaining_move, unit)
		if reachable.size() <= 1:
			unit.remaining_move = 0

	action_menu.visible = true
	if action_panel:
		action_panel.visible = true

	move_btn.disabled = not (unit.can_move() and not unit.has_attacked and not unit.has_acted)

	var weapon_type = unit.get_weapon_type()
	if weapon_type == UnitDataManagerClass.WEAPON_HEAL:
		attack_btn.text = "治疗"
	elif weapon_type == UnitDataManagerClass.WEAPON_MAGIC:
		attack_btn.text = "魔法"
	elif weapon_type == UnitDataManagerClass.WEAPON_DRAGONSTONE:
		attack_btn.text = "龙炎"
	else:
		attack_btn.text = "攻击"

	var can_attack = true
	var equipped_id = unit.get_equipped_weapon_id()
	if equipped_id == "" or not unit.can_use_weapon(equipped_id):
		can_attack = false
	
	attack_btn.disabled = unit.has_acted or not unit.can_act_this_turn or not can_attack

	wait_btn.disabled = false

	if equip_btn:
		equip_btn.disabled = false

	if item_btn:
		var has_items = ItemManager.has_any_item()
		item_btn.disabled = not has_items or unit.has_attacked or not unit.can_act_this_turn

func hide_menu():
	if action_menu:
		action_menu.visible = false
	hide_equip_menu()
	hide_weapon_select_menu()

# ============================================================
#  装备菜单（含给予/丢弃）
# ============================================================
# 以下是 show_equip_menu 的完整实现，其他函数不变

func show_equip_menu(unit: Unit):
	if not equip_menu or not equip_container:
		return
	if action_menu:
		action_menu.visible = true

	for child in equip_container.get_children():
		child.queue_free()

	equip_menu.size.x = 180
	equip_container.size.x = 160

	var can_act = unit.can_act_this_turn and not unit.has_acted

	# ---- 武器槽 ----
	var weapon_label = Label.new()
	weapon_label.text = "武器"
	weapon_label.add_theme_font_size_override("font_size", 8)
	equip_container.add_child(weapon_label)

	var weapon_inst = unit.get_weapon()
	if weapon_inst:
		var btn = _create_item_button(weapon_inst, unit, can_act, -1, true)
		equip_container.add_child(btn)
	else:
		var empty_label = Label.new()
		empty_label.text = "（空）"
		empty_label.add_theme_font_size_override("font_size", 6)
		equip_container.add_child(empty_label)

	# ---- 防具/饰品槽 ----
	var armor_label = Label.new()
	armor_label.text = "防具/饰品"
	armor_label.add_theme_font_size_override("font_size", 8)
	equip_container.add_child(armor_label)

	var armor_slots = unit.get_armor_slots()
	for i in range(armor_slots.size()):
		var hbox = HBoxContainer.new()
		var slot_label = Label.new()
		slot_label.text = "槽" + str(i+1) + ":"
		slot_label.add_theme_font_size_override("font_size", 6)
		slot_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hbox.add_child(slot_label)

		var inst = armor_slots[i]
		if inst:
			var btn = _create_item_button(inst, unit, can_act, i, false)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(btn)
			if can_act:
				var unequip_btn = Button.new()
				unequip_btn.text = "×"
				unequip_btn.add_theme_font_size_override("font_size", 6)
				unequip_btn.pressed.connect(_on_unequip_armor_pressed.bind(unit, i))
				unequip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				hbox.add_child(unequip_btn)
		else:
			var empty_label = Label.new()
			empty_label.text = "（空）"
			empty_label.add_theme_font_size_override("font_size", 6)
			empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(empty_label)

		equip_container.add_child(hbox)

	# ---- 背包道具（排除已装备的） ----
	var backpack_label = Label.new()
	backpack_label.text = "背包"
	backpack_label.add_theme_font_size_override("font_size", 8)
	equip_container.add_child(backpack_label)

	var equipped_insts = []
	if unit.get_weapon():
		equipped_insts.append(unit.get_weapon())
	for slot in unit.get_armor_slots():
		if slot:
			equipped_insts.append(slot)

	var has_backpack_item = false
	for inst in unit.inventory:
		if inst in equipped_insts:
			continue
		has_backpack_item = true
		var btn = _create_item_button(inst, unit, can_act, -1, false)
		equip_container.add_child(btn)

	if not has_backpack_item:
		var empty_label = Label.new()
		empty_label.text = "（空）"
		empty_label.add_theme_font_size_override("font_size", 6)
		equip_container.add_child(empty_label)

	# 调整面板高度
	await get_tree().process_frame
	var container_min_height = equip_container.get_minimum_size().y
	var style = equip_menu.get_theme_stylebox("panel")
	var margin_top = style.get_margin(SIDE_TOP) if style else 0.0
	var margin_bottom = style.get_margin(SIDE_BOTTOM) if style else 0.0
	var panel_height = container_min_height + margin_top + margin_bottom
	equip_menu.size.y = panel_height

	_show_submenu(equip_menu)
	Globals.is_equip_menu_active = true

func _create_item_button(inst: ItemInstance, unit: Unit, can_act: bool, slot_index: int = -1, _is_weapon: bool = false) -> Button:
	var data = ItemManager.get_item_data(inst.item_id)
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 6)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if data.icon:
		btn.icon = data.icon
	btn.text = data.name
	if not can_act:
		btn.disabled = true
	else:
		btn.pressed.connect(_show_item_action_panel.bind(unit, inst, slot_index))
	return btn

func _on_unequip_armor_pressed(unit: Unit, slot_index: int):
	if not unit.can_act_this_turn or unit.has_acted:
		return
	var removed = unit.unequip_armor(slot_index)
	if removed:
		if unit.add_item(removed.item_id, removed.count):
			print("卸下装备到背包")
		else:
			print("背包已满，装备已丢弃")
		unit.mark_non_attack_action()
		show_equip_menu(unit)

func hide_equip_menu():
	_hide_submenu(equip_menu)
	Globals.is_equip_menu_active = false

# ============================================================
#  武器选择菜单
# ============================================================
func show_weapon_select_menu(unit: Unit, weapons: Array):
	if not weapon_select_menu or not weapon_select_container:
		print("武器选择菜单未初始化")
		return
	for child in weapon_select_container.get_children():
		child.queue_free()

	weapons.sort_custom(func(a, b):
		var a_equipped = (a == unit.get_equipped_weapon_id())
		var b_equipped = (b == unit.get_equipped_weapon_id())
		if a_equipped and not b_equipped:
			return true
		if not a_equipped and b_equipped:
			return false
		return a < b
	)

	for weapon_id in weapons:
		var data = ItemManager.get_item_data(weapon_id)
		if not data:
			continue
		var btn = Button.new()
		var type_display = ""
		if data.category != "":
			type_display = UnitDataManager.get_weapon_category_display(data.category)
		else:
			type_display = _get_type_display_name(data.type)
		var attack_str = ""
		if data.stats.has("attack"):
			attack_str += "物理+" + str(data.stats["attack"])
		if data.stats.has("magic_attack"):
			attack_str += "魔法+" + str(data.stats["magic_attack"])
		if data.stats.has("heal_amount"):
			attack_str += "治疗+" + str(data.stats["heal_amount"])
		btn.text = data.name + " [" + type_display + "] " + attack_str
		btn.add_theme_font_size_override("font_size", 6)
		btn.pressed.connect(_on_weapon_selected.bind(unit, weapon_id))
		weapon_select_container.add_child(btn)

	_show_submenu(weapon_select_menu)
	Globals.is_weapon_select_active = true

func hide_weapon_select_menu():
	_hide_submenu(weapon_select_menu)
	Globals.is_weapon_select_active = false

# ============================================================
#  子菜单辅助
# ============================================================
func _show_submenu(menu: Control):
	if action_panel:
		action_panel.visible = false
	if menu:
		menu.visible = true

func _hide_submenu(menu: Control):
	if menu:
		menu.visible = false
	if action_panel:
		action_panel.visible = true

# ============================================================
#  按钮回调
# ============================================================
func _on_equip_weapon_pressed(unit: Unit, item_id: String):
	hide_item_action_panel()
	var inst = unit.find_first_instance(item_id)
	if inst and unit.equip_weapon(inst):
		InputManager.selected_unit = unit
		InputManager.interaction_phase = "menu"
		SignalBus.request_show_menu.emit(unit)
		SignalBus.request_show_info.emit(unit)
	else:
		SoundManager.play_invalid_sound()

func _on_use_item_pressed(unit: Unit, item_id: String):
	hide_item_action_panel()
	_execute_use_item(unit, item_id)

func _on_give_item_pressed(unit: Unit, inst: ItemInstance):
	hide_item_action_panel()
	var success = InputManager.on_give_button_pressed(unit, inst)
	if not success:
		show_equip_menu(unit)

func _on_drop_item_pressed(unit: Unit, inst: ItemInstance):
	hide_item_action_panel()
	if unit.equipped_weapon_instance == inst:
		SoundManager.play_invalid_sound()
		return
	if unit.has_acted:
		SoundManager.play_invalid_sound()
		return
	if unit.remove_instance(inst):
		if unit.equipped_weapon_instance == inst:
			unit.equipped_weapon_instance = null
		unit.mark_non_attack_action()
		show_equip_menu(unit)
		SoundManager.play_select_sound()
	else:
		SoundManager.play_invalid_sound()

func _on_weapon_selected(unit: Unit, weapon_id: String):
	hide_weapon_select_menu()
	InputManager.on_attack_weapon_selected(unit, weapon_id)

# ============================================================
#  胜利面板
# ============================================================
func show_victory(label_text: String, button_text: String, callback: Callable):
	if not victory_label or not victory_button:
		return
	victory_label.text = label_text
	victory_button.text = button_text
	if victory_button.pressed.is_connected(_on_victory_button_pressed):
		victory_button.pressed.disconnect(_on_victory_button_pressed)
	victory_button.pressed.connect(_on_victory_button_pressed.bind(callback))
	victory_panel.visible = true
	move_btn.disabled = true
	attack_btn.disabled = true
	wait_btn.disabled = true
	if item_btn:
		item_btn.disabled = true

func _on_victory_button_pressed(callback: Callable):
	victory_panel.visible = false
	if callback.is_valid():
		callback.call()

# ============================================================
#  辅助函数（道具类型显示等）
# ============================================================
func _get_type_display_name(type: String) -> String:
	match type:
		"weapon": return "武器"
		"heal": return "回复"
		"cure": return "治愈"
		"buff": return "增益"
		"attack": return "攻击"
		_: return type

func get_effect_cells(unit: Unit, use_effect: Dictionary) -> Dictionary:
	var min_range = use_effect.get("min_range", 0)
	var max_range = use_effect.get("max_range", 0)
	var cells = {}
	for x in range(-max_range, max_range+1):
		for y in range(-max_range, max_range+1):
			var dist = abs(x) + abs(y)
			if dist < min_range or dist > max_range:
				continue
			var cell = unit.grid_cell + Vector2i(x, y)
			if cell.x < 0 or cell.x >= TerrainManager.grid_size.x or cell.y < 0 or cell.y >= TerrainManager.grid_size.y:
				continue
			cells[cell] = true
	return cells

func get_usable_targets(unit: Unit, use_effect: Dictionary) -> Array:
	var min_range = use_effect.get("min_range", 0)
	var max_range = use_effect.get("max_range", 0)
	var target_type = use_effect.get("target", "self")
	var targets = []
	for u in UnitManager.unit_list:
		if u.hit_points <= 0:
			continue
		var dist = abs(u.grid_cell.x - unit.grid_cell.x) + abs(u.grid_cell.y - unit.grid_cell.y)
		if dist < min_range or dist > max_range:
			continue
		if target_type == "ally":
			if u.unit_stats.team_id == unit.unit_stats.team_id:
				targets.append(u)
		elif target_type == "enemy":
			if u.unit_stats.team_id != unit.unit_stats.team_id:
				targets.append(u)
		else:
			targets.append(u)
	return targets

# ============================================================
#  道具操作面板
# ============================================================
func _show_item_action_panel(unit: Unit, inst: ItemInstance, _slot_index: int = -1):
	print("=== _show_item_action_panel 被调用 ===")
	if not item_action_panel or not _buttons_container:
		print("面板或容器为空")
		return

	Globals.is_item_action_panel_open = true
	panel_unit = unit
	SignalBus.request_hide_menu.emit()

	if _panel_background:
		_panel_background.queue_free()
	_panel_background = ColorRect.new()
	_panel_background.color = Color(0, 0, 0, 0)
	_panel_background.size = get_viewport().get_visible_rect().size
	_panel_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_action_panel.add_child(_panel_background)

	var can_act = unit.can_act_this_turn and not unit.has_acted
	var data = ItemManager.get_item_data(inst.item_id)
	if not data:
		print("道具数据为空")
		return

	for child in _buttons_container.get_children():
		child.queue_free()

	var title_label = _panel_container.get_node_or_null("Title")
	if title_label:
		title_label.text = data.name

	if _panel_container:
		_panel_container.mouse_filter = Control.MOUSE_FILTER_STOP

	var is_weapon = (data.type == "weapon")
	var is_equipped = (is_weapon and inst == unit.equipped_weapon_instance)
	var can_use = (not is_weapon and data.use_effect and not data.use_effect.is_empty())
	var can_give = (not is_equipped)
	var can_drop = (not is_equipped)
	var can_equip = (is_weapon and not is_equipped and unit.can_use_weapon(inst.item_id))

	var make_button = func(text: String, callback: Callable) -> Button:
		var btn = Button.new()
		btn.text = text
		btn.add_theme_font_size_override("font_size", 6)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(callback)
		return btn

	var make_label = func(text: String) -> Label:
		var lbl = Label.new()
		lbl.text = text
		lbl.add_theme_font_size_override("font_size", 6)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return lbl

	if is_weapon:
		if is_equipped:
			_buttons_container.add_child(make_label.call("已装备"))
		else:
			var btn = make_button.call("装备", _on_equip_weapon_pressed.bind(unit, inst.item_id))
			btn.disabled = not (can_equip and can_act)
			_buttons_container.add_child(btn)

	if not is_weapon and can_use:
		var btn = make_button.call("使用", _on_use_item_pressed.bind(unit, inst.item_id))
		btn.disabled = not can_act
		_buttons_container.add_child(btn)

	if can_give:
		var btn = make_button.call("给予", _on_give_item_pressed.bind(unit, inst))
		btn.disabled = not can_act
		_buttons_container.add_child(btn)

	if can_drop:
		var btn = make_button.call("丢弃", _on_drop_item_pressed.bind(unit, inst))
		btn.disabled = not can_act
		_buttons_container.add_child(btn)

	item_action_panel.visible = true
	print("面板已显示")

func hide_item_action_panel():
	print("hide_item_action_panel 被调用")
	Globals.is_item_action_panel_open = false
	if item_action_panel:
		item_action_panel.visible = false
	if _panel_background:
		_panel_background.queue_free()
		_panel_background = null

# ============================================================
#  两步丢弃菜单（紧凑尺寸 + 滚动）
# ============================================================
func show_drop_menu_with_choice(unit: Unit, new_item_id: String, new_count: int, callback_success: Callable, callback_cancel: Callable):
	# 模态弹出
	var popup = CanvasLayer.new()
	popup.layer = 30
	get_tree().current_scene.add_child(popup)

	var panel = Panel.new()
	panel.size = Vector2(160, 150)   # 固定较小尺寸
	var viewport_size = get_viewport().get_visible_rect().size
	panel.position = viewport_size / 2 - panel.size / 2

	var stylebox = load("res://content/resource/stylebox/8bit_style_box_flat.tres")
	if stylebox:
		panel.add_theme_stylebox_override("panel", stylebox)
	popup.add_child(panel)

	# 步骤1：选择操作
	var label = Label.new()
	label.text = "背包已满，选择操作："
	label.add_theme_font_size_override("font_size", 8)
	label.position = Vector2(10, 10)
	panel.add_child(label)

	# 使用 ScrollContainer 容纳 VBoxContainer，防止溢出
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(10, 35)
	scroll.size = Vector2(140, 100)  # 适应面板
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size = scroll.size
	scroll.add_child(vbox)

	var drop_btn = Button.new()
	drop_btn.text = "丢弃装备"
	drop_btn.add_theme_font_size_override("font_size", 6)
	drop_btn.pressed.connect(_on_drop_choice_show_items.bind(unit, new_item_id, new_count, panel, scroll, vbox, popup, callback_success, callback_cancel))
	vbox.add_child(drop_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "放弃获得"
	cancel_btn.add_theme_font_size_override("font_size", 6)
	cancel_btn.pressed.connect(_on_drop_choice_cancel.bind(popup, callback_cancel))
	vbox.add_child(cancel_btn)

	Globals.is_item_get_popup_active = true

func _on_drop_choice_show_items(unit: Unit, new_item_id: String, new_count: int, panel: Panel, scroll: ScrollContainer, vbox: VBoxContainer, popup: CanvasLayer, callback_success: Callable, callback_cancel: Callable):
	# 清空当前面板内除标签和滚动容器外的所有内容
	for child in panel.get_children():
		if child != scroll and child is Label and child.text.begins_with("背包已满"):
			# 保留标签
			pass
		elif child != scroll:
			child.queue_free()

	# 更新标签文字
	var label = panel.get_child(0) as Label
	if label:
		label.text = "选择要丢弃的道具："

	# 清空 vbox
	for child in vbox.get_children():
		child.queue_free()

	# 获取可丢弃道具
	var items = []
	for inst in unit.inventory:
		if inst != unit.equipped_weapon_instance:
			items.append(inst)

	if items.is_empty():
		_on_drop_choice_cancel(popup, callback_cancel)
		return

	for inst in items:
		var data = ItemManager.get_item_data(inst.item_id)
		if not data:
			continue
		var hbox = HBoxContainer.new()
		var name_label = Label.new()
		name_label.text = data.name + " x" + str(inst.count)
		name_label.add_theme_font_size_override("font_size", 6)
		hbox.add_child(name_label)

		var drop_btn = Button.new()
		drop_btn.text = "丢弃"
		drop_btn.add_theme_font_size_override("font_size", 5)
		drop_btn.pressed.connect(_on_drop_item_selected.bind(unit, inst, new_item_id, new_count, popup, callback_success, callback_cancel))
		hbox.add_child(drop_btn)
		vbox.add_child(hbox)

	# 返回按钮
	var back_btn = Button.new()
	back_btn.text = "返回"
	back_btn.add_theme_font_size_override("font_size", 6)
	back_btn.pressed.connect(_on_drop_choice_back.bind(unit, new_item_id, new_count, panel, scroll, vbox, popup, callback_success, callback_cancel))
	vbox.add_child(back_btn)

	# 确保滚动容器尺寸不变
	scroll.size = Vector2(140, 100)

func _on_drop_item_selected(unit: Unit, inst: ItemInstance, _new_item_id: String, _new_count: int, popup: CanvasLayer, callback_success: Callable, _callback_cancel: Callable):
	unit.remove_instance(inst)
	popup.queue_free()
	Globals.is_item_get_popup_active = false
	if callback_success.is_valid():
		callback_success.call()

func _on_drop_choice_cancel(popup: CanvasLayer, callback_cancel: Callable):
	popup.queue_free()
	Globals.is_item_get_popup_active = false
	if callback_cancel.is_valid():
		callback_cancel.call()

func _on_drop_choice_back(unit: Unit, new_item_id: String, new_count: int, panel: Panel, scroll: ScrollContainer, vbox: VBoxContainer, popup: CanvasLayer, callback_success: Callable, callback_cancel: Callable):
	# 恢复步骤1
	for child in panel.get_children():
		if child != scroll and child is Label:
			child.text = "背包已满，选择操作："
		elif child != scroll:
			child.queue_free()

	for child in vbox.get_children():
		child.queue_free()

	var drop_btn = Button.new()
	drop_btn.text = "丢弃装备"
	drop_btn.add_theme_font_size_override("font_size", 6)
	drop_btn.pressed.connect(_on_drop_choice_show_items.bind(unit, new_item_id, new_count, panel, scroll, vbox, popup, callback_success, callback_cancel))
	vbox.add_child(drop_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "放弃获得"
	cancel_btn.add_theme_font_size_override("font_size", 6)
	cancel_btn.pressed.connect(_on_drop_choice_cancel.bind(popup, callback_cancel))
	vbox.add_child(cancel_btn)

# ---- 兼容旧接口 ----
func show_drop_choice(unit: Unit, new_item_id: String, new_count: int, callback_success: Callable, callback_cancel: Callable = Callable()):
	show_drop_menu_with_choice(unit, new_item_id, new_count, callback_success, callback_cancel)

func show_drop_for_new_item(unit: Unit, new_item_id: String, new_count: int):
	show_drop_menu_with_choice(
		unit,
		new_item_id,
		new_count,
		Callable(self, "_on_drop_for_new_item_success").bind(unit, new_item_id, new_count),
		Callable(self, "_on_drop_for_new_item_cancel")
	)

func _on_drop_for_new_item_success(unit: Unit, new_item_id: String, new_count: int):
	if unit.add_item(new_item_id, new_count):
		EventManager.show_item_get_popup(new_item_id, new_count)

func _on_drop_for_new_item_cancel():
	print("放弃获得道具")

# ============================================================
#  模态消息提示（给予道具失败）
# ============================================================
func show_modal_message(text: String, callback_after: Callable = Callable()):
	# 模态弹窗，带“确定”按钮
	var popup = CanvasLayer.new()
	popup.layer = 40
	get_tree().current_scene.add_child(popup)

	var panel = Panel.new()
	panel.size = Vector2(160, 80)
	var viewport_size = get_viewport().get_visible_rect().size
	panel.position = viewport_size / 2 - panel.size / 2

	var stylebox = load("res://content/resource/stylebox/8bit_style_box_flat.tres")
	if stylebox:
		panel.add_theme_stylebox_override("panel", stylebox)
	popup.add_child(panel)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.position = Vector2(10, 10)
	label.size = Vector2(140, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	var btn = Button.new()
	btn.text = "确定"
	btn.add_theme_font_size_override("font_size", 6)
	btn.position = Vector2(55, 50)
	btn.size = Vector2(50, 20)
	btn.pressed.connect(func():
		popup.queue_free()
		Globals.is_item_get_popup_active = false
		if callback_after.is_valid():
			callback_after.call()
	)
	panel.add_child(btn)

	Globals.is_item_get_popup_active = true

func show_message(text: String):
	# 创建弹出层（含全屏透明遮罩）
	var popup = CanvasLayer.new()
	popup.layer = 40
	get_tree().current_scene.add_child(popup)

	# 透明遮罩，拦截鼠标点击
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0)  # 完全透明
	bg.size = get_viewport().get_visible_rect().size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.add_child(bg)

	# 主面板
	var panel = Panel.new()
	panel.size = Vector2(180, 60)
	var viewport_size = get_viewport().get_visible_rect().size
	panel.position = viewport_size / 2 - panel.size / 2

	var stylebox = load("res://content/resource/stylebox/8bit_style_box_flat.tres")
	if stylebox:
		panel.add_theme_stylebox_override("panel", stylebox)
	popup.add_child(panel)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = panel.size
	panel.add_child(label)

	# 阻塞游戏操作（设置标志）
	Globals.is_item_get_popup_active = true  # 复用这个标志

	await get_tree().create_timer(1.5).timeout

	# 解除阻塞
	Globals.is_item_get_popup_active = false
	popup.queue_free()

# ============================================================
#  使用道具（内部）
# ============================================================
func _execute_use_item(unit: Unit, item_id: String):
	var data = ItemManager.get_item_data(item_id)
	if not data:
		return
	var use_effect = data.use_effect
	if use_effect.is_empty():
		return

	var target_type = use_effect.get("target", "self")
	var is_attack_item = (use_effect.get("type") == "damage")

	if is_attack_item and unit.has_acted:
		print("本回合已行动，无法再使用攻击道具")
		return
	if not is_attack_item and unit.has_acted:
		print("本回合已行动，无法再使用非攻击道具")
		return

	if target_type == "self":
		Globals.is_performing_action = true
		var success = ItemManager.use_item_on_target(item_id, unit, unit)
		if success:
			if not is_attack_item:
				unit.mark_non_attack_action()
			else:
				unit.mark_attacked()
			await get_tree().create_timer(CombatManager.PERFORMANCE_DURATION).timeout
			Globals.is_performing_action = false
			hide_equip_menu()
			SignalBus.request_show_menu.emit(unit)
		else:
			Globals.is_performing_action = false
		return

	hide_equip_menu()
	hide_menu()
	SignalBus.request_hide_info.emit()
	var battlefield = get_node("/root/Battlefield")
	if battlefield and battlefield.camera_controller:
		battlefield.camera_controller.cancel_smooth_move()

	InputManager.selected_unit = unit
	InputManager.interaction_phase = "item_target"
	InputManager.pending_item_id = item_id
	InputManager.pending_item_effect = use_effect
	InputManager.pending_is_attack_item = is_attack_item

	var cells = get_effect_cells(unit, use_effect)
	SignalBus.request_highlight.emit(cells)
