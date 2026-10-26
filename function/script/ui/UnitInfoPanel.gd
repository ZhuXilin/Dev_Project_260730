extends PanelContainer

var current_unit_name : String = ""
var show_mode : int = 1 # 1=强制玩法, 2=强制叙事

@onready var avatar_rect = get_node_or_null("VBox/AvatarBg/AvatarRect")
@onready var avatar_bg = get_node_or_null("VBox/AvatarBg")
@onready var info_name = get_node_or_null("VBox/InfoName")
@onready var scroll_box = get_node_or_null("VBox/Scroll")
@onready var info_stats = get_node_or_null("VBox/Scroll/ContentVBox/InfoStats")
@onready var info_desc = get_node_or_null("VBox/Scroll/ContentVBox/InfoDesc")
@onready var hsep = get_node_or_null("VBox/HSep")

func _ready():
	clear_info()

func set_unit(unit_name: String):
	current_unit_name = unit_name
	refresh()

func clear_info():
	current_unit_name = ""
	refresh()

func toggle_mode():
	if show_mode == 1: show_mode = 2
	elif show_mode == 2: show_mode = 1
	refresh()

func refresh():
	if current_unit_name == "":
		if info_name: info_name.text = ""
		if info_stats: info_stats.text = ""
		if info_desc: info_desc.text = ""
		if scroll_box: scroll_box.visible = false
		if hsep: hsep.visible = false
		_hide_avatar_both()
		return
	else:
		if scroll_box: scroll_box.visible = true
		if hsep: hsep.visible = true

	if show_mode == 2:
		var flavor : String = FlavorManager.get_flavor("units", current_unit_name)
		if flavor == "": flavor = "（暂无叙事）"
		_update_avatar(current_unit_name)
		if info_name: info_name.text = ""
		if info_stats: info_stats.text = ""
		if info_desc: info_desc.text = flavor
		return

	var unit_dict = UnitDataManager.get_unit_data(current_unit_name)
	if unit_dict.is_empty():
		_hide_avatar_both()
		if info_name: info_name.text = "（无数据）"
		if info_stats: info_stats.text = ""
		if info_desc: info_desc.text = "该单位在 unit_data.json 中未定义。"
		return

	_update_avatar(current_unit_name)

	var display = unit_dict.get("display_name", current_unit_name)
	var faction = unit_dict.get("faction", "无")
	var type_cn = UnitDataManager.get_unit_type_display_name(current_unit_name)

	if info_name: info_name.text = "%s\n（%s｜%s）" % [display, faction, type_cn]

	var lines : Array = []
	lines.append("HP      %d" % unit_dict.get("max_hp", 0))
	lines.append("力量    %d" % unit_dict.get("strength", 0))
	lines.append("灵巧    %d" % unit_dict.get("dexterity", 0))
	lines.append("智力    %d" % unit_dict.get("intelligence", 0))
	lines.append("信仰    %d" % unit_dict.get("faith", 0))
	lines.append("感应    %d" % unit_dict.get("arcane", 0))
	lines.append("移动力  %d" % unit_dict.get("move_range", 0))
	
	lines.append("")

	if DispatchManager.is_unit_dispatched(current_unit_name):
		lines.append("【派遣中，本局不能出战】")
		lines.append("")

	if info_stats:
		info_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info_stats.text = "\n".join(lines)
	if info_desc:
		info_desc.text = unit_dict.get("description", "")

# ★ 兼容装备界面/物品详情的显示
func show_info(data: Dictionary):
	current_unit_name = "" 
	
	if info_name:
		info_name.text = data.get("name", "")
		info_name.add_theme_color_override("font_color", data.get("name_color", Color.WHITE))
	
	if info_stats:
		info_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info_stats.text = data.get("stats", "")
		info_stats.add_theme_color_override("font_color", Color.WHITE)
		
	if info_desc:
		info_desc.text = data.get("desc", "")

	var icon_tex = data.get("icon")
	if icon_tex and avatar_rect and avatar_bg:
		avatar_rect.texture = icon_tex
		avatar_rect.custom_minimum_size = Vector2(48, 48)
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_show_avatar_raw()
	else:
		_hide_avatar_both()
		
	if scroll_box: scroll_box.visible = true
	if hsep: hsep.visible = true

func _update_avatar(unit_name: String):
	if not avatar_rect or not avatar_bg: return
	
	if unit_name == "":
		_hide_avatar_both()
		return

	var avatar_id = GameState.get_unit_avatar(unit_name)
	var has_avatar = false
	
	if avatar_id != "":
		var path = "res://content/images/characters/avatar/%s.png" % avatar_id
		if ResourceLoader.exists(path):
			var tex = load(path)
			if avatar_rect.texture != tex:
				avatar_rect.texture = tex
			has_avatar = true
			
	if has_avatar:
		avatar_rect.custom_minimum_size = Vector2(48, 48)
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_show_avatar_raw()
	else:
		_hide_avatar_both()

# 暴力显示，剥离所有可能残留的 Shader 和动画
func _show_avatar_raw():
	if avatar_bg:
		avatar_bg.material = null
		avatar_bg.visible = true
	if avatar_rect:
		avatar_rect.material = null
		avatar_rect.visible = true

# 暴力隐藏，剥离所有可能残留的 Shader 和动画
func _hide_avatar_both():
	if avatar_bg:
		avatar_bg.material = null
		avatar_bg.visible = false
	if avatar_rect:
		avatar_rect.material = null
		avatar_rect.visible = false
