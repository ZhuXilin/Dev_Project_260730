extends Node
class_name TurnLayerManager

@export var transition_duration : float = UIConst.TURN_TRANSITION_DURATION

# ★ 与 TurnRect 的 color 一致，避免"黑底"
const MASK_COLOR : Color = Color(0.191, 0.253, 0.527)

var turn_overlay : ColorRect
var _text_label : Label = null


func initialize(overlay: ColorRect):
	turn_overlay = overlay
	if turn_overlay:
		turn_overlay.modulate = Color(1, 1, 1, 1)
		turn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		PanelRevealer.force_hide(turn_overlay)

		_text_label = turn_overlay.get_node_or_null("Text") as Label
		if not _text_label:
			push_error("FadeOverlay 下缺少名为 'Text' 的 Label 节点！")
		else:
			_text_label.visible = false
			_text_label.modulate.a = 1.0
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
		var turn_num = Globals.current_battle_turn
		if team == 0:
			_text_label.text = UIConst.TURN_TEXT_PLAYER % turn_num
		else:
			_text_label.text = UIConst.TURN_TEXT_ENEMY % turn_num
		_text_label.visible = true
		_text_label.modulate.a = 1.0

	# ★ 扫描线揭示（蓝色 mask）
	PanelRevealer.show_panel(turn_overlay, transition_duration * 0.35, MASK_COLOR)
	await get_tree().create_timer(transition_duration * 0.35, true, false, true).timeout

	if callback.is_valid():
		callback.call()

	# 停留
	await get_tree().create_timer(transition_duration * 0.35, true, false, true).timeout

	# ★ 扫描线收起（蓝色 mask）
	PanelRevealer.hide_panel(turn_overlay, transition_duration * 0.30, MASK_COLOR)
	await get_tree().create_timer(transition_duration * 0.30, true, false, true).timeout

	if _text_label:
		_text_label.visible = false

	turn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Globals.is_fading = false


func set_overlay_size(size: Vector2):
	if turn_overlay:
		turn_overlay.size = size
		if _text_label:
			_text_label.size = size
