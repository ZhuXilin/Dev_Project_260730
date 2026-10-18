class_name PanelRevealer
extends Node

const SHADER_PATH : String = "res://content/resource/shader/panel_reveal.gdshader"
const NODE_NAME : String = "__PanelRevealer"
const MASK_NODE_NAME : String = "__RevealMaskRect"

const DEFAULT_SHOW_DURATION : float = 0.22
const DEFAULT_HIDE_DURATION : float = 0.16

# ★ 改回 8bit 面板的默认深灰色
const DEFAULT_BG_COLOR : Color = Color(0.11, 0.11, 0.11)

var _mask : ColorRect = null
var _mat : ShaderMaterial = null
var _tween : Tween = null
var _target : Control = null


static func show_panel(panel: Control, duration: float = -1.0, bg_color: Color = DEFAULT_BG_COLOR) -> void:
	if panel == null: return
	if duration < 0.0: duration = DEFAULT_SHOW_DURATION
	_get_or_create(panel)._play(duration, false, bg_color)


static func hide_panel(panel: Control, duration: float = -1.0, bg_color: Color = DEFAULT_BG_COLOR) -> void:
	if panel == null: return
	if duration < 0.0: duration = DEFAULT_HIDE_DURATION
	_get_or_create(panel)._play(duration, true, bg_color)


func _play(duration: float, hide_after: bool, bg_color: Color):
	if _mat == null or _target == null or _mask == null:
		return

	if hide_after:
		_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		_target.visible = true
		_target.mouse_filter = Control.MOUSE_FILTER_STOP

	# 确保遮罩完全覆盖目标面板
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 直接使用传入的颜色（或默认深灰），不再做全局坐标映射
	_mat.set_shader_parameter("bg_color", bg_color)
	_mask.visible = true
	_kill_tween()

	_mat.set_shader_parameter("mode", 1 if hide_after else 0)
	_mat.set_shader_parameter("progress", 0.0)

	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_method(
		func(v): if is_instance_valid(_mat): _mat.set_shader_parameter("progress", v),
		0.0, 1.0, duration
	)
	_tween.tween_callback(func():
		if is_instance_valid(_mask): _mask.visible = false
		if hide_after and is_instance_valid(_target): _target.visible = false
	)


static func force_hide(panel: Control) -> void:
	if panel == null: return
	_get_or_create(panel)._force_hide()

static func is_active(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel): return false
	return panel.visible and panel.mouse_filter == Control.MOUSE_FILTER_STOP

static func _get_or_create(panel: Control) -> PanelRevealer:
	var existing = panel.get_node_or_null(NODE_NAME)
	if existing is PanelRevealer:
		return existing as PanelRevealer
	var r := PanelRevealer.new()
	r.name = NODE_NAME
	r._target = panel
	panel.add_child(r)
	r._setup()
	return r


func _setup():
	var shader : Shader = load(SHADER_PATH)
	if shader == null: return

	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("progress", 1.0)

	_mask = ColorRect.new()
	_mask.name = MASK_NODE_NAME
	_mask.color = Color.WHITE
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.z_index = 4096
	_mask.material = _mat
	_target.add_child(_mask)

	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.visible = false

	_target.resized.connect(func():
		if is_instance_valid(_mask):
			_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	)


func _force_hide():
	_kill_tween()
	if _mat: _mat.set_shader_parameter("progress", 1.0)
	if _mask: _mask.visible = false
	if _target:
		_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_target.visible = false


func _kill_tween():
	if _tween == null: return
	if not is_instance_valid(_tween): _tween = null; return
	if _tween.is_valid(): _tween.kill()
	_tween = null
