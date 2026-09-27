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
##   setup(day: int)            — 按天数决定数值缩放
##   setup(legacy: Dictionary)  — 老调用，读 day 字段（默认 1）
func setup(arg = 1):
	if arg is int:
		_day = int(arg)
	elif arg is Dictionary:
		_day = int((arg as Dictionary).get("day", 1))

	_reward_options = _roll_three_options()
	_build_options()


# ============================================================
#  生成 3 个侧重点不同的选项
# ============================================================
func _roll_three_options() -> Array:
	var result : Array = []
	result.append(_roll_gold_option())
	result.append(_roll_armor_option())
	var relic_opt : Dictionary = _roll_relic_option()
	if relic_opt.is_empty():
		# 遗物池空 → 再给一个金币选项作为补偿
		result.append(_roll_gold_option())
	else:
		result.append(relic_opt)
	return result


## 金币选项：主金币 + 少量魂
func _roll_gold_option() -> Dictionary:
	var gold_base : int = 600 if _day <= 1 else 1000
	var gold : int = gold_base + randi() % 400    # 600-1000 或 1000-1400
	var soul : int = 2 + randi() % 3              # 2-4
	return {
		"kind": "gold",
		"gold": gold,
		"soul": soul,
	}


## 防具选项：1 件高级防具（epic/legendary）+ 少量金币
func _roll_armor_option() -> Dictionary:
	# Day1：只出 epic；Day2+：epic 或 legendary
	var target_quality : Array = ["epic", "legendary"] if _day >= 2 else ["epic"]
	var pool : Array = []
	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if not d: continue
		if d.type != "armor": continue
		if d.quality not in target_quality: continue
		if d.price <= 0: continue
		pool.append(iid)

	# 降级：连 price=0 的也算上（保底能出东西）
	if pool.is_empty():
		for iid in ItemManager.get_all_item_ids():
			var d : ItemData = ItemManager.get_item_data(iid)
			if not d: continue
			if d.type != "armor": continue
			if d.quality not in ["epic", "legendary"]: continue
			pool.append(iid)

	if pool.is_empty():
		return _roll_gold_option()

	var pick : String = pool[randi() % pool.size()]
	var gold : int = 150 + randi() % 150    # 150-300
	return {
		"kind": "armor",
		"gold": gold,
		"items": [pick],
	}


## 遗物选项：1 件随机未拥有遗物 + 少量魂
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
	var soul : int = 3 + randi() % 3    # 3-5
	return {
		"kind": "relic",
		"soul": soul,
		"items": [pick],
	}


# ============================================================
#  显示
# ============================================================
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
	var kind : String = option.get("kind", "")

	# ★ 顶部标题（明确侧重）
	match kind:
		"gold":   lines.append("【金币奖励】")
		"armor":  lines.append("【强力防具】")
		"relic":  lines.append("【遗物】")
		_:        pass

	lines.append("")

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
				lines.append("★ " + rd.get("name", item_id))
			else:
				lines.append("★ " + item_id)

	return "\n".join(lines)


# ============================================================
#  选择 / 应用
# ============================================================
func _on_option_selected(idx : int):
	if _applied: return
	if idx < 0 or idx >= _reward_options.size(): return
	_applied = true
	var option : Dictionary = _reward_options[idx]
	_apply_reward(option)

	# 全屏遮挡：拦截一切鼠标点击
	var blocker : ColorRect = _create_input_blocker()
	await _show_popup(option)
	if is_instance_valid(blocker):
		blocker.queue_free()

	closed.emit()
	queue_free()


func _apply_reward(option : Dictionary):
	# 金币
	var gold : int = int(option.get("gold", 0))
	if gold > 0:
		EconomyManager.add_temp_gold(gold)
		print("[宝箱] 金币 +%d" % gold)

	# 魂
	var soul : int = int(option.get("soul", 0))
	if soul > 0:
		EconomyManager.add_temp_soul(soul)
		print("[宝箱] 魂 +%d" % soul)

	# 材料
	var materials : Dictionary = option.get("materials", {})
	for mat_name in materials:
		var amount : int = int(materials[mat_name])
		if amount > 0:
			EconomyManager.apply_material_reward({ mat_name: amount })
			print("[宝箱] 材料 %s ×%d" % [mat_name, amount])

	# 装备 / 遗物
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


## 全屏透明遮挡层
func _create_input_blocker() -> ColorRect:
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.z_index = 100
	add_child(blocker)
	return blocker
