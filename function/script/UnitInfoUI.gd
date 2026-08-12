extends PanelContainer

@onready var unit_list = $VBoxContainer/ScrollContainer/UnitList
@onready var detail_label = $VBoxContainer/DetailLabel

var all_unit_names = ["剑士", "枪兵", "斧兵", "弓兵", "飞马", "法师", "修女", "龙人", "重甲兵"]

func _ready():
	populate_list()

func populate_list():
	for child in unit_list.get_children():
		child.queue_free()
	for name in all_unit_names:
		var btn = Button.new()
		btn.text = name
		var unlocked = Globals.is_unit_unlocked(name)
		btn.modulate = Color.WHITE if unlocked else Color(0.5, 0.5, 0.5)
		btn.disabled = not unlocked
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_unit_selected.bind(name))
		unit_list.add_child(btn)

func _on_unit_selected(unit_name: String):
	var stats = UnitDataManager.get_unit_data(unit_name)
	var desc = stats.get("description", "暂无描述")
	var text = "名称：%s\n" % unit_name
	text += "HP：%d\n" % stats.get("max_hp", 0)
	text += "防御：%d\n" % stats.get("defense", 0)
	text += "魔防：%d\n" % stats.get("magic_defense", 0)
	text += "技能：%d\n" % stats.get("skill", 0)
	text += "速度：%d\n" % stats.get("speed", 0)
	text += "幸运：%d\n" % stats.get("luck", 0)
	text += "移动力：%d\n" % stats.get("move_range", 0)
	text += "描述：%s" % desc
	detail_label.text = text
