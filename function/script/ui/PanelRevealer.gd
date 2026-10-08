class_name PanelRevealer
extends Node

# ============================================================
#  PanelRevealer — 面板扫描线刷入（按屏幕高度）
# ============================================================

const SHADER_PATH : String = "res://content/resource/shader/panel_reveal.gdshader"
const NODE_NAME : String = "__PanelRevealer"
const MASK_NODE_NAME : String = "__RevealMaskRect"

const DEFAULT_SHOW_DURATION : float = 0.22
const DEFAULT_HIDE_DURATION : float = 0.16

var _mask : ColorRect = null
var _mat : ShaderMaterial = null
var _tween : Tween = null
var _target : Control = null


# ============================================================
#  静态入口
# ============================================================
static func show_panel(panel: Control, duration: float = -1.0,
		bg_color: Color = Color(0.11, 0.11, 0.11)) -> void:
	if panel == null: return
	if duration < 0.0:
		duration = DEFAULT_SHOW_DURATION
	_get_or_create(panel)._play(duration, false, bg_color)


static func hide_panel(panel: Control, duration: float = -1.0,
		bg_color: Color = Color(0.11, 0.11, 0.11)) -> void:
	if panel == null: return
	if duration < 0.0:
		duration = DEFAULT_HIDE_DURATION
	_get_or_create(panel)._play(duration, true, bg_color)


func _play(duration: float, hide_after: bool, bg_color: Color):
	if _mat == null or _target == null or _mask == null:
		return

	if hide_after:
		_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		_target.visible = true
		_target.mouse_filter = Control.MOUSE_FILTER_STOP

	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bounds := _compute_uv_bounds()
	_mat.set_shader_parameter("uv_y_top", bounds.x)
	_mat.set_shader_parameter("uv_y_bottom", bounds.y)

	# ★ 设置 mask 颜色
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
		if is_instance_valid(_mask):
			_mask.visible = false
		if hide_after and is_instance_valid(_target):
			_target.visible = false
	)


static func force_hide(panel: Control) -> void:
	if panel == null: return
	_get_or_create(panel)._force_hide()


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
	_mat.set_shader_parameter("uv_y_top", 0.0)
	_mat.set_shader_parameter("uv_y_bottom", 1.0)

	_mask = ColorRect.new()
	_mask.name = MASK_NODE_NAME
	_mask.color = Color.WHITE
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.z_index = 4096
	_mask.material = _mat
	_target.add_child(_mask)

	# ★★★ 关键：这里一定要用 set_anchors_and_offsets_preset ★★★
	# 只用 set_anchors_preset 的话，offset 不重算，mask 实际是 (0,0) 大小 → 看不见效果
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.visible = false

	# 面板尺寸变化时同步 mask 尺寸
	_target.resized.connect(func():
		if is_instance_valid(_mask):
			_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	)


## 计算 mask 的 UV 坐标映射：屏幕顶/底对应 mask 上的 UV.y 值
func _compute_uv_bounds() -> Vector2:
	if _mask == null or _target == null:
		return Vector2(0.0, 1.0)

	var mask_y : float = _mask.global_position.y
	var mask_h : float = maxf(_mask.size.y, 1.0)
	var vp_h : float = get_viewport().get_visible_rect().size.y

	var uv_top : float = (0.0 - mask_y) / mask_h
	var uv_bottom : float = (vp_h - mask_y) / mask_h
	return Vector2(uv_top, uv_bottom)
	

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
		_tween.kill()
	_tween = null
