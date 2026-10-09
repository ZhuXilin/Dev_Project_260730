extends Node
class_name UIManager

var victory_panel : Panel
var victory_label : Label
var victory_button : Button


func initialize(ui_nodes: Dictionary):
	victory_panel = ui_nodes.get("victory_panel")
	victory_label = ui_nodes.get("victory_label")
	victory_button = ui_nodes.get("victory_button")


func show_victory(label_text: String, button_text: String, callback: Callable):
	if not victory_label or not victory_button:
		return
	victory_label.text = label_text
	victory_button.text = button_text
	if victory_button.pressed.is_connected(_on_victory_button_pressed):
		victory_button.pressed.disconnect(_on_victory_button_pressed)
	victory_button.pressed.connect(_on_victory_button_pressed.bind(callback))

	PanelRevealer.show_panel(victory_panel)


func _on_victory_button_pressed(callback: Callable):
	PanelRevealer.hide_panel(victory_panel)
	if callback.is_valid():
		callback.call()


func show_modal_message(text: String, callback_after: Callable = Callable()):
	var popup = CanvasLayer.new()
	popup.layer = 40
	get_tree().current_scene.add_child(popup)

	var panel = Panel.new()
	panel.size = UIConst.MODAL_PANEL_SIZE
	var viewport_size = get_viewport().get_visible_rect().size
	panel.position = viewport_size / 2 - panel.size / 2

	var stylebox = load(Config.PATHS.STYLEBOX_8BIT)
	if stylebox:
		panel.add_theme_stylebox_override("panel", stylebox)
	popup.add_child(panel)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	label.position = Vector2(10, 10)
	label.size = Vector2(UIConst.MODAL_PANEL_SIZE.x - 20, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	var btn_size = Vector2(50, 20)
	var btn = Button.new()
	btn.text = "确定"
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.size = btn_size
	btn.position = Vector2(
		(UIConst.MODAL_PANEL_SIZE.x - btn_size.x) / 2,
		UIConst.MODAL_PANEL_SIZE.y - btn_size.y - 10
	)
	btn.pressed.connect(func():
		popup.queue_free()
		Globals.is_item_get_popup_active = false
		if callback_after.is_valid():
			callback_after.call()
	)
	panel.add_child(btn)

	Globals.is_item_get_popup_active = true


func show_message(text: String):
	var popup = CanvasLayer.new()
	popup.layer = 40
	get_tree().current_scene.add_child(popup)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.size = get_viewport().get_visible_rect().size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.add_child(bg)

	var panel = Panel.new()
	panel.size = UIConst.MSG_PANEL_SIZE
	var viewport_size = get_viewport().get_visible_rect().size
	panel.position = viewport_size / 2 - panel.size / 2

	var stylebox = load(Config.PATHS.STYLEBOX_8BIT)
	if stylebox:
		panel.add_theme_stylebox_override("panel", stylebox)
	popup.add_child(panel)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = panel.size
	panel.add_child(label)

	Globals.is_item_get_popup_active = true

	await get_tree().create_timer(1.5).timeout

	Globals.is_item_get_popup_active = false
	popup.queue_free()
