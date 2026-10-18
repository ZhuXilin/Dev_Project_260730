class_name SoulFireVisualController
extends Node

var _vignette : TextureRect = null
var _state_banner : Label = null
var _canvas : CanvasLayer = null
var _vignette_tween : Tween = null
var _banner_tween : Tween = null

const COLOR_BURNING  : Color = Color(1.00, 0.65, 0.25, 0.12)
const COLOR_DEPLETED : Color = Color(0.65, 0.35, 0.85, 0.15)
const COLOR_NORMAL   : Color = Color(1.00, 1.00, 1.00, 0.00)

const VIGNETTE_FADE_IN  : float = 0.4
const VIGNETTE_FADE_OUT : float = 0.5
const BANNER_FADE_IN    : float = 0.2
const BANNER_HOLD       : float = 1.4
const BANNER_FADE_OUT   : float = 0.6


func _ready():
	_setup_ui()
	SoulFireManager.state_changed.connect(_on_state_changed)
	_on_state_changed(SoulFireManager.get_state())


func _setup_ui():
	_canvas = CanvasLayer.new()
	_canvas.layer = 95
	add_child(_canvas)

	var gradient := Gradient.new()
	gradient.add_point(0.5, Color(1, 1, 1, 1))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
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
	_canvas.add_child(_vignette)

	_state_banner = Label.new()
	_state_banner.add_theme_font_size_override("font_size", 12)
	_state_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_state_banner.add_theme_constant_override("outline_size", 2)
	_state_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_banner.anchor_left = 0.5
	_state_banner.anchor_right = 0.5
	_state_banner.offset_left = -120
	_state_banner.offset_right = 120
	_state_banner.offset_top = 78
	_state_banner.offset_bottom = 96
	_state_banner.modulate = Color(1, 1, 1, 0)
	_canvas.add_child(_state_banner)


func _on_state_changed(new_state: int):
	_kill_vignette_tween()

	match new_state:
		SoulFireManager.State.BURNING:
			_set_vignette_color(COLOR_BURNING)
			_show_banner("燃烧态", Color(1.0, 0.75, 0.35))
		SoulFireManager.State.DEPLETED:
			_set_vignette_color(COLOR_DEPLETED)
			_show_banner("枯竭态", Color(0.85, 0.6, 1.0))
		SoulFireManager.State.ZERO:
			_set_vignette_color(COLOR_NORMAL)
			_show_banner("魂火耗尽", Color(0.95, 0.55, 0.55))
		_:
			_set_vignette_color(COLOR_NORMAL)


func _set_vignette_color(color: Color):
	if _vignette == null: return
	var current_a := _vignette.modulate.a
	_vignette.modulate = Color(color.r, color.g, color.b, current_a)
	_vignette_tween = create_tween()
	_vignette_tween.set_ignore_time_scale(true)
	var duration : float = VIGNETTE_FADE_IN if color.a > 0.0 else VIGNETTE_FADE_OUT
	_vignette_tween.tween_property(_vignette, "modulate:a", color.a, duration)


func _show_banner(text: String, color: Color):
	if _state_banner == null: return
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
		_banner_tween = null
	_state_banner.text = text
	_state_banner.add_theme_color_override("font_color", color)
	_state_banner.modulate = Color(1, 1, 1, 0)
	_banner_tween = create_tween()
	_banner_tween.set_ignore_time_scale(true)
	_banner_tween.tween_property(_state_banner, "modulate:a", 1.0, BANNER_FADE_IN)
	_banner_tween.tween_interval(BANNER_HOLD)
	_banner_tween.tween_property(_state_banner, "modulate:a", 0.0, BANNER_FADE_OUT)


func _kill_vignette_tween():
	if _vignette_tween and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette_tween = null


# ★ 核心修复：退出场景时强制隐藏和释放，防止红色渐变残留到下一个场景
func _exit_tree():
	_kill_vignette_tween()
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
		_banner_tween = null
	if _vignette and is_instance_valid(_vignette):
		_vignette.visible = false
		_vignette.modulate.a = 0.0
	if _canvas and is_instance_valid(_canvas):
		_canvas.queue_free()
