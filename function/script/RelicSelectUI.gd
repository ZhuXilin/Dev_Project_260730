extends CanvasLayer

signal relic_selected(relic_id: String)

@onready var relic_container: HBoxContainer = $Panel/VBoxContainer/RelicContainer

var _relic_options: Array = []   # 3 个候选遗物 id

func _ready():
	pass

# ---- 从已解锁遗物中随机 3 个 ----
func setup_options(exclude_ids: Array = []):
	var unlocked = RelicManager.get_unlocked_relics()
	
	# 过滤掉已拥有/排除的
	var pool = []
	for relic_id in unlocked:
		if relic_id not in exclude_ids:
			pool.append(relic_id)
	
	# 如果不足 3 个，可以重复（或补全）
	if pool.size() < 3:
		print("警告：可选的遗物不足 3 个，仅 ", pool.size(), " 个")
	
	# 随机 3 个
	pool.shuffle()
	_relic_options = pool.slice(0, min(3, pool.size()))
	
	_build_buttons()

func _build_buttons():
	for child in relic_container.get_children():
		child.queue_free()
	
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
		btn.pressed.connect(_on_relic_chosen.bind(relic_id))
		vbox.add_child(btn)
		
		relic_container.add_child(vbox)

func _on_relic_chosen(relic_id: String):
	print("选择遗物: ", relic_id)
	relic_selected.emit(relic_id)
	queue_free()
