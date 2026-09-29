class_name PanelManager
extends Node

var _bf : Node2D
var _is_showing_relics : bool = false
var _detail_popup = null


func _init(bf: Node2D):
	_bf = bf


func init() -> void:
	_detail_popup = load(Config.PATHS.ITEM_DETAIL_POPUP).instantiate()
	_bf.add_child(_detail_popup)
	_detail_popup.visible = false


# ============================================================
#  队伍查看
# ============================================================
func on_team_view_btn_pressed() -> void:
	if _bf.setting_menu_panel.visible:
		_bf.setting_menu_panel.visible = false
	if _bf.item_list_panel.visible:
		_bf.item_list_panel.visible = false
	_bf.team_view_panel.visible = not _bf.team_view_panel.visible
	if _bf.team_view_panel.visible:
		refresh_team_view()


func refresh_team_view() -> void:
	for child in _bf.team_view_container.get_children():
		child.queue_free()

	var units = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			units.append(unit)

	if units.is_empty():
		var label = Label.new()
		label.text = "没有存活的我方单位"
		label.add_theme_font_size_override("font_size", 6)
		_bf.team_view_container.add_child(label)
	else:
		units.sort_custom(func(a, b):
			if a.grid_cell.y != b.grid_cell.y:
				return a.grid_cell.y < b.grid_cell.y
			return a.grid_cell.x < b.grid_cell.x
		)

		for unit in units:
			var btn = Button.new()
			var icon_texture: Texture2D = null
			if unit.animated_sprite and unit.animated_sprite.sprite_frames:
				var frames = unit.animated_sprite.sprite_frames
				var anim = unit.current_anim if unit.current_anim else "idle"
				if frames.has_animation(anim):
					icon_texture = frames.get_frame_texture(anim, 0)
				elif frames.has_animation("idle"):
					icon_texture = frames.get_frame_texture("idle", 0)
			if icon_texture:
				var image = icon_texture.get_image()
				image.resize(16, 16, Image.INTERPOLATE_NEAREST)
				btn.icon = ImageTexture.create_from_image(image)
				btn.add_theme_constant_override("hseparation", 4)

			var status = ""
			var color = Color.WHITE
			if unit.has_attacked:
				status = "   已攻击"
				color = Color(0.7, 0.4, 0.2, 1.0)
			elif not unit.can_act_this_turn:
				status = "   已待机"
				color = Color(0.5, 0.5, 0.5)
			else:
				status = "   可行动"

			var full_name = UnitDataManager.get_display_name_from_unit(unit)
			btn.text = full_name + " HP:" + str(unit.hit_points) + "/" + str(unit.unit_stats.max_hp) + status
			var talent_line = format_unit_talents(unit)
			if talent_line != "":
				btn.text += "  [ " + talent_line + " ]"
			btn.add_theme_font_size_override("font_size", 6)
			if color != Color.WHITE:
				btn.add_theme_color_override("font_color", color)
			btn.pressed.connect(on_team_member_selected.bind(unit))
			_bf.team_view_container.add_child(btn)

	var parent = _bf.team_view_container.get_parent()
	var scroll = parent as ScrollContainer
	if not scroll:
		scroll = create_scroll_container(_bf.team_view_container, parent, "TeamViewScroll")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	await get_tree().process_frame
	var content_height = _bf.team_view_container.get_minimum_size().y
	var viewport_height = get_viewport().get_visible_rect().size.y
	var max_height = viewport_height * 0.8
	var panel_height = clamp(content_height + 16, 20, max_height)
	_bf.team_view_panel.size.y = panel_height


func format_unit_talents(unit) -> String:
	var parts: Array = []
	for inst in unit.talent_slots:
		if not inst or not inst.is_active:
			continue
		var data = TalentManager.get_talent_data(inst.talent_id)
		if not data:
			continue
		var status := ""

		if inst.talent_id == "vengeance":
			status = ""
		elif data.is_active_skill:
			if inst.is_ready:
				status = "(就绪★)"
			else:
				status = "(冷%d)" % inst.cooldown_remaining
		elif inst.cooldown_remaining >= 9999:
			status = "(R)"
		elif inst.cooldown_remaining > 0:
			status = "(冷%d)" % inst.cooldown_remaining
		elif inst.is_ready:
			status = "(就绪)"
		else:
			var remain = max(0, data.accumulation_threshold - inst.current_stack)
			status = "(%d)" % remain

		if status == "":
			parts.append(data.display_name)
		else:
			parts.append(data.display_name + status)
	return " ".join(parts)


func on_team_member_selected(unit) -> void:
	_bf.setting_menu_panel.visible = false
	_bf.team_view_panel.visible = false
	SignalBus.request_hide_setting.emit()
	SignalBus.request_hide_info.emit()

	InputManager.selected_unit = unit
	if unit.can_act_this_turn and unit.hit_points > 0:
		InputManager.interaction_phase = InputManager.Phase.MENU
		SignalBus.request_show_menu.emit(unit)
	else:
		InputManager.interaction_phase = InputManager.Phase.IDLE

	SignalBus.request_show_info.emit(unit)
	SoundManager.play_select_sound()
	SignalBus.request_clear_highlight.emit()
	_bf.camera_controller.smooth_move_to(_bf.grid_to_world(unit.grid_cell), 0.3, true)
	InputManager.current_highlight_cells = {}
	InputManager.current_move_attack_targets = {}


# ============================================================
#  道具列表
# ============================================================
func on_item_list_btn_pressed() -> void:
	if _bf.setting_menu_panel.visible:
		_bf.setting_menu_panel.visible = false
	if _bf.team_view_panel.visible:
		_bf.team_view_panel.visible = false
	if _is_showing_relics:
		_bf.item_list_panel.visible = false
		_is_showing_relics = false
		return
	_bf.item_list_panel.visible = not _bf.item_list_panel.visible
	if _bf.item_list_panel.visible:
		refresh_item_list()
		_is_showing_relics = false


func refresh_item_list() -> void:
	_bf.item_list_panel.size = Vector2(120, 20)
	for child in _bf.item_list_container.get_children():
		child.queue_free()

	_bf.item_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bf.item_list_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var parent = _bf.item_list_container.get_parent()
	var scroll = parent as ScrollContainer
	if not scroll:
		scroll = create_scroll_container(_bf.item_list_container, parent, "ItemListScroll")
	scroll.size = _bf.item_list_panel.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var entries = []

	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			var unit_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name

			var weapon = unit.get_weapon()
			if weapon:
				var data = ItemManager.get_item_data(weapon.item_id)
				if data:
					var type_display = ""
					if data.category != "":
						type_display = UnitDataManager.get_weapon_category_display(data.category)
					else:
						type_display = get_type_display_name(data.type)
					entries.append({
						"item_name": data.name,
						"type_display": type_display,
						"source": unit_name,
						"slot": "武器",
						"is_equipped": true,
						"data": data
					})

			var armor_slots = unit.get_armor_slots()
			for i in range(armor_slots.size()):
				var inst = armor_slots[i]
				if inst:
					var data = ItemManager.get_item_data(inst.item_id)
					if data:
						entries.append({
							"item_name": data.name,
							"type_display": "",
							"source": unit_name,
							"slot": "防具槽" + str(i+1),
							"is_equipped": true,
							"data": data
						})

	if entries.is_empty():
		var label = Label.new()
		label.text = "没有装备"
		label.add_theme_font_size_override("font_size", 6)
		_bf.item_list_container.add_child(label)
	else:
		entries.sort_custom(func(a, b):
			if a["source"] != b["source"]:
				return a["source"] < b["source"]
			return a["slot"] < b["slot"]
		)

		for entry in entries:
			var btn = Button.new()
			var data = entry["data"]
			if data.icon:
				btn.icon = data.icon

			var equipped_str = " [已装备]" if entry["is_equipped"] else ""
			var type_str = "[" + entry["type_display"] + "]" if entry["type_display"] != "" else ""
			btn.text = entry["item_name"] + " " + type_str + equipped_str + " (" + entry["source"] + " " + entry["slot"] + ")"
			btn.add_theme_font_size_override("font_size", 6)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.clip_text = true
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			btn.disabled = true

			btn.mouse_entered.connect(on_item_hover_entered.bind(entry["data"].id))
			btn.mouse_exited.connect(on_item_hover_exited)

			_bf.item_list_container.add_child(btn)

	await get_tree().process_frame

	var viewport_size = get_viewport().get_visible_rect().size
	var max_panel_width = viewport_size.x * 0.4
	var min_panel_width = 120
	var content_width = min_panel_width
	for child in _bf.item_list_container.get_children():
		if child is Button:
			var w = child.size.x
			if w > content_width:
				content_width = w
	content_width += 16
	var panel_width = clamp(content_width, min_panel_width, max_panel_width)

	var content_height = _bf.item_list_container.get_minimum_size().y
	var padding = 16
	var max_height = viewport_size.y * 0.9
	var final_height = clamp(content_height + padding, 20, max_height)

	_bf.item_list_panel.size = Vector2(panel_width, final_height)
	scroll.size = _bf.item_list_panel.size
	_bf.item_list_container.size = scroll.size


func on_item_hover_entered(item_id: String) -> void:
	show_item_detail(item_id)


func on_item_hover_exited() -> void:
	hide_item_detail()


func find_unit_by_name(display_name: String):
	for unit in UnitManager.unit_list:
		var unit_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
		if unit_name == display_name:
			return unit
	return null


# ============================================================
#  遗物查看
# ============================================================
func on_relic_view_btn_pressed() -> void:
	if _bf.setting_menu_panel.visible:
		_bf.setting_menu_panel.visible = false
	if _bf.team_view_panel.visible:
		_bf.team_view_panel.visible = false
	if _bf.item_list_panel.visible and _is_showing_relics:
		_bf.item_list_panel.visible = false
		_is_showing_relics = false
		return

	_bf.item_list_panel.visible = true
	refresh_relic_list()
	_is_showing_relics = true


func refresh_relic_list() -> void:
	for child in _bf.item_list_container.get_children():
		child.queue_free()

	var relics = GameState.get_relics_from_passives()
	if relics.is_empty():
		var label = Label.new()
		label.text = "暂无遗物"
		label.add_theme_font_size_override("font_size", 6)
		_bf.item_list_container.add_child(label)
		return

	for relic in relics:
		var data = RelicManager.get_relic_data(relic.item_id)
		if data.is_empty():
			continue
		var btn = Button.new()
		btn.text = data.get("name", "未知遗物")
		var icon_path = data.get("icon", "")
		if icon_path != "" and ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
		btn.add_theme_font_size_override("font_size", 6)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = true

		var item_id = relic.item_id
		btn.mouse_entered.connect(on_relic_hover_entered.bind(item_id))
		btn.mouse_exited.connect(on_relic_hover_exited)

		_bf.item_list_container.add_child(btn)

	await get_tree().process_frame
	var content_height = _bf.item_list_container.get_minimum_size().y
	var viewport_size = get_viewport().get_visible_rect().size
	var max_height = viewport_size.y * 0.9
	var panel_height = clamp(content_height + 16, 20, max_height)
	var panel_width = clamp(120, 80, viewport_size.x * 0.4)
	_bf.item_list_panel.size = Vector2(panel_width, panel_height)

	var parent = _bf.item_list_container.get_parent()
	var scroll = parent as ScrollContainer
	if not scroll:
		scroll = create_scroll_container(_bf.item_list_container, parent, "ItemListScroll")
	scroll.size = _bf.item_list_panel.size


func on_relic_hover_entered(item_id: String) -> void:
	show_item_detail(item_id)


func on_relic_hover_exited() -> void:
	hide_item_detail()


# ============================================================
#  设置菜单开关
# ============================================================
func on_setting_btn_pressed() -> void:
	if _bf.team_view_panel.visible:
		_bf.team_view_panel.visible = false
	if _bf.item_list_panel.visible:
		_bf.item_list_panel.visible = false
	_bf.setting_menu_panel.visible = not _bf.setting_menu_panel.visible


# ============================================================
#  遗物图标 + 精炼使用
# ============================================================
func update_relic_icons() -> void:
	for child in _bf.relic_icon_container.get_children():
		child.queue_free()

	var passives = GameState.get_passives()
	var has_any = false

	for i in range(passives.size()):
		var p = passives[i]
		if p == null:
			continue

		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 6)
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.custom_minimum_size = Vector2(0, 14)

		if p is ItemInstance:
			var data = RelicManager.get_relic_data(p.item_id)
			if data.is_empty():
				continue
			btn.text = "◆ " + data.get("name", "?")
			btn.disabled = true
			btn.tooltip_text = data.get("description", "")
			_bf.relic_icon_container.add_child(btn)
			has_any = true

		elif p is Dictionary and p.has("refine_id"):
			var refine_id : String = p.get("refine_id", "")
			var recipe : Dictionary = RefineManager.get_recipe(refine_id)
			if recipe.is_empty():
				continue
			btn.text = "★ " + recipe.get("name", "?") + " ▶"
			btn.tooltip_text = recipe.get("description", "")
			btn.pressed.connect(on_use_refine.bind(i))
			_bf.relic_icon_container.add_child(btn)
			has_any = true

	if not has_any:
		var label := Label.new()
		label.text = "无遗物/精炼"
		label.add_theme_font_size_override("font_size", 6)
		_bf.relic_icon_container.add_child(label)


func on_use_refine(slot_idx: int) -> void:
	var passives = GameState.get_passives()
	if slot_idx < 0 or slot_idx >= passives.size():
		return
	var p = passives[slot_idx]
	if not (p is Dictionary and p.has("refine_id")):
		return

	var refine_id : String = p.get("refine_id", "")
	var effect : Dictionary = RefineManager.get_effect(refine_id)
	if effect.is_empty():
		return

	var effect_type : String = effect.get("type", "")
	var value : Variant = effect.get("value", 0)

	for unit in UnitManager.unit_list:
		if not is_instance_valid(unit):
			continue
		if unit.unit_stats.team_id != 0:
			continue
		match effect_type:
			"attack_percent":
				unit.buff_attack_percent += value
			"crit_damage_bonus":
				unit.buff_crit_damage_bonus += value
			"defense_flat":
				unit.buff_defense_flat += int(value)
			"damage_reduction":
				unit.buff_damage_reduction += value
			"heal_full":
				unit.hit_points = unit.unit_stats.max_hp
				unit.update_hp_label()

	GameState.set_passive_at_slot(slot_idx, null)
	update_relic_icons()
	SoundManager.play_heal_sound()
	print("[Battlefield] 使用精炼：", refine_id, " 类型：", effect_type)


# ============================================================
#  详情弹窗
# ============================================================
func show_item_detail(item_id: String) -> void:
	if _detail_popup:
		_detail_popup.show_item(item_id)
		_detail_popup.visible = true


func hide_item_detail() -> void:
	if _detail_popup:
		_detail_popup.visible = false


# ============================================================
#  辅助
# ============================================================
func get_type_display_name(type: String) -> String:
	match type:
		"weapon": return "武器"
		"armor": return "防具"
		"relic": return "遗物"
		_:
			return type


func create_scroll_container(child: Control, parent: Node, container_name: String) -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.name = container_name
	scroll.anchors_preset = Control.PRESET_FULL_RECT
	scroll.offset_left = 0
	scroll.offset_top = 0
	scroll.offset_right = 0
	scroll.offset_bottom = 0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var idx = parent.get_index()
	parent.add_child(scroll)
	parent.move_child(scroll, idx)
	parent.remove_child(child)
	scroll.add_child(child)

	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_vertical = Control.SIZE_EXPAND_FILL

	return scroll
