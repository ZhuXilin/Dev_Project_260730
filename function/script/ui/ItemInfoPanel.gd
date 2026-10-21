extends PanelContainer

@onready var icon_bg = $VBox/IconBg as Panel
@onready var icon_rect = $VBox/IconRect as TextureRect
@onready var name_label = $VBox/NameLabel as Label
@onready var type_label = $VBox/TypeLabel as Label
@onready var desc_label = $VBox/Scroll/ContentVBox/DescLabel as Label
@onready var stats_label = $VBox/Scroll/ContentVBox/StatsLabel as Label

# 供外部调用：清空界面
func clear_info():
	name_label.text = "选中物品详情"
	type_label.text = ""
	desc_label.text = ""
	stats_label.text = ""
	_hide_icon()

# 供外部调用：展示物品信息
func show_info(data: Dictionary):
	name_label.text = data.get("name", "未知")
	name_label.add_theme_color_override("font_color", data.get("name_color", Color.WHITE))
	
	type_label.text = data.get("type_str", "")
	type_label.modulate = Color(0.7, 0.7, 0.7)
	
	desc_label.text = data.get("desc", "")
	stats_label.text = data.get("stats", "")
	
	var icon: Texture2D = data.get("icon")
	_update_icon(icon)

func _update_icon(tex: Texture2D):
	if tex != null:
		icon_rect.texture = tex
		icon_rect.custom_minimum_size = Vector2(48, 48)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		if not icon_bg.visible:
			icon_bg.visible = true
			PanelRevealer.show_panel(icon_bg)
		if not icon_rect.visible:
			icon_rect.visible = true
			PanelRevealer.show_panel(icon_rect)
	else:
		_hide_icon()

func _hide_icon():
	if icon_bg.visible: PanelRevealer.hide_panel(icon_bg)
	if icon_rect.visible: PanelRevealer.hide_panel(icon_rect)
