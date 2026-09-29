extends TestPlugin

var _selected_id : String = ""


func get_key() -> String: return "dialogue"
func get_category() -> String: return "UI 组件"
func get_display_name() -> String: return "对话"


func build_params(container: VBoxContainer, on_ready: Callable):
	container.add_child(_make_label("点击对话直接播放"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(vbox)
	container.add_child(scroll)

	var ids : Array = _load_ids()
	if ids.is_empty():
		vbox.add_child(_make_label("（无对话）", 7))
		on_ready.call()
		return

	for did in ids:
		var btn := _make_button(did)
		btn.clip_text = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_dialogue_clicked.bind(did))
		vbox.add_child(btn)

	on_ready.call()


func _on_dialogue_clicked(did: String):
	_selected_id = did
	_play_dialogue()


func _play_dialogue():
	if _selected_id == "":
		return

	# ★ 隐藏 TestHarness
	var harness := _get_harness()
	if harness:
		harness.visible = false

	# 播放对话
	DialogueManager.start_dialogue(_selected_id)
	await DialogueManager.dialogue_finished

	# ★ 恢复 TestHarness
	if harness and is_instance_valid(harness):
		harness.visible = true


func validate() -> String:
	return ""


func launch():
	# 若用户在"启动"按钮触发（而不是点击列表），也播放当前选中的
	_play_dialogue()


func _load_ids() -> Array:
	var path = Config.PATHS.DIALOGUE_DATA
	if not FileAccess.file_exists(path):
		return []
	var file = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary):
		return []
	var ids : Array = data.keys()
	ids.sort()
	return ids

func get_status_text() -> String:
	if _selected_id == "":
		return "点击对话播放"
	return "已播放：" + _selected_id
