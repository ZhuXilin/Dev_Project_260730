extends CanvasLayer

@onready var message_label = $Panel/Message
@onready var confirm_button = $Panel/HBoxContainer/ConfirmButton
@onready var cancel_button = $Panel/HBoxContainer/CancelButton

var confirm_callback: Callable
var cancel_callback: Callable

# function/script/ConfirmUI.gd

func _ready():
	# ★ 强制显示系统鼠标：ConfirmUI 可能在战斗场景（鼠标被 CursorController 隐藏）弹出
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_confirm_ui_active = true

	# 去除按钮的焦点高亮（防止默认出现白框）
	confirm_button.focus_mode = Control.FOCUS_NONE
	cancel_button.focus_mode = Control.FOCUS_NONE

	for conn in confirm_button.pressed.get_connections():
		confirm_button.pressed.disconnect(conn.callable)
	for conn in cancel_button.pressed.get_connections():
		cancel_button.pressed.disconnect(conn.callable)

	confirm_button.pressed.connect(_on_confirm_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)


func _on_confirm_button_pressed() -> void:
	visible = false
	Globals.is_confirm_ui_active = false   # ★ 先清标志，再触发 callback
	SoundManager.play_select_sound()
	if confirm_callback.is_valid():
		confirm_callback.call()
	queue_free.call_deferred()


func _on_cancel_button_pressed() -> void:
	visible = false
	Globals.is_confirm_ui_active = false   # ★
	if cancel_callback.is_valid():
		cancel_callback.call()
	queue_free.call_deferred()

func _input(event):
	if not visible:
		return
		
	# ★ 统一处理 ESC 和 鼠标右键，均视为“取消”
	var is_cancel = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			is_cancel = true
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_cancel = true

	if is_cancel:
		get_viewport().set_input_as_handled()
		# 播放正确的取消音效
		SoundManager.play_cancel_sound()
		_on_cancel_button_pressed()

func show_confirm(message: String, confirm_text: String = "确定", cancel_text: String = "取消", confirm_cb: Callable = Callable(), cancel_cb: Callable = Callable(), show_cancel: bool = true, font_size: int = 0):
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	confirm_callback = confirm_cb
	cancel_callback = cancel_cb

	if font_size > 0:
		message_label.add_theme_font_size_override("font_size", font_size)

	cancel_button.visible = show_cancel

	if show_cancel:
		confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


## v5.13：在弹窗中展示"将获得"的防具图标（水平居中，位于文字与按钮之间）。
## texture 为 ItemData.icon（ItemManager 加载时已转好的 Texture2D），传空则不显示。
func set_item_icon(texture: Texture2D) -> void:
	if texture == null:
		return
	var rect := TextureRect.new()
	rect.name = "RewardIcon"
	rect.texture = texture
	# ★ v5.14：保持图标原始尺寸（16x16），不放大；按纹理原大小绘制。
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 水平居中，垂直放在中下部（文字区在下边界之上、按钮行之上）
	rect.anchor_left = 0.5
	rect.anchor_right = 0.5
	rect.anchor_top = 0.5
	rect.anchor_bottom = 0.5
	var tex_size : Vector2 = texture.get_size()
	var half_w : float = tex_size.x * 0.5
	var half_h : float = tex_size.y * 0.5
	rect.offset_left = -half_w
	rect.offset_right = half_w
	rect.offset_top = 8.0 - half_h
	rect.offset_bottom = 8.0 + half_h
	$Panel.add_child(rect)
