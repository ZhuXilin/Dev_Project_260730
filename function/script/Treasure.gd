extends CanvasLayer

signal closed

var _reward_options : Array = []
var _applied : bool = false
var _day : int = 1

@onready var title_label : Label = $Panel/VBoxContainer/TitleLabel
@onready var reward_container : VBoxContainer = $Panel/VBoxContainer/RewardContainer


func _ready():
	title_label.text = "选择奖励"


## 兼容两种调用：
##   setup(day: int)      — 推荐：按天数抽 3 条
##   setup(legacy: Dictionary) — 旧调用，用字典里的 day 字段（无则 1）
func setup(arg = 1):
	if arg is int:
		_day = int(arg)
	elif arg is Dictionary:
		_day = int((arg as Dictionary).get("day", 1))

	_reward_options = TreasureRewardManager.roll_n_rewards(_day, 3)

	# 池子彻底空 → 保底金币
	if _reward_options.is_empty():
		_reward_options = [
			{ "gold": 300 },
			{ "gold": 400 },
			{ "gold": 500 },
		]

	_build_options()


func _build_options():
	for child in reward_container.get_children():
		reward_container.remove_child(child)
		child.queue_free()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_container.add_child(hbox)

	for i in range(_reward_options.size()):
		var option : Dictionary = _reward_options[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 100)
		btn.add_theme_font_size_override("font_size", 7)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.text = _format_option_text(option)
		btn.pressed.connect(_on_option_selected.bind(i))
		hbox.add_child(btn)


func _format_option_text(option : Dictionary) -> String:
	var lines : Array = []
	var gold = int(option.get("gold", 0))
	var soul = int(option.get("soul", 0))
	var materials : Dictionary = option.get("materials", {})
	var items : Array = option.get("items", [])

	if gold > 0:
		lines.append("金币 +%d" % gold)
	if soul > 0:
		lines.append("魂 +%d" % soul)
	for mat in materials:
		lines.append("%s ×%d" % [mat, materials[mat]])
	for item_id in items:
		var d : ItemData = ItemManager.get_item_data(item_id)
		if d:
			lines.append("★ " + d.name)
		else:
			var rd : Dictionary = RelicManager.get_relic_data(item_id)
			if not rd.is_empty():
				lines.append("★ 遗物：" + rd.get("name", item_id))
			else:
				lines.append("★ " + item_id)

	if lines.is_empty():
		return "?"
	return "\n".join(lines)


func _on_option_selected(idx : int):
	if _applied: return
	if idx < 0 or idx >= _reward_options.size(): return
	_applied = true
	var option : Dictionary = _reward_options[idx]
	_apply_reward(option)

	# ★ 全屏遮挡：拦截一切鼠标点击
	var blocker : ColorRect = _create_input_blocker()
	await _show_popup(option)
	if is_instance_valid(blocker):
		blocker.queue_free()

	closed.emit()
	queue_free()


func _apply_reward(option : Dictionary):
	# ---- 金币 ----
	var gold : int = int(option.get("gold", 0))
	if gold > 0:
		EconomyManager.add_temp_gold(gold)
		print("[宝箱] 金币 +%d" % gold)

	# ---- 魂 ----
	var soul : int = int(option.get("soul", 0))
	if soul > 0:
		EconomyManager.add_temp_soul(soul)
		print("[宝箱] 魂 +%d" % soul)

	# ---- 材料 ----
	var materials : Dictionary = option.get("materials", {})
	for mat_name in materials:
		var amount : int = int(materials[mat_name])
		if amount > 0:
			EconomyManager.apply_material_reward({ mat_name: amount })
			print("[宝箱] 材料 %s ×%d" % [mat_name, amount])

	# ---- 装备 / 遗物 ----
	var items : Array = option.get("items", [])
	for item_id in items:
		_grant_item(item_id)


func _grant_item(item_id: String):
	if item_id == "":
		return

	# 遗物
	var relic_data : Dictionary = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		RelicManager.unlock_relic(item_id)
		var inst := ItemInstance.new()
		inst.item_id = item_id
		inst.count = 1
		if not GameState.add_relic_to_passive_slot(inst):
			print("[宝箱] 遗物 %s 解锁但未入槽（槽满）" % item_id)
		print("[宝箱] 遗物 %s" % item_id)
		return

	# 普通装备
	var item_data : ItemData = ItemManager.get_item_data(item_id)
	if not item_data:
		print("[宝箱] 警告：道具不存在 %s" % item_id)
		return

	Globals.unlock_item(item_id)
	var inst2 := ItemInstance.new()
	inst2.item_id = item_id
	inst2.count = 1
	GameState.pending_forge_rewards.append(inst2)
	print("[宝箱] 装备进待领取区: %s" % item_data.name)


func _show_popup(option : Dictionary):
	if Globals.is_item_get_popup_active:
		return
	var scene = load(Config.PATHS.ITEM_GET_POPUP)
	if not scene:
		return
	var popup = scene.instantiate()
	get_tree().root.add_child(popup)
	popup.show_text(_format_option_text(option))
	if popup.has_signal("closed"):
		await popup.closed
	else:
		await get_tree().create_timer(3.5, true, false, true).timeout


## 全屏透明遮挡层（拦截所有鼠标点击）
func _create_input_blocker() -> ColorRect:
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.z_index = 100
	add_child(blocker)
	return blocker
