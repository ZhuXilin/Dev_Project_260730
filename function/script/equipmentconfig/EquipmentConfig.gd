extends Panel

enum Mode { DEPLOY, MAP, FORGE, ARENA_REST, MAP_SHOP_REST, ARMOR_ROLL }

## ★ v6.41：战后防具落位模式——点防具槽回传单位 index，供 ArmorRollUI 执行落位
signal armor_slot_picked(unit_idx: int, slot_idx: int)
## ★ v6.44：落位模式下请求放弃待落袋防具
signal armor_discard_requested()

const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")

## 连通方向箭头（v5.4）：矢量绘制的等腰直角三角形，箭头尖 90°、两腰等长。
## 尖端落在 20x20 图标色块的边沿中点（正交）或四角（斜向），其余部分完全在色块内部。
## v5.4：半宽由 12 改 10，与按钮/色块/图标统一的 20x20 基准一致，
##       解决商店格子里箭尖贴着看不见的 24x24 边、视觉上偏离图标的问题。
class LinkArrow extends Control:
	var angle_deg : float = 0.0                       # Godot 坐标：0=右, 90=下, -90=上
	var fill_color : Color = Color(1.0, 0.88, 0.35)   # 与连通黄框统一的黄色
	var arm : float = 4.0                             # 两腰在轴向/横向的投影（决定三角形大小）

	func _draw() -> void:
		var c := size * 0.5                           # 图标色块中心 (10,10)
		var rad := deg_to_rad(angle_deg)
		var dir := Vector2(cos(rad), sin(rad))
		var perp := Vector2(-dir.y, dir.x)
		var half : float = minf(size.x, size.y) * 0.5  # 与自身控件等宽（20x20 → 10）
		# 射线与正方形边界求交：正交命中边中点(t=10)，45° 命中四角(t=10√2)
		var t : float = half / maxf(absf(dir.x), absf(dir.y))
		var tip := c + dir * t                        # 箭尖贴图标色块边沿/角
		var base := c + dir * (t - arm)               # 底边中点内缩 arm
		var p1 := base + perp * arm                   # 两腰等长 + 顶角 90°
		var p2 := base - perp * arm
		draw_colored_polygon(PackedVector2Array([tip, p1, p2]), fill_color)

var current_mode: Mode = Mode.DEPLOY
var selected_units: Array = []
var target_slot: int = -1
var party: Array = []
var _is_building_ui: bool = false
var _build_ui_pending: bool = false
var _is_closing: bool = false
var _context : EquipContext = null

const MAX_PASSIVE_SLOTS : int = 6  # ★ 与 PartyState 一致：团队遗物6槽

var current_tab: String = "talent"  # ★ v5.1：武器库已移除，默认特技库
var shop_manager = null

var _forge : EquipmentConfigForge = null
## ★ v6.59：魂栈遗物商店
var _relic_shop = null
var _drag : EquipmentConfigDrag = null
var _detail : EquipmentConfigDetail = null
var _shop : EquipmentConfigShop = null
var _talent : EquipmentConfigTalent = null

var _upgrade_shop_btn : Button = null
var _aura_tab_btn : Button = null
var _forge_enter_done : bool = false
## ★ v6.43：待落袋防具 {item_id,quality,school,name,mechanic}，落位模式下显示并高亮槽位
var _pending_armor : Dictionary = {}

const ShopManagerScript = preload(Config.PATHS.SHOP_MANAGER_SCRIPT)
const DETAIL_ZONE_PATH : String = "VBoxContainer/MainHBox/LeftInfoColumn/DetailZone"
const DIRECTION_REROLL_COST : int = 120

# ★★★ v5.0 连通组悬停高亮：槽位原始样式备份 ★★★
var _armor_btn_default_style : Dictionary = {}
## v6.5：单位列防具区固定行数，技能图标始终落在同一水平线（红线下方）
var _unit_column_armor_rows : int = 0
## v6.62d：团队遗物槽对齐布局稳定后才执行，且只连接一次尺寸变化监听
var _relic_align_connected : bool = false

@onready var mode_label = get_node_or_null("VBoxContainer/TopBar/ModeLabel")
@onready var gold_label = get_node_or_null("VBoxContainer/GoldLabel")
@onready var close_btn = get_node_or_null("VBoxContainer/BottomHBox/CloseBtn")
@onready var confirm_btn = get_node_or_null("VBoxContainer/BottomHBox/ConfirmBtn")
@onready var unit_container = get_node_or_null("VBoxContainer/MainHBox/LeftVBox/UnitContainer")

var shop_container: Control = null
var shop_scroll: ScrollContainer = null

@onready var right_container = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer")
@onready var reset_btn = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ResetBtn")
@onready var discard_zone = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/DiscardZone")
@onready var tab_bar = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar")
@onready var weapon_tab_btn = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar/WeaponTabBtn")
@onready var talent_tab_btn = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar/TalentTabBtn")
# ★ 团队遗物与单位/防具/技能共享 LeftVBox；老虎机遗物与商店共享 RightContainer
@onready var relic_section: VBoxContainer = get_node_or_null("VBoxContainer/MainHBox/LeftVBox/RelicSection")
@onready var relic_container: Control = get_node_or_null("VBoxContainer/MainHBox/LeftVBox/RelicSection/RelicContainer")
@onready var roll_relic_section: VBoxContainer = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/RollRelicSection")
@onready var roll_relic_container: HBoxContainer = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/RollRelicSection/RollRelicContainer")
@onready var sacrifice_tab_btn : Button = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar/SacrificeTabBtn")
@onready var furnace_tab_btn : Button = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar/FurnaceTabBtn")

var _pending_section : VBoxContainer = null
var _pending_container : GridContainer = null

var _connectivity_groups : Array = []
var _connected_cells : Dictionary = {}
var _shop_direction_cache : Dictionary = {}

# ★ v5.1：队伍标签统计槽（Build 引导）
var _tag_stats_container : HBoxContainer = null


func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var custom_theme := Theme.new()
	custom_theme.set_font_size("font_size", "TooltipLabel", 6)
	custom_theme.set_font_size("font_size", "TooltipPanel", 6)
	
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	tip_sb.content_margin_left = 4
	tip_sb.content_margin_right = 4
	tip_sb.content_margin_top = 2
	tip_sb.content_margin_bottom = 2
	custom_theme.set_stylebox("panel", "TooltipPanel", tip_sb)
	theme = custom_theme
	
	shop_container = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ShopScroll/ShopContainer")
	shop_scroll = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ShopScroll")
	
	if shop_container is GridContainer:
		var old_sc = shop_container
		var new_flow = HFlowContainer.new()
		new_flow.name = old_sc.name
		# 网格逐行左对齐：FlowContainer 的 ALIGNMENT_CENTER 是「每一行各自居中」，
		# 最后一行不满时会整体偏移（第二排不从第一格开始）。改用 BEGIN 让所有行
		# 都从最左第一格开始；满行时与原来视觉位置一致，不影响商店/熔炉等页。
		new_flow.alignment = FlowContainer.ALIGNMENT_BEGIN
		new_flow.add_theme_constant_override("h_separation", Style.ITEM_GRID_GAP)
		new_flow.add_theme_constant_override("v_separation", Style.ITEM_GRID_GAP)
		new_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		old_sc.get_parent().add_child(new_flow)
		old_sc.get_parent().remove_child(old_sc)
		old_sc.queue_free()
		shop_container = new_flow
	
	_forge = EquipmentConfigForge.new(self)
	_drag = EquipmentConfigDrag.new(self)
	_detail = EquipmentConfigDetail.new(self)
	_shop = EquipmentConfigShop.new(self)
	_talent = EquipmentConfigTalent.new(self)
	if weapon_tab_btn:
		weapon_tab_btn.pressed.connect(_on_weapon_tab_pressed)
	if talent_tab_btn:
		talent_tab_btn.pressed.connect(_on_talent_tab_pressed)
	if sacrifice_tab_btn:
		sacrifice_tab_btn.visible = false
	_ensure_aura_tab_btn()

	var detail_label : Label = get_node_or_null(DETAIL_ZONE_PATH + "/DetailLabel")
	if detail_label:
		detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_connectivity_groups.clear()
	_connected_cells.clear()
	_armor_btn_default_style.clear()


func _ensure_aura_tab_btn():
	pass


func _on_aura_tab_pressed():
	_switch_tab("aura")


func is_forge_mode() -> bool:
	return current_mode == Mode.FORGE

func is_shop_rest_mode() -> bool:
	return current_mode == Mode.ARENA_REST or current_mode == Mode.MAP_SHOP_REST

func _is_shop_rest_mode() -> bool:
	return is_shop_rest_mode()


func _on_weapon_tab_pressed():
	# ★ v5.1：武器库已移除，此按钮在各模式统一作为「商店」入口
	_switch_tab("arena_shop")


func _on_talent_tab_pressed():
	if is_shop_rest_mode(): _switch_tab("arena_forge")
	elif current_mode == Mode.FORGE: _switch_tab("arena_forge")
	else: _switch_tab("talent")


func _on_sacrifice_tab_pressed(): _switch_tab("sacrifice")


func init(units: Array, slot: int, mode: int, context: EquipContext = null):
	var canvas_layer : Node = get_parent()
	if canvas_layer is CanvasLayer:
		if mode == Mode.ARMOR_ROLL:
			(canvas_layer as CanvasLayer).layer = 32   # 盖住 ArmorRollUI(30)
		elif context != null and context.get_context_id() == "arena":
			(canvas_layer as CanvasLayer).layer = 30
		else:
			(canvas_layer as CanvasLayer).layer = 20

	selected_units = units
	target_slot = slot
	current_mode = mode as Mode
	_context = context if context else MainGameEquipContext.new()

	if current_mode == Mode.FORGE or is_shop_rest_mode():
		GameState.refresh_aura_candidates()

	if is_shop_rest_mode() or mode == Mode.FORGE:
		if not shop_manager:
			shop_manager = ShopManagerScript.new()
			add_child(shop_manager)
			shop_manager.shop_updated.connect(_on_shop_updated)
		shop_manager.set_context(_context)
		shop_manager.generate_shop_items()
		shop_manager.reset_count = 0

	if mode == Mode.FORGE or is_shop_rest_mode():
		_forge.init_slots()

	# ★ v6.59：魂栈改为遗物商店
	if mode == Mode.FORGE:
		var RelicShopScript = preload("res://function/script/equipmentconfig/RelicShop.gd")
		_relic_shop = RelicShopScript.new(self)
		_relic_shop.generate()

	if is_shop_rest_mode():
		current_tab = "arena_shop"

	if current_mode == Mode.FORGE or current_mode == Mode.MAP_SHOP_REST:
		_forge_enter_done = false
	else:
		_forge_enter_done = true

	_copy_party_data()
	_build_ui()

	if current_mode == Mode.FORGE:
		AnalyticsLogger.begin_forge_session()


func _on_shop_updated():
	_update_gold_display()
	var is_shop_view : bool = (
		current_tab == "arena_shop" and (
			current_mode == Mode.ARENA_REST
			or current_mode == Mode.MAP_SHOP_REST
			or current_mode == Mode.FORGE
		)
	)
	if is_shop_view and shop_container and shop_container.visible:
		_build_shop_items()
	else:
		_schedule_build_ui()


# ============================================================
#  v5.0：只强制检查熔铸奖励（pending_sacrifice_rewards）
#  合成产物 + 阵亡回收的防具（pending_forge_rewards）允许带着离开，
#  玩家可在下次进入 FORGE / MAP_SHOP_REST 时再处理。
# ============================================================
func _on_close_pressed():
	if GameState.has_pending_sacrifice_rewards():
		var total : int = GameState.pending_sacrifice_rewards.size()
		Globals.show_confirm(
			self,
			"还有 %d 件熔铸奖励待领取。\n请先把它们装备到单位防具槽后再离开。" % total,
			"好的", "",
			func(): pass,
			func(): pass,
			false
		)
		return
	_do_close_normal()


func _do_close_with_discard():
	GameState.clear_all_pending_rewards()
	_do_close_normal()


func _do_close_normal():
	if is_shop_rest_mode() and current_tab == "arena_forge":
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return
		if current_mode == Mode.ARENA_REST:
			_switch_tab("arena_shop")
			return

	if current_mode == Mode.FORGE and _forge.has_pending():
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			Globals.show_confirm(self, "有 %d 件防具无法归还，请先腾出空间" % unresolved,
				"确定", "", func(): pass, func(): pass, false)
			return

	# ★ v6.41：落位模式只读，关闭时不回写 party、不触发 context 生命周期
	if current_mode == Mode.ARMOR_ROLL:
		_is_closing = true
		var cl : Node = get_parent()
		if cl: cl.queue_free()
		else: queue_free()
		return

	_sync_all()
	_context.mark_cancelled()
	_is_closing = true
	if current_mode == Mode.FORGE:
		AnalyticsLogger.finish_forge_session()
	if shop_manager:
		if shop_manager.shop_updated.is_connected(_on_shop_updated):
			shop_manager.shop_updated.disconnect(_on_shop_updated)
		shop_manager.queue_free()
		shop_manager = null
	_context.on_close()
	var canvas_layer : Node = get_parent()
	if canvas_layer: canvas_layer.queue_free()
	else: queue_free()


# ============================================================
#  v5.0：只检查 pending_sacrifice_rewards
# ============================================================
func _check_pending_before_leave() -> bool:
	if GameState.has_pending_sacrifice_rewards():
		_show_detail_in_zone("请先领取熔铸奖励（%d 件）" % GameState.pending_sacrifice_rewards.size())
		return false
	return true


func _build_ui():
	if _is_closing: return
	if _is_building_ui: return
	_is_building_ui = true
	_build_ui_inner()
	_is_building_ui = false
	if current_mode == Mode.ARMOR_ROLL:
		_apply_armor_pick_readonly()
	if current_mode == Mode.FORGE or current_mode == Mode.MAP_SHOP_REST:
		_setup_forge_narrative_ui()
		

func _refresh_connectivity(_silent: bool = false):
	_connectivity_groups.clear()
	_connected_cells.clear()

	if party.is_empty():
		return

	var slots : Array = []
	for i in range(party.size()):
		slots.append(party[i].armor_slots)

	_connectivity_groups = ConnectedGroupCalculator.compute_groups(slots)

	for gi in range(_connectivity_groups.size()):
		var g = _connectivity_groups[gi]
		for c in g.cells:
			_connected_cells["%d_%d" % [c.unit_index, c.row]] = gi

	# v6.5：连通提示已移除

# ★★★ v5.1 修复：连线黄框改画在按钮子节点最上层 ★★★
# 防具图标已改为全尺寸 TextureRect 子节点（见 _draw_build_tag_backdrop），
# 它会盖住按钮自身 stylebox 的边框，所以原来的 normal/hover stylebox 边框不可见。
# 这里把连线框做成独立 Panel 子节点并最后加入，保证绘制在图标与色块之上。
const LINK_FRAME_NODE_NAME : String = "__link_frame"

func _set_slot_link_frame(_btn: Button, _unit_idx: int, _slot_idx: int, _highlight: bool = false):
	# v6.5：连通黄框/箭头功能已移除，不再绘制连线提示
	pass


func _get_connectivity_style(unit_idx: int, slot_idx: int) -> StyleBox:
	var key : String = "%d_%d" % [unit_idx, slot_idx]
	if not _connected_cells.has(key):
		return null
		
	var gi = _connected_cells[key]
	var g = _connectivity_groups[gi]
	var group_size = g.size()
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	
	if group_size >= 5:
		sb.border_color = Color(1.0, 0.8, 0.1) 
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
	else:
		sb.border_color = Color(0.9, 0.75, 0.3) 
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


func _build_unit_columns():
	if not unit_container: return
	_refresh_connectivity(true)
	unit_container.alignment = BoxContainer.ALIGNMENT_CENTER
	# 三个单位之间改为 1px 间距（原 ITEM_GRID_GAP=6 太宽）
	unit_container.add_theme_constant_override("separation", 1)
	# ★ v6.48：按全队实际最大防具槽数补齐（不再固定4格）。双列布局下 2 槽=1 行，
	#   避免每单位显示 4 个格子（2真+2占位）让人误以为槽位很多。三列技能仍同一排。
	_unit_column_armor_rows = 2
	for u in party:
		if u != null:
			_unit_column_armor_rows = maxi(_unit_column_armor_rows, u.max_armor_slots)
	for child in unit_container.get_children():
		unit_container.remove_child(child); child.free()

	for i in range(party.size()):
		unit_container.add_child(_create_unit_column(i))

	_backup_all_armor_styles()
	# ★ v5.1：重建完毕后刷新标签统计（Build 引导反馈）
	_refresh_tag_stats()


# ============================================================
#  v5.1：队伍标签统计槽（Build 引导）
#  统计全队防具各标签件数，达 2 件（套装激活阈值）即高亮
# ============================================================
func _refresh_tag_stats():
	var left_vbox = get_node_or_null("VBoxContainer/MainHBox/LeftVBox")
	if left_vbox == null: return
	# 复用已有容器，避免重复创建
	if _tag_stats_container == null or not is_instance_valid(_tag_stats_container):
		_tag_stats_container = HBoxContainer.new()
		_tag_stats_container.name = "TagStatsBar"
		_tag_stats_container.add_theme_constant_override("separation", 3)
		left_vbox.add_child(_tag_stats_container)
		# 置顶：统计条放在单位栏上方
		left_vbox.move_child(_tag_stats_container, 0)
	else:
		for c in _tag_stats_container.get_children():
			_tag_stats_container.remove_child(c); c.free()

	# 统计全队防具标签件数
	var counts : Dictionary = {}
	for u in party:
		for slot in u.armor_slots:
			if slot == null: continue
			var data = ItemManager.get_item_data(slot.item_id)
			if data == null: continue
			for tag in data.tags:
				counts[tag] = int(counts.get(tag, 0)) + 1

	# 标题
	var title := Label.new()
	title.text = "流派:"
	title.add_theme_font_size_override("font_size", Style.FONT_SMALL)
	title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_stats_container.add_child(title)

	# ★ v6.38（A4）：这是"全队防具分布"，不是套装激活——真实套装判定是同单位 2 件
	#   (SetBonusManager.get_unit_set_tier)。旧版按全队件数标"已激活 2 件套"是假提示。
	for tag in UIConst.BUILD_TAG_ORDER:
		var n : int = int(counts.get(tag, 0))
		if n <= 0: continue
		var col : Color = UIConst.BUILD_TAG_COLORS.get(tag, Color.WHITE)
		var lbl := Label.new()
		lbl.text = "%s %d" % [tag, n]
		lbl.add_theme_font_size_override("font_size", Style.FONT_SMALL)
		lbl.add_theme_color_override("font_color", col)
		lbl.tooltip_text = "全队 %d 件【%s】防具（套装需同一单位 2 件才激活）" % [n, tag]
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tag_stats_container.add_child(lbl)


func _backup_all_armor_styles():
	_armor_btn_default_style.clear()
	if not unit_container: return
	for child in unit_container.get_children():
		_recursive_backup_armor_styles(child)

func _recursive_backup_armor_styles(node: Node):
	if node is Button:
		var b : Button = node
		if b.get_meta("slot_type", "") == "armor":
			var u = int(b.get_meta("unit_idx", -1))
			var s = int(b.get_meta("slot_idx", -1))
			if u >= 0 and s >= 0:
				var key = "%d_%d" % [u, s]
				_armor_btn_default_style[key] = {
					"normal": b.get_theme_stylebox("normal"),
					"hover": b.get_theme_stylebox("hover"),
				}
	for c in node.get_children():
		_recursive_backup_armor_styles(c)

func _on_armor_hover_entered(item_id: String, unit_idx: int, slot_idx: int):
	var key : String = "%d_%d" % [unit_idx, slot_idx]
	var group_size : int = 0
	var unit_count : int = 0
	if _connected_cells.has(key):
		var gi : int = _connected_cells[key]
		if gi >= 0 and gi < _connectivity_groups.size():
			var g = _connectivity_groups[gi]
			group_size = g.size()
			unit_count = g.unit_count()
			_apply_group_highlight(gi)
		else:
			_restore_all_armor_styles()
	else:
		_restore_all_armor_styles()

	# ★ v5.1：从队伍实例读取该防具实际 roll 出的词条（词条挂在实例上，不在 ItemData 上）
	var affixes_snapshot : Array = []
	if unit_idx >= 0 and unit_idx < party.size():
		var ud : UnitData = party[unit_idx]
		if ud and slot_idx >= 0 and slot_idx < ud.armor_slots.size():
			var worn : ItemInstance = ud.armor_slots[slot_idx]
			if worn and worn.affixes:
				affixes_snapshot = worn.affixes.duplicate(true)
	_detail.on_button_hover_entered_with_link(item_id, group_size, unit_count, affixes_snapshot)

func _on_armor_hover_exited():
	_detail.on_button_hover_exited()
	_restore_all_armor_styles()

func _apply_group_highlight(group_idx: int):
	_restore_all_armor_styles()
	if group_idx < 0 or group_idx >= _connectivity_groups.size():
		return
	var g = _connectivity_groups[group_idx]
	# ★ v5.1：高亮同样走子节点边框层，避免被图标/色块遮挡
	for cell in g.cells:
		var btn = _find_armor_button_at(cell.unit_index, cell.row)
		if btn:
			_set_slot_link_frame(btn, cell.unit_index, cell.row, true)

func _restore_all_armor_styles():
	# ★ v5.1：高亮画在子节点边框层，恢复时把所有连通格边框还原为常态黄框。
	# 直接遍历 _connected_cells，不再依赖从未被调用的样式备份字典。
	for key in _connected_cells:
		var parts : PackedStringArray = String(key).split("_", false)
		if parts.size() != 2: continue
		var u : int = int(parts[0])
		var s : int = int(parts[1])
		var btn = _find_armor_button_at(u, s)
		if btn:
			_set_slot_link_frame(btn, u, s, false)

func _find_armor_button_at(unit_idx: int, slot_idx: int) -> Button:
	if not unit_container: return null
	for child in unit_container.get_children():
		var found = _recursive_find_armor(child, unit_idx, slot_idx)
		if found: return found
	return null

func _recursive_find_armor(node: Node, unit_idx: int, slot_idx: int) -> Button:
	if node is Button:
		var b : Button = node
		if b.get_meta("slot_type", "") == "armor" \
				and int(b.get_meta("unit_idx", -1)) == unit_idx \
				and int(b.get_meta("slot_idx", -1)) == slot_idx:
			return b
	for c in node.get_children():
		var found = _recursive_find_armor(c, unit_idx, slot_idx)
		if found: return found
	return null


func _create_unit_column(unit_idx: int, is_preview: bool = false) -> Control:
	var wrapper: PanelContainer = PanelContainer.new()
	# 按内容宽度收拢，避免三列被 HBoxContainer 拉伸后头像间距过大；
	# 列间距已在 _build_unit_columns 收到 1px。
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	if is_preview:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.1, 0.15, 0.9)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.6, 0.6, 0.8)
		# 强制边距为 0
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		wrapper.add_theme_stylebox_override("panel", sb)
	else:
		var sb_empty = StyleBoxEmpty.new()
		sb_empty.content_margin_left = 0
		sb_empty.content_margin_right = 0
		sb_empty.content_margin_top = 0
		sb_empty.content_margin_bottom = 0
		wrapper.add_theme_stylebox_override("panel", sb_empty)

	var col := VBoxContainer.new()
	# v5.1：单位列内各段（头像/等级/防具/特技）统一使用商店格间距，
	# 避免等级按钮与防具槽贴在一起。
	col.add_theme_constant_override("separation", Style.ITEM_GRID_GAP)
	# ★ 核心修复：统一改为 ALIGNMENT_BEGIN 贴顶对齐，绝不居中，防止拖拽时因高度变化导致下沉
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.clip_contents = false
	wrapper.add_child(col)

	var unit = party[unit_idx]

	# 头像 + 升级按钮放进紧凑子容器：两者间距压到 1px，
	# 不影响下方防具/特技段仍用 ITEM_GRID_GAP。
	var head_group := VBoxContainer.new()
	head_group.add_theme_constant_override("separation", 1)
	head_group.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_child(head_group)

	# 头像
	var icon_ctrl = _create_unit_icon(unit, unit_idx)
	if unit.is_dead: icon_ctrl.modulate = Color(0.4, 0.4, 0.4, 1)
	head_group.add_child(icon_ctrl)

	# 升级按钮
	if _is_level_up_enabled():
		var level_btn = _create_level_btn(unit, unit_idx)
		if unit.is_dead: _disable_button(level_btn)
		head_group.add_child(level_btn)

	# 防具槽位 ★ v6.41：由每单位每行 1 个改为每行 2 个（GridContainer 双列，节约纵向空间）
	var armor_group := GridContainer.new()
	armor_group.name = "ArmorGroup"
	armor_group.columns = 2
	armor_group.add_theme_constant_override("h_separation", Style.ITEM_GRID_GAP)
	armor_group.add_theme_constant_override("v_separation", Style.ITEM_GRID_GAP)
	# ★ v6.42：按内容宽度收拢并居中，使防具槽区对齐在头像正下方（默认 FILL 会左对齐）
	armor_group.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(armor_group)

	# ★ v6.48：按机制槽上限(max_armor_slots)显示，而非 armor_slots.size()——
	#   底层数组会因同流派并入累积多个实例(贡献属性)，但玩家可见槽位 = 机制槽数。
	var visible_slots : int = clampi(unit.max_armor_slots, 0, unit.armor_slots.size())
	for slot_idx in range(visible_slots):
		var armor_btn = _create_item_button(unit.armor_slots[slot_idx], "armor", unit_idx, slot_idx)
		if unit.is_dead: _disable_button(armor_btn)
		# ★ v5.1：连线框用子节点画在图标之上（stylebox 边框会被全尺寸图标盖住）
		_set_slot_link_frame(armor_btn, unit_idx, slot_idx)
		armor_group.add_child(armor_btn)
	# 防具不足的列用透明占位补齐到固定格数，保证下方技能行统一高度（双列下 N 格）
	var missing_rows: int = maxi(0, _unit_column_armor_rows - visible_slots)
	for i in range(missing_rows):
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(Style.BTN_ITEM_SIZE.x, Style.BTN_ITEM_SIZE.y)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		armor_group.add_child(spacer)

	# ★ v6.49：技能槽与防具一致——每行 2 个（GridContainer 双列）
	var talent_group := GridContainer.new()
	talent_group.columns = 2
	talent_group.add_theme_constant_override("h_separation", Style.ITEM_GRID_GAP)
	talent_group.add_theme_constant_override("v_separation", Style.ITEM_GRID_GAP)
	talent_group.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(talent_group)

	var talent_inst = unit.talent_slots[0] if unit.talent_slots.size() > 0 else null
	var talent_btn = _create_talent_button(talent_inst, unit_idx, 0)
	if unit.is_dead: _disable_button(talent_btn)
	talent_group.add_child(talent_btn)

	var adv_btn = _create_advanced_talent_button(unit, unit_idx)
	if unit.is_dead: _disable_button(adv_btn)
	talent_group.add_child(adv_btn)

	# ★ v6.45：落位模式单位流派标签移到最下方（技能/进阶之后）
	if current_mode == Mode.ARMOR_ROLL:
		var school_lbl := Label.new()
		var mechs : Array = BuildManager.get_unit_mechanisms(unit)
		var parts : Array = []
		for m in mechs:
			parts.append("%s Lv%d" % [str(m.get("school", "")), int(m.get("level", 1))])
		school_lbl.text = " / ".join(parts) if not parts.is_empty() else "无流派"
		school_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		school_lbl.add_theme_font_size_override("font_size", Style.FONT_SMALL)
		school_lbl.add_theme_color_override("font_color",
			BuildManager.get_school_color(str(mechs[0].get("school", ""))) if not parts.is_empty() else Color(0.55, 0.55, 0.58))
		school_lbl.set_meta("slot_type", "school_label")
		col.add_child(school_lbl)

	if is_preview:
		_disable_all_input_recursive(wrapper)
		wrapper.modulate = Color(1, 1, 1, 0.9)

	return wrapper


## ★ v6.44：灰显但保留鼠标悬停 / 右键切换信息（mouse_filter 用 STOP 不用 IGNORE）
func _disable_all_input_recursive_keep_hover(node: Node):
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_STOP
		if node is Button:
			node.disabled = true
	for child in node.get_children():
		_disable_all_input_recursive_keep_hover(child)


func _disable_all_input_recursive(node: Node):
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if node is Button:
			node.disabled = true
	for child in node.get_children():
		_disable_all_input_recursive(child)


## ★ v6.41：防具落位模式——灰显除"防具槽按钮"外的一切交互，
##   让玩家看着全貌（遗物/技能词条）但只能点防具槽决定落位单位。
func _apply_armor_pick_readonly():
	if current_mode != Mode.ARMOR_ROLL:
		return
	# ★ v6.44：灰显保留 mouse_filter=STOP，让悬停信息 / 右键切换仍能工作
	for node in [tab_bar, confirm_btn]:
		if node is Node:
			_disable_all_input_recursive_keep_hover(node)
	# ★ v6.45：落位模式隐藏右栏（含出售区），只留装备全貌
	if right_container is CanvasItem:
		(right_container as CanvasItem).visible = false
	# 左侧遗物栏：展示但不可操作（保留 hover）
	if relic_container is Node:
		_disable_all_input_recursive_keep_hover(relic_container)
	# ★ v6.44：落位模式隐藏"全队流派统计条"，改由每单位列显示自己的流派
	if _tag_stats_container and is_instance_valid(_tag_stats_container):
		_tag_stats_container.visible = false
	# 单位列：逐列处理——头像/等级/技能/进阶按钮灰掉，只留防具槽按钮可点
	if unit_container is Node:
		_gray_unit_columns_except_armor(unit_container)


func _gray_unit_columns_except_armor(node: Node):
	for child in node.get_children():
		if child is Button and str(child.get_meta("slot_type", "")) == "armor":
			# 防具槽：保持可点，接落位回调
			child.pressed.connect(_on_armor_pick_pressed.bind(
				int(child.get_meta("unit_idx", -1)), int(child.get_meta("slot_idx", -1))))
			continue
		# ★ v6.50：单位头像整体保留 hover——内部子节点设 IGNORE，且**不要**再递归
		#   灰显逻辑（旧版递归把子节点又设回 STOP，吞掉事件，导致 avatar 悬停无信息）
		if child is Control and str(child.get_meta("slot_type", "")) == "unit_icon":
			_set_children_mouse_ignore(child)
			child.mouse_filter = Control.MOUSE_FILTER_STOP
			child.modulate = Color(0.45, 0.45, 0.48, 1)   # 视觉灰显（落位模式只读）
			continue
		# ★ v6.44：灰显但保留 hover / 右键（STOP），只灰视觉不改 mouse_filter
		if child is Control and not (child is Container):
			child.mouse_filter = Control.MOUSE_FILTER_STOP
			if child is Button:
				child.disabled = true
			if child is CanvasItem:
				(child as CanvasItem).modulate = Color(0.45, 0.45, 0.48, 1)
		_gray_unit_columns_except_armor(child)


func _set_children_mouse_ignore(node: Node):
	for c in node.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_ignore(c)


## ★ v6.43：由 ArmorRollUI 注入待落袋防具，更新顶部提示并高亮所有防具槽
func set_pending_armor(info: Dictionary) -> void:
	_pending_armor = info.duplicate()
	if current_mode != Mode.ARMOR_ROLL:
		return
	var item_name : String = str(_pending_armor.get("name", "防具"))
	var school : String = str(_pending_armor.get("school", ""))
	var top_bar = get_node_or_null("VBoxContainer/TopBar")
	if top_bar == null:
		return

	# ★ v6.46：清空旧的落袋栏（图标/文字/放弃按钮），整段重建
	for node_name in ["PendingCenter", "PendingArmorIcon", "PendingArmorSwatch"]:
		var old = top_bar.get_node_or_null(node_name)
		if old: old.queue_free()
	# 隐藏原 mode_label（改用自定义居中行）
	if mode_label: mode_label.visible = false
	top_bar.custom_minimum_size = Vector2(0, 26)   # 容纳 20x20 图标 + 色块

	# ---- 居中行：CenterContainer 包 HBox[防具按钮 + 文字] ----
	var center := CenterContainer.new()
	center.name = "PendingCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	# 防具按钮：复用 _create_item_button —— 自带流派色块 + 图标 + 悬停信息，与其他防具完全一致
	var iid : String = str(_pending_armor.get("item_id", ""))
	var temp_inst := ItemInstance.new()
	temp_inst.item_id = iid
	temp_inst.count = 1
	var pending_affixes : Array = _pending_armor.get("affixes", [])
	if not pending_affixes.is_empty():
		temp_inst.affixes = pending_affixes.duplicate()
	var armor_btn := _create_item_button(temp_inst, "pending", -1, -1)
	armor_btn.disabled = false
	row.add_child(armor_btn)

	var desc := Label.new()
	desc.text = "【%s】%s" % [school, item_name] if school != "" else item_name
	desc.add_theme_font_size_override("font_size", Style.FONT_NORMAL)
	desc.add_theme_color_override("font_color", Color.WHITE)
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc)

	# ★ v6.50：放弃防具按钮并入居中行，紧跟文字之后（不再被 EXPAND_FILL 挤到最右）
	var discard := Button.new()
	discard.name = "DiscardArmorBtn"
	discard.text = "放弃防具"
	discard.add_theme_font_size_override("font_size", Style.FONT_SMALL)
	discard.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	discard.pressed.connect(func(): armor_discard_requested.emit())
	row.add_child(discard)

	_highlight_armor_slots()


## ★ v6.43：给所有防具槽套高亮框（脉动），让玩家一眼知道要点这里落位
func _highlight_armor_slots() -> void:
	if not unit_container:
		return
	_highlight_armor_slots_recursive(unit_container)


func _highlight_armor_slots_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Button and str(child.get_meta("slot_type", "")) == "armor":
			var btn := child as Button
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.20, 0.18, 0.10, 0.55)
			sb.set_border_width_all(2)
			sb.border_color = Color(1.0, 0.82, 0.28, 1.0)
			sb.content_margin_left = 1
			sb.content_margin_right = 1
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			btn.add_theme_stylebox_override("normal", sb)
			var hover_sb := sb.duplicate()
			(hover_sb as StyleBoxFlat).bg_color = Color(0.35, 0.30, 0.12, 0.8)
			btn.add_theme_stylebox_override("hover", hover_sb)
			continue
		_highlight_armor_slots_recursive(child)


func _on_armor_pick_pressed(unit_idx: int, slot_idx: int):
	if current_mode != Mode.ARMOR_ROLL:
		return
	if unit_idx < 0 or unit_idx >= party.size():
		return
	var ud : UnitData = (_context.get_units()[unit_idx] if _context.get_units().size() > unit_idx else party[unit_idx])
	if ud != null and ud.is_dead:
		return
	# ★ v6.53：所有落位决策统一由 ArmorRollUI._on_place 弹 show_choice（强化/转向），
	#   这里只回传"点的是哪个单位、哪个槽"，转向时就替换该槽的流派。
	armor_slot_picked.emit(unit_idx, slot_idx)


func _is_level_up_enabled() -> bool:
	# ★ v6：单位升级改为战斗累计经验 + 战后自动升级，装备界面不再提供手动升级按钮
	return false

func _build_ui_inner():
	var vbox = $VBoxContainer
	if vbox:
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# 左右各留 4px 安全边距：防止左栏长标题/右栏内容贴死画面边界被裁切
		vbox.offset_left = 4
		vbox.offset_top = 2
		vbox.offset_right = -4
		vbox.offset_bottom = -2
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 2)

	var top_bar = get_node_or_null("VBoxContainer/TopBar")
	if top_bar:
		top_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top_bar.custom_minimum_size = Vector2(0, 16)

	var gold_lbl = get_node_or_null("VBoxContainer/GoldLabel")
	if gold_lbl:
		gold_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		gold_lbl.custom_minimum_size = Vector2(0, 12)

	var main_hbox = get_node_or_null("VBoxContainer/MainHBox")
	if main_hbox:
		main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.clip_contents = false

	var bottom_hbox = get_node_or_null("VBoxContainer/BottomHBox")
	if bottom_hbox:
		bottom_hbox.size_flags_vertical = Control.SIZE_SHRINK_END
		bottom_hbox.custom_minimum_size = Vector2(0, 20)
		bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var left_info = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn")
	if left_info:
		left_info.custom_minimum_size = Vector2(80, 0) 
		left_info.size_flags_horizontal = Control.SIZE_FILL 
		left_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_info.clip_contents = true

	var detail_zone = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/DetailZone")
	if detail_zone:
		detail_zone.custom_minimum_size = Vector2(80, 150) 
		detail_zone.size_flags_horizontal = Control.SIZE_FILL
		detail_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL 
		detail_zone.clip_contents = true

	var item_info = get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/ItemInfoPanel")
	if item_info:
		item_info.custom_minimum_size = Vector2.ZERO 
		item_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_info.clip_contents = true
		var scroll = item_info.get_node_or_null("VBox/Scroll")
		if scroll:
			scroll.custom_minimum_size = Vector2.ZERO
			scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		
		for label_path in ["VBox/NameLabel", "VBox/TypeLabel", "VBox/Scroll/ContentVBox/DescLabel", "VBox/Scroll/ContentVBox/StatsLabel"]:
			var lb = item_info.get_node_or_null(label_path)
			if lb:
				lb.custom_minimum_size = Vector2(0, 0)
				lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lb.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY

	var left_vbox = get_node_or_null("VBoxContainer/MainHBox/LeftVBox")
	if left_vbox:
		left_vbox.custom_minimum_size = Vector2(0, 0)
		left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL 
		left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_vbox.clip_contents = false

		# ★ 核心修复：直接使用类顶部的成员变量 unit_container，不再用 var 声明，防止变量遮蔽
		if unit_container and unit_container.get_parent() == left_vbox:
			if not left_vbox.has_node("UnitScroll"):
				var scroll = ScrollContainer.new()
				scroll.name = "UnitScroll"
				scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
				scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
				
				left_vbox.remove_child(unit_container)
				left_vbox.add_child(scroll)
				# ★ 保证单位栏在团队遗物区上方：scroll 插到 RelicSection 之前，
				#   否则 add_child 默认加到末尾会把遗物顶到单位上方
				if relic_section and relic_section.get_parent() == left_vbox:
					left_vbox.move_child(scroll, relic_section.get_index())
				scroll.add_child(unit_container)
				unit_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				unit_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var r_scroll = get_node_or_null("VBoxContainer/MainHBox/RightScroll")
	if r_scroll and r_scroll is ScrollContainer:
		r_scroll.custom_minimum_size = Vector2(110, 0) 
		r_scroll.size_flags_horizontal = Control.SIZE_FILL
		r_scroll.size_flags_vertical = Control.SIZE_FILL
		r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		r_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		r_scroll.clip_contents = true 

	var r_container = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer")
	if r_container:
		r_container.custom_minimum_size = Vector2(0, 0)
		r_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_container.clip_contents = true

	var inner_shop_scroll = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/ShopScroll")
	if inner_shop_scroll and inner_shop_scroll is ScrollContainer:
		inner_shop_scroll.custom_minimum_size = Vector2(0, 0)
		inner_shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner_shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inner_shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		inner_shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		inner_shop_scroll.clip_contents = true

	var t_bar = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/TabBar")
	if t_bar:
		t_bar.custom_minimum_size = Vector2(0, 16)
		t_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_bar.clip_contents = true
		for child in t_bar.get_children():
			if child is Button:
				child.clip_text = true
				child.custom_minimum_size = Vector2(0, 16) 
				child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				child.add_theme_font_size_override("font_size", 7)

	var d_zone = get_node_or_null("VBoxContainer/MainHBox/RightScroll/RightContainer/DiscardZone")
	if d_zone:
		d_zone.custom_minimum_size = Vector2(0, 20) 
		var lbl = d_zone.get_node_or_null("DiscardLabel")
		if lbl:
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var show_passive : bool = (_context.get_context_id() != "arena")
	# ★ v6.62c：底部两个遗物区域（团队 6 槽 / 老虎机 4 槽），区域内直接放插槽
	if relic_section: relic_section.visible = show_passive
	if relic_container:
		relic_container.visible = show_passive
		relic_container.add_theme_constant_override("separation", 2)
	if roll_relic_section: roll_relic_section.visible = show_passive
	if roll_relic_container:
		roll_relic_container.visible = show_passive
		roll_relic_container.add_theme_constant_override("separation", 2)
	if show_passive:
		_build_passive_slots()
		_build_roll_relic_slots()

	var show_pending : bool = false
	# ★ v6.62c：魂栈（FORGE）已无熔铸奖励，"一键领取"整段移除；仅 MAP_SHOP_REST 保留
	if current_mode == Mode.MAP_SHOP_REST:
		if current_tab != "arena_shop":
			show_pending = true
			
	if show_pending:
		_ensure_pending_section()
		_build_pending_slots()
		if _pending_section:
			_pending_section.visible = true
	else:
		if _pending_section and is_instance_valid(_pending_section):
			var p = _pending_section.get_parent()
			if p: p.remove_child(_pending_section)
			_pending_section.queue_free()
			_pending_section = null
			_pending_container = null

	if not mode_label: return

	_update_gold_display()

	shop_container.visible = false
	tab_bar.visible = false
	right_container.visible = true

	weapon_tab_btn.visible = false
	talent_tab_btn.visible = false
	if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
	if furnace_tab_btn: furnace_tab_btn.visible = false
	if _aura_tab_btn: _aura_tab_btn.visible = false

	match current_mode:
		Mode.DEPLOY:
			mode_label.text = "装备配置 - 战前准备" if _context.get_title() == "" else _context.get_title()
			close_btn.visible = true
			close_btn.text = "返回"
			confirm_btn.visible = true
			confirm_btn.text = "开始探索"
			confirm_btn.disabled = false
			confirm_btn.modulate = Color.WHITE
			gold_label.visible = _context.show_gold()
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = false
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "特技库"
			if current_tab == "":
				current_tab = "talent"
			_update_tab_style()
			_build_talent_grid(shop_container)
			shop_container.visible = true

		Mode.MAP:
			mode_label.text = "装备配置"
			close_btn.visible = true
			close_btn.text = "返回"
			confirm_btn.visible = false
			gold_label.visible = false
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = false
			talent_tab_btn.visible = false
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# ★ v6.4：技能词条开局 roll 后锁定，地图界面不再提供特技库替换/交换
			talent_tab_btn.disabled = true
			talent_tab_btn.text = "技能（已锁定）"
			current_tab = "talent"
			_update_tab_style()
			_build_talent_grid(shop_container)
			shop_container.visible = false

		Mode.ARMOR_ROLL:
			# ★ v6.41：战后落位决策——展示全貌（防具/遗物/技能词条），除防具槽外只读
			mode_label.text = "防具落位 · 选择单位"
			# ★ v6.44：取消落位按钮去掉（改为顶部"放弃防具"），关闭只能先做决定
			close_btn.visible = false
			confirm_btn.visible = false
			gold_label.visible = false
			tab_bar.visible = false
			weapon_tab_btn.visible = false
			talent_tab_btn.visible = false
			if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
			if furnace_tab_btn: furnace_tab_btn.visible = false
			if _aura_tab_btn: _aura_tab_btn.visible = false
			shop_container.visible = false
			# 展示遗物与技能词条供综合考虑（右侧 TabBar 虽隐藏，左侧遗物栏 + 单位列技能照常显示）

		Mode.ARENA_REST:
			mode_label.text = "魂之竞技场 · 备战"
			gold_label.visible = true
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = true
			weapon_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			weapon_tab_btn.text = "商店"
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "铁匠铺"
			if current_tab == "" or (not current_tab.begins_with("arena_") and current_tab != "sacrifice" and current_tab != "aura"):
				current_tab = "arena_shop"
			_update_tab_style()
			_forge.cleanup()

			close_btn.visible = false
			confirm_btn.visible = true
			confirm_btn.text = "出发"

			if current_tab == "arena_forge":
				confirm_btn.disabled = true
				confirm_btn.modulate = Color(0.5, 0.5, 0.5)
				_forge.build_forge_slots()
				shop_container.visible = true
			else:
				confirm_btn.disabled = false
				confirm_btn.modulate = Color.WHITE
				_build_shop_items()
				shop_container.visible = true

		Mode.MAP_SHOP_REST:
			mode_label.text = "魂栈 · 魂栈侍从"
			close_btn.visible = true
			close_btn.text = "继续探索"
			confirm_btn.visible = false
			gold_label.visible = true
			tab_bar.visible = true
			tab_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
			weapon_tab_btn.visible = true
			weapon_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			weapon_tab_btn.text = "商店"
			talent_tab_btn.visible = true
			talent_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			talent_tab_btn.disabled = false
			talent_tab_btn.text = "铁匠铺"
			if sacrifice_tab_btn:
				sacrifice_tab_btn.visible = true
				sacrifice_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if _aura_tab_btn:
				_aura_tab_btn.visible = true
				_aura_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			if current_tab == "" or (not current_tab.begins_with("arena_") and current_tab != "sacrifice" and current_tab != "aura"):
				current_tab = "arena_shop"
			_update_tab_style()
			_forge.cleanup()

			match current_tab:
				"arena_forge":
					_forge.build_forge_slots()
					shop_container.visible = true
				"sacrifice":
					_build_sacrifice_panel()
					shop_container.visible = true
				"aura":
					_build_aura_panel()
					shop_container.visible = true
				_:
					_build_shop_items()
					shop_container.visible = true

		Mode.FORGE:
			mode_label.text = "魂栈"
			close_btn.visible = true
			close_btn.text = "离开"
			confirm_btn.visible = false
			gold_label.visible = false
			# ★ 魂栈只需遗物商店，不要页签切换（用户划掉"熔铸"页签）
			tab_bar.visible = false
			weapon_tab_btn.visible = false
			talent_tab_btn.visible = false
			if _aura_tab_btn: _aura_tab_btn.visible = false
			if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
			current_tab = "sacrifice"
			_forge.cleanup()
			# 清掉可能残留的旧熔铸/一键领取动态节点（用户划掉的两个宽框）
			_clear_forge_leftovers()
			# ★ 魂栈改为遗物商店（献祭赋能已合入英灵殿）
			if _relic_shop:
				_build_relic_shop_panel()
			else:
				_build_sacrifice_panel()
			shop_container.visible = true

	# ★ v6.59：魂栈遗物商店显示刷新按钮
	reset_btn.visible = (current_tab == "arena_shop") or (current_mode == Mode.FORGE and _relic_shop != null)
	if reset_btn.visible and current_mode == Mode.FORGE and _relic_shop != null:
		reset_btn.text = "刷新商店（%dG）" % _relic_shop.get_refresh_cost()
	elif reset_btn.visible and shop_manager:
		reset_btn.text = "刷新 (" + str(shop_manager.get_reset_cost()) + "G)"
		
	# ★ v6.59：魂栈遗物商店需要出售区
	discard_zone.visible = (current_mode == Mode.FORGE and _relic_shop != null) or (current_tab != "arena_forge" and current_tab != "sacrifice" and current_tab != "aura" and current_mode != Mode.DEPLOY and current_mode != Mode.MAP)

	if current_mode == Mode.FORGE or is_shop_rest_mode():
		_setup_forge_narrative_ui()

	close_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	confirm_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
	
	if reset_btn:
		reset_btn.add_theme_font_size_override("font_size", Style.FONT_LARGE)
		reset_btn.custom_minimum_size = Vector2(0, 16)
		reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reset_btn.size_flags_vertical = Control.SIZE_SHRINK_END
		reset_btn.clip_text = true
		# ★ v6.72ai：刷新按钮用 8bit 按钮 stylebox（五态共用，去掉硬编码状态色）
		var sb_reset := load(Config.PATHS.STYLEBOX_8BIT_BUTTON)
		if sb_reset:
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				reset_btn.add_theme_stylebox_override(state, sb_reset)

	_ensure_upgrade_shop_btn()
	_refresh_upgrade_shop_btn()

	_refresh_connectivity()

	_build_unit_columns()
	visible = true

	if shop_container: shop_container.queue_sort()
	if right_container: right_container.queue_sort()
	if tab_bar: tab_bar.queue_sort()

func _get_level_up_cost(cur_level: int) -> int:
	var cfg : Dictionary = GameConfigManager.get_file("economy_config.json")
	var costs : Array = cfg.get("unit_level_up_cost", [50, 100, 200, 400, 800])
	var idx : int = cur_level - 1
	if idx < 0 or idx >= costs.size():
		return 999999
	return int(costs[idx])	


func _create_level_btn(unit: UnitData, unit_idx: int) -> Button:
	# 与 54x54 头像框同宽；高度从 24 收到 16，减少纵向占用
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Vector2(54, 16))
	btn.set_meta("slot_type", "level_btn")
	btn.set_meta("unit_idx", unit_idx)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# ★ v6.72ai：单位按钮用 8bit 按钮 stylebox（紧凑版，不硬编码参数）
	#   五态共用同一资源实例：避免某态回落到引擎默认样式导致尺寸不一致、布局错位。
	var sb := load(Config.PATHS.STYLEBOX_8BIT_BUTTON)
	if sb:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(state, sb)

	var cap : int = int(GameState.unit_level_cap.get(unit.unit_name, 3))
	var cur : int = int(unit.level)

	if cur >= 6 or cur >= cap:
		btn.text = "L%d\nMAX" % cur
		btn.disabled = true
		btn.modulate = Color(0.5, 0.5, 0.5)
		return btn

	var cost : int = _get_level_up_cost(cur)
	var has_gold : bool = _context.get_gold() >= cost
	
	btn.text = "L%d\n%dG" % [cur, cost]
	btn.tooltip_text = ""
	btn.disabled = not has_gold
	btn.modulate = Color.WHITE if has_gold else Color(0.6, 0.5, 0.5)
	
	if has_gold:
		btn.pressed.connect(_on_level_up_pressed.bind(unit_idx))
	return btn


func _on_level_up_pressed(unit_idx: int):
	if unit_idx < 0 or unit_idx >= party.size(): return
	var u : UnitData = party[unit_idx]
	if u.is_dead: return

	var cap : int = int(GameState.unit_level_cap.get(u.unit_name, 3))
	if u.level >= cap: return
	if u.level >= 6: return

	var cost : int = _get_level_up_cost(u.level)
	if not _context.subtract_gold(cost): return

	u.apply_level_up()
	SoundManager.play_get_item_sound()
	_update_gold_display()
	_sync_all()
	
	call_deferred("_build_unit_columns")
	_schedule_build_ui()


func _update_gold_display():
	if gold_label:
		var soul_fire_str: String = ""
		if SoulFireManager:
			soul_fire_str = "    |    魂火: %d/%d" % [SoulFireManager.current, SoulFireManager.get_max_carried()]
		gold_label.text = "金币: " + str(_context.get_gold()) + soul_fire_str
	# ★ v6.62j：同步魂栈商店上方的持有金币（出售/购买不重建商店格，需单独刷新）
	if _relic_shop:
		_relic_shop.refresh_gold_label()


func _build_aura_panel():
	_clear_container(shop_container)
	shop_container.add_theme_constant_override("h_separation", 2)
	shop_container.add_theme_constant_override("v_separation", 2)
	shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN 
	shop_container.visible = true

	if shop_scroll:
		shop_scroll.custom_minimum_size = Vector2(0, 0)
		shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		shop_scroll.scroll_vertical = 0
		shop_scroll.scroll_horizontal = 0

	if _context.get_context_id() == "arena":
		var hint0 := Label.new()
		hint0.text = "竞技场不支持光环\n（光环为局内被动，仅主游戏可用）"
		hint0.add_theme_font_size_override("font_size", 7)
		hint0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint0.modulate = Color(0.7, 0.7, 0.7)
		hint0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		shop_container.add_child(hint0)
		return

	var unlocked : Array = GameState.unlocked_auras.duplicate()
	var equipped : Array = GameState.get_auras_from_passives()
	var candidates : Array = GameState.current_aura_candidates.duplicate()
	var cur_sf : int = SoulFireManager.current
	var empty_slot : int = _get_first_empty_passive_slot()

	if unlocked.is_empty():
		var hint0 := Label.new()
		hint0.text = "暂无解锁光环\n（在灰烬铁匠处研究以解锁）"
		hint0.add_theme_font_size_override("font_size", 7)
		hint0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint0.modulate = Color(0.6, 0.6, 0.6)
		hint0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		shop_container.add_child(hint0)
		return

	for aid in equipped:
		var btn := _make_aura_icon_btn(aid, cur_sf, true, empty_slot)
		shop_container.add_child(btn)

	for aid in candidates:
		var btn := _make_aura_icon_btn(aid, cur_sf, false, empty_slot)
		shop_container.add_child(btn)

	if empty_slot < 0 and not candidates.is_empty():
		var warn := Label.new()
		warn.text = "被动槽已满\n需先卸下光环"
		warn.add_theme_font_size_override("font_size", 6)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.modulate = Color(1.0, 0.6, 0.6)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(40, 0)
		shop_container.add_child(warn)


func _make_aura_icon_btn(aid: String, cur_sf: int, is_equipped: bool, _empty_slot: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_SHOP_SIZE)
	btn.expand_icon = true
	btn.clip_text = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)
	
	var ad : Dictionary = AuraManager.get_aura(aid)
	var icon = ad.get("icon")
	if icon is Texture2D:
		btn.icon = icon
		btn.text = ""
	else:
		btn.text = ad.get("name", aid).substr(0, 2)

	var buy_cost : int = int(ad.get("buy_cost", 0))
	if buy_cost <= 0: buy_cost = 6

	var label = Label.new()
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_bottom = 1
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if is_equipped:
		label.text = "已装"
		label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
		btn.set_meta("slot_type", "aura_equipped")
		btn.set_meta("aura_id", aid)
	else:
		label.text = "%d魂" % buy_cost
		label.add_theme_color_override("font_color", Color.WHITE)
		if cur_sf < buy_cost:
			btn.modulate = Color(0.5, 0.5, 0.5)
			btn.disabled = true
		else:
			btn.set_meta("slot_type", "aura_shop")
			btn.set_meta("aura_id", aid)
			btn.set_meta("aura_price", buy_cost)

	btn.add_child(label)
	
	btn.mouse_entered.connect(_on_aura_hover_entered.bind(aid))
	btn.mouse_exited.connect(_on_aura_hover_exited)
	
	return btn


func _get_first_empty_passive_slot() -> int:
	var passives : Array = _context.get_passives()
	for i in range(passives.size()):
		if passives[i] == null: return i
	return -1


func _on_buy_aura(aid: String, cost: int):
	if not SoulFireManager.spend(cost):
		return
	if not _context.add_aura_to_passive_slot(aid):
		SoulFireManager.add(cost)
		_show_detail_in_zone("被动槽已满")
		return
	GameState.remove_aura_candidate(aid)
	SoundManager.play_select_sound()
	_sync_all()
	_update_gold_display()
	_schedule_build_ui()
	_show_detail_in_zone("已购买光环：%s" % AuraManager.get_display_name(aid))


func _on_unequip_aura(aid: String):
	var passives : Array = _context.get_passives()
	var found_idx : int = -1
	for i in range(passives.size()):
		var p : Variant = passives[i]
		if p is Dictionary and p.get("type", "") == "aura" and p.get("aura_id", "") == aid:
			found_idx = i
			break
	if found_idx < 0:
		return
	_context.remove_passive_at_slot(found_idx)
	SoundManager.play_cancel_sound()
	_sync_all()
	_schedule_build_ui()
	_show_detail_in_zone("已卸下光环：%s\n（不返还魂火，下次进 FORGE 时可能重新抽到）" % AuraManager.get_display_name(aid))


func _ensure_pending_section():
	if _pending_container and is_instance_valid(_pending_container):
		return
	if not right_container: return

	_pending_section = VBoxContainer.new()
	_pending_section.name = "PendingSection"
	_pending_section.add_theme_constant_override("separation", 2)
	_pending_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_section.clip_contents = true
	
	if shop_scroll:
		var sc_idx : int = shop_scroll.get_index()
		right_container.add_child(_pending_section)
		right_container.move_child(_pending_section, sc_idx + 1)
	else:
		right_container.add_child(_pending_section)

	var btn_claim := Style.create_styled_button(Style.FONT_SMALL, Vector2(0, 16))
	btn_claim.name = "PendingTitleBtn"
	btn_claim.text = "一键领取 (0)"
	btn_claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_claim.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	btn_claim.pressed.connect(_on_claim_all_pending)
	_pending_section.add_child(btn_claim)

	var center_wrap := CenterContainer.new()
	center_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_section.add_child(center_wrap)

	_pending_container = GridContainer.new()
	_pending_container.name = "PendingContainer"
	_pending_container.columns = 3
	_pending_container.add_theme_constant_override("h_separation", 4)
	_pending_container.add_theme_constant_override("v_separation", 4)
	_pending_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_wrap.add_child(_pending_container)


func _build_pending_slots():
	if not _pending_container or not is_instance_valid(_pending_container): 
		return
		
	for child in _pending_container.get_children():
		_pending_container.remove_child(child)
		child.free()

	var all_pending : Array = []
	for i in range(GameState.pending_sacrifice_rewards.size()):
		all_pending.append({"inst": GameState.pending_sacrifice_rewards[i], "idx": i, "src": "sacrifice"})
	for i in range(GameState.pending_forge_rewards.size()):
		all_pending.append({"inst": GameState.pending_forge_rewards[i], "idx": i, "src": "forge"})

	var title_btn = _pending_section.get_node_or_null("PendingTitleBtn")
	if title_btn:
		title_btn.text = "一键领取 (%d)" % all_pending.size()
		title_btn.disabled = all_pending.is_empty()

	var MAX_SLOTS : int = 6
	for i in range(MAX_SLOTS):
		if i < all_pending.size():
			var entry = all_pending[i]
			var btn := _create_pending_button(entry["inst"], entry["idx"], entry["src"])
			_pending_container.add_child(btn)
		else:
			var empty_btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
			empty_btn.custom_minimum_size = Style.BTN_ITEM_SIZE
			empty_btn.disabled = true
			empty_btn.modulate = Color(1, 1, 1, 0) 
			_pending_container.add_child(empty_btn)


func _create_pending_button(inst: ItemInstance, idx: int, src: String) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.expand_icon = true
	btn.custom_minimum_size = Style.BTN_ITEM_SIZE
	btn.set_meta("slot_type", "pending_reward")
	btn.set_meta("pending_idx", idx)
	btn.set_meta("pending_src", src)
	btn.clip_text = true
	btn.clip_contents = false

	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)

	if inst:
		var data : ItemData = ItemManager.get_item_data(inst.item_id)
		if data and data.icon:
			btn.icon = data.icon
			btn.text = ""
		else:
			btn.text = data.name if data else inst.item_id

		# ★ v5.14：待领取防具也垫 20x20 流派色块，与商店/已装备格子一致
		if data and data.type == "armor":
			_draw_build_tag_backdrop(btn, data)

		btn.set_meta("item_id", inst.item_id)
		btn.modulate = Color.WHITE 
		
		if inst.direction != Direction.Value.NONE:
			_draw_direction_badges(btn, inst.direction)
			
		var item_id : String = inst.item_id
		btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
		btn.mouse_exited.connect(_on_button_hover_exited)
	return btn


func _build_sacrifice_panel():
	_clear_container(shop_container)
	shop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if GameState.has_pending_sacrifice_rewards():
		var hint := Label.new()
		hint.text = "请先在上方领取熔铸奖励（%d 件）" % GameState.pending_sacrifice_rewards.size()
		hint.add_theme_font_size_override("font_size", 8)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.modulate = Color(1.0, 0.85, 0.3)
		shop_container.add_child(hint)
		return
	
	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 4) 
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	shop_container.add_child(main_vbox)

	var title := Label.new()
	title.text = "熔铸一个单位\n获得该职业专属 buff 防具"
	title.add_theme_font_size_override("font_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(title)

	var drop_zone := PanelContainer.new()
	drop_zone.name = "SacrificeDropZone"
	drop_zone.custom_minimum_size = Vector2(0, 35)
	drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.15, 0.15, 0.2, 0.5)
	stylebox.border_color = Color(0.4, 0.4, 0.5)
	stylebox.set_border_width_all(1)
	drop_zone.add_theme_stylebox_override("panel", stylebox)
	
	var drop_lbl := Label.new()
	drop_lbl.text = "拖拽单位至此确认熔铸"
	drop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_lbl.add_theme_font_size_override("font_size", 7)
	drop_lbl.modulate = Color(0.7, 0.8, 0.9)
	drop_zone.add_child(drop_lbl)
	main_vbox.add_child(drop_zone)

	var warn := Label.new()
	warn.text = "⚠ 熔铸第 3 个单位将导致全灭"
	warn.add_theme_font_size_override("font_size", 6)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.modulate = Color(1.0, 0.5, 0.5)
	main_vbox.add_child(warn)

## ★ v6.62：魂栈遗物商店面板（按参考图4——右侧四区：购买战场遗物/购买防具遗物/刷新商店/出售遗物）
var _relic_shop_section : String = "team"   # "team" 战场遗物 / "roll" 防具遗物

## ★ 魂栈：清掉旧熔铸/一键领取遗留在 right_container 的动态宽框节点
func _clear_forge_leftovers() -> void:
	if not right_container: return
	for n_name in ["ForgeCraftRow", "PendingSection", "PendingCenter"]:
		var n : Node = right_container.get_node_or_null(n_name)
		if n:
			right_container.remove_child(n)
			n.queue_free()


func _build_relic_shop_panel() -> void:
	if _relic_shop == null or shop_container == null: return
	# ★ 魂栈只有 6 格（HFlow 自动换 2 行），ShopScroll 不能 EXPAND_FILL 撑满，
	#   否则会把下方「刷新商店 / 出售区」功能区挤出可视范围。
	if shop_scroll:
		shop_scroll.custom_minimum_size = Vector2(0, 0)
		shop_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		# ★ v6.72o-p1：必须 DISABLED——SHRINK_BEGIN + AUTO 会让 ScrollContainer 最小高度塌缩为 0，
		#   商品格全被裁掉（实机「商品没有了」）。右侧中部有大片留白，两行标题挤不掉功能按钮。
		shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# ★ 回归最简结构：shop_container 是运行时 HFlowContainer（见 init），
	#   直接渲染 6 个遗物格（上排 3 团队 / 下排 3 老虎机），不再嵌套 VBox/Grid。
	_relic_shop.render(shop_container, null)

	# 刷新商店（复用 right_container 的 ResetBtn）
	if reset_btn:
		reset_btn.visible = true
		reset_btn.text = "刷新商店（%dG）" % _relic_shop.get_refresh_cost()

	# 出售遗物（右下出售区）
	if discard_zone:
		discard_zone.visible = true
		var dl = discard_zone.get_node_or_null("DiscardLabel")
		if dl:
			var rate_pct : int = int(RelicShop.get_sell_rate() * 100.0)
			dl.text = "出售遗物（返还 %d%%）\n拖入遗物换金币" % rate_pct


func _on_relic_shop_section(section: String) -> void:
	_relic_shop_section = section
	_build_relic_shop_panel()


func _on_relic_shop_reset() -> void:
	if _relic_shop == null: return
	var cost : int = _relic_shop.get_refresh_cost()
	if _context.get_gold() < cost:
		_show_detail_in_zone("金币不足，无法刷新")
		return
	_context.subtract_gold(cost)
	_relic_shop.generate()
	_build_relic_shop_panel()
	_update_gold_display()
	_show_detail_in_zone("商店已刷新")


## ★ v6.59：魂栈出售遗物（团队槽 / 老虎机槽）
## ★ v6.62c：魂栈商店格子拖到遗物槽——执行购买
func _buy_relic_by_drag(data: Dictionary) -> void:
	if _relic_shop == null: return
	var idx : int = int(data.get("shop_candidate_idx", -1))
	var is_roll : bool = bool(data.get("is_roll_relic", false))
	_relic_shop.buy_to_slot(idx, is_roll)
	_build_passive_slots()
	_build_roll_relic_slots()


func _sell_relic(data: Dictionary) -> void:
	var relic_id : String = str(data.get("item_id", ""))
	if relic_id == "": return
	var price : int = RelicShop.get_relic_sell_price(relic_id)
	var st : String = str(data.get("slot_type", ""))
	if st == "roll_relic_slot":
		var idx : int = int(data.get("roll_index", -1))
		if idx >= 0: GameState.remove_roll_relic_at_slot(idx)
	else:
		var idx : int = int(data.get("passive_index", -1))
		if idx >= 0: _context.remove_passive_at_slot(idx)
	_context.add_gold(price)
	_context.auto_save()
	SoundManager.play_select_sound()  # ★ v6.62j：出售反馈用 click 音效
	_show_detail_in_zone("出售遗物，获得 %d 金币" % price)
	_update_gold_display()
	_build_passive_slots()
	_build_roll_relic_slots()


func _on_open_sacrifice_ui():
	pass


func _trigger_sacrifice_confirm(u: UnitData):
	var melt_id : String = SacrificeHelper.get_melt_item_id(u.unit_name)
	var melt_data : ItemData = ItemManager.get_item_data(melt_id)
	var melt_name : String = melt_data.name if melt_data else "专属防具"
	var alive_count := 0
	for member in party:
		if not member.is_dead: alive_count += 1
		
	# ★ v6.56：标题一句 + 结构化奖励预览（图标/名字/数值分区分行），避免文字挤在一起
	var msg : String = "确定熔铸 %s？" % u.display_name
	if alive_count <= 1:
		msg += "\n（熔铸后全灭，本局将结束并返回营地）"
	var confirm_ui = Globals.show_confirm(self, msg, "熔铸", "取消",
		func(): _do_sacrifice(u, [], 0), func(): pass)
	if confirm_ui and melt_data:
		var qcolor : Color = UIConst.QUALITY_COLORS.get(melt_data.quality, Color.WHITE)
		confirm_ui.set_reward_detail(melt_data.icon, melt_name,
			SacrificeHelper.describe_melt_reward(melt_id), qcolor)


func _do_sacrifice(u: UnitData, _armors_ignored: Array, _discard_count: int):
	var result : Dictionary = SacrificeHelper.do_sacrifice(party, u)

	_sync_all()

	var alive_count := 0
	for member in party:
		if not member.is_dead:
			alive_count += 1
	if alive_count <= 0:
		GameState.abandon_and_return_to_camp()
		return

	_build_unit_columns()
	_build_pending_slots()
	_update_gold_display()

	var msg : String = "已熔铸：%s\n获得：%s（请在上方领取）" % [
		u.display_name, result.get("melt_item_name", "专属防具")
	]
	_show_detail_in_zone(msg)
	SoundManager.play_select_sound()  # ★ v5.13：熔铸成功播放拖拽成功音效

	_schedule_build_ui()


func _equip_pending_reward(data: Dictionary, target: Control):
	var pending_idx : int = data.get("pending_idx", -1)
	var pending_src : String = data.get("pending_src", "sacrifice")
	var target_type : String = target.get_meta("slot_type", "")
	var unit_idx : int = target.get_meta("unit_idx", -1)
	if unit_idx < 0 or unit_idx >= party.size(): return
	var u : UnitData = party[unit_idx]
	if u.is_dead: return

	var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice"
		else GameState.pending_forge_rewards)
	if pending_idx < 0 or pending_idx >= list.size(): return
	var inst : ItemInstance = list[pending_idx]
	if inst == null: return
	var item_data = ItemManager.get_item_data(inst.item_id)
	if not item_data: return

	if target_type == "armor":
		if item_data.type != "armor": return
		var slot_idx : int = target.get_meta("slot_idx", -1)
		if slot_idx < 0 or slot_idx >= u.armor_slots.size(): return

		if _is_slot_occupied_by_unsellable(unit_idx, slot_idx):
			_show_detail_in_zone("该槽位是不可丢弃的熔铸防具，无法覆盖")
			return

		var old_inst : ItemInstance = u.armor_slots[slot_idx]
		if old_inst:
			var old_data = ItemManager.get_item_data(old_inst.item_id)
			if old_data and not old_data.no_sell:
				var sell_price = old_inst.get_sell_price()
				_context.add_gold(sell_price)
				_show_detail_in_zone("替换下旧防具，自动折算 %d 金币" % sell_price)

		u.armor_slots[slot_idx] = inst
	else:
		return

	list.erase(inst)
	SaveManager.auto_save()

	_build_unit_columns()
	_build_pending_slots()
	_sync_all()
	_update_gold_display()

	if current_tab == "sacrifice" and shop_container and shop_container.visible:
		_build_sacrifice_panel()


func _discard_pending_reward(data: Dictionary):
	var pending_idx : int = data.get("pending_idx", -1)
	var pending_src : String = data.get("pending_src", "sacrifice")
	var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice"
		else GameState.pending_forge_rewards)
	if pending_idx < 0 or pending_idx >= list.size(): return
	var inst : ItemInstance = list[pending_idx]
	if inst == null: return
	var idata : ItemData = ItemManager.get_item_data(inst.item_id)
	if idata != null and idata.no_sell:
		_show_detail_in_zone("熔铸防具不可丢弃，请装备到单位防具槽")
		return
	
	var sell_price = inst.get_sell_price()
	if sell_price > 0:
		_context.add_gold(sell_price)
		_update_gold_display()
		_show_detail_in_zone("已出售 %s，获得 %d 金币" % [idata.name if idata else inst.item_id, sell_price])

	list.erase(inst)
	SaveManager.auto_save()
	_build_pending_slots()

	if current_tab == "sacrifice" and shop_container and shop_container.visible:
		_build_sacrifice_panel()


func _create_unit_icon(unit: UnitData, unit_idx: int) -> Control:
	# ★ v6.50：改用 create_unit_avatar_button（Button）——纯 Control 的 mouse_entered
	#   在本场景不稳定，Button 的悬停信号可靠（遗物/技能也是 Button，故它们能显示信息）。
	# ★ v6.62p：赋能单位头像统一用 overlord 图片
	var wrapper = UnitDataManager.create_unit_avatar_button(unit.unit_name, Vector2(54, 54), Vector2(48, 48), unit.is_empowered)
	wrapper.set_meta("slot_type", "unit_icon")
	wrapper.set_meta("unit_idx", unit_idx)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.focus_mode = Control.FOCUS_NONE
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP

	wrapper.mouse_entered.connect(_on_unit_hover_entered.bind(unit_idx))
	wrapper.mouse_exited.connect(_on_unit_hover_exited)

	return wrapper


func _disable_button(btn: Button):
	btn.disabled = true
	btn.modulate = Color(0.4, 0.4, 0.4, 1)


func _on_unit_hover_entered(unit_idx: int) -> void:
	if unit_idx < 0 or unit_idx >= party.size(): return
	var unit : UnitData = party[unit_idx]
	_detail.show_unit(unit)


func _on_unit_hover_exited() -> void:
	_detail.clear_zone()


func _create_item_button(inst: ItemInstance, slot_type: String, unit_idx: int, slot_idx: int, shop_dir: int = 0, is_shop: bool = false) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.clip_contents = false 
	
	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)
	
	if inst:
		var base_name : String = _get_item_name(inst)
		var data = ItemManager.get_item_data(inst.item_id)
		if data and data.icon:
			btn.icon = data.icon
			btn.text = ""
		else:
			btn.text = base_name

		# ★ v5.1：防具图标背后 24x24 Build 方向色块（取第一个标签配色）
		if slot_type == "armor" or (data and data.type == "armor"):
			_draw_build_tag_backdrop(btn, data)

		var dir = inst.direction
		if is_shop:
			dir = shop_dir
			btn.set_meta("shop_direction", shop_dir)

		if dir != Direction.Value.NONE:
			_draw_direction_badges(btn, dir)
			btn.tooltip_text = "可在铁匠铺单件放入重roll方向"

		# v5.3：连通成功仅由黄色边框标识，已移除星标（边框已足够醒目）

	else:
		btn.text = "空"
	btn.set_meta("slot_type", slot_type)
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	btn.set_meta("item_id", inst.item_id if inst else "")
	if inst and inst.item_id != "":
		var item_id : String = inst.item_id
		# ★ v5.1：商店商品悬浮显示本次 roll 出的词条（词条在实例上，不在 ItemData 上）
		var affixes_snapshot : Array = (inst.affixes.duplicate(true) if inst.affixes else [])
		# ★★★ v5.0：armor 类型走连通组感知 hover ★★★
		if slot_type == "armor" and unit_idx >= 0 and slot_idx >= 0:
			btn.mouse_entered.connect(_on_armor_hover_entered.bind(item_id, unit_idx, slot_idx))
			btn.mouse_exited.connect(_on_armor_hover_exited)
		elif slot_type == "shop_item":
			btn.mouse_entered.connect(_on_shop_item_hover_entered.bind(item_id, affixes_snapshot))
			btn.mouse_exited.connect(_on_button_hover_exited)
		else:
			btn.mouse_entered.connect(_on_button_hover_entered.bind(item_id))
			btn.mouse_exited.connect(_on_button_hover_exited)
	return btn


## v5.1：防具图标背后画 24x24 Build 方向方块（标签配色，统一读 UIConst）
## 注意：Button.icon 属于按钮自身绘制，子节点无法垫到它后面；
## 因此把图标转成 TextureRect 子节点，先加色块再加图标，保证色块在图标下层。
func _draw_build_tag_backdrop(btn: Button, data):
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = UIConst.NO_TAG_COLOR
	if data != null and not data.tags.is_empty():
		var first_tag : String = str(data.tags[0])
		backdrop.color = UIConst.BUILD_TAG_COLORS.get(first_tag, UIConst.NO_TAG_COLOR)
	# v5.4：与按钮/图标统一 20x20 基准（±10），勿用 24x24——否则箭尖贴看不见的外框
	backdrop.set_anchors_preset(Control.PRESET_CENTER)
	backdrop.offset_left = -10
	backdrop.offset_right = 10
	backdrop.offset_top = -10
	backdrop.offset_bottom = 10
	btn.add_child(backdrop)

	# 图标移到独立 TextureRect 子节点，叠在色块之上
	if btn.icon:
		var icon_texture : Texture2D = btn.icon
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# v5.4：与色块/箭头严格共用「按钮中心 20x20」基准（±10）。
		# 原 PRESET_FULL_RECT 会铺满按钮实际尺寸，商店按钮在 GridContainer 中被拉伸时
		# 图标尺寸 ≠ 色块/箭头固定尺寸，箭尖便偏离图标边角。
		icon_rect.set_anchors_preset(Control.PRESET_CENTER)
		icon_rect.offset_left = -10
		icon_rect.offset_right = 10
		icon_rect.offset_top = -10
		icon_rect.offset_bottom = 10
		btn.add_child(icon_rect)
		# 拖拽预览仍要拿到原图标
		btn.set_meta("_item_icon", icon_texture)
		btn.icon = null


## ★ v6.62g：把图标作为固定 20×20 的 TextureRect 子节点挂到按钮上，
##   与防具槽 `_draw_build_tag_backdrop` 的图标绘制口径一致，统一图标显示大小；
##   同时保留原图标到 meta 供拖拽预览使用。按钮自身 stylebox 不动（空槽边框不变）。
func _attach_fixed_icon(btn: Button, icon_texture: Texture2D) -> void:
	if btn == null or icon_texture == null: return
	var icon_rect := TextureRect.new()
	icon_rect.texture = icon_texture
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.set_anchors_preset(Control.PRESET_CENTER)
	icon_rect.offset_left = -10
	icon_rect.offset_right = 10
	icon_rect.offset_top = -10
	icon_rect.offset_bottom = 10
	btn.add_child(icon_rect)
	btn.set_meta("_item_icon", icon_texture)


func _draw_direction_badges(_btn: Button, _dir: int):
	# v6.5：箭头连通功能已移除，不再绘制方向箭头
	pass


func _apply_icon_button_style(btn: Button):
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.clip_text = true
	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)


func _create_talent_button(inst: TalentInstance, unit_idx: int, slot_idx: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_TINY, Style.BTN_ITEM_SIZE)
	_apply_icon_button_style(btn)
	btn.set_meta("slot_type", "talent")
	btn.set_meta("unit_idx", unit_idx)
	btn.set_meta("slot_idx", slot_idx)
	if inst and inst.is_active:
		# ★ v6.4：地图界面技能已锁定，拖拽/丢弃已在 Drag 与 drop 层拦截；
		#   只对已装备技能轻度灰化，保留图标可读性；空槽不加任何色调，口径同防具空槽。
		if current_mode == Mode.MAP:
			btn.modulate = Color(0.72, 0.72, 0.75, 1.0)
		var data : TalentData = TalentManager.get_talent_data(inst.talent_id)
		if data:
			var icon : Texture2D = TalentManager.get_talent_icon(inst.talent_id)
			if icon:
				btn.icon = icon
				btn.text = ""
			else:
				btn.text = data.display_name.substr(0, mini(2, data.display_name.length()))
			btn.set_meta("talent_id", inst.talent_id)
			btn.mouse_entered.connect(_on_talent_hover_entered.bind(inst.talent_id))
			btn.mouse_exited.connect(_on_talent_hover_exited)
		else:
			# ★ v6.68b：空槽与防具槽同款——不加灰化、不换色调，仅显示「空」。
			btn.text = "空"
			btn.add_theme_font_size_override("font_size", Style.FONT_SMALL)
			btn.set_meta("talent_id", "")
	else:
		btn.text = "空"
		btn.add_theme_font_size_override("font_size", Style.FONT_SMALL)
		btn.set_meta("talent_id", "")
	return btn


func _build_passive_slots():
	if not relic_container: return
	for child in relic_container.get_children(): relic_container.remove_child(child); child.free()
	var passives : Array = _context.get_passives()
	for i in range(MAX_PASSIVE_SLOTS):
		var inst : Variant = passives[i] if i < passives.size() else null
		var btn : Button = _create_passive_button(inst, i)
		relic_container.add_child(btn)
	# ★ 团队遗物槽与上方防具槽逐列对齐：等布局完成后读取每个单位列ArmorGroup的槽x
	call_deferred("_deferred_align_relic_slots")

## ★ v6.62d：ScrollContainer / VBox 在帧末才完成布局，call_deferred 一帧不够。
##   等几帧读到稳定的 global_position 后再对齐，并监听尺寸变化重算，防止父级重排后漂移。
func _deferred_align_relic_slots() -> void:
	for _i in range(3):
		await get_tree().process_frame
		if not is_instance_valid(self): return
	_align_relic_slots_to_armor()
	if not _relic_align_connected:
		_relic_align_connected = true
		if unit_container and is_instance_valid(unit_container):
			unit_container.resized.connect(_on_relic_layout_changed)
		if roll_relic_container and is_instance_valid(roll_relic_container):
			roll_relic_container.resized.connect(_on_relic_layout_changed)

func _on_relic_layout_changed() -> void:
	call_deferred("_align_relic_slots_to_armor")

## ★ 团队遗物槽：x 逐列对齐每个单位列防具槽第一行，y 对齐防具遗物槽那一行
func _align_relic_slots_to_armor() -> void:
	if not relic_container or not unit_container: return
	# 1) 每个单位列的 ArmorGroup 只取第一行两个槽的 global x（从左到右按单位遍历顺序）
	var armor_xs : Array = []
	_collect_armor_slots_x(unit_container, armor_xs)
	if armor_xs.is_empty(): return
	# 2) 目标 y = 防具遗物区已生成槽的 global y（没有则用容器 y）
	var target_y : float = 0.0
	if roll_relic_container:
		if roll_relic_container.get_child_count() > 0:
			var first : Node = roll_relic_container.get_child(0)
			target_y = (first as Control).global_position.y if first is Control else roll_relic_container.global_position.y
		else:
			target_y = roll_relic_container.global_position.y
	# 3) 逐槽对齐；防具列数不足时，多余槽在最后一个 x 后按槽宽顺延，保证 6 槽都可见
	var slot_w : float = float(Style.BTN_ITEM_SIZE.x)
	var step : float = float(Style.ITEM_GRID_GAP) + slot_w
	var last_x : float = armor_xs[armor_xs.size() - 1] if not armor_xs.is_empty() else 0.0
	var children := relic_container.get_children()
	for i in range(children.size()):
		var btn : Control = children[i] as Control
		if btn == null: continue
		btn.visible = true
		var x : float = float(armor_xs[i]) if i < armor_xs.size() else (last_x + step * float(i - armor_xs.size() + 1))
		btn.global_position = Vector2(x, target_y)

## ★ 每个 ArmorGroup 只取前两个（第一行）槽的 global x，双列布局正好对应团队遗物 6 槽
func _collect_armor_slots_x(node: Node, out: Array) -> void:
	if node == null: return
	if node.name == "ArmorGroup" and node is GridContainer:
		var taken : int = 0
		for c in node.get_children():
			if c is Control:
				out.append((c as Control).global_position.x)
				taken += 1
				if taken >= 2: break
		return
	for c in node.get_children():
		_collect_armor_slots_x(c, out)


## ★ v6.59：老虎机专用遗物槽（4 个），空槽显示老虎机图标作占位提示
func _build_roll_relic_slots() -> void:
	if not roll_relic_container: return
	for child in roll_relic_container.get_children():
		roll_relic_container.remove_child(child); child.free()
	var relics : Array = GameState.get_roll_relics()
	var count : int = 4
	for i in range(count):
		var inst : Variant = relics[i] if i < relics.size() else null
		var btn : Button = _create_passive_button(inst, i)
		btn.set_meta("slot_type", "roll_relic_slot")
		btn.set_meta("roll_index", i)
		# ★ 不再用老虎机图标占位：空槽沿用_create_passive_button的方块+"空"字，与其他槽视觉统一
		roll_relic_container.add_child(btn)


## ★ v6.62q：只读遗物槽——把 hover/pressed/focus 样式覆盖为 normal，
##   消除一切"可点击"视觉反馈（外观变静态展示块），但保留 mouse_filter=STOP
##   让 mouse_entered/exited 悬停详情照常工作。从祖先节点取项目主题 normal 样式。
func _apply_readonly_button_visual(btn: Button) -> void:
	var normal_sb : StyleBox = get_theme_stylebox("normal", "Button")
	if normal_sb == null:
		normal_sb = load(Config.PATHS.STYLEBOX_8BIT_BUTTON) as StyleBox
	if normal_sb == null: return
	for state in ["hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, normal_sb)


func _create_passive_button(inst: Variant, slot_index: int) -> Button:
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	btn.clip_text = true
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.set_meta("slot_type", "passive_slot")
	btn.set_meta("passive_index", slot_index)
	# ★ v6.72o：统一槽位外观——团队遗物槽/防具抽取遗物槽此前用主题默认按钮样式，
	#   比防具槽/天赋槽多出一层圆角灰底。改为与 _make_aura_icon_btn 等一致的 StyleBoxEmpty，
	#   全状态（normal/hover/pressed/focus/disabled）去底，视觉与其它插槽统一。
	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 0
	empty_sb.content_margin_right = 0
	empty_sb.content_margin_top = 0
	empty_sb.content_margin_bottom = 0
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty_sb)

	if inst == null:
		btn.text = "空"
		btn.set_meta("item_id", "")
	elif inst is ItemInstance:
		var item_inst : ItemInstance = inst
		var data : Dictionary = RelicManager.get_relic_data(item_inst.item_id)
		if not data.is_empty():
			var prefix : String = "★ " if GameState.is_relic_refined(item_inst.item_id) else ""
			var icon = data.get("icon")
			if icon is Texture2D:
				# ★ v6.62g：与防具槽同款「固定 20×20 图标子节点」，避免 Button.icon 受默认 stylebox margin 影响而显小
				_attach_fixed_icon(btn, icon)
				btn.text = ""
			else:
				btn.text = prefix + data.get("name", "?")
			btn.set_meta("item_id", item_inst.item_id)
			btn.mouse_entered.connect(_on_relic_hover_entered.bind(item_inst.item_id))
			btn.mouse_exited.connect(_on_relic_hover_exited)
		else:
			btn.text = "?"
			btn.set_meta("item_id", "")
	elif inst is Dictionary and inst.get("type", "") == "aura":
		var aid : String = inst.get("aura_id", "")
		var ad : Dictionary = AuraManager.get_aura(aid)
		var icon = ad.get("icon")
		if icon is Texture2D:
			_attach_fixed_icon(btn, icon)
			btn.text = ""
		else:
			btn.text = "✦ " + ad.get("name", aid)
		btn.set_meta("item_id", "")
		btn.set_meta("aura_id", aid) 
		btn.modulate = Color(0.7, 0.9, 1.0)
	else:
		btn.text = "空"
		btn.set_meta("item_id", "")

	# ★ v6.62q：装备配置（MAP）界面是纯查看页——遗物槽只能悬停显示信息，不可点击。
	#   这些槽本就没有 pressed 信号，点击唯一效果是 start_drag（MAP 已在起点拦截）。
	#   这里进一步消除 Button 的 hover/pressed 视觉反馈，让外观像静态展示块，
	#   避免"看起来能点"。mouse_entered/exited 保持启用，悬停详情正常显示。
	#   ★ 不用 disabled：Godot 4 中 disabled Button 不接收鼠标事件，会连带丢失悬停信息。
	#   魂栈（FORGE）等需要拖拽遗物出售的模式不动，仍保持可交互。
	if current_mode == Mode.MAP:
		btn.set_meta("readonly_hover_only", true)
		_apply_readonly_button_visual(btn)
	return btn


func _inst_slots(inst: ItemInstance) -> int:
	return 0 if inst == null else 1

func _used_slots_of(unit: UnitData) -> int:
	var used : int = 0
	for slot in unit.armor_slots:
		if slot != null: used += 1
	return used

func _used_slots_excluding(unit: UnitData, exclude_slots: Array) -> int:
	var used : int = 0
	for i in range(unit.armor_slots.size()):
		if i in exclude_slots: continue
		if unit.armor_slots[i] != null: used += 1
	return used

func _can_equip_armor_to(unit_idx: int, item_id: String, exclude_slot_idx: int = -1) -> bool:
	if unit_idx < 0 or unit_idx >= party.size(): return false
	if item_id == "": return true
	var unit : UnitData = party[unit_idx]
	if exclude_slot_idx >= 0 and exclude_slot_idx < unit.armor_slots.size():
		return true
	for s in unit.armor_slots:
		if s == null: return true
	return false

func _is_slot_occupied_by_unsellable(unit_idx: int, slot_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= party.size(): return false
	if slot_idx < 0 or slot_idx >= party[unit_idx].armor_slots.size(): return false
	var inst : ItemInstance = party[unit_idx].armor_slots[slot_idx]
	if inst == null: return false
	var idata : ItemData = ItemManager.get_item_data(inst.item_id)
	return idata != null and idata.no_sell

func _inst_slots_for_id(_item_id: String) -> int:
	return 1

func _get_item_name(inst: ItemInstance) -> String:
	if not inst: return ""
	var data : ItemData = ItemManager.get_item_data(inst.item_id)
	return data.name if data else inst.item_id


func _is_valid_drop(data: Dictionary, target: Control) -> bool:
	# ★ v6.22：地图装备配置界面为纯查看页，拒绝任何拖放落点（防具/遗物/光环等）
	if current_mode == Mode.MAP:
		return false
	# ★ v6.56：魂栈（熔铸/休整）模式——完全参考地图装备界面的"只读"口径：
	#   遗物/防具/单位一律不可拖拽移动或交换；唯一例外是"拖拽单位到献祭熔铸槽"
	#   （unit_icon → SacrificeDropZone）。注意这不是单位间换位（unit_icon→unit_icon）。
	var forge_ctx : bool = (current_mode == Mode.FORGE or is_shop_rest_mode())
	if forge_ctx:
		# ★ v6.62c：魂栈商店格子拖到遗物槽购买（团队→团队槽，老虎机→老虎机槽）
		if current_mode == Mode.FORGE and data.get("slot_type", "") == "relic_shop_item":
			var is_roll : bool = bool(data.get("is_roll_relic", false))
			var tt : String = target.get_meta("slot_type", "")
			if is_roll:
				return tt == "roll_relic_slot"
			return tt == "passive_slot"
		# ★ v6.59：魂栈遗物商店——团队/老虎机遗物可拖到出售区换金币
		if current_mode == Mode.FORGE and target == discard_zone \
				and data.get("slot_type", "") in ["passive_slot", "roll_relic_slot"]:
			return true
		if data.get("slot_type", "") == "unit_icon" and target.name == "SacrificeDropZone":
			var fidx : int = data.get("unit_idx", -1)
			if fidx >= 0 and fidx < party.size():
				return not party[fidx].is_dead
			return false
		return false
	var source_type : String = data["slot_type"]
	var target_type : String = target.get_meta("slot_type", "")
	var discard : bool = target == discard_zone

	if source_type == "unit_icon":
		if target.name == "SacrificeDropZone":
			var uidx = data.get("unit_idx", -1)
			if uidx >= 0 and uidx < party.size():
				return not party[uidx].is_dead
			return false
		return target_type == "unit_icon"

	if discard:
		if source_type == "armor":
			var uidx : int = data.get("unit_idx", -1)
			var sidx : int = data.get("slot_idx", -1)
			if uidx >= 0 and uidx < party.size() and sidx >= 0 and sidx < party[uidx].armor_slots.size():
				var inst : ItemInstance = party[uidx].armor_slots[sidx]
				if inst != null:
					var idata : ItemData = ItemManager.get_item_data(inst.item_id)
					if idata != null and idata.no_sell:
						return false
		elif source_type == "pending_reward":
			var pidx : int = data.get("pending_idx", -1)
			var psrc : String = data.get("pending_src", "sacrifice")
			var plist : Array = (GameState.pending_sacrifice_rewards if psrc == "sacrifice"
				else GameState.pending_forge_rewards)
			if pidx >= 0 and pidx < plist.size():
				var pinst : ItemInstance = plist[pidx]
				if pinst != null:
					var pdata : ItemData = ItemManager.get_item_data(pinst.item_id)
					if pdata != null and pdata.no_sell:
						return false

	if source_type in ["aura_shop", "aura_equipped"]:
		if target_type == "passive_slot":
			var tgt_idx = target.get_meta("passive_index", -1)
			var passives = _context.get_passives()
			if tgt_idx >= 0 and tgt_idx < passives.size() and passives[tgt_idx] == null:
				return true
		return false

	if source_type == "talent" and target_type == "library_talent":
		return true

	var tgt_uidx : int = target.get_meta("unit_idx", -1)
	if tgt_uidx >= 0 and tgt_uidx < party.size():
		if party[tgt_uidx].is_dead:
			return false
	var src_uidx : int = data.get("unit_idx", -1)
	if src_uidx >= 0 and src_uidx < party.size():
		if party[src_uidx].is_dead:
			return false

	if source_type == "pending_reward":
		if discard: return true
		if target_type == "forge_slot":
			return _forge.is_valid_forge_drop(data, target)
		if target_type != "armor": return false
		var tu_p : int = target.get_meta("unit_idx", -1)
		if tu_p < 0 or tu_p >= party.size(): return false
		if party[tu_p].is_dead: return false
		var pending_idx : int = data.get("pending_idx", -1)
		var pending_src : String = data.get("pending_src", "sacrifice")
		var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice"
			else GameState.pending_forge_rewards)
		if pending_idx < 0 or pending_idx >= list.size(): return false
		var inst : ItemInstance = list[pending_idx]
		if inst == null: return false
		var idata = ItemManager.get_item_data(inst.item_id)
		if not idata: return false
		if target_type == "armor":
			if idata.type != "armor": return false
			var ts_p : int = target.get_meta("slot_idx", -1)
			if ts_p < 0 or ts_p >= party[tu_p].armor_slots.size(): return false
			if _is_slot_occupied_by_unsellable(tu_p, ts_p): return false
			var need_p : int = _inst_slots(inst)
			var used_p : int = _used_slots_excluding(party[tu_p], [ts_p])
			return used_p + need_p <= party[tu_p].max_armor_slots
		return false

	if source_type == "passive_slot":
		if target_type == "passive_slot": return true
		if discard: return true
		return false
	if target_type == "passive_slot":
		return false

	if current_mode == Mode.FORGE and current_tab != "arena_shop":
		return _forge.is_valid_forge_drop(data, target)
	if is_shop_rest_mode() and current_tab == "arena_forge":
		return _forge.is_valid_forge_drop(data, target)

	if current_mode == Mode.DEPLOY:
		if discard: return false
		if source_type == "library_talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		if source_type == "talent" and target_type == "talent": return _talent.check_talent_compatibility(data, target)
		return false

	if current_mode == Mode.MAP:
		if discard:
			if source_type == "armor": return true
			return false
		if source_type == "armor" and target_type == "armor":
			return _check_armor_swap_budget(data, target)
		# 技能词条已锁定：不接受任何技能拖入/交换
		return false

	var is_shop_ctx = (
		(current_mode == Mode.FORGE and current_tab == "arena_shop")
		or (is_shop_rest_mode() and current_tab == "arena_shop")
	)
	if is_shop_ctx:
		if discard:
			if source_type in ["shop_item", "library_talent", "talent"]: return false
			return true
		if source_type == "shop_item":
			var item_data : ItemData = data.get("item_data")
			if not item_data: return false
			var tu2 : int = target.get_meta("unit_idx", -1)
			var ts2 : int = target.get_meta("slot_idx", -1)
			if item_data.type == "armor":
				if target_type != "armor": return false
				if tu2 < 0 or ts2 < 0: return false
				if _is_slot_occupied_by_unsellable(tu2, ts2): return false
				return _can_equip_armor_to(tu2, item_data.id, ts2)
			return false
		if source_type == "armor" and target_type == "armor":
			return _check_armor_swap_budget(data, target)
		return false
	return false


func _check_armor_swap_budget(data: Dictionary, target: Control) -> bool:
	var su : int = data.get("unit_idx", -1)
	var ss : int = data.get("slot_idx", -1)
	var tu : int = target.get_meta("unit_idx", -1)
	var ts : int = target.get_meta("slot_idx", -1)
	if su < 0 or ss < 0 or tu < 0 or ts < 0: return false
	if su == tu and ss == ts: return false
	return true


# v5.5：target 参数去掉 Control 类型注解。此函数经 call_deferred 延迟执行，
# 拖放过程中 UI 可能重建（_schedule_build_ui / build_forge_slots）导致按钮被 queue_free，
# freed 实例在消息队列做 Object→Control 转换时报
# "Cannot convert argument 2 from Object to Object"，这里改为执行前显式校验。
func _execute_drop(data: Dictionary, target) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not (target is Control):
		return
	var source_type : String = data.get("slot_type", "")
	var target_type : String = target.get_meta("slot_type", "")

	# ★ v6.56：魂栈模式只放行"拖单位入献祭熔铸槽"，与 _is_valid_drop 口径一致
	if (current_mode == Mode.FORGE or is_shop_rest_mode()):
		# ★ v6.62c：商店格子拖到遗物槽 → 购买并装入
		if current_mode == Mode.FORGE and source_type == "relic_shop_item":
			_buy_relic_by_drag(data)
			return
		# ★ v6.59：遗物拖到出售区 → 售出换金币
		if current_mode == Mode.FORGE and target == discard_zone \
				and source_type in ["passive_slot", "roll_relic_slot"]:
			_sell_relic(data)
			return
		if not (source_type == "unit_icon" and target.name == "SacrificeDropZone"):
			return

	if source_type == "unit_icon" and target.name == "SacrificeDropZone":
		var uidx = data.get("unit_idx", -1)
		if uidx >= 0 and uidx < party.size():
			_trigger_sacrifice_confirm(party[uidx])
		return

	if source_type == "pending_reward" and target_type == "forge_slot":
		var pending_idx : int = data.get("pending_idx", -1)
		var pending_src : String = data.get("pending_src", "sacrifice")
		var list : Array = (GameState.pending_sacrifice_rewards if pending_src == "sacrifice" else GameState.pending_forge_rewards)
		if pending_idx >= 0 and pending_idx < list.size():
			var inst : ItemInstance = list[pending_idx]
			list.erase(inst)
			
			var empty_idx = -1
			for i in range(_forge.forge_slots.size()):
				if _forge.forge_slots[i] == null:
					empty_idx = i
					break
			if empty_idx >= 0:
				_forge.forge_slots[empty_idx] = {"inst": inst, "origin_unit": -1, "origin_slot": -1}
				_forge.build_forge_slots()
				_build_pending_slots()
				_sync_all()
				_schedule_build_ui()
		return

	if source_type == "unit_icon" and target_type == "unit_icon":
		var su : int = data.get("unit_idx", -1)
		var tu : int = target.get_meta("unit_idx", -1)
		if su >= 0 and tu >= 0 and su != tu:
			_apply_unit_swap(su, tu)
		return

	if source_type == "aura_shop" and target_type == "passive_slot":
		_buy_and_equip_aura(data, target); return
	if source_type == "aura_equipped" and target_type == "passive_slot":
		_swap_aura(data, target); return

	if source_type == "pending_reward" and target_type == "armor":
		_equip_pending_reward(data, target); return
	if source_type == "pending_reward" and target == discard_zone:
		_discard_pending_reward(data); return

	if source_type == "passive_slot":
		if target == discard_zone: _discard_passive(data); return
		if target_type == "passive_slot": _swap_passives(data, target); return

	if current_mode == Mode.FORGE and current_tab != "arena_shop":
		_forge.execute_forge_drop(data, target); return
	if is_shop_rest_mode() and current_tab == "arena_forge":
		_forge.execute_forge_drop(data, target); return

	var discard : bool = target == discard_zone

	if discard and source_type == "talent": _talent.execute_talent_remove(data); return
	if source_type == "talent" and target_type == "library_talent":
		_talent.execute_talent_remove(data); return
	if discard: _discard_item(data); return
	if source_type == "shop_item": _shop.buy_shop_item(data, target); return
	if source_type == "library_talent" and target_type == "talent": _talent.execute_talent_drop(data, target); return
	if source_type == "talent" and target_type == "talent": _talent.execute_talent_drop(data, target); return
	if source_type == "armor" and target_type == "armor": _shop.swap_armor(data, target)


func _buy_and_equip_aura(data: Dictionary, target: Control):
	var aid : String = data.get("aura_id", "")
	var cost : int = data.get("aura_price", 0)
	var tgt_idx : int = target.get_meta("passive_index", -1)
	if tgt_idx < 0 or aid == "": return

	var passives : Array = _context.get_passives()
	if passives[tgt_idx] != null: return

	if not SoulFireManager.spend(cost):
		return

	_context.set_passive_at_slot(tgt_idx, {"type": "aura", "aura_id": aid})
	GameState.remove_aura_candidate(aid)
	_sync_all()
	_update_gold_display()
	_schedule_build_ui()
	_show_detail_in_zone("已购买并装备光环：%s" % AuraManager.get_display_name(aid))

func _swap_aura(data: Dictionary, target: Control):
	var aid : String = data.get("aura_id", "")
	var tgt_idx : int = target.get_meta("passive_index", -1)
	if tgt_idx < 0: return
	
	var passives : Array = _context.get_passives()
	var src_idx : int = -1
	for i in range(passives.size()):
		var p : Variant = passives[i]
		if p is Dictionary and p.get("type", "") == "aura" and p.get("aura_id", "") == aid:
			src_idx = i
			break
			
	if src_idx == -1 or src_idx == tgt_idx: return
	if passives[tgt_idx] != null: return
	
	_context.set_passive_at_slot(tgt_idx, passives[src_idx])
	_context.set_passive_at_slot(src_idx, null)
	SoundManager.play_select_sound()
	_sync_all()
	_schedule_build_ui()


func _discard_passive(data: Dictionary):
	var idx : int = data.get("passive_index", -1)
	if idx < 0: return
	_context.remove_passive_at_slot(idx)
	_sync_all(); _schedule_build_ui()


func _swap_passives(data: Dictionary, target: Control):
	var src_idx : int = data.get("passive_index", -1)
	var tgt_idx : int = target.get_meta("passive_index", -1)
	if src_idx < 0 or tgt_idx < 0 or src_idx == tgt_idx: return
	var passives : Array = _context.get_passives()
	var temp : Variant = passives[src_idx]
	_context.set_passive_at_slot(src_idx, passives[tgt_idx])
	_context.set_passive_at_slot(tgt_idx, temp)
	_sync_all(); _schedule_build_ui()


func _discard_item(data: Dictionary):
	var source_type : String = data["slot_type"]
	var unit_idx : int = data["unit_idx"]
	var slot_idx : int = data["slot_idx"]
	var u : UnitData = party[unit_idx]
	
	if source_type == "armor":
		var inst : ItemInstance = u.armor_slots[slot_idx]
		if inst != null:
			var sell_price = inst.get_sell_price()
			if sell_price > 0:
				_context.add_gold(sell_price)
				_show_detail_in_zone("出售防具，获得 %d 金币" % sell_price)
		u.armor_slots[slot_idx] = null
	elif source_type == "talent": 
		_talent.discard_talent(data)
		
	_update_gold_display()
	_build_unit_columns()
	_sync_all(); _schedule_build_ui()


func _on_confirm_pressed():
	if not _check_pending_before_leave():
		return

	if current_mode == Mode.FORGE: _forge.on_forge_craft_pressed(); return
	if current_mode == Mode.ARENA_REST:
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return

	var target_units : Array = _context.get_units()
	var target_map : Dictionary = {}
	for tu in target_units:
		var key : String = "%s|%s" % [tu.unit_name, tu.display_name]
		target_map[key] = tu
		
	_sync_all()

	if _context.get_context_id() == "main_game" and selected_units.size() > 0:
		var main_data : Dictionary = UnitDataManager.get_unit_data(selected_units[0])
		var faction : String = main_data.get("faction", "王国")
		_context.set_pending_faction(faction)

	_context.on_confirm()
	_context.auto_save()
	var canvas_layer : Node = get_parent()
	if canvas_layer: canvas_layer.queue_free()
	else: queue_free()


func _copy_party_data():
	party.clear()
	var units : Array = _context.get_units()
	for unit_data in units:
		var ud : UnitData = unit_data
		party.append(UnitData.from_dict(ud.to_dict()))
	
	_ensure_armor_directions()


func _ensure_armor_directions():
	for u in party:
		for slot in u.armor_slots:
			if slot == null: continue
			if slot.direction != Direction.Value.NONE: continue
			var data = ItemManager.get_item_data(slot.item_id)
			if data and data.enable_direction:
				slot.direction = Direction.roll_birth_direction(data.quality)


func _clear_container(container: Node):
	if not container: return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _sync_all():
	var target_units : Array = _context.get_units()
	var target_map : Dictionary = {}
	for tu in target_units:
		var key : String = "%s|%s" % [tu.unit_name, tu.display_name]
		target_map[key] = tu

	for u in party:
		var armor_target : int = clampi(u.max_armor_slots, 0, 10)
		u.max_armor_slots = armor_target
		u.armor_slots.resize(armor_target)
		var talent_target : int = maxi(u.talent_slots.size(), 1)
		u.talent_slots.resize(talent_target)

		var key : String = "%s|%s" % [u.unit_name, u.display_name]
		if not target_map.has(key):
			continue
		var tu : UnitData = target_map[key]
		if u.is_dead and tu.is_dead:
			continue
		
		tu.armor_slots = _clone_inst_array(u.armor_slots)
		tu.max_armor_slots = u.max_armor_slots
		tu.talent_slots = _clone_talent_array(u.talent_slots)
		tu.is_dead = u.is_dead
		tu.advanced_talent_id = u.advanced_talent_id
		tu.level = u.level
		tu.attack_range_bonus = u.attack_range_bonus
		tu.static_physical_penetration = u.static_physical_penetration
		tu.static_magic_penetration = u.static_magic_penetration
		tu.static_crit_damage_bonus = u.static_crit_damage_bonus
		tu.max_hp = u.max_hp
		tu.hit_points = u.hit_points
		tu.strength = u.strength
		tu.dexterity = u.dexterity
		tu.intelligence = u.intelligence
		tu.faith = u.faith
		tu.move_range = u.move_range

static func _clone_item_inst(src: ItemInstance) -> ItemInstance:
	if src == null: return null
	var inst = ItemInstance.new()
	inst.item_id = src.item_id
	inst.count = src.count
	inst.upgrade_level = src.upgrade_level
	inst.affixes = src.affixes.duplicate(true)
	inst.direction = src.direction
	return inst

static func _clone_inst_array(src: Array) -> Array:
	var out : Array = []
	for s in src: out.append(_clone_item_inst(s))
	return out

static func _clone_talent_inst(src) -> TalentInstance:
	if src == null or not (src is TalentInstance): return null
	var inst := TalentInstance.new()
	inst.talent_id = src.talent_id
	inst.current_stack = src.current_stack
	inst.is_ready = src.is_ready
	inst.is_active = src.is_active
	inst.cooldown_remaining = src.cooldown_remaining
	return inst

static func _clone_talent_array(src: Array) -> Array:
	var out : Array = []
	for s in src: out.append(_clone_talent_inst(s))
	return out


func _switch_tab(tab: String):
	SoundManager.play_select_sound()
	
	if not _check_pending_before_leave():
		return
	if current_tab == tab: return
	
	if (current_mode == Mode.FORGE or is_shop_rest_mode()) and current_tab == "arena_forge":
		var unresolved : int = _forge.return_all_forge_slots()
		_build_unit_columns()
		if unresolved > 0:
			_show_detail_in_zone("有 %d 件防具无法归还，请先腾出空间" % unresolved)
			return
			
	current_tab = tab
	_update_tab_style()
	_clear_container(shop_container)
	var is_forge_tab : bool = (tab == "arena_forge")
	if not is_forge_tab:
		_forge.cleanup()
		
	var show_pending : bool = false
	if current_mode == Mode.FORGE or is_shop_rest_mode():
		if tab != "arena_shop":
			show_pending = true
			
	if show_pending:
		_ensure_pending_section()
		_build_pending_slots()
		if _pending_section:
			_pending_section.visible = true
	else:
		if _pending_section and is_instance_valid(_pending_section):
			var p = _pending_section.get_parent()
			if p: p.remove_child(_pending_section)
			_pending_section.queue_free()
			_pending_section = null
			_pending_container = null

	match tab:
		"talent": _talent.build_talent_grid(shop_container)
		"arena_shop":
			if shop_manager and shop_manager.get_shop_items().is_empty():
				shop_manager.generate_shop_items()
			_shop.build_shop_items()
		"arena_forge":
			_forge.build_forge_slots()
		"sacrifice":
			_build_sacrifice_panel()
		"aura":
			_build_aura_panel()
	shop_container.visible = true
	
	reset_btn.visible = (tab == "arena_shop")
	if reset_btn.visible and shop_manager:
		reset_btn.text = "刷新商店 (" + str(shop_manager.get_reset_cost()) + "G)"
		
	discard_zone.visible = (tab != "arena_forge" and tab != "sacrifice" and tab != "aura" and current_mode != Mode.DEPLOY and current_mode != Mode.MAP)
	
	_refresh_bottom_buttons()
	_refresh_upgrade_shop_btn()


func _force_relayout():
	await get_tree().process_frame
	if not is_inside_tree(): return
	if shop_scroll:
		shop_scroll.scroll_vertical = 0
		shop_scroll.scroll_horizontal = 0
		shop_scroll.queue_sort()
	if shop_container:
		shop_container.queue_sort()


func _refresh_bottom_buttons():
	var in_sacrifice : bool = (current_tab == "sacrifice")
	var in_arena_forge : bool = (current_tab == "arena_forge")
	var in_aura : bool = (current_tab == "aura")

	if in_sacrifice or in_arena_forge or in_aura:
		close_btn.disabled = true
		close_btn.modulate = Color(0.5, 0.5, 0.5)
	else:
		close_btn.disabled = false
		close_btn.modulate = Color.WHITE

	if current_mode == Mode.ARENA_REST:
		close_btn.visible = false
		confirm_btn.visible = true
		confirm_btn.text = "出发"
		if current_tab == "arena_forge" or current_tab == "aura":
			confirm_btn.disabled = true
			confirm_btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			confirm_btn.disabled = false
			confirm_btn.modulate = Color.WHITE
		discard_zone.visible = (current_tab != "arena_forge")
	elif current_mode == Mode.MAP_SHOP_REST:
		close_btn.visible = true
		close_btn.text = "继续探索"
		confirm_btn.visible = false
		discard_zone.visible = (current_tab != "arena_forge")


func _update_tab_style():
	if not weapon_tab_btn or not talent_tab_btn:
		return

	if current_mode == Mode.ARENA_REST:
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
		if _aura_tab_btn: _aura_tab_btn.visible = false
		return

	if current_mode == Mode.MAP_SHOP_REST:
		weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
		talent_tab_btn.modulate = Color.WHITE if current_tab == "arena_forge" else Color(0.5, 0.5, 0.5)
		if sacrifice_tab_btn:
			sacrifice_tab_btn.modulate = Color.WHITE if current_tab == "sacrifice" else Color(0.5, 0.5, 0.5)
		if _aura_tab_btn:
			_aura_tab_btn.modulate = Color.WHITE if current_tab == "aura" else Color(0.5, 0.5, 0.5)
		return

	if current_mode == Mode.FORGE:
		weapon_tab_btn.visible = false
		talent_tab_btn.visible = false
		if _aura_tab_btn: _aura_tab_btn.visible = false
		if sacrifice_tab_btn:
			sacrifice_tab_btn.visible = true
			sacrifice_tab_btn.modulate = Color.WHITE
		return

	weapon_tab_btn.modulate = Color.WHITE if current_tab == "arena_shop" else Color(0.5, 0.5, 0.5)
	talent_tab_btn.modulate = Color.WHITE if current_tab == "talent" else Color(0.5, 0.5, 0.5)
	if sacrifice_tab_btn: sacrifice_tab_btn.visible = false
	if _aura_tab_btn: _aura_tab_btn.visible = false


func _input(event: InputEvent):
	if _has_active_confirm_ui(): return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _detail != null and _detail.has_hover():
			Globals.toggle_info_mode()
			_detail.refresh()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# ★ v6.41：落位模式不走拖拽，让防具槽 Button 的 pressed 正常触发
		if current_mode == Mode.ARMOR_ROLL:
			return
		var mouse_pos : Vector2 = get_global_mouse_position()
		var btn : Control = _drag._find_control_at_position(mouse_pos)
		# ★ v6.62q：只读悬停槽（MAP 遗物槽）——点击不触发任何拖拽，直接吞掉
		if btn and bool(btn.get_meta("readonly_hover_only", false)):
			get_viewport().set_input_as_handled()
			return
		if btn and (btn is Button or btn.get_meta("slot_type", "") == "unit_icon"):
			_drag.start_drag(btn)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drag.end_drag()
	elif event is InputEventMouseMotion:
		if _drag.is_dragging: _drag.update_drag_preview()


func _process(_delta):
	if _drag.is_dragging: _drag.update_drag_preview()


func _show_buy_failure_message(reason: String):
	var msg : String = ""
	match reason:
		"not_enough_gold": msg = "金币不足！"
		"empty_slot": msg = "该商品已被购买"
		"invalid_index": msg = "无效的商品位置"
		_: msg = "购买失败：" + reason
	Globals.show_confirm(self, msg, "确定", "", func(): pass, func(): pass, false)


func _schedule_build_ui():
	if _build_ui_pending: return
	_build_ui_pending = true
	call_deferred("_do_build_ui")


func _do_build_ui():
	_build_ui_pending = false
	if _is_closing: return
	_build_ui()


func _has_active_confirm_ui() -> bool:
	for child in get_children():
		if child is CanvasLayer:
			var script : Script = child.get_script()
			if script and script.resource_path.ends_with("ConfirmUI.gd"): return true
	return false


func _build_shop_items(): 
	_shop.build_shop_items()

func _build_weapon_grid(container: Container): 
	_shop.build_weapon_grid(container)

func _on_reset_shop_pressed():
	SoundManager.play_select_sound()  # ★ v6.62f：刷新按钮点击反馈
	# ★ v6.59：魂栈遗物商店刷新走独立逻辑
	if current_mode == Mode.FORGE and _relic_shop != null:
		_on_relic_shop_reset()
		return
	_shop_direction_cache.clear()
	_shop.on_reset_shop_pressed()

func _build_talent_grid(container: Container): 
	_talent.build_talent_grid(container)

func _get_talent_display_unit_type() -> String: 
	return _talent._get_talent_display_unit_type()

func _use_context_units() -> Array: 
	return _talent._use_context_units()

func _check_talent_compatibility(data: Dictionary, target: Control) -> bool:
	return _talent.check_talent_compatibility(data, target)

func _is_talent_already_equipped(talent_id: String, exclude_unit_idx: int = -1, exclude_slot_idx: int = -1) -> bool:
	return _talent.is_talent_already_equipped(talent_id, exclude_unit_idx, exclude_slot_idx)

func _get_unit_with_talent(talent_id: String) -> String:
	return _talent.get_unit_with_talent(talent_id)

func _is_talent_equipped_anywhere(talent_id: String) -> bool:
	return _talent.is_talent_equipped_anywhere(talent_id)

func show_item_detail(item_id: String): _detail.show_item(item_id, [], true)
func hide_item_detail(): _detail.clear_zone()
func _on_button_hover_entered(item_id: String): _detail.on_button_hover_entered(item_id)

## v5.1：商店商品悬浮——把实例上的词条传给详情面板
func _on_shop_item_hover_entered(item_id: String, affixes: Array):
	if _detail:
		_detail.show_item(item_id, affixes)
func _on_button_hover_exited(): _detail.on_button_hover_exited()
func _on_talent_hover_entered(talent_id: String): _detail.on_talent_hover_entered(talent_id)
func _on_aura_hover_entered(aura_id: String) -> void:
	if _detail:
		_detail.show_aura(aura_id)
func _on_aura_hover_exited() -> void:
	if _detail:
		_detail.clear_zone()
func _on_talent_hover_exited(): _detail.on_talent_hover_exited()
func _on_relic_hover_entered(relic_id: String): _detail.on_relic_hover_entered(relic_id)
func _on_relic_hover_exited(): _detail.on_relic_hover_exited()
func _show_detail_in_zone(text: String): _detail.show_in_zone(text)
func _clear_detail_zone(): _detail.clear_zone()


func _show_craft_result(result : Dictionary):
	var lines : Array = []
	if result.get("is_recipe", false):
		lines.append("=== 图纸合成 ===")
	else:
		var score : int = result.get("input_score", 0)
		lines.append("=== 通用合成（评分 %d）===" % score)
		if result.get("lucky", false):
			lines.append("★ 幸运暴击！品质 +1")

	for item_id in result["item_ids"]:
		var data = ItemManager.get_item_data(item_id)
		if data:
			lines.append("★ " + data.name)
	lines.append("品质：" + _quality_cn(result["quality"]))
	if result.get("bonus_count", 0) > 0:
		lines.append("[额外] 产出 ×%d" % result["bonus_count"])
	_show_detail_in_zone("\n".join(lines))


func _quality_cn(q : String) -> String:
	match q:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return q


func _ensure_upgrade_shop_btn():
	if _upgrade_shop_btn and is_instance_valid(_upgrade_shop_btn):
		return
	if not reset_btn: return

	_upgrade_shop_btn = Style.create_styled_button(Style.FONT_LARGE, Vector2(100, 16))
	_upgrade_shop_btn.name = "UpgradeShopBtn" 
	_upgrade_shop_btn.custom_minimum_size = Vector2(0, 16)
	_upgrade_shop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_shop_btn.size_flags_vertical = Control.SIZE_SHRINK_END 
	_upgrade_shop_btn.clip_text = true
	_upgrade_shop_btn.pressed.connect(_on_upgrade_shop_pressed)
	
	right_container.add_child(_upgrade_shop_btn)
	var reset_idx : int = reset_btn.get_index()
	right_container.move_child(_upgrade_shop_btn, reset_idx)


func _refresh_upgrade_shop_btn():
	if not _upgrade_shop_btn or not is_instance_valid(_upgrade_shop_btn):
		return
	if not shop_manager:
		_upgrade_shop_btn.visible = false
		return

	var is_shop_tab : bool = (
		(current_mode == Mode.FORGE and current_tab == "arena_shop")
		or (is_shop_rest_mode() and current_tab == "arena_shop")
	)
	if not is_shop_tab:
		_upgrade_shop_btn.visible = false
	else:
		_upgrade_shop_btn.visible = true
		var lv : int = shop_manager.get_shop_level()
		var cost : int = shop_manager.get_upgrade_cost()
		if cost < 0:
			_upgrade_shop_btn.text = "商店 Lv%d（满级）" % lv
			_upgrade_shop_btn.disabled = true
			_upgrade_shop_btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			_upgrade_shop_btn.text = "升级商店 Lv%d→%d（%dG）" % [lv, lv + 1, cost]
			var afford : bool = _context.get_gold() >= cost
			_upgrade_shop_btn.disabled = not afford
			_upgrade_shop_btn.modulate = Color.WHITE if afford else Color(1.0, 0.6, 0.6)


func _on_upgrade_shop_pressed():
	if not shop_manager: return
	if not shop_manager.upgrade_shop():
		_show_buy_failure_message("not_enough_gold")
		return
	SoundManager.play_select_sound()
	_update_gold_display()
	_schedule_build_ui()


func _create_advanced_talent_button(unit: UnitData, unit_idx: int) -> Button:
	# ★ v6.68d：转职技能空槽与防具/普通技能空槽统一——字号 FONT_SMALL、文案「空」、不加灰化。
	var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
	_apply_icon_button_style(btn)
	btn.set_meta("slot_type", "advanced_talent")
	btn.set_meta("unit_idx", unit_idx)
	# 已获得转职技能后保持锁定（无 pressed 回调）；空槽不禁用，外观与其他空槽一致。
	btn.disabled = unit.advanced_talent_id != ""

	if unit.advanced_talent_id == "":
		btn.text = "空"
		return btn

	var data : TalentData = TalentManager.get_talent_data(unit.advanced_talent_id)
	if not data:
		btn.text = "?"
		btn.modulate = Color(0.5, 0.5, 0.5, 1)
		return btn

	var icon : Texture2D = TalentManager.get_talent_icon(unit.advanced_talent_id)
	if icon:
		btn.icon = icon
		btn.text = ""
	else:
		btn.text = data.display_name.substr(0, mini(2, data.display_name.length()))

	btn.set_meta("talent_id", unit.advanced_talent_id)
	btn.mouse_entered.connect(_on_talent_hover_entered.bind(unit.advanced_talent_id))
	btn.mouse_exited.connect(_on_talent_hover_exited)
	return btn


func _setup_forge_narrative_ui() -> void:
	if not _forge_enter_done:
		_forge_enter_done = true
		call_deferred("_trigger_forge_enter")


func _trigger_forge_enter() -> void:
	if not is_inside_tree():
		return
	var ctx := {
		"npc_id": "forge",
		"current_day": GameState.current_day,
		"npc_interact_count": StoryManager.get_npc_interact_count("forge"),
	}
	StoryManager.trigger("forge_enter", ctx)


func _swap_units_cyclic(unit_idx: int):
	if unit_idx < 0 or unit_idx >= party.size(): return
	if party.size() <= 1: return

	var next_idx : int = (unit_idx + 1) % party.size()
	_apply_unit_swap(unit_idx, next_idx)


func _apply_unit_swap(a: int, b: int):
	if a == b: return
	if a < 0 or a >= party.size(): return
	if b < 0 or b >= party.size(): return

	if party[a].is_dead or party[b].is_dead:
		Globals.show_confirm(self, "已阵亡的单位无法交换", "确定", "",
			func(): pass, func(): pass, false)
		return

	SoundManager.play_select_sound()

	var name_a : String = party[a].display_name if party[a].display_name != "" else party[a].unit_name
	var name_b : String = party[b].display_name if party[b].display_name != "" else party[b].unit_name

	var temp = party[a]
	party[a] = party[b]
	party[b] = temp

	_refresh_connectivity()
	_build_unit_columns.call_deferred()
	_sync_all.call_deferred()
	_schedule_build_ui.call_deferred()

	_show_detail_in_zone("已交换单位位置：%s ↔ %s" % [name_a, name_b])


func _on_claim_all_pending():
	var all_pending : Array = []
	for inst in GameState.pending_sacrifice_rewards:
		all_pending.append({"inst": inst, "src": "sacrifice"})
	for inst in GameState.pending_forge_rewards:
		all_pending.append({"inst": inst, "src": "forge"})

	if all_pending.is_empty(): return

	var sold_gold : int = 0
	var kept_count : int = 0

	for entry in all_pending:
		var inst : ItemInstance = entry["inst"]
		var data : ItemData = ItemManager.get_item_data(inst.item_id)
		if not data: continue

		var new_price : int = inst.get_sell_price()
		var is_unsellable : bool = data.no_sell
		var placed : bool = false

		for u in party:
			if u.is_dead: continue
			for i in range(u.armor_slots.size()):
				if u.armor_slots[i] == null:
					u.armor_slots[i] = inst
					placed = true
					break
			if placed: break

		if not placed:
			var worst_u : UnitData = null
			var worst_idx : int = -1
			var worst_price : int = 999999

			for u in party:
				if u.is_dead: continue
				for i in range(u.armor_slots.size()):
					var old_inst : ItemInstance = u.armor_slots[i]
					if old_inst:
						var old_data = ItemManager.get_item_data(old_inst.item_id)
						if old_data and old_data.no_sell:
							continue
						var p : int = old_inst.get_sell_price()
						if p < worst_price:
							worst_price = p
							worst_u = u
							worst_idx = i

			if worst_u != null and not is_unsellable and new_price >= worst_price:
				_context.add_gold(worst_price)
				sold_gold += worst_price
				worst_u.armor_slots[worst_idx] = inst
				placed = true

		if not placed:
			if is_unsellable:
				kept_count += 1
				continue
			_context.add_gold(new_price)
			sold_gold += new_price

		if entry["src"] == "sacrifice":
			GameState.pending_sacrifice_rewards.erase(inst)
		else:
			GameState.pending_forge_rewards.erase(inst)

	_build_unit_columns()
	_build_pending_slots()
	_update_gold_display()
	_sync_all()

	if sold_gold > 0 and kept_count > 0:
		_show_detail_in_zone("一键领取完成。\n替换/多余装备已折算为 %d 金币。\n★ 有 %d 件熔铸防具因无处装备，已保留在待领取区。" % [sold_gold, kept_count])
	elif kept_count > 0:
		_show_detail_in_zone("一键领取完成。\n★ 有 %d 件熔铸防具因无处装备，已保留在待领取区。" % kept_count)
	elif sold_gold > 0:
		_show_detail_in_zone("一键领取完成。\n替换/多余装备已折算为 %d 金币。" % sold_gold)
	else:
		_show_detail_in_zone("已领取所有装备。")
	SoundManager.play_select_sound()
