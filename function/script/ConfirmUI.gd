extends CanvasLayer

@onready var message_label = $Panel/Message
@onready var confirm_button = $Panel/HBoxContainer/ConfirmButton
@onready var cancel_button = $Panel/HBoxContainer/CancelButton

var confirm_callback: Callable
var cancel_callback: Callable

func _ready():
	# 断开已有信号，防止重复连接
	for conn in confirm_button.pressed.get_connections():
		confirm_button.pressed.disconnect(conn.callable)
	for conn in cancel_button.pressed.get_connections():
		cancel_button.pressed.disconnect(conn.callable)
	
	confirm_button.pressed.connect(_on_confirm_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)

func show_confirm(message: String, confirm_text: String = "确定", cancel_text: String = "取消", confirm_cb: Callable = Callable(), cancel_cb: Callable = Callable(), show_cancel: bool = true):
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	confirm_callback = confirm_cb
	cancel_callback = cancel_cb
	
	cancel_button.visible = show_cancel
	
	# 两个按钮都居中，不扩展，保持内容宽度
	if show_cancel:
		confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _on_confirm_button_pressed() -> void:
	if confirm_callback.is_valid():
		confirm_callback.call()
	queue_free()

func _on_cancel_button_pressed() -> void:
	if cancel_callback.is_valid():
		cancel_callback.call()
	queue_free()
