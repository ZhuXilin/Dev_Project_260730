extends CanvasLayer

signal closed

var _reward_options : Array = []
var _applied : bool = false
var _day : int = 1
var _treasure_cfg : Dictionary = {}
var _is_premium : bool = false

@onready var title_label : Label = $Panel/VBoxContainer/TitleLabel
@onready var reward_container : VBoxContainer = $Panel/VBoxContainer/RewardContainer


func _ready():
	_treasure_cfg = GameConfigManager.get_value("economy_config.json", "treasure", {})
	title_label.text = "发现了一个宝箱..."
	_show_choice_ui()


func setup(arg = 1):
	if arg is int:
		_day = int(arg)
	elif arg is Dictionary:
		_day = int((arg as Dictionary).get("day", 1))

	if not _applied and reward_container.get_child_count() == 0:
		_show_choice_ui()


# ============================================================
#  界面 1：选择开启方式
# ============================================================
func _show_choice_ui():
	for child in reward_container.get_children():
		reward_container.remove_child(child)
		child.queue_free()

	var info := Label.new()
	info.text = "当前【死眠之钥】：%d / 1\n" % GameState.keys
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_container.add_child(info)

	var btn_normal := Button.new()
	btn_normal.text = "普通开启（随机 3 选 1）"
	btn_normal.custom_minimum_size = Vector2(150, 30)
	btn_normal.pressed.connect(_on_open_normal)
	reward_container.add_child(btn_normal)

	var btn_premium := Button.new()
	btn_premium.text = "高级隐藏开启（消耗 1 钥匙）\n必出史诗 / 极高概率出遗物"
	btn_premium.custom_minimum_size = Vector2(150, 40)
	btn_premium.disabled = (GameState.keys <= 0)

	if GameState.keys > 0:
		btn_premium.modulate = Color(1.0, 0.85, 0.3)
		btn_premium.pressed.connect(_on_open_premium)
	else:
		btn_premium.text += "\n（无钥匙）"

	reward_container.add_child(btn_premium)


# ============================================================
#  界面 2：展示奖励选项
# ============================================================
func _on_open_normal():
	_is_premium = false
	_start_roll()


func _on_open_premium():
	_is_premium = true
	GameState.keys = maxi(0, GameState.keys - 1)
	SaveManager.auto_save()
	_start_roll()


func _start_roll():
	title_label.text = "选择奖励"
	_reward_options = _roll_three_options()
	_build_options()


func _roll_three_options() -> Array:
	var result : Array = []
	var types : Array = _roll_option_types()
	for t in types:
		match t:
			"gold":
				result.append(_roll_gold_option())
			"armor":
				var armor_opt = _roll_armor_option()
				if armor_opt.is_empty():
					result.append(_roll_gold_option())
				else:
					result.append(armor_opt)
			"relic":
				var r : Dictionary = _roll_relic_option()
				if r.is_empty():
					result.append(_roll_gold_option())
				else:
					result.append(r)
			_:
				result.append(_roll_gold_option())
	return result


func _roll_option_types() -> Array:
	var weights : Dictionary = _treasure_cfg.get(
		"option_weights", {"gold": 3, "armor": 2, "relic": 1})

	if _is_premium:
		weights = {"gold": 1, "armor": 2, "relic": 8}

	var pool : Array = []
	for k in weights:
		for i in range(maxi(1, int(weights[k]))):
			pool.append(k)

	if pool.is_empty():
		pool = ["gold", "armor", "relic"]

	var result : Array = []
	var safety : int = 0
	# ★ 修复：三选项严格不重复；safety 从 50 提到 200，避免极端权重下死循环
	while result.size() < 3 and safety < 200:
		safety += 1
		var pick : String = pool[randi() % pool.size()]
		if pick in result:
			continue
		result.append(pick)

	while result.size() < 3:
		result.append("gold")

	return result


func _roll_gold_option() -> Dictionary:
	var gold_base : int
	var gold_var : int
	if _day <= 1:
		gold_base = int(_treasure_cfg.get("day1_gold_base", 600))
		gold_var = int(_treasure_cfg.get("day1_gold_var", 400))
	else:
		gold_base = int(_treasure_cfg.get("day2_gold_base", 1000))
		gold_var = int(_treasure_cfg.get("day2_gold_var", 400))

	if _is_premium:
		gold_base = int(gold_base * 1.8)

	var gold : int = gold_base + randi() % maxi(1, gold_var)

	var soul_base : int = int(_treasure_cfg.get("soul_base", 2))
	var soul_var : int = int(_treasure_cfg.get("soul_var", 3))
	var soul : int = soul_base + randi() % maxi(1, soul_var)

	if _is_premium:
		# v4.5 修复：魂也按 ×1.8 缩放，与文档 4.6/6.11 一致
		soul = int(soul * 1.8)

	return {"kind": "gold", "gold": gold, "soul": soul}


func _roll_armor_option() -> Dictionary:
	var target_quality : Array
	if _is_premium:
		target_quality = ["epic", "legendary"]
	elif _day >= 2:
		target_quality = ["epic", "legendary"]
	else:
		target_quality = ["epic"]

	var pool : Array = []
	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if not d:
			continue
		if d.type != "armor":
			continue
		if d.quality not in target_quality:
			continue
		if d.price <= 0:
			continue
		pool.append(iid)

	if pool.is_empty():
		return _roll_gold_option()

	var pick : String = pool[randi() % pool.size()]
	var gold_base : int = int(_treasure_cfg.get("armor_gold_base", 150))
	var gold_var : int = int(_treasure_cfg.get("armor_gold_var", 150))
	var gold : int = gold_base + randi() % maxi(1, gold_var)

	if _is_premium:
		gold = int(gold * 2.0)

	return {"kind": "armor", "gold": gold, "items": [pick]}


func _roll_relic_option() -> Dictionary:
	var pool : Array = []
	var owned : Dictionary = {}
	for p in GameState.get_relics_from_passives():
		owned[p.item_id] = true

	for rid in RelicManager.get_unlocked_relics():
		if not owned.has(rid):
			pool.append(rid)

	if pool.is_empty():
		return {}

	var pick : String = pool[randi() % pool.size()]
	var soul_base : int = int(_treasure_cfg.get("relic_soul_base", 3))
	var soul_var : int = int(_treasure_cfg.get("relic_soul_var", 3))
	var soul : int = soul_base + randi() % maxi(1, soul_var)

	if _is_premium:
		soul += 2

	return {"kind": "relic", "soul": soul, "items": [pick]}


func _build_options():
	for child in reward_container.get_children():
		reward_container.remove_child(child)
		child.queue_free()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_container.add_child(hbox)

	var texts : Array = []
	var max_lines : int = 0
	for i in range(_reward_options.size()):
		var t : String = _format_option_text(_reward_options[i])
		texts.append(t)
		max_lines = maxi(max_lines, t.split("\n").size())

	var card_height : int = maxi(90, max_lines * 11 + 20)

	for i in range(_reward_options.size()):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, card_height)
		btn.add_theme_font_size_override("font_size", 7)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.text = texts[i]
		if _is_premium:
			btn.modulate = Color(1.0, 0.9, 0.6)
		btn.pressed.connect(_on_option_selected.bind(i))
		hbox.add_child(btn)


func _on_option_selected(idx : int):
	if _applied:
		return
	if idx < 0 or idx >= _reward_options.size():
		return

	_applied = true
	var option : Dictionary = _reward_options[idx]
	_apply_reward(option)

	# 移除遗留的碎片逻辑，单纯展示高级物品
	
	var blocker : ColorRect = _create_input_blocker()
	await _show_popup(option)
	if is_instance_valid(blocker):
		blocker.queue_free()

	closed.emit()
	queue_free()

func _format_option_text(option : Dictionary) -> String:
	var lines : Array = []
	var kind : String = option.get("kind", "")

	match kind:
		"gold":
			lines.append("【金币奖励】")
		"armor":
			lines.append("【史诗防具】" if _is_premium else "【强力防具】")
		"relic":
			lines.append("【传说遗物】")
		_:
			pass

	lines.append("")

	var gold = int(option.get("gold", 0))
	var soul = int(option.get("soul", 0))
	var items : Array = option.get("items", [])

	if gold > 0:
		lines.append("金币 +%d" % gold)
	if soul > 0:
		lines.append("魂 +%d" % soul)

	for item_id in items:
		var d : ItemData = ItemManager.get_item_data(item_id)
		if d:
			lines.append("★ " + d.name)
		else:
			var rd : Dictionary = RelicManager.get_relic_data(item_id)
			lines.append("★ " + rd.get("name", item_id))
			
	# 附加提示死眠效果
	if _is_premium:
		lines.append("\n(死眠之钥效果：必出史诗及以上)")

	return "\n".join(lines)


func _apply_reward(option : Dictionary):
	var gold : int = int(option.get("gold", 0))
	if gold > 0:
		EconomyManager.add_temp_gold(gold)

	var soul : int = int(option.get("soul", 0))
	if soul > 0:
		EconomyManager.add_soul(soul)

	var items : Array = option.get("items", [])
	for item_id in items:
		_grant_item(item_id)


func _grant_item(item_id: String):
	if item_id == "":
		return

	var relic_data : Dictionary = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		RelicManager.unlock_relic(item_id)
		var inst := ItemInstance.new()
		inst.item_id = item_id
		inst.count = 1
		if not GameState.add_relic_to_passive_slot(inst):
			print("[宝箱] 遗物 %s 解锁但未入槽（槽满）" % item_id)
		return

	var item_data : ItemData = ItemManager.get_item_data(item_id)
	if not item_data:
		return

	Globals.unlock_item(item_id)
	var inst2 : ItemInstance = ItemManager.create_instance_with_affixes(item_id)
	if inst2 == null:
		inst2 = ItemInstance.new()
		inst2.item_id = item_id
		inst2.count = 1

	GameState.pending_forge_rewards.append(inst2)


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


func _create_input_blocker() -> ColorRect:
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.z_index = 100
	add_child(blocker)
	return blocker
