extends CanvasLayer

@onready var icon = $Panel/VBox/IconNameHBox/Icon
@onready var name_label = $Panel/VBox/IconNameHBox/Name
@onready var desc_label = $Panel/VBox/Description
@onready var stats_label = $Panel/VBox/Stats
@onready var close_btn = $Panel/VBox/CloseButton

func _ready():
	close_btn.pressed.connect(_on_close)

func show_item(item_id: String, _unit: Unit = null):
	# ---- 先检查是否为遗物 ----
	var relic_data = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		_show_relic_detail(relic_data)
		return
	
	# ---- 非遗物：使用 ItemManager ----
	var data = ItemManager.get_item_data(item_id)
	if not data:
		_on_close()
		return
	
	if data.icon:
		icon.texture = data.icon
		icon.visible = true
	else:
		icon.visible = false
	
	name_label.text = data.name
	desc_label.text = data.description if data.description else ""
	
	var stats_text = ""
	if data.stats and not data.stats.is_empty():
		var stat_names = {
			"attack": "攻击",
			"defense": "防御",
			"magic_attack": "魔法攻击",
			"heal_amount": "治疗量",
			"move_range": "移动力"
		}
		for key in data.stats:
			var chinese = stat_names.get(key, key.capitalize())
			stats_text += chinese + ": " + str(data.stats[key]) + "\n"
	stats_label.text = stats_text
	
	visible = true

func _show_relic_detail(data: Dictionary):
	icon.visible = false
	name_label.text = data.get("name", "")
	desc_label.text = data.get("description", "")
	
	var stats_text = ""
	var stats = data.get("stats", {})
	if not stats.is_empty():
		var stat_names = {
			"attack": "攻击",
			"defense": "防御",
			"magic_attack": "魔法攻击",
			"move_range": "移动力"
		}
		for key in stats:
			var chinese = stat_names.get(key, key.capitalize())
			stats_text += chinese + ": +" + str(stats[key]) + "\n"
	
	stats_label.text = stats_text
	visible = true

func _on_close():
	queue_free()
