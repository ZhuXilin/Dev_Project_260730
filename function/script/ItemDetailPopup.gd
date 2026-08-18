extends CanvasLayer

@onready var icon = $Panel/VBox/IconNameHBox/Icon
@onready var name_label = $Panel/VBox/IconNameHBox/Name
@onready var desc_label = $Panel/VBox/Description
@onready var stats_label = $Panel/VBox/Stats
@onready var close_btn = $Panel/VBox/CloseButton

func show_item(item_id: String, _unit: Unit = null):
	var data = ItemManager.get_item_data(item_id)
	if not data:
		_on_close_pressed()
		return
	
	if data.icon:
		icon.texture = data.icon
		icon.visible = true
	else:
		icon.visible = false
	
	name_label.text = data.name
	desc_label.text = data.description if data.description else ""
	
	# 构建属性文本
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
	
	# 如果是单位身上的装备，可以额外显示“已装备”等信息，但不需要操作
	visible = true

func _on_close_pressed() -> void:
	queue_free()
