class_name SoulFireVisualController
extends Node

var _state_label : Label = null
var _canvas : CanvasLayer = null
var _fade_tween : Tween = null

const COLOR_BURNING  : Color = Color(1.00, 0.65, 0.25)
const COLOR_DEPLETED : Color = Color(0.65, 0.35, 0.85)
const COLOR_ZERO     : Color = Color(0.95, 0.45, 0.45)

const FADE_IN  : float = 0.15
const HOLD     : float = 1.2
const FADE_OUT : float = 0.4


func _ready():
	_setup_ui()
	SoulFireManager.state_changed.connect(_on_state_changed)


func _setup_ui():
	_canvas = CanvasLayer.new()
	_canvas.layer = 95
	add_child(_canvas)

	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 8)
	_state_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_state_label.add_theme_constant_override("outline_size", 2)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 屏幕底部居中
	_state_label.anchor_left = 0.5
	_state_label.anchor_right = 0.5
	_state_label.anchor_top = 1.0
	_state_label.anchor_bottom = 1.0
	_state_label.offset_left = -60
	_state_label.offset_right = 60
	_state_label.offset_top = -22
	_state_label.offset_bottom = -10
	_state_label.modulate = Color(1, 1, 1, 0)
	_canvas.add_child(_state_label)


func _on_state_changed(new_state: int):
	match new_state:
		SoulFireManager.State.BURNING:
			_show_state_text("燃烧", COLOR_BURNING)
		SoulFireManager.State.DEPLETED:
			_show_state_text("枯竭", COLOR_DEPLETED)
		SoulFireManager.State.ZERO:
			_show_state_text("魂火耗尽", COLOR_ZERO)
		_:
			# 回落到正常态：不显示任何文字，避免遮挡
			_hide_immediately()


func _show_state_text(text: String, color: Color):
	if _state_label == null:
		return
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

	_state_label.text = text
	_state_label.add_theme_color_override("font_color", color)
	_state_label.modulate = Color(1, 1, 1, 0)

	_fade_tween = create_tween()
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.tween_property(_state_label, "modulate:a", 1.0, FADE_IN)
	_fade_tween.tween_interval(HOLD)
	_fade_tween.tween_property(_state_label, "modulate:a", 0.0, FADE_OUT)


func _hide_immediately():
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
		_fade_tween = null
	if _state_label and is_instance_valid(_state_label):
		_state_label.modulate = Color(1, 1, 1, 0)
		_state_label.text = ""


func _exit_tree():
	# 立即隐藏，避免切场景那一帧残留
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
		_fade_tween = null
	if _state_label and is_instance_valid(_state_label):
		_state_label.visible = false
		_state_label.modulate = Color(1, 1, 1, 0)
		_state_label.text = ""
	if _canvas and is_instance_valid(_canvas):
		_canvas.visible = false
		_canvas.queue_free()
		_canvas = null
