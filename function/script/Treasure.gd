extends CanvasLayer

signal closed

var _rewards : Dictionary = {}

@onready var reward_container : VBoxContainer = $Panel/VBoxContainer/RewardContainer

func _ready():
	_roll_rewards()
	_populate_rewards()


# ============================================================
#  奖励生成
# ============================================================
func _roll_rewards():
	# 暂时：占位奖励
	# TODO: 从 MapNode 读取实际配置
	_rewards = {
		"gold": 50,
		"materials": {"粗铁": 2},
		"items": [],
	}


func _populate_rewards():
	for child in reward_container.get_children():
		child.queue_free()

	if _rewards.get("gold", 0) > 0:
		reward_container.add_child(_make_label("金币 +%d" % _rewards["gold"]))

	for mat_name in _rewards.get("materials", {}):
		var count = _rewards["materials"][mat_name]
		if count > 0:
			reward_container.add_child(_make_label("%s ×%d" % [mat_name, count]))

	for item_id in _rewards.get("items", []):
		var data = ItemManager.get_item_data(item_id)
		if data:
			reward_container.add_child(_make_label(data.name))


func _make_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


# ============================================================
#  信号回调（由 .tscn 连线）
# ============================================================
func _on_confirm_pressed():
	if _rewards.get("gold", 0) > 0:
		EconomyManager.add_temp_gold(_rewards["gold"])
	for mat_name in _rewards.get("materials", {}):
		var count = _rewards["materials"][mat_name]
		if count > 0:
			GameState.add_material(mat_name, count)
	for item_id in _rewards.get("items", []):
		Globals.unlock_item(item_id)

	closed.emit()
	queue_free()
