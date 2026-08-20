extends Panel

enum Mode { DEPLOY, MAP }

var current_mode: Mode = Mode.DEPLOY
var selected_units: Array[String] = []
var target_slot: int = -1
var party: Array = []  # 本地副本

# ---- 更新后的节点路径 ----
@onready var mode_label = $VBoxContainer/TopBar/ModeLabel
@onready var close_btn = $VBoxContainer/HBoxContainer/CloseBtn
@onready var confirm_btn = $VBoxContainer/HBoxContainer/ConfirmBtn
@onready var unit_container = $VBoxContainer/MainHBox/VBoxContainer/UnitContainer
@onready var library_container = $VBoxContainer/MainHBox/VBoxContainer/LibraryContainer
@onready var relic_container = $VBoxContainer/MainHBox/VBoxContainer/RelicContainer
@onready var discard_zone = $VBoxContainer/MainHBox/DiscardZone

func init(units: Array[String], slot: int, mode: Mode):
	selected_units = units
	target_slot = slot
	current_mode = mode
	party = _create_party_from_units(selected_units)
	_build_ui()

func _create_party_from_units(units: Array[String]) -> Array:
	var copy = []
	for unit_name in units:
		var data = UnitData.new()
		var stats = UnitDataManager.get_default_stats(unit_name)
		var unit_dict = UnitDataManager.get_unit_data(unit_name)
		data.unit_name = unit_name
		data.display_name = unit_dict.get("display_name", unit_name)
		data.faction = unit_dict.get("faction", "")
		data.team_id = 0
		data.max_hp = stats.max_hp
		data.hit_points = stats.max_hp
		data.defense = stats.defense
		data.magic_defense = stats.magic_defense
		data.skill = stats.skill
		data.speed = stats.speed
		data.luck = stats.luck
		data.move_range = stats.move_range
		data.ignore_terrain_cost = stats.ignore_terrain_cost
		var default_weapon = UnitDataManager.get_default_weapon_id(unit_name)
		if default_weapon != "":
			var inst = ItemInstance.new()
			inst.item_id = default_weapon
			inst.count = 1
			data.weapon_slot = inst
		data.armor_slots.clear()
		data.armor_slots.append(null)
		data.armor_slots.append(null)
		data.max_armor_slots = 2
		copy.append(data)
	return copy

func _build_ui():
	mode_label.text = "装备配置 - " + ("出战准备" if current_mode == Mode.DEPLOY else "队伍管理")
	close_btn.text = "返回"
	close_btn.add_theme_font_size_override("font_size", 8)
	confirm_btn.visible = (current_mode == Mode.DEPLOY)
	confirm_btn.text = "出发"
	confirm_btn.add_theme_font_size_override("font_size", 8)

	_clear_containers()
	_build_unit_columns()

	if current_mode == Mode.DEPLOY:
		_build_library()
		library_container.visible = true
		relic_container.visible = false
	else:
		library_container.visible = false
		_build_relics()
		relic_container.visible = true

	discard_zone.visible = true
	call_deferred("_setup_all_drag_forwarding")

func _clear_containers():
	for child in unit_container.get_children():
		child.queue_free()
	for child in library_container.get_children():
		child.queue_free()
	for child in relic_container.get_children():
		child.queue_free()

func _build_unit_columns():
	for i in range(party.size()):
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		var unit = party[i]

		var name_label = Label.new()
		name_label.text = unit.display_name + "(" + unit.unit_name + ")"
		name_label.add_theme_font_size_override("font_size", 6)
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(name_label)

		var weapon_btn = _create_item_button(unit.weapon_slot, "weapon", i, -1)
		col.add_child(weapon_btn)

		for slot_idx in range(unit.armor_slots.size()):
			var armor_btn = _create_item_button(unit.armor_slots[slot_idx], "armor", i, slot_idx)
			if current_mode == Mode.DEPLOY:
				armor_btn.disabled = true
			col.add_child(armor_btn)

		unit_container.add_child(col)

func _create_item_button(inst: ItemInstance, slot_type: String, unit_idx: int, slot_idx: int) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 6)
	btn.text = _get_item_name(inst) if inst else ("空" if slot_type == "armor" else "无")
	btn.set_meta("slot_type", slot_type)
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	btn.set_meta("item_id", inst.item_id if inst else "")
	return btn

func _build_library():
	var title = Label.new()
	title.text = "武器库"
	title.add_theme_font_size_override("font_size", 8)
	library_container.add_child(title)

	var grid = GridContainer.new()
	grid.columns = 3
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "weapon":
			var btn = Button.new()
			btn.text = data.name
			btn.add_theme_font_size_override("font_size", 6)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.set_meta("slot_type", "library_weapon")
			btn.set_meta("item_id", item_id)
			grid.add_child(btn)
	library_container.add_child(grid)

func _build_relics():
	var title = Label.new()
	title.text = "遗物"
	title.add_theme_font_size_override("font_size", 8)
	relic_container.add_child(title)

	var grid = GridContainer.new()
	grid.columns = 3
	var relics = GameState.global_relics.duplicate()
	while relics.size() < 3:
		relics.append(null)
	for i in range(3):
		var relic = relics[i]
		var btn = Button.new()
		if relic:
			var data = RelicManager.get_relic_data(relic.item_id)
			btn.text = data.get("name", "?") if not data.is_empty() else "?"
			btn.set_meta("slot_type", "relic")
			btn.set_meta("relic_index", i)
			btn.set_meta("item_id", relic.item_id)
		else:
			btn.text = "空"
			btn.modulate = Color.GRAY
			btn.disabled = true
		btn.add_theme_font_size_override("font_size", 6)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(btn)
	relic_container.add_child(grid)

func _setup_all_drag_forwarding():
	if not is_inside_tree():
		return
	_set_drag_forwarding_for_children(unit_container)
	_set_drag_forwarding_for_children(library_container)
	_set_drag_forwarding_for_children(relic_container)

func _set_drag_forwarding_for_children(parent: Node):
	if not parent:
		return
	for child in parent.get_children():
		if child is Button:
			child.set_drag_forwarding(
				Callable(self, "_get_drag_data"),
				Callable(self, "_can_drop_data"),
				Callable(self, "_drop_data")
			)
		elif child is Container or child is GridContainer or child is HBoxContainer or child is VBoxContainer:
			_set_drag_forwarding_for_children(child)

func _get_item_name(inst: ItemInstance) -> String:
	if not inst:
		return ""
	var data = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id

# ========== 拖拽系统 ==========
func _get_drag_data(_at_position: Vector2) -> Variant:
	var selection = get_viewport().gui.drag_selection
	if selection.is_empty():
		return null
	var from = selection[0]
	if not (from is Button):
		return null
	var meta = {
		"slot_type": from.get_meta("slot_type", ""),
		"unit_idx": from.get_meta("unit_idx", -1),
		"slot_idx": from.get_meta("slot_idx", -1),
		"item_id": from.get_meta("item_id", ""),
		"relic_index": from.get_meta("relic_index", -1),
		"source_control": from
	}
	if meta["item_id"] == "" and meta["slot_type"] != "library_weapon":
		return null

	var preview = Label.new()
	preview.text = from.text
	preview.add_theme_font_size_override("font_size", 8)
	preview.modulate = Color(0.5, 0.5, 0.5, 0.7)
	from.set_drag_preview(preview)
	return meta

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var target = _get_target_from_position(get_viewport().get_mouse_position())
	if target == null:
		return false
	return _is_valid_drop(data, target)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var target = _get_target_from_position(get_viewport().get_mouse_position())
	if target == null:
		return
	if not _is_valid_drop(data, target):
		return
	_execute_drop(data, target)

func _get_target_from_position(global_pos: Vector2) -> Control:
	var discard = discard_zone
	if discard.get_global_rect().has_point(global_pos):
		return discard

	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button and child.get_global_rect().has_point(global_pos):
				return child

	if current_mode == Mode.DEPLOY:
		for grid in library_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button and btn.get_global_rect().has_point(global_pos):
						return btn

	if current_mode == Mode.MAP:
		for grid in relic_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button and btn.get_global_rect().has_point(global_pos):
						return btn

	return null

func _is_valid_drop(data: Dictionary, target: Control) -> bool:
	var source_type = data["slot_type"]
	var target_type = target.get_meta("slot_type", "")
	var discard = target == discard_zone

	if discard:
		if source_type == "library_weapon":
			return false
		return true

	if source_type == "library_weapon":
		return target_type == "weapon"

	if source_type == "weapon" and target_type == "weapon":
		return true
	if source_type == "armor" and target_type == "armor":
		return true
	if source_type == "relic" and target_type == "relic":
		return true

	return false

func _execute_drop(data: Dictionary, target: Control):
	var discard = target == discard_zone
	var source_type = data["slot_type"]
	var target_type = target.get_meta("slot_type", "")

	if discard:
		_discard_item(data)
		return

	if source_type == "library_weapon":
		_library_to_weapon(data, target)
		return

	if source_type == "weapon" and target_type == "weapon":
		_swap_weapons(data, target)
	elif source_type == "armor" and target_type == "armor":
		_swap_armor(data, target)
	elif source_type == "relic" and target_type == "relic":
		_swap_relics(data, target)

# ---------- 操作函数 ----------
func _discard_item(data: Dictionary):
	var source_type = data["slot_type"]
	if source_type == "library_weapon":
		return
	var unit_idx = data["unit_idx"]
	var slot_idx = data["slot_idx"]
	if source_type == "weapon":
		party[unit_idx].weapon_slot = null
	elif source_type == "armor":
		party[unit_idx].armor_slots[slot_idx] = null
	elif source_type == "relic":
		var idx = data["relic_index"]
		if idx < GameState.global_relics.size():
			GameState.global_relics.remove_at(idx)
			_sync_relics()
	_sync_all()
	_build_ui()

func _library_to_weapon(data: Dictionary, target: Control):
	var item_id = data["item_id"]
	var unit_idx = target.get_meta("unit_idx", -1)
	if unit_idx == -1:
		return
	var inst = ItemInstance.new()
	inst.item_id = item_id
	inst.count = 1
	party[unit_idx].weapon_slot = inst
	_sync_all()
	_build_ui()

func _swap_weapons(data: Dictionary, target: Control):
	var src_unit = data["unit_idx"]
	var tgt_unit = target.get_meta("unit_idx", -1)
	if tgt_unit == -1:
		return
	var temp = party[src_unit].weapon_slot
	party[src_unit].weapon_slot = party[tgt_unit].weapon_slot
	party[tgt_unit].weapon_slot = temp
	_sync_all()
	_build_ui()

func _swap_armor(data: Dictionary, target: Control):
	var src_unit = data["unit_idx"]
	var src_slot = data["slot_idx"]
	var tgt_unit = target.get_meta("unit_idx", -1)
	var tgt_slot = target.get_meta("slot_idx", -1)
	if tgt_unit == -1 or tgt_slot == -1:
		return
	var temp = party[src_unit].armor_slots[src_slot]
	party[src_unit].armor_slots[src_slot] = party[tgt_unit].armor_slots[tgt_slot]
	party[tgt_unit].armor_slots[tgt_slot] = temp
	_sync_all()
	_build_ui()

func _swap_relics(data: Dictionary, target: Control):
	var src_idx = data["relic_index"]
	var tgt_idx = target.get_meta("relic_index", -1)
	if tgt_idx == -1:
		return
	var relics = GameState.global_relics
	if src_idx < relics.size() and tgt_idx < relics.size():
		var temp = relics[src_idx]
		relics[src_idx] = relics[tgt_idx]
		relics[tgt_idx] = temp
	_sync_relics()
	_sync_all()
	_build_ui()

# ---------- 数据同步 ----------
func _sync_all():
	for i in range(party.size()):
		if i < GameState.party.size():
			GameState.party[i].weapon_slot = party[i].weapon_slot
			GameState.party[i].armor_slots = party[i].armor_slots.duplicate()
			GameState.party[i].max_armor_slots = party[i].max_armor_slots
	SaveManager.auto_save()

func _sync_relics():
	SaveManager.auto_save()

# ---------- 按钮回调 ----------
func _on_confirm_pressed():
	# 初始化 GameState 队伍
	GameState.initialize_party(selected_units, 0)
	# 应用本地装备
	for i in range(min(party.size(), GameState.party.size())):
		var local_unit = party[i]
		var state_unit = GameState.party[i]
		state_unit.weapon_slot = local_unit.weapon_slot
		state_unit.armor_slots = local_unit.armor_slots.duplicate()
		state_unit.max_armor_slots = local_unit.max_armor_slots
		state_unit.hit_points = local_unit.hit_points
	# 清空遗物（出战前没有遗物操作）
	GameState.global_relics.clear()
	# 设置资源
	GameState.temp_soul = 0
	GameState.temp_gold = 0
	if selected_units.size() > 0:
		var main_data = UnitDataManager.get_unit_data(selected_units[0])
		GameState.current_faction = main_data.get("faction", "王国")
	else:
		GameState.current_faction = "王国"
	GameState.interrupt_state = 2
	GameState.reset_progress()
	# 保存存档
	SaveManager.save_game(target_slot, false)
	# 进入地图
	LevelManager.start_game()
	queue_free()

func _on_close_pressed():
	if current_mode == Mode.MAP:
		_sync_all()
	# 出战前直接关闭面板，不保存，返回 UnitSelectUI（自动显示）
	queue_free()
