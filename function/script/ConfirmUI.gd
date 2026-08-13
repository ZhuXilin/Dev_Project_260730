extends CanvasLayer

@onready var message_label = $Panel/Message
@onready var confirm_button = $Panel/HBoxContainer/ConfirmButton
@onready var cancel_button = $Panel/HBoxContainer/CancelButton

func show_confirm(message: String, confirm_text: String = "确定", cancel_text: String = "取消", confirm_cb: Callable = Callable(), cancel_cb: Callable = Callable(), show_cancel: bool = true):
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text

	# 断开所有已存在的信号连接（避免重复触发）
	for conn in confirm_button.pressed.get_connections():
		confirm_button.pressed.disconnect(conn.callable)
	for conn in cancel_button.pressed.get_connections():
		cancel_button.pressed.disconnect(conn.callable)

	# 连接新回调（使用匿名函数防止捕获问题）
	confirm_button.pressed.connect(func():
		if confirm_cb.is_valid():
			confirm_cb.call()
		queue_free()
	)
	cancel_button.pressed.connect(func():
		if cancel_cb.is_valid():
			cancel_cb.call()
		queue_free()
	)

	cancel_button.visible = show_cancel
	if not show_cancel:
		confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
