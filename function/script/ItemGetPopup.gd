extends CanvasLayer

@onready var panel = $ItemPanel
@onready var icon = $ItemPanel/BoxContainer/Icon
@onready var name_label = $ItemPanel/BoxContainer/Name
@onready var count_label = $ItemPanel/BoxContainer/Count

func show_item(item_id: String, count: int):
	var data = ItemManager.get_item_data(item_id)
	if not data:
		queue_free()
		return

	# ---- 锁定操作 ----
	Globals.is_item_get_popup_active = true

	# ---- 暂停背景音乐 ----
	MusicManager.pause_and_save()

	# ---- 播放获得道具音效 ----
	SoundManager.play_get_item_sound()

	# ---- 设置 UI ----
	icon.texture = data.icon
	name_label.text = data.name
	count_label.text = "x" + str(count)
	panel.visible = true

	# ---- 2 秒后自动关闭 ----
	await get_tree().create_timer(2.0).timeout

	# ---- 解除锁定 ----
	Globals.is_item_get_popup_active = false

	# ---- 恢复背景音乐 ----
	MusicManager.resume_saved()

	queue_free()
