class_name RelicShop
extends RefCounted

## ============================================================
##  RelicShop — 魂栈遗物商店（v6.59）
##  右侧上下两排各 3 个格子：团队遗物 + 老虎机专用遗物。
##  点击格子购买 → 放入对应槽位（团队槽 6 / 老虎机槽 4）。
##  刷新按钮重 roll 候选；出售区支持把已装备遗物拖入换金币。
## ============================================================

const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")

## ★ v6.62h：商店格固定宽度——有无图标/空槽/价格文字都不改变格子尺寸与位置
const CELL_WIDTH : float = 40.0

var panel = null
var _candidates : Array = []          # 六个候选：{relic_id, price, slot_machine}
var _refresh_cost : int = 100

func _init(p):
	panel = p


func get_refresh_cost() -> int:
	return _refresh_cost


## ★ v6.62j：只刷新商店上方的持有金币标签（不重建格子），供出售/购买后同步金币显示。
func refresh_gold_label() -> void:
	if panel == null or panel.shop_container == null: return
	var rows : Node = panel.shop_container.get_node_or_null("RelicShopRows")
	if rows == null: return
	var lb : Node = rows.get_node_or_null("ShopGoldLabel")
	if lb is Label:
		var gold_val : int = panel._context.get_gold() if panel._context != null else 0
		(lb as Label).text = "持有金币: %d G" % gold_val


func generate() -> void:
	_candidates.clear()
	_refresh_cost = 100
	_roll_candidates()


func _roll_candidates() -> void:
	_candidates.clear()
	var team_pool : Array = []
	var roll_pool : Array = []
	for key in RelicManager.get_all_relic_data():
		var d : Dictionary = RelicManager.get_relic_data(key)
		if d.is_empty(): continue
		if bool(d.get("from_aura", false)): continue
		if bool(d.get("slot_machine", false)):
			roll_pool.append(key)
		else:
			team_pool.append(key)
	team_pool.shuffle()
	roll_pool.shuffle()
	# 上排 3 个团队遗物，下排 3 个老虎机遗物
	for i in range(3):
		if i < team_pool.size():
			_candidates.append(_make_entry(team_pool[i], false))
	for i in range(3):
		if i < roll_pool.size():
			_candidates.append(_make_entry(roll_pool[i], true))


func _make_entry(relic_id: String, is_roll: bool) -> Dictionary:
	var d : Dictionary = RelicManager.get_relic_data(relic_id)
	var price : int = int(d.get("price", 150))
	return {"relic_id": relic_id, "price": price, "slot_machine": is_roll}


## ★ v6.62g：买走 idx 候选后该格留空（不补货、不 remove_at），保持 6 格恒定但内容为空。
func _mark_candidate_sold(idx: int) -> void:
	if idx < 0 or idx >= _candidates.size(): return
	var is_roll : bool = bool(_candidates[idx].get("slot_machine", false))
	_candidates[idx] = {"relic_id": "", "price": 0, "slot_machine": is_roll, "sold_out": true}


## 在给定容器里渲染商店格子。cell 点击 = 购买。
## ★ v6.62f：固定两排——上排 3 个团队遗物，下排 3 个防具(老虎机)遗物；
##   每排格数恒定，买走后 _candidates 原位补新候选（不会少格）。
func render(container: Control, filter_roll = null) -> void:
	if container == null: return
	for c in container.get_children():
		container.remove_child(c); c.free()
	# 容器本身占满宽度，垂直按内容收缩（ShopScroll 已在魂栈模式设 SHRINK）
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# ★ 用显式两行结构，不再靠 FlowContainer 自动换行：保证团队/防具严格分行、各 3 格
	var rows := VBoxContainer.new()
	rows.name = "RelicShopRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rows.add_theme_constant_override("separation", Style.ITEM_GRID_GAP)
	container.add_child(rows)

	# ★ v6.62h：商品区上方显示持有金币（魂栈模式顶部 gold_label 被隐藏，故在此补）
	var gold_lb := Label.new()
	gold_lb.name = "ShopGoldLabel"
	var gold_val : int = panel._context.get_gold() if panel != null and panel._context != null else 0
	gold_lb.text = "持有金币: %d G" % gold_val
	gold_lb.add_theme_font_size_override("font_size", 8)
	gold_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(gold_lb)

	var team_row := HBoxContainer.new()
	team_row.name = "TeamRow"
	team_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_row.alignment = BoxContainer.ALIGNMENT_CENTER
	team_row.add_theme_constant_override("separation", Style.ITEM_GRID_GAP)
	rows.add_child(team_row)
	var roll_row := HBoxContainer.new()
	roll_row.name = "RollRow"
	roll_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_row.alignment = BoxContainer.ALIGNMENT_CENTER
	roll_row.add_theme_constant_override("separation", Style.ITEM_GRID_GAP)
	rows.add_child(roll_row)

	for i in range(_candidates.size()):
		var e : Dictionary = _candidates[i]
		var is_roll : bool = bool(e.get("slot_machine", false))
		if filter_roll != null and is_roll != bool(filter_roll):
			continue
		var target_row : HBoxContainer = roll_row if is_roll else team_row
		var cell := _make_shop_cell(i, e)
		target_row.add_child(cell)


## 构造单个商店格（图标 + 价格），保留拖拽/点击购买所需的全部 meta
func _make_shop_cell(idx: int, e: Dictionary) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.name = "ShopCell"
	cell.add_theme_constant_override("separation", 1)
	# ★ v6.62h：固定格子宽度，有无图标/空槽/价格文字都不影响尺寸与位置
	cell.custom_minimum_size = Vector2(CELL_WIDTH, 0)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.custom_minimum_size = Vector2(CELL_WIDTH - 4, Style.BTN_ITEM_SIZE.y)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.clip_contents = false
	var d : Dictionary = RelicManager.get_relic_data(str(e.get("relic_id", "")))
	var is_roll : bool = bool(e.get("slot_machine", false))
	var sold_out : bool = bool(e.get("sold_out", false)) or str(e.get("relic_id", "")) == ""
	var icon = d.get("icon")
	# ★ v6.62f：团队/防具遗物统一显示自身配置的图标（图标编辑走游戏内遗物配置编辑器）
	if sold_out:
		btn.text = "空"
		btn.disabled = true
	elif icon is Texture2D:
		# ★ v6.62h：商店图标也用固定 20×20 子节点，尺寸不随按钮宽度变化（与槽位一致）
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.set_anchors_preset(Control.PRESET_CENTER)
		icon_rect.offset_left = -10
		icon_rect.offset_right = 10
		icon_rect.offset_top = -10
		icon_rect.offset_bottom = 10
		btn.add_child(icon_rect)
		btn.set_meta("_item_icon", icon)
	else:
		btn.text = str(d.get("name", "?")).substr(0, 2)
	btn.set_meta("relic_id", str(e.get("relic_id", "")))
	btn.set_meta("slot_machine", is_roll)
	btn.set_meta("price", int(e.get("price", 0)))
	# ★ 售罄占位不参与拖拽购买
	if not sold_out:
		btn.set_meta("slot_type", "relic_shop_item")
		btn.set_meta("shop_candidate_idx", idx)
	btn.tooltip_text = "已购买（空槽）" if sold_out else "%s\n%s\n%d G\n拖到%s槽购买" % [
		str(d.get("name", "?")), str(d.get("description", "")), int(e.get("price", 0)),
		"防具遗物" if is_roll else "团队遗物"]
	# 保留点击购买作后备
	if not sold_out:
		btn.pressed.connect(_on_buy.bind(idx))
	cell.add_child(btn)
	var price_lb := Label.new()
	price_lb.text = "—" if sold_out else "%dG" % int(e.get("price", 0))
	price_lb.add_theme_font_size_override("font_size", 6)
	price_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lb.custom_minimum_size = Vector2(CELL_WIDTH - 4, 0)
	price_lb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_child(price_lb)
	return cell


func _on_buy(idx: int) -> void:
	if idx < 0 or idx >= _candidates.size(): return
	var e : Dictionary = _candidates[idx]
	var relic_id : String = str(e.get("relic_id", ""))
	var price : int = int(e.get("price", 0))
	var is_roll : bool = bool(e.get("slot_machine", false))
	if panel._context.get_gold() < price:
		panel._show_detail_in_zone("金币不足")
		return
	var inst := ItemInstance.new()
	inst.item_id = relic_id
	inst.count = 1
	var ok : bool = false
	if is_roll:
		ok = GameState.add_roll_relic(inst)
	else:
		ok = GameState.add_relic_to_passive_slot(inst)
	if not ok:
		panel._show_detail_in_zone("对应遗物槽已满")
		return
	panel._context.subtract_gold(price)
	panel._show_detail_in_zone("购买 %s，花费 %dG" % [
		str(RelicManager.get_relic_data(relic_id).get("name", relic_id)), price])
	SoundManager.play_select_sound()
	_mark_candidate_sold(idx)
	render(panel.shop_container)
	panel._update_gold_display()


## ★ v6.62c：拖拽购买——把候选 idx 的遗物买下并自动装入对应类别的空槽
## is_roll=true 放老虎机槽，否则放团队槽。成功返回 true。
## 注：实际落位走 add 找空槽，不依赖目标槽索引。
func buy_to_slot(idx: int, is_roll: bool) -> bool:
	if idx < 0 or idx >= _candidates.size(): return false
	var e : Dictionary = _candidates[idx]
	var relic_id : String = str(e.get("relic_id", ""))
	var price : int = int(e.get("price", 0))
	if panel._context.get_gold() < price:
		panel._show_detail_in_zone("金币不足")
		return false
	var inst := ItemInstance.new()
	inst.item_id = relic_id
	inst.count = 1
	var ok : bool = false
	if is_roll:
		ok = GameState.add_roll_relic(inst)
	else:
		ok = GameState.add_relic_to_passive_slot(inst)
	if not ok:
		panel._show_detail_in_zone("对应遗物槽已满")
		return false
	panel._context.subtract_gold(price)
	panel._show_detail_in_zone("购买 %s，花费 %dG" % [
		str(RelicManager.get_relic_data(relic_id).get("name", relic_id)), price])
	SoundManager.play_select_sound()
	_mark_candidate_sold(idx)
	render(panel.shop_container, null)
	panel._update_gold_display()
	return true


## ★ v6.62k：出售返还率做成「基础率 + 遗物加成」的可配置百分比。
##   基础率见 BASE_SELL_RATE；已装备团队遗物的 effects.relic_sell_rate_bonus 会叠加（每个遗物一份加成）。
const BASE_SELL_RATE : float = 0.5
const SELL_RATE_BONUS_KEY : String = "relic_sell_rate_bonus"


## 获取当前出售返还率（0~1）：基础率 + 遗物加成，clamp 到 [0,1]
static func get_sell_rate() -> float:
	var eff : Dictionary = GameState.get_global_relic_effects()
	var bonus : float = float(eff.get(SELL_RATE_BONUS_KEY, 0.0))
	return clampf(BASE_SELL_RATE + bonus, 0.0, 1.0)


## 遗物出售价（团队槽/老虎机槽共用）：遗物 price × 当前返还率
static func get_relic_sell_price(relic_id: String) -> int:
	var d : Dictionary = RelicManager.get_relic_data(relic_id)
	if d.is_empty(): return 0
	return maxi(1, int(float(int(d.get("price", 0))) * get_sell_rate()))
