extends Node

# ============================================================
#  DialogueManager — 纯播放器
#  职责：接收 lines / choices，驱动 DialogueUI
#  数据加载、条件判断、去重、effect 全部由 StoryManager 负责
#  对外唯一入口：
#    start_inline_dialogue(lines, music_stream)
#    start_inline_dialogue_with_choices(lines, choices, music_stream)
# ============================================================

@export var music_transition_delay : float = 0.5

const NPC_AVATAR_MAP : Dictionary = {
	"守火者": "soul_keeper",
	"灰烬铁匠": "blacksmith",
	"游魂向导": "guide",
	"角斗士": "gladiator",
	"兜帽商人": "secret_merchant",
	"村长": "villager", # 如果有对应图片
}

var dialogue_ui : CanvasLayer = null
var dialogue_panel : Panel = null
var name_label : Label = null
var text_label : Label = null
var _choice_container : VBoxContainer = null

# v4.6：当前播放的台词列表（不再依赖 _dialogues 字典）
var _current_entries : Array = []
var current_index : int = 0
var is_active : bool = false
var can_interact : bool = false

var _pending_choices : Array = []

signal dialogue_finished
signal choice_selected(index: int, data: Dictionary)


func _ready():
	call_deferred("_load_ui")


func has_pending_choices() -> bool:
	return not _pending_choices.is_empty()


# ============================================================
#  启动（唯一入口）
# ============================================================
func start_inline_dialogue(entries: Array, music_stream: AudioStream = null):
	if entries.is_empty():
		dialogue_finished.emit()
		return

	if not dialogue_ui or not is_instance_valid(dialogue_ui):
		_load_ui()
		if not dialogue_ui or not is_instance_valid(dialogue_ui):
			push_error("[DialogueManager] DialogueUI 未加载，无法启动对话")
			return

	if is_active:
		return

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

	_current_entries = entries
	current_index = 0
	_show_entry(0)
	can_interact = true


func start_inline_dialogue_with_choices(entries: Array, choices: Array, music_stream: AudioStream = null):
	_pending_choices = choices.duplicate()
	start_inline_dialogue(entries, music_stream)


# ============================================================
#  兼容接口（废弃，重定向到 StoryManager）
# ============================================================
func start_dialogue(dialogues_id: String, _music_stream: AudioStream = null):
	push_warning("[DialogueManager] start_dialogue 已废弃，请用 StoryManager.play_dialogue_by_id：%s" % dialogues_id)
	if StoryManager and StoryManager.has_method("play_dialogue_by_id"):
		StoryManager.play_dialogue_by_id(dialogues_id)


func has_dialogue(dialogues_id: String) -> bool:
	if StoryManager and StoryManager.has_method("has_dialogue"):
		return StoryManager.has_dialogue(dialogues_id)
	return false


# ============================================================
#  显示
# ============================================================
# 1. 修改 _show_entry 函数
func _show_entry(index: int):
	if index < 0 or index >= _current_entries.size():
		return
	var entry : Variant = _current_entries[index]
	if entry is Dictionary:
		var e : Dictionary = entry
		if name_label and text_label:
			var speaker : String = str(e.get("speaker", "???"))
			name_label.text = speaker
			text_label.text = str(e.get("text", "......"))
			_update_dialogue_avatar(speaker) # ★ 调用头像更新

# 2. 新增头像更新与排版逻辑
func _update_dialogue_avatar(speaker: String):
	var avatar_bg = dialogue_panel.get_node_or_null("AvatarBg")
	var avatar_rect = dialogue_panel.get_node_or_null("AvatarBg/AvatarRect")
	if not avatar_bg or not avatar_rect:
		return
		
	var tex : Texture2D = _resolve_speaker_avatar(speaker)
	
	if tex:
		avatar_rect.texture = tex
		avatar_bg.visible = true
		# 头像显示时，文本向右偏移留出空间
		name_label.offset_left = 62.0
		text_label.offset_left = 62.0
		if _choice_container:
			_choice_container.offset_left = 62.0
	else:
		avatar_bg.visible = false
		# 没有头像时，文本占满全屏
		name_label.offset_left = 16.0
		text_label.offset_left = 16.0
		if _choice_container:
			_choice_container.offset_left = 16.0

# 3. 新增头像资源智能加载逻辑
func _resolve_speaker_avatar(speaker: String) -> Texture2D:
	# 过滤掉没有实体的说话者
	if speaker == "" or speaker == "???" or speaker == "系统" or speaker == "指挥官":
		return null
		
	var avatar_id := ""
	
	# 策略 1：优先查是不是可上阵单位（如 艾琳、罗兰）
	var unit_key = UnitDataManager.normalize_unit_key(speaker)
	if not UnitDataManager.get_unit_data(unit_key).is_empty():
		avatar_id = GameState.get_unit_avatar(unit_key)
	else:
		# 策略 2：如果不是单位，查是不是剧情 NPC（如 守火者、铁匠）
		avatar_id = StoryManager.get_npc_avatar_id(speaker)
		
	if avatar_id == "":
		return null
		
	# 加载统一路径的头像
	var path = "res://content/images/characters/avatar/%s.png" % avatar_id
	print("[对话头像] 说话者: ", speaker, " | 尝试加载: ", avatar_id)
	if ResourceLoader.exists(path):
		return load(path)
		
	# 兼容：如果是旧的 sanctuary 目录下的 NPC 图，也支持读取
	var backup_path = "res://content/images/sanctuary/%s.png" % avatar_id
	if ResourceLoader.exists(backup_path):
		return load(backup_path)
		
	return null


# ============================================================
#  输入
# ============================================================
func _input(event: InputEvent):
	if not is_active or not can_interact:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _current_entries.is_empty():
			_close_dialogue()
			return
		current_index += 1
		if current_index < _current_entries.size():
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

	# 记录 flag（如果有）—— 委托给 StoryManager
	var flag : String = str(c.get("flag", ""))
	if flag != "" and StoryManager and StoryManager.has_method("record_choice"):
		StoryManager.record_choice("", flag)

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
	_current_entries = []
	current_index = 0
	dialogue_finished.emit()


func reset():
	if is_active:
		_close_dialogue()
	is_active = false
	can_interact = false
	Globals.is_dialogue_active = false
	_current_entries = []
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

	print("[DialogueManager] 已重置")


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
			print("[DialogueManager] 复用已存在的 DialogueUI")
			return
		existing.queue_free()
		dialogue_ui = null

	var ui_scene = load(Config.PATHS.DIALOGUE_UI)
	if not ui_scene:
		push_error("[DialogueManager] 无法加载 DialogueUI.tscn")
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
		push_error("[DialogueManager] DialogueUI 缺少必要节点")
		dialogue_ui.queue_free()
		dialogue_ui = null
		return

	PanelRevealer.force_hide(dialogue_panel)
	print("[DialogueManager] 创建 DialogueUI 实例（挂到 root 下）")
