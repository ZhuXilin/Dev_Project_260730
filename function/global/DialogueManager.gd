extends Node

@export var music_transition_delay : float = 0.5
@export var json_path : String = Config.PATHS.DIALOGUE_DATA

var dialogue_ui : CanvasLayer = null
var name_label : Label = null
var text_label : Label = null
var _dialogues : Dictionary = {}
var current_dialogue_id : String = ""
var current_index : int = 0
var is_active : bool = false
var can_interact : bool = false

# ---- 默认对话（当请求的 ID 不存在时使用） ----
var _default_dialogue = [{"speaker": "???", "text": "......"}]

signal dialogue_finished

func _ready():
	_load_dialogues()
	call_deferred("_load_ui")

# ---- 加载对话 JSON ----
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

# ---- 获取对话条目（若不存在则返回默认） ----
func _get_dialogue_entries(dialogue_id: String) -> Array:
	if _dialogues.has(dialogue_id) and _dialogues[dialogue_id].size() > 0:
		return _dialogues[dialogue_id]
	else:
		print("警告：对话 ", dialogue_id, " 不存在，使用默认对话")
		return _default_dialogue

# ---- 检查对话是否存在（保留兼容） ----
func has_dialogue(dialogues_id: String) -> bool:
	return _dialogues.has(dialogues_id) and _dialogues[dialogues_id].size() > 0

# ---- 启动对话 ----
func start_dialogue(dialogues_id: String, music_stream: AudioStream = null):
	if not dialogue_ui:
		_load_ui()
		if not dialogue_ui:
			push_error("Dialogue UI 未加载，无法启动对话")
			return
	
	var entries = _get_dialogue_entries(dialogues_id)
	if entries.is_empty():
		print("警告：对话 ", dialogues_id, " 无条目，跳过")
		dialogue_finished.emit()
		return

	if is_active:
		return

	# ---- 隐藏行动菜单 ----
	SignalBus.request_hide_menu.emit()
	
	# ---- 隐藏其他可能干扰的 UI ----
	SignalBus.request_hide_info.emit()
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_clear_highlight_unit.emit()

	is_active = true
	can_interact = false
	Globals.is_dialogue_active = true
	dialogue_ui.visible = true

	MusicManager.pause_and_save()
	await get_tree().create_timer(music_transition_delay).timeout
	if music_stream != null:
		MusicManager.play_music(music_stream)
	else:
		MusicManager.play_dialogue_music()

	current_dialogue_id = dialogues_id
	current_index = 0
	_show_entry(0)
	can_interact = true

# ---- 显示当前对话条目 ----
func _show_entry(index: int):
	var entries = _get_dialogue_entries(current_dialogue_id)
	if index < entries.size():
		var entry = entries[index]
		if name_label and text_label:
			name_label.text = entry.get("speaker", "???")
			text_label.text = entry.get("text", "......")

# ---- 输入处理 ----
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

# ---- 关闭对话 ----
func _close_dialogue():
	is_active = false
	can_interact = false
	Globals.is_dialogue_active = false
	if dialogue_ui:
		dialogue_ui.visible = false
	MusicManager.stop_music()
	dialogue_finished.emit()
	await get_tree().create_timer(music_transition_delay).timeout
	MusicManager.resume_saved()

func reset():
	if is_active:
		_close_dialogue()
	is_active = false
	can_interact = false
	Globals.is_dialogue_active = false
	current_dialogue_id = ""
	current_index = 0
	if dialogue_ui:
		dialogue_ui.visible = false
	print("DialogueManager 已重置")

# ---- 延迟加载 UI ----
func _load_ui():
	if dialogue_ui != null:
		return
	var ui_scene = load("res://content/scenes/ui/DialogueUI.tscn")
	if ui_scene:
		dialogue_ui = ui_scene.instantiate()
		var root = get_tree().current_scene
		if root:
			root.add_child(dialogue_ui)
			dialogue_ui.layer = 100
			name_label = dialogue_ui.get_node("DialoguePanel/NameLabel") as Label
			text_label = dialogue_ui.get_node("DialoguePanel/TextLabel") as Label
			if not name_label or not text_label:
				push_error("DialogueUI 缺少 NameLabel 或 TextLabel 节点")
				dialogue_ui.queue_free()
				dialogue_ui = null
			else:
				dialogue_ui.visible = false
		else:
			push_error("无法获取当前场景根节点，请确保 DialogueManager 在场景树中")
	else:
		push_error("无法加载 DialogueUI.tscn，请确保路径正确")
