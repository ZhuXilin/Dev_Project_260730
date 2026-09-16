extends CanvasLayer

signal closed(result: Dictionary)

const SHOP_SIZE : int = 6
const REFRESH_COST : int = 20
const MAX_PASSIVE_SLOTS : int = 4

enum Tab { SHOP, FORGE, TALENT, REFINE }

# ============================================================
#  状态
# ============================================================
var _state : Dictionary = {}
var _current_tab : Tab = Tab.SHOP
var _shop_items : Array = []
var _shop_refreshed : bool = false

# 拖拽
var _is_dragging : bool = false
var _drag_source : Control = null
var _drag_meta : Dictionary = {}
var _drag_preview : Control = null
var _drag_grab_offset : Vector2 = Vector2.ZERO
var _slot_buttons : Dictionary = {}

# ============================================================
#  节点引用
# ============================================================
@onready var mode_label : Label = $MainPanel/VBoxContainer/TopBar/ModeLabel
@onready var gold_label : Label = $MainPanel/VBoxContainer/TopBar/GoldLabel
@onready var crystal_label : Label = $MainPanel/VBoxContainer/TopBar/CrystalLabel
@onready var shop_tab_btn : Button = $MainPanel/VBoxContainer/MainHBox/RightContainer/TabBar/ShopTabBtn
@onready var forge_tab_btn : Button = $MainPanel/VBoxContainer/MainHBox/RightContainer/TabBar/ForgeTabBtn
@onready var talent_tab_btn : Button = $MainPanel/VBoxContainer/MainHBox/RightContainer/TabBar/TalentTabBtn
@onready var refine_tab_btn : Button = get_node_or_null("MainPanel/VBoxContainer/MainHBox/RightContainer/TabBar/RefineTabBtn")
@onready var passive_title : Label = $MainPanel/VBoxContainer/MainHBox/LeftInfoColumn/PassiveSection/PassiveTitle
@onready var passive_container : HBoxContainer = $MainPanel/VBoxContainer/MainHBox/LeftInfoColumn/PassiveSection/PassiveContainer
@onready var detail_label : Label = $MainPanel/VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/DetailLabel
@onready var unit_container : HBoxContainer = $MainPanel/VBoxContainer/MainHBox/LeftVBox/UnitContainer
@onready var shop_container : GridContainer = $MainPanel/VBoxContainer/MainHBox/RightContainer/ShopScroll/ShopContainer
@onready var shop_scroll : ScrollContainer = $MainPanel/VBoxContainer/MainHBox/RightContainer/ShopScroll
@onready var discard_zone : Panel = get_node_or_null("MainPanel/VBoxContainer/MainHBox/RightContainer/DiscardZone")
@onready var discard_label : Label = null
@onready var next_battle_label : Label = $MainPanel/VBoxContainer/BottomHBox/NextBattleLabel
@onready var go_btn : Button = $MainPanel/VBoxContainer/BottomHBox/GoBtn
@onready var retreat_btn : Button = $MainPanel/VBoxContainer/BottomHBox/RetreatBtn
@onready var quit_btn : Button = $MainPanel/VBoxContainer/BottomHBox/QuitBtn

# ============================================================
#  生命周期
# ============================================================
func _ready():
	if discard_zone:
		discard_label = discard_zone.get_node_or_null("DiscardLabel")
	mode_label.text = "魂之竞技场"
	if shop_tab_btn:   shop_tab_btn.text = "商店"
	if forge_tab_btn:  forge_tab_btn.text = "铁匠铺"
	if talent_tab_btn: talent_tab_btn.text = "特技"
	if refine_tab_btn: refine_tab_btn.text = "精炼库"
	if go_btn:         go_btn.text = "出发"
	if retreat_btn:    retreat_btn.text = "撤离"
	if quit_btn:       quit_btn.text = "放弃"
	detail_label.text = "选中物品详情"

func setup(state: Dictionary):
	_state = state
	if not _state.has("active_refines"):
		_state["active_refines"] = []
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

func _on_refine_tab_pressed():
	_current_tab = Tab.REFINE
	_refresh_tab_style()
	_refresh_content()

# ============================================================
#  底部按钮
# ============================================================
func _on_go_pressed():      _emit("go")
func _on_retreat_pressed(): _emit("retreat")
func _on_quit_pressed():    _emit("quit")

func _emit(action: String):
	_state.action = action
	closed.emit({
		"action": action,
		"gold": _state.gold,
		"crystals": _state.crystals,
		"armory": _state.armory,
		"weapon_upgrade_tokens": _state.weapon_upgrade_tokens,
		"locked_talent_id": _state.locked_talent_id,
		"active_refines": _state.get("active_refines", []),
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
	shop_tab_btn.modulate   = Color.WHITE if _current_tab == Tab.SHOP   else Color(0.5, 0.5, 0.5, 1)
	forge_tab_btn.modulate  = Color.WHITE if _current_tab == Tab.FORGE  else Color(0.5, 0.5, 0.5, 1)
	talent_tab_btn.modulate = Color.WHITE if _current_tab == Tab.TALENT else Color(0.5, 0.5, 0.5, 1)
	if refine_tab_btn:
		refine_tab_btn.modulate = Color.WHITE if _current_tab == Tab.REFINE else Color(0.5, 0.5, 0.5, 1)

func _refresh_bottom_bar():
	next_battle_label.text = "下一战：第 %d 场%s" % [
		_state.next_battle_index,
		"（精英）" if _state.next_is_elite else ("（BOSS）" if _state.next_is_boss else "")
	]
	retreat_btn.visible = _state.can_retreat

# ============================================================
#  左侧：装备栏（武器 + 防具 + 特技）
# ============================================================
func _refresh_equip():
	for child in unit_container.get_children():
		unit_container.remove_child(child)
		child.queue_free()
	_slot_buttons.clear()

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

	# ---- 武器槽 ----
	var weapon_btn = _make_slot_button("weapon", "空")
	if unit.weapon_slot:
		var data = ItemManager.get_item_data(unit.weapon_slot.item_id)
		var txt = data.name if data else "?"
		if unit.weapon_slot.upgrade_level > 0:
			txt += "+" + str(unit.weapon_slot.upgrade_level)
		weapon_btn.text = txt
		_attach_drag(weapon_btn, {
			"source_type": "weapon",
			"item_id": unit.weapon_slot.item_id,
		})
		weapon_btn.mouse_entered.connect(_on_item_hover.bind(unit.weapon_slot.item_id))
		weapon_btn.mouse_exited.connect(_on_item_hover_exit)
	else:
		_attach_drag(weapon_btn, {"source_type": "empty"})
	_slot_buttons["weapon"] = weapon_btn
	col.add_child(weapon_btn)

	_add_label(col, "──────", 6)

	# ---- 防具槽 ----
	for i in range(unit.armor_slots.size()):
		var slot = unit.armor_slots[i]
		var btn = _make_slot_button("armor", "空")
		if slot:
			var data = ItemManager.get_item_data(slot.item_id)
			btn.text = data.name if data else "?"
			_attach_drag(btn, {
				"source_type": "armor",
				"slot_idx": i,
				"item_id": slot.item_id,
			})
			btn.mouse_entered.connect(_on_item_hover.bind(slot.item_id))
			btn.mouse_exited.connect(_on_item_hover_exit)
		else:
			_attach_drag(btn, {"source_type": "empty"})
		_slot_buttons["armor_" + str(i)] = btn
		col.add_child(btn)

	_add_label(col, "──────", 6)

	# ---- 特技槽 ----
	_add_label(col, "特技", 6)
	var talent_btn = _make_slot_button("talent_slot", "无")
	talent_btn.custom_minimum_size = Vector2(0, 16)
	var tid : String = _state.get("locked_talent_id", "")
	if tid != "":
		var tdata = TalentManager.get_talent_data(tid)
		if tdata:
			talent_btn.text = tdata.display_name
			talent_btn.mouse_entered.connect(_on_talent_hover.bind(tid))
			talent_btn.mouse_exited.connect(_on_item_hover_exit)
			_attach_drag(talent_btn, {
				"source_type": "talent",
				"talent_id": tid,
			})
	talent_btn.pressed.connect(_on_talent_slot_pressed)
	_slot_buttons["talent_slot"] = talent_btn
	col.add_child(talent_btn)

func _on_talent_slot_pressed():
	_current_tab = Tab.TALENT
	_refresh_tab_style()
	_refresh_content()

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

# ============================================================
#  被动槽（遗物 + 精炼）
# ============================================================
func _refresh_passive_slots():
	for child in passive_container.get_children():
		passive_container.remove_child(child)
		child.queue_free()
	for key in _slot_buttons.keys():
		if key.begins_with("passive_"):
			_slot_buttons.erase(key)

	var display_list : Array = []
	for relic in GameState.global_relics:
		if relic != null:
			display_list.append({"kind": "relic", "relic": relic})

	var active_refines : Array = _state.get("active_refines", [])
	for refine_id in active_refines:
		display_list.append({"kind": "refine", "refine_id": refine_id})

	passive_title.text = "── 被动 %d/%d ──" % [display_list.size(), MAX_PASSIVE_SLOTS]

	for i in range(MAX_PASSIVE_SLOTS):
		var btn = _make_slot_button("passive_slot", "空")
		btn.custom_minimum_size = Vector2(24, 12)
		btn.set_meta("passive_index", i)

		if i < display_list.size():
			var entry = display_list[i]
			if entry.kind == "relic":
				var relic = entry.relic
				var data = RelicManager.get_relic_data(relic.item_id)
				if not data.is_empty():
					btn.text = data.get("name", "?")
					btn.set_meta("item_id", relic.item_id)
					btn.mouse_entered.connect(_on_item_hover.bind(relic.item_id))
					btn.mouse_exited.connect(_on_item_hover_exit)
				else:
					btn.text = "?"
			elif entry.kind == "refine":
				var refine_id = entry.refine_id
				var recipe = RefineManager.get_recipe(refine_id)
				var rname = recipe.get("name", refine_id) if not recipe.is_empty() else refine_id
				btn.text = rname
				btn.set_meta("refine_id", refine_id)
				btn.mouse_entered.connect(_on_refine_hover.bind(refine_id))
				btn.mouse_exited.connect(_on_item_hover_exit)
				btn.pressed.connect(_on_passive_refine_clicked.bind(refine_id))

		_slot_buttons["passive_" + str(i)] = btn
		passive_container.add_child(btn)

func _on_passive_refine_clicked(refine_id: String):
	var arr : Array = _state.get("active_refines", [])
	arr.erase(refine_id)
	_state["active_refines"] = arr
	_refresh_passive_slots()

# ============================================================
#  右侧内容
# ============================================================
func _refresh_content():
	for child in shop_container.get_children():
		shop_container.remove_child(child)
		child.queue_free()

	match _current_tab:
		Tab.SHOP:   _build_shop_tab()
		Tab.FORGE:  _build_forge_tab()
		Tab.TALENT: _build_talent_tab()
		Tab.REFINE: _build_refine_tab()

# ---- 商店 ----
func _build_shop_tab():
	shop_container.columns = 3
	shop_container.visible = true

	var refresh_btn = _make_shop_cell("刷新\n%d G" % (0 if not _shop_refreshed else REFRESH_COST))
	refresh_btn.disabled = _shop_refreshed and _state.gold < REFRESH_COST
	refresh_btn.pressed.connect(_on_refresh_shop)
	shop_container.add_child(refresh_btn)

	if _shop_items.is_empty():
		_roll_shop_items()

	for i in range(_shop_items.size()):
		var entry = _shop_items[i]
		if entry == null:
			var empty_btn = _make_shop_cell("已售")
			empty_btn.disabled = true
			shop_container.add_child(empty_btn)
			continue

		var item_data = entry["item_data"]
		var price = entry["price"]
		var btn = _make_shop_cell("%s\n%dG" % [item_data.name, price])
		btn.set_meta("shop_index", i)
		btn.set_meta("item_id", item_data.id)
		btn.disabled = _state.gold < price
		btn.pressed.connect(_on_buy_shop.bind(i))
		btn.mouse_entered.connect(_on_item_hover.bind(item_data.id))
		btn.mouse_exited.connect(_on_item_hover_exit)

		if not btn.disabled:
			_attach_drag(btn, {
				"source_type": "shop",
				"shop_index": i,
				"item_id": item_data.id,
				"price": price,
			})

		shop_container.add_child(btn)

func _make_shop_cell(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(60, 36)
	btn.add_theme_font_size_override("font_size", 8)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.focus_mode = Control.FOCUS_NONE
	var style = load(Config.PATHS.STYLEBOX_8BIT)
	if style:
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("disabled", style)
		btn.add_theme_stylebox_override("focus", style)
	return btn

# ---- 铁匠铺 ----
func _build_forge_tab():
	shop_container.columns = 1
	shop_container.visible = true

	var unit : UnitData = _state.player_data
	if not unit:
		return

	_add_shop_label("武器升级（剩余 %d 次）" % _state.weapon_upgrade_tokens)

	if unit.weapon_slot:
		var weapon_data = ItemManager.get_item_data(unit.weapon_slot.item_id)
		if weapon_data:
			var level = unit.weapon_slot.upgrade_level
			var upgrade_btn = _make_shop_cell("%s +%d → +%d" % [weapon_data.name, level, level + 1])
			upgrade_btn.custom_minimum_size = Vector2(0, 24)
			upgrade_btn.disabled = (_state.weapon_upgrade_tokens <= 0) or (level >= 3)
			upgrade_btn.pressed.connect(_on_upgrade_weapon)
			shop_container.add_child(upgrade_btn)
	else:
		_add_shop_label("（无武器）")

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
		var slot_btn = _make_shop_cell(slot_text)
		slot_btn.custom_minimum_size = Vector2(0, 24)
		slot_btn.disabled = true
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
		var craft_btn = _make_shop_cell("合成")
		craft_btn.custom_minimum_size = Vector2(0, 24)
		craft_btn.pressed.connect(_on_craft_armor.bind(matched, forge_slots))
		shop_container.add_child(craft_btn)

# ---- 特技 ----
func _build_talent_tab():
	shop_container.columns = 1
	shop_container.visible = true

	var unit : UnitData = _state.player_data
	if not unit:
		return

	_add_shop_label("目标特技（每局锁一次）")

	var unlocked = Globals.get_unlocked_talents()
	for talent_id in unlocked:
		var data = TalentManager.get_talent_data(talent_id)
		if not data:
			continue

		var compatible = TalentManager.is_talent_compatible_with_unit(talent_id, unit.unit_name)
		var is_current = (_state.get("locked_talent_id", "") == talent_id)

		var btn = _make_shop_cell("Lv.%d %s" % [
			TalentManager.get_talent_level(unit.unit_name, talent_id),
			data.display_name
		])
		btn.custom_minimum_size = Vector2(0, 24)
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
			# ★ 特技可拖拽
			_attach_drag(btn, {
				"source_type": "talent",
				"talent_id": talent_id,
			})
		shop_container.add_child(btn)

# ---- 精炼库 ----
func _build_refine_tab():
	shop_container.columns = 3
	shop_container.visible = true

	var active : Array = _state.get("active_refines", [])
	var all_ids = RefineManager.get_all_ids()

	var has_any = false
	for refine_id in all_ids:
		if not RefineManager.is_recipe_unlocked(refine_id):
			continue
		var recipe = RefineManager.get_recipe(refine_id)
		if recipe.is_empty():
			continue
		var rname = recipe.get("name", refine_id)
		var stock = RefineManager.get_count(refine_id)
		var is_active = refine_id in active
		has_any = true

		var btn = _make_shop_cell("%s\n库存 %d" % [rname, stock])
		if is_active:
			btn.modulate = Color(0.5, 1.0, 0.6, 1)
		if stock <= 0 and not is_active:
			btn.disabled = true
		btn.set_meta("refine_id", refine_id)
		btn.pressed.connect(_on_refine_click.bind(refine_id))
		btn.mouse_entered.connect(_on_refine_hover.bind(refine_id))
		btn.mouse_exited.connect(_on_item_hover_exit)
		shop_container.add_child(btn)

	if not has_any:
		_add_shop_label("（暂无已解锁精炼配方）")

func _on_refine_click(refine_id: String):
	var arr : Array = _state.get("active_refines", [])
	if refine_id in arr:
		arr.erase(refine_id)
	else:
		var relic_count = 0
		for relic in GameState.global_relics:
			if relic != null:
				relic_count += 1
		if relic_count + arr.size() + 1 > MAX_PASSIVE_SLOTS:
			return
		arr.append(refine_id)
	_state["active_refines"] = arr
	_refresh_passive_slots()
	_refresh_content()

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
		if _state.player_data.weapon_slot:
			_state.armory.append(_state.player_data.weapon_slot)
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
#  铁匠铺
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
#  特技
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
		var relic = RelicManager.get_relic_data(item_id)
		if not relic.is_empty():
			detail_label.text = relic.get("name", "") + "\n" + relic.get("description", "")
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

func _on_refine_hover(refine_id: String):
	var recipe = RefineManager.get_recipe(refine_id)
	if recipe.is_empty():
		return
	var lines = []
	lines.append(recipe.get("name", refine_id))
	lines.append(recipe.get("description", ""))
	var effect = recipe.get("effect", {})
	if not effect.is_empty():
		lines.append("类型：" + effect.get("type", ""))
	detail_label.text = "\n".join(lines)

func _on_item_hover_exit():
	detail_label.text = "选中物品详情"

# ============================================================
#  拖拽系统
# ============================================================
func _input(event: InputEvent):
	if not _is_dragging:
		return
	if event is InputEventMouseMotion:
		if _drag_preview and is_instance_valid(_drag_preview):
			_drag_preview.global_position = get_viewport().get_mouse_position() - _drag_grab_offset
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_finish_drag()
		get_viewport().set_input_as_handled()
		return

func _attach_drag(btn: Button, meta: Dictionary):
	btn.set_meta("_drag_meta", meta)
	if not btn.gui_input.is_connected(_on_slot_gui_input):
		btn.gui_input.connect(_on_slot_gui_input.bind(btn))

func _on_slot_gui_input(event: InputEvent, btn: Button):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start_drag(btn)

func _start_drag(btn: Button):
	var meta : Dictionary = btn.get_meta("_drag_meta", {})
	if meta.is_empty():
		return
	var src_type = meta.get("source_type", "")
	if src_type == "" or src_type == "empty":
		return

	_is_dragging = true
	_drag_source = btn
	_drag_meta = meta.duplicate()
	_drag_preview = _create_drag_preview(btn.text)
	add_child(_drag_preview)

	var mouse_pos = get_viewport().get_mouse_position()
	_drag_grab_offset = Vector2(30, 12)
	_drag_preview.global_position = mouse_pos - _drag_grab_offset

func _create_drag_preview(text: String) -> Control:
	var panel = Panel.new()
	panel.size = Vector2(80, 22)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 1000
	panel.modulate = Color(1, 1, 1, 0.85)
	var style = load(Config.PATHS.STYLEBOX_8BIT)
	if style:
		panel.add_theme_stylebox_override("panel", style)
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel

func _finish_drag():
	var mouse_pos = get_viewport().get_mouse_position()
	var target = _find_drop_target(mouse_pos)

	if _drag_preview and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
	_drag_preview = null

	if not target.is_empty():
		_execute_drop(target, _drag_meta)

	_is_dragging = false
	_drag_source = null
	_drag_meta = {}
	_drag_grab_offset = Vector2.ZERO

func _find_drop_target(mouse_pos: Vector2) -> Dictionary:
	if discard_zone and is_instance_valid(discard_zone):
		if discard_zone.get_global_rect().has_point(mouse_pos):
			return {"type": "discard"}
	for slot_key in _slot_buttons:
		var btn : Button = _slot_buttons[slot_key]
		if is_instance_valid(btn) and btn.get_global_rect().has_point(mouse_pos):
			return {"type": "slot", "slot": slot_key}
	return {}

func _execute_drop(target: Dictionary, meta: Dictionary):
	match target.get("type", ""):
		"discard":
			_discard_item(meta)
		"slot":
			_handle_slot_drop(target.get("slot", ""), meta)

func _discard_item(meta: Dictionary):
	var unit : UnitData = _state.player_data
	if not unit:
		return
	var src = meta.get("source_type", "")
	if src == "weapon":
		if unit.weapon_slot:
			_state.armory.append(unit.weapon_slot)
			unit.weapon_slot = null
	elif src == "armor":
		var idx = int(meta.get("slot_idx", -1))
		if idx >= 0 and idx < unit.armor_slots.size():
			if unit.armor_slots[idx]:
				_state.armory.append(unit.armor_slots[idx])
				unit.armor_slots[idx] = null
	elif src == "talent":
		_state.locked_talent_id = ""
	else:
		return
	_refresh_all()

func _handle_slot_drop(slot_key: String, meta: Dictionary):
	var unit : UnitData = _state.player_data
	if not unit:
		return
	var src = meta.get("source_type", "")

	# ---- 特技 → 特技槽 ----
	if src == "talent" and slot_key == "talent_slot":
		if _state.streak_locked:
			return
		var talent_id = meta.get("talent_id", "")
		if talent_id == "":
			return
		_state.locked_talent_id = talent_id
		GameState.arena_target_talents[unit.unit_name] = talent_id
		_refresh_all()
		return

	# ---- 商店 → 装备槽 ----
	if src == "shop":
		var shop_index = int(meta.get("shop_index", -1))
		var item_id = meta.get("item_id", "")
		var price = int(meta.get("price", 0))
		if shop_index < 0 or item_id == "":
			return
		var item_data = ItemManager.get_item_data(item_id)
		if not item_data:
			return
		if slot_key == "weapon" and item_data.type != "weapon":
			return
		if slot_key.begins_with("armor_") and item_data.type != "armor":
			return
		if _state.gold < price:
			return

		_state.gold -= price
		_shop_items[shop_index] = null
		var inst = ItemInstance.new()
		inst.item_id = item_id
		inst.count = 1

		if slot_key == "weapon":
			if unit.weapon_slot:
				_state.armory.append(unit.weapon_slot)
			unit.weapon_slot = inst
		elif slot_key.begins_with("armor_"):
			var idx = int(slot_key.substr(6))
			if idx < unit.armor_slots.size():
				if unit.armor_slots[idx]:
					_state.armory.append(unit.armor_slots[idx])
				unit.armor_slots[idx] = inst
		_refresh_all()
		return

	# ---- 装备槽 → 装备槽（交换） ----
	if src == "weapon" or src == "armor":
		var src_idx = int(meta.get("slot_idx", -1))
		var src_inst : ItemInstance = null
		if src == "weapon":
			src_inst = unit.weapon_slot
			unit.weapon_slot = null
		elif src == "armor":
			if src_idx >= 0 and src_idx < unit.armor_slots.size():
				src_inst = unit.armor_slots[src_idx]
				unit.armor_slots[src_idx] = null

		if not src_inst:
			return
		var src_data = ItemManager.get_item_data(src_inst.item_id)
		if not src_data:
			_restore_to_source(unit, src, src_idx, src_inst)
			return

		if slot_key == "weapon" and src_data.type != "weapon":
			_restore_to_source(unit, src, src_idx, src_inst)
			return
		if slot_key.begins_with("armor_") and src_data.type != "armor":
			_restore_to_source(unit, src, src_idx, src_inst)
			return

		var target_inst : ItemInstance = null
		if slot_key == "weapon":
			target_inst = unit.weapon_slot
			unit.weapon_slot = src_inst
		elif slot_key.begins_with("armor_"):
			var tidx = int(slot_key.substr(6))
			if tidx < unit.armor_slots.size():
				target_inst = unit.armor_slots[tidx]
				unit.armor_slots[tidx] = src_inst

		if target_inst:
			_restore_to_source(unit, src, src_idx, target_inst)

		_refresh_all()

func _restore_to_source(unit: UnitData, slot: String, idx: int, inst: ItemInstance):
	if slot == "weapon":
		if not unit.weapon_slot:
			unit.weapon_slot = inst
		else:
			_state.armory.append(inst)
	elif slot == "armor":
		if idx >= 0 and idx < unit.armor_slots.size():
			if not unit.armor_slots[idx]:
				unit.armor_slots[idx] = inst
			else:
				_state.armory.append(inst)
