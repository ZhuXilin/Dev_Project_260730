extends TestPlugin

# ============================================================
#  ChipMusicTestPlugin — 预览 chip_music JSON
#  - 从 MusicManager 的扫描结果拉取列表
#  - 点击即播放
# ============================================================

var _player: ChipMusicPlayer = null
var _playing: bool = false
var _current_slot: String = ""
var _status_label: Label = null
var _list_vbox: VBoxContainer = null
var _on_ready: Callable = Callable()


func get_key() -> String: return "chip_music"
func get_category() -> String: return "音频"
func get_display_name() -> String: return "8-bit 音乐"


func on_deactivate():
	_stop()


func get_status_text() -> String:
	if _playing:
		return "▶ " + _current_slot
	return "未播放"


func build_params(container: VBoxContainer, on_ready: Callable):
	_on_ready = on_ready

	if _player == null:
		_player = ChipMusicPlayer.new()
		_attach_to_root(_player)

	# 顶部按钮
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)

	var refresh_btn := _make_button("重新扫描", 7)
	refresh_btn.pressed.connect(func():
		MusicManager.rescan_chip_music()
		_rebuild_list()
		if _on_ready.is_valid():
			_on_ready.call()
	)
	btn_row.add_child(refresh_btn)

	var stop_btn := _make_button("停止", 7)
	stop_btn.pressed.connect(func():
		_stop()
		if _on_ready.is_valid():
			_on_ready.call()
	)
	btn_row.add_child(stop_btn)

	container.add_child(btn_row)

	# 状态标签
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 7)
	_status_label.modulate = Color(0.75, 0.85, 1.0)
	_status_label.text = "点击列表播放"
	container.add_child(_status_label)

	# 列表
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(_list_vbox)

	_rebuild_list()
	on_ready.call()


func validate() -> String:
	var slots: Array = MusicManager.get_chip_slots()
	if slots.is_empty():
		return "未找到 chip JSON（请放到 content/music/ 或 content/sound/）"
	return ""


func launch():
	pass


func _rebuild_list():
	if _list_vbox == null:
		return
	for c in _list_vbox.get_children():
		_list_vbox.remove_child(c)
		c.queue_free()

	var slots: Array = MusicManager.get_chip_slots()
	slots.sort()

	if slots.is_empty():
		var hint := _make_label("（无 chip JSON）", 7)
		hint.modulate = Color(0.6, 0.6, 0.6)
		_list_vbox.add_child(hint)
		return

	for slot in slots:
		var btn := _make_button(slot, 7)
		btn.clip_text = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_slot_clicked.bind(slot))
		_list_vbox.add_child(btn)


func _on_slot_clicked(slot: String):
	_stop()
	var path: String = MusicManager._chip_slot_map.get(slot, "")
	if path == "":
		return
	var song := ChipSong.from_json(path)
	if song == null:
		_status_label.text = "❌ 解析失败: " + path
		return

	# ★ 停掉当前背景音乐（避免混音）
	MusicManager.stop_music()

	_player.play_song(song)
	_player.set_volume(Globals.music_volume)
	_playing = true
	_current_slot = slot
	_status_label.text = "▶ %s  (%.1fs, %d 事件, BPM %.0f)" % [
		slot, song.get_duration_seconds(), song.events.size(), song.bpm
	]
	if _on_ready.is_valid():
		_on_ready.call()


func _stop():
	if _player and _player.is_playing():
		_player.stop()
	_playing = false
	_current_slot = ""
	if _status_label:
		_status_label.text = "已停止"
