extends CanvasLayer

signal closed(result: Dictionary)

const SHOP_SIZE : int = 6
const REFRESH_COST : int = 20
const MAX_PASSIVE_SLOTS : int = 4

enum Tab { SHOP, FORGE, TALENT }

var _state : Dictionary = {}
var _current_tab : Tab = Tab.SHOP
var _shop_items : Array = []
var _shop_refreshed : bool = false

# ============================================================
#  节点引用
# ============================================================
@onready var mode_label : Label = $MainPanel/VBoxContainer/TopBar/ModeLabel
@onready var gold_label : Label = $MainPanel/VBoxContainer/TopBar/GoldLabel
@onready var crystal_label : Label = $MainPanel/VBoxContainer/TopBar/CrystalLabel
@onready var shop_tab_btn : Button = $MainPanel/VBoxContainer/MainHBox/RightContainer/TabBar/ShopTabBtn
@onready var forge_tab_btn : Button = $MainPanel/VBoxContainer/MainHBox/RightContainer/TabBar/ForgeTabBtn
@onready var talent_tab_btn : Button = $MainPanel/VBoxContainer/MainHBox/RightContainer/TabBar/TalentTabBtn
@onready var passive_container : HBoxContainer = $MainPanel/VBoxContainer/MainHBox/LeftInfoColumn/PassiveSection/PassiveContainer
@onready var detail_label : Label = $MainPanel/VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/DetailLabel
@onready var unit_container : HBoxContainer = $MainPanel/VBoxContainer/MainHBox/LeftVBox/UnitContainer
@onready var shop_container : GridContainer = $MainPanel/VBoxContainer/MainHBox/RightContainer/ShopScroll/ShopContainer
@onready var shop_scroll : ScrollContainer = $MainPanel/VBoxContainer/MainHBox/RightContainer/ShopScroll
@onready var next_battle_label : Label = $MainPanel/VBoxContainer/BottomHBox/NextBattleLabel
@onready var go_btn : Button = $MainPanel/VBoxContainer/BottomHBox/GoBtn
@onready var retreat_btn : Button = $MainPanel/VBoxContainer/BottomHBox/RetreatBtn
@onready var quit_btn : Button = $MainPanel/VBoxContainer/BottomHBox/QuitBtn
@onready var passive_title : Label = $MainPanel/VBoxContainer/MainHBox/LeftInfoColumn/PassiveSection/PassiveTitle

func _ready():
	mode_label.text = "魂之竞技场"
	if shop_tab_btn:   shop_tab_btn.text = "商店"
	if forge_tab_btn:  forge_tab_btn.text = "铁匠铺"
	if talent_tab_btn: talent_tab_btn.text = "词条"
	if go_btn:         go_btn.text = "出发"
	if retreat_btn:    retreat_btn.text = "撤离"
	if quit_btn:       quit_btn.text = "放弃"
	detail_label.text = "选中物品详情"

func setup(state: Dictionary):
	_state = state
	_refresh_all()


# ============================================================
#  Tab 信号
# ============================================================
func _on_shop_tab_pressed():
	_current_tab = Tab.SHOP
	_refresh_tab_style()
	_refresh_content()

func _on_forge_tab_pressed():
	_current_tab = Tab.FORGE
	_refresh_tab_style()
	_refresh_content()

func _on_talent_tab_pressed():
	_current_tab = Tab.TALENT
	_refresh_tab_style()
	_refresh_content()


# ============================================================
#  底部按钮
# ============================================================
func _on_go_pressed():     _emit("go")
func _on_retreat_pressed(): _emit("retreat")
func _on_quit_pressed():   _emit("quit")


func _emit(action: String):
	_state.action = action
	closed.emit({
		"action": action,
		"gold": _state.gold,
		"crystals": _state.crystals,
		"armory": _state.armory,
		"weapon_upgrade_tokens": _state.weapon_upgrade_tokens,
		"locked_talent_id": _state.locked_talent_id,
	})
	queue_free()


# ============================================================
#  刷新
# ============================================================
func _refresh_all():
	_refresh_top()
	_refresh_equip()
	_refresh_passive_slots()
	_refresh_tab_style()
	_refresh_content()
	_refresh_bottom_bar()


func _refresh_top():
	gold_label.text = "金币：" + str(_state.gold)
	crystal_label.text = "结晶：" + str(_state.crystals)


func _refresh_tab_style():
	shop_tab_btn.modulate = Color.WHITE if _current_tab == Tab.SHOP else Color(0.5, 0.5, 0.5, 1)
	forge_tab_btn.modulate = Color.WHITE if _current_tab == Tab.FORGE else Color(0.5, 0.5, 0.5, 1)
	talent_tab_btn.modulate = Color.WHITE if _current_tab == Tab.TALENT else Color(0.5, 0.5, 0.5, 1)


func _refresh_bottom_bar():
	next_battle_label.text = "下一战：第 %d 场%s" % [
		_state.next_battle_index,
		"（精英）" if _state.next_is_elite else ("（BOSS）" if _state.next_is_boss else "")
	]
	retreat_btn.visible = _state.can_retreat


# ---- 单位列 ----
func _refresh_equip():
	for child in unit_container.get_children():
		unit_container.remove_child(child)
		child.queue_free()

	var unit : UnitData = _state.player_data
	if not unit:
		return

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	unit_container.add_child(col)

	_add_label(col, unit.display_name, 6)
	_add_label(col, "──────", 6)

	# 武器
	var weapon_btn = _make_slot_button("武器", "空")
	if unit.weapon_slot:
		var data = ItemManager.get_item_data(unit.weapon_slot.item_id)
		var txt = data.name if data else "?"
		if unit.weapon_slot.upgrade_level > 0:
			txt += "+" + str(unit.weapon_slot.upgrade_level)
		weapon_btn.text = txt
		weapon_btn.set_meta("item_id", unit.weapon_slot.item_id)
	col.add_child(weapon_btn)

	_add_label(col, "──────", 6)

	# 防具
	for i in range(unit.armor_slots.size()):
		var slot = unit.armor_slots[i]
		var btn = _make_slot_button("armor", "空")
		btn.set_meta("slot_type", "armor")
		btn.set_meta("unit_idx", 0)
		btn.set_meta("slot_idx", i)
		if slot:
			var data = ItemManager.get_item_data(slot.item_id)
			btn.text = data.name if data else "?"
			btn.set_meta("item_id", slot.item_id)
			btn.mouse_entered.connect(_on_item_hover.bind(slot.item_id))
			btn.mouse_exited.connect(_on_item_hover_exit)
		col.add_child(btn)


func _make_slot_button(slot_type: String, default_text: String) -> Button:
	var btn = Button.new()
	btn.text = default_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 12)
	btn.add_theme_font_size_override("font_size", 6)
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("slot_type", slot_type)
	var style = load(Config.PATHS.STYLEBOX_8BIT)
	if style:
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("disabled", style)
		btn.add_theme_stylebox_override("focus", style)
	return btn


func _add_label(parent: Node, text: String, size: int):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)


# ---- 被动槽（遗物 + 精炼） ----
func _refresh_passive_slots():
	for child in passive_container.get_children():
		passive_container.remove_child(child)
		child.queue_free()

	var passives = GameState.get_passives()
	passive_title.text = "── 被动 %d/%d ──" % [passives.size(), MAX_PASSIVE_SLOTS]

	for i in range(MAX_PASSIVE_SLOTS):
		var inst = passives[i] if i < passives.size() else null
		# ... 后面保持不变 ...
		var btn = _make_slot_button("passive_slot", "空")
		btn.custom_minimum_size = Vector2(24, 12)
		btn.set_meta("passive_index", i)

		if inst == null:
			pass
		elif inst is ItemInstance:
			var data = RelicManager.get_relic_data(inst.item_id)
			if not data.is_empty():
				btn.text = data.get("name", "?")
				btn.set_meta("item_id", inst.item_id)
				btn.mouse_entered.connect(_on_item_hover.bind(inst.item_id))
				btn.mouse_exited.connect(_on_item_hover_exit)
		elif inst is Dictionary:
			var refine_id = inst.get("refine_id", "")
			var recipe = RefineManager.get_recipe(refine_id)
			if not recipe.is_empty():
				btn.text = recipe.get("name", refine_id)
				btn.set_meta("refine_id", refine_id)

		passive_container.add_child(btn)


# ---- 右侧内容 ----
func _refresh_content():
	for child in shop_container.get_children():
		child.queue_free()    # queue_free 会自动从父节点脱离，不用手动 remove_child
	match _current_tab:
		Tab.SHOP: _build_shop_tab()
		Tab.FORGE: _build_forge_tab()
		Tab.TALENT: _build_talent_tab()


func _build_shop_tab():
	shop_container.columns = 3
	shop_container.visible = true

	# 刷新按钮（作为第一格）
	var refresh_btn = _make_slot_button("refresh", "刷新\n%d G" % (0 if not _shop_refreshed else REFRESH_COST))
	refresh_btn.custom_minimum_size = Vector2(60, 36)
	refresh_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refresh_btn.disabled = _shop_refreshed and _state.gold < REFRESH_COST
	refresh_btn.pressed.connect(_on_refresh_shop)
	shop_container.add_child(refresh_btn)

	# 商品
	if _shop_items.is_empty():
		_roll_shop_items()

	for i in range(_shop_items.size()):
		var entry = _shop_items[i]
		if entry == null:
			var empty_btn = _make_slot_button("shop_item", "已售")
			empty_btn.custom_minimum_size = Vector2(60, 36)
			empty_btn.disabled = true
			shop_container.add_child(empty_btn)
			continue

		var item_data = entry["item_data"]
		var price = entry["price"]
		var btn = _make_slot_button("shop_item", "%s\n%dG" % [item_data.name, price])
		btn.custom_minimum_size = Vector2(60, 36)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.set_meta("shop_index", i)
		btn.set_meta("item_id", item_data.id)
		btn.disabled = _state.gold < price
		btn.pressed.connect(_on_buy_shop.bind(i))
		btn.mouse_entered.connect(_on_item_hover.bind(item_data.id))
		btn.mouse_exited.connect(_on_item_hover_exit)
		shop_container.add_child(btn)


func _build_forge_tab():
	shop_container.columns = 1
	shop_container.visible = true

	var unit : UnitData = _state.player_data
	if not unit:
		return

	# 武器升级
	_add_shop_label("武器升级（剩余 %d 次）" % _state.weapon_upgrade_tokens)

	if unit.weapon_slot:
		var weapon_data = ItemManager.get_item_data(unit.weapon_slot.item_id)
		if weapon_data:
			var level = unit.weapon_slot.upgrade_level
			var upgrade_btn = _make_slot_button("upgrade", "%s +%d → +%d" % [weapon_data.name, level, level + 1])
			upgrade_btn.custom_minimum_size = Vector2(0, 20)
			upgrade_btn.disabled = (_state.weapon_upgrade_tokens <= 0) or (level >= 3)
			upgrade_btn.pressed.connect(_on_upgrade_weapon)
			shop_container.add_child(upgrade_btn)
	else:
		_add_shop_label("（无武器）")

	# 防具合成
	_add_shop_label("防具合成")

	var forge_slots : Array = [null, null]
	for i in range(unit.armor_slots.size()):
		var slot = unit.armor_slots[i]
		if slot:
			for j in range(2):
				if forge_slots[j] == null:
					forge_slots[j] = {"unit_slot": i, "item_id": slot.item_id}
					break

	for j in range(2):
		var slot_text = "空"
		if forge_slots[j] != null:
			var d = ItemManager.get_item_data(forge_slots[j].item_id)
			slot_text = d.name if d else "?"
		var slot_btn = _make_slot_button("forge_slot", slot_text)
		slot_btn.custom_minimum_size = Vector2(0, 20)
		shop_container.add_child(slot_btn)

	var ids : Array = []
	for s in forge_slots:
		if s != null:
			ids.append(s.item_id)

	var matched = ""
	if ids.size() == 2:
		matched = RecipeManager.match_recipe(ids)

	if matched != "":
		var out_data = ItemManager.get_item_data(matched)
		_add_shop_label("→ %s" % (out_data.name if out_data else matched))
		var craft_btn = _make_slot_button("craft", "合成")
		craft_btn.custom_minimum_size = Vector2(0, 20)
		craft_btn.pressed.connect(_on_craft_armor.bind(matched, forge_slots))
		shop_container.add_child(craft_btn)


func _build_talent_tab():
	shop_container.columns = 1
	shop_container.visible = true

	var unit : UnitData = _state.player_data
	if not unit:
		return

	_add_shop_label("目标词条配置")

	var unlocked = Globals.get_unlocked_talents()
	for talent_id in unlocked:
		var data = TalentManager.get_talent_data(talent_id)
		if not data:
			continue

		var compatible = TalentManager.is_talent_compatible_with_unit(talent_id, unit.unit_name)
		var is_current = (_state.locked_talent_id == talent_id)

		var btn = _make_slot_button("talent", "Lv.%d %s" % [
			TalentManager.get_talent_level(unit.unit_name, talent_id),
			data.display_name
		])
		btn.custom_minimum_size = Vector2(0, 20)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		if not compatible:
			btn.modulate = Color(0.35, 0.35, 0.35, 1)
			btn.disabled = true
		elif is_current:
			btn.modulate = Color(0.5, 0.8, 1.0, 1)
			btn.disabled = true
		elif _state.streak_locked:
			btn.modulate = Color(0.35, 0.35, 0.35, 1)
			btn.disabled = true
		else:
			btn.pressed.connect(_on_select_talent.bind(talent_id))
			btn.mouse_entered.connect(_on_talent_hover.bind(talent_id))
			btn.mouse_exited.connect(_on_item_hover_exit)
		shop_container.add_child(btn)


func _add_shop_label(text: String):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 6)
	shop_container.add_child(label)


# ============================================================
#  商店逻辑
# ============================================================
func _roll_shop_items():
	_shop_items.clear()

	# ---- 收集已拥有的装备 ----
	var owned := {}
	if _state.player_data.weapon_slot:
		owned[_state.player_data.weapon_slot.item_id] = true
	for slot in _state.player_data.armor_slots:
		if slot:
			owned[slot.item_id] = true
	for inst in _state.armory:
		if inst:
			owned[inst.item_id] = true

	var pool : Array = []
	for item_id in Globals.unlocked_items:
		if owned.has(item_id):
			continue
		var data = ItemManager.get_item_data(item_id)
		if data and data.type in ["weapon", "armor"] and data.price > 0:
			pool.append({"item_data": data, "price": data.price})
	pool.shuffle()
	for i in range(min(SHOP_SIZE, pool.size())):
		_shop_items.append(pool[i])
	while _shop_items.size() < SHOP_SIZE:
		_shop_items.append(null)

func _on_refresh_shop():
	var cost = 0 if not _shop_refreshed else REFRESH_COST
	if _state.gold < cost:
		return
	_state.gold -= cost
	_shop_refreshed = true
	_roll_shop_items()
	_refresh_all()


func _on_buy_shop(shop_index: int):
	if shop_index < 0 or shop_index >= _shop_items.size():
		return
	var entry = _shop_items[shop_index]
	if entry == null:
		return
	var item_data = entry["item_data"]
	var price = entry["price"]
	if _state.gold < price:
		return

	_state.gold -= price
	_shop_items[shop_index] = null

	if item_data.type == "weapon":
		var inst = ItemInstance.new()
		inst.item_id = item_data.id
		inst.count = 1
		_state.player_data.weapon_slot = inst
	elif item_data.type == "armor":
		var placed = false
		for i in range(_state.player_data.armor_slots.size()):
			if _state.player_data.armor_slots[i] == null:
				var inst = ItemInstance.new()
				inst.item_id = item_data.id
				inst.count = 1
				_state.player_data.armor_slots[i] = inst
				placed = true
				break
		if not placed:
			var inst = ItemInstance.new()
			inst.item_id = item_data.id
			inst.count = 1
			_state.armory.append(inst)

	_refresh_all()


# ============================================================
#  铁匠铺逻辑
# ============================================================
func _on_upgrade_weapon():
	if _state.weapon_upgrade_tokens <= 0:
		return
	var unit : UnitData = _state.player_data
	if not unit or not unit.weapon_slot:
		return
	if unit.weapon_slot.upgrade_level >= 3:
		return

	unit.weapon_slot.upgrade_level += 1
	_state.weapon_upgrade_tokens -= 1
	_refresh_all()


func _on_craft_armor(recipe_id: String, forge_slots: Array):
	var unit : UnitData = _state.player_data
	if not unit:
		return

	var first_slot_idx = forge_slots[0].unit_slot
	for s in forge_slots:
		unit.armor_slots[s.unit_slot] = null
	var out_inst = ItemInstance.new()
	out_inst.item_id = recipe_id
	out_inst.count = 1
	unit.armor_slots[first_slot_idx] = out_inst

	_refresh_all()


# ============================================================
#  词条逻辑
# ============================================================
func _on_select_talent(talent_id: String):
	if _state.streak_locked:
		return
	_state.locked_talent_id = talent_id
	_refresh_all()


# ============================================================
#  详情
# ============================================================
func _on_item_hover(item_id: String):
	var data = ItemManager.get_item_data(item_id)
	if not data:
		return
	var lines = []
	lines.append(data.name)
	lines.append(data.description)
	if data.type == "weapon":
		lines.append("攻击：" + str(data.base_attack))
		lines.append("射程：%d~%d" % [data.min_attack_range, data.attack_range])
	elif data.type == "armor":
		lines.append("防御：" + str(data.defense))
	detail_label.text = "\n".join(lines)


func _on_talent_hover(talent_id: String):
	var data = TalentManager.get_talent_data(talent_id)
	if not data:
		return
	var lines = []
	lines.append(data.display_name)
	lines.append(data.description)
	lines.append("稀有度：" + data.rarity)
	detail_label.text = "\n".join(lines)


func _on_item_hover_exit():
	detail_label.text = "选中物品详情"
