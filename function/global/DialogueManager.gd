extends Node

@export var music_transition_delay : float = 0.5
@export var json_path : String = Config.PATHS.DIALOGUE_DATA

var dialogue_ui : CanvasLayer = null
var dialogue_panel : Panel = null
var name_label : Label = null
var text_label : Label = null
var _choice_container : VBoxContainer = null
var _dialogues : Dictionary = {}
var current_dialogue_id : String = ""
var current_index : int = 0
var is_active : bool = false
var can_interact : bool = false

var _pending_choices : Array = []

var _default_dialogue = [{"speaker": "???", "text": "......"}]

signal dialogue_finished
signal choice_selected(index: int, data: Dictionary)


func _ready():
	_load_dialogues()
	call_deferred("_load_ui")


func _load_dialogues():
	if not FileAccess.file_exists(json_path):
		push_error("对话 JSON 文件不存在: ", json_path)
		return
	var file = FileAccess.open(json_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("JSON 解析失败或格式错误")
		return
	_dialogues = data
	print("成功加载 ", _dialogues.size(), " 个对话事件")


func _get_dialogue_entries(dialogue_id: String) -> Array:
	if _dialogues.has(dialogue_id) and _dialogues[dialogue_id].size() > 0:
		return _dialogues[dialogue_id]
	else:
		print("警告：对话 ", dialogue_id, " 不存在，使用默认对话")
		return _default_dialogue


func has_dialogue(dialogues_id: String) -> bool:
	return _dialogues.has(dialogues_id) and _dialogues[dialogues_id].size() > 0


func has_pending_choices() -> bool:
	return not _pending_choices.is_empty()


# ============================================================
#  启动
# ============================================================
func start_dialogue(dialogues_id: String, music_stream: AudioStream = null):
	if not dialogue_ui or not is_instance_valid(dialogue_ui):
		_load_ui()
		if not dialogue_ui or not is_instance_valid(dialogue_ui):
			push_error("Dialogue UI 未加载，无法启动对话")
			return

	var entries = _get_dialogue_entries(dialogues_id)
	if entries.is_empty():
		print("警告：对话 ", dialogues_id, " 无条目，跳过")
		dialogue_finished.emit()
		return

	if is_active:
		return

	SignalBus.request_hide_menu.emit()
	SignalBus.request_hide_info.emit()
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_clear_highlight_unit.emit()

	is_active = true
	can_interact = false
	Globals.is_dialogue_active = true

	if dialogue_panel and is_instance_valid(dialogue_panel):
		PanelRevealer.show_panel(dialogue_panel)
	else:
		dialogue_ui.visible = true

	MusicManager.pause_and_save()
	await get_tree().create_timer(music_transition_delay, true, false, true).timeout
	if music_stream != null:
		MusicManager.play_music(music_stream)
	else:
		MusicManager.play_dialogue_music()

	current_dialogue_id = dialogues_id
	current_index = 0
	_show_entry(0)
	can_interact = true


func start_inline_dialogue(entries: Array, music_stream: AudioStream = null):
	if entries.is_empty():
		dialogue_finished.emit()
		return

	if not dialogue_ui or not is_instance_valid(dialogue_ui):
		_load_ui()
		if not dialogue_ui or not is_instance_valid(dialogue_ui):
			push_error("Dialogue UI 未加载，无法启动对话")
			return

	if is_active:
		return

	SignalBus.request_hide_menu.emit()
	SignalBus.request_hide_info.emit()
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_clear_highlight_unit.emit()

	is_active = true
	can_interact = false
	Globals.is_dialogue_active = true

	if dialogue_panel and is_instance_valid(dialogue_panel):
		PanelRevealer.show_panel(dialogue_panel)
	else:
		dialogue_ui.visible = true

	MusicManager.pause_and_save()
	await get_tree().create_timer(music_transition_delay, true, false, true).timeout
	if music_stream != null:
		MusicManager.play_music(music_stream)
	else:
		MusicManager.play_dialogue_music()

	current_dialogue_id = "__inline__"
	_dialogues["__inline__"] = entries
	current_index = 0
	_show_entry(0)
	can_interact = true


func start_inline_dialogue_with_choices(entries: Array, choices: Array, music_stream: AudioStream = null):
	_pending_choices = choices.duplicate()
	start_inline_dialogue(entries, music_stream)


# ============================================================
#  显示
# ============================================================
func _show_entry(index: int):
	var entries = _get_dialogue_entries(current_dialogue_id)
	if index < entries.size():
		var entry = entries[index]
		if name_label and text_label:
			name_label.text = entry.get("speaker", "???")
			text_label.text = entry.get("text", "......")


# ============================================================
#  输入
# ============================================================
func _input(event: InputEvent):
	if not is_active or not can_interact:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var entries = _get_dialogue_entries(current_dialogue_id)
		if entries.is_empty():
			_close_dialogue()
			return
		current_index += 1
		if current_index < entries.size():
			_show_entry(current_index)
		else:
			_close_dialogue()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_close_dialogue()


# ============================================================
#  选项
# ============================================================
func _show_choices():
	if not _choice_container or not is_instance_valid(_choice_container):
		_pending_choices = []
		_do_close()
		return

	if text_label:
		text_label.visible = false

	for child in _choice_container.get_children():
		_choice_container.remove_child(child)
		child.queue_free()

	for i in range(_pending_choices.size()):
		var c : Dictionary = _pending_choices[i]
		var btn := Button.new()
		btn.text = "· " + str(c.get("text", "..."))
		btn.add_theme_font_size_override("font_size", 8)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choice_container.add_child(btn)

	_choice_container.visible = true
	can_interact = false


func _on_choice_pressed(index: int):
	if index < 0 or index >= _pending_choices.size():
		return
	var c : Dictionary = _pending_choices[index]
	for child in _choice_container.get_children():
		_choice_container.remove_child(child)
		child.queue_free()
	_choice_container.visible = false
	if text_label:
		text_label.visible = true
	_pending_choices = []
	can_interact = true
	choice_selected.emit(index, c)
	_do_close()


# ============================================================
#  关闭
# ============================================================
func _close_dialogue():
	if not _pending_choices.is_empty():
		_show_choices()
		return
	_do_close()


func _do_close():
	is_active = false
	can_interact = false
	Globals.is_dialogue_active = false

	if dialogue_panel and is_instance_valid(dialogue_panel):
		PanelRevealer.hide_panel(dialogue_panel)
	elif dialogue_ui and is_instance_valid(dialogue_ui):
		dialogue_ui.visible = false

	MusicManager.stop_music()
	await get_tree().create_timer(music_transition_delay, true, false, true).timeout
	MusicManager.resume_saved()
	dialogue_finished.emit()


func reset():
	if is_active:
		_close_dialogue()
	is_active = false
	can_interact = false
	Globals.is_dialogue_active = false
	current_dialogue_id = ""
	current_index = 0
	_pending_choices = []
	if _choice_container and is_instance_valid(_choice_container):
		for child in _choice_container.get_children():
			_choice_container.remove_child(child)
			child.queue_free()
		_choice_container.visible = false
	if text_label:
		text_label.visible = true

	if dialogue_panel and is_instance_valid(dialogue_panel):
		PanelRevealer.force_hide(dialogue_panel)
	elif dialogue_ui and is_instance_valid(dialogue_ui):
		dialogue_ui.visible = false

	print("DialogueManager 已重置")


# ============================================================
#  加载 UI
# ============================================================
func _load_ui():
	if dialogue_ui != null and is_instance_valid(dialogue_ui):
		return

	var root = get_tree().root
	var existing = root.get_node_or_null("DialogueUI_Instance")
	if existing:
		dialogue_ui = existing
		name_label = dialogue_ui.get_node("DialoguePanel/NameLabel") as Label
		text_label = dialogue_ui.get_node("DialoguePanel/TextLabel") as Label
		dialogue_panel = dialogue_ui.get_node("DialoguePanel") as Panel
		_choice_container = dialogue_ui.get_node_or_null("DialoguePanel/ChoiceContainer") as VBoxContainer
		if name_label and text_label and dialogue_panel:
			PanelRevealer.force_hide(dialogue_panel)
			print("DialogueManager: 复用已存在的 DialogueUI")
			return
		existing.queue_free()
		dialogue_ui = null

	var ui_scene = load(Config.PATHS.DIALOGUE_UI)
	if not ui_scene:
		push_error("无法加载 DialogueUI.tscn，请确保路径正确")
		return

	dialogue_ui = ui_scene.instantiate()
	dialogue_ui.name = "DialogueUI_Instance"
	dialogue_ui.layer = 100
	root.add_child(dialogue_ui)

	name_label = dialogue_ui.get_node("DialoguePanel/NameLabel") as Label
	text_label = dialogue_ui.get_node("DialoguePanel/TextLabel") as Label
	dialogue_panel = dialogue_ui.get_node("DialoguePanel") as Panel
	_choice_container = dialogue_ui.get_node_or_null("DialoguePanel/ChoiceContainer") as VBoxContainer
	if not name_label or not text_label or not dialogue_panel:
		push_error("DialogueUI 缺少必要节点")
		dialogue_ui.queue_free()
		dialogue_ui = null
		return

	PanelRevealer.force_hide(dialogue_panel)
	print("DialogueManager: 创建 DialogueUI 实例（挂到 root 下）")
