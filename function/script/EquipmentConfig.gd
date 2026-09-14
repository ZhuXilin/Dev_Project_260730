extends Panel

enum Mode { DEPLOY, MAP, SHOP, FORGE }

# ============================================================
#  样式常量
# ============================================================
class Style:
	const FONT_TINY = 4
	const FONT_SMALL = 6
	const FONT_NORMAL = 6
	const FONT_LARGE = 6
	
	const BTN_ITEM_SIZE = Vector2(20, 10)
	const BTN_TALENT_SIZE = Vector2(20, 15)
	const BTN_SHOP_SIZE = Vector2(24, 10)
	const BTN_LIBRARY_SIZE = Vector2(20, 10)
	const BTN_RELIC_SIZE = Vector2(24, 12)
	
	const ICON_SIZE = Vector2(11, 11)
	const SEPARATOR_TEXT = "──────"

var current_mode: Mode = Mode.DEPLOY
var selected_units: Array[String] = []
var target_slot: int = -1
var party: Array = []
var _is_building_ui: bool = false
var _build_ui_pending: bool = false
var _is_closing: bool = false

const MAX_RELIC_SLOTS = 3

# ---- 硬性上限（防止异常存档注入超大值） ----
const MAX_ARMOR_SLOTS_HARD_LIMIT : int = 10
const MIN_TALENT_SLOTS : int = 1

# ---- FORGE 模式 ----
const FORGE_MAX_SLOTS : int = 3
var _forge_slots : Array = []
var _forge_matched_recipe : String = ""
var forge_result_label : Label = null

# ---- 预加载 ShopManager 脚本 ----
const ShopManagerScript = preload(Config.PATHS.SHOP_MANAGER_SCRIPT)

# ---- 手动拖拽状态 ----
var _is_dragging: bool = false
var _drag_source: Button = null
var _drag_meta: Dictionary = {}
var _drag_preview: Control = null
var _drag_grab_offset: Vector2 = Vector2.ZERO

# ---- 目标控件高亮 ----
var _target_states: Dictionary = {}

# ---- 标签栏（右侧） ----
var current_tab: String = "weapon"

var shop_manager = null

# ---- 右侧标签栏 ----
@onready var mode_label = $VBoxContainer/TopBar/ModeLabel
@onready var gold_label = $VBoxContainer/GoldLabel
@onready var close_btn = $VBoxContainer/BottomHBox/CloseBtn
@onready var confirm_btn = $VBoxContainer/BottomHBox/ConfirmBtn
@onready var unit_container = $VBoxContainer/MainHBox/LeftVBox/UnitContainer
@onready var right_container = $VBoxContainer/MainHBox/RightContainer
@onready var shop_scroll: ScrollContainer = $VBoxContainer/MainHBox/RightContainer/ShopScroll
@onready var shop_container: GridContainer = $VBoxContainer/MainHBox/RightContainer/ShopScroll/ShopContainer
@onready var reset_btn = $VBoxContainer/MainHBox/RightContainer/ResetBtn
@onready var discard_zone = $VBoxContainer/MainHBox/RightContainer/DiscardZone
@onready var tab_bar = $VBoxContainer/MainHBox/RightContainer/TabBar
@onready var weapon_tab_btn = $VBoxContainer/MainHBox/RightContainer/TabBar/WeaponTabBtn
@onready var talent_tab_btn = $VBoxContainer/MainHBox/RightContainer/TabBar/TalentTabBtn
@onready var relic_section: VBoxContainer = $VBoxContainer/MainHBox/LeftInfoColumn/RelicSection
@onready var relic_container: HBoxContainer = $VBoxContainer/MainHBox/LeftInfoColumn/RelicSection/RelicContainer

# ============================================================
#  初始化
# ============================================================
func _ready():
	if weapon_tab_btn:
		weapon_tab_btn.pressed.connect(_on_weapon_tab_pressed)
	if talent_tab_btn:
		talent_tab_btn.pressed.connect(_on_talent_tab_pressed)

func _on_weapon_tab_pressed():
	_switch_tab("weapon")

func _on_talent_tab_pressed():
	_switch_tab("talent")

func init(units: Array[String], slot: int, mode: Mode):
	print("EquipmentConfig.init 被调用，模式: ", mode)
	var canvas_layer = get_parent()
	if canvas_layer is CanvasLayer:
		canvas_layer.layer = 20
		print("CanvasLayer layer 设置为 20")
	
	selected_units = units
	target_slot = slot
	current_mode = mode
	
	# ---- SHOP 模式特殊处理 ----
	if mode == Mode.SHOP:
		if not shop_manager:
			shop_manager = ShopManagerScript.new()
			add_child(shop_manager)
			shop_manager.shop_updated.connect(_on_shop_updated)
		shop_manager.generate_shop_items()
		shop_manager.reset_count = 0
	
	# ---- FORGE 模式：初始化插槽 ----
	if mode == Mode.FORGE:
		_forge_slots.clear()
		for i in range(FORGE_MAX_SLOTS):
			_forge_slots.append(null)
		_forge_matched_recipe = ""
	
	_copy_party_data()
	_build_ui()

func _on_shop_updated():
	_update_gold_display()
	_schedule_build_ui()

func _on_close_pressed():
	_is_closing = true
	if current_mode == Mode.SHOP and shop_manager:
		if shop_manager.shop_updated.is_connected(_on_shop_updated):
			shop_manager.shop_updated.disconnect(_on_shop_updated)
		shop_manager.queue_free()
		shop_manager = null
	var canvas_layer = get_parent()
	if canvas_layer:
		canvas_layer.queue_free()
	else:
		queue_free()

# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	if _is_closing:
		return
	if _is_building_ui:
		print("_build_ui 被跳过（重入保护）")
		return
	_is_building_ui = true
	_build_ui_inner()
	_is_building_ui = false

func _build_ui_inner():
	print("[A] 开始")
	
	_build_relic_slots()
	print("[B] _build_relic_slots 完成")
	
	if not mode_label:
		print("[X] mode_label 为 null")
		return
	
	_update_gold_display()
	print("[C] _update_gold_display 完成")
	
	shop_container.visible = false
	discard_zone.visible = false
	reset_btn.visible = false
	tab_bar.visible = false
	right_container.visible = true
	
	var left_column = $VBoxContainer/MainHBox/LeftVBox
	if left_column:
		left_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	print("[D] 进入 match，current_mode = ", current_mode)
	
	match current_mode:
		Mode.DEPLOY:
			print("[E1] DEPLOY 开始")
			mode_label.text = "装备配置 - 出战准备"
			close_btn.text = "返回"
			confirm_btn.visible = true
			confirm_btn.text = "出发"
			confirm_btn.disabled = false
			gold_label.visible = false
			tab_bar.visible = true
			weapon_tab_btn.visible = true
			talent_tab_btn.visible = true
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "特技库"
			if current_tab == "":
				current_tab = "weapon"
			_update_tab_style()
			if current_tab == "weapon":
				_build_weapon_grid(shop_container)
			else:
				_build_talent_grid(shop_container)
			shop_container.visible = true
			reset_btn.visible = false
			discard_zone.visible = false
			if left_column:
				left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			print("[E1] DEPLOY 完成")
		
		Mode.MAP:
			print("[E2] MAP 开始")
			mode_label.text = "装备配置 - 队伍管理"
			close_btn.text = "返回"
			confirm_btn.visible = false
			gold_label.visible = false
			tab_bar.visible = true
			weapon_tab_btn.visible = false
			talent_tab_btn.visible = true
			talent_tab_btn.disabled = true
			talent_tab_btn.text = "特技库"
			talent_tab_btn.modulate = Color.WHITE
			_build_talent_grid(shop_container)
			shop_container.visible = true
			discard_zone.visible = true
			reset_btn.visible = false
			if left_column:
				left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			print("[E2] MAP 完成")
		
		Mode.SHOP:
			print("[E3] SHOP 开始")
			mode_label.text = "商店"
			close_btn.text = "关闭"
			confirm_btn.visible = false
			gold_label.visible = true
			tab_bar.visible = false
			
			print("[E3.1] 准备 _build_shop_items")
			_build_shop_items()
			print("[E3.2] _build_shop_items 完成")
			
			shop_container.visible = true
			reset_btn.visible = true
			if shop_manager:
				reset_btn.text = "重置商店 (" + str(shop_manager.get_reset_cost()) + "G)"
			discard_zone.visible = true
			if left_column:
				left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			print("[E3.3] SHOP 完成")
		
		Mode.FORGE:
			print("[E4] FORGE 开始")
			mode_label.text = "铁匠铺 - 防具合成"
			close_btn.text = "关闭"
			confirm_btn.visible = true
			confirm_btn.text = "合成"
			confirm_btn.disabled = (_forge_matched_recipe == "")
			gold_label.visible = false
			tab_bar.visible = false
			
			_build_forge_slots()
			shop_container.visible = true
			
			reset_btn.visible = true
			reset_btn.text = "清空插槽"
			
			discard_zone.visible = false
			if left_column:
				left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			
			_display_forge_recipe_info()
			print("[E4] FORGE 完成")
	
	print("[F] 字体设置开始")
	close_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	confirm_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	reset_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	print("[F] 字体设置完成")
	
	print("[G] _build_unit_columns 开始")
	_build_unit_columns()
	print("[H] _build_unit_columns 完成")
	
	visible = true
	print("[I] 全部完成")

func _update_gold_display():
	if gold_label:
		gold_label.text = "金币: " + str(EconomyManager.get_temp_gold())

# ============================================================
#  单位列构建
# ============================================================
func _build_unit_columns():
	for child in unit_container.get_children():
		unit_container.remove_child(child)
		child.free()
	
	for i in range(party.size()):
		var unit = party[i]
		print("  [U", i, "] START")
		
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		unit_container.add_child(col)
		
		var name_label = _create_label(
			unit.display_name + "(" + UnitDataManager.get_unit_type_display_name(unit.unit_name) + ")",
			Style.FONT_SMALL
		)
		col.add_child(name_label)
		
		col.add_child(_create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))
		
		col.add_child(_create_item_button(unit.weapon_slot, "weapon", i, -1))
		
		col.add_child(_create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))
		
		for slot_idx in range(unit.armor_slots.size()):
			var armor_btn = _create_item_button(unit.armor_slots[slot_idx], "armor", i, slot_idx)
			if current_mode == Mode.DEPLOY:
				armor_btn.disabled = true
			col.add_child(armor_btn)
		
		col.add_child(_create_label(Style.SEPARATOR_TEXT, Style.FONT_SMALL))
		col.add_child(_create_label("特技", Style.FONT_SMALL))
		
		var talent_inst = unit.talent_slots[0] if unit.talent_slots.size() > 0 else null
		col.add_child(_create_talent_button(talent_inst, i, 0))

# ============================================================
#  创建按钮
# ============================================================
func _create_item_button(inst: ItemInstance, slot_type: String, unit_idx: int, slot_idx: int) -> Button:
	var btn = _create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	
	btn.text = _get_item_name(inst) if inst else "空"
	
	btn.set_meta("slot_type", slot_type)
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	btn.set_meta("item_id", inst.item_id if inst else "")
	
	if inst and inst.item_id != "":
		var item_id = inst.item_id
		btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_button_hover_exited)
	
	return btn

func _create_talent_button(inst: TalentInstance, unit_idx: int, slot_idx: int) -> Button:
	var btn = _create_styled_button(Style.FONT_TINY, Style.BTN_TALENT_SIZE)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	btn.set_meta("slot_type", "talent")
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	
	if inst and inst.is_active:
		var data = TalentManager.get_talent_data(inst.talent_id)
		if data:
			btn.text = _get_talent_display_name(data)
			btn.modulate = _get_rarity_color(data.rarity)
			btn.set_meta("talent_id", inst.talent_id)
			btn.mouse_entered.connect(_on_talent_hover_entered.bind(inst.talent_id))
			btn.mouse_exited.connect(_on_talent_hover_exited)
		else:
			btn.text = "空"
			btn.modulate = Color(0.5, 0.5, 0.5, 1)
			btn.set_meta("talent_id", "")
	else:
		btn.text = "空"
		btn.modulate = Color(0.5, 0.5, 0.5, 1)
		btn.set_meta("talent_id", "")
	
	return btn

# ============================================================
#  商店 / 武器库 / 特技库
# ============================================================
func _build_shop_items():
	if not shop_manager:
		return
	_clear_container(shop_container)
	
	shop_container.columns = 3
	shop_container.visible = true
	
	var items = shop_manager.get_shop_items()
	for i in range(items.size()):
		var entry = items[i]
		var btn = _create_styled_button(Style.FONT_SMALL, Style.BTN_SHOP_SIZE)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		
		if entry != null:
			var item_data = entry["item_data"]
			var price = entry["price"]
			btn.text = item_data.name + "\n" + str(price) + "G"
			if item_data.icon:
				btn.icon = item_data.icon
			btn.set_meta("shop_index", i)
			btn.set_meta("slot_type", "shop_item")
			btn.set_meta("item_price", price)
			btn.set_meta("item_id", item_data.id)
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_data.id))
			btn.mouse_exited.connect(_on_button_hover_exited)
		else:
			btn.text = "空位"
			btn.disabled = true
		
		shop_container.add_child(btn)

func _build_weapon_grid(container: GridContainer):
	for child in container.get_children():
		container.remove_child(child)
		child.free()
	container.columns = 3
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "weapon":
			var btn = _create_styled_button(Style.FONT_SMALL, Style.BTN_LIBRARY_SIZE)
			btn.text = data.name
			btn.set_meta("slot_type", "library_weapon")
			btn.set_meta("item_id", item_id)
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
			btn.mouse_exited.connect(_on_button_hover_exited)
			container.add_child(btn)

func _build_talent_grid(container: GridContainer):
	for child in container.get_children():
		container.remove_child(child)
		child.free()
	
	var unlocked = Globals.get_unlocked_talents()
	if unlocked.is_empty():
		container.add_child(_create_label("暂无解锁特技", Style.FONT_SMALL))
		return
	
	for talent_id in unlocked:
		var data = TalentManager.get_talent_data(talent_id)
		if not data:
			continue
		
		var is_equipped = _is_talent_equipped_anywhere(talent_id)
		
		var btn = _create_styled_button(Style.FONT_TINY, Style.BTN_TALENT_SIZE)
		btn.text = _get_talent_display_name(data)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.set_meta("talent_id", talent_id)
		btn.set_meta("slot_type", "library_talent")
		
		var rarity_color = _get_rarity_color(data.rarity)
		
		if is_equipped:
			btn.modulate = Color(0.4, 0.4, 0.4, 1.0)
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			btn.disabled = true
			btn.tooltip_text = "该特技已被其他单位装备"
		else:
			btn.modulate = Color.WHITE
			btn.add_theme_color_override("font_color", rarity_color)
			btn.disabled = false
		
		btn.mouse_entered.connect(_on_talent_hover_entered.bind(talent_id))
		btn.mouse_exited.connect(_on_talent_hover_exited)
		
		container.add_child(btn)

func _get_item_name(inst: ItemInstance) -> String:
	if not inst:
		return ""
	var data = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id

# ============================================================
#  FORGE 模式专用
# ============================================================
func _build_forge_slots():
	_clear_container(shop_container)
	shop_container.columns = FORGE_MAX_SLOTS
	shop_container.visible = true

	# 确保 result label 存在
	_ensure_forge_result_label()

	for i in range(FORGE_MAX_SLOTS):
		var slot_btn = _create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)   # ← 统一
		slot_btn.set_meta("slot_type", "forge_slot")
		slot_btn.set_meta("forge_slot_index", i)

		var inst = _forge_slots[i] if i < _forge_slots.size() else null
		if inst:
			var data = ItemManager.get_item_data(inst.item_id)
			slot_btn.text = data.name if data else inst.item_id
			slot_btn.set_meta("item_id", inst.item_id)
			if data:
				slot_btn.modulate = UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE)
			slot_btn.mouse_entered.connect(_on_button_hover_entered.bind(inst.item_id))
			slot_btn.mouse_exited.connect(_on_button_hover_exited)
		else:
			slot_btn.text = "空"                          # ← 简化为"空"，去掉换行
			slot_btn.set_meta("item_id", "")
			slot_btn.modulate = Color(0.5, 0.5, 0.5)

		shop_container.add_child(slot_btn)

	# 刷新合成结果
	_update_forge_result_label()

func _display_forge_recipe_info():
	var input_ids : Array = []
	for inst in _forge_slots:
		if inst:
			input_ids.append(inst.item_id)

	if input_ids.is_empty():
		_show_detail_in_zone("将防具拖入插槽以匹配配方")
		_forge_matched_recipe = ""
		_update_forge_result_label()   # ← 新增
		return

	_forge_matched_recipe = RecipeManager.match_recipe(input_ids)

	if _forge_matched_recipe == "":
		var names = []
		for id in input_ids:
			var d = ItemManager.get_item_data(id)
			names.append(d.name if d else id)
		_show_detail_in_zone("无匹配配方\n\n已放: " + ", ".join(names))
		_update_forge_result_label()   # ← 新增
		return

	var recipe = RecipeManager.get_recipe(_forge_matched_recipe)
	var out_data = ItemManager.get_item_data(_forge_matched_recipe)
	var lines = []
	lines.append("匹配配方: " + (out_data.name if out_data else _forge_matched_recipe))
	lines.append("")
	lines.append("消耗:")
	for id in recipe.inputs:
		var d = ItemManager.get_item_data(id)
		lines.append("  " + (d.name if d else id))
	lines.append("")
	lines.append("→ 产物: " + (out_data.name if out_data else _forge_matched_recipe))
	_show_detail_in_zone("\n".join(lines))

	_update_forge_result_label()   # ← 新增

func _execute_forge_drop(data: Dictionary, target: Control):
	var slot_idx = target.get_meta("forge_slot_index", -1)
	if slot_idx < 0 or slot_idx >= _forge_slots.size():
		return

	var src_type = data.get("slot_type", "")

	# ---- forge_slot → forge_slot 互换 ----
	if src_type == "forge_slot":
		var from_idx = data.get("forge_slot_index", -1)
		if from_idx >= 0 and from_idx < _forge_slots.size() and from_idx != slot_idx:
			var temp = _forge_slots[from_idx]
			_forge_slots[from_idx] = _forge_slots[slot_idx]
			_forge_slots[slot_idx] = temp
		_display_forge_recipe_info()
		_schedule_build_ui()
		return

	# ---- armor → forge_slot ----
	if src_type == "armor":
		var unit_idx = data.get("unit_idx", -1)
		var src_slot = data.get("slot_idx", -1)
		if unit_idx < 0 or src_slot < 0:
			return
		var inst = party[unit_idx].armor_slots[src_slot]
		if inst == null:
			return
		_forge_slots[slot_idx] = inst
		_display_forge_recipe_info()
		_schedule_build_ui()
		return

func _on_forge_clear_pressed():
	_forge_slots.clear()
	for i in range(FORGE_MAX_SLOTS):
		_forge_slots.append(null)
	_forge_matched_recipe = ""
	_display_forge_recipe_info()
	_schedule_build_ui()

func _on_forge_craft_pressed():
	if _forge_matched_recipe == "":
		return
	var recipe = RecipeManager.get_recipe(_forge_matched_recipe)
	if not recipe:
		return

	# 1. 收集所有输入防具在队伍里的位置
	var positions : Array = []
	for inst in _forge_slots:
		if inst == null:
			continue
		var found = false
		for ui in range(party.size()):
			for si in range(party[ui].armor_slots.size()):
				if party[ui].armor_slots[si] == inst:
					positions.append({"unit_idx": ui, "slot_idx": si})
					found = true
					break
			if found:
				break

	if positions.size() != recipe.inputs.size():
		print("FORGE 合成失败：输入不完整，positions=", positions.size(), " inputs=", recipe.inputs.size())
		return

	# 2. 第一个位置放产物，其余清空
	var first = positions[0]
	for i in range(1, positions.size()):
		var p = positions[i]
		party[p.unit_idx].armor_slots[p.slot_idx] = null

	var out_inst = ItemInstance.new()
	out_inst.item_id = _forge_matched_recipe
	out_inst.count = 1
	party[first.unit_idx].armor_slots[first.slot_idx] = out_inst

	# 3. 清空 forge 状态
	_forge_slots.clear()
	for i in range(FORGE_MAX_SLOTS):
		_forge_slots.append(null)
	_forge_matched_recipe = ""

	_sync_all()
	_schedule_build_ui()

# ============================================================
#  详情显示
# ============================================================
func show_item_detail(item_id: String):
	var relic_data = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		_show_relic_detail_in_zone(relic_data)
		return
	
	var data = ItemManager.get_item_data(item_id)
	if not data:
		return
	
	var lines = []
	lines.append(data.name)
	
	if data.quality and data.quality != "":
		lines.append("品质: " + _get_quality_display_name(data.quality))
	
	if data.description and data.description != "":
		lines.append(data.description)
	
	if data.type == "weapon":
		lines.append("基础攻击: " + str(data.base_attack))
		lines.append("射程: " + str(data.min_attack_range) + "~" + str(data.attack_range))
		if data.modifier and not data.modifier.is_empty():
			var mod_str = ""
			for key in data.modifier:
				mod_str += _get_attr_display_name(key) + "+" + str(data.modifier[key]) + " "
			lines.append("补正: " + mod_str.strip_edges())
	elif data.type == "armor":
		if data.defense > 0:
			lines.append("防御: +" + str(data.defense))
		if data.slot_count > 0:
			lines.append("占用槽位: " + str(data.slot_count))
	
	if data.price > 0:
		lines.append("价格: " + str(data.price) + "G")
	
	_show_detail_in_zone("\n".join(lines))

func _show_relic_detail_in_zone(data: Dictionary):
	var lines = []
	lines.append(data.get("name", "未知遗物"))
	lines.append(data.get("description", ""))
	
	var stats = data.get("stats", {})
	if not stats.is_empty():
		lines.append("")
		lines.append("— 属性加成 —")
		for key in stats:
			var stat_name = _get_attr_display_name(key)
			lines.append(stat_name + ": +" + str(stats[key]))
	
	_show_detail_in_zone("\n".join(lines))

func _get_quality_display_name(quality: String) -> String:
	match quality:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return quality

func _get_attr_display_name(attr: String) -> String:
	match attr:
		"strength": return "力量"
		"dexterity": return "敏捷"
		"intelligence": return "智力"
		"faith": return "信仰"
		"arcane": return "感应"
		"attack": return "攻击"
		"defense": return "防御"
		"magic_attack": return "魔法攻击"
		"move_range": return "移动力"
		_: return attr

func hide_item_detail():
	_clear_detail_zone()

func _on_button_hover_entered(item_id: String):
	show_item_detail(item_id)

func _on_button_hover_exited():
	hide_item_detail()

# ============================================================
#  特技悬停详情
# ============================================================
func _on_talent_hover_entered(talent_id: String):
	var data = TalentManager.get_talent_data(talent_id)
	if data:
		_show_talent_detail(data)

func _on_talent_hover_exited():
	_hide_talent_detail()

func _show_talent_detail(data):
	var lines = []
	lines.append(data.display_name)
	lines.append(data.description)
	lines.append("稀有度: " + data.rarity)
	lines.append("流派: " + data.school)
	lines.append("积累: " + str(data.accumulation_threshold) + "回合")
	
	var compatible_units = data.compatible_units if data.compatible_units != null else []
	if not compatible_units.is_empty():
		var unit_names = []
		for unit_key in compatible_units:
			var display = UnitDataManager.get_unit_type_display_name(unit_key)
			if display != "":
				unit_names.append(display)
		lines.append("可装备: " + "/".join(unit_names))
	else:
		lines.append("可装备: 全部")
	
	_show_detail_in_zone("\n".join(lines))

func _hide_talent_detail():
	_clear_detail_zone()

func _get_talent_display_name(data) -> String:
	var rarity_icon = ""
	match data.rarity:
		"common": rarity_icon = ""
		"rare": rarity_icon = "★"
		"epic": rarity_icon = "★★"
		"legendary": rarity_icon = "★★★"
	
	var compatible_units = data.compatible_units if data.compatible_units != null else []
	var unit_names = []
	for unit_key in compatible_units:
		var display = UnitDataManager.get_unit_type_display_name(unit_key)
		if display != "":
			unit_names.append(display)
	var compat_str = "/".join(unit_names) if not unit_names.is_empty() else "全部"
	
	return rarity_icon + data.display_name + "\n" + compat_str

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(1.0, 1.0, 1.0, 1.0)
		"rare": return Color(0.3, 0.6, 1.0, 1.0)
		"epic": return Color(0.7, 0.3, 1.0, 1.0)
		"legendary": return Color(1.0, 0.7, 0.0, 1.0)
		_: return Color.WHITE

# ============================================================
#  标签切换
# ============================================================
func _switch_tab(tab: String):
	if current_tab == tab:
		return
	current_tab = tab
	_update_tab_style()
	
	_clear_container(shop_container)
	if tab == "weapon":
		_build_weapon_grid(shop_container)
	else:
		_build_talent_grid(shop_container)
	shop_container.visible = true

func _update_tab_style():
	if not weapon_tab_btn or not talent_tab_btn:
		return
	if current_tab == "weapon":
		weapon_tab_btn.modulate = Color.WHITE
		talent_tab_btn.modulate = Color(0.5, 0.5, 0.5)
	else:
		weapon_tab_btn.modulate = Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE

# ============================================================
#  目标控件高亮
# ============================================================
func _get_all_target_controls() -> Array[Control]:
	var targets: Array[Control] = []

	for btn in relic_container.get_children():
		if btn is Button:
			targets.append(btn)

	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				targets.append(child)
	
	# DEPLOY 模式
	if current_mode == Mode.DEPLOY and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				targets.append(btn)
	
	# MAP 模式
	if current_mode == Mode.MAP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				targets.append(btn)
	
	# FORGE 模式：合成插槽
	if current_mode == Mode.FORGE and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and btn.get_meta("slot_type", "") == "forge_slot":
				targets.append(btn)
	
	if discard_zone.visible:
		targets.append(discard_zone)
	
	return targets

func _update_targets_visuals():
	if _drag_meta.is_empty():
		_reset_targets_visuals()
		return
	
	var targets = _get_all_target_controls()
	_target_states.clear()
	
	var is_talent_drag = _drag_meta.has("talent_id") and _drag_meta["talent_id"] != ""
	var is_talent_library_drag = _drag_meta.get("slot_type", "") == "library_talent"
	
	for target in targets:
		if not _target_states.has(target):
			_target_states[target] = target.modulate
		
		if is_talent_drag and not is_talent_library_drag and target == discard_zone:
			target.modulate = Color.WHITE
			continue
		
		if is_talent_library_drag and target == discard_zone:
			target.modulate = Color(0.4, 0.4, 0.4, 0.5)
			continue
		
		var is_valid = _is_valid_drop(_drag_meta, target)
		if is_valid:
			target.modulate = Color.WHITE
		else:
			target.modulate = Color(0.4, 0.4, 0.4, 1.0)

func _reset_targets_visuals():
	for target in _target_states.keys():
		if is_instance_valid(target):
			target.modulate = _target_states[target]
	_target_states.clear()

# ============================================================
#  拖拽检测
# ============================================================
func _find_control_at_position(pos: Vector2) -> Control:
	const BUFFER = 4
	
	for btn in relic_container.get_children():
		if btn is Button:
			var rect = btn.get_global_rect().grow(BUFFER)
			if rect.has_point(pos):
				return btn
				
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				if current_mode == Mode.DEPLOY and child.get_meta("slot_type", "") == "armor":
					continue
				var rect = child.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return child
	
	if current_mode == Mode.DEPLOY and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return btn
	
	if current_mode == Mode.MAP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return btn
	
	if current_mode == Mode.SHOP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return btn
	
	if current_mode == Mode.FORGE and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and btn.get_meta("slot_type", "") == "forge_slot":
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return btn
	
	return null

func _get_target_from_position(global_pos: Vector2) -> Control:
	const BUFFER = 4
	
	if discard_zone.visible and discard_zone.get_global_rect().has_point(global_pos):
		return discard_zone

	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				var rect = child.get_global_rect().grow(BUFFER)
				if rect.has_point(global_pos):
					return child

	for btn in relic_container.get_children():
		if btn is Button:
			var rect = btn.get_global_rect().grow(BUFFER)
			if rect.has_point(global_pos):
				return btn

	if current_mode == Mode.DEPLOY and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(global_pos):
					return btn

	if current_mode == Mode.MAP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(global_pos):
					return btn

	if current_mode == Mode.SHOP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(global_pos):
					return btn

	if current_mode == Mode.FORGE and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and btn.get_meta("slot_type", "") == "forge_slot":
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(global_pos):
					return btn

	return null

func _is_valid_drop(data: Dictionary, target: Control) -> bool:
	var source_type = data["slot_type"]
	var target_type = target.get_meta("slot_type", "")
	var discard = target == discard_zone

	# ===== FORGE 模式优先判断 =====
	if current_mode == Mode.FORGE:
		return _is_valid_forge_drop(data, target)

	# ===== 遗物槽规则（所有模式） =====
	if source_type == "relic_slot":
		if target_type == "relic_slot":
			return true
		if discard:
			return true
		return false
	if target_type == "relic_slot":
		return false

	# ===== 特技拖到丢弃区 =====
	if discard and source_type in ["library_talent", "talent"]:
		if source_type == "library_talent":
			return false
		return true

	if current_mode == Mode.DEPLOY:
		if discard:
			return false
		if source_type == "library_weapon":
			return target_type == "weapon"
		if source_type == "weapon" and target_type == "weapon":
			return true
		if source_type == "library_talent" and target_type == "talent":
			return _check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent":
			return _check_talent_compatibility(data, target)
		return false

	if current_mode == Mode.MAP:
		if discard:
			if source_type == "library_talent":
				return false
			if source_type == "weapon":
				return false
			return true
		if source_type == "library_weapon":
			return target_type == "weapon"
		if source_type == "weapon" and target_type == "weapon":
			return true
		if source_type == "armor" and target_type == "armor":
			return true
		if source_type == "library_talent" and target_type == "talent":
			return _check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent":
			return _check_talent_compatibility(data, target)
		return false

	if current_mode == Mode.SHOP:
		if discard:
			if source_type in ["shop_item", "weapon", "library_talent", "talent"]:
				return false
			return true
		
		if source_type == "shop_item":
			var item_data = data.get("item_data")
			if not item_data:
				return false
			if item_data.type == "weapon":
				return target_type == "weapon"
			elif item_data.type == "armor":
				return target_type == "armor"
			elif item_data.type == "relic":
				return target_type == "relic"
			return false
		
		if source_type == "weapon" and target_type == "weapon":
			return true
		if source_type == "armor" and target_type == "armor":
			return true
		return false

	return false

func _is_valid_forge_drop(data: Dictionary, target: Control) -> bool:
	var src_type = data.get("slot_type", "")
	var tgt_type = target.get_meta("slot_type", "")

	if tgt_type != "forge_slot":
		return false

	var slot_idx = target.get_meta("forge_slot_index", -1)

	# forge_slot → forge_slot（互换）
	if src_type == "forge_slot":
		return true

	# armor → forge_slot
	if src_type == "armor":
		var unit_idx = data.get("unit_idx", -1)
		var src_slot = data.get("slot_idx", -1)
		if unit_idx < 0 or src_slot < 0:
			return false
		var inst = party[unit_idx].armor_slots[src_slot]
		if inst == null:
			return false
		# 已在其他 forge_slot 里
		for i in range(_forge_slots.size()):
			if _forge_slots[i] == inst and i != slot_idx:
				return false
		return true

	return false

# ============================================================
#  拖拽执行
# ============================================================
func _execute_drop(data: Dictionary, target: Control):
	# ---- FORGE 模式 ----
	if current_mode == Mode.FORGE:
		_execute_forge_drop(data, target)
		return

	var discard = target == discard_zone
	var source_type = data["slot_type"]
	var target_type = target.get_meta("slot_type", "")
	
	if source_type == "relic_slot":
		if discard:
			_discard_relic(data)
			return
		if target_type == "relic_slot":
			_swap_relics(data, target)
			return

	if discard and source_type == "talent":
		_execute_talent_remove(data)
		return

	if discard:
		_discard_item(data)
		return

	if source_type == "shop_item":
		_buy_shop_item(data, target)
		return

	if source_type == "library_weapon":
		_library_to_weapon(data, target)
		return

	if source_type == "library_talent" and target_type == "talent":
		_execute_talent_drop(data, target)
		return

	if source_type == "talent" and target_type == "talent":
		_execute_talent_drop(data, target)
		return

	if source_type == "weapon" and target_type == "weapon":
		_swap_weapons(data, target)
	elif source_type == "armor" and target_type == "armor":
		_swap_armor(data, target)

func _discard_item(data: Dictionary):
	var source_type = data["slot_type"]
	if source_type == "library_weapon" or source_type == "weapon":
		return
	
	var unit_idx = data["unit_idx"]
	var slot_idx = data["slot_idx"]
	
	if source_type == "armor":
		party[unit_idx].armor_slots[slot_idx] = null
	elif source_type == "talent":
		_discard_talent(data)
	
	_sync_all()
	_schedule_build_ui()

# ============================================================
#  特技拖拽逻辑
# ============================================================
func _execute_talent_drop(data: Dictionary, target: Control):
	var source_type = data.get("slot_type", "")
	var target_type = target.get_meta("slot_type", "")
	
	if target == discard_zone:
		_discard_talent(data)
		return
	
	if source_type == "library_talent" and target_type == "talent":
		var talent_id = data.get("talent_id", "")
		if talent_id == "":
			return
		var unit_idx = target.get_meta("unit_idx", -1)
		var slot_idx = target.get_meta("slot_idx", -1)
		if unit_idx == -1 or slot_idx == -1:
			return
		if not Globals.is_talent_unlocked(talent_id):
			return
		
		if _is_talent_already_equipped(talent_id, unit_idx, slot_idx):
			var equipped_unit = _get_unit_with_talent(talent_id)
			Globals.show_confirm(
				self,
				"特技已被 %s 装备，不可重复装备" % equipped_unit,
				"确定", "", func(): pass, func(): pass, false
			)
			return
		
		var inst = TalentInstance.new()
		inst.talent_id = talent_id
		inst.is_active = true
		party[unit_idx].talent_slots[slot_idx] = inst
		_sync_all()
		_refresh_after_talent_change()
		return
	
	if source_type == "talent" and target_type == "talent":
		var src_unit = data.get("unit_idx", -1)
		var src_slot = data.get("slot_idx", -1)
		var tgt_unit = target.get_meta("unit_idx", -1)
		var tgt_slot = target.get_meta("slot_idx", -1)
		if src_unit == -1 or tgt_unit == -1:
			return
		
		var src_inst = party[src_unit].talent_slots[src_slot]
		var tgt_inst = party[tgt_unit].talent_slots[tgt_slot]
		
		var src_talent_id = src_inst.talent_id if src_inst and src_inst.is_active else ""
		var tgt_talent_id = tgt_inst.talent_id if tgt_inst and tgt_inst.is_active else ""
		
		if src_talent_id == "" and tgt_talent_id == "":
			return
		
		if tgt_talent_id == "":
			if _is_talent_already_equipped(src_talent_id, tgt_unit, tgt_slot):
				var equipped_unit = _get_unit_with_talent(src_talent_id)
				Globals.show_confirm(self, "特技已被 %s 装备，不可重复装备" % equipped_unit, "确定", "", func(): pass, func(): pass, false)
				return
			party[tgt_unit].talent_slots[tgt_slot] = src_inst
			party[src_unit].talent_slots[src_slot] = null
			_sync_all()
			_refresh_after_talent_change()
			return
		
		if src_talent_id == "" and tgt_talent_id != "":
			if _is_talent_already_equipped(tgt_talent_id, src_unit, src_slot):
				var equipped_unit = _get_unit_with_talent(tgt_talent_id)
				Globals.show_confirm(self, "特技已被 %s 装备，不可重复装备" % equipped_unit, "确定", "", func(): pass, func(): pass, false)
				return
			party[src_unit].talent_slots[src_slot] = tgt_inst
			party[tgt_unit].talent_slots[tgt_slot] = null
			_sync_all()
			_refresh_after_talent_change()
			return
		
		if _is_talent_already_equipped(tgt_talent_id, src_unit, src_slot):
			var equipped_unit = _get_unit_with_talent(tgt_talent_id)
			Globals.show_confirm(self, "特技已被 %s 装备，不可重复装备" % equipped_unit, "确定", "", func(): pass, func(): pass, false)
			return
		
		if _is_talent_already_equipped(src_talent_id, tgt_unit, tgt_slot):
			var equipped_unit = _get_unit_with_talent(src_talent_id)
			Globals.show_confirm(self, "特技已被 %s 装备，不可重复装备" % equipped_unit, "确定", "", func(): pass, func(): pass, false)
			return
		
		var temp = party[src_unit].talent_slots[src_slot]
		party[src_unit].talent_slots[src_slot] = party[tgt_unit].talent_slots[tgt_slot]
		party[tgt_unit].talent_slots[tgt_slot] = temp
		_sync_all()
		_refresh_after_talent_change()
		return

func _refresh_after_talent_change():
	_schedule_build_ui()

func _discard_talent(data: Dictionary):
	var source_type = data.get("slot_type", "")
	if source_type == "library_talent":
		return
	if source_type == "talent":
		var unit_idx = data.get("unit_idx", -1)
		var slot_idx = data.get("slot_idx", -1)
		if unit_idx == -1 or slot_idx == -1:
			return
		party[unit_idx].talent_slots[slot_idx] = null
		_sync_all()
		_refresh_after_talent_change()

func _buy_shop_item(data: Dictionary, target: Control):
	print("=== _buy_shop_item 开始 ===")
	if target == null:
		return
	if not shop_manager:
		return

	var shop_index = data.get("shop_index", -1)
	if shop_index == -1:
		return

	var items = shop_manager.get_shop_items()
	if shop_index < 0 or shop_index >= items.size():
		return
	var entry = items[shop_index]
	if entry == null:
		return
	var item_data = entry["item_data"]
	if not item_data:
		return

	var target_unit_idx = target.get_meta("unit_idx", -1)
	var target_slot_idx = target.get_meta("slot_idx", -1)

	var result = shop_manager.buy_shop_item(shop_index)
	if not result["success"]:
		_show_buy_failure_message(result.get("reason", "unknown"))
		return

	var inst = ItemInstance.new()
	inst.item_id = item_data.id
	inst.count = 1

	if item_data.type == "weapon":
		if target_unit_idx != -1:
			party[target_unit_idx].weapon_slot = inst
		else:
			Globals.unlock_item(item_data.id)
	elif item_data.type == "armor":
		if target_unit_idx != -1 and target_slot_idx != -1:
			party[target_unit_idx].armor_slots[target_slot_idx] = inst

	_sync_all()
	_update_gold_display()

func _library_to_weapon(data: Dictionary, target: Control):
	var item_id = data["item_id"]
	var unit_idx = target.get_meta("unit_idx", -1)
	if unit_idx == -1:
		return
	var inst = ItemInstance.new()
	inst.item_id = item_id
	inst.count = 1
	party[unit_idx].weapon_slot = inst
	_sync_all()
	_schedule_build_ui()

func _swap_weapons(data: Dictionary, target: Control):
	var src_unit = data["unit_idx"]
	var tgt_unit = target.get_meta("unit_idx", -1)
	if tgt_unit == -1:
		return
	var temp = party[src_unit].weapon_slot
	party[src_unit].weapon_slot = party[tgt_unit].weapon_slot
	party[tgt_unit].weapon_slot = temp
	_sync_all()
	_schedule_build_ui()

func _swap_armor(data: Dictionary, target: Control):
	var src_unit = data["unit_idx"]
	var src_slot = data["slot_idx"]
	var tgt_unit = target.get_meta("unit_idx", -1)
	var tgt_slot = target.get_meta("slot_idx", -1)
	if tgt_unit == -1 or tgt_slot == -1:
		return
	var temp = party[src_unit].armor_slots[src_slot]
	party[src_unit].armor_slots[src_slot] = party[tgt_unit].armor_slots[tgt_slot]
	party[tgt_unit].armor_slots[tgt_slot] = temp
	_sync_all()
	_schedule_build_ui()

# ============================================================
#  同步保存
# ============================================================
func _sync_all():
	for i in range(party.size()):
		if i < GameState.party.size():
			GameState.party[i].weapon_slot = party[i].weapon_slot
			GameState.party[i].armor_slots = party[i].armor_slots.duplicate()
			GameState.party[i].max_armor_slots = party[i].max_armor_slots
			GameState.party[i].talent_slots = party[i].talent_slots.duplicate()

			# ---- 防具槽补齐 ----
			var armor_target = clampi(
				GameState.party[i].max_armor_slots,
				0,
				MAX_ARMOR_SLOTS_HARD_LIMIT
			)
			GameState.party[i].max_armor_slots = armor_target
			GameState.party[i].armor_slots.resize(armor_target)

			# ---- 词条槽补齐 ----
			var talent_target = maxi(
				GameState.party[i].talent_slots.size(),
				MIN_TALENT_SLOTS
			)
			GameState.party[i].talent_slots.resize(talent_target)
	call_deferred("_deferred_auto_save")

func _deferred_auto_save():
	print("_deferred_auto_save 开始")
	SaveManager.auto_save()
	print("_deferred_auto_save 完成")

# ============================================================
#  手动拖拽
# ============================================================
func _input(event: InputEvent):
	if _has_active_confirm_ui():
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		var btn = _find_control_at_position(mouse_pos)
		if btn:
			_start_drag(btn)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_end_drag()
	elif event is InputEventMouseMotion:
		if _is_dragging:
			_update_drag_preview()

func _start_drag(btn: Button):
	var slot_type = btn.get_meta("slot_type", "")
	
	if current_mode == Mode.DEPLOY and slot_type == "armor":
		return
	
	var item_id = btn.get_meta("item_id", "")
	var talent_id = btn.get_meta("talent_id", "")
	
	if slot_type == "relic_slot":
		if item_id == "":
			return
	
	if slot_type in ["library_talent", "talent"] and talent_id == "":
		return
	
	if slot_type in ["library_weapon", "weapon"] and item_id == "":
		return
	
	if slot_type == "shop_item" and item_id == "":
		return
	
	# FORGE 空槽不可拖
	if slot_type == "forge_slot" and item_id == "":
		return
	
	_drag_source = btn
	_drag_meta = {
		"slot_type": slot_type,
		"unit_idx": btn.get_meta("unit_idx", -1),
		"slot_idx": btn.get_meta("slot_idx", -1),
		"item_id": item_id,
		"source_control": btn,
		"shop_index": btn.get_meta("shop_index", -1),
		"talent_id": talent_id,
		"relic_index": btn.get_meta("relic_index", -1),
		"item_price": btn.get_meta("item_price", 0),
		"forge_slot_index": btn.get_meta("forge_slot_index", -1),
	}
	
	if slot_type == "shop_item":
		var shop_idx = _drag_meta["shop_index"]
		if shop_idx != -1 and shop_manager:
			var items = shop_manager.get_shop_items()
			if shop_idx >= 0 and shop_idx < items.size() and items[shop_idx] != null:
				_drag_meta["item_data"] = items[shop_idx]["item_data"]
				_drag_meta["item_price"] = items[shop_idx]["price"]
	
	var btn_rect = btn.get_global_rect()
	var btn_center = btn_rect.position + btn_rect.size / 2
	_drag_grab_offset = get_global_mouse_position() - btn_center
	
	_begin_dragging()

func _begin_dragging():
	if _is_dragging:
		return
	_is_dragging = true
	var btn = _drag_source
	if not btn:
		return
	
	btn.set_meta("_original_disabled", btn.disabled)
	btn.set_meta("_original_modulate", btn.modulate)
	btn.set_meta("_original_text", btn.text)
	btn.set_meta("_original_custom_minimum_size", btn.custom_minimum_size)
	
	var current_size = btn.custom_minimum_size
	if current_size == Vector2.ZERO or current_size.y < 10:
		current_size = btn.size
	if current_size.y < 10:
		current_size.y = 16
	btn.custom_minimum_size = current_size
	
	btn.disabled = true
	btn.modulate = Color(0.3, 0.3, 0.3, 1.0)
	btn.text = "空"
	
	_drag_preview = _create_drag_preview(btn)
	
	var canvas = get_parent()
	if canvas and canvas is CanvasLayer:
		canvas.add_child(_drag_preview)
	else:
		add_child(_drag_preview)
	_update_drag_preview()
	
	_update_targets_visuals()

func _update_drag_preview():
	if not _drag_preview:
		return
	var mouse_pos = get_global_mouse_position()
	var preview_center = mouse_pos - _drag_grab_offset
	_drag_preview.position = preview_center - _drag_preview.size / 2
	_drag_preview.z_index = UIConst.DRAG_PREVIEW_Z_INDEX

func _end_drag():
	if not _is_dragging:
		return
	
	if _has_active_confirm_ui():
		if _drag_preview:
			_drag_preview.queue_free()
			_drag_preview = null
		_is_dragging = false
		_reset_targets_visuals()
		_drag_source = null
		_drag_meta = {}
		return
	
	var mouse_pos = get_global_mouse_position()
	var target = _get_target_from_position(mouse_pos)
	var valid = target and _is_valid_drop(_drag_meta, target)
	var drop_data = _drag_meta.duplicate()
	var source_type = drop_data.get("slot_type", "")
	
	if _drag_preview:
		_drag_preview.queue_free()
		_drag_preview = null
	_is_dragging = false
	_reset_targets_visuals()
	
	if valid:
		_execute_drop.call_deferred(drop_data, target)
		SoundManager.play_select_sound()
	else:
		if source_type == "talent" and target == null:
			_execute_talent_remove.call_deferred(drop_data)
			SoundManager.play_select_sound()
		else:
			SoundManager.play_cancel_sound()
			if is_instance_valid(_drag_source):
				var original_disabled = _drag_source.get_meta("_original_disabled", false)
				var original_modulate = _drag_source.get_meta("_original_modulate", Color.WHITE)
				var original_text = _drag_source.get_meta("_original_text", "")
				var original_min_size = _drag_source.get_meta("_original_custom_minimum_size", Vector2.ZERO)
				_drag_source.disabled = original_disabled
				_drag_source.modulate = original_modulate
				_drag_source.text = original_text
				_drag_source.custom_minimum_size = original_min_size
				_drag_source.remove_meta("_original_disabled")
				_drag_source.remove_meta("_original_modulate")
				_drag_source.remove_meta("_original_text")
				_drag_source.remove_meta("_original_custom_minimum_size")
			_schedule_build_ui()
	
	_drag_source = null
	_drag_meta = {}

func _process(_delta):
	if _is_dragging:
		_update_drag_preview()

# ============================================================
#  底部按钮（多模式分发）
# ============================================================
func _on_reset_shop_pressed():
	# FORGE 模式：清空插槽
	if current_mode == Mode.FORGE:
		_on_forge_clear_pressed()
		return
	
	# SHOP 模式：重置商店
	if current_mode != Mode.SHOP:
		return
	if not shop_manager:
		return
	
	var cost = shop_manager.get_reset_cost()
	
	if EconomyManager.get_temp_gold() < cost:
		Globals.show_confirm(self, "金币不足！需要 " + str(cost) + " 金币，当前 " + str(EconomyManager.get_temp_gold()), "确定", "", func(): pass, func(): pass, false)
		return
	
	var spent = shop_manager.reset_shop()
	if spent >= 0:
		SoundManager.play_select_sound()
		_update_gold_display()
		reset_btn.text = "重置商店 (" + str(shop_manager.get_reset_cost()) + "G)"
	else:
		Globals.show_confirm(self, "金币不足！需要 " + str(cost) + " 金币，当前 " + str(EconomyManager.get_temp_gold()), "确定", "", func(): pass, func(): pass, false)

func _on_confirm_pressed():
	# FORGE 模式：合成
	if current_mode == Mode.FORGE:
		_on_forge_craft_pressed()
		return
	
	# DEPLOY 模式：出发
	print("_on_confirm_pressed 被调用")
	GameState.party.clear()
	for local_unit in party:
		var data = UnitData.from_dict(local_unit.to_dict())
		GameState.party.append(data)
	
	if selected_units.size() > 0:
		var main_data = UnitDataManager.get_unit_data(selected_units[0])
		GameState.current_faction = main_data.get("faction", "王国")
	else:
		GameState.current_faction = "王国"
	
	GameState.interrupt_state = GameState.InterruptState.MAP
	GameState.reset_progress()
	LevelManager.start_game()
	
	var canvas_layer = get_parent()
	if canvas_layer:
		canvas_layer.queue_free()
	else:
		queue_free()

# ============================================================
#  数据拷贝
# ============================================================
func _copy_party_data():
	party.clear()
	for unit_name in selected_units:
		var existing = null
		for u in GameState.party:
			if u.unit_name == unit_name:
				existing = u
				break
		
		if existing:
			var data = UnitData.from_dict(existing.to_dict())
			party.append(data)
		else:
			var data = UnitDataManager.create_unit_data(unit_name)
			party.append(data)

func _clear_container(container: Node):
	if not container:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.free()

# ============================================================
#  特技兼容性
# ============================================================
func _check_talent_compatibility(data: Dictionary, target: Control) -> bool:
	var source_type = data.get("slot_type", "")
	var talent_id = data.get("talent_id", "")
	if talent_id == "":
		return false
	
	var target_unit_idx = target.get_meta("unit_idx", -1)
	var target_slot_idx = target.get_meta("slot_idx", -1)
	if target_unit_idx == -1:
		return false
	
	var target_unit = party[target_unit_idx]
	var unit_name = target_unit.unit_name
	
	if not TalentManager.is_talent_compatible_with_unit(talent_id, unit_name):
		return false
	
	if source_type == "library_talent":
		if _is_talent_already_equipped(talent_id, -1, -1):
			return false
	elif source_type == "talent":
		var src_unit_idx = data.get("unit_idx", -1)
		var src_slot_idx = data.get("slot_idx", -1)
		
		var tgt_inst = party[target_unit_idx].talent_slots[target_slot_idx]
		var tgt_talent_id = tgt_inst.talent_id if tgt_inst and tgt_inst.is_active else ""
		
		if tgt_talent_id == "":
			if _is_talent_already_equipped(talent_id, target_unit_idx, target_slot_idx):
				return false
		else:
			if _is_talent_already_equipped(tgt_talent_id, src_unit_idx, src_slot_idx):
				return false
			if _is_talent_already_equipped(talent_id, target_unit_idx, target_slot_idx):
				return false
	
	return true

func _is_talent_already_equipped(talent_id: String, exclude_unit_idx: int = -1, exclude_slot_idx: int = -1) -> bool:
	for i in range(party.size()):
		if i == exclude_unit_idx:
			continue
		var unit = party[i]
		for slot_idx in range(unit.talent_slots.size()):
			if slot_idx == exclude_slot_idx and i == exclude_unit_idx:
				continue
			var inst = unit.talent_slots[slot_idx]
			if inst and inst.is_active and inst.talent_id == talent_id:
				return true
	return false

func _get_unit_with_talent(talent_id: String) -> String:
	for i in range(party.size()):
		var unit = party[i]
		for inst in unit.talent_slots:
			if inst and inst.is_active and inst.talent_id == talent_id:
				return unit.display_name
	return ""

func _is_talent_equipped_anywhere(talent_id: String) -> bool:
	for i in range(party.size()):
		var unit = party[i]
		for inst in unit.talent_slots:
			if inst and inst.is_active and inst.talent_id == talent_id:
				return true
	return false

# ============================================================
#  拖拽预览
# ============================================================
func _create_drag_preview(btn: Button) -> Label:
	var preview = Label.new()
	
	preview.text = btn.get_meta("_original_text")
	
	var font_size = btn.get_theme_font_size("font_size")
	if font_size > 0:
		preview.add_theme_font_size_override("font_size", font_size)
	
	preview.autowrap_mode = btn.autowrap_mode
	preview.horizontal_alignment = btn.alignment
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	var font_color = btn.get_theme_color("font_color")
	if font_color:
		preview.add_theme_color_override("font_color", font_color)
	preview.modulate = btn.modulate
	
	var preview_size = btn.custom_minimum_size
	if preview_size == Vector2.ZERO or preview_size.y < 10:
		preview_size = btn.size
	if preview_size == Vector2.ZERO or preview_size.y < 10:
		preview_size = Vector2(50, 20)
	if preview_size.y < 14:
		preview_size.y = 14
	preview.size = preview_size
	
	var original_style = btn.get_theme_stylebox("normal")
	if original_style:
		var new_style = StyleBoxFlat.new()
		if original_style is StyleBoxFlat:
			var flat_style = original_style as StyleBoxFlat
			new_style.bg_color = flat_style.bg_color
			new_style.border_width_left = flat_style.border_width_left
			new_style.border_width_right = flat_style.border_width_right
			new_style.border_width_top = flat_style.border_width_top
			new_style.border_width_bottom = flat_style.border_width_bottom
			new_style.border_color = flat_style.border_color
		else:
			new_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
			new_style.border_width_left = 1
			new_style.border_width_right = 1
			new_style.border_width_top = 1
			new_style.border_width_bottom = 1
			new_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		preview.add_theme_stylebox_override("normal", new_style)
	else:
		var default_style = StyleBoxFlat.new()
		default_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
		default_style.border_width_left = 1
		default_style.border_width_right = 1
		default_style.border_width_top = 1
		default_style.border_width_bottom = 1
		default_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		preview.add_theme_stylebox_override("normal", default_style)
	
	preview.text_overrun_behavior = btn.text_overrun_behavior
	preview.clip_text = btn.clip_text
	
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview

# ============================================================
#  样式应用
# ============================================================
func _create_styled_button(font_size: int, min_size: Vector2) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn

func _create_label(text: String, font_size: int, center: bool = true) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if center:
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

# ============================================================
#  详情显示
# ============================================================
func _show_detail_in_zone(text: String):
	var detail_label = $VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/DetailLabel
	if detail_label:
		detail_label.text = text

func _clear_detail_zone():
	var detail_label = $VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/DetailLabel
	if detail_label:
		detail_label.text = "选中物品详情"

# ============================================================
#  移除特技
# ============================================================
func _execute_talent_remove(data: Dictionary):
	var unit_idx = data.get("unit_idx", -1)
	var slot_idx = data.get("slot_idx", -1)
	if unit_idx == -1 or slot_idx == -1:
		return
	party[unit_idx].talent_slots[slot_idx] = null
	_sync_all()
	_refresh_after_talent_change()

# ============================================================
#  遗物槽
# ============================================================
func _build_relic_slots():
	if not relic_container:
		return
	for child in relic_container.get_children():
		relic_container.remove_child(child)
		child.free()
	
	var relics = GameState.get_global_relics()
	
	for i in range(MAX_RELIC_SLOTS):
		var inst = relics[i] if i < relics.size() else null
		var btn = _create_relic_button(inst, i)
		relic_container.add_child(btn)

func _create_relic_button(inst: ItemInstance, slot_index: int) -> Button:
	var btn = _create_styled_button(Style.FONT_SMALL, Style.BTN_RELIC_SIZE)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	btn.set_meta("slot_type", "relic_slot")
	btn.set_meta("relic_index", slot_index)
	
	if inst != null:
		var data = RelicManager.get_relic_data(inst.item_id)
		if not data.is_empty():
			btn.text = data.get("name", "?")
			btn.set_meta("item_id", inst.item_id)
			btn.mouse_entered.connect(_on_relic_hover_entered.bind(inst.item_id))
			btn.mouse_exited.connect(_on_relic_hover_exited)
		else:
			btn.text = "?"
			btn.set_meta("item_id", "")
	else:
		btn.text = "空"
		btn.set_meta("item_id", "")
	
	return btn

# ============================================================
#  遗物操作
# ============================================================
func _swap_relics(data: Dictionary, target: Control):
	var src_idx = data.get("relic_index", -1)
	var tgt_idx = target.get_meta("relic_index", -1)
	if src_idx == -1 or tgt_idx == -1 or src_idx == tgt_idx:
		return
	
	var relics = GameState.global_relics
	if src_idx >= relics.size() or tgt_idx >= relics.size():
		return
	
	var temp = relics[src_idx]
	relics[src_idx] = relics[tgt_idx]
	relics[tgt_idx] = temp
	
	_sync_all()
	_refresh_after_relic_change()

func _discard_relic(data: Dictionary):
	var idx = data.get("relic_index", -1)
	if idx == -1:
		return
	
	var relics = GameState.global_relics
	if idx >= relics.size():
		return
	
	relics[idx] = null
	
	_sync_all()
	_refresh_after_relic_change()

func _refresh_after_relic_change():
	_schedule_build_ui()

func _on_relic_hover_entered(relic_id: String):
	var data = RelicManager.get_relic_data(relic_id)
	if not data.is_empty():
		_show_relic_detail_in_zone(data)

func _on_relic_hover_exited():
	_clear_detail_zone()

func _show_buy_failure_message(reason: String):
	var msg = ""
	match reason:
		"not_enough_gold":
			msg = "金币不足！当前 " + str(EconomyManager.get_temp_gold()) + "G"
		"empty_slot":
			msg = "该商品已被购买"
		"invalid_index":
			msg = "无效的商品位置"
		_:
			msg = "购买失败：" + reason
	Globals.show_confirm(self, msg, "确定", "", func(): pass, func(): pass, false)

# ============================================================
#  重建调度
# ============================================================
func _schedule_build_ui():
	if _build_ui_pending:
		return
	_build_ui_pending = true
	call_deferred("_do_build_ui")

func _do_build_ui():
	_build_ui_pending = false
	if _is_closing:
		return
	_build_ui()

func _has_active_confirm_ui() -> bool:
	for child in get_children():
		if child is CanvasLayer:
			var script = child.get_script()
			if script and script.resource_path.ends_with("ConfirmUI.gd"):
				return true
	return false

func _ensure_forge_result_label():
	if forge_result_label and is_instance_valid(forge_result_label):
		return

	forge_result_label = Label.new()
	forge_result_label.add_theme_font_size_override("font_size", Style.FONT_SMALL)
	forge_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_result_label.modulate = Color(0.5, 0.5, 0.5)
	forge_result_label.text = "合成结果：—"

	right_container.add_child(forge_result_label)
	# 移动到 ShopScroll 之后
	var scroll_idx = shop_scroll.get_index()
	right_container.move_child(forge_result_label, scroll_idx + 1)

func _update_forge_result_label():
	if not forge_result_label or not is_instance_valid(forge_result_label):
		return
	if _forge_matched_recipe == "":
		forge_result_label.text = "合成结果：—"
		forge_result_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		var out_data = ItemManager.get_item_data(_forge_matched_recipe)
		var out_name = out_data.name if out_data else _forge_matched_recipe
		forge_result_label.text = "合成结果：" + out_name
		if out_data:
			forge_result_label.modulate = UIConst.QUALITY_COLORS.get(out_data.quality, Color.WHITE)
		else:
			forge_result_label.modulate = Color.WHITE
