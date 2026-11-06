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

func setup(party_ref: Array, panel_ref) -> void:
	_party = party_ref
	_panel_ref = panel_ref
	if hint_label:
		hint_label.text = "选择一个单位熔铸：熔铸后获得该单位的专属 buff 防具\n熔铸第 3 个单位将导致全灭，本局结束"
	_build_cards()


func _build_cards():
	for child in unit_row.get_children():
		unit_row.remove_child(child)
		child.queue_free()

	var alive : Array = []
	for u in _party:
		if not u.is_dead:
			alive.append(u)

	if alive.is_empty():
		var hint := Label.new()
		hint.text = "没有可熔铸的单位"
		hint.add_theme_font_size_override("font_size", 8)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.modulate = Color(1.0, 0.6, 0.6)
		unit_row.add_child(hint)
		return

	# ★ 存活 ≤ 1 时，仍然显示卡片，但提示"熔铸后将全灭"
	for u in alive:
		unit_row.add_child(_build_unit_card(u))


func _build_unit_card(u: UnitData) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(100, 160)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	var texture_rect = UnitDataManager.create_idle_texture_rect(u.unit_name, Vector2(32, 32))
	texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(texture_rect)

	var name_lb := Label.new()
	name_lb.text = u.display_name
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lb.add_theme_font_size_override("font_size", 8)
	vbox.add_child(name_lb)

	var type_lb := Label.new()
	type_lb.text = UnitDataManager.get_unit_type_display_name(u.unit_name)
	type_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lb.add_theme_font_size_override("font_size", 6)
	type_lb.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(type_lb)

	var hp_lb := Label.new()
	hp_lb.text = "HP %d/%d" % [u.hit_points, u.max_hp]
	hp_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lb.add_theme_font_size_override("font_size", 6)
	vbox.add_child(hp_lb)

	# ★ 熔铸奖励预览：专属防具名 + 简述
	var melt_id : String = SacrificeHelper.get_melt_item_id(u.unit_name)
	var melt_data : ItemData = ItemManager.get_item_data(melt_id)
	var reward_lb := Label.new()
	reward_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_lb.add_theme_font_size_override("font_size", 6)
	reward_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if melt_data:
		reward_lb.text = "获得：" + melt_data.name
		reward_lb.modulate = Color(1.0, 0.85, 0.3)
	else:
		reward_lb.text = "（无产出）"
		reward_lb.modulate = Color(0.6, 0.6, 0.6)
	vbox.add_child(reward_lb)

	# ★ 存活 ≤ 1 时，显示"全灭"警告
	var alive_count := 0
	for member in _party:
		if not member.is_dead:
			alive_count += 1
	if alive_count <= 1:
		var warn_lb := Label.new()
		warn_lb.text = "⚠ 熔铸后全灭，本局结束"
		warn_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn_lb.add_theme_font_size_override("font_size", 6)
		warn_lb.modulate = Color(1.0, 0.4, 0.4)
		warn_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(warn_lb)

	var btn := Button.new()
	btn.text = "熔铸"
	btn.add_theme_font_size_override("font_size", 8)
	btn.pressed.connect(_on_sacrifice.bind(u))
	vbox.add_child(btn)

	return card


func _on_sacrifice(u: UnitData):
	if _panel_ref == null:
		return

	var melt_id : String = SacrificeHelper.get_melt_item_id(u.unit_name)
	var melt_data : ItemData = ItemManager.get_item_data(melt_id)
	var melt_name : String = melt_data.name if melt_data else "专属防具"

	var equip_count : int = 0
	if u.weapon_slot != null: equip_count += 1
	for s in u.armor_slots:
		if s != null: equip_count += 1

	var alive_count := 0
	for member in _party:
		if not member.is_dead:
			alive_count += 1

	var msg : String = ""
	if equip_count > 0:
		msg += "该单位仍有 %d 件装备，熔铸后将被锁定（需通过英灵殿复活取回）。\n\n" % equip_count

	msg += "确定熔铸 %s？\n将获得：【%s】（请在上方领取）" % [u.display_name, melt_name]

	if alive_count <= 1:
		msg += "\n\n⚠ 熔铸后全灭，本局将结束并返回营地。"

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

	_panel_ref._do_sacrifice(u, [], 0)

	closed.emit()
	queue_free()


func _on_back_pressed():
	closed.emit()
	queue_free()
