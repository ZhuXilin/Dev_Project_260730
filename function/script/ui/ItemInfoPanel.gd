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
	if name_label: 
		name_label.text = "选中物品详情"
	if type_label: 
		type_label.text = ""
	if desc_label: 
		desc_label.text = ""
	if stats_label: 
		stats_label.text = ""
	if scroll_box: 
		scroll_box.visible = false
		scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if hsep: 
		hsep.visible = false

func show_info(data: Dictionary):
	if name_label:
		name_label.text = data.get("name", "")
		name_label.add_theme_color_override("font_color", data.get("name_color", Color.WHITE))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # ★ 强制左对齐
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	if type_label:
		type_label.text = data.get("type_str", "")
		type_label.modulate = Color(0.7, 0.7, 0.7)
		type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # ★ 强制左对齐
	
	if desc_label:
		desc_label.text = data.get("desc", "")
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # ★ 强制左对齐
		
	if stats_label:
		stats_label.text = data.get("stats", "")
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # ★ 强制左对齐
		
	if scroll_box: 
		scroll_box.visible = true
		scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if hsep: 
		hsep.visible = true
