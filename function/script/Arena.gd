extends CanvasLayer

signal closed

# ============================================================
#  难度 → 经验倍率
# ============================================================
const DIFFICULTY_EXP_MULTIPLIER : Dictionary = {
	"easy":   1.0,
	"normal": 1.5,
	"hard":   2.0,
}

# ============================================================
#  状态
# ============================================================
var _current_unit_type : String = ""
var _difficulty : String = "easy"

# ---- 手动拖拽状态 ----
var _is_dragging : bool = false
var _drag_source : Button = null
var _drag_meta : Dictionary = {}
var _drag_preview : Control = null
var _drag_grab_offset : Vector2 = Vector2.ZERO

# ============================================================
#  节点引用
# ============================================================
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/UnitListScroll/UnitList
@onready var selected_unit_label : Label = $Panel/VBox/MainHBox/CenterPanel/SelectedUnitLabel
@onready var slot_btn : Button = $Panel/VBox/MainHBox/CenterPanel/SlotContainer/TalentSlotBtn
@onready var talent_library : VBoxContainer = $Panel/VBox/MainHBox/TalentLibraryScroll/TalentLibrary
@onready var easy_btn : Button = $Panel/VBox/BottomBar/EasyBtn
@onready var normal_btn : Button = $Panel/VBox/BottomBar/NormalBtn
@onready var hard_btn : Button = $Panel/VBox/BottomBar/HardBtn

# ============================================================
#  生命周期
# ============================================================
func _ready():
	_build_unit_list()
	_refresh_center_panel()
	_refresh_talent_library()
	_update_difficulty_style()


# ============================================================
#  信号
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
	var talent_id = GameState.arena_target_talents.get(_current_unit_type, "")
	if talent_id == "":
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
		btn.set_meta("unit_type", unit_type)
		btn.pressed.connect(_on_unit_selected.bind(unit_type))
		unit_list.add_child(btn)

	if unlocked.size() > 0:
		_on_unit_selected(unlocked[0])


func _on_unit_selected(unit_type: String):
	_current_unit_type = unit_type

	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			child.modulate = Color.WHITE if ut == unit_type else Color(0.6, 0.6, 0.6, 1)

	_refresh_center_panel()
	_refresh_talent_library()


# ============================================================
#  中间：当前单位 + 词条槽
# ============================================================
func _refresh_center_panel():
	if _current_unit_type == "":
		selected_unit_label.text = "（未选择单位）"
		slot_btn.text = "空"
		slot_btn.modulate = Color(0.5, 0.5, 0.5, 1)
		return

	var display = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	var talent_id = GameState.arena_target_talents.get(_current_unit_type, "")

	selected_unit_label.text = "单位：" + display

	if talent_id == "":
		slot_btn.text = "空"
		slot_btn.modulate = Color(0.5, 0.5, 0.5, 1)
	else:
		var data = TalentManager.get_talent_data(talent_id)
		if data:
			var lv = TalentManager.get_talent_level(_current_unit_type, talent_id)
			var exp_in_lv = TalentManager.get_talent_exp_in_level(_current_unit_type, talent_id)
			var required = TalentManager.get_level_required_exp(_current_unit_type, talent_id)
			var is_max = TalentManager.is_talent_max_level(_current_unit_type, talent_id)

			if is_max:
				slot_btn.text = "Lv.%d %s  MAX" % [lv, data.display_name]
			else:
				slot_btn.text = "Lv.%d %s  %d/%d" % [lv, data.display_name, exp_in_lv, required]

			slot_btn.modulate = _get_talent_color(data.rarity)
		else:
			slot_btn.text = talent_id
			slot_btn.modulate = Color.WHITE


func _get_talent_color(rarity: String) -> Color:
	match rarity:
		"rare":      return Color(0.3, 0.6, 1.0, 1)
		"epic":      return Color(0.7, 0.3, 1.0, 1)
		"legendary": return Color(1.0, 0.7, 0.0, 1)
		_:           return Color.WHITE


# ============================================================
#  右侧：词条库
# ============================================================
func _refresh_talent_library():
	for child in talent_library.get_children():
		talent_library.remove_child(child)
		child.queue_free()

	var unlocked = Globals.get_unlocked_talents()
	if unlocked.is_empty():
		var hint = Label.new()
		hint.text = "（暂无解锁词条）"
		hint.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		hint.modulate = Color(0.6, 0.6, 0.6, 1)
		talent_library.add_child(hint)
		return

	var current_target = GameState.arena_target_talents.get(_current_unit_type, "")

	for talent_id in unlocked:
		var data = TalentManager.get_talent_data(talent_id)
		if not data:
			continue
		var btn = _make_talent_button(talent_id, data, current_target)
		talent_library.add_child(btn)


func _make_talent_button(talent_id: String, data, current_target: String) -> Button:
	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	btn.set_meta("slot_type", "library_talent")
	btn.set_meta("talent_id", talent_id)

	var is_current = (current_target == talent_id)
	var compatible = TalentManager.is_talent_compatible_with_unit(talent_id, _current_unit_type)
	var lv = TalentManager.get_talent_level(_current_unit_type, talent_id)

	var label_text = "Lv.%d %s" % [lv, data.display_name]

	if not compatible:
		btn.text = label_text
		btn.modulate = Color(0.35, 0.35, 0.35, 1)
		btn.disabled = true
	elif is_current:
		btn.text = label_text + "  (已选)"
		btn.modulate = Color(0.5, 0.8, 1.0, 1)
	else:
		btn.text = label_text
		btn.modulate = _get_talent_color(data.rarity)
		btn.pressed.connect(_on_talent_clicked.bind(talent_id))

	return btn


func _on_talent_clicked(talent_id: String):
	_set_target_talent(talent_id)


# ============================================================
#  拖拽逻辑
# ============================================================
func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = _viewport_mouse_pos()
		var btn = _find_control_at_position(mouse_pos)
		if btn:
			_start_drag(btn)

	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_end_drag()

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _current_unit_type != "":
			var pos = _viewport_mouse_pos()
			if slot_btn.get_global_rect().has_point(pos):
				_set_target_talent("")

	elif event is InputEventMouseMotion:
		if _is_dragging:
			_update_drag_preview()


func _viewport_mouse_pos() -> Vector2:
	return get_viewport().get_mouse_position()


func _find_control_at_position(pos: Vector2) -> Control:
	const BUFFER = 4

	for child in talent_library.get_children():
		if child is Button:
			if child.disabled:
				continue
			var rect = child.get_global_rect().grow(BUFFER)
			if rect.has_point(pos):
				return child

	return null


func _get_target_from_position(global_pos: Vector2) -> Control:
	const BUFFER = 4

	if slot_btn.get_global_rect().grow(BUFFER).has_point(global_pos):
		return slot_btn

	return null


func _start_drag(btn: Button):
	var slot_type = btn.get_meta("slot_type", "")
	var talent_id = btn.get_meta("talent_id", "")

	if slot_type != "library_talent":
		return
	if talent_id == "":
		return

	_drag_source = btn
	_drag_meta = {
		"slot_type": slot_type,
		"talent_id": talent_id,
		"source_control": btn,
	}

	var btn_rect = btn.get_global_rect()
	var btn_center = btn_rect.position + btn_rect.size / 2
	_drag_grab_offset = _viewport_mouse_pos() - btn_center

	_begin_dragging()


func _begin_dragging():
	if _is_dragging:
		return
	_is_dragging = true

	var btn = _drag_source
	if not btn:
		return

	btn.set_meta("_original_disabled", btn.disabled)
	btn.set_meta("_original_modulate", btn.modulate)
	btn.set_meta("_original_text", btn.text)
	btn.set_meta("_original_custom_minimum_size", btn.custom_minimum_size)

	var current_size = btn.custom_minimum_size
	if current_size == Vector2.ZERO or current_size.y < 10:
		current_size = btn.size
	if current_size.y < 10:
		current_size.y = 16
	btn.custom_minimum_size = current_size

	btn.disabled = true
	btn.modulate = Color(0.3, 0.3, 0.3, 1)
	btn.text = "空"

	_drag_preview = _create_drag_preview(btn)

	add_child(_drag_preview)
	_update_drag_preview()


func _create_drag_preview(btn: Button) -> Label:
	var preview = Label.new()

	preview.text = btn.get_meta("_original_text", "")

	var font_size = btn.get_theme_font_size("font_size")
	if font_size > 0:
		preview.add_theme_font_size_override("font_size", font_size)

	preview.autowrap_mode = btn.autowrap_mode
	preview.horizontal_alignment = btn.alignment
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var font_color = btn.get_theme_color("font_color")
	if font_color:
		preview.add_theme_color_override("font_color", font_color)
	preview.modulate = btn.get_meta("_original_modulate", Color.WHITE)

	var preview_size = btn.custom_minimum_size
	if preview_size == Vector2.ZERO or preview_size.y < 10:
		preview_size = btn.size
	if preview_size == Vector2.ZERO or preview_size.y < 10:
		preview_size = Vector2(80, 20)
	if preview_size.y < 14:
		preview_size.y = 14
	preview.size = preview_size

	var original_style = btn.get_theme_stylebox("normal")
	if original_style:
		var new_style = StyleBoxFlat.new()
		if original_style is StyleBoxFlat:
			var flat_style = original_style as StyleBoxFlat
			new_style.bg_color = flat_style.bg_color
			new_style.border_width_left = flat_style.border_width_left
			new_style.border_width_right = flat_style.border_width_right
			new_style.border_width_top = flat_style.border_width_top
			new_style.border_width_bottom = flat_style.border_width_bottom
			new_style.border_color = flat_style.border_color
		else:
			new_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
			new_style.border_width_left = 1
			new_style.border_width_right = 1
			new_style.border_width_top = 1
			new_style.border_width_bottom = 1
			new_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		preview.add_theme_stylebox_override("normal", new_style)

	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview


func _update_drag_preview():
	if not _drag_preview:
		return
	var mouse_pos = _viewport_mouse_pos()
	var preview_center = mouse_pos - _drag_grab_offset
	_drag_preview.position = preview_center - _drag_preview.size / 2
	_drag_preview.z_index = 100


func _end_drag():
	if not _is_dragging:
		return

	var mouse_pos = _viewport_mouse_pos()
	var target = _get_target_from_position(mouse_pos)
	var valid = target and _is_valid_drop(_drag_meta, target)
	var drop_data = _drag_meta.duplicate()

	if _drag_preview:
		_drag_preview.queue_free()
		_drag_preview = null
	_is_dragging = false

	if valid:
		_execute_drop.call_deferred(drop_data, target)
		SoundManager.play_select_sound()
	else:
		SoundManager.play_cancel_sound()
		if is_instance_valid(_drag_source):
			var original_disabled = _drag_source.get_meta("_original_disabled", false)
			var original_modulate = _drag_source.get_meta("_original_modulate", Color.WHITE)
			var original_text = _drag_source.get_meta("_original_text", "")
			var original_min_size = _drag_source.get_meta("_original_custom_minimum_size", Vector2.ZERO)
			_drag_source.disabled = original_disabled
			_drag_source.modulate = original_modulate
			_drag_source.text = original_text
			_drag_source.custom_minimum_size = original_min_size
			_drag_source.remove_meta("_original_disabled")
			_drag_source.remove_meta("_original_modulate")
			_drag_source.remove_meta("_original_text")
			_drag_source.remove_meta("_original_custom_minimum_size")
		_refresh_talent_library()

	_drag_source = null
	_drag_meta = {}


func _process(_delta):
	if _is_dragging:
		_update_drag_preview()


func _is_valid_drop(data: Dictionary, target: Control) -> bool:
	var src_type = data.get("slot_type", "")
	var talent_id = data.get("talent_id", "")

	if src_type != "library_talent":
		return false
	if talent_id == "":
		return false
	if target != slot_btn:
		return false

	if not TalentManager.is_talent_compatible_with_unit(talent_id, _current_unit_type):
		return false

	return true


func _execute_drop(data: Dictionary, _target: Control):
	var talent_id = data.get("talent_id", "")
	if talent_id == "":
		return
	_set_target_talent(talent_id)


# ============================================================
#  设置目标词条
# ============================================================
func _set_target_talent(talent_id: String):
	if _current_unit_type == "":
		return

	if talent_id != "":
		if not TalentManager.is_talent_compatible_with_unit(talent_id, _current_unit_type):
			return

	if talent_id == "":
		GameState.arena_target_talents.erase(_current_unit_type)
	else:
		GameState.arena_target_talents[_current_unit_type] = talent_id

	SaveManager.auto_save()

	_refresh_center_panel()
	_refresh_talent_library()


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
	var talent_id = GameState.arena_target_talents.get(_current_unit_type, "")

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
		# ---- 胜利：获得经验 ----
		var base_exp = _get_enemy_arena_exp(enemy_type)
		var multiplier = DIFFICULTY_EXP_MULTIPLIER.get(_difficulty, 1.0)
		var exp_gain = int(round(base_exp * multiplier))

		var actual_gain = TalentManager.add_talent_exp(_current_unit_type, talent_id, exp_gain)
		SaveManager.auto_save()

		if actual_gain > 0:
			var data = TalentManager.get_talent_data(talent_id)
			var display_name = data.display_name if data else talent_id
			_show_hint("胜利！%s +%d 经验" % [display_name, actual_gain])
		else:
			_show_hint("胜利！（词条已满级）")
	else:
		_show_hint("失败，无经验")

	_refresh_center_panel()
	_refresh_talent_library()


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


func _get_enemy_arena_exp(enemy_type: String) -> int:
	var unit_dict = UnitDataManager.get_unit_data(enemy_type)
	return int(unit_dict.get("arena_exp", 30))   # 默认 30


# ============================================================
#  辅助
# ============================================================
func _show_hint(text: String):
	selected_unit_label.text = text
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(selected_unit_label) and _current_unit_type != "":
		selected_unit_label.text = "单位：" + UnitDataManager.get_unit_type_display_name(_current_unit_type)
