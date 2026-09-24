extends CanvasLayer

signal closed

var _reward_options : Array = []
var _applied : bool = false

@onready var title_label : Label = $Panel/VBoxContainer/TitleLabel
@onready var reward_container : VBoxContainer = $Panel/VBoxContainer/RewardContainer


func _ready():
	title_label.text = "选择奖励"


func setup(_rewards: Dictionary):
	_reward_options = _roll_three_options()
	_build_options()


func _roll_three_options() -> Array:
	var result : Array = []

	# ---- 选项 1：金币 ----
	result.append({
		"type": "gold",
		"amount": 200 + randi() % 300,  # 200-500
	})

	# ---- 选项 2：遗物 ----
	var relic_pool : Array = []
	var owned : Dictionary = {}
	for p in GameState.get_relics_from_passives():
		owned[p.item_id] = true
	for rid in RelicManager.get_unlocked_relics():
		if not owned.has(rid):
			relic_pool.append(rid)
	if not relic_pool.is_empty():
		relic_pool.shuffle()
		result.append({"type": "relic", "id": relic_pool[0]})
	else:
		# 池子空 → 给金币
		result.append({"type": "gold", "amount": 400})

	# ---- 选项 3：高级装备 ----
	var armor_pool : Array = []
	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if not d: continue
		if d.type != "armor": continue
		if d.quality not in ["epic", "legendary"]: continue
		if d.price <= 0: continue
		armor_pool.append(iid)
	if not armor_pool.is_empty():
		armor_pool.shuffle()
		result.append({"type": "armor", "id": armor_pool[0]})
	else:
		result.append({"type": "gold", "amount": 300})

	return result


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
	var t : String = option.get("type", "")
	match t:
		"gold":
			return "金币\n+%d" % option["amount"]
		"relic":
			var rd : Dictionary = RelicManager.get_relic_data(option["id"])
			return "★ 遗物\n%s" % rd.get("name", "?")
		"armor":
			var d : ItemData = ItemManager.get_item_data(option["id"])
			return "★ 装备\n%s" % (d.name if d else "?")
	return "?"


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
	var t : String = option.get("type", "")
	match t:
		"gold":
			EconomyManager.add_temp_gold(option["amount"])
			print("[宝箱] 金币 +%d" % option["amount"])
		"relic":
			var rid : String = option["id"]
			RelicManager.unlock_relic(rid)
			var inst := ItemInstance.new()
			inst.item_id = rid
			inst.count = 1
			if not GameState.add_relic_to_passive_slot(inst):
				print("[宝箱] 遗物 %s 解锁但未入槽（槽满）" % rid)
			print("[宝箱] 遗物 %s" % rid)
		"armor":
			var iid : String = option["id"]
			var d : ItemData = ItemManager.get_item_data(iid)
			if d:
				Globals.unlock_item(iid)
				var inst2 := ItemInstance.new()
				inst2.item_id = iid
				inst2.count = 1
				GameState.pending_forge_rewards.append(inst2)
				print("[宝箱] 装备进待领取区: %s" % d.name)


func _show_popup(option : Dictionary):
	if Globals.is_item_get_popup_active: return
	var scene = load(Config.PATHS.ITEM_GET_POPUP)
	if not scene: return
	var popup = scene.instantiate()
	get_tree().root.add_child(popup)
	var t : String = option.get("type", "")
	match t:
		"gold":
			popup.show_text("金币 +%d" % option["amount"])
		"relic":
			popup.show_relic(option["id"], 1)
		"armor":
			popup.show_item(option["id"], 1)
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
