extends CanvasLayer

signal closed

# ============================================================
#  连胜参数
# ============================================================
## 敌人属性倍率 = 1.0 + streak * 此值
const ENEMY_SCALE_PER_STREAK : float = 0.15

## 经验倍率 = 1.0 + streak * 此值
const EXP_MULT_PER_STREAK : float = 0.2

# ============================================================
#  状态
# ============================================================
var _current_unit_type : String = ""
var _streak : int = 0
var _current_player_data : UnitData = null
var _locked_talent_id : String = ""
var _streak_active : bool = false

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
@onready var streak_label : Label = $Panel/VBox/MainHBox/CenterPanel/StreakLabel
@onready var talent_library : VBoxContainer = $Panel/VBox/MainHBox/RightColumn/TalentLibraryScroll/TalentLibrary

# ============================================================
#  生命周期
# ============================================================
func _ready():
	MusicManager.play_arena_music()
	_build_unit_list()
	_refresh_center_panel()
	_refresh_talent_library()
	_refresh_streak_label()


# ============================================================
#  信号
# ============================================================
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
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
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
	# ---- 连胜中不能换单位 ----
	if _streak_active:
		_show_hint("连胜中无法切换单位")
		_refresh_unit_list_highlight()
		return

	_current_unit_type = unit_type

	# ---- 重置玩家单位数据（满血） ----
	_current_player_data = UnitDataManager.create_unit_data(_current_unit_type)
	UnitDataManager.apply_growth(_current_player_data, _current_unit_type)

	_streak = 0
	_streak_active = false

	_refresh_unit_list_highlight()
	_refresh_center_panel()
	_refresh_talent_library()
	_refresh_streak_label()


func _refresh_unit_list_highlight():
	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			if ut == _current_unit_type:
				child.modulate = Color.WHITE
			else:
				child.modulate = Color(0.6, 0.6, 0.6, 1)


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

	# ---- 显示当前 HP ----
	if _current_player_data and _current_player_data.max_hp > 0:
		var hp = _current_player_data.hit_points
		var max_hp = _current_player_data.max_hp
		selected_unit_label.text = "单位：%s  HP %d/%d" % [display, hp, max_hp]
	else:
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

	# ---- 连胜中禁用词条槽 ----
	slot_btn.disabled = _streak_active


func _refresh_streak_label():
	var best = GameState.arena_best_streak
	if _streak <= 0:
		# ---- 未在连胜中：只显示历史最高 ----
		streak_label.text = "最高连胜：%d" % best
		streak_label.modulate = Color(0.6, 0.6, 0.6, 1)
	else:
		# ---- 连胜中：显示当前 + 最高 ----
		streak_label.text = "当前连胜：%d  |  最高：%d" % [_streak, best]
		streak_label.modulate = Color(1.0, 0.8, 0.2, 1)


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

	if _streak_active:
		btn.text = label_text
		btn.modulate = Color(0.35, 0.35, 0.35, 1)
		btn.disabled = true
	elif not compatible:
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
	if _streak_active:
		_show_hint("连胜中无法切换词条")
		return
	_set_target_talent(talent_id)


# ============================================================
#  拖拽逻辑
# ============================================================
func _input(event: InputEvent):
	if _streak_active:
		return

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
	if slot_type != "library_talent" or talent_id == "":
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
			_drag_source.disabled = _drag_source.get_meta("_original_disabled", false)
			_drag_source.modulate = _drag_source.get_meta("_original_modulate", Color.WHITE)
			_drag_source.text = _drag_source.get_meta("_original_text", "")
			_drag_source.custom_minimum_size = _drag_source.get_meta("_original_custom_minimum_size", Vector2.ZERO)
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
	if src_type != "library_talent" or talent_id == "" or target != slot_btn:
		return false
	if not TalentManager.is_talent_compatible_with_unit(talent_id, _current_unit_type):
		return false
	return true


func _execute_drop(data: Dictionary, _target: Control):
	var talent_id = data.get("talent_id", "")
	if talent_id == "":
		return
	_set_target_talent(talent_id)


func _set_target_talent(talent_id: String):
	if _current_unit_type == "":
		return
	if _streak_active:
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
#  开始战斗 + 连胜循环
# ============================================================
func _start_battle():
	if not _current_player_data:
		return

	var talent_id = GameState.arena_target_talents.get(_current_unit_type, "")
	if _streak_active:
		talent_id = _locked_talent_id

	# ---- 生成本场对手 ----
	var enemy_type = _roll_enemy(_streak)
	if enemy_type == "":
		_show_hint("对手池为空")
		return
	var enemy_data = UnitDataManager.create_unit_data(enemy_type)
	_apply_streak_scaling(enemy_data, _streak)

	# ---- 计算经验 ----
	var base_exp = _get_enemy_arena_exp(enemy_type)
	var exp_mult = 1.0 + _streak * EXP_MULT_PER_STREAK
	var exp_gain = int(round(base_exp * exp_mult))

	# ---- 打开战斗 ----
	var scene = load(Config.PATHS.ARENA_BATTLE_UI)
	if not scene:
		push_error("ArenaBattle 场景未找到")
		return
	var battle = scene.instantiate()
	add_child(battle)
	battle.setup(_current_player_data, enemy_data, exp_gain, _streak + 1)
	var result = await battle.closed

	# ---- 处理战斗结果 ----
	var winner_team = result.get("winner_team", -1)
	var remaining_hp = result.get("remaining_hp", 0)
	var continue_requested = result.get("continue_requested", false)

	if winner_team == 0:
		# ---- 胜利 ----
		if not _streak_active:
			_locked_talent_id = talent_id
			_streak_active = true

		_streak += 1

		# ---- 加经验 ----
		var old_level = TalentManager.get_talent_level(_current_unit_type, _locked_talent_id)
		var actual_gain = TalentManager.add_talent_exp(_current_unit_type, _locked_talent_id, exp_gain)
		var new_level = TalentManager.get_talent_level(_current_unit_type, _locked_talent_id)

		# ---- 更新最高连胜 ----
		var is_new_record = false
		if _streak > GameState.arena_best_streak:
			GameState.arena_best_streak = _streak
			is_new_record = true

		SaveManager.auto_save()

		# ---- 提示（升级 > 新纪录 > 普通胜利） ----
		if new_level > old_level:
			var data = TalentManager.get_talent_data(_locked_talent_id)
			var display_name = data.display_name if data else _locked_talent_id
			_show_hint("词条升级！%s → Lv.%d" % [display_name, new_level])
		elif is_new_record:
			_show_hint("新纪录！最高连胜 %d" % _streak)
		elif actual_gain > 0:
			_show_hint("胜利 +%d 经验" % actual_gain)

		if continue_requested:
			# ---- 残血继续 ----
			_current_player_data.hit_points = remaining_hp
			_refresh_center_panel()
			_refresh_streak_label()
			await get_tree().process_frame
			_start_battle()
		else:
			# ---- 玩家选择返回 ----
			_reset_streak()
	else:
		# ---- 失败 ----
		_show_hint("失败，连胜终止")
		_reset_streak()

	_refresh_center_panel()
	_refresh_talent_library()
	_refresh_streak_label()


func _reset_streak():
	_streak = 0
	_streak_active = false
	_locked_talent_id = ""

	# ---- 恢复满血 ----
	if _current_unit_type != "":
		_current_player_data = UnitDataManager.create_unit_data(_current_unit_type)
		UnitDataManager.apply_growth(_current_player_data, _current_unit_type)


func _roll_enemy(streak: int) -> String:
	var path = Config.PATHS.ARENA_ENEMIES
	if not FileAccess.file_exists(path):
		return ""
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		return ""

	# ---- 连胜段位决定池子 ----
	var pool_key : String
	if streak >= 5:
		pool_key = "hard"
	elif streak >= 2:
		pool_key = "normal"
	else:
		pool_key = "easy"

	var pool = data.get(pool_key, [])
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


func _apply_streak_scaling(enemy_data: UnitData, streak: int):
	if streak <= 0:
		return
	var mult = 1.0 + streak * ENEMY_SCALE_PER_STREAK
	enemy_data.max_hp = int(enemy_data.max_hp * mult)
	enemy_data.hit_points = enemy_data.max_hp
	enemy_data.strength = int(enemy_data.strength * mult)
	enemy_data.dexterity = int(enemy_data.dexterity * mult)


func _get_enemy_arena_exp(enemy_type: String) -> int:
	var unit_dict = UnitDataManager.get_unit_data(enemy_type)
	return int(unit_dict.get("arena_exp", 30))


# ============================================================
#  辅助
# ============================================================
func _show_hint(text: String):
	selected_unit_label.text = text
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(selected_unit_label):
		_refresh_center_panel()
