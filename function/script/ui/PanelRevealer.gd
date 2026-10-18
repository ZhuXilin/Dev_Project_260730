class_name PanelRevealer
extends Node

const SHADER_PATH : String = "res://content/resource/shader/panel_reveal.gdshader"
const DEFAULT_SHOW_DURATION : float = 0.3
const DEFAULT_HIDE_DURATION : float = 0.2

var _target : Control = null
var _tween : Tween = null
var _mat : ShaderMaterial = null
var _saved_materials : Dictionary = {}


static func show_panel(panel: Control, duration: float = -1.0, _bg_color: Color = Color.BLACK) -> void:
	if panel == null: return
	if duration < 0.0: duration = DEFAULT_SHOW_DURATION
	
	panel.visible = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_get_or_create(panel)._play(duration, false)


static func hide_panel(panel: Control, duration: float = -1.0, _bg_color: Color = Color.BLACK) -> void:
	if panel == null: return
	if duration < 0.0: duration = DEFAULT_HIDE_DURATION
	
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_get_or_create(panel)._play(duration, true)


static func force_hide(panel: Control) -> void:
	if panel == null: return
	_get_or_create(panel)._force_hide()


static func _get_or_create(panel: Control) -> PanelRevealer:
	var existing = panel.get_node_or_null("__PanelRevealer")
	if existing is PanelRevealer:
		return existing as PanelRevealer
	var r := PanelRevealer.new()
	r.name = "__PanelRevealer"
	r._target = panel
	panel.add_child(r)
	r._setup()
	return r


func _setup():
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)


func _play(duration: float, hide_after: bool):
	if _target == null: return
	
	_mat.set_shader_parameter("mode", 1 if hide_after else 0)
	_mat.set_shader_parameter("progress", 0.0)
	
	# 递归给目标面板和其中所有文字、图标挂载裁剪 Shader
	_apply_material(_target)
	
	_kill_tween()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_method(func(v): _mat.set_shader_parameter("progress", v), 0.0, 1.0, duration)
	
	_tween.tween_callback(func():
		# 动画结束，恢复节点原本的材质
		_restore_materials()
		if hide_after and is_instance_valid(_target):
			_target.visible = false
	)


func _apply_material(node: Node):
	if node is CanvasItem:
		var c_node := node as CanvasItem
		if not _saved_materials.has(c_node):
			# 备份原始状态
			_saved_materials[c_node] = {
				"material": c_node.material,
				"use_parent_material": c_node.use_parent_material
			}
			# 强制应用我们的 Shader
			c_node.material = _mat
			c_node.use_parent_material = false
	
	for child in node.get_children():
		_apply_material(child)


func _restore_materials():
	for c_node in _saved_materials.keys():
		if is_instance_valid(c_node):
			var data = _saved_materials[c_node]
			c_node.material = data["material"]
			c_node.use_parent_material = data["use_parent_material"]
	_saved_materials.clear()


func _force_hide():
	_kill_tween()
	_restore_materials()
	if _target:
		_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_target.visible = false


func _kill_tween():
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
