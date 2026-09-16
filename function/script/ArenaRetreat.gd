extends CanvasLayer

signal closed(choice: String)

@onready var title_label : Label = $Panel/TitleLabel
@onready var info_label : Label = $Panel/InfoLabel


func setup(data: Dictionary):
	var is_elite = data.get("is_elite", false)
	var next_battle_index = data.get("battle_index", 5)
	var crystals = data.get("crystals", 0)
	var gold = data.get("gold", 0)
	var streak = data.get("streak", 0)
	var retreat_gain = int(crystals * 0.8)

	title_label.text = "%s战 · 第 %d 战" % ["精英" if is_elite else "BOSS", next_battle_index]
	info_label.text = "当前结晶：%d\n当前金币：%d\n连胜：%d\n\n撤离：+%d 结晶（80%%）" % [
		crystals, gold, streak, retreat_gain
	]


func _on_retreat_pressed():
	closed.emit("retreat")
	queue_free()


func _on_challenge_pressed():
	closed.emit("challenge")
	queue_free()
