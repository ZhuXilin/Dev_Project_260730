extends CanvasLayer

@onready var panel = $Panel
@onready var icon = $Panel/VBox/IconNameHBox/Icon
@onready var name_label = $Panel/VBox/IconNameHBox/Name
@onready var desc_label = $Panel/VBox/Description
@onready var stats_label = $Panel/VBox/Stats


func _ready():
	if panel:
		panel.visible = false


func get_panel() -> Panel:
	return panel


func show_item(item_id: String, _unit: Unit = null):
	var relic_data = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		_show_relic_detail(relic_data, item_id)
		return

	var data = ItemManager.get_item_data(item_id)
	if not data:
		hide_popup()
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

	_show_panel_animated()


func _show_relic_detail(data: Dictionary, item_id: String = ""):
	icon.visible = false
	var name_text : String = data.get("name", "")
	var desc_text : String = data.get("description", "")
	# ★ v4.5：精炼状态
	if item_id != "" and GameState.is_relic_refined(item_id):
		name_text = "★ " + name_text
		desc_text += "\n（已精炼）"
	name_label.text = name_text
	desc_label.text = desc_text
	stats_label.text = ""
	_show_panel_animated()


func hide_popup():
	if panel == null:
		return
	if panel.visible:
		PanelRevealer.hide_panel(panel)


func _show_panel_animated():
	if panel == null:
		return
	var was_visible : bool = panel.visible
	panel.visible = true
	if not was_visible:
		PanelRevealer.show_panel(panel)
