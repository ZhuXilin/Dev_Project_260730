extends Node
class_name ScreenShake

@export var default_duration : float = 0.15
@export var default_intensity : float = 4.0
@export var crit_intensity : float = 10.0
@export var miss_intensity : float = 0.0  # 回避无震动

var camera : Camera2D
var tween : Tween

func _ready():
	camera = get_parent() as Camera2D
	if not camera:
		push_error("ScreenShake must be child of Camera2D")

func shake(duration: float = default_duration, intensity: float = default_intensity, direction: Vector2 = Vector2.ZERO):
	if not camera or not is_instance_valid(camera):
		return
	if tween and tween.is_valid():
		tween.kill()
	tween = create_tween()
	var offset: Vector2
	if direction != Vector2.ZERO:
		offset = direction.normalized() * intensity
	else:
		offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
	tween.tween_property(camera, "offset", offset, duration * 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(camera, "offset", Vector2.ZERO, duration * 0.9).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
