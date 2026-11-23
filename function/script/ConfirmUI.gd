extends CanvasLayer

@onready var message_label = $Panel/Message
@onready var confirm_button = $Panel/HBoxContainer/ConfirmButton
@onready var cancel_button = $Panel/HBoxContainer/CancelButton

var confirm_callback: Callable
var cancel_callback: Callable
## ★ v6.53：双选项模式——两个回调分别对应"强化/转向"两个可点的结果卡片
var choice_a_callback: Callable = Callable()
var choice_b_callback: Callable = Callable()
var _choice_root: Control = null

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

func _exit_tree():
	# ★ 兜底：若确认框因场景切换/父节点释放而消失（非用户点击），
	#   也要清标志，否则会永久屏蔽战斗输入。正常点击时已提前清过，重复清无害。
	Globals.is_confirm_ui_active = false


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


## ★ v6.53：双选项模式——展示两个"结果预览卡片"，各带 图标/流派色块/数值/词条，
##   玩家点卡片即选对应动作（强化/转向），底部另有正常大小的取消按钮。
## data_a/data_b: {icon:Texture2D, school:String, color:Color, title:String, detail:String, affixes:Array, cb:Callable}
func show_choice(title: String, data_a: Dictionary, data_b: Dictionary, cancel_cb: Callable = Callable()) -> void:
	message_label.visible = false
	$Panel/HBoxContainer.visible = false

	_choice_root = VBoxContainer.new()
	_choice_root.name = "ChoiceRoot"
	_choice_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_root.offset_left = 48
	_choice_root.offset_right = -48
	_choice_root.offset_top = 32
	_choice_root.offset_bottom = -24
	_choice_root.add_theme_constant_override("separation", 10)
	$Panel.add_child(_choice_root)

	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 10)
	_choice_root.add_child(head)

	choice_a_callback = data_a.get("cb", Callable())
	choice_b_callback = data_b.get("cb", Callable())
	cancel_callback = cancel_cb

	_choice_root.add_child(_make_choice_card(data_a, true))
	_choice_root.add_child(_make_choice_card(data_b, false))

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(60, 20)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.add_theme_font_size_override("font_size", 8)
	cancel.pressed.connect(_on_cancel_button_pressed)
	_choice_root.add_child(cancel)


func _make_choice_card(data: Dictionary, is_a: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 56)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	var c : Color = data.get("color", Color.WHITE)
	sb.border_color = c
	sb.set_border_width_all(2)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_choice_picked(is_a))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	# 流派色块 + 防具图标（叠放，样式与其他防具一致）
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(20, 20)
	var color_rect := ColorRect.new()
	color_rect.color = c
	color_rect.set_anchors_preset(Control.PRESET_CENTER)
	color_rect.offset_left = -10
	color_rect.offset_right = 10
	color_rect.offset_top = -10
	color_rect.offset_bottom = 10
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(color_rect)
	var tex : Texture2D = data.get("icon")
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tr.set_anchors_preset(Control.PRESET_CENTER)
		tr.offset_left = -10
		tr.offset_right = 10
		tr.offset_top = -10
		tr.offset_bottom = 10
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(tr)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_box)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)
	var t1 := Label.new()
	t1.text = str(data.get("title", ""))
	t1.add_theme_font_size_override("font_size", 9)
	text_col.add_child(t1)
	var t2 := Label.new()
	t2.text = str(data.get("detail", ""))
	t2.add_theme_font_size_override("font_size", 7)
	t2.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(t2)
	return card


func _on_choice_picked(is_a: bool) -> void:
	visible = false
	Globals.is_confirm_ui_active = false
	SoundManager.play_select_sound()
	var cb : Callable = choice_a_callback if is_a else choice_b_callback
	if cb.is_valid():
		cb.call()
	queue_free.call_deferred()


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
