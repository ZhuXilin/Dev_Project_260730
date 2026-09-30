extends CanvasLayer

var _current_plugin : TestPlugin = null
var _plugin_buttons : Dictionary = {}
var _built : bool = false
var _protect_hint : Label = null
var _plugin_name_label : Label = null
var _status_label : Label = null
var _launching : bool = false

@onready var category_list : VBoxContainer = $Panel/VBox/MainHBox/LeftColumn/CategoryScroll/CategoryList
@onready var param_container : VBoxContainer = $Panel/VBox/MainHBox/MidColumn/ParamScroll/ParamContainer
@onready var info_label : Label = $Panel/VBox/InfoBar/InfoLabel
@onready var launch_btn : Button = $Panel/VBox/BottomBar/LaunchBtn
@onready var close_btn : Button = $Panel/VBox/BottomBar/CloseBtn


func _ready():
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_apply_tooltip_theme()


func _apply_tooltip_theme():
	var t := Theme.new()
	t.set_font_size("font_size", "TooltipLabel", 6)
	t.set_font_size("font_size", "TooltipPanel", 6)
	# ★ 挂到 Panel 上（Panel 是 Control，会递归传播）
	var panel := get_node_or_null("Panel")
	if panel is Control:
		(panel as Control).theme = t

func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# 启动中忽略热键
	if _launching:
		return

	if visible and event.keycode == KEY_ESCAPE:
		_toggle(false)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_1:
		var focus = get_viewport().gui_get_focus_owner()
		if focus and (focus is LineEdit or focus is TextEdit):
			return
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle(force = null):
	if _launching:
		return
	var target : bool = (not visible) if force == null else force
	if target:
		SaveManager.suppress_save = true
		if not _built:
			_build_once()
			_built = true
		_refresh_category_list()
		_refresh_protect_hint()
	else:
		# ★ 关闭时通知当前插件
		if _current_plugin:
			_current_plugin.on_deactivate()
	visible = target


func _build_once():
	launch_btn.pressed.connect(_on_launch)
	close_btn.pressed.connect(_on_close)

	# InfoBar 结构：
	# [固定宽左容器(插件名)] [状态标签] [弹性] [存档保护中]
	# ★ 注意：InfoLabel 已在重构时废弃，其 @onready 引用不再使用
	var info_bar : HBoxContainer = $Panel/VBox/InfoBar
	for c in info_bar.get_children():
		info_bar.remove_child(c)
		c.queue_free()

	info_bar.add_theme_constant_override("separation", 6)

	# ★ 左：固定宽度容器，宽度 = 分类列宽(90)，让后续状态标签与 MidColumn 对齐
	var left_box := Control.new()
	left_box.custom_minimum_size = Vector2(90, 0)
	left_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_bar.add_child(left_box)

	_plugin_name_label = Label.new()
	_plugin_name_label.add_theme_font_size_override("font_size", 7)
	_plugin_name_label.text = "（未选择）"
	_plugin_name_label.clip_text = true
	_plugin_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left_box.add_child(_plugin_name_label)

	# ★ 中：状态标签（位置由 left_box 固定，不会被挤压）
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 7)
	_status_label.text = ""
	_status_label.custom_minimum_size = Vector2(80, 0)
	info_bar.add_child(_status_label)

	# 弹性：把存档保护推到右
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_bar.add_child(spacer)

	# 右：存档保护提示
	_protect_hint = Label.new()
	_protect_hint.add_theme_font_size_override("font_size", 7)
	_protect_hint.modulate = Color(1.0, 0.85, 0.3)
	info_bar.add_child(_protect_hint)


func _refresh_protect_hint():
	if not _protect_hint:
		return
	_protect_hint.text = "⚠️ 存档保护中" if SaveManager.suppress_save else "存档：正常"


# ============================================================
#  分类 + 插件列表
# ============================================================
func _refresh_category_list():
	for child in category_list.get_children():
		category_list.remove_child(child)
		child.queue_free()
	_plugin_buttons.clear()

	var by_cat : Dictionary = TestRegistry.get_by_category()
	for cat in by_cat:
		var title := Label.new()
		title.text = "▸ " + cat
		title.add_theme_font_size_override("font_size", 7)
		title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		category_list.add_child(title)

		for p in by_cat[cat]:
			var btn := Button.new()
			btn.text = "  " + p.get_display_name()
			btn.toggle_mode = true
			btn.add_theme_font_size_override("font_size", 8)
			btn.clip_text = true
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_on_plugin_selected.bind(p))
			category_list.add_child(btn)
			_plugin_buttons[p.get_key()] = btn

	var all = TestRegistry.get_all()
	if not all.is_empty() and _current_plugin == null:
		_on_plugin_selected(all[0])


func _on_plugin_selected(plugin: TestPlugin):
	# ★ 切换插件时，先通知旧插件停止
	if _current_plugin and _current_plugin != plugin:
		_current_plugin.on_deactivate()

	_current_plugin = plugin

	for key in _plugin_buttons:
		_plugin_buttons[key].button_pressed = (key == plugin.get_key())

	for child in param_container.get_children():
		param_container.remove_child(child)
		child.queue_free()

	plugin.build_params(param_container, func(): _refresh_launch_btn())
	_refresh_launch_btn()


func _refresh_launch_btn():
	if _current_plugin == null:
		launch_btn.disabled = true
		if _plugin_name_label:
			_plugin_name_label.text = "（未选择）"
		_refresh_status_text()
		return
	var err : String = _current_plugin.validate()
	if err != "":
		launch_btn.disabled = true
		launch_btn.tooltip_text = err
		if _plugin_name_label:
			_plugin_name_label.text = "❌ " + err
	else:
		launch_btn.disabled = false
		launch_btn.tooltip_text = ""
		if _plugin_name_label:
			_plugin_name_label.text = "当前：" + _current_plugin.get_display_name()
	_refresh_status_text()


func _refresh_status_text():
	if _status_label == null:
		return
	if _current_plugin == null:
		_status_label.text = ""
		return
	_status_label.text = _current_plugin.get_status_text()


# ============================================================
#  启动 / 关闭
# ============================================================
func _on_launch():
	if _current_plugin == null or _launching:
		return
	var err : String = _current_plugin.validate()
	if err != "":
		# ★ 改用 _status_label（info_label 已废弃）
		if _status_label:
			_status_label.text = "❌ " + err
		return

	SaveManager.suppress_save = true
	_refresh_protect_hint()
	_launching = true

	# 每次启动前重置 keep_hidden
	_current_plugin.reset_keep_hidden()

	# 隐藏自身
	visible = false

	# 等插件完成（UI 关闭 / 切场景）
	await _current_plugin.launch()

	_launching = false

	# 如果插件要求保持隐藏（比如切场景），不恢复
	if _current_plugin.should_keep_hidden():
		return

	if not is_inside_tree():
		return

	# UI 结束后恢复自己
	visible = true
	_refresh_protect_hint()
	_refresh_launch_btn()


func _on_close():
	_toggle(false)
