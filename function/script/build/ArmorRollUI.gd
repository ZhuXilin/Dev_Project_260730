extends CanvasLayer
const BuildUI = preload("res://function/script/build/BuildUI.gd")
const SlotMachineUI = preload("res://function/script/build/SlotMachineUI.gd")
const EquipCfg = preload("res://function/script/equipmentconfig/EquipmentConfig.gd")
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

const FS_TITLE: int = 10
const FS_BODY: int = 7
const FS_SMALL: int = 6

var _gold_color := Color(0.98, 0.75, 0.25)
var _dim_color := Color(0.55, 0.55, 0.58)

var _roll_count: int = 0
var _quality_level: int = 0
var _current: Dictionary = {}          # 当前待领取防具 {item_id,quality,school,name,mechanic}

var _root: Panel = null
var _gold_label: Label = null
var _machine = null
var _cost_label: Label = null
var _upgrade_btn: Button = null
var _close_btn: Button = null
var _action_row: HBoxContainer = null
var _result_box: VBoxContainer = null
var _msg: Label = null
var _closing: bool = false   # ★ 防两个关闭按钮同帧重复触发

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
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_root = Panel.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var root_sb := StyleBoxFlat.new()
	root_sb.bg_color = Color(0.06, 0.06, 0.09, 0.98)
	root_sb.set_border_width_all(0)
	root_sb.content_margin_left = 2.0
	root_sb.content_margin_right = 2.0
	_root.add_theme_stylebox_override("panel", root_sb)
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "竞技场 · 防具抽取" if _arena_mode else "战后 · 防具抽取"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", _gold_color)
	vbox.add_child(title)

	_gold_label = Label.new()
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", FS_BODY)
	vbox.add_child(_gold_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_cost_label = Label.new()
	_cost_label.add_theme_font_size_override("font_size", FS_SMALL)
	_cost_label.add_theme_color_override("font_color", _gold_color)
	btn_row.add_child(_cost_label)

	_machine = SlotMachineUI.new()
	# ★ v6.23：400x240 小视口，轮盘从 96 压到 72，给下方单位信息腾出高度
	_machine.custom_minimum_size = Vector2(0, 72)
	vbox.add_child(_machine)
	_machine.stopped.connect(_on_machine_stopped)
	_machine.started.connect(_on_spin_started)

	_upgrade_btn = Button.new()
	_upgrade_btn.add_theme_font_size_override("font_size", FS_BODY)
	BuildUI.style_button(_upgrade_btn)
	_upgrade_btn.pressed.connect(_on_upgrade_quality)
	btn_row.add_child(_upgrade_btn)

	# ★ v6.25：删除顶部常驻返回键，只保留最下方"结束抽取"按钮，避免两个"返回地图"重复。
	#   金币不足时无待领取→最下方按钮可用；待领取时可用"放弃防具"脱困，不会死锁。

	# ★ 中间信息压缩：品质并入金币行，删除单独的 _quality_label，减少一行占用
	_msg = Label.new()
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", FS_SMALL)
	_msg.custom_minimum_size = Vector2(0, 10)   # ★ 固定矮高度，避免 autowrap 撑高挤掉单位区
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_msg)

	# ★ v6.44：放弃防具按钮已移入 EquipmentConfig 落位界面，此处不再创建
	_action_row = HBoxContainer.new()
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_action_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ★ v6.23：不再强制 140 最小高度——400x240 视口里固定高度累加会溢出，
	#   底部（单位卡第二行）被挤出视口裁切。改用 EXPAND_FILL 吃剩余空间，内容超出时内部滚动。
	scroll.custom_minimum_size = Vector2(0, 80)   # 单位卡约60px + 摘要行，安全下限；配合上方压缩不溢出视口
	vbox.add_child(scroll)
	_result_box = VBoxContainer.new()
	_result_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_box.add_theme_constant_override("separation", 1)
	scroll.add_child(_result_box)

	var close := Button.new()
	close.text = "结束抽取"
	close.add_theme_font_size_override("font_size", FS_BODY)
	BuildUI.style_button(close)
	close.pressed.connect(_on_close)
	# ★ v6.44：收窄为约 1/6 视口宽（400px → 66px），不再占满整行
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(66, 0)
	vbox.add_child(close)
	_close_btn = close


## ★ v6.17：操作门控——转轮进行中 / 有待领取防具时，禁止离开与升级，
##   防止中途退出丢结果、或转动中改品质导致转轮池与品质不符。
func _update_action_buttons() -> void:
	var spinning: bool = (_machine != null and _machine.is_spinning())
	var has_pending: bool = not _current.is_empty()
	var locked: bool = spinning or has_pending
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
	if gold < cost and _msg.text == "":
		_msg.text = "金币不足，可点最下方「结束抽取」离开"
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
	_roll_count += 1
	_current = {}
	# ★ v6.43：移除老虎机状态文字（点「停！」提示），轮盘自身已有按钮反馈
	_msg.text = ""
	_refresh()


func _on_machine_stopped(entry: Dictionary) -> void:
	var iid := str(entry.get("item_id", ""))
	if iid == "":
		_msg.text = "抽取失败（防具池为空）"
		return
	_current = {
		"item_id": iid,
		"quality": str(entry.get("quality", "common")),
		"school": str(entry.get("school", "")),
		"name": str(entry.get("name", iid)),
		"mechanic": str(entry.get("mechanic", "")),
	}
	# ★ v6.43：抽到后直接跳转装备界面落位，不再显示三个 avatar 让玩家选
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

		# 第二行：单位名 + Lv + 防具数/槽位（普通色）
		var armor_used: int = ud.count_used_armor_slots()
		var armor_slots: int = ud.max_armor_slots
		var name_lbl := Label.new()
		name_lbl.text = "%s Lv%d 防%d/%d" % [
			ud.display_name, int(ud.level), armor_used, armor_slots]
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
		if BuildManager.get_school_of_item(slot.item_id) == school:
			remove_n += 1
	return "覆盖 → 删 %d 件旧防具" % remove_n


func _on_discard() -> void:
	_current = {}
	_msg.text = "已放弃该防具"
	_refresh()   # ★ 走 _refresh 才能重新装填转轮 + 恢复离开按钮（原来只 render 会卡在「已停止」）


## ★ v6.41：弹出只读 EquipmentConfig（防具落位模式），玩家看三单位装备全貌后点防具槽决定落位
var _pick_ui = null

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
	if panel.has_signal("armor_overwrite_requested"):
		panel.armor_overwrite_requested.connect(_on_pick_overwrite)
	# 落位模式：展示全貌，除防具槽外只读
	panel.init(_get_units(), SaveManager.current_slot, EquipCfg.Mode.ARMOR_ROLL, null)
	# ★ v6.43：把待落袋防具传给装备界面，高亮槽位 + 顶部展示
	if panel.has_method("set_pending_armor"):
		panel.set_pending_armor(_current)
	# 底层不再显示三 avatar 结果卡（信息已移到装备界面）
	for c in _result_box.get_children():
		c.queue_free()


func _on_pick_unit(unit_idx: int) -> void:
	var units := _get_units()
	if unit_idx < 0 or unit_idx >= units.size():
		return
	var ud = units[unit_idx]
	if ud == null or ud.is_dead:
		return
	_on_place(ud)
	_close_pick_ui()


## ★ v6.44：在装备界面点"放弃防具"——放弃当前防具并关闭浮层
func _on_pick_discard() -> void:
	_on_discard()
	_close_pick_ui()


## ★ v6.47：EquipmentConfig 内确认覆盖 → 执行 overwrite 并关闭浮层进下一轮
func _on_pick_overwrite(unit_idx: int, school_to_remove: String) -> void:
	var units := _get_units()
	if unit_idx < 0 or unit_idx >= units.size():
		return
	_do_overwrite(units[unit_idx], school_to_remove)
	_close_pick_ui()


func _close_pick_ui() -> void:
	if _pick_ui == null:
		return
	# ★ v6.43：只释放装备浮层本身。旧版误 queue_free 了 parent(current_scene=Battlefield)，
	#   导致落位后整个战场被销毁 → 黑屏且无法操作。
	if is_instance_valid(_pick_ui):
		_pick_ui.queue_free()
	_pick_ui = null


func _on_place(ud: UnitData) -> void:
	var item_id := str(_current.get("item_id", ""))
	var quality := str(_current.get("quality", "common"))
	# ★ v6.27：同流派并入升 Lv 免费，不再收 200G（原预判扣费块已删除）
	var result := BuildManager.apply_armor(ud, item_id, quality)
	match str(result.get("result", "")):
		"awaken", "merge", "plain":
			# ★ v6.45：落位后直接进下一轮——不写结算态、不停留，_refresh 自动装填新转轮
			SoundManager.play_get_item_sound()
			_current = {}
			_refresh()
		"full":
			# ★ v6.47：槽满覆盖已下沉到 EquipmentConfig，此分支仅兜底
			_msg.text = "请在装备界面选择要覆盖的流派"
		_:
			_msg.text = "无法落位"


func _do_overwrite(ud: UnitData, school_to_remove: String) -> void:
	BuildManager.overwrite_school(ud, school_to_remove,
		str(_current.get("item_id", "")), str(_current.get("quality", "common")))
	# ★ v6.45：覆盖后同样直接进下一轮，不停留结算态
	_current = {}
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
