# UnitSelectUI.gd
extends CanvasLayer

var all_unit_names: Array[String] = ["剑士", "枪兵", "斧兵", "弓兵", "飞马", "法师", "修女", "龙人", "重甲兵"]
var selected_units: Array[String] = []   # 存储选中的 unit_name（类型）
var selected_names: Array[String] = []   # 存储选中的 display_name（用于显示）
var max_selection: int = 3

@onready var unit_buttons = $UnitListContainer/VBoxContainer
@onready var main_label = $MainUnitLabel
@onready var slot1_label = $Slot1Label
@onready var slot2_label = $Slot2Label
@onready var confirm_btn = $BottomBar/ConfirmButton
@onready var back_btn = $BottomBar/BackButton

func _ready():
	if MusicManager.config and MusicManager.config.unit_select_music:
		MusicManager.play_music(MusicManager.config.unit_select_music)
	_setup_unit_buttons()
	_update_labels()

func _setup_unit_buttons():
	for child in unit_buttons.get_children():
		child.queue_free()

	var unlocked = Globals.get_unlocked_units()
	unlocked.sort()

	for unit_name in unlocked:
		var btn = Button.new()
		btn.text = unit_name   # 显示类型名（暂定，后续会在选中时显示姓名）
		btn.add_theme_font_size_override("font_size", 8)
		btn.size = Vector2(100, 30)
		btn.pressed.connect(_on_unit_selected.bind(unit_name, btn))
		unit_buttons.add_child(btn)
		# 如果该单位已被选择，禁用按钮
		if unit_name in selected_units:
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)

func _on_unit_selected(unit_name: String, btn: Button):
	if selected_units.size() >= max_selection:
		return
	if unit_name in selected_units:
		return   # 不允许重复选择
	selected_units.append(unit_name)
	btn.disabled = true
	btn.modulate = Color(0.5, 0.5, 0.5)
	_update_labels()

func _update_labels():
	var slots = ["主单位", "辅助1", "辅助2"]
	var labels = [main_label, slot1_label, slot2_label]
	for i in range(max_selection):
		if i < selected_units.size():
			labels[i].text = slots[i] + ": " + selected_units[i]
		else:
			labels[i].text = slots[i] + ": (未选择)"
	confirm_btn.disabled = selected_units.size() < max_selection

func _on_confirm_pressed():
	# 确定主单位（第一个选择的），获取其阵营和姓名
	var main_unit_name = selected_units[0]
	var main_data = UnitDataManager.get_unit_data(main_unit_name)  # 读取基本数据，但我们还需要获取 display_name 和 faction，这些需要从游戏数据中读取。
	# 由于我们还没有创建实际单位，我们需要从配置或默认生成。我们可以从 unit_data.json 中读取额外字段？
	# 更好的方式：在单位选择时，我们默认 display_name = unit_name，阵营默认空。但为了功能，我们可临时生成一个 UnitData。
	# 更简单：我们使用 UnitDataManager.get_default_stats 得到基本属性，然后设置 display_name 和 faction 为默认。
	# 实际上，在正式选择前，我们需要让玩家为每个单位输入姓名？需求没有明确，我们先简化：display_name 等于 unit_name。
	# 这样就不需要额外输入了。
	# 但需求要求“单位新增姓名数据”，那么应该在选择时允许命名？当前先假设姓名由配置文件提供（如 unit_data.json 中增加字段）。
	# 为了演示，我们直接使用 unit_name 作为显示名。
	
	# 构建队伍数据
	var selected_unit_names = selected_units.duplicate()
	var main_index = 0
	GameState.initialize_party(selected_unit_names, main_index)
	# 设置阵营：从主单位的配置文件读取
	var main_unit_data = UnitDataManager.get_unit_data(main_unit_name)
	var faction = main_unit_data.get("faction", "王国")   # 若未配置，默认“王国”
	GameState.current_faction = faction
	
	# 继续原有保存和跳转逻辑
	var target_slot = -1
	if SaveManager.current_slot != -1:
		target_slot = SaveManager.current_slot
	elif Globals.pending_save_slot != -1:
		target_slot = Globals.pending_save_slot
	else:
		target_slot = SaveManager.find_empty_slot()
		if target_slot == -1:
			var dialog = AcceptDialog.new()
			dialog.dialog_text = "所有存档槽已满，请先删除一个存档。"
			add_child(dialog)
			dialog.popup_centered()
			return

	Globals.pending_save_slot = target_slot
	GameState.start_new_cycle()
	GameState.reset_progress()
	GameState.interrupt_state = 2
	SaveManager.save_game(target_slot, false)
	LevelManager.start_game()

func _on_back_pressed():
	MusicManager.stop_music()
	GameState.interrupt_state = 1
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")
