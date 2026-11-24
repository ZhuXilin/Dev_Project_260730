extends CanvasLayer
const BuildUI = preload("res://function/script/build/BuildUI.gd")
const SlotMachineUI = preload("res://function/script/build/SlotMachineUI.gd")
const EquipCfg = preload("res://function/script/equipmentconfig/EquipmentConfig.gd")
const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")
## ============================================================
##  ArmorRollUI — v6 战后防具 roll + 领取台
## ============================================================
##  战后结算确认后弹出：
##   - 花金币 roll 防具（100G 起，每次 +50G，离开界面重置）
##   - 可花金币升级 roll 品质等级
##   - 领取台：装备 / 并入 / 覆盖 / 放弃
##   - 满流派槽时必须覆盖或放弃；覆盖二次确认
##  战斗不再直接送防具，所有防具都从这里获取。
## ============================================================

signal closed
signal skill_finished  # ★ v6.57：技能 Roll 模式完成

const FS_TITLE: int = 10
const FS_BODY: int = 7
const FS_SMALL: int = 6

var _gold_color := Color(0.98, 0.75, 0.25)
var _dim_color := Color(0.55, 0.55, 0.58)

var _roll_count: int = 0
var _quality_level: int = 0
var _current: Dictionary = {}          # 当前待领取防具 {item_id,quality,school,name,mechanic}
## ★ v6.62z：封顶二选一相关（离开结算 UI 销毁即重置，天然"每场限 1 次"）
var _last_roll_cost: int = 0           # 本次抽取实际花费，封顶时全额退还
var _inject_used_this_session: bool = false  # 本场是否已用过「注入词条」

# ★ v6.57：防具模式 UI 节点来自 ArmorRollUI.tscn 场景（原全代码生成）
@onready var _root: Panel = $Root
@onready var _gold_label: Label = $Root/Margin/VBox/GoldLabel
@onready var _cost_label: Label = $Root/Margin/VBox/BtnRow/CostLabel
@onready var _upgrade_btn: Button = $Root/Margin/VBox/BtnRow/UpgradeBtn
@onready var _close_btn: Button = $Root/Margin/VBox/CloseBtn
@onready var _action_row: HBoxContainer = $Root/Margin/VBox/ActionRow
@onready var _result_box: VBoxContainer = $Root/Margin/VBox/Scroll/ResultBox
@onready var _msg: Label = $Root/Margin/VBox/Msg
@onready var _title_label: Label = $Root/Margin/VBox/Title
@onready var _machine_slot: Control = $Root/Margin/VBox/MachineSlot
@onready var _roll_relic_row: HBoxContainer = $Root/Margin/VBox/RollRelicRow
var _machine = null
var _closing: bool = false   # ★ 防两个关闭按钮同帧重复触发
var _revealing: bool = false # ★ v6.58：roll 结果展示停留中，锁定一切操作

# ★ Arena 统一：注入单单位 + 独立金币（主线不调用则完全走 GameState/EconomyManager）
var _arena_mode: bool = false
var _unit_override: Array = []
var _get_gold_cb: Callable = Callable()
var _set_gold_cb: Callable = Callable()


## Arena 模式：用竞技场单单位与独立金币，界面与主线完全共用。
## 必须在 add_child 之前调用（_ready 会 _build_ui/_refresh）。
func setup_for_arena(unit: UnitData, get_gold: Callable, set_gold: Callable) -> void:
	_arena_mode = true
	_unit_override = [unit] if unit != null else []
	_get_gold_cb = get_gold
	_set_gold_cb = set_gold


func _gold() -> int:
	if _arena_mode and _get_gold_cb.is_valid():
		return maxi(0, int(_get_gold_cb.call()))
	return EconomyManager.get_temp_gold()


func _spend(amount: int) -> void:
	if _arena_mode and _set_gold_cb.is_valid():
		_set_gold_cb.call(maxi(0, _gold() - amount))
	else:
		EconomyManager.subtract_temp_gold(amount)


func _get_units() -> Array:
	if _arena_mode:
		return _unit_override
	return GameState.party


func _ready() -> void:
	layer = 30
	# ★ v6.56：Roll 界面共用 BGM（关闭后由目标场景音乐覆盖恢复）
	MusicManager.play_roll_music()
	if _skill_mode:
		# ★ v6.57：只建 UI；show_step 由 setup_skill 调用（那时信号已连接，避免空池同步 emit 漏接）
		if _unit_row == null:
			_sk_build_ui()
	else:
		_build_ui()
		_refresh()


func _build_ui() -> void:
	# ★ v6.57：UI 结构已在 ArmorRollUI.tscn（Root/Margin/VBox 全节点），
	#   这里只补：样式、信号、动态文字、轮盘实例（SlotMachineUI 是自定义控件无法在 tscn 直接放）。
	_root.visible = true
	var root_sb := StyleBoxFlat.new()
	root_sb.bg_color = Color(0, 0, 0, 0)   # 透明，让场景背景图透出
	root_sb.set_border_width_all(0)
	root_sb.content_margin_left = 2.0
	root_sb.content_margin_right = 2.0
	_root.add_theme_stylebox_override("panel", root_sb)

	# 动态标题（竞技场/主线）
	_title_label.text = "竞技场 · 防具抽取" if _arena_mode else "战后 · 防具抽取"
	_title_label.add_theme_color_override("font_color", _gold_color)
	_gold_label.add_theme_color_override("font_color", Color.WHITE)
	_cost_label.add_theme_color_override("font_color", _gold_color)

	# 轮盘：代码创建（自定义控件）塞进场景的 MachineSlot 占位
	_machine = SlotMachineUI.new()
	_machine.custom_minimum_size = Vector2(0, 72)
	# ★ v6.59：缓速发条遗物——防具 roll 转速放慢（技能模式共用轮盘但不受影响）
	var sm: Dictionary = GameState.get_slot_machine_relic_effects()
	var slower := float(sm.get("roll_spin_slower", 0.0))
	if slower > 0.0:
		_machine.speed_scale = clampf(slower, 0.05, 1.0)
	_machine_slot.add_child(_machine)
	# ★ 必须铺满 MachineSlot，否则轮盘宽度塌成内容宽、内部居中整体贴左
	_machine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_machine.stopped.connect(_on_machine_stopped)
	_machine.started.connect(_on_spin_started)

	# ★ v6.62s：轮盘下方显示 4 个已装备老虎机遗物槽（有遗物显示自身图标），
	#   让玩家直观看到哪些遗物正在影响本次防具 roll。竞技场模式无队伍遗物，隐藏整行。
	_build_roll_relic_row()

	# 按钮样式 + 信号
	BuildUI.style_button(_upgrade_btn)
	_upgrade_btn.pressed.connect(_on_upgrade_quality)
	BuildUI.style_button(_close_btn)
	_close_btn.pressed.connect(_on_close)


## ★ v6.62s：填充轮盘下方的 4 个老虎机遗物槽（纯展示，有遗物显示自身图标）。
##   竞技场模式用单单位、不走队伍遗物，隐藏整行；主线按 GameState.get_roll_relics() 渲染。
func _build_roll_relic_row() -> void:
	if _roll_relic_row == null:
		return
	for c in _roll_relic_row.get_children():
		_roll_relic_row.remove_child(c)
		c.free()
	if _arena_mode:
		_roll_relic_row.visible = false
		return
	_roll_relic_row.visible = true
	var relics : Array = GameState.get_roll_relics()
	for i in range(4):
		# ★ v6.62t：与其他防具/遗物槽同款标准按钮——空槽显示「空」、有图标显示自身图标，
		#   大小 20×20、主题默认方块边框，不再自创 PanelContainer 样式。
		var btn : Button = Style.create_styled_button(Style.FONT_SMALL, Style.BTN_ITEM_SIZE)
		btn.expand_icon = true
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.clip_text = true
		btn.disabled = true  # 纯展示，不可点击（保留 mouse_filter=STOP 供 tooltip）
		var inst : Variant = relics[i] if i < relics.size() else null
		var item_id : String = ""
		if inst is ItemInstance:
			item_id = (inst as ItemInstance).item_id
		if item_id == "":
			btn.text = "空"
		else:
			var d : Dictionary = RelicManager.get_relic_data(item_id)
			var icon = d.get("icon")
			if icon is Texture2D:
				# 固定 20×20 TextureRect 子节点，口径同装备界面 _attach_fixed_icon
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
				btn.text = ""
			else:
				btn.text = str(d.get("name", "遗物")).substr(0, 2)
			btn.tooltip_text = "%s\n%s" % [str(d.get("name", item_id)), str(d.get("description", ""))]
		_roll_relic_row.add_child(btn)


## ★ v6.17：操作门控——转轮进行中 / 有待领取防具时，禁止离开与升级，
##   防止中途退出丢结果、或转动中改品质导致转轮池与品质不符。
func _update_action_buttons() -> void:
	var spinning: bool = (_machine != null and _machine.is_spinning())
	var has_pending: bool = not _current.is_empty()
	var locked: bool = spinning or has_pending or _revealing
	if _close_btn != null:
		_close_btn.disabled = locked
	# ★ 操作行：v6.44 放弃按钮已移入装备界面，此行保留为空容器兼容布局
	if _action_row != null:
		_action_row.visible = has_pending
	if _upgrade_btn != null:
		var up: int = BuildManager.get_upgrade_cost(_quality_level)
		_upgrade_btn.disabled = locked or up < 0 or _gold() < up


func _refresh() -> void:
	_update_action_buttons()
	var gold := _gold()
	# ★ 品质并入金币行，省一整行高度
	_gold_label.text = "金币：%d · 品质 %d/5（%s）" % [gold, _quality_level, _quality_desc()]
	var cost := BuildManager.get_roll_cost(_roll_count)
	_cost_label.text = "本次抽取 %dG" % cost
	_machine.set_start_enabled(gold >= cost)
	# ★ 金币不足提示移到结果区显示（见 _render_result），轮盘下方 Msg 不再占用
	var up := BuildManager.get_upgrade_cost(_quality_level)
	if up < 0:
		_upgrade_btn.text = "品质已满"
	else:
		_upgrade_btn.text = "升级品质（%dG）" % up
	# ★ disabled 由 _update_action_buttons 统一门控（含转动中/待领取锁定）

	_render_result()
	# ★ v6.38：结算态停留展示前后对比，不自动重滚；点轮盘"已停止·继续"才进下一轮
	if _current.is_empty():
		_prepare_spin()


func _prepare_spin() -> void:
	if _machine == null or _machine.is_spinning():
		return
	_machine.setup(BuildManager.get_armor_roll_pool(_quality_level, 8),
		"防具轮盘 · 下一次（%dG）" % BuildManager.get_roll_cost(_roll_count))


func _quality_desc() -> String:
	match _quality_level:
		0: return "common 为主"
		1: return "rare 概率提升"
		2: return "epic 概率提升"
		3: return "legendary 出现"
		4: return "高品几率大幅提升"
		_: return "legendary 高概率"


func _on_upgrade_quality() -> void:
	# ★ 转动中/待领取时禁止升级（防止转轮池与品质档位不一致、或结果丢失）
	if _machine != null and _machine.is_spinning():
		return
	if not _current.is_empty():
		_msg.text = "请先处理待领取的防具"
		return
	var up := BuildManager.get_upgrade_cost(_quality_level)
	if up < 0:
		return
	if _gold() < up:
		_msg.text = "金币不足"
		return
	_spend(up)
	_quality_level += 1
	_msg.text = "品质等级提升至 %d" % _quality_level
	_refresh()


func _on_spin_started() -> void:
	var cost := BuildManager.get_roll_cost(_roll_count)
	if _gold() < cost:
		_msg.text = "金币不足"
		_machine.request_stop()
		return
	_spend(cost)
	# ★ v6.62z：记录本次抽取实付，封顶二选一「返还金币」按此全额退回
	_last_roll_cost = cost
	# ★ v6.59：返利硬币遗物——roll 后按比例返还金币
	var rebate := BuildManager.get_roll_gold_rebate(cost)
	if rebate > 0:
		if _arena_mode and _set_gold_cb.is_valid():
			_set_gold_cb.call(_gold() + rebate)
		else:
			EconomyManager.add_temp_gold(rebate)
	_roll_count += 1
	_set_current({})
	# ★ v6.43：移除老虎机状态文字（点「停！」提示），轮盘自身已有按钮反馈
	_msg.text = ""
	_refresh()


## ★ v6.54：统一更新待落袋防具并即时落盘，避免异常退出丢失 roll 结果
func _set_current(value: Dictionary) -> void:
	_current = value.duplicate(true)
	GameState.resource_state.pending_armor_roll = _current.duplicate(true)
	SaveManager.auto_save()


func _on_machine_stopped(entry: Dictionary) -> void:
	if _skill_mode:
		_sk_on_machine_stopped(entry)
		return
	var iid := str(entry.get("item_id", ""))
	if iid == "":
		_msg.text = "抽取失败（防具池为空）"
		return
	_set_current({
		"item_id": iid,
		"quality": str(entry.get("quality", "common")),
		"school": str(entry.get("school", "")),
		"affixes": (entry.get("affixes", []) as Array).duplicate(),
		"name": str(entry.get("name", iid)),
		"mechanic": str(entry.get("mechanic", "")),
	})
	# ★ v6.58：roll 出结果后停留 0.5 秒（真实时间、不受倍速影响）展示中奖结果，
	#   期间轮盘保持停止画面、不接受操作（返回/放弃键已被 _update_action_buttons 因待领取锁定），
	#   之后才进入落袋界面。让玩家看清抽到了什么。
	_revealing = true
	var result_name : String = str(entry.get("name", iid))
	_msg.text = "抽到：%s" % result_name
	await get_tree().create_timer(0.5, true, false, true).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_revealing = false
	_msg.text = ""
	_refresh()
	_open_equipment_for_pick()


func _render_result() -> void:
	_update_action_buttons()   # ★ 放弃/覆盖取消后也要恢复离开按钮
	if _result_box == null:
		return
	for c in _result_box.get_children():
		c.queue_free()
	if _current.is_empty():
		# ★ 金币不足时把提示放到结果区（黄框位置），居中显示
		if _gold() < BuildManager.get_roll_cost(_roll_count):
			var hint := Label.new()
			hint.text = "金币不足，可点最下方「结束抽取」离开"
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.add_theme_font_size_override("font_size", FS_SMALL)
			hint.add_theme_color_override("font_color", _gold_color)
			hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_result_box.add_child(hint)
		return

	var school := str(_current.get("school", ""))
	var quality := str(_current.get("quality", "common"))
	var cap := BuildManager.get_quality_cap(quality)
	var school_color := BuildManager.get_school_color(school)
	var mech_txt := BuildManager.get_school_mechanic(school) if school != "" else "无流派·仅属性"

	# ★ v6.20：抽到的防具做成"流派徽标"卡——流派文字用流派色 + 同名色描边，
	#   玩家一眼认出这是什么流派，再对照下方单位的流派色决定落给谁。
	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_row.add_theme_constant_override("separation", 4)
	_result_box.add_child(card_row)

	# 流派徽标：填流派色的小方块
	var badge := ColorRect.new()
	badge.color = school_color if school != "" else Color(0.35, 0.35, 0.38)
	badge.custom_minimum_size = Vector2(8, 8)
	card_row.add_child(badge)

	var line := Label.new()
	# 名字去掉轮盘带来的【流派】前缀避免重复，流派单独一段强调
	var raw_name := str(_current.get("name", ""))
	var item_name := raw_name
	if school != "" and item_name.begins_with("【%s】" % school):
		item_name = item_name.substr(("【%s】" % school).length())
	line.text = "抽到 %s" % item_name
	line.add_theme_font_size_override("font_size", FS_BODY)
	line.add_theme_color_override("font_color", Color.WHITE)
	card_row.add_child(line)

	# 流派名 + 机制：统一用流派色，与下方单位流派标签同色对应
	var school_lbl := Label.new()
	school_lbl.text = ("【%s】Lv≤%d · %s" % [school, cap, mech_txt]) if school != "" else ("无流派 · 仅属性")
	school_lbl.add_theme_font_size_override("font_size", FS_BODY)
	school_lbl.add_theme_color_override("font_color", school_color)
	card_row.add_child(school_lbl)

	# ★ v6.41：点头像弹出装备配置全貌，再点防具槽落位
	var actions := Label.new()
	actions.text = "点击头像查看装备全貌，再点防具槽落位："
	actions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions.add_theme_font_size_override("font_size", FS_SMALL)
	_result_box.add_child(actions)

	var unit_row := HBoxContainer.new()
	unit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	unit_row.add_theme_constant_override("separation", 6)
	# ★ 收缩到内容宽度并居中，避免被 ScrollContainer 拉伸导致最右单位被裁
	unit_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_result_box.add_child(unit_row)

	for ud in _get_units():
		if ud == null:
			continue
		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.add_theme_constant_override("separation", 1)
		card.custom_minimum_size = Vector2(120, 0)
		var avatar := UnitDataManager.create_unit_avatar_button(
			ud.unit_name, Vector2(40, 40), Vector2(36, 36))
		avatar.disabled = ud.is_dead
		avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if ud.is_dead:
			avatar.modulate = Color(0.35, 0.35, 0.38)
		else:
			# ★ v6.41：点头像弹出只读 EquipmentConfig，让玩家看全貌后点防具槽落位
			avatar.pressed.connect(_open_equipment_for_pick)
		card.add_child(avatar)

		# ★ v6.22：avatar 正下方第一行就是"流派徽标 + 流派文字"（玩家要的当前在用流派）。
		#   用流派色色块 + 同名色文字，与顶部抽到防具的流派徽标同色对应。
		var mechs := BuildManager.get_unit_mechanisms(ud)
		var school_row := HBoxContainer.new()
		school_row.alignment = BoxContainer.ALIGNMENT_CENTER
		school_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		school_row.add_theme_constant_override("separation", 2)
		if mechs.is_empty():
			var none_mark := ColorRect.new()
			none_mark.color = Color(0.35, 0.35, 0.38)
			none_mark.custom_minimum_size = Vector2(7, 7)
			school_row.add_child(none_mark)
			var none_lbl := Label.new()
			none_lbl.text = "无流派"
			none_lbl.add_theme_font_size_override("font_size", FS_BODY)
			none_lbl.add_theme_color_override("font_color", _dim_color)
			school_row.add_child(none_lbl)
		else:
			for m in mechs:
				var mcolor: Color = m.get("color", Color.WHITE)
				var mark := ColorRect.new()
				mark.color = mcolor
				mark.custom_minimum_size = Vector2(7, 7)
				school_row.add_child(mark)
				var tag := Label.new()
				tag.text = "%s Lv%d" % [str(m.get("school", "")), int(m.get("level", 1))]
				tag.add_theme_font_size_override("font_size", FS_BODY)
				tag.add_theme_color_override("font_color", mcolor)
				school_row.add_child(tag)
		card.add_child(school_row)

		# 第二行：单位名 + 当前LV/最大LV + 当前/所需经验（普通色）
		var lv_txt : String = "Lv%d/%d" % [ud.level, BuildManager.LEVEL_CAP]
		if ud.level >= BuildManager.LEVEL_CAP:
			lv_txt += " MAX"
		else:
			lv_txt += "·%d/%d" % [ud.experience, BuildManager.exp_to_next_level(ud.level)]
		var name_lbl := Label.new()
		name_lbl.text = "%s %s" % [ud.display_name, lv_txt]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.custom_minimum_size = Vector2(120, 10)
		name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		name_lbl.clip_text = false
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_lbl.add_theme_font_size_override("font_size", FS_SMALL)
		name_lbl.add_theme_color_override("font_color", _dim_color if ud.is_dead else Color.WHITE)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_lbl)
		# ★ v6.38（A2）：落位结果预判——并入后 Lv / 觉醒 / 覆盖删几件，一眼可见
		var preview := Label.new()
		preview.text = _preview_placement(ud, school, cap)
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview.custom_minimum_size = Vector2(120, 10)
		preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		preview.add_theme_font_size_override("font_size", FS_SMALL)
		var is_merge : bool = preview.text.begins_with("并入")
		preview.add_theme_color_override("font_color",
			Color(0.55, 0.85, 1.0) if is_merge else Color(1.0, 0.75, 0.4))
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(preview)
		unit_row.add_child(card)


## ★ v6.38（A2）：预判落位结果，让"该给谁"一眼可见（不改动任何状态）。
## 口径与 BuildManager.apply_armor 完全一致。
func _preview_placement(ud: UnitData, school: String, cap: int) -> String:
	if ud == null:
		return ""
	if school == "" or not BuildManager.is_school(school):
		return "仅属性防具"
	var mechs: Array = BuildManager.get_unit_mechanisms(ud)
	for m in mechs:
		if str(m.get("school", "")) != school:
			continue
		var count: int = int(m.get("count", 1)) + 1
		var new_cap: int = maxi(int(m.get("cap", 1)), cap)
		var new_lv: int = mini(count, new_cap)
		return "并入 → Lv%d（上限 Lv%d）" % [new_lv, new_cap]
	var used: int = mechs.size()
	var slots: int = ud.max_armor_slots   # ★ v6.51：当前槽上限（随天数+1）
	if used < slots:
		return "觉醒 Lv1"
	# 槽满：覆盖会删掉该流派所有旧防具，统计件数
	var remove_n: int = 0
	for slot in ud.armor_slots:
		if slot == null: continue
		if BuildManager.get_school_of_instance(slot) == school:
			remove_n += 1
	return "覆盖 → 删 %d 件旧防具" % remove_n


func _on_discard() -> void:
	_set_current({})
	_msg.text = "已放弃该防具"
	_refresh()   # ★ 走 _refresh 才能重新装填转轮 + 恢复离开按钮（原来只 render 会卡在「已停止」）


## ★ v6.41：弹出只读 EquipmentConfig（防具落位模式），玩家看三单位装备全貌后点防具槽决定落位
var _pick_ui = null

## 关闭落位用的装备界面浮层（取消/落位/放弃/异常路径共用）
func _close_pick_ui() -> void:
	if _pick_ui != null and is_instance_valid(_pick_ui):
		_pick_ui.queue_free()
	_pick_ui = null


func _open_equipment_for_pick() -> void:
	if _current.is_empty():
		return
	if _pick_ui != null and is_instance_valid(_pick_ui):
		return
	var scene = load(Config.PATHS.EQUIPMENT_CONFIG)
	if scene == null:
		push_error("ArmorRollUI: 无法加载 EquipmentConfig 场景")
		# 降级：直接落位到第一个存活单位
		for ud in _get_units():
			if ud != null and not ud.is_dead:
				_on_place(ud)
				return
		return
	_pick_ui = scene.instantiate()
	get_tree().current_scene.add_child(_pick_ui)
	var panel = _pick_ui.get_node_or_null("MainPanel")
	if panel == null:
		push_error("ArmorRollUI: EquipmentConfig 缺少 MainPanel")
		_close_pick_ui()
		return
	if panel.has_signal("armor_slot_picked"):
		panel.armor_slot_picked.connect(_on_pick_unit)
	if panel.has_signal("armor_discard_requested"):
		panel.armor_discard_requested.connect(_on_pick_discard)
	# 落位模式：展示全貌，除防具槽外只读
	panel.init(_get_units(), SaveManager.current_slot, EquipCfg.Mode.ARMOR_ROLL, null)
	# ★ v6.43：把待落袋防具传给装备界面，高亮槽位 + 顶部展示
	if panel.has_method("set_pending_armor"):
		panel.set_pending_armor(_current)
	# 底层不再显示三 avatar 结果卡（信息已移到装备界面）
	for c in _result_box.get_children():
		c.queue_free()


func _on_pick_unit(unit_idx: int, slot_idx: int = -1) -> void:
	var units := _get_units()
	if unit_idx < 0 or unit_idx >= units.size():
		return
	var ud = units[unit_idx]
	if ud == null or ud.is_dead:
		return
	_on_place(ud, slot_idx)
	_close_pick_ui()


## ★ v6.44：在装备界面点"放弃防具"——放弃当前防具并关闭浮层
func _on_pick_discard() -> void:
	_on_discard()
	_close_pick_ui()


func _on_place(ud: UnitData, slot_idx: int = -1) -> void:
	var item_id := str(_current.get("item_id", ""))
	var quality := str(_current.get("quality", "common"))
	var affixes : Array = _current.get("affixes", [])
	var school : String = str(_current.get("school", ""))
	var cap : int = BuildManager.get_quality_cap(quality)
	var idata : ItemData = ItemManager.get_item_data(item_id)
	var icon : Texture2D = idata.icon if idata != null else null
	var color : Color = BuildManager.get_school_color(school) if school != "" else Color.WHITE
	var affix_text : String = _affix_summary(affixes)
	var mechs : Array = BuildManager.get_unit_mechanisms(ud)
	var used : int = mechs.size()
	var slots : int = ud.max_armor_slots

	# 点击槽位当前流派
	var slot_school : String = ""
	if slot_idx >= 0 and slot_idx < ud.armor_slots.size():
		var slot_inst = ud.armor_slots[slot_idx]
		if slot_inst != null:
			slot_school = BuildManager.get_school_of_instance(slot_inst)

	# 空槽且流派未满 → 纯觉醒，无取舍，直接落位不弹面板
	if slot_school == "" and used < slots:
		_do_apply_armor(ud, item_id, quality, affixes)
		return

	# ---- 选项A：强化（并入同流派升 Lv，词条不动） ----
	var same : Dictionary = {}
	for m in mechs:
		if str(m.get("school", "")) == school:
			same = m
			break
	var can_strengthen : bool = not same.is_empty()
	# ★ v6.62z：封顶判定与 BuildManager.apply_armor 一致——cap 取 max 后 Lv 未提升才算封顶
	var is_capped : bool = false
	if can_strengthen:
		var old_cap : int = maxi(int(same.get("cap", 1)), cap)
		var new_lv : int = mini(int(same.get("count", 1)) + 1, old_cap)
		is_capped = new_lv <= int(same.get("level", 1))
	var a_title : String = ""
	var a_detail : String = ""
	if can_strengthen:
		if is_capped:
			a_title = "强化 · %s 已满 Lv%d" % [school, int(same.get("level", 1))]
			a_detail = "Lv 已达上限，选「返还金币」或「注入词条」"
		else:
			var new_lv : int = mini(int(same.get("count", 1)) + 1, maxi(int(same.get("cap", 1)), cap))
			a_title = "强化 · %s Lv%d → Lv%d" % [school, int(same.get("level", 1)), new_lv]
			a_detail = "机制升 Lv，已有词条与搭配不变"
	else:
		a_title = "觉醒 · 新流派 %s Lv1" % school
		a_detail = "占 1 个流派槽，词条生效"
	var cb_a := func():
		if is_capped:
			_show_capped_choice(ud, slot_idx, school, affixes)
		else:
			_do_apply_armor(ud, item_id, quality, affixes)

	# ---- 选项B：转向（替换点击槽的流派，100% 继承等级，用新词条） ----
	if slot_school == "":
		for m in mechs:
			slot_school = str(m.get("school", ""))
			break
	var inherit_lv : int = 1
	for m in mechs:
		if str(m.get("school", "")) == slot_school:
			inherit_lv = maxi(1, int(m.get("level", 1)))
			break
	var b_title : String = "转向 · %s → %s Lv%d" % [slot_school if slot_school != "" else "空槽", school, inherit_lv]
	var b_detail : String = "100% 继承等级，新词条：" + affix_text
	var cb_b := func(): _do_overwrite_at(ud, slot_idx, slot_school, item_id, quality, affixes, inherit_lv)

	var confirm_parent : Node = get_tree().current_scene if get_tree() != null else self
	Globals.show_choice(confirm_parent,
		"抽到：%s  【%s】%s" % [str(_current.get("name", item_id)), school, quality],
		{"title": a_title, "detail": a_detail, "icon": icon, "color": color, "cb": cb_a},
		{"title": b_title, "detail": b_detail, "icon": icon, "color": color, "cb": cb_b},
		func(): _on_merge_cancelled())


## ★ v6.62z：强化封顶二选一——返还本次 roll 金币 / 注入新词条（Lv 不变）。
##   注入每场限 1 次；退款不受限（封顶本就该全额退，避免"白花钱"负反馈）。
func _show_capped_choice(ud: UnitData, slot_idx: int, school: String, affixes: Array) -> void:
	var refund_gold : int = _last_roll_cost
	var can_inject : bool = not _inject_used_this_session and not affixes.is_empty()
	var inject_text : String = "用新防具词条替换该槽旧词条，Lv 不变"
	if _inject_used_this_session:
		inject_text = "本场已用过注入，本次只能返还金币"
	var a_detail : String = "退回本次抽取花费 %dG（该流派已满级）" % refund_gold
	var b_detail : String = inject_text + "：" + _affix_summary(affixes)
	var refund_cb := func():
		_refund_capped_roll(refund_gold)
	var inject_cb := func():
		if not can_inject:
			_refund_capped_roll(refund_gold)
			return
		var n : int = BuildManager.inject_affixes(ud, school, affixes, slot_idx)
		if n <= 0:
			_msg.text = "该槽无可注入词条，已返还金币"
			_refund_capped_roll(refund_gold)
			return
		_inject_used_this_session = true
		SoundManager.play_get_item_sound()
		_msg.text = "已注入 %d 条新词条（Lv 不变，本场不再注入）" % n
		_set_current({})
		_refresh()
	var cancel_cb := func():
		_open_equipment_for_pick()
	var parent : Node = get_tree().current_scene if get_tree() != null else self
	Globals.show_choice(parent,
		"%s · %s 已满级，如何处理？" % [ud.display_name, school],
		{"title": "返还金币 +%dG" % refund_gold, "detail": a_detail, "cb": refund_cb},
		{"title": "注入词条（每场 1 次）" if can_inject else "注入词条（本场已用）", "detail": b_detail, "cb": inject_cb},
		cancel_cb)


func _refund_capped_roll(amount: int) -> void:
	if amount <= 0:
		return
	if _arena_mode and _set_gold_cb.is_valid():
		_set_gold_cb.call(_gold() + amount)
	else:
		EconomyManager.add_temp_gold(amount)
	SoundManager.play_get_item_sound()
	_msg.text = "该流派已满级，本次强化不消耗金币（已返还 %dG）。可转向其他槽，或放弃。" % amount
	_set_current({})
	_refresh()


func _affix_summary(affixes: Array) -> String:
	var parts : Array = []
	for a in affixes:
		if not (a is Dictionary):
			continue
		var d : Dictionary = AffixManager.get_affix(str(a.get("id", "")))
		var label : String = str(d.get("name", a.get("id", "?")))
		# ★ v6.62x：异常词条用「名称（一句话描述）」，其他词条保持「名称+数值」
		if d.has("abnormal"):
			parts.append("%s（%s）" % [label, AffixManager.format_description(str(a.get("id", "")), int(a.get("value", 0)))])
		else:
			parts.append("%s+%s" % [label, str(a.get("value", ""))])
	return " / ".join(parts) if not parts.is_empty() else "无词条"


## 取消选择后，重新打开装备界面让玩家另选落位单位
func _on_merge_cancelled() -> void:
	if not _current.is_empty():
		_open_equipment_for_pick()


func _do_apply_armor(ud: UnitData, item_id: String, quality: String, affixes: Array = []) -> void:
	var result := BuildManager.apply_armor(ud, item_id, quality, "", affixes)
	match str(result.get("result", "")):
		"awaken", "merge", "plain":
			SoundManager.play_get_item_sound()
			_set_current({})
			_refresh()
		"full":
			# ★ v6.55：槽位满时明确告知，防具保留在领取台，可换单位或覆盖/放弃
			_msg.text = "%s 的防具槽已满，请选其他单位或覆盖" % ud.display_name
		_:
			_msg.text = "无法落位"


## ★ v6.53：转向执行——替换点击槽的流派，100% 继承等级，新词条
func _do_overwrite_at(ud: UnitData, slot_idx: int, slot_school: String,item_id: String, quality: String, affixes: Array, inherit_lv: int) -> void:
	BuildManager.overwrite_at_slot(ud, slot_idx, slot_school, item_id, quality, affixes, inherit_lv)
	SoundManager.play_get_item_sound()
	_set_current({})
	_refresh()


func _on_close() -> void:
	if _closing:
		return
	# ★ v6.17：防御性门控——转轮进行中或有待领取防具时不允许离开
	#   （按钮已 disabled，这里再挡一层，防止信号绕过 UI 直接调用）
	if _machine != null and _machine.is_spinning():
		return
	if not _current.is_empty():
		_msg.text = "请在装备界面选择防具槽落位，或点「放弃防具」"
		return
	_closing = true
	SaveManager.auto_save()
	closed.emit()
	queue_free()


# ===== v6.57：技能 Roll 模式（SkillRollUI 合入） =====
var _unit_names: Array = []
var _skills: Array = []
var _index: int = 0
var _placed_skills: Array = []
var _current_skill: String = ""
var _title: Label = null
var _progress: Label = null
var _unit_row: HBoxContainer = null
var _skip_btn: Button = null
var _picked_icon: TextureRect = null
var _safe_picks: Array = []
var sk_roll_count: int = 3
var _skill_mode: bool = false

## ★ v6.57：在 add_child 之前调用，标记本实例进入技能 Roll 模式，
##   让 _ready 跳过防具 UI 构建（信号仍可在 add_child 后、setup_skill 前连接）
func set_skill_mode() -> void:
	_skill_mode = true
	# ★ v6.57：隐藏场景里的防具 UI（技能模式用代码自建 UI），保留背景图/底色
	var scene_root : Node = get_node_or_null("Root")
	if scene_root != null:
		scene_root.visible = false


func setup_skill(unit_names: Array, unit_data_override: Array = [], roll_count: int = 3) -> void:
	_unit_names = unit_names.duplicate()
	_unit_override = unit_data_override.duplicate()
	sk_roll_count = maxi(1, roll_count)
	# 保留一份原本的匹配结果作兜底；玩家停轮后可以改写当前这张
	# ★ v6.16：把注入的单位对象传给 roll_active_skills，用其自身槽位状态判空，
	#   避免 Arena 单单位因 GameState.party 同名单位占格被排除导致空池秒关。
	_skills = BuildManager.roll_active_skills(_unit_names, sk_roll_count, _unit_override)
	print("[SkillRollUI] setup: units=%s, skills=%d, override=%d" % [
		str(_unit_names), _skills.size(), _unit_override.size()])
	_index = 0
	_placed_skills.clear()
	_skill_mode = true
	# _ready 可能已建过 UI；避免重复构建
	if _unit_row == null:
		_sk_build_ui()
	_sk_show_step()




func _sk_build_ui() -> void:
	# ★ v6.57：底色与背景图已在共用场景 ArmorRollUI.tscn（BackgroundImage，同 EquipmentConfig 图）
	var root := Panel.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var root_sb := StyleBoxFlat.new()   # 透明面板，让场景背景图透出
	root_sb.bg_color = Color(0, 0, 0, 0)
	root.add_theme_stylebox_override("panel", root_sb)
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	_title = Label.new()
	_title.text = "开局技能抉择"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", FS_TITLE)
	_title.add_theme_color_override("font_color", _gold_color)
	vbox.add_child(_title)

	_progress = Label.new()
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.add_theme_font_size_override("font_size", FS_SMALL)
	_progress.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(_progress)

	# ★ 技能说明放到标题区（参考图的黄框位置）：图标 + 文字，和防具落袋卡同样的居中方式
	var pick_row := HBoxContainer.new()
	pick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# ★ 整行收缩到「图标+文字」的实际宽度再在 VBox 里居中，不要铺满画面两侧
	pick_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pick_row.add_theme_constant_override("separation", 6)
	pick_row.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(pick_row)

	# 技能图标（20x20，与装备界面落袋防具图标统一）
	_picked_icon = TextureRect.new()
	_picked_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picked_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picked_icon.custom_minimum_size = Vector2(20, 20)
	_picked_icon.visible = false
	pick_row.add_child(_picked_icon)

	_msg = Label.new()
	_msg.text = ""
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# ★ 关自动换行：让 Label 的最小宽度=整行文字宽度，HBox 才能收缩到内容宽并居中。
	#   若开 WORD_SMART 且宽度塌窄会逐字竖排；若给 EXPAND_FILL 又会把图标推到画面最左。
	_msg.autowrap_mode = TextServer.AUTOWRAP_OFF
	_msg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_msg.add_theme_font_size_override("font_size", FS_SMALL)
	_msg.add_theme_color_override("font_color", _dim_color)
	pick_row.add_child(_msg)

	_machine = SlotMachineUI.new()
	_machine.custom_minimum_size = Vector2(0, 96)
	_machine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_machine)
	_machine.stopped.connect(_on_machine_stopped)

	# ★ v6.57：移除"停下后选落位单位"提示文字（红框处，界面已足够直观）

	_unit_row = HBoxContainer.new()
	_unit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_unit_row.add_theme_constant_override("separation", 8)
	_unit_row.custom_minimum_size = Vector2(0, 46)
	vbox.add_child(_unit_row)

	_skip_btn = Button.new()
	_skip_btn.text = "无人可落位 · 重转"
	_skip_btn.add_theme_font_size_override("font_size", FS_SMALL)
	BuildUI.style_button(_skip_btn)
	_skip_btn.pressed.connect(_sk_on_skip)
	_skip_btn.visible = false
	vbox.add_child(_skip_btn)


func _sk_show_step() -> void:
	# ★ 进入新一次 roll：清掉上一件已落袋技能的图标与描述，避免残留到本次
	if _picked_icon != null:
		_picked_icon.texture = null
		_picked_icon.visible = false
	if _msg != null:
		_msg.text = ""
	_progress.text = "第 %d / %d 次" % [mini(_index + 1, _skills.size()), maxi(_skills.size(), 1)]
	if _index >= _skills.size():
		_sk_finish()
		return
	# ★ 死锁修复：没有可落位技能时绝不能用空池 setup（轮盘转不起来、
	#   本界面又无退出按钮）。直接跳过剩余次数并正常结束，进入地图。
	var entries: Array = _sk_build_entries()
	if entries.is_empty():
		push_warning("[SkillRollUI] 第 %d 次无可用技能，跳过本次及后续" % (_index + 1))
		_index = _skills.size()
		_sk_finish()
		return
	# ★ v6.22：池子只剩 1 个技能时，转轮里全是同一个、没有选择意义——
	#   直接当作已停在该技能，进入落位单位选择（仍由玩家点头像决定给谁）
	if entries.size() == 1:
		_sk_clear_picks()
		_sk_apply_entry(entries[0])
		return
	_current_skill = str(_skills[_index])
	_sk_clear_picks()
	_machine.setup(entries, "主动技能轮盘 · 第 %d 次" % (_index + 1))
	_msg.text = "玩家决定结果：点开始，看准技能图标再点停"
	_msg.add_theme_color_override("font_color", _dim_color)


func _sk_build_entries() -> Array:
	var entries: Array = []
	# ★ v6.18：轮盘池预筛改用 can_place_with_future（全池匹配），
	#   与落位判定口径一致。旧版用固定剩余技能精确覆盖，把池子压得只剩少数技能、
	#   每张卡又只剩 1 个落点 → 1 对 1。现在只要存在一个单位能安全落位即可入池。
	var remaining_names: Array = []
	for uname in _unit_names:
		var u: UnitData = _sk_find_unit(str(uname))
		if u != null and (u.talent_slots.is_empty() or u.talent_slots[0] == null):
			remaining_names.append(str(uname))

	# ★ v6.22：池子改用全池并集，不再用 ranked(兼容≥2单位) 的交集。
	#   旧版第 2 次剩 2 个单位时交集常只剩 1 个技能 → 轮盘全是同一个。
	#   全池并集配合下面的 can_place_with_future 安全过滤，池子大且不会转出死卡。
	var source_pool: Array = BuildManager.build_skill_pool(remaining_names)

	var safe_pool: Array = []       # 至少一个单位能安全落位（首选）
	var fallback_pool: Array = []   # 仅兼容但无法保证后续覆盖（兜底）
	for tid in source_pool:
		var sid := str(tid)
		if _placed_skills.has(sid):
			continue
		var has_safe := false
		var has_placeable := false
		for uname in remaining_names:
			var ud: UnitData = _sk_find_unit(str(uname))
			if ud == null:
				continue
			if BuildManager.can_place_skill(ud, sid):
				has_placeable = true
			if BuildManager.can_place_with_future(ud, sid, remaining_names):
				has_safe = true
				break
		if has_safe:
			safe_pool.append(sid)
		elif has_placeable:
			fallback_pool.append(sid)

	var chosen: Array = safe_pool if not safe_pool.is_empty() else fallback_pool
	for sid in chosen:
		var data := TalentManager.get_talent_data(sid)
		if data == null:
			continue
		# ★ v6.57：技能统一亮色，不按流派上色
		var color := Color(0.85, 0.85, 0.9)
		var desc := data.description
		var cost := int(data.effect_params.get("soul_fire_cost", data.soul_cost))
		desc += "｜消耗 %d 魂火" % cost
		# ★ v6.57：技能不展示流派（无流派色/无共鸣文字），仅保留数值描述
		entries.append({
			"id": sid,
			"name": data.display_name,
			"desc": desc,
			"color": color,
			"icon": TalentManager.get_talent_icon(sid),
		})
	return entries


func _sk_clear_picks() -> void:
	for c in _unit_row.get_children():
		c.queue_free()
	_safe_picks.clear()
	_skip_btn.visible = false


func _sk_apply_entry(entry: Dictionary) -> void:
	var tid := str(entry.get("id", ""))
	_skills[_index] = tid
	_current_skill = tid
	# ★ v6.57：图标 + 文字展示（参考防具落袋）；技能无流派，文字统一白色不加流派色
	var icon_tex : Texture2D = entry.get("icon") as Texture2D
	if _picked_icon != null:
		_picked_icon.texture = icon_tex
		_picked_icon.visible = icon_tex != null
	_msg.text = str(entry.get("desc", ""))
	_msg.add_theme_color_override("font_color", Color.WHITE)
	_sk_show_units(tid)


func _sk_on_machine_stopped(entry: Dictionary) -> void:
	var tid := str(entry.get("id", ""))
	if tid == "" or _placed_skills.has(tid):
		var entries: Array = _sk_build_entries()
		if entries.is_empty():
			_index = _skills.size()
			_sk_finish()
			return
		# ★ v6.22：重转后若只剩 1 个技能，同样直接落位，不再转全同轮盘
		if entries.size() == 1:
			_sk_apply_entry(entries[0])
			return
		_msg.text = "这张已用过，请再转一次"
		_msg.add_theme_color_override("font_color", _dim_color)
		_machine.setup(entries, "主动技能轮盘 · 第 %d 次" % (_index + 1))
		return
	_sk_apply_entry(entry)


func _sk_show_units(tid: String) -> void:
	_sk_clear_picks()
	# 收集尚未占用第 1 技能格的单位
	var remaining_names: Array = []
	for uname in _unit_names:
		var u: UnitData = _sk_find_unit(str(uname))
		if u != null and (u.talent_slots.is_empty() or u.talent_slots[0] == null):
			remaining_names.append(str(uname))
	# ★ v6.19：只显示"尚未装备技能"的单位——已落位的单位不再出现在本界面选项里。
	# ★ v6.18：落位判定用 can_place_with_future（全池匹配），取代过紧的 is_safe_placement。
	var any_ok := false
	for uname in remaining_names:
		var ud: UnitData = _sk_find_unit(str(uname))
		if ud == null:
			continue
		var adv := str(ud.advanced_class)
		var compatible := TalentManager.is_talent_compatible_with_unit(tid, ud.unit_name, adv)
		var safe := BuildManager.can_place_with_future(ud, tid, remaining_names)
		var can_pick := compatible and safe

		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.size_flags_vertical = Control.SIZE_FILL
		card.add_theme_constant_override("separation", 1)
		card.custom_minimum_size = Vector2(84, 0)
		# 头像按钮自带画框，不再额外套 PanelContainer，避免双层边框
		var avatar := UnitDataManager.create_unit_avatar_button(
			ud.unit_name, Vector2(46, 46), Vector2(40, 40))
		avatar.disabled = not can_pick
		avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if can_pick:
			avatar.pressed.connect(_sk_on_pick.bind(ud, tid))
			any_ok = true
			_safe_picks.append({"ud": ud, "tid": tid})
		else:
			avatar.modulate = Color(0.35, 0.35, 0.38)
		card.add_child(avatar)

		var name_lbl := Label.new()
		# ★ v6.58：紧凑显示当前/最大等级 + 当前/所需经验
		var lv_short : String = "L%d/%d" % [ud.level, BuildManager.LEVEL_CAP]
		if ud.level >= BuildManager.LEVEL_CAP:
			lv_short += " MAX"
		else:
			lv_short += "·%d/%d" % [ud.experience, BuildManager.exp_to_next_level(ud.level)]
		name_lbl.text = "%s %s" % [ud.display_name, lv_short]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.custom_minimum_size = Vector2(84, 12)
		name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		name_lbl.clip_text = true
		name_lbl.add_theme_font_size_override("font_size", FS_SMALL)
		name_lbl.add_theme_color_override("font_color", _gold_color if can_pick else _dim_color)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_lbl)

		# ★ v6.21：头像下方的流派方向文字，颜色与流派一致。
		#   ① 本次 roll 技能的共鸣流派（让玩家看懂这张技能属于哪个流派方向）；
		#   ② 该单位已觉醒的流派（开局通常为空）。都用各自流派色，方便对应。
		var school_row := HBoxContainer.new()
		school_row.alignment = BoxContainer.ALIGNMENT_CENTER
		school_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		school_row.add_theme_constant_override("separation", 3)

		var resonance := BuildManager.get_school_of_skill(tid)
		var mechs := BuildManager.get_unit_mechanisms(ud)
		if resonance == "" and mechs.is_empty():
			var none_lbl := Label.new()
			none_lbl.text = "无流派"
			none_lbl.add_theme_font_size_override("font_size", FS_SMALL)
			none_lbl.add_theme_color_override("font_color", _dim_color)
			school_row.add_child(none_lbl)
		else:
			if resonance != "":
				var rl := Label.new()
				rl.text = "共鸣·%s" % resonance
				rl.add_theme_font_size_override("font_size", FS_SMALL)
				rl.add_theme_color_override("font_color", BuildManager.get_school_color(resonance))
				school_row.add_child(rl)
			for m in mechs:
				var ml := Label.new()
				ml.text = "%s Lv%d" % [str(m.get("school", "")), int(m.get("level", 1))]
				ml.add_theme_font_size_override("font_size", FS_SMALL)
				ml.add_theme_color_override("font_color", m.get("color", Color.WHITE))
				school_row.add_child(ml)
		card.add_child(school_row)
		_unit_row.add_child(card)

	_skip_btn.visible = not any_ok
	if not any_ok:
		_msg.text = "这张技能当前队伍无人可用，请重转"
		_msg.add_theme_color_override("font_color", _dim_color)


func _sk_find_unit(unit_name: String) -> UnitData:
	# ★ 优先从外部注入的单位对象找（Arena 单单位），否则回退主线 GameState.party
	if not _unit_override.is_empty():
		for ud in _unit_override:
			if ud != null and ud.unit_name == unit_name:
				return ud
		return null
	for ud in GameState.party:
		if ud != null and ud.unit_name == unit_name:
			return ud
	return null


func _sk_on_pick(ud: UnitData, tid: String) -> void:
	BuildManager.place_skill(ud, tid)
	_placed_skills.append(tid)
	_sk_next()


func _sk_on_skip() -> void:
	if _safe_picks.is_empty():
		# 无人可用：重新开一轮，不推进次数；但若池已空则直接结束，避免卡死
		var entries: Array = _sk_build_entries()
		if entries.is_empty():
			_index = _skills.size()
			_sk_finish()
			return
		# ★ v6.22：重转后若只剩 1 个技能，直接落位，不再转全同轮盘
		if entries.size() == 1:
			_sk_clear_picks()
			_sk_apply_entry(entries[0])
			return
		_machine.setup(entries, "主动技能轮盘 · 第 %d 次" % (_index + 1))
		return
	_sk_next()


func _sk_next() -> void:
	_index += 1
	_sk_show_step()


func _sk_finish() -> void:
	SaveManager.auto_save()
	skill_finished.emit()
	queue_free()
