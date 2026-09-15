extends CanvasLayer

signal closed

# ============================================================
#  状态
# ============================================================
var _current_unit_type : String = ""
var _selected_talent_id : String = ""
var _difficulty : String = "easy"

# ============================================================
#  节点引用
# ============================================================
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/UnitListScroll/UnitList
@onready var selected_unit_label : Label = $Panel/VBox/MainHBox/RightPanel/SelectedUnitLabel
@onready var talent_list : VBoxContainer = $Panel/VBox/MainHBox/RightPanel/TalentScroll/TalentList
@onready var easy_btn : Button = $Panel/VBox/MainHBox/RightPanel/DifficultyBar/EasyBtn
@onready var normal_btn : Button = $Panel/VBox/MainHBox/RightPanel/DifficultyBar/NormalBtn
@onready var hard_btn : Button = $Panel/VBox/MainHBox/RightPanel/DifficultyBar/HardBtn
@onready var start_btn : Button = $Panel/VBox/BottomBar/StartBtn


func _ready():
	_build_unit_list()
	_update_difficulty_style()


# ============================================================
#  信号（.tscn 连接）
# ============================================================
func _on_easy_pressed():
	_difficulty = "easy"
	_update_difficulty_style()

func _on_normal_pressed():
	_difficulty = "normal"
	_update_difficulty_style()

func _on_hard_pressed():
	_difficulty = "hard"
	_update_difficulty_style()

func _on_start_pressed():
	if _current_unit_type == "":
		_show_hint("请先选择单位")
		return
	if _selected_talent_id == "":
		_show_hint("请先选择目标词条")
		return
	_start_battle()

func _on_back_pressed():
	closed.emit()
	queue_free()


# ============================================================
#  左侧：单位列表
# ============================================================
func _build_unit_list():
	for child in unit_list.get_children():
		unit_list.remove_child(child)
		child.queue_free()

	var unlocked = Globals.get_unlocked_units()
	unlocked.sort()

	for unit_type in unlocked:
		var btn = Button.new()
		btn.text = UnitDataManager.get_unit_type_display_name(unit_type)
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_unit_selected.bind(unit_type))
		unit_list.add_child(btn)

	if unlocked.size() > 0:
		_on_unit_selected(unlocked[0])


func _on_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	_selected_talent_id = ""
	_refresh_talent_list()


# ============================================================
#  右侧：词条列表
# ============================================================
func _refresh_talent_list():
	var display = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	selected_unit_label.text = "单位：" + display

	for child in talent_list.get_children():
		talent_list.remove_child(child)
		child.queue_free()

	var unit_dict = UnitDataManager.get_unit_data(_current_unit_type)
	var talents = unit_dict.get("default_talents", [])

	if talents.is_empty():
		var hint = Label.new()
		hint.text = "（该单位没有词条）"
		hint.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		hint.modulate = Color(0.6, 0.6, 0.6)
		talent_list.add_child(hint)
		return

	for talent_id in talents:
		var data = TalentManager.get_talent_data(talent_id)
		if not data:
			continue
		talent_list.add_child(_build_talent_row(talent_id, data))


func _build_talent_row(talent_id: String, data) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var level = TalentManager.get_talent_level(_current_unit_type, talent_id)
	var usage = TalentManager.get_talent_usage(_current_unit_type, talent_id)
	var next_th = TalentManager.get_next_level_threshold(_current_unit_type, talent_id)

	var level_label = Label.new()
	level_label.text = "Lv.%d" % level
	level_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	level_label.custom_minimum_size = Vector2(30, 0)
	row.add_child(level_label)

	var name_label = Label.new()
	name_label.text = data.display_name
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	name_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(name_label)

	var progress_label = Label.new()
	if next_th < 0:
		progress_label.text = "已满级（使用 %d）" % usage
	else:
		progress_label.text = "%d / %d" % [usage, next_th]
	progress_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_label.modulate = Color(0.7, 0.7, 0.7)
	row.add_child(progress_label)

	var sel_btn = Button.new()
	sel_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	var style = load(Config.PATHS.STYLEBOX_8BIT)
	if style:
		sel_btn.add_theme_stylebox_override("normal", style)
		sel_btn.add_theme_stylebox_override("pressed", style)
		sel_btn.add_theme_stylebox_override("hover", style)
		sel_btn.add_theme_stylebox_override("disabled", style)
		sel_btn.add_theme_stylebox_override("focus", style)

	if _selected_talent_id == talent_id:
		sel_btn.text = "已选中"
		sel_btn.disabled = true
	else:
		sel_btn.text = "选中"
		sel_btn.pressed.connect(_on_talent_selected.bind(talent_id))
	row.add_child(sel_btn)

	return row


func _on_talent_selected(talent_id: String):
	_selected_talent_id = talent_id
	_refresh_talent_list()


# ============================================================
#  难度样式
# ============================================================
func _update_difficulty_style():
	easy_btn.modulate = Color.WHITE if _difficulty == "easy" else Color(0.5, 0.5, 0.5, 1)
	normal_btn.modulate = Color.WHITE if _difficulty == "normal" else Color(0.5, 0.5, 0.5, 1)
	hard_btn.modulate = Color.WHITE if _difficulty == "hard" else Color(0.5, 0.5, 0.5, 1)


# ============================================================
#  开始战斗
# ============================================================
func _start_battle():
	var player_data = UnitDataManager.create_unit_data(_current_unit_type)
	UnitDataManager.apply_growth(player_data, _current_unit_type)

	var enemy_type = _roll_enemy(_difficulty)
	if enemy_type == "":
		_show_hint("对手池为空")
		return
	var enemy_data = UnitDataManager.create_unit_data(enemy_type)

	var scene = load(Config.PATHS.ARENA_BATTLE_UI)
	if not scene:
		push_error("ArenaBattle 场景未找到")
		return
	var battle = scene.instantiate()
	add_child(battle)
	battle.setup(player_data, enemy_data)
	await battle.closed

	if battle.winner_team == 0:
		TalentManager.record_arena_win(_current_unit_type, _selected_talent_id)
		SaveManager.auto_save()
		_show_hint("胜利！词条使用次数 +1")
	else:
		_show_hint("失败，无奖励")

	_refresh_talent_list()


func _roll_enemy(difficulty: String) -> String:
	var path = Config.PATHS.ARENA_ENEMIES
	if not FileAccess.file_exists(path):
		return ""
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		return ""
	var pool = data.get(difficulty, [])
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


# ============================================================
#  辅助
# ============================================================
func _show_hint(text: String):
	var original = selected_unit_label.text
	selected_unit_label.text = text
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(selected_unit_label):
		selected_unit_label.text = original
