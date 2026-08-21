extends Panel

enum Mode { DEPLOY, MAP, REWARD }

signal reward_confirmed   # 结算确认信号

var current_mode: Mode = Mode.DEPLOY
var selected_units: Array[String] = []
var target_slot: int = -1
var party: Array = []

# ---- 奖励相关变量（仅 REWARD 模式使用） ----
var reward_items: Array = []      # 奖励物品列表（ItemData）
var reward_gold: int = 0
var reward_soul: int = 0
var _reward_processed: bool = false

# ---- 手动拖拽状态 ----
var _is_dragging: bool = false
var _drag_source: Button = null
var _drag_meta: Dictionary = {}
var _drag_preview: Control = null
var _drag_grab_offset: Vector2 = Vector2.ZERO

# ---- 目标控件高亮 ----
var _target_states: Dictionary = {}   # 存储目标控件的原始颜色

# ---- 详情弹窗 ----
var _detail_popup = null

@onready var mode_label = $VBoxContainer/TopBar/ModeLabel
@onready var reward_resource_label = $VBoxContainer/RewardResourceBar/RewardResourceLabel
@onready var reward_item_bar = $VBoxContainer/RewardItemBar
@onready var close_btn = $VBoxContainer/HBoxContainer/CloseBtn
@onready var confirm_btn = $VBoxContainer/HBoxContainer/ConfirmBtn
@onready var unit_container = $VBoxContainer/MainHBox/VBoxContainer/UnitContainer
@onready var library_container = $VBoxContainer/MainHBox/VBoxContainer/LibraryContainer
@onready var relic_container = $VBoxContainer/MainHBox/VBoxContainer/RelicContainer
@onready var discard_zone = $VBoxContainer/MainHBox/DiscardZone


# ============================================================
#  初始化
# ============================================================

func init(units: Array[String], slot: int, mode: Mode):
	print("EquipmentConfig.init 被调用")
	var canvas_layer = get_parent()
	if canvas_layer is CanvasLayer:
		canvas_layer.layer = 20
		print("CanvasLayer layer 设置为 20")
	
	selected_units = units
	target_slot = slot
	current_mode = mode
	
	# 如果是 REWARD 模式，初始化奖励相关变量（奖励数据由 init_reward 设置）
	if mode == Mode.REWARD:
		reward_items = []
		reward_gold = 0
		reward_soul = 0
		_reward_processed = false
	
	# ---- 复制队伍数据 ----
	_copy_party_data()
	
	# ---- 创建详情弹窗（隐藏） ----
	if not _detail_popup:
		_detail_popup = load("res://content/scenes/ui/ItemDetailPopup.tscn").instantiate()
		var canvas = get_parent()
		if canvas and canvas is CanvasLayer:
			canvas.add_child(_detail_popup)
			_detail_popup.layer = 30
		else:
			add_child(_detail_popup)
		_detail_popup.visible = false
	
	_build_ui()


func init_reward(items: Array, gold: int, soul: int, slot: int):
	print("EquipmentConfig.init_reward 被调用")
	current_mode = Mode.REWARD
	target_slot = slot
	reward_items = items
	reward_gold = gold
	reward_soul = soul
	_reward_processed = false
	
	# 确保 selected_units 已有值（由 init 先调用）
	if selected_units.is_empty():
		# 从 GameState.party 获取单位名称
		for unit_data in GameState.party:
			selected_units.append(unit_data.unit_name)
	
	_copy_party_data()
	_build_ui()


func _copy_party_data():
	party.clear()
	for unit_name in selected_units:
		var existing = null
		for u in GameState.party:
			if u.unit_name == unit_name:
				existing = u
				break
		
		if existing:
			# 深度复制现有 UnitData
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
			
			# 复制武器
			if existing.weapon_slot:
				var inst = ItemInstance.new()
				inst.item_id = existing.weapon_slot.item_id
				inst.count = existing.weapon_slot.count
				data.weapon_slot = inst
			else:
				data.weapon_slot = null
			
			# 复制防具槽
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
			# 使用工厂方法创建默认数据
			var data = UnitDataManager.create_unit_data(unit_name)
			party.append(data)


func _create_party_from_units(units: Array[String]) -> Array:
	var copy = []
	for unit_name in units:
		var data = UnitDataManager.create_unit_data(unit_name)
		copy.append(data)
	return copy


# ============================================================
#  UI 构建
# ============================================================

func _build_ui():
	print("_build_ui 被调用")
	if not mode_label:
		print("错误：mode_label 为 null")
		return
	
	# ---- 默认隐藏所有动态容器 ----
	reward_item_bar.visible = false
	reward_resource_label.text = ""
	library_container.visible = false
	relic_container.visible = false
	discard_zone.visible = false
	
	match current_mode:
		Mode.DEPLOY:
			mode_label.text = "装备配置 - 出战准备"
			close_btn.text = "返回"
			confirm_btn.visible = true
			confirm_btn.text = "出发"
			library_container.visible = true
			discard_zone.visible = false
			reward_item_bar.visible = false
		
		Mode.MAP:
			mode_label.text = "装备配置 - 队伍管理"
			close_btn.text = "返回"
			confirm_btn.visible = false
			library_container.visible = false
			relic_container.visible = true
			discard_zone.visible = true
			reward_item_bar.visible = false
		
		Mode.REWARD:
			mode_label.text = "关卡结算 - 获得奖励"
			close_btn.text = "返回"
			confirm_btn.visible = true
			confirm_btn.text = "确认"
			discard_zone.visible = true
			reward_item_bar.visible = true
			_show_reward_info()
	
	close_btn.add_theme_font_size_override("font_size", 8)
	confirm_btn.add_theme_font_size_override("font_size", 8)
	
	_clear_containers()
	_build_unit_columns()
	
	# DEPLOY 模式：显示武器库
	if current_mode == Mode.DEPLOY:
		_build_library()
	# REWARD 模式：显示奖励物品在 RewardItemBar 中
	elif current_mode == Mode.REWARD:
		_build_reward_items_in_bar()
	
	# MAP 模式：显示遗物在 RelicContainer 中
	if current_mode == Mode.MAP:
		_build_relics()
	
	visible = true
	print("_build_ui 完成，面板可见：", visible)


func _clear_containers():
	for child in unit_container.get_children():
		child.queue_free()
	for child in library_container.get_children():
		child.queue_free()
	for child in relic_container.get_children():
		child.queue_free()
	# RewardItemBar 在 _build_reward_items_in_bar 中手动清空


func _show_reward_info():
	reward_resource_label.text = "金币 +%d    魂 +%d" % [reward_gold, reward_soul]


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
			
			# REWARD 模式下遗物只读，不可操作
			if current_mode == Mode.REWARD:
				btn.disabled = true
				btn.modulate = Color(0.5, 0.5, 0.5)
			else:
				# 悬停显示详情
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


func _build_reward_items_in_bar():
	# 清空 RewardItemBar
	for child in reward_item_bar.get_children():
		child.queue_free()
	
	# 分离武器/防具和遗物
	var equipment_items = []
	var relic_items = []
	for item_data in reward_items:
		if item_data.type == "relic":
			relic_items.append(item_data)
		elif item_data.type in ["weapon", "armor"]:
			equipment_items.append(item_data)
	
	# ---- 显示武器/防具 ----
	if equipment_items.size() > 0:
		var equip_label = Label.new()
		equip_label.text = "获得装备（可拖拽到单位槽位或丢弃区）"
		equip_label.add_theme_font_size_override("font_size", 6)
		reward_item_bar.add_child(equip_label)
		
		var grid = GridContainer.new()
		grid.columns = min(equipment_items.size(), 4)
		for item_data in equipment_items:
			var btn = Button.new()
			btn.text = item_data.name
			btn.add_theme_font_size_override("font_size", 6)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.set_meta("slot_type", "reward_item")
			btn.set_meta("item_id", item_data.id)
			btn.set_meta("item_data", item_data)
			btn.focus_mode = Control.FOCUS_NONE
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_data.id))
			btn.mouse_exited.connect(_on_button_hover_exited)
			grid.add_child(btn)
		reward_item_bar.add_child(grid)
	
	# ---- 显示遗物（只读） ----
	if relic_items.size() > 0:
		var relic_label = Label.new()
		relic_label.text = "获得遗物（自动生效，不可操作）"
		relic_label.add_theme_font_size_override("font_size", 6)
		reward_item_bar.add_child(relic_label)
		
		var grid = GridContainer.new()
		grid.columns = min(relic_items.size(), 4)
		for item_data in relic_items:
			var btn = Button.new()
			btn.text = item_data.name
			btn.add_theme_font_size_override("font_size", 6)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
			btn.focus_mode = Control.FOCUS_NONE
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_data.id))
			btn.mouse_exited.connect(_on_button_hover_exited)
			grid.add_child(btn)
		reward_item_bar.add_child(grid)
	
	# 如果没有奖励物品
	if equipment_items.is_empty() and relic_items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "本次没有获得任何物品"
		empty_label.add_theme_font_size_override("font_size", 8)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward_item_bar.add_child(empty_label)


func _get_item_name(inst: ItemInstance) -> String:
	if not inst:
		return ""
	var data = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id


# ============================================================
#  详情弹窗（悬停显示）
# ============================================================

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


# ============================================================
#  目标控件高亮（拖拽时变灰）
# ============================================================

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
	
	# 3. 奖励物品（REWARD 模式下）
	if current_mode == Mode.REWARD and reward_item_bar.visible:
		for child in reward_item_bar.get_children():
			if child is GridContainer:
				for btn in child.get_children():
					if btn is Button and not btn.disabled:
						targets.append(btn)
			elif child is Button and not child.disabled:
				targets.append(child)
	
	# 4. 遗物槽（MAP 模式下）
	if current_mode == Mode.MAP and relic_container.visible:
		for grid in relic_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button and not btn.disabled:
						targets.append(btn)
	
	# 5. 丢弃区（MAP 或 REWARD 模式下）
	if (current_mode == Mode.MAP or current_mode == Mode.REWARD) and discard_zone.visible:
		targets.append(discard_zone)
	
	return targets


func _update_targets_visuals():
	var targets = _get_all_target_controls()
	_target_states.clear()
	
	for target in targets:
		if not _target_states.has(target):
			_target_states[target] = target.modulate
		
		var is_valid = _is_valid_drop(_drag_meta, target)
		if is_valid:
			target.modulate = Color.WHITE
		else:
			target.modulate = Color(0.4, 0.4, 0.4, 1.0)


func _reset_targets_visuals():
	for target in _target_states.keys():
		if is_instance_valid(target):
			target.modulate = _target_states[target]
	_target_states.clear()


# ============================================================
#  拖拽检测
# ============================================================

func _find_control_at_position(pos: Vector2) -> Control:
	const BUFFER = 4
	
	# 单位槽位
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				if current_mode == Mode.DEPLOY and child.get_meta("slot_type", "") == "armor":
					continue
				var rect = child.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return child
	
	# 武器库（DEPLOY 模式）
	if current_mode == Mode.DEPLOY:
		for grid in library_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button:
						var rect = btn.get_global_rect().grow(BUFFER)
						if rect.has_point(pos):
							return btn
	
	# 奖励物品（REWARD 模式）
	if current_mode == Mode.REWARD and reward_item_bar.visible:
		for child in reward_item_bar.get_children():
			if child is GridContainer:
				for btn in child.get_children():
					if btn is Button and not btn.disabled:
						var rect = btn.get_global_rect().grow(BUFFER)
						if rect.has_point(pos):
							return btn
			elif child is Button and not child.disabled:
				var rect = child.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return child
	
	# 遗物槽（MAP 模式）
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

	# 单位槽位
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button and child.get_global_rect().has_point(global_pos):
				return child

	# 武器库（DEPLOY 模式）
	if current_mode == Mode.DEPLOY:
		for grid in library_container.get_children():
			if grid is GridContainer:
				for btn in grid.get_children():
					if btn is Button and btn.get_global_rect().has_point(global_pos):
						return btn

	# 奖励物品（REWARD 模式）
	if current_mode == Mode.REWARD and reward_item_bar.visible:
		for child in reward_item_bar.get_children():
			if child is GridContainer:
				for btn in child.get_children():
					if btn is Button and btn.get_global_rect().has_point(global_pos):
						return btn
			elif child is Button and child.get_global_rect().has_point(global_pos):
				return child

	# 遗物槽（MAP 模式）
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
		if source_type == "reward_item":
			return true   # 奖励物品可以丢弃
		return true

	# ---- 奖励物品拖拽 ----
	if source_type == "reward_item":
		var item_data = data.get("item_data")
		if item_data:
			if item_data.equipment_slot == "weapon":
				return target_type == "weapon"
			elif item_data.equipment_slot == "armor":
				return target_type == "armor"
		return false

	if source_type == "library_weapon":
		return target_type == "weapon"
	if source_type == "weapon" and target_type == "weapon":
		return true
	if source_type == "armor" and target_type == "armor":
		return true
	if source_type == "relic" and target_type == "relic":
		return true

	return false


# ============================================================
#  拖拽执行
# ============================================================

func _execute_drop(data: Dictionary, target: Control):
	var discard = target == discard_zone
	var source_type = data["slot_type"]
	var target_type = target.get_meta("slot_type", "")

	if discard:
		_discard_item(data)
		return

	if source_type == "reward_item":
		_reward_to_unit(data, target)
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
	
	# ---- 奖励物品丢弃 ----
	if source_type == "reward_item":
		var item_id = data["item_id"]
		for i in range(reward_items.size()):
			if reward_items[i].id == item_id:
				reward_items.remove_at(i)
				break
		_sync_all()
		call_deferred("_build_ui")
		return
	
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


func _reward_to_unit(data: Dictionary, target: Control):
	var item_data = data.get("item_data")
	if not item_data:
		return
	var unit_idx = target.get_meta("unit_idx", -1)
	if unit_idx == -1:
		return
	
	var inst = ItemInstance.new()
	inst.item_id = item_data.id
	inst.count = 1
	
	if item_data.equipment_slot == "weapon":
		party[unit_idx].weapon_slot = inst
	elif item_data.equipment_slot == "armor":
		var equipped = false
		for i in range(party[unit_idx].armor_slots.size()):
			if party[unit_idx].armor_slots[i] == null:
				party[unit_idx].armor_slots[i] = inst
				equipped = true
				break
		if not equipped:
			# 没有空槽，替换最后一个
			party[unit_idx].armor_slots[party[unit_idx].armor_slots.size() - 1] = inst
	
	# 从奖励列表中移除已装备的物品
	for i in range(reward_items.size()):
		if reward_items[i].id == item_data.id:
			reward_items.remove_at(i)
			break
	
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


# ============================================================
#  同步保存
# ============================================================

func _sync_all():
	for i in range(party.size()):
		if i < GameState.party.size():
			GameState.party[i].weapon_slot = party[i].weapon_slot
			GameState.party[i].armor_slots = party[i].armor_slots.duplicate()
			GameState.party[i].max_armor_slots = party[i].max_armor_slots
	SaveManager.auto_save()


func _sync_relics():
	SaveManager.auto_save()


# ============================================================
#  手动拖拽（按下即拖拽，无延迟）
# ============================================================

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


func _start_drag(btn: Button):
	var slot_type = btn.get_meta("slot_type", "")
	
	# DEPLOY 模式下防具和遗物不可拖拽
	if current_mode == Mode.DEPLOY and (slot_type == "armor" or slot_type == "relic"):
		return
	
	# 武器库的武器可以拖拽
	var item_id = btn.get_meta("item_id", "")
	if item_id == "" and slot_type != "library_weapon" and slot_type != "reward_item":
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
	
	# 如果是奖励物品，额外保存 item_data
	if slot_type == "reward_item":
		_drag_meta["item_data"] = btn.get_meta("item_data", null)
	
	# 计算鼠标相对于按钮中心的偏移
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
	
	# 更新目标控件视觉效果
	_update_targets_visuals()


func _update_drag_preview():
	if not _drag_preview:
		return
	var mouse_pos = get_global_mouse_position()
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


# ============================================================
#  按钮回调
# ============================================================

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
	
	# ---- REWARD 模式 ----
	if current_mode == Mode.REWARD:
		_sync_all()
		reward_confirmed.emit()
		queue_free()
		return
	
	# ---- DEPLOY 模式 ----
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
	
	# 遗物数据已经在 GameState.global_relics 中，不需要清除
	
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
