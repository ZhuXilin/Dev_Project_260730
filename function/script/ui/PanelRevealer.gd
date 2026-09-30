class_name PanelRevealer
extends Node

# ============================================================
#  PanelRevealer — 面板扫描线刷入
#
#  MaskRect 直接挂在 Panel 下 → PanelContainer 会自动撑满它，
#  位置/大小与 Panel 内容区一致，不会错乱。
# ============================================================

const SHADER_PATH : String = "res://content/resource/shader/panel_reveal.gdshader"
const NODE_NAME : String = "__PanelRevealer"
const MASK_NODE_NAME : String = "__RevealMaskRect"

var _mask : ColorRect = null
var _mat : ShaderMaterial = null
var _tween : Tween = null
var _target : Control = null


# ============================================================
#  静态入口
# ============================================================
static func show_panel(panel: Control, duration: float = 0.22) -> void:
	if panel == null: return
	var r := _get_or_create(panel)
	r._play(0.0, 1.0, duration, false)


static func hide_panel(panel: Control, duration: float = 0.18) -> void:
	if panel == null: return
	var r := _get_or_create(panel)
	r._play(1.0, 0.0, duration, true)


static func force_hide(panel: Control) -> void:
	if panel == null: return
	var r := _get_or_create(panel)
	r._force_hide()


static func is_active(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
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


# ============================================================
#  实例
# ============================================================
func _setup():
	var shader : Shader = load(SHADER_PATH)
	if shader == null:
		push_error("[PanelRevealer] shader 加载失败: " + SHADER_PATH)
		return

	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("progress", 1.0)

	# ★ 直接挂 Panel 下，PanelContainer 会自动撑满
	_mask = ColorRect.new()
	_mask.name = MASK_NODE_NAME
	_mask.color = Color.WHITE
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.z_index = 4096
	_mask.material = _mat
	_target.add_child(_mask)
	_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mask.visible = false


func _play(from_v: float, to_v: float, duration: float, hide_after: bool):
	if _mat == null or _target == null or _mask == null:
		return

	if hide_after:
		_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		_target.visible = true
		_target.mouse_filter = Control.MOUSE_FILTER_STOP

	_mask.visible = true

	_kill_tween()
	_mat.set_shader_parameter("progress", from_v)

	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_method(
		func(v): if is_instance_valid(_mat): _mat.set_shader_parameter("progress", v),
		from_v, to_v, duration
	)
	_tween.tween_callback(func():
		if is_instance_valid(_mask):
			_mask.visible = false
		if hide_after and is_instance_valid(_target):
			_target.visible = false
	)


func _force_hide():
	_kill_tween()
	if _mat:
		_mat.set_shader_parameter("progress", 1.0)
	if _mask:
		_mask.visible = false
	if _target:
		_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_target.visible = false


func _kill_tween():
	if _tween == null:
		return
	if not is_instance_valid(_tween):
		_tween = null
		return
	if _tween.is_valid():
		_tween.custom_step(999.0)
		_tween.kill()
	_tween = null
