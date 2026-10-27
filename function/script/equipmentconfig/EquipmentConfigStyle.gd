class_name EquipmentConfigStyle
extends RefCounted

# ============================================================
#  字号 / 尺寸常量
# ============================================================
const FONT_TINY   = 4
const FONT_SMALL  = 6
const FONT_NORMAL = 6
const FONT_LARGE  = 8
const FONT_TITLE  = 10

# ★ 统一插槽为 20x20 正方形
const BTN_ITEM_SIZE = Vector2(20, 20)
const BTN_TALENT_SIZE = Vector2(20, 20)
const BTN_SHOP_SIZE = Vector2(20, 20)
const BTN_LIBRARY_SIZE = Vector2(20, 20)
const BTN_RELIC_SIZE = Vector2(20, 20)

const SEPARATOR_TEXT = "──────"


static func create_styled_button(font_size: int, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# ★ 移除了强制的 StyleBoxEmpty，恢复默认的内边距，保证文字按钮能正常显示
	return btn

static func create_drag_preview(btn: Button) -> Control:
	if btn.icon:
		var tex_rect = TextureRect.new()
		tex_rect.texture = btn.icon
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE 
		tex_rect.custom_minimum_size = btn.custom_minimum_size
		tex_rect.size = btn.custom_minimum_size 
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.modulate = btn.get_meta("_original_modulate", Color.WHITE)
		return tex_rect
	else:
		var label = Label.new()
		label.text = btn.get_meta("_original_text", "")
		label.add_theme_font_size_override("font_size", FONT_SMALL)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.modulate = btn.get_meta("_original_modulate", Color.WHITE)
		return label


static func create_label(text: String, font_size: int, center: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if center:
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


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
