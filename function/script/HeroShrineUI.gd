extends CanvasLayer

signal closed

# ★ 从 const 改为 var，_ready() 里从配置读
var COST_PER_CLASS : int = 0

const PERFORMANCE_DURATION : float = 2.0
const POST_SWITCH_DURATION : float = 0.8

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/TopBar/TitleLabel
@onready var gold_label : Label = $Panel/VBox/TopBar/GoldLabel
@onready var cost_label : Label = $Panel/VBox/TopBar/CostLabel
@onready var hint_label : Label = $Panel/VBox/HintLabel
@onready var unit_row : HBoxContainer = $Panel/VBox/UnitRow
@onready var close_btn : Button = $Panel/VBox/BottomBar/CloseButton

@onready var performance_layer : Control = $PerformanceLayer
@onready var perf_sprite : AnimatedSprite2D = $PerformanceLayer/CenterBox/SpriteBox/UnitSprite
@onready var perf_label : Label = $PerformanceLayer/CenterBox/PerfLabel

var _is_performing : bool = false
var _mode : String = "map"
var _arena_ref = null
var _custom_party : Array = []

var _max_conversions : int = 1
var _converted_count : int = 0

var _is_chapel_mode : bool = false

# ============================================================
#  上下文设置
# ============================================================
func setup_arena(arena_node, unit_data) -> void:
	_mode = "arena"
	_arena_ref = arena_node
	_custom_party = [unit_data] if unit_data else []
	_max_conversions = 1
	_converted_count = 0
	if is_node_ready():
		_rebuild()


func setup_map(max_conversions: int = 1) -> void:
	_mode = "map"
	_arena_ref = null
	_custom_party = []
	_max_conversions = max_conversions
	_converted_count = 0
	if is_node_ready():
		_rebuild()


func _rebuild():
	_refresh_soul_display()
	_build_unit_row()


func _get_party() -> Array:
	if not _custom_party.is_empty():
		return _custom_party
	return GameState.party


# ★ 统一用魂
func _get_soul() -> int:
	return GameState.soul


func _subtract_soul(amount: int) -> void:
	GameState.soul -= amount


func _reached_limit() -> bool:
	return _max_conversions >= 0 and _converted_count >= _max_conversions


# ============================================================
#  初始化
# ============================================================
func _ready():
	COST_PER_CLASS = 0 
	performance_layer.visible = false
	cost_label.text = "  |  转职：免费"
	
	# ★ 调整转职演出界面：放大3倍并居中
	var sprite_box = get_node_or_null("PerformanceLayer/CenterBox/SpriteBox")
	if sprite_box:
		sprite_box.custom_minimum_size = Vector2(96, 96)
	if perf_sprite:
		perf_sprite.position = Vector2(48, 48)
		perf_sprite.scale = Vector2(1, 1)

	# ★ 绑定英灵殿复活按钮
	var revive_btn = get_node_or_null("Panel/VBox/ChapelActions/ReviveBtn")
	var actions_box = get_node_or_null("Panel/VBox/ChapelActions")
	
	if actions_box:
		actions_box.visible = _is_chapel_mode
	if revive_btn:
		revive_btn.pressed.connect(_on_chapel_revive)

	MusicManager.play_hero_shrine_music()
	_refresh_soul_display()
	_build_unit_row()


## 由 MapScene 调用，标记为英灵殿模式
func setup_as_chapel():
	_is_chapel_mode = true
	if is_node_ready():
		var actions_box = get_node_or_null("Panel/VBox/ChapelActions")
		if actions_box: actions_box.visible = true
	if hint_label:
		hint_label.text = "英灵殿赐福：可免费复活或转职一次"


func _on_chapel_revive():
	var dead : Array = GameState.get_dead_party()
	if dead.is_empty():
		if hint_label:
			hint_label.text = "当前没有阵亡单位需要复活"
		return
		
	_show_revive_submenu()


func _show_revive_submenu():
	for child in unit_row.get_children():
		unit_row.remove_child(child)
		child.queue_free()
		
	if hint_label:
		hint_label.text = "选择一名单位复活"
		
	var dead_units : Array = GameState.get_dead_party()
	for ud in dead_units:
		var btn := Button.new()
		btn.text = "%s（%s）" % [
			ud.display_name,
			UnitDataManager.get_unit_type_display_name(ud.unit_name)
		]
		btn.custom_minimum_size = Vector2(100, 40)
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_revive_unit.bind(ud.unit_name, ud.display_name))
		unit_row.add_child(btn)

	var back := Button.new()
	back.text = "返回转职"
	back.custom_minimum_size = Vector2(80, 40)
	back.add_theme_font_size_override("font_size", 8)
	back.pressed.connect(_build_unit_row)
	unit_row.add_child(back)


func _on_revive_unit(unit_name: String, display_name: String):
	if GameState.revive_unit(unit_name, display_name):
		SaveManager.auto_save()
		if hint_label:
			hint_label.text = "%s 已复活" % display_name
		_build_unit_row()
		SoundManager.play_heal_sound()


func _refresh_soul_display():
	if gold_label:
		gold_label.text = "魂: %d" % GameState.soul


func _build_unit_row():
	for child in unit_row.get_children():
		unit_row.remove_child(child)
		child.queue_free()

	var party : Array = _get_party()
	print("[HeroShrine] 构建单位列表：", party.size(), " 个，mode=", _mode)
	for i in range(party.size()):
		unit_row.add_child(_build_unit_card(i))


# ============================================================
#  单位卡片
# ============================================================
func _build_unit_card(unit_idx: int) -> PanelContainer:
	var party : Array = _get_party()
	if unit_idx < 0 or unit_idx >= party.size():
		return PanelContainer.new()
	var unit : UnitData = party[unit_idx]
	var unit_display : String = unit.display_name if unit.display_name != "" else unit.unit_name
	var type_cn : String = UnitDataManager.get_unit_type_display_name(unit.unit_name)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(130, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# ★ 新增：单位图标（32x32，含 idle 动画）
	var sprite_wrapper := Control.new()
	sprite_wrapper.custom_minimum_size = Vector2(32, 32)
	sprite_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(sprite_wrapper)

	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite_wrapper.add_child(texture_rect)

	var frames_path = UnitDataManager.get_sprite_frames_path(unit.unit_name)
	if unit.override_sprite_path != "":
		frames_path = unit.override_sprite_path
	if frames_path != "" and ResourceLoader.exists(frames_path):
		var frames = load(frames_path) as SpriteFrames
		if frames and frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
			texture_rect.texture = frames.get_frame_texture("idle", 0)
			_attach_idle_animator(texture_rect, frames)

	var name_lb = Label.new()
	name_lb.add_theme_font_size_override("font_size", 9)
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lb)

	var status_lb = Label.new()
	status_lb.add_theme_font_size_override("font_size", 7)
	status_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(status_lb)

	# ---- 已转职 ----
	if unit.advanced_class != "":
		var adv_name : String = AdvancedClassManager.get_display_name(unit.advanced_class)
		name_lb.text = unit_display + "\n" + type_cn

		var suffix : String = "（已转职）"
		var dim_color : Color = Color(0.55, 0.55, 0.55, 1)
		var card_color : Color = Color(0.7, 0.7, 0.7, 1)
		if unit.is_dead:
			suffix = "（已转职 · 已阵亡）"
			dim_color = Color(0.4, 0.4, 0.4, 1)
			card_color = Color(0.5, 0.5, 0.5, 1)

		name_lb.modulate = dim_color
		status_lb.text = "★ " + adv_name + "\n" + suffix
		status_lb.modulate = dim_color
		card.modulate = card_color
		sprite_wrapper.modulate = card_color
		return card

	# ---- 阵亡 ----
	if unit.is_dead:
		name_lb.text = unit_display + "\n" + type_cn
		name_lb.modulate = Color(0.4, 0.4, 0.4, 1)
		status_lb.text = "已阵亡 / 已熔铸"
		status_lb.modulate = Color(0.4, 0.4, 0.4, 1)
		card.modulate = Color(0.5, 0.5, 0.5, 1)
		sprite_wrapper.modulate = Color(0.4, 0.4, 0.4, 1)
		return card

	# ---- 无进阶定义 ----
	var branches : Array = AdvancedClassManager.get_branches_for_unit(unit.unit_name)
	if branches.is_empty():
		name_lb.text = unit_display + "\n" + type_cn
		status_lb.text = "无转职"
		status_lb.modulate = Color(0.55, 0.55, 0.55, 1)
		card.modulate = Color(0.7, 0.7, 0.7, 1)
		return card

	# ---- 可转职 ----
	name_lb.text = unit_display + "\n" + type_cn
	var branch_names : Array = []
	for b in branches:
		branch_names.append("★ " + b.name)
	status_lb.text = "可转职：\n" + "\n".join(branch_names) + "\n（点击查看）"

	var _can_afford : bool = true 
	var reached : bool = _reached_limit()

	if reached:
		status_lb.modulate = Color(0.55, 0.55, 0.55, 1)
		card.modulate = Color(0.7, 0.7, 0.7, 1)
		status_lb.text += "\n（本次已转职）"
	else:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_input.bind(unit_idx))
		card.mouse_entered.connect(_on_card_hover_enter.bind(card))
		card.mouse_exited.connect(_on_card_hover_exit.bind(card))

	return card


func _attr_short(key: String) -> String:
	match key:
		"max_hp":       return "HP"
		"strength":     return "力"
		"dexterity":    return "灵"
		"intelligence": return "智"
		"faith":        return "信"
		"arcane":       return "感"
		"move_range":   return "移"
		_:              return key


func _on_card_hover_enter(card: PanelContainer):
	card.modulate = Color(1.2, 1.2, 1.2, 1)


func _on_card_hover_exit(card: PanelContainer):
	card.modulate = Color.WHITE


func _on_card_input(event: InputEvent, unit_idx: int):
	if _is_performing:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_on_card_clicked(unit_idx)


# ============================================================
#  点击卡片 → 二选一弹窗
# ============================================================
func _on_card_clicked(unit_idx: int):
	if _is_performing: return
	if _reached_limit(): return
	var party : Array = _get_party()
	if unit_idx < 0 or unit_idx >= party.size(): return
	if _get_soul() < COST_PER_CLASS: return

	var unit : UnitData = party[unit_idx]
	if unit.advanced_class != "": return

	var branches : Array = AdvancedClassManager.get_branches_for_unit(unit.unit_name)
	if branches.is_empty():
		return
	if branches.size() == 1:
		_begin_convert(unit, branches[0])
		return
	_show_branch_picker(unit, branches)


func _show_branch_picker(unit : UnitData, branches : Array):
	var picker := _make_picker_panel(unit, branches)
	add_child(picker)


func _make_picker_panel(unit : UnitData, branches : Array) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# ★ 修复边沿问题：使用完全纯色覆盖，彻底遮住底层的原界面
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 1) 
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var center_box := CenterContainer.new()
	center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center_box)

	var picker_panel := PanelContainer.new()
	picker_panel.custom_minimum_size = Vector2(440, 0)
	
	var sb := StyleBoxFlat.new()
	# ★ 去掉背景和所有边框，只作为纯排版容器使用
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	picker_panel.add_theme_stylebox_override("panel", sb)
	center_box.add_child(picker_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	picker_panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择转职方向"
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vbox.add_child(row)

	# 基础单位 sprite（回退用）
	var base_path : String = UnitDataManager.get_sprite_frames_path(unit.unit_name)
	if unit.override_sprite_path != "":
		base_path = unit.override_sprite_path

	for b in branches:
		var adv : AdvancedClassData = b
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(130, 0)
		col.add_theme_constant_override("separation", 6)
		col.alignment = BoxContainer.ALIGNMENT_BEGIN
		
		# ---- 1. 单位图标 (32x32) ----
		var sprite_wrapper := Control.new()
		sprite_wrapper.custom_minimum_size = Vector2(32, 32) 
		sprite_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(sprite_wrapper)

		var texture_rect := TextureRect.new()
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite_wrapper.add_child(texture_rect)

		var preview_path : String = adv.sprite_frames_path
		if preview_path == "" or not ResourceLoader.exists(preview_path):
			preview_path = base_path

		var preview_loaded : bool = false
		if preview_path != "" and ResourceLoader.exists(preview_path):
			var frames = load(preview_path) as SpriteFrames
			if frames and frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
				texture_rect.texture = frames.get_frame_texture("idle", 0)
				_attach_idle_animator(texture_rect, frames)
				preview_loaded = true
		if not preview_loaded:
			texture_rect.visible = false
			
		# ---- 2. 文字与属性信息 ----
		var name_lb := Label.new()
		name_lb.text = "★ " + adv.name
		name_lb.add_theme_font_size_override("font_size", 10)
		name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_lb)

		var desc_lb := Label.new()
		desc_lb.text = adv.description
		desc_lb.add_theme_font_size_override("font_size", 7)
		desc_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(desc_lb)

		var stats_lb := Label.new()
		var stats_text : Array = []
		for k in adv.stat_bonus:
			stats_text.append("%s +%d" % [_attr_short(k), int(adv.stat_bonus[k])])
		stats_lb.text = "\n".join(stats_text)
		stats_lb.add_theme_font_size_override("font_size", 7)
		stats_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_lb.modulate = Color(0.7, 0.9, 0.7)
		col.add_child(stats_lb)

		# ★ 占位区：推底对齐
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(spacer)

		# ---- 3. 按钮 ----
		var btn := Button.new()
		btn.text = "选择"
		btn.add_theme_font_size_override("font_size", 9)
		btn.custom_minimum_size = Vector2(80, 22)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(func():
			overlay.queue_free()
			_begin_convert(unit, adv)
		)
		col.add_child(btn)

		row.add_child(col)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 8)
	cancel.custom_minimum_size = Vector2(80, 20)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(cancel)

	return overlay


# ★ 新增：idle 动画播放器（复用 SacrificeUI 的实现思路）
func _attach_idle_animator(tex_rect: TextureRect, frames: SpriteFrames):
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	tex_rect.add_child(timer)

	var frame_count := frames.get_frame_count("idle")
	var idx := {"value": 0}
	timer.timeout.connect(func():
		if not is_instance_valid(tex_rect):
			return
		idx["value"] = (idx["value"] + 1) % frame_count
		var t = frames.get_frame_texture("idle", idx["value"])
		if t:
			tex_rect.texture = t
	)


# ============================================================
#  转职流程
# ============================================================
func _begin_convert(unit : UnitData, adv : AdvancedClassData):
	if _is_performing:
		return
	if _get_soul() < COST_PER_CLASS:
		return
	if _reached_limit():
		return

	_is_performing = true

	print("[HeroShrine][DEBUG] _begin_convert unit=%s/%s adv=%s granted_talent=%s" % [
		unit.unit_name, unit.display_name, adv.id, adv.granted_talent])

	# 1. 立即扣魂 + 记录
	_subtract_soul(COST_PER_CLASS)
	unit.advanced_class = adv.id

	_apply_growth_rolls(unit)
	unit.tags.clear()
	for t in adv.tags:
		unit.tags.append(t)

	for key in adv.stat_bonus:
		var val : int = int(adv.stat_bonus[key])
		match key:
			"max_hp":
				unit.max_hp += val
				unit.hit_points += val
			"strength":     unit.strength += val
			"dexterity":    unit.dexterity += val
			"intelligence": unit.intelligence += val
			"faith":        unit.faith += val
			"arcane":       unit.arcane += val
			"move_range":   unit.move_range += val

	if adv.granted_talent != "":
		unit.advanced_talent_id = adv.granted_talent
		var t_inst := TalentInstance.new()
		t_inst.talent_id = adv.granted_talent
		t_inst.is_active = true
		var tdata = TalentManager.get_talent_data(adv.granted_talent)
		if tdata and tdata.is_active_skill:
			t_inst.is_ready = true
			t_inst.cooldown_remaining = 0
		unit.advanced_talent_inst = t_inst

	if adv.sprite_frames_path != "":
		unit.override_sprite_path = adv.sprite_frames_path

	_converted_count += 1

	if _mode == "map":
		SaveManager.auto_save()
	else:
		_sync_advanced_class_to_gamestate(unit)
		SaveManager.auto_save()
	print("[HeroShrine] %s 转职为 %s（%s 模式，魂已扣，本次已转 %d/%d）" % [
		unit.display_name, adv.name, _mode, _converted_count, _max_conversions])

	# 2. 演出
	panel.visible = false
	performance_layer.visible = true
	performance_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	perf_label.text = "英灵降临..."

	var base_path : String = UnitDataManager.get_sprite_frames_path(unit.unit_name)
	_load_sprite_into(perf_sprite, base_path)

	MusicManager.play_hero_shrine_convert_music()
	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout

	var adv_path : String = adv.sprite_frames_path if adv.sprite_frames_path != "" else base_path
	_load_sprite_into(perf_sprite, adv_path)
	perf_label.text = "★ " + adv.name

	await get_tree().create_timer(POST_SWITCH_DURATION, true, false, true).timeout

	# 3. 恢复界面
	performance_layer.visible = false
	performance_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = true
	MusicManager.play_hero_shrine_music()

	_refresh_soul_display()
	_build_unit_row()

	if _reached_limit():
		if hint_label:
			hint_label.text = "本次转职已完成"
		if close_btn:
			close_btn.text = "完成"

	_is_performing = false


func _load_sprite_into(sprite: AnimatedSprite2D, path: String):
	if path == "" or not ResourceLoader.exists(path):
		sprite.visible = false
		return
	var frames = load(path) as SpriteFrames
	if not frames:
		sprite.visible = false
		return
	sprite.sprite_frames = frames
	sprite.visible = true
	if frames.has_animation("idle"):
		sprite.play("idle")
	else:
		var anims = frames.get_animation_names()
		if anims.size() > 0:
			sprite.play(anims[0])


# ============================================================
#  关闭
# ============================================================
func _on_close_pressed():
	if _is_performing:
		return
	closed.emit()
	queue_free()


# ============================================================
#  竞技场模式：同步到 GameState.party
# ============================================================
func _sync_advanced_class_to_gamestate(src_unit: UnitData):
	if src_unit == null: return
	print("[HeroShrine][DEBUG] _sync_advanced_class_to_gamestate src=%s/%s class=%s talent=%s" % [
		src_unit.unit_name, src_unit.display_name,
		src_unit.advanced_class, src_unit.advanced_talent_id])

	for i in range(GameState.party.size()):
		var u : UnitData = GameState.party[i]
		if u.unit_name == src_unit.unit_name and u.display_name == src_unit.display_name:
			u.advanced_class = src_unit.advanced_class
			u.advanced_talent_id = src_unit.advanced_talent_id
			u.advanced_talent_inst = src_unit.advanced_talent_inst
			u.override_sprite_path = src_unit.override_sprite_path
			u.max_hp = src_unit.max_hp
			u.strength = src_unit.strength
			u.dexterity = src_unit.dexterity
			u.intelligence = src_unit.intelligence
			u.faith = src_unit.faith
			u.arcane = src_unit.arcane
			u.move_range = src_unit.move_range

			u.tags.clear()
			for t in src_unit.tags:
				u.tags.append(t)
			return


func _apply_growth_rolls(unit : UnitData):
	var points_dict : Dictionary = GameState.unit_attr_points.get(unit.unit_name, {})
	if points_dict.is_empty(): return
	for attr_key in points_dict:
		if not _is_attr_key(attr_key): continue
		var points : int = int(points_dict[attr_key])
		if points <= 0: continue
		var bonus : int = 0
		for i in range(points):
			if randf() < 0.3: bonus += 1
		if bonus > 0:
			_apply_attr_bonus(unit, attr_key, bonus)


func _is_attr_key(key : String) -> bool:
	return key in ["max_hp", "strength", "dexterity", "intelligence", "faith", "arcane", "move_range"]


func _apply_attr_bonus(unit : UnitData, key : String, amount : int):
	match key:
		"max_hp": unit.max_hp += amount; unit.hit_points += amount
		"strength":     unit.strength += amount
		"dexterity":    unit.dexterity += amount
		"intelligence": unit.intelligence += amount
		"faith":        unit.faith += amount
		"arcane":       unit.arcane += amount
		"move_range":   unit.move_range += amount
