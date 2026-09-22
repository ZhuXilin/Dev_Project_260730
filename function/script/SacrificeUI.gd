class_name SacrificeUI
extends CanvasLayer

signal closed

var _party : Array = []
var _panel_ref = null   # EquipmentConfig 引用

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/Title
@onready var unit_row : HBoxContainer = $Panel/VBox/UnitRow
@onready var back_btn : Button = $Panel/VBox/BottomBar/BackBtn


func _ready():
	layer = 25
	back_btn.pressed.connect(_on_back_pressed)


func setup(party_ref: Array, panel_ref) -> void:
	_party = party_ref
	_panel_ref = panel_ref
	_build_cards()


func _build_cards():
	for child in unit_row.get_children():
		unit_row.remove_child(child)
		child.queue_free()

	var alive : Array = []
	for u in _party:
		if not u.is_dead:
			alive.append(u)

	if alive.size() <= 1:
		var hint := Label.new()
		hint.text = "至少保留 1 个存活单位，无法熔铸"
		hint.add_theme_font_size_override("font_size", 8)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.modulate = Color(1.0, 0.6, 0.6)
		unit_row.add_child(hint)
		return

	for u in alive:
		unit_row.add_child(_build_unit_card(u))


func _build_unit_card(u: UnitData) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(90, 120)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# 图标
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(48, 48)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var frames_path = UnitDataManager.get_sprite_frames_path(u.unit_name)
	if u.override_sprite_path != "":
		frames_path = u.override_sprite_path
	if frames_path != "" and ResourceLoader.exists(frames_path):
		var frames = load(frames_path) as SpriteFrames
		if frames and frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
			texture_rect.texture = frames.get_frame_texture("idle", 0)
			# 切帧
			var timer := Timer.new()
			timer.wait_time = 0.25
			timer.autostart = true
			texture_rect.add_child(timer)
			var frame_count := frames.get_frame_count("idle")
			var idx := {"value": 0}
			timer.timeout.connect(func():
				if not is_instance_valid(texture_rect):
					return
				idx["value"] = (idx["value"] + 1) % frame_count
				var t = frames.get_frame_texture("idle", idx["value"])
				if t:
					texture_rect.texture = t
			)
	vbox.add_child(texture_rect)

	# 名字
	var name_lb := Label.new()
	name_lb.text = u.display_name
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lb.add_theme_font_size_override("font_size", 7)
	vbox.add_child(name_lb)

	# 类型
	var type_lb := Label.new()
	type_lb.text = UnitDataManager.get_unit_type_display_name(u.unit_name)
	type_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lb.add_theme_font_size_override("font_size", 6)
	type_lb.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(type_lb)

	# HP
	var hp_lb := Label.new()
	hp_lb.text = "%d/%d" % [u.hit_points, u.max_hp]
	hp_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lb.add_theme_font_size_override("font_size", 6)
	vbox.add_child(hp_lb)

	# 熔铸按钮
	var btn := Button.new()
	btn.text = "熔铸"
	btn.add_theme_font_size_override("font_size", 7)
	btn.pressed.connect(_on_sacrifice.bind(u))
	vbox.add_child(btn)

	return card


func _on_sacrifice(u: UnitData):
	Globals.show_confirm(
		self,
		"确定熔铸 %s？\n将获得 500 金币 + 1 件史诗装备。\n该单位进入阵亡状态，可通过圣坛或复活圣油复活。" % u.display_name,
		"熔铸",
		"取消",
		func(): _do_sacrifice(u),
		func(): pass
	)


func _do_sacrifice(u: UnitData):
	if _panel_ref == null:
		return

	# 收集防具
	var armor_list : Array = []
	for s in u.armor_slots:
		if s != null:
			armor_list.append(s)

	var free_slots : int = GameState.count_free_storage_slots()
	if free_slots >= armor_list.size():
		_panel_ref._do_sacrifice(u, armor_list, 0)
		_rebuild_after_sacrifice()
	else:
		var need : int = armor_list.size() - free_slots
		Globals.show_confirm(
			self,
			"仓库空位不足（需 %d，现有 %d）。\n将丢弃仓库末尾 %d 件防具，是否继续？" % [armor_list.size(), free_slots, need],
			"继续熔铸",
			"取消",
			func():
				_panel_ref._do_sacrifice(u, armor_list, need)
				_rebuild_after_sacrifice(),
			func(): pass
		)


func _rebuild_after_sacrifice():
	_build_cards()
	# 通知主面板刷新
	if _panel_ref and is_instance_valid(_panel_ref):
		_panel_ref._build_unit_columns()
		_panel_ref._build_storage_slots()
		_panel_ref._update_gold_display()


func _on_back_pressed():
	closed.emit()
	queue_free()
