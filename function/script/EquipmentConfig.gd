extends Panel

enum Mode { DEPLOY, MAP, SHOP }

var current_mode: Mode = Mode.DEPLOY
var selected_units: Array[String] = []
var target_slot: int = -1
var party: Array = []

# ---- 预加载 ShopManager 脚本 ----
const ShopManagerScript = preload("res://function/script/ShopManager.gd")

# ---- 手动拖拽状态 ----
var _is_dragging: bool = false
var _drag_source: Button = null
var _drag_meta: Dictionary = {}
var _drag_preview: Control = null
var _drag_grab_offset: Vector2 = Vector2.ZERO

# ---- 目标控件高亮 ----
var _target_states: Dictionary = {}

# ---- 详情弹窗 ----
var _detail_popup = null

# ---- 标签栏（右侧） ----
var current_tab: String = "weapon"   # "weapon" 或 "talent"

var shop_manager = null

# ---- 右侧标签栏（场景中有） ----
@onready var mode_label = $VBoxContainer/TopBar/ModeLabel
@onready var gold_label = $VBoxContainer/GoldLabel
@onready var close_btn = $VBoxContainer/BottomHBox/CloseBtn          # ✅ 路径修正
@onready var confirm_btn = $VBoxContainer/BottomHBox/ConfirmBtn      # ✅ 路径修正
@onready var unit_container = $VBoxContainer/MainHBox/LeftVBox/UnitContainer
@onready var right_container = $VBoxContainer/MainHBox/RightContainer
@onready var shop_scroll: ScrollContainer = $VBoxContainer/MainHBox/RightContainer/ShopScroll
@onready var shop_container: GridContainer = $VBoxContainer/MainHBox/RightContainer/ShopScroll/ShopContainer
@onready var reset_btn = $VBoxContainer/MainHBox/RightContainer/ResetBtn
@onready var discard_zone = $VBoxContainer/MainHBox/RightContainer/DiscardZone
@onready var tab_bar = $VBoxContainer/MainHBox/RightContainer/TabBar
@onready var weapon_tab_btn = $VBoxContainer/MainHBox/RightContainer/TabBar/WeaponTabBtn
@onready var talent_tab_btn = $VBoxContainer/MainHBox/RightContainer/TabBar/TalentTabBtn

# ============================================================
#  初始化
# ============================================================

func _ready():
	# 连接标签按钮信号
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
	
	_copy_party_data()
	
	# ---- 创建详情弹窗（隐藏） ----
	if not _detail_popup:
		_detail_popup = load("res://content/scenes/ui/ItemDetailPopup.tscn").instantiate()
		var canvas = get_parent()
		if canvas and canvas is CanvasLayer:
			canvas.add_child(_detail_popup)
			_detail_popup.layer = 30
		else:
			add_child(_detail_popup)
		_detail_popup.visible = false
	
	_build_ui()

# ---- 商店信号处理 ----
func _on_shop_updated():
	_update_gold_display()
	call_deferred("_build_ui")

# ---- 按钮回调 ----
func _on_close_pressed():
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
	print("_build_ui 被调用")
	if not mode_label:
		print("错误：mode_label 为 null")
		return
	
	_update_gold_display()
	
	# 默认隐藏所有容器
	shop_container.visible = false
	discard_zone.visible = false
	reset_btn.visible = false
	tab_bar.visible = false
	right_container.visible = true
	
	var left_column = $VBoxContainer/MainHBox/LeftVBox
	if left_column:
		left_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	match current_mode:
		Mode.DEPLOY:
			mode_label.text = "装备配置 - 出战准备"
			close_btn.text = "返回"
			confirm_btn.visible = true
			confirm_btn.text = "出发"
			gold_label.visible = false
			confirm_btn.disabled = false
			
			tab_bar.visible = true
			weapon_tab_btn.visible = true
			talent_tab_btn.visible = true
			
			# ---- 保留当前标签页（不重置为 weapon） ----
			# 如果 current_tab 为空，默认设为 weapon
			if current_tab == "":
				current_tab = "weapon"
			_update_tab_style()
			
			# ---- 根据当前标签页填充内容 ----
			_clear_container(shop_container)
			if current_tab == "weapon":
				_build_weapon_grid(shop_container)
			else:
				_build_talent_grid(shop_container)
			shop_container.visible = true
			
			reset_btn.visible = false
			discard_zone.visible = false
			
			if left_column:
				left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		Mode.MAP:
			mode_label.text = "装备配置 - 队伍管理"
			close_btn.text = "返回"
			confirm_btn.visible = false
			gold_label.visible = false
			
			# ---- 只显示特技库（无标签切换） ----
			tab_bar.visible = false
			
			# ---- 清空并填充特技库 ----
			_clear_container(shop_container)
			_build_talent_grid(shop_container)
			shop_container.visible = true
			
			# ---- 显示丢弃区 ----
			discard_zone.visible = true
			reset_btn.visible = false
			
			if left_column:
				left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		Mode.SHOP:
			mode_label.text = "商店"
			close_btn.text = "关闭"
			confirm_btn.visible = false
			gold_label.visible = true
			
			# ---- 隐藏标签栏 ----
			tab_bar.visible = false
			
			# ---- 清空并填充商店 ----
			_clear_container(shop_container)
			_build_shop_items()
			shop_container.visible = true
			
			# ---- 显示商店相关 ----
			reset_btn.visible = true
			reset_btn.text = "重置商店 (" + str(shop_manager.get_reset_cost()) + "G)"
			discard_zone.visible = true
			
			if left_column:
				left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	close_btn.add_theme_font_size_override("font_size", 8)
	confirm_btn.add_theme_font_size_override("font_size", 8)
	reset_btn.add_theme_font_size_override("font_size", 8)
	
	# ---- 构建单位列 ----
	_clear_container(unit_container)
	_build_unit_columns()
	
	visible = true
	print("_build_ui 完成，面板可见：", visible)

func _update_gold_display():
	if gold_label:
		gold_label.text = "金币: " + str(EconomyManager.get_temp_gold())

# ============================================================
#  单位列构建（纯动态创建）
# ============================================================
func _build_unit_columns():
	for child in unit_container.get_children():
		child.queue_free()
	
	for i in range(party.size()):
		var unit = party[i]
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		unit_container.add_child(col)
		
		# ---- 单位名称 ----
		var name_label = Label.new()
		name_label.text = unit.display_name + "(" + UnitDataManager.get_unit_type_display_name(unit.unit_name) + ")"
		name_label.add_theme_font_size_override("font_size", 6)
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_label)
		
		# ---- 武器标题 ----
		var weapon_title = Label.new()
		weapon_title.text = "──────"
		weapon_title.add_theme_font_size_override("font_size", 6)
		weapon_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		weapon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(weapon_title)
		
		# ---- 武器按钮 ----
		var weapon_btn = _create_item_button(unit.weapon_slot, "weapon", i, -1)
		col.add_child(weapon_btn)
		
		# ---- 防具标题 ----
		var armor_title = Label.new()
		armor_title.text = "──────"
		armor_title.add_theme_font_size_override("font_size", 6)
		armor_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		armor_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(armor_title)
		
		# ---- 防具按钮 ----
		for slot_idx in range(unit.armor_slots.size()):
			var armor_btn = _create_item_button(unit.armor_slots[slot_idx], "armor", i, slot_idx)
			if current_mode == Mode.DEPLOY:
				armor_btn.disabled = true
			col.add_child(armor_btn)
		
		# ---- 特技分隔线 ----
		var talent_separator = Label.new()
		talent_separator.text = "──────"
		talent_separator.add_theme_font_size_override("font_size", 6)
		talent_separator.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		talent_separator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(talent_separator)
		
		# ---- 特技标题 ----
		var talent_title = Label.new()
		talent_title.text = "特技"
		talent_title.add_theme_font_size_override("font_size", 6)
		talent_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		talent_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(talent_title)
		
		# ---- 特技槽（每个单位1个） ----
		var talent_inst = unit.talent_slots[0] if unit.talent_slots.size() > 0 else null
		var talent_btn = _create_talent_button(talent_inst, i, 0)
		col.add_child(talent_btn)

# ============================================================
#  创建按钮
# ============================================================
func _create_item_button(inst: ItemInstance, slot_type: String, unit_idx: int, slot_idx: int) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 6)
	btn.custom_minimum_size = Vector2(30, 14)
	
	if inst:
		btn.text = _get_item_name(inst)
	else:
		btn.text = "空"
	
	btn.set_meta("slot_type", slot_type)
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	btn.set_meta("item_id", inst.item_id if inst else "")
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	if inst and inst.item_id != "":
		var item_id = inst.item_id
		btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_button_hover_exited)
	
	return btn

func _create_talent_button(inst: TalentInstance, unit_idx: int, slot_idx: int) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 5)
	btn.custom_minimum_size = Vector2(30, 22)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# ---- 多行支持 ----
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
#  武器库 / 特技库 / 商店（统一使用 ShopContainer）
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
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 6)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
		if entry != null:
			var item_data = entry["item_data"]
			var price = entry["price"]
			btn.text = item_data.name + "\n" + str(price) + "G"
			if item_data.icon:
				btn.icon = item_data.icon
			btn.set_meta("shop_index", i)
			btn.set_meta("slot_type", "shop_item")
			btn.set_meta("item_data", item_data)
			btn.set_meta("item_price", price)
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_data.id))
			btn.mouse_exited.connect(_on_button_hover_exited)
		else:
			btn.text = "空位"
			btn.disabled = true
		
		shop_container.add_child(btn)

func _build_weapon_grid(container: GridContainer):
	container.columns = 3
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "weapon":
			var btn = Button.new()
			btn.text = data.name
			btn.add_theme_font_size_override("font_size", 6)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.set_meta("slot_type", "library_weapon")
			btn.set_meta("item_id", item_id)
			btn.focus_mode = Control.FOCUS_NONE
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
			btn.mouse_exited.connect(_on_button_hover_exited)
			container.add_child(btn)

# ---- 构建特技库 ----
func _build_talent_grid(container: GridContainer):
	container.columns = 2
	var unlocked = Globals.get_unlocked_talents()
	if unlocked.is_empty():
		var label = Label.new()
		label.text = "暂无解锁特技"
		label.add_theme_font_size_override("font_size", 6)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(label)
		return
	
	for talent_id in unlocked:
		var data = TalentManager.get_talent_data(talent_id)
		if not data:
			continue
		var btn = Button.new()
		btn.text = _get_talent_display_name(data)
		btn.add_theme_font_size_override("font_size", 5)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(30, 22)
		btn.set_meta("talent_id", talent_id)
		btn.set_meta("slot_type", "library_talent")
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
		# ---- 多行支持（不设置垂直对齐，默认居中） ----
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		var rarity_color = _get_rarity_color(data.rarity)
		btn.add_theme_color_override("font_color", rarity_color)
		
		btn.mouse_entered.connect(_on_talent_hover_entered.bind(talent_id))
		btn.mouse_exited.connect(_on_talent_hover_exited)
		
		container.add_child(btn)

func _get_item_name(inst: ItemInstance) -> String:
	if not inst:
		return ""
	var data = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id

# ============================================================
#  详情弹窗
# ============================================================
func show_item_detail(item_id: String):
	if _detail_popup:
		_detail_popup.show_item(item_id)
		_detail_popup.visible = true

func hide_item_detail():
	if _detail_popup:
		_detail_popup.visible = false

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
	var detail_label = $VBoxContainer/MainHBox/DetailZone/DetailLabel
	if detail_label:
		var text = data.display_name + "\n" + data.description
		text += "\n稀有度: " + data.rarity
		text += "\n流派: " + data.school
		text += "\n积累: " + str(data.accumulation_threshold) + "回合"
		detail_label.text = text

func _hide_talent_detail():
	var detail_label = $VBoxContainer/MainHBox/DetailZone/DetailLabel
	if detail_label:
		detail_label.text = "选中物品详情"

# ---- 获取特技显示名称（含可装备单位） ----
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
#  标签切换（右侧）
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
#  目标控件高亮（拖拽时变灰）
# ============================================================
func _get_all_target_controls() -> Array[Control]:
	var targets: Array[Control] = []
	
	# 单位列中的所有按钮（武器、防具、特技）
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				targets.append(child)
	
	# DEPLOY 模式：右侧 ShopContainer 中的武器库/特技库按钮
	if current_mode == Mode.DEPLOY and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				targets.append(btn)
	
	# MAP 模式：右侧 ShopContainer 中的特技库按钮
	if current_mode == Mode.MAP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				targets.append(btn)
	
	# 丢弃区（DEPLOY 模式下特技不可丢弃，但仍可高亮指示）
	if discard_zone.visible:
		targets.append(discard_zone)
	
	return targets

func _update_targets_visuals():
	var targets = _get_all_target_controls()
	_target_states.clear()
	
	for target in targets:
		if not _target_states.has(target):
			_target_states[target] = target.modulate
		
		var is_valid = _is_valid_drop(_drag_meta, target)
		
		# 如果拖拽的是特技，且目标无效，显示红色提示
		if _drag_meta.has("talent_id") and _drag_meta["talent_id"] != "":
			if target.get_meta("slot_type", "") == "talent":
				if not is_valid:
					target.modulate = Color(1.0, 0.3, 0.3, 1.0)   # 红色表示不可用
				else:
					target.modulate = Color(0.3, 1.0, 0.3, 1.0)   # 绿色表示可用
		else:
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
	
	# 单位槽位
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button:
				if current_mode == Mode.DEPLOY and child.get_meta("slot_type", "") == "armor":
					continue
				var rect = child.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return child
	
	# DEPLOY 模式：右侧 ShopContainer
	if current_mode == Mode.DEPLOY and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return btn
	
	# MAP 模式：右侧 ShopContainer（特技库）
	if current_mode == Mode.MAP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return btn
	
	# SHOP 模式
	if current_mode == Mode.SHOP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled:
				var rect = btn.get_global_rect().grow(BUFFER)
				if rect.has_point(pos):
					return btn
	
	return null

func _get_target_from_position(global_pos: Vector2) -> Control:
	if discard_zone.visible and discard_zone.get_global_rect().has_point(global_pos):
		return discard_zone

	# 单位槽位
	for col in unit_container.get_children():
		for child in col.get_children():
			if child is Button and child.get_global_rect().has_point(global_pos):
				return child

	# DEPLOY 模式：右侧 ShopContainer
	if current_mode == Mode.DEPLOY and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled and btn.get_global_rect().has_point(global_pos):
				return btn

	# MAP 模式：右侧 ShopContainer（特技库）
	if current_mode == Mode.MAP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled and btn.get_global_rect().has_point(global_pos):
				return btn

	# SHOP 模式
	if current_mode == Mode.SHOP and shop_container.visible:
		for btn in shop_container.get_children():
			if btn is Button and not btn.disabled and btn.get_global_rect().has_point(global_pos):
				return btn

	return null

func _is_valid_drop(data: Dictionary, target: Control) -> bool:
	var source_type = data["slot_type"]
	var target_type = target.get_meta("slot_type", "")
	var discard = target == discard_zone

	# ===== 统一规则：特技不可丢弃 =====
	if discard and source_type in ["library_talent", "talent"]:
		return false

	if current_mode == Mode.DEPLOY:
		if discard:
			return false
		# ---- 武器相关 ----
		if source_type == "library_weapon":
			return target_type == "weapon"
		if source_type == "weapon" and target_type == "weapon":
			return true
		# ---- 特技相关 ----
		if source_type == "library_talent" and target_type == "talent":
			return _check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent":
			return _check_talent_compatibility(data, target)
		return false

	if current_mode == Mode.MAP:
		if discard:
			if source_type in ["library_talent", "talent"]:
				return false   # 特技不可丢弃
			if source_type == "weapon":
				return false
			return true
		
		# ---- 武器相关 ----
		if source_type == "library_weapon":
			return target_type == "weapon"
		if source_type == "weapon" and target_type == "weapon":
			return true
		
		# ---- 防具相关 ----
		if source_type == "armor" and target_type == "armor":
			return true
		
		# ---- 特技相关（必须检查兼容性） ----
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
		else:
			if source_type == "shop_item":
				var item_data = data.get("item_data")
				if not item_data:
					return false
				if item_data.type == "weapon":
					return target_type == "weapon"
				elif item_data.type == "armor":
					return target_type == "armor"
				return false
			else:
				if source_type == "weapon" and target_type == "weapon":
					return true
				if source_type == "armor" and target_type == "armor":
					return true
				return false

	return false

# ============================================================
#  拖拽执行
# ============================================================
func _execute_drop(data: Dictionary, target: Control):
	var discard = target == discard_zone
	var source_type = data["slot_type"]
	var target_type = target.get_meta("slot_type", "")

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
	call_deferred("_build_ui")

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
		
		# ---- 检查唯一性 ----
		if _is_talent_already_equipped(talent_id, unit_idx, slot_idx):
			var equipped_unit = _get_unit_with_talent(talent_id)
			Globals.show_confirm(
				self,
				"特技已被 %s 装备，不可重复装备" % equipped_unit,
				"确定",
				"",
				func(): pass,
				func(): pass,
				false
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
		
		var src_talent_id = party[src_unit].talent_slots[src_slot].talent_id if party[src_unit].talent_slots[src_slot] else ""
		
		var tgt_inst = party[tgt_unit].talent_slots[tgt_slot]
		if tgt_inst and tgt_inst.is_active and tgt_inst.talent_id == src_talent_id:
			# 只声明一次 temp_talent
			var temp_talent = party[src_unit].talent_slots[src_slot]
			party[src_unit].talent_slots[src_slot] = party[tgt_unit].talent_slots[tgt_slot]
			party[tgt_unit].talent_slots[tgt_slot] = temp_talent
			_sync_all()
			_refresh_after_talent_change()
			return
		
		if src_talent_id != "":
			if _is_talent_already_equipped(src_talent_id, tgt_unit, tgt_slot):
				var equipped_unit = _get_unit_with_talent(src_talent_id)
				Globals.show_confirm(
					self,
					"特技已被 %s 装备，不可重复装备" % equipped_unit,
					"确定",
					"",
					func(): pass,
					func(): pass,
					false
				)
				return
		
		# 这里只使用一个 temp_talent，不要重复声明
		var temp_talent = party[src_unit].talent_slots[src_slot]
		party[src_unit].talent_slots[src_slot] = party[tgt_unit].talent_slots[tgt_slot]
		party[tgt_unit].talent_slots[tgt_slot] = temp_talent
		_sync_all()
		_refresh_after_talent_change()
		return

# ---- 新增：刷新特技变更后的界面 ----
func _refresh_after_talent_change():
	# 只刷新单位列（更新特技槽显示）
	_clear_container(unit_container)
	_build_unit_columns()
	
	# 刷新当前标签页内容（武器库或特技库）
	if current_mode == Mode.DEPLOY:
		_clear_container(shop_container)
		if current_tab == "weapon":
			_build_weapon_grid(shop_container)
		else:
			_build_talent_grid(shop_container)
		shop_container.visible = true
	elif current_mode == Mode.MAP:
		_clear_container(shop_container)
		_build_talent_grid(shop_container)
		shop_container.visible = true

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
	if not shop_manager:
		return
	
	var shop_index = data.get("shop_index", -1)
	if shop_index == -1:
		return
	
	var item_data = data.get("item_data")
	if not item_data:
		return
	
	var target_unit_idx = target.get_meta("unit_idx", -1)
	var target_slot_idx = target.get_meta("slot_idx", -1)
	
	var result = shop_manager.buy_shop_item(shop_index)
	if not result["success"]:
		print("购买失败: ", result.get("reason", "unknown"))
		return
	
	var inst = ItemInstance.new()
	inst.item_id = item_data.id
	inst.count = 1
	
	if item_data.type == "weapon":
		if target_unit_idx != -1:
			party[target_unit_idx].weapon_slot = inst
			print("购买了武器并装备到单位: ", item_data.name)
		else:
			Globals.unlock_item(item_data.id)
			print("购买了武器（未装备）: ", item_data.name)
			
	elif item_data.type == "armor":
		if target_unit_idx != -1 and target_slot_idx != -1:
			party[target_unit_idx].armor_slots[target_slot_idx] = inst
			print("购买了防具并装备到单位: ", item_data.name)
		else:
			var equipped = false
			if target_unit_idx != -1:
				for i in range(party[target_unit_idx].armor_slots.size()):
					if party[target_unit_idx].armor_slots[i] == null:
						party[target_unit_idx].armor_slots[i] = inst
						equipped = true
						break
				if not equipped:
					party[target_unit_idx].armor_slots[party[target_unit_idx].armor_slots.size() - 1] = inst
					print("防具槽已满，替换最后一个槽位")
			else:
				Globals.unlock_item(item_data.id)
				print("购买了防具（未装备）: ", item_data.name)
	
	_sync_all()
	_update_gold_display()
	call_deferred("_build_ui")

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
	call_deferred("_build_ui")

func _swap_weapons(data: Dictionary, target: Control):
	var src_unit = data["unit_idx"]
	var tgt_unit = target.get_meta("unit_idx", -1)
	if tgt_unit == -1:
		return
	var temp = party[src_unit].weapon_slot
	party[src_unit].weapon_slot = party[tgt_unit].weapon_slot
	party[tgt_unit].weapon_slot = temp
	_sync_all()
	call_deferred("_build_ui")

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
	call_deferred("_build_ui")

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
			while GameState.party[i].armor_slots.size() < GameState.party[i].max_armor_slots:
				GameState.party[i].armor_slots.append(null)
			while GameState.party[i].talent_slots.size() < 1:
				GameState.party[i].talent_slots.append(null)
	SaveManager.auto_save()

# ============================================================
#  手动拖拽
# ============================================================
func _input(event: InputEvent):
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
	
	# 特技库和特技槽使用 talent_id 作为标识
	if slot_type in ["library_talent", "talent"] and talent_id == "":
		return
	
	# 武器库和武器槽使用 item_id
	if slot_type in ["library_weapon", "weapon"] and item_id == "":
		return
	
	# 商店商品
	if slot_type == "shop_item" and item_id == "":
		return
	
	_drag_source = btn
	_drag_meta = {
		"slot_type": slot_type,
		"unit_idx": btn.get_meta("unit_idx", -1),
		"slot_idx": btn.get_meta("slot_idx", -1),
		"item_id": item_id,
		"source_control": btn,
		"shop_index": btn.get_meta("shop_index", -1),
		"talent_id": talent_id
	}
	
	if slot_type == "shop_item":
		_drag_meta["item_data"] = btn.get_meta("item_data", null)
	
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
		print("_begin_dragging: 源按钮为空")
		return
	
	btn.set_meta("_original_disabled", btn.disabled)
	btn.set_meta("_original_modulate", btn.modulate)
	btn.set_meta("_original_text", btn.text)
	btn.set_meta("_original_custom_minimum_size", btn.custom_minimum_size)
	
	var current_size = btn.get_rect().size
	if current_size.y < 10:
		current_size.y = 16
	btn.custom_minimum_size = current_size
	
	btn.disabled = true
	btn.modulate = Color(0.3, 0.3, 0.3, 1.0)
	btn.text = "空"
	
	var source_size = btn.size
	var preview = Label.new()
	preview.text = btn.get_meta("_original_text")
	preview.add_theme_font_size_override("font_size", 6)
	preview.modulate = Color.WHITE
	preview.add_theme_color_override("font_color", btn.get_theme_color("font_color"))
	preview.add_theme_stylebox_override("normal", StyleBoxFlat.new())
	var style = preview.get_theme_stylebox("normal") as StyleBoxFlat
	if style:
		style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.5, 0.5, 0.5, 1.0)
	preview.size = source_size
	preview.horizontal_alignment = btn.alignment
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var canvas = get_parent()
	if canvas and canvas is CanvasLayer:
		canvas.add_child(preview)
	else:
		add_child(preview)
	_drag_preview = preview
	_update_drag_preview()
	
	_update_targets_visuals()

func _update_drag_preview():
	if not _drag_preview:
		return
	var mouse_pos = get_global_mouse_position()
	var preview_center = mouse_pos - _drag_grab_offset
	_drag_preview.position = preview_center - _drag_preview.size / 2
	_drag_preview.z_index = 100

func _end_drag():
	if _is_dragging:
		var mouse_pos = get_global_mouse_position()
		var target = _get_target_from_position(mouse_pos)
		
		var valid = target and _is_valid_drop(_drag_meta, target)
		if valid:
			_execute_drop(_drag_meta, target)
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
			call_deferred("_build_ui")
		
		if _drag_preview:
			_drag_preview.queue_free()
			_drag_preview = null
		_is_dragging = false
		_reset_targets_visuals()
		
	_drag_source = null
	_drag_meta = {}

func _process(_delta):
	if _is_dragging:
		_update_drag_preview()

func _on_reset_shop_pressed():
	print("_on_reset_shop_pressed 被调用")
	
	if not shop_manager:
		return
	
	var cost = shop_manager.get_reset_cost()
	
	if EconomyManager.get_temp_gold() < cost:
		Globals.show_confirm(
			self,
			"金币不足！需要 " + str(cost) + " 金币，当前 " + str(EconomyManager.get_temp_gold()),
			"确定",
			"",
			func(): pass,
			func(): pass,
			false
		)
		return
	
	var spent = shop_manager.reset_shop()
	if spent >= 0:
		_update_gold_display()
		reset_btn.text = "重置商店 (" + str(shop_manager.get_reset_cost()) + "G)"
		_build_shop_items()
	else:
		Globals.show_confirm(
			self,
			"金币不足！需要 " + str(cost) + " 金币，当前 " + str(EconomyManager.get_temp_gold()),
			"确定",
			"",
			func(): pass,
			func(): pass,
			false
		)

func _copy_party_data():
	party.clear()
	for unit_name in selected_units:
		var existing = null
		for u in GameState.party:
			if u.unit_name == unit_name:
				existing = u
				break
		
		if existing:
			var data = UnitData.new()
			data.unit_name = existing.unit_name
			data.display_name = existing.display_name
			data.faction = existing.faction
			data.team_id = existing.team_id
			data.max_hp = existing.max_hp
			data.hit_points = existing.hit_points
			data.strength = existing.strength
			data.dexterity = existing.dexterity
			data.intelligence = existing.intelligence
			data.faith = existing.faith
			data.arcane = existing.arcane
			data.move_range = existing.move_range
			data.ignore_terrain_cost = existing.ignore_terrain_cost
			data.experience = existing.experience
			data.level = existing.level
			
			if existing.weapon_slot:
				var inst = ItemInstance.new()
				inst.item_id = existing.weapon_slot.item_id
				inst.count = existing.weapon_slot.count
				data.weapon_slot = inst
			else:
				data.weapon_slot = null
			
			data.armor_slots.clear()
			for slot_inst in existing.armor_slots:
				if slot_inst:
					var new_inst = ItemInstance.new()
					new_inst.item_id = slot_inst.item_id
					new_inst.count = slot_inst.count
					data.armor_slots.append(new_inst)
				else:
					data.armor_slots.append(null)
			data.max_armor_slots = existing.max_armor_slots
			
			data.talent_slots.clear()
			for slot_inst in existing.talent_slots:
				if slot_inst:
					var new_inst = TalentInstance.new()
					new_inst.talent_id = slot_inst.talent_id
					new_inst.current_stack = slot_inst.current_stack
					new_inst.is_ready = slot_inst.is_ready
					new_inst.is_active = slot_inst.is_active
					data.talent_slots.append(new_inst)
				else:
					data.talent_slots.append(null)
			while data.talent_slots.size() < 1:
				data.talent_slots.append(null)
			
			while data.armor_slots.size() < data.max_armor_slots:
				data.armor_slots.append(null)
			
			party.append(data)
		else:
			var data = UnitDataManager.create_unit_data(unit_name)
			party.append(data)

func _on_confirm_pressed():
	print("_on_confirm_pressed 被调用")
	GameState.party.clear()
	for local_unit in party:
		var data = UnitData.new()
		data.unit_name = local_unit.unit_name
		data.display_name = local_unit.display_name
		data.faction = local_unit.faction
		data.team_id = 0
		data.max_hp = local_unit.max_hp
		data.hit_points = local_unit.hit_points
		data.strength = local_unit.strength
		data.dexterity = local_unit.dexterity
		data.intelligence = local_unit.intelligence
		data.faith = local_unit.faith
		data.arcane = local_unit.arcane
		data.move_range = local_unit.move_range
		data.ignore_terrain_cost = local_unit.ignore_terrain_cost
		data.experience = local_unit.experience
		data.level = local_unit.level
		
		if local_unit.weapon_slot:
			var inst = ItemInstance.new()
			inst.item_id = local_unit.weapon_slot.item_id
			inst.count = local_unit.weapon_slot.count
			data.weapon_slot = inst
		else:
			data.weapon_slot = null
		data.armor_slots.clear()
		for slot_inst in local_unit.armor_slots:
			if slot_inst:
				var inst = ItemInstance.new()
				inst.item_id = slot_inst.item_id
				inst.count = slot_inst.count
				data.armor_slots.append(inst)
			else:
				data.armor_slots.append(null)
		data.max_armor_slots = local_unit.max_armor_slots
		while data.armor_slots.size() < data.max_armor_slots:
			data.armor_slots.append(null)
		
		data.talent_slots.clear()
		for slot_inst in local_unit.talent_slots:
			if slot_inst:
				var inst = TalentInstance.new()
				inst.talent_id = slot_inst.talent_id
				inst.current_stack = slot_inst.current_stack
				inst.is_ready = slot_inst.is_ready
				inst.is_active = slot_inst.is_active
				data.talent_slots.append(inst)
			else:
				data.talent_slots.append(null)
		while data.talent_slots.size() < 1:
			data.talent_slots.append(null)
		
		GameState.party.append(data)
	
	if selected_units.size() > 0:
		var main_data = UnitDataManager.get_unit_data(selected_units[0])
		GameState.current_faction = main_data.get("faction", "王国")
	else:
		GameState.current_faction = "王国"
	
	GameState.interrupt_state = 2
	GameState.reset_progress()
	SaveManager.save_game(target_slot, false)
	LevelManager.start_game()
	
	var canvas_layer = get_parent()
	if canvas_layer:
		canvas_layer.queue_free()
	else:
		queue_free()

func _clear_container(container: Node):
	for child in container.get_children():
		child.queue_free()

func _check_talent_compatibility(data: Dictionary, target: Control) -> bool:
	var talent_id = data.get("talent_id", "")
	if talent_id == "":
		return false
	
	var target_unit_idx = target.get_meta("unit_idx", -1)
	if target_unit_idx == -1:
		return false
	
	var target_unit = party[target_unit_idx]
	var unit_name = target_unit.unit_name
	
	# 1. 检查单位类型兼容性
	if not TalentManager.is_talent_compatible_with_unit(talent_id, unit_name):
		return false
	
	# 2. 检查词条唯一性（是否已被其他单位装备）
	var target_slot_idx = target.get_meta("slot_idx", -1)
	if _is_talent_already_equipped(talent_id, target_unit_idx, target_slot_idx):
		var equipped_unit = _get_unit_with_talent(talent_id)
		print("词条已被 %s 装备，不可重复装备" % equipped_unit)
		return false
	
	return true

# ---- 检查词条是否已被其他单位装备（除了当前槽位） ----
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

# ---- 获取装备了某词条的单位名称（用于提示） ----
func _get_unit_with_talent(talent_id: String) -> String:
	for i in range(party.size()):
		var unit = party[i]
		for inst in unit.talent_slots:
			if inst and inst.is_active and inst.talent_id == talent_id:
				return unit.display_name
	return ""
