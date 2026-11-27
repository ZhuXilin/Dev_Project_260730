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
## ★ v6.68b：二选一场景可关闭 ESC/右键的"取消"语义，避免误触把选择当成取消。
var _esc_cancel_enabled: bool = true

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
	if not visible or not _esc_cancel_enabled:
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

func show_confirm(message: String, confirm_text: String = "确定", cancel_text: String = "取消", confirm_cb: Callable = Callable(), cancel_cb: Callable = Callable(), show_cancel: bool = true, font_size: int = 0, esc_cancel: bool = true):
	_esc_cancel_enabled = esc_cancel
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
## ★ v6.62：新增 horizontal（两卡左右排列）+ avatar_unit（用单位头像而非图标/战场图）
func show_choice(title: String, data_a: Dictionary, data_b: Dictionary, cancel_cb: Callable = Callable(), horizontal: bool = false) -> void:
	_esc_cancel_enabled = true
	message_label.visible = false
	$Panel/HBoxContainer.visible = false

	_choice_root = VBoxContainer.new()
	_choice_root.name = "ChoiceRoot"
	_choice_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ★ v6.72at：ConfirmUI 回到「全屏无边框」形态（400×240 铺底图），
	#   动态内容按全屏给内缩：左右 40、上 36、下 48（给取消按钮留出位置）。
	_choice_root.offset_left = 40
	_choice_root.offset_right = -40
	_choice_root.offset_top = 36
	_choice_root.offset_bottom = -48
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

	# ★ v6.62：横向模式用 HBox 并排两张卡；默认仍 VBox（兼容防具强化/转向）
	var cards_box : BoxContainer
	if horizontal:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cards_box = hbox
	else:
		cards_box = _choice_root
	if cards_box != _choice_root:
		_choice_root.add_child(cards_box)
	cards_box.add_child(_make_choice_card(data_a, true))
	cards_box.add_child(_make_choice_card(data_b, false))

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(64, 24)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.add_theme_font_size_override("font_size", 8)
	cancel.pressed.connect(_on_cancel_button_pressed)
	_choice_root.add_child(cancel)


func _make_choice_card(data: Dictionary, is_a: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var avatar_unit : String = str(data.get("avatar_unit", ""))
	# ★ v6.62e：avatar 模式两张卡固定同宽（画面 400px，两卡+间距放得下），保证大小统一
	card.custom_minimum_size = Vector2(140, 96) if avatar_unit != "" else Vector2(0, 56)
	var c : Color = data.get("color", Color.WHITE)
	# ★ v6.72ak：卡片不再硬编码 StyleBoxFlat（bg/边框/圆角/边距），
	#   统一套 8bit 卡片皮肤——样式参数全在 8bit_style_box_card.tres 里。
	var card_sb := load(Config.PATHS.STYLEBOX_8BIT_CARD)
	if card_sb:
		card.add_theme_stylebox_override("panel", card_sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_choice_picked(is_a))
	# ★ v6.62：卡片 hover 时整体提亮，明确可点击（不再改边框色）
	card.mouse_entered.connect(func():
		card.modulate = Color(1.15, 1.15, 1.15, 1))
	card.mouse_exited.connect(func():
		card.modulate = Color.WHITE)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# ★ v6.62d：avatar 模式改成上下结构——上：头像+标题，下：赋能数据区
	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 6)
	card.add_child(card_vbox)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card_vbox.add_child(row)

	if avatar_unit != "":
		# ★ v6.62e：头像用只读展示（不是按钮），mouse_filter=IGNORE 让点击穿透到卡片，
		#   这样鼠标在头像图片上点击也能选中卡片，且不会双重触发
		var avatar_ctrl : Control = UnitDataManager.create_unit_avatar_rect(avatar_unit, Vector2(48, 48))
		row.add_child(avatar_ctrl)
	else:
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
			var icon_rect := TextureRect.new()
			icon_rect.texture = tex
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon_rect.set_anchors_preset(Control.PRESET_CENTER)
			icon_rect.offset_left = -10
			icon_rect.offset_right = 10
			icon_rect.offset_top = -10
			icon_rect.offset_bottom = 10
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_box.add_child(icon_rect)
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

	if avatar_unit != "":
		# ★ v6.62d：下方数据区（红框位置）——显示赋能后的单位数据作为判断依据
		var data_box := PanelContainer.new()
		data_box.custom_minimum_size = Vector2(0, 60)
		data_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		data_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = Color(0.08, 0.08, 0.11, 0.9)
		dsb.border_color = Color(0.3, 0.3, 0.35)
		dsb.set_border_width_all(1)
		data_box.add_theme_stylebox_override("panel", dsb)
		data_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var data_lb := Label.new()
		data_lb.text = str(data.get("detail", ""))
		data_lb.add_theme_font_size_override("font_size", 7)
		data_lb.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		data_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		data_lb.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		data_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		data_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		data_box.add_child(data_lb)
		card_vbox.add_child(data_box)
	else:
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


## ★ v6.56：结构化奖励预览——把"将获得"的图标/名字/数值词条分区分行显示，
##   替代旧 set_item_icon（绝对定位在顶部 y≈8，与塞进 message 的多行文字重叠）。
##   用法：先 show_confirm(简短标题...) 再调本方法，传入奖励详情；
##   本方法会隐藏 message_label，用独立 VBox 占满消息区，分区清晰不重叠。
func set_reward_detail(icon: Texture2D, reward_name: String, detail: String, quality_color: Color = Color.WHITE) -> void:
	message_label.visible = false
	# 旧的 set_item_icon 图标若已存在先移除，避免重复/重叠
	var old_icon := $Panel.get_node_or_null("RewardIcon")
	if old_icon:
		old_icon.queue_free()

	var root := VBoxContainer.new()
	root.name = "RewardDetail"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 32
	root.offset_bottom = -56
	root.add_theme_constant_override("separation", 4)
	$Panel.add_child(root)

	# 分区1：图标 + 名字（横排）
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	if icon != null:
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.06, 0.09)
		sb.border_color = quality_color
		sb.set_border_width_all(1)
		sb.content_margin_left = 2
		sb.content_margin_right = 2
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		box.add_theme_stylebox_override("panel", sb)
		var rect := TextureRect.new()
		rect.texture = icon
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(20, 20)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rect)
		head.add_child(box)
	var name_lbl := Label.new()
	name_lbl.text = reward_name
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", quality_color)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_lbl)

	# 分区2：数值/词条（每行一条，左对齐，独立区域）
	var detail_box := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.10, 0.10, 0.14, 0.9)
	dsb.set_border_width_all(1)
	dsb.border_color = Color(0.30, 0.30, 0.36)
	dsb.content_margin_left = 6
	dsb.content_margin_right = 6
	dsb.content_margin_top = 4
	dsb.content_margin_bottom = 4
	detail_box.add_theme_stylebox_override("panel", dsb)
	var dvbox := VBoxContainer.new()
	dvbox.add_theme_constant_override("separation", 2)
	detail_box.add_child(dvbox)
	for line in detail.split("\n"):
		var txt := str(line).strip_edges()
		if txt == "":
			continue
		var dl := Label.new()
		dl.text = "· " + txt
		dl.add_theme_font_size_override("font_size", 8)
		dl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dvbox.add_child(dl)
	root.add_child(detail_box)
