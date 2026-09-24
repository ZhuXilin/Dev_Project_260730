class_name SacrificeUI
extends CanvasLayer

signal closed

var _party : Array = []
var _panel_ref = null   # EquipmentConfig 引用

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/Title
@onready var hint_label : Label = $Panel/VBox/Hint
@onready var unit_row : HBoxContainer = $Panel/VBox/UnitRow
@onready var back_btn : Button = $Panel/VBox/BottomBar/BackBtn


func _ready():
	layer = 25
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)


func setup(party_ref: Array, panel_ref) -> void:
	_party = party_ref
	_panel_ref = panel_ref
	if hint_label:
		hint_label.text = "选择一个单位熔铸：次数越多奖励越丰厚\n熔铸后单位装备保留，可通过圣坛或复活圣油取回"
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
	card.custom_minimum_size = Vector2(100, 150)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# ---- 单位图标（含 idle 动画） ----
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
			_attach_idle_animator(texture_rect, frames)
	vbox.add_child(texture_rect)

	# ---- 名字 ----
	var name_lb := Label.new()
	name_lb.text = u.display_name
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lb.add_theme_font_size_override("font_size", 8)
	vbox.add_child(name_lb)

	# ---- 类型 ----
	var type_lb := Label.new()
	type_lb.text = UnitDataManager.get_unit_type_display_name(u.unit_name)
	type_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lb.add_theme_font_size_override("font_size", 6)
	type_lb.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(type_lb)

	# ---- HP ----
	var hp_lb := Label.new()
	hp_lb.text = "HP %d/%d" % [u.hit_points, u.max_hp]
	hp_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lb.add_theme_font_size_override("font_size", 6)
	vbox.add_child(hp_lb)

	# ---- 装备数（有装备时高亮） ----
	var equip_count : int = 0
	if u.weapon_slot != null: equip_count += 1
	for s in u.armor_slots:
		if s != null: equip_count += 1
	var equip_lb := Label.new()
	equip_lb.text = "装备 %d 件" % equip_count
	equip_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_lb.add_theme_font_size_override("font_size", 6)
	if equip_count > 0:
		equip_lb.modulate = Color(1.0, 0.85, 0.3)
	else:
		equip_lb.modulate = Color(0.6, 0.6, 0.6)
	vbox.add_child(equip_lb)

	# ---- 熔铸按钮 ----
	var btn := Button.new()
	btn.text = "熔铸"
	btn.add_theme_font_size_override("font_size", 8)
	btn.pressed.connect(_on_sacrifice.bind(u))
	vbox.add_child(btn)

	return card


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


func _on_sacrifice(u: UnitData):
	if _panel_ref == null:
		return

	# 统计装备数，决定是否警告
	var equip_count : int = 0
	if u.weapon_slot != null: equip_count += 1
	for s in u.armor_slots:
		if s != null: equip_count += 1

	var msg : String = ""
	if equip_count > 0:
		msg += "该单位仍有 %d 件装备，熔铸后将永久锁定（可通过圣坛或复活圣油取回）。\n\n" % equip_count
	var next_count : int = GameState.sacrifice_count + 1
	var reward_gold : int = 1000
	var reward_epic : int = 3
	var reward_relic : bool = false
	if next_count == 2:
		reward_gold = 2000
		reward_epic = 5
	elif next_count >= 3:
		reward_gold = 3000
		reward_epic = 5
		reward_relic = true

	msg += "确定熔铸 %s？\n将获得 %d 金币 + %d 件史诗防具" % [u.display_name, reward_gold, reward_epic]
	if reward_relic:
		msg += " + 1 件遗物"
	msg += "。"

	Globals.show_confirm(
		self,
		msg,
		"熔铸",
		"取消",
		func(): _do_sacrifice(u),
		func(): pass
	)


func _do_sacrifice(u: UnitData):
	if _panel_ref == null:
		return

	# 调用主面板逻辑（内部会立即落盘，SL 防护）
	_panel_ref._do_sacrifice(u, [], 0)

	# 关闭 SacrificeUI
	closed.emit()
	queue_free()


func _on_back_pressed():
	closed.emit()
	queue_free()
