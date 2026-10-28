class_name PanelManager
extends Node

var _bf : Node2D
var _unit_icon_cache : Dictionary = {}

func _init(bf: Node2D):
	_bf = bf

func init() -> void:
	pass

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
			if inst.is_ready: status = "(就绪★)"
			else: status = "(冷%d)" % inst.cooldown_remaining
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
	# 强制清理 UI 状态，防止动画冲突
	_bf.setting_menu_panel.visible = false
	_bf.team_view_panel.visible = false
	PanelRevealer.force_hide(_bf.team_view_panel)
	PanelRevealer.force_hide(_bf.setting_menu_panel)
	PanelRevealer.force_hide(_bf.info_panel)
	SignalBus.request_hide_setting.emit()
	
	InputManager.selected_unit = unit
	InputManager.interaction_phase = InputManager.Phase.IDLE
	
	SignalBus.request_show_info.emit(unit)
	SoundManager.play_select_sound()
	SignalBus.request_clear_highlight.emit()
	_bf.camera_controller.smooth_move_to(_bf.grid_to_world(unit.grid_cell), 0.3, true)
	InputManager.current_highlight_cells = {}
	InputManager.current_move_attack_targets = {}


# ---- 大设置菜单 ----
func on_setting_btn_pressed() -> void:
	if _bf.team_view_panel.visible:
		PanelRevealer.hide_panel(_bf.team_view_panel)
	
	var is_menu_open = _bf.setting_menu_panel.visible and _bf.setting_menu_panel.mouse_filter == Control.MOUSE_FILTER_STOP
	
	if is_menu_open:
		# ★ 关闭大菜单，恢复竖条栏
		PanelRevealer.hide_panel(_bf.setting_menu_panel)
		PanelRevealer.show_panel(_bf.setting_panel)
		SoundManager.play_cancel_sound()
	else:
		# ★ 打开大菜单，隐藏竖条栏
		PanelRevealer.hide_panel(_bf.setting_panel)
		PanelRevealer.show_panel(_bf.setting_menu_panel)
		SoundManager.play_select_sound()


# ---- 队伍查看 ----
func on_team_view_btn_pressed() -> void:
	SoundManager.play_select_sound()
	
	var is_tv_open = _bf.team_view_panel.visible and _bf.team_view_panel.mouse_filter == Control.MOUSE_FILTER_STOP
	
	if is_tv_open:
		# ★ 关闭队伍面板，恢复竖条栏
		PanelRevealer.hide_panel(_bf.team_view_panel)
		PanelRevealer.show_panel(_bf.setting_panel)
	else:
		# ★ 打开队伍面板，隐藏竖条栏
		PanelRevealer.hide_panel(_bf.setting_panel)
		if _bf.setting_menu_panel.visible:
			PanelRevealer.hide_panel(_bf.setting_menu_panel)
		
		PanelRevealer.force_hide(_bf.team_view_panel)
		refresh_team_view()
		PanelRevealer.show_panel(_bf.team_view_panel)


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
				var cache_key : String = "%s|%s" % [
					unit.unit_stats.unit_name,
					unit.unit_stats.override_sprite_path
				]
				if not _unit_icon_cache.has(cache_key):
					var image = icon_texture.get_image()
					image.resize(16, 16, Image.INTERPOLATE_NEAREST)
					_unit_icon_cache[cache_key] = ImageTexture.create_from_image(image)
				btn.icon = _unit_icon_cache[cache_key]
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


func _on_aura_icon_clicked(aid: String):
	if AuraManager.use_aura_in_battle(aid):
		SignalBus.request_hint_override.emit("★ 光环生效：%s" % AuraManager.get_display_name(aid), 1.5)
		SoundManager.play_get_item_sound()
		update_relic_icons()


# ============ PanelManager.gd ============

func update_relic_icons() -> void:
	for child in _bf.relic_icon_container.get_children():
		child.queue_free()

	var passives = GameState.get_passives()
	var has_any = false

	# ★ 统一使用 20x20 方形图标
	var icon_size = Vector2(20, 20)

	for i in range(passives.size()):
		var p = passives[i]
		if p == null: continue

		var btn := Button.new()
		btn.custom_minimum_size = icon_size
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.focus_mode = Control.FOCUS_NONE
		btn.expand_icon = true
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		# 清除内边距和默认背景，确保纯图标显示，不灰暗
		var empty_sb := StyleBoxEmpty.new()
		empty_sb.content_margin_left = 0
		empty_sb.content_margin_right = 0
		empty_sb.content_margin_top = 0
		empty_sb.content_margin_bottom = 0
		btn.add_theme_stylebox_override("normal", empty_sb)
		btn.add_theme_stylebox_override("hover", empty_sb)
		btn.add_theme_stylebox_override("pressed", empty_sb)
		btn.add_theme_stylebox_override("focus", empty_sb)
		btn.add_theme_stylebox_override("disabled", empty_sb)

		if p is ItemInstance:
			var data = RelicManager.get_relic_data(p.item_id)
			if data.is_empty(): continue
			
			var icon = data.get("icon")
			if icon is Texture2D:
				btn.icon = icon
				btn.text = ""
			else:
				var prefix : String = "★ " if GameState.is_relic_refined(p.item_id) else ""
				btn.text = prefix + data.get("name", "?").substr(0, 2)
				
			# ★ 修复：不使用 disabled，避免半透明。移除原生 tooltip
			btn.tooltip_text = ""
			var r_id = p.item_id
			btn.mouse_entered.connect(func(): _show_relic_hover_info(r_id))
			btn.mouse_exited.connect(_hide_relic_hover_info)
			
			_bf.relic_icon_container.add_child(btn)
			has_any = true
			
		elif p is Dictionary and p.get("type", "") == "aura":
			var aid : String = p.get("aura_id", "")
			var ad : Dictionary = AuraManager.get_aura(aid)
			if ad.is_empty(): continue
				
			var icon = ad.get("icon")
			if icon is Texture2D:
				btn.icon = icon
				btn.text = ""
			else:
				btn.text = ad.get("name", aid).substr(0, 2)
				
			btn.tooltip_text = ""
			btn.pressed.connect(_on_aura_icon_clicked.bind(aid))
			btn.mouse_entered.connect(func(): _show_aura_hover_info(aid))
			btn.mouse_exited.connect(_hide_relic_hover_info)
			
			_bf.relic_icon_container.add_child(btn)
			has_any = true

	if not has_any:
		var label := Label.new()
		label.text = "无遗物"
		label.add_theme_font_size_override("font_size", 6)
		_bf.relic_icon_container.add_child(label)

# ★ 新增：遗物悬浮显示到左上角统一信息面板
func _show_relic_hover_info(relic_id: String):
	if not _bf or not _bf.info_text_label or not _bf.info_panel: return
	var data = RelicManager.get_relic_data(relic_id)
	if data.is_empty(): return
	
	var lines = []
	var name_text = data.get("name", "未知遗物")
	if GameState.is_relic_refined(relic_id): name_text = "★ " + name_text
	lines.append(name_text)
	lines.append("遗物")
	lines.append(data.get("description", ""))
	
	_bf.info_text_label.text = "\n".join(lines)
	_bf._adjust_info_panel(_bf.info_text_label, _bf.info_panel, null)

# ★ 新增：光环悬浮显示到统一信息面板
func _show_aura_hover_info(aid: String):
	if not _bf or not _bf.info_text_label or not _bf.info_panel: return
	var ad = AuraManager.get_aura(aid)
	if ad.is_empty(): return
	
	var lines = []
	lines.append(ad.get("name", aid))
	lines.append("光环 [" + str(ad.get("tag", "")) + "]")
	lines.append(ad.get("description", ""))
	
	_bf.info_text_label.text = "\n".join(lines)
	_bf._adjust_info_panel(_bf.info_text_label, _bf.info_panel, null)

func _hide_relic_hover_info():
	if _bf:
		_bf._on_request_hide_info()


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
