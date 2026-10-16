extends CanvasLayer

signal relic_selected(relic_id: String)

@onready var relic_container: HBoxContainer = $Panel/VBoxContainer/RelicContainer
@onready var hint_label: Label = $Panel/VBoxContainer/HintLabel
@onready var existing_container: HBoxContainer = $Panel/VBoxContainer/ExistingContainer
@onready var cancel_btn: Button = $Panel/VBoxContainer/CancelButton
@onready var separator2: HSeparator = $Panel/VBoxContainer/Separator2

var _relic_options: Array = []
var _selected_candidate: String = ""
var _slots_full: bool = false
var _candidate_buttons: Dictionary = {}

func _ready():
	cancel_btn.pressed.connect(_on_cancel_pressed)


func setup_options(exclude_ids: Array = []):
	_slots_full = GameState.is_passive_full()
	print("RelicSelectUI: 被动槽已满=", _slots_full)

	var owned_ids : Array = []
	for relic in GameState.get_relics_from_passives():
		owned_ids.append(relic.item_id)

	var unlocked = RelicManager.get_unlocked_relics()
	var pool = []
	for relic_id in unlocked:
		if relic_id in exclude_ids:
			continue
		if relic_id in owned_ids:
			continue
		pool.append(relic_id)

	if pool.size() < 3:
		print("警告：可选的遗物不足 3 个，仅 ", pool.size(), " 个")

	pool.shuffle()
	_relic_options = pool.slice(0, min(3, pool.size()))

	_build_candidates()
	_update_ui_state()


func _build_candidates():
	for child in relic_container.get_children():
		child.queue_free()
	_candidate_buttons.clear()

	for relic_id in _relic_options:
		var data = RelicManager.get_relic_data(relic_id)
		if data.is_empty():
			continue

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var name_label = Label.new()
		name_label.text = data.get("name", "?")
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_label)

		var desc_label = Label.new()
		desc_label.text = data.get("description", "")
		desc_label.add_theme_font_size_override("font_size", 6)
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(100, 0)
		vbox.add_child(desc_label)

		var btn = Button.new()
		btn.text = "选择"
		btn.add_theme_font_size_override("font_size", 8)
		btn.custom_minimum_size = Vector2(80, 20)
		btn.pressed.connect(_on_candidate_clicked.bind(relic_id))
		vbox.add_child(btn)

		relic_container.add_child(vbox)
		_candidate_buttons[relic_id] = btn


func _on_candidate_clicked(relic_id: String):
	print("候选点击: ", relic_id)

	if not _slots_full:
		_confirm_selection(relic_id)
		return

	_selected_candidate = relic_id
	_update_ui_state()


func _update_ui_state():
	if not _slots_full:
		hint_label.visible = false
		separator2.visible = false
		existing_container.visible = false
		cancel_btn.visible = false
		return

	if _selected_candidate == "":
		hint_label.text = "被动槽已满，请先点击上方候选遗物"
		hint_label.visible = true
		separator2.visible = true
		existing_container.visible = false
		cancel_btn.visible = false
	else:
		var data = RelicManager.get_relic_data(_selected_candidate)
		hint_label.text = "已选：" + data.get("name", "") + "，请点击下方遗物槽进行替换"
		hint_label.visible = true
		separator2.visible = true
		existing_container.visible = true
		cancel_btn.visible = true
		_build_existing_relics()


# ★ v4.2：兼容 {type:"aura"} 与 {type:"refine"} 槽位
func _build_existing_relics():
	for child in existing_container.get_children():
		child.queue_free()

	var passives = GameState.get_passives()
	for i in range(passives.size()):
		var p = passives[i]
		var btn = Button.new()
		btn.add_theme_font_size_override("font_size", 8)
		btn.custom_minimum_size = Vector2(80, 20)

		if p == null:
			btn.text = "空"
			btn.pressed.connect(_on_existing_relic_clicked.bind(i))
		elif p is ItemInstance:
			var data = RelicManager.get_relic_data(p.item_id)
			btn.text = data.get("name", "?")
			btn.pressed.connect(_on_existing_relic_clicked.bind(i))
		elif p is Dictionary and p.has("refine_id"):
			btn.text = "（精炼）"
			btn.disabled = true
		elif p is Dictionary and p.get("type", "") == "aura":
			# ★ 光环槽：不可被遗物替换
			var aid : String = p.get("aura_id", "")
			btn.text = "◆ " + AuraManager.get_display_name(aid)
			btn.disabled = true
		else:
			btn.text = "空"
			btn.pressed.connect(_on_existing_relic_clicked.bind(i))

		existing_container.add_child(btn)


func _on_existing_relic_clicked(slot_idx: int):
	print("替换被动槽 ", slot_idx, " -> ", _selected_candidate)

	# ★ 双保险：精炼槽 / 光环槽 不可被遗物替换
	var target = GameState.get_passives()[slot_idx]
	if target is Dictionary and (target.has("refine_id") or target.get("type", "") == "aura"):
		return

	var inst = ItemInstance.new()
	inst.item_id = _selected_candidate
	inst.count = 1

	GameState.set_passive_at_slot(slot_idx, inst)
	RelicManager.unlock_relic(_selected_candidate)

	relic_selected.emit(_selected_candidate)
	queue_free()


func _confirm_selection(relic_id: String):
	var inst = ItemInstance.new()
	inst.item_id = relic_id
	inst.count = 1
	var success = GameState.add_relic_to_passive_slot(inst)
	if success:
		RelicManager.unlock_relic(relic_id)
		print("获得遗物: ", relic_id)
	else:
		print("被动槽异常，未获得: ", relic_id)
	relic_selected.emit(relic_id)
	queue_free()


func _on_cancel_pressed():
	print("放弃遗物选择")
	relic_selected.emit("")
	queue_free()
