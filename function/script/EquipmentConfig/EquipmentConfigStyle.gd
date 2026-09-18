class_name EquipmentConfigStyle
extends RefCounted

# ============================================================
#  字号 / 尺寸常量
# ============================================================
const FONT_TINY = 4
const FONT_SMALL = 6
const FONT_NORMAL = 6
const FONT_LARGE = 6

const BTN_ITEM_SIZE = Vector2(28, 16)
const BTN_TALENT_SIZE = Vector2(28, 18)
const BTN_SHOP_SIZE = Vector2(28, 16)
const BTN_LIBRARY_SIZE = Vector2(28, 16)
const BTN_RELIC_SIZE = Vector2(22, 16)

const SEPARATOR_TEXT = "──────"


# ============================================================
#  UI 工厂
# ============================================================
static func create_styled_button(font_size: int, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn


static func create_label(text: String, font_size: int, center: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if center:
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func create_drag_preview(btn: Button) -> Label:
	var preview := Label.new()
	var orig_text : Variant = btn.get_meta("_original_text", "")
	preview.text = orig_text
	var font_size : int = btn.get_theme_font_size("font_size")
	if font_size > 0:
		preview.add_theme_font_size_override("font_size", font_size)
	preview.autowrap_mode = btn.autowrap_mode
	preview.horizontal_alignment = btn.alignment
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font_color : Color = btn.get_theme_color("font_color")
	if font_color:
		preview.add_theme_color_override("font_color", font_color)
	var orig_mod : Variant = btn.get_meta("_original_modulate", Color.WHITE)
	preview.modulate = orig_mod
	var preview_size : Vector2 = btn.custom_minimum_size
	if preview_size == Vector2.ZERO or preview_size.y < 10:
		preview_size = btn.size
	if preview_size == Vector2.ZERO or preview_size.y < 10:
		preview_size = Vector2(50, 20)
	if preview_size.y < 14:
		preview_size.y = 14
	preview.size = preview_size
	var original_style : StyleBox = btn.get_theme_stylebox("normal")
	if original_style:
		var new_style := StyleBoxFlat.new()
		if original_style is StyleBoxFlat:
			var fs : StyleBoxFlat = original_style
			new_style.bg_color = fs.bg_color
			new_style.border_width_left = fs.border_width_left
			new_style.border_width_right = fs.border_width_right
			new_style.border_width_top = fs.border_width_top
			new_style.border_width_bottom = fs.border_width_bottom
			new_style.border_color = fs.border_color
		else:
			new_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
			new_style.border_width_left = 1
			new_style.border_width_right = 1
			new_style.border_width_top = 1
			new_style.border_width_bottom = 1
			new_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		preview.add_theme_stylebox_override("normal", new_style)
	preview.text_overrun_behavior = btn.text_overrun_behavior
	preview.clip_text = btn.clip_text
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview


# ============================================================
#  显示辅助（纯函数）
# ============================================================
static func get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":    return Color(1.0, 1.0, 1.0, 1.0)
		"rare":      return Color(0.3, 0.6, 1.0, 1.0)
		"epic":      return Color(0.7, 0.3, 1.0, 1.0)
		"legendary": return Color(1.0, 0.7, 0.0, 1.0)
		_:           return Color.WHITE


static func get_quality_display_name(quality: String) -> String:
	match quality:
		"common":    return "普通"
		"rare":      return "稀有"
		"epic":      return "史诗"
		"legendary": return "传说"
		_:           return quality


static func get_attr_display_name(attr: String) -> String:
	match attr:
		"strength":     return "力量"
		"dexterity":    return "灵巧"
		"intelligence": return "智力"
		"faith":        return "信仰"
		"arcane":       return "感应"
		"attack":       return "攻击"
		"defense":      return "防御"
		"magic_attack": return "魔法攻击"
		"move_range":   return "移动力"
		"max_hp":       return "最大HP"
		_:              return attr
