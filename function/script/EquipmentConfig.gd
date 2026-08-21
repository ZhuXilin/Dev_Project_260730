extends Panel

enum Mode { DEPLOY, MAP }

var current_mode: Mode = Mode.DEPLOY
var selected_units: Array[String] = []
var target_slot: int = -1
var party: Array = []

# ---- 手动拖拽状态 ----
var _is_dragging: bool = false
var _drag_source: Button = null
var _drag_meta: Dictionary = {}
var _drag_preview: Control = null
var _drag_grab_offset: Vector2 = Vector2.ZERO
var _target_states: Dictionary = {}
var _detail_popup = null   # 详情弹窗

@onready var mode_label = $VBoxContainer/TopBar/ModeLabel
@onready var close_btn = $VBoxContainer/HBoxContainer/CloseBtn
@onready var confirm_btn = $VBoxContainer/HBoxContainer/ConfirmBtn
@onready var unit_container = $VBoxContainer/MainHBox/VBoxContainer/UnitContainer
@onready var library_container = $VBoxContainer/MainHBox/VBoxContainer/LibraryContainer
@onready var relic_container = $VBoxContainer/MainHBox/VBoxContainer/RelicContainer
@onready var discard_zone = $VBoxContainer/MainHBox/DiscardZone

func init(units: Array[String], slot: int, mode: Mode):
	print("EquipmentConfig.init 被调用")
	var canvas_layer = get_parent()
	if canvas_layer is CanvasLayer:
		canvas_layer.layer = 20
		print("CanvasLayer layer 设置为 20")
	selected_units = units
	target_slot = slot
	current_mode = mode
	# ---- 从 GameState.party 复制现有装备数据，而不是创建默认 ----
	party.clear()
	for unit_name in units:
		# 在 GameState.party 中查找同名单位
		var existing = null
		for u in GameState.party:
			if u.unit_name == unit_name:
				existing = u
				break
		if existing:
			# 复制现有 UnitData
			var data = UnitData.new()
			data.unit_name = existing.unit_name
			data.display_name = existing.display_name
			data.faction = existing.faction
			data.team_id = existing.team_id
			data.max_hp = existing.max_hp
			data.hit_points = existing.hit_points
			data.defense = existing.defense
			data.magic_defense = existing.magic_defense
			data.skill = existing.skill
			data.speed = existing.speed
			data.luck = existing.luck
			data.move_range = existing.move_range
			data.ignore_terrain_cost = existing.ignore_terrain_cost
			data.experience = existing.experience
			data.level = existing.level
			# 复制装备
			if existing.weapon_slot:
				var inst = ItemInstance.new()
				inst.item_id = existing.weapon_slot.item_id
				inst.count = existing.weapon_slot.count
				data.weapon_slot = inst
			else:
				data.weapon_slot = null
			data.armor_slots.clear()
			for slot_inst in existing.armor_slots:
				if slot_inst:
					var new_inst = ItemInstance.new()
					new_inst.item_id = slot_inst.item_id
					new_inst.count = slot_inst.count
					data.armor_slots.append(new_inst)
				else:
					data.armor_slots.append(null)
			data.max_armor_slots = existing.max_armor_slots
			party.append(data)
		else:
			# 如果不存在，使用默认创建（向后兼容）
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
			data.armor_slots = [null, null]
			data.max_armor_slots = 2
			party.append(data)
	_build_ui()

	# ---- 创建详情弹窗（隐藏） ----
	if not _detail_popup:
		_detail_popup = load("res://content/scenes/ui/ItemDetailPopup.tscn").instantiate()
		var canvas = get_parent()
		if canvas and canvas is CanvasLayer:
			canvas.add_child(_detail_popup)
			_detail_popup.layer = 30   # 确保在拖拽预览之上
		else:
			add_child(_detail_popup)
		_detail_popup.visible = false

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
	print("_build_ui 被调用")
	if not mode_label:
		print("错误：mode_label 为 null")
		return
	
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
	else:
		library_container.visible = false
	
	# 遗物始终显示，允许编辑
	_build_relics()
	relic_container.visible = true
	
	discard_zone.visible = (current_mode == Mode.MAP)
	visible = true
	print("_build_ui 完成，面板可见：", visible)

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
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# ---- 悬停显示详情 ----
	if inst and inst.item_id != "":
		var item_id = inst.item_id
		btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_button_hover_exited)
	
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
			btn.focus_mode = Control.FOCUS_NONE
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			
			# ---- 悬停显示详情 ----
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
			btn.mouse_exited.connect(_on_button_hover_exited)
			
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
			# ---- 悬停显示详情 ----
			btn.mouse_entered.connect(_on_button_hover_entered.bind(relic.item_id))
			btn.mouse_exited.connect(_on_button_hover_exited)
		else:
			btn.text = "空"
			btn.modulate = Color.GRAY
			btn.disabled = true
		btn.add_theme_font_size_override("font_size", 6)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(btn)
	relic_container.add_child(grid)

func _get_item_name(inst: ItemInstance) -> String:
	if not inst:
		return ""
	var data = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id

# ========== 辅助检测 ==========
func _find_control_at_position(pos: Vector2) -> Control:
	const BUFFER = 4
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				if current_mode == Mode.DEPLOY and child.get_meta("slot_type", "") == "armor":
					continue
				var rect = child.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return child
	
	if current_mode == Mode.DEPLOY:
		for grid in library_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button:
						var rect = btn.get_global_rect().grow(BUFFER)
						if rect.has_point(pos):
							return btn
	
	if current_mode == Mode.MAP:
		for grid in relic_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button:
						var rect = btn.get_global_rect().grow(BUFFER)
						if rect.has_point(pos):
							return btn
	
	return null

func _get_target_from_position(global_pos: Vector2) -> Control:
	if discard_zone.visible and discard_zone.get_global_rect().has_point(global_pos):
		return discard_zone

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

	if current_mode == Mode.DEPLOY:
		if discard:
			return false
		if source_type == "library_weapon":
			return target_type == "weapon"
		if source_type == "weapon" and target_type == "weapon":
			return true
		return false

	if discard:
		if source_type == "weapon":
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

func _discard_item(data: Dictionary):
	var source_type = data["slot_type"]
	if source_type == "library_weapon" or source_type == "weapon":
		return
	var unit_idx = data["unit_idx"]
	var slot_idx = data["slot_idx"]
	if source_type == "armor":
		party[unit_idx].armor_slots[slot_idx] = null
	elif source_type == "relic":
		var idx = data["relic_index"]
		if idx < GameState.global_relics.size():
			GameState.global_relics.remove_at(idx)
			_sync_relics()
	_sync_all()
	call_deferred("_build_ui")

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
	call_deferred("_build_ui")

func _swap_weapons(data: Dictionary, target: Control):
	var src_unit = data["unit_idx"]
	var tgt_unit = target.get_meta("unit_idx", -1)
	if tgt_unit == -1:
		return
	var temp = party[src_unit].weapon_slot
	party[src_unit].weapon_slot = party[tgt_unit].weapon_slot
	party[tgt_unit].weapon_slot = temp
	_sync_all()
	call_deferred("_build_ui")

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
	call_deferred("_build_ui")

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
	call_deferred("_build_ui")

func _sync_all():
	for i in range(party.size()):
		if i < GameState.party.size():
			GameState.party[i].weapon_slot = party[i].weapon_slot
			GameState.party[i].armor_slots = party[i].armor_slots.duplicate()
			GameState.party[i].max_armor_slots = party[i].max_armor_slots
	SaveManager.auto_save()

func _sync_relics():
	SaveManager.auto_save()

# ========== 手动拖拽（按下即拖拽，无延迟） ==========
func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		var btn = _find_control_at_position(mouse_pos)
		if btn:
			_start_drag(btn)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_end_drag()
	elif event is InputEventMouseMotion:
		if _is_dragging:
			_update_drag_preview()
		else:
			# 如果鼠标移动过且拖拽尚未开始，允许拖拽（但此时没有按下）
			pass

func _start_drag(btn: Button):
	var slot_type = btn.get_meta("slot_type", "")
	if current_mode == Mode.DEPLOY and (slot_type == "armor" or slot_type == "relic"):
		return
	var item_id = btn.get_meta("item_id", "")
	if item_id == "" and slot_type != "library_weapon":
		return
	
	_drag_source = btn
	_drag_meta = {
		"slot_type": slot_type,
		"unit_idx": btn.get_meta("unit_idx", -1),
		"slot_idx": btn.get_meta("slot_idx", -1),
		"item_id": item_id,
		"relic_index": btn.get_meta("relic_index", -1),
		"source_control": btn
	}
	
	# ---- 计算鼠标相对于按钮中心的偏移 ----
	var btn_rect = btn.get_global_rect()
	var btn_center = btn_rect.position + btn_rect.size / 2
	_drag_grab_offset = get_global_mouse_position() - btn_center
	
	_begin_dragging()

func _begin_dragging():
	if _is_dragging:
		return
	_is_dragging = true
	var btn = _drag_source
	var source_size = btn.size
	var preview = Label.new()
	preview.text = btn.text
	preview.add_theme_font_size_override("font_size", 8)
	preview.modulate = Color(0.8, 0.8, 0.8, 0.9)
	preview.add_theme_color_override("font_color", btn.get_theme_color("font_color"))
	preview.add_theme_stylebox_override("normal", StyleBoxFlat.new())
	var style = preview.get_theme_stylebox("normal") as StyleBoxFlat
	if style:
		style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.5, 0.5, 0.5, 0.8)
	preview.size = source_size
	preview.horizontal_alignment = btn.alignment
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var canvas = get_parent()
	if canvas and canvas is CanvasLayer:
		canvas.add_child(preview)
	else:
		add_child(preview)
	_drag_preview = preview
	_update_drag_preview()
	
	# ---- 新增：更新所有目标控件的视觉效果 ----
	_update_targets_visuals()

func _update_drag_preview():
	if not _drag_preview:
		return
	var mouse_pos = get_global_mouse_position()
	# 预览中心 = 鼠标位置 - 抓取偏移
	var preview_center = mouse_pos - _drag_grab_offset
	_drag_preview.position = preview_center - _drag_preview.size / 2
	_drag_preview.z_index = 100

func _end_drag():
	if _is_dragging:
		var mouse_pos = get_global_mouse_position()
		var target = _get_target_from_position(mouse_pos)
		
		if target and _is_valid_drop(_drag_meta, target):
			_execute_drop(_drag_meta, target)
			SoundManager.play_select_sound()   # 成功 → 点击音效
		else:
			SoundManager.play_cancel_sound()   # 失败 → 取消音效
			
		if _drag_preview:
			_drag_preview.queue_free()
			_drag_preview = null
		_is_dragging = false
		_reset_targets_visuals()
		
	_drag_source = null
	_drag_meta = {}

func _process(_delta):
	if _is_dragging:
		_update_drag_preview()

# ========== 按钮回调 ==========
func _on_close_pressed():
	print("_on_close_pressed 被调用")
	if current_mode == Mode.MAP:
		_sync_all()
	var canvas_layer = get_parent()
	if canvas_layer:
		canvas_layer.queue_free()
	else:
		queue_free()

func _on_confirm_pressed():
	print("_on_confirm_pressed 被调用")
	
	# ---- 调试打印 ----
	print("=== 当前 party 装备状态 ===")
	for i in range(party.size()):
		var u = party[i]
		var weapon_id = u.weapon_slot.item_id if u.weapon_slot else "无"
		print("单位 ", i, ": ", u.unit_name, " 武器: ", weapon_id)
		for j in range(u.armor_slots.size()):
			var slot = u.armor_slots[j]
			var slot_id = slot.item_id if slot else "空"
			print("  防具槽", j, ": ", slot_id)
	print("============================")
	
	# ---- 直接用本地 party 数据覆盖 GameState.party ----
	GameState.party.clear()
	for local_unit in party:
		var data = UnitData.new()
		data.unit_name = local_unit.unit_name
		data.display_name = local_unit.display_name
		data.faction = local_unit.faction
		data.team_id = 0
		data.max_hp = local_unit.max_hp
		data.hit_points = local_unit.hit_points
		data.defense = local_unit.defense
		data.magic_defense = local_unit.magic_defense
		data.skill = local_unit.skill
		data.speed = local_unit.speed
		data.luck = local_unit.luck
		data.move_range = local_unit.move_range
		data.ignore_terrain_cost = local_unit.ignore_terrain_cost
		data.experience = local_unit.experience
		data.level = local_unit.level
		
		# 复制装备
		if local_unit.weapon_slot:
			var inst = ItemInstance.new()
			inst.item_id = local_unit.weapon_slot.item_id
			inst.count = local_unit.weapon_slot.count
			data.weapon_slot = inst
		else:
			data.weapon_slot = null
		data.armor_slots.clear()
		for slot_inst in local_unit.armor_slots:
			if slot_inst:
				var inst = ItemInstance.new()
				inst.item_id = slot_inst.item_id
				inst.count = slot_inst.count
				data.armor_slots.append(inst)
			else:
				data.armor_slots.append(null)
		data.max_armor_slots = local_unit.max_armor_slots
		
		GameState.party.append(data)
	
	# ---- 遗物数据已经在 GameState.global_relics 中，不需要清除 ----
	# 注意：不要调用 GameState.global_relics.clear()
	
	# ---- 其他状态 ----
	GameState.temp_soul = 0
	GameState.temp_gold = 0
	
	if selected_units.size() > 0:
		var main_data = UnitDataManager.get_unit_data(selected_units[0])
		GameState.current_faction = main_data.get("faction", "王国")
	else:
		GameState.current_faction = "王国"
	
	GameState.interrupt_state = 2
	GameState.reset_progress()
	SaveManager.save_game(target_slot, false)
	LevelManager.start_game()
	
	var canvas_layer = get_parent()
	if canvas_layer:
		canvas_layer.queue_free()
	else:
		queue_free()

func _get_all_target_controls() -> Array[Control]:
	var targets: Array[Control] = []
	
	# 1. 单位槽位（武器槽 + 防具槽）
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				targets.append(child)
	
	# 2. 武器库（DEPLOY 模式下可见）
	if current_mode == Mode.DEPLOY and library_container.visible:
		for grid in library_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button:
						targets.append(btn)
	
	# 3. 遗物槽（仅在 MAP 模式下可见）
	if current_mode == Mode.MAP and relic_container.visible:
		for grid in relic_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button and not btn.disabled:
						targets.append(btn)
	
	# 4. 丢弃区（仅在 MAP 模式下可见）
	if current_mode == Mode.MAP and discard_zone.visible:
		targets.append(discard_zone)
	
	return targets

func _update_targets_visuals():
	var targets = _get_all_target_controls()
	_target_states.clear()
	
	for target in targets:
		# 保存原始 modulate（如果未保存过）
		if not _target_states.has(target):
			_target_states[target] = target.modulate
		
		var is_valid = _is_valid_drop(_drag_meta, target)
		if is_valid:
			target.modulate = Color.WHITE
		else:
			target.modulate = Color(0.4, 0.4, 0.4, 1.0)   # 灰色

func _reset_targets_visuals():
	for target in _target_states.keys():
		if is_instance_valid(target):
			target.modulate = _target_states[target]
	_target_states.clear()

func show_item_detail(item_id: String):
	if _detail_popup:
		_detail_popup.show_item(item_id)
		_detail_popup.visible = true

func hide_item_detail():
	if _detail_popup:
		_detail_popup.visible = false

func _on_button_hover_entered(item_id: String):
	show_item_detail(item_id)

func _on_button_hover_exited():
	hide_item_detail()
