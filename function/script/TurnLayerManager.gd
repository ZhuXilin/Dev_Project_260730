extends Node
class_name TurnLayerManager

@export var transition_duration : float = UIConst.TURN_TRANSITION_DURATION

# ★ v6.72at：底图已换成 8bit_style_box_info.tres（Panel），不再靠纯色遮罩，
#   这个颜色只作为 PanelRevealer 的历史参数保留（其内部已改为 shader 扫线，不再使用）。
const MASK_COLOR : Color = Color(0.191, 0.253, 0.527)

var turn_overlay : Control
var _text_label : Label = null


func initialize(overlay: Control):
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

	var lines := _build_lines(team)
	if lines.size() > 0:
		_set_line(lines[0])

	# ★ 扫描线揭示（蓝色 mask）
	PanelRevealer.show_panel(turn_overlay, transition_duration * 0.35, MASK_COLOR)
	await get_tree().create_timer(transition_duration * 0.35, true, false, true).timeout

	if callback.is_valid():
		callback.call()

	# ★ v6.72at：有多行时按先后顺序播报——背景面板只有一个，只换文字，
	#   行与行之间先淡出再淡入（间隔 transition_duration * 0.18），
	#   每行停留 transition_duration * 0.35，保证玩家能读完。
	for i in lines.size():
		if i > 0:
			await _swap_line(lines[i], transition_duration * 0.18)
		await get_tree().create_timer(transition_duration * 0.35, true, false, true).timeout

	# ★ 扫描线收起（蓝色 mask）
	PanelRevealer.hide_panel(turn_overlay, transition_duration * 0.30, MASK_COLOR)
	await get_tree().create_timer(transition_duration * 0.30, true, false, true).timeout

	if _text_label:
		_text_label.visible = false

	turn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Globals.is_fading = false


## 组装本次要播报的文字行：第 1 行回合归属，敌方增援时再加第 2 行波次
func _build_lines(team: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var turn_num : int = Globals.current_battle_turn
	if team == 0:
		lines.append(UIConst.TURN_TEXT_PLAYER % turn_num)
	else:
		lines.append(UIConst.TURN_TEXT_ENEMY % turn_num)
		# ★ 核心修改：波次数字 -1，更符合直觉
		if WaveManager and WaveManager.is_active() and WaveManager.get_current_wave() > 1:
			lines.append("第 %d 波增援" % (WaveManager.get_current_wave() - 1))
	return lines


func _set_line(text: String) -> void:
	if _text_label == null:
		return
	_text_label.text = text
	_text_label.visible = true
	_text_label.modulate.a = 1.0


## 换行：旧字淡出 → 换文本 → 新字淡入，总时长 gap，背景面板保持不动
func _swap_line(text: String, gap: float) -> void:
	if _text_label == null:
		return
	var half : float = max(gap * 0.5, 0.01)
	var out_tw := create_tween()
	out_tw.set_ignore_time_scale(true)
	out_tw.tween_property(_text_label, "modulate:a", 0.0, half)
	await out_tw.finished
	_text_label.text = text
	var in_tw := create_tween()
	in_tw.set_ignore_time_scale(true)
	in_tw.tween_property(_text_label, "modulate:a", 1.0, half)
	await in_tw.finished


func set_overlay_size(size: Vector2):
	if turn_overlay:
		turn_overlay.size = size
		if _text_label:
			_text_label.size = size
