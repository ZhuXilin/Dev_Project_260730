class_name SoulFireVisualController
extends Node

var _vignette : TextureRect = null
var _state_banner : Label = null
var _tween : Tween = null

const COLOR_BURNING = Color(1.0, 0.6, 0.2, 0.15)   # 金色/橙色光晕
const COLOR_DEPLETED = Color(0.8, 0.1, 0.1, 0.25)  # 血色暗角
const COLOR_ZERO = Color(1.0, 0.0, 0.0, 0.4)       # 危险红

func _ready():
	_setup_ui()
	SoulFireManager.state_changed.connect(_on_state_changed)
	_on_state_changed(SoulFireManager.get_state())

func _setup_ui():
	var canvas = CanvasLayer.new()
	canvas.layer = 95 
	add_child(canvas)

	# 径向渐变暗角
	var gradient = Gradient.new()
	gradient.add_point(0.5, Color(1, 1, 1, 1))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)

	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.modulate = Color(1, 1, 1, 0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_vignette)

	# 状态横幅
	_state_banner = Label.new()
	_state_banner.add_theme_font_size_override("font_size", 16)
	_state_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_state_banner.add_theme_constant_override("outline_size", 4)
	_state_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_banner.anchor_left = 0.5
	_state_banner.anchor_right = 0.5
	_state_banner.offset_left = -150
	_state_banner.offset_right = 150
	_state_banner.offset_top = 80
	_state_banner.modulate = Color(1, 1, 1, 0)
	canvas.add_child(_state_banner)

func _on_state_changed(new_state: int):
	if _tween and _tween.is_valid():
		_tween.kill()

	match new_state:
		SoulFireManager.State.BURNING:
			_set_vignette_color(COLOR_BURNING)
			_show_banner("★ 燃烧态", Color(1.0, 0.7, 0.2))
		SoulFireManager.State.DEPLETED:
			_set_vignette_color(COLOR_DEPLETED)
			_show_banner("⚠ 枯竭态", Color(1.0, 0.3, 0.3))
			_tween = create_tween().set_loops()
			_tween.tween_property(_vignette, "modulate:a", COLOR_DEPLETED.a * 1.5, 0.8).set_trans(Tween.TRANS_SINE)
			_tween.tween_property(_vignette, "modulate:a", COLOR_DEPLETED.a, 0.8).set_trans(Tween.TRANS_SINE)
		SoulFireManager.State.ZERO:
			_set_vignette_color(COLOR_ZERO)
			_show_banner("💀 魂火归零", Color(1.0, 0.0, 0.0))
			_tween = create_tween().set_loops()
			_tween.tween_property(_vignette, "modulate:a", 0.1, 0.3)
			_tween.tween_property(_vignette, "modulate:a", COLOR_ZERO.a, 0.3)
		_:
			_tween = create_tween()
			_tween.tween_property(_vignette, "modulate:a", 0.0, 0.5)

func _set_vignette_color(color: Color):
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_vignette.modulate = color
	_tween.tween_property(_vignette, "modulate:a", color.a, 0.4)

func _show_banner(text: String, color: Color):
	_state_banner.text = text
	_state_banner.add_theme_color_override("font_color", color)
	_state_banner.modulate = Color(1, 1, 1, 1)
	_state_banner.scale = Vector2(1.2, 1.2)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(_state_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_state_banner, "modulate:a", 0.0, 0.5).set_delay(1.5)
