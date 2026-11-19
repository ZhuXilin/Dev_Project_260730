extends RefCounted
## ============================================================
##  BuildUI — v6 新建面板的统一样式工具
## ============================================================
##  工程全局主题只设了字体、Button 无默认 StyleBox，
##  纯代码 new() 出来的 Button 本体透明（只有文字），看起来像"没有按钮"。
##  本工具给 Button 套上与 RewardSummaryUI 一致的 8bit 纯色 StyleBox，
##  五态齐全，保证按钮可见且有交互反馈。
## ============================================================

const BTN_BG        : Color = Color(0.16, 0.16, 0.22, 1.0)
const BTN_HOVER     : Color = Color(0.26, 0.24, 0.34, 1.0)
const BTN_PRESSED   : Color = Color(0.10, 0.10, 0.15, 1.0)
const BTN_DISABLED  : Color = Color(0.10, 0.10, 0.12, 0.8)
const BTN_BORDER    : Color = Color(0.45, 0.40, 0.22, 1.0)
const BTN_TEXT      : Color = Color(0.95, 0.95, 0.97, 1.0)
const BTN_TEXT_DIM  : Color = Color(0.45, 0.45, 0.48, 1.0)


static func style_button(btn: Button, accent: Color = Color(0, 0, 0, 0)) -> void:
	var border := BTN_BORDER if accent.a <= 0.0 else accent
	btn.add_theme_stylebox_override("normal", _make(BTN_BG, border))
	btn.add_theme_stylebox_override("hover", _make(BTN_HOVER, border))
	btn.add_theme_stylebox_override("pressed", _make(BTN_PRESSED, border))
	btn.add_theme_stylebox_override("disabled", _make(BTN_DISABLED, border))
	btn.add_theme_stylebox_override("focus", _make(BTN_HOVER, border))
	btn.add_theme_color_override("font_color", BTN_TEXT)
	btn.add_theme_color_override("font_hover_color", BTN_TEXT)
	btn.add_theme_color_override("font_pressed_color", BTN_TEXT)
	btn.add_theme_color_override("font_disabled_color", BTN_TEXT_DIM)


static func _make(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	sb.anti_aliasing = false
	return sb
