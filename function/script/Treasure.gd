extends CanvasLayer

signal closed

var _rewards : Dictionary = {}
var _applied : bool = false

@onready var title_label : Label = $Panel/VBoxContainer/TitleLabel
@onready var reward_container : VBoxContainer = $Panel/VBoxContainer/RewardContainer


func _ready():
	title_label.text = "宝箱"
	# 内容由 setup() 填充


## 外部传入奖励（MapScene 调用）
func setup(rewards: Dictionary):
	_rewards = rewards.duplicate(true)
	# ★ 50% 概率额外给稀有掉落
	if randf() < 0.5:
		var rare_item : String = _roll_rare_drop()
		if rare_item != "":
			if not _rewards.has("items"):
				_rewards["items"] = []
			_rewards["items"].append(rare_item)
			print("[宝箱] ★ 稀有掉落：%s" % rare_item)
	_populate_rewards()


## 稀有掉落池：epic/legendary 防具 + 精炼
func _roll_rare_drop() -> String:
	var pool : Array = []
	# epic / legendary 防具
	for iid in ItemManager.get_all_item_ids():
		var d : ItemData = ItemManager.get_item_data(iid)
		if not d: continue
		if d.type != "armor": continue
		if d.quality not in ["epic", "legendary"]: continue
		if d.price <= 0: continue
		pool.append(iid)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]
	

func _populate_rewards():
	for child in reward_container.get_children():
		reward_container.remove_child(child)
		child.queue_free()

	if _rewards.is_empty():
		reward_container.add_child(_make_label("空空如也……"))
		return

	# ---- 金币 ----
	if _rewards.get("gold", 0) > 0:
		reward_container.add_child(_make_label("金币 +%d" % _rewards["gold"]))

	# ---- 魂 ----
	if _rewards.get("soul", 0) > 0:
		reward_container.add_child(_make_label("魂 +%d" % _rewards["soul"]))

	# ---- 材料 ----
	var mats = _rewards.get("materials", {})
	for mat_name in mats:
		var count = mats[mat_name]
		if count > 0:
			reward_container.add_child(_make_label("%s ×%d" % [mat_name, count]))

	# ---- 道具 ----
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
#  信号回调（.tscn 连线）
# ============================================================
func _on_confirm_pressed():
	if _applied:
		return
	_applied = true

	# ---- 金币 ----
	if _rewards.get("gold", 0) > 0:
		EconomyManager.add_temp_gold(_rewards["gold"])

	# ---- 魂 ----
	if _rewards.get("soul", 0) > 0:
		GameState.temp_soul += _rewards["soul"]

	# ---- 材料 ----
	var mats = _rewards.get("materials", {})
	for mat_name in mats:
		var count = mats[mat_name]
		if count > 0:
			GameState.add_material(mat_name, count)

	# ---- 道具 ----
	for item_id in _rewards.get("items", []):
		if item_id == "":
			continue
		# 1. 遗物
		var relic_data : Dictionary = RelicManager.get_relic_data(item_id)
		if not relic_data.is_empty():
			RelicManager.unlock_relic(item_id)
			var relic_inst := ItemInstance.new()
			relic_inst.item_id = item_id
			relic_inst.count = 1
			if not GameState.add_relic_to_passive_slot(relic_inst):
				print("[宝箱] 遗物 %s 解锁但未入槽（槽满）" % item_id)
			GameState.add_reward_item(item_id)
			continue

		# 2. 武器 / 防具 → 进待领取区（玩家去装备配置里领取）
		var data : ItemData = ItemManager.get_item_data(item_id)
		if not data:
			continue
		if data.type in ["weapon", "armor"]:
			Globals.unlock_item(item_id)
			var inst := ItemInstance.new()
			inst.item_id = item_id
			inst.count = 1
			GameState.pending_forge_rewards.append(inst)
			GameState.add_reward_item(item_id)
			print("[宝箱] 装备进待领取区: %s" % data.name)
		else:
			# 其他类型只解锁
			Globals.unlock_item(item_id)
			GameState.add_reward_item(item_id)

	closed.emit()
	queue_free()
