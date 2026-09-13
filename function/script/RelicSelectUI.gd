extends CanvasLayer

signal relic_selected(relic_id: String)

@onready var relic_container: HBoxContainer = $Panel/VBoxContainer/RelicContainer
@onready var hint_label: Label = $Panel/VBoxContainer/HintLabel
@onready var existing_container: HBoxContainer = $Panel/VBoxContainer/ExistingContainer
@onready var cancel_btn: Button = $Panel/VBoxContainer/CancelButton
@onready var separator2: HSeparator = $Panel/VBoxContainer/Separator2

var _relic_options: Array = []          # 3 个候选遗物 id
var _selected_candidate: String = ""    # 玩家选中的候选遗物 id
var _slots_full: bool = false           # 遗物槽是否已满
var _candidate_buttons: Dictionary = {} # relic_id -> Button，用于高亮


func _ready():
	cancel_btn.pressed.connect(_on_cancel_pressed)


# ---- 初始化：从已解锁遗物中排除已拥有的，随机 3 个 ----
func setup_options(exclude_ids: Array = []):
	# ---- 检查槽位是否已满 ----
	_slots_full = true
	for relic in GameState.global_relics:
		if relic == null:
			_slots_full = false
			break
	
	print("RelicSelectUI: 槽位已满=", _slots_full)
	
	# ---- 候选池 ----
	var unlocked = RelicManager.get_unlocked_relics()
	var pool = []
	for relic_id in unlocked:
		if relic_id not in exclude_ids:
			pool.append(relic_id)
	
	if pool.size() < 3:
		print("警告：可选的遗物不足 3 个，仅 ", pool.size(), " 个")
	
	pool.shuffle()
	_relic_options = pool.slice(0, min(3, pool.size()))
	
	_build_candidates()
	_update_ui_state()


# ---- 构建 3 个候选卡片 ----
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
		
		# ---- 名称 ----
		var name_label = Label.new()
		name_label.text = data.get("name", "?")
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_label)
		
		# ---- 描述 ----
		var desc_label = Label.new()
		desc_label.text = data.get("description", "")
		desc_label.add_theme_font_size_override("font_size", 6)
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(100, 0)
		vbox.add_child(desc_label)
		
		# ---- 选择按钮 ----
		var btn = Button.new()
		btn.text = "选择"
		btn.add_theme_font_size_override("font_size", 8)
		btn.custom_minimum_size = Vector2(80, 20)
		btn.pressed.connect(_on_candidate_clicked.bind(relic_id))
		vbox.add_child(btn)
		
		relic_container.add_child(vbox)
		_candidate_buttons[relic_id] = btn


# ---- 候选被点击 ----
func _on_candidate_clicked(relic_id: String):
	print("候选点击: ", relic_id)
	
	# ---- 槽未满：直接确认选择 ----
	if not _slots_full:
		_confirm_selection(relic_id)
		return
	
	# ---- 槽满：进入替换选择阶段 ----
	_selected_candidate = relic_id
	_update_ui_state()


# ---- 更新界面状态 ----
func _update_ui_state():
	if not _slots_full:
		# 槽未满：直接显示候选，隐藏替换区
		hint_label.visible = false
		separator2.visible = false
		existing_container.visible = false
		cancel_btn.visible = false
		return
	
	if _selected_candidate == "":
		# 槽满，但未选候选：提示玩家先选候选
		hint_label.text = "遗物槽已满，请先点击上方候选遗物"
		hint_label.visible = true
		separator2.visible = true
		existing_container.visible = false
		cancel_btn.visible = false
	else:
		# 槽满，且已选候选：显示替换区
		var data = RelicManager.get_relic_data(_selected_candidate)
		hint_label.text = "已选：" + data.get("name", "") + "，请点击下方遗物进行替换"
		hint_label.visible = true
		separator2.visible = true
		existing_container.visible = true
		cancel_btn.visible = true
		_build_existing_relics()


# ---- 构建已有遗物按钮（用于替换） ----
func _build_existing_relics():
	for child in existing_container.get_children():
		child.queue_free()
	
	for i in range(GameState.global_relics.size()):
		var relic = GameState.global_relics[i]
		var btn = Button.new()
		btn.add_theme_font_size_override("font_size", 8)
		btn.custom_minimum_size = Vector2(80, 20)
		
		if relic != null:
			var data = RelicManager.get_relic_data(relic.item_id)
			btn.text = data.get("name", "?")
			btn.pressed.connect(_on_existing_relic_clicked.bind(i))
		else:
			btn.text = "空"
			btn.disabled = true
		
		existing_container.add_child(btn)

# ---- 已有遗物被点击（替换） ----
func _on_existing_relic_clicked(slot_idx: int):
	print("替换槽 ", slot_idx, " -> ", _selected_candidate)
	
	var inst = ItemInstance.new()
	inst.item_id = _selected_candidate
	inst.count = 1
	
	# ---- 直接替换槽位中的遗物 ----
	GameState.global_relics[slot_idx] = inst
	RelicManager.unlock_relic(_selected_candidate)
	
	relic_selected.emit(_selected_candidate)
	queue_free()

# ---- 未满槽：直接确认选择 ----
func _confirm_selection(relic_id: String):
	var inst = ItemInstance.new()
	inst.item_id = relic_id
	inst.count = 1
	var success = GameState.add_global_relic(inst)
	if success:
		RelicManager.unlock_relic(relic_id)
		print("获得遗物: ", relic_id)
	else:
		print("遗物槽异常，未获得: ", relic_id)
	relic_selected.emit(relic_id)
	queue_free()

# ---- 放弃选择 ----
func _on_cancel_pressed():
	print("放弃遗物选择")
	relic_selected.emit("")
	queue_free()
