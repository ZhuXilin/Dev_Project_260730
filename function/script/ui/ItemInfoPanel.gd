extends PanelContainer

@onready var name_label = get_node_or_null("VBox/NameLabel")
@onready var type_label = get_node_or_null("VBox/TypeLabel")
@onready var scroll_box = get_node_or_null("VBox/Scroll")
@onready var desc_label = get_node_or_null("VBox/Scroll/ContentVBox/DescLabel")
@onready var stats_label = get_node_or_null("VBox/Scroll/ContentVBox/StatsLabel")
@onready var hsep = get_node_or_null("VBox/HSep")

func _ready():
	clear_info()

func clear_info():
	if name_label: name_label.text = "选中物品详情"
	if type_label: type_label.text = ""
	if desc_label: desc_label.text = ""
	if stats_label: stats_label.text = ""
	if scroll_box: scroll_box.visible = false
	if hsep: hsep.visible = false

func show_info(data: Dictionary):
	if name_label:
		name_label.text = data.get("name", "")
		name_label.add_theme_color_override("font_color", data.get("name_color", Color.WHITE))
	
	if type_label:
		type_label.text = data.get("type_str", "")
		type_label.modulate = Color(0.7, 0.7, 0.7)
	
	if desc_label:
		desc_label.text = data.get("desc", "")
		
	if stats_label:
		stats_label.text = data.get("stats", "")
		
	if scroll_box: scroll_box.visible = true
	if hsep: hsep.visible = true
