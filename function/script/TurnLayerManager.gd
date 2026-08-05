extends Node
class_name TurnLayerManager

@export var transition_duration : float = 1.0

var turn_overlay : ColorRect
var _text_label : Label = null

func initialize(overlay: ColorRect):
	turn_overlay = overlay
	if turn_overlay:
		turn_overlay.modulate = Color(1, 1, 1, 0)
		turn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		_text_label = turn_overlay.get_node_or_null("Text") as Label
		if not _text_label:
			push_error("FadeOverlay 下缺少名为 'Text' 的 Label 节点！")
		else:
			_text_label.visible = false
			_text_label.modulate.a = 0.0
	else:
		push_error("FadeOverlay 未设置！")

func play_transition(team: int, callback: Callable = Callable()):
	if not turn_overlay:
		if callback.is_valid():
			callback.call()
		return
	
	Globals.is_fading = true
	turn_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	
	turn_overlay.modulate.a = 1.0
	if _text_label:
		# 修改：根据队伍显示带回合数的文字
		var turn_num = Globals.current_battle_turn
		if team == 0:
			_text_label.text = "我方第 " + str(turn_num) + " 回合"
		else:
			_text_label.text = "敌方第 " + str(turn_num) + " 回合"
		_text_label.visible = true
		_text_label.modulate.a = 1.0
	
	await get_tree().create_timer(transition_duration).timeout
	
	if callback.is_valid():
		callback.call()
	
	turn_overlay.modulate.a = 0.0
	if _text_label:
		_text_label.visible = false
		_text_label.modulate.a = 0.0
	
	turn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Globals.is_fading = false

func set_overlay_size(size: Vector2):
	if turn_overlay:
		turn_overlay.size = size
		if _text_label:
			_text_label.size = size
