extends CanvasLayer

signal closed

@onready var title_label : Label = $Panel/TitleLabel
@onready var body_label : Label = $Panel/BodyLabel


func setup(data: Dictionary):
	var success = data.get("success", false)
	var reason = data.get("reason", "")
	var streak = data.get("streak", 0)
	var survival_round = data.get("survival_round", 0)
	var crystals = data.get("crystals", 0)
	var soul_gain = data.get("soul_gain", 0)

	title_label.text = ("成功 · %s" % reason) if success else ("结束 · %s" % reason)
	title_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3, 1) if success else Color(1.0, 0.4, 0.4, 1))

	var lines = []
	match reason:
		"生存通过":
			lines.append("普通阶段：%d 胜" % streak)
			lines.append("生存模式：%d 胜" % survival_round)
		"通关":
			lines.append("普通阶段：%d 胜（通关）" % streak)
		"撤离":
			lines.append("普通阶段：%d 胜" % streak)
			lines.append("主动撤离")
		"失败":
			lines.append("普通阶段：%d 胜" % streak)
			lines.append("（失败）")
		"放弃":
			lines.append("普通阶段：%d 胜" % streak)
			lines.append("（主动放弃）")

	lines.append("────────────")
	lines.append("结晶：%d" % crystals)
	lines.append("兑换魂：+%d" % soul_gain)

	body_label.text = "\n".join(lines)


func _on_confirm_pressed():
	closed.emit()
	queue_free()
