extends PanelContainer

@onready var unit_list = $VBoxContainer/HBoxContainer/ScrollContainer/UnitList
@onready var info_panel = $VBoxContainer/HBoxContainer/InfoPanel

func _ready():
	populate_list()

func populate_list():
	for child in unit_list.get_children():
		child.queue_free()

	var unlocked = Globals.get_unlocked_units()
	unlocked.sort()

	for unit_name in unlocked:
		var btn = Button.new()
		btn.text = UnitDataManager.get_display_name_full(unit_name)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_unit_selected.bind(unit_name))
		btn.mouse_entered.connect(_on_unit_selected.bind(unit_name))
		unit_list.add_child(btn)

func _on_unit_selected(unit_name: String):
	info_panel.set_unit(unit_name)

func _on_back_button_pressed():
	queue_free()
