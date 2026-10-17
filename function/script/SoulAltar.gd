extends CanvasLayer

signal closed

enum Tab { SOUL_FIRE, ATTR_CAP, UNIT_UNLOCK }

## ★ v4.1：只保留 3 级成本（20 / 50 / 120）
const ATTR_CAP_COSTS : Array[int] = [20, 50, 120]

var _current_tab : Tab = Tab.SOUL_FIRE
var _current_unit_type : String = ""
var unit_unlock_tab_btn : Button = null

@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var soul_fire_tab_btn : Button = $Panel/VBox/TabBar/SoulFireTabBtn
@onready var attr_cap_tab_btn : Button = $Panel/VBox/TabBar/AttrCapTabBtn
@onready var left_title : Label = $Panel/VBox/MainHBox/LeftColumn/LeftTitle
@onready var unit_list : VBoxContainer = $Panel/VBox/MainHBox/LeftColumn/UnitListScroll/UnitList
@onready var unit_sprite : AnimatedSprite2D = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/SpriteContainer/UnitSprite
@onready var unit_name_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitNameLabel
@onready var unit_desc_label : Label = $Panel/VBox/MainHBox/InfoPanel/UnitHeader/HeaderInfo/UnitDescLabel
@onready var attr_container : VBoxContainer = $Panel/VBox/MainHBox/InfoPanel/AttrScroll/AttrContainer
@onready var hint_label : Label = $Panel/VBox/MainHBox/InfoPanel/BottomBar/HintLabel


func _ready():
	MusicManager.play_soul_altar_music()
	if soul_fire_tab_btn:
		soul_fire_tab_btn.text = "魂火"
	if attr_cap_tab_btn:
		attr_cap_tab_btn.text = "属性上限"
	if hint_label:
		hint_label.visible = false

	if soul_fire_tab_btn and not soul_fire_tab_btn.pressed.is_connected(_on_soul_fire_tab_pressed):
		soul_fire_tab_btn.pressed.connect(_on_soul_fire_tab_pressed)
	if attr_cap_tab_btn and not attr_cap_tab_btn.pressed.is_connected(_on_attr_cap_tab_pressed):
		attr_cap_tab_btn.pressed.connect(_on_attr_cap_tab_pressed)

	# ★ v4.1：动态创建"唤醒残魂"tab
	var tab_bar : HBoxContainer = $Panel/VBox/TabBar
	if tab_bar:
		unit_unlock_tab_btn = Button.new()
		unit_unlock_tab_btn.text = "唤醒残魂"
		unit_unlock_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_unlock_tab_btn.add_theme_font_size_override("font_size", 7)
		tab_bar.add_child(unit_unlock_tab_btn)
		unit_unlock_tab_btn.pressed.connect(_on_unit_unlock_tab_pressed)

	_refresh_soul()
	_switch_tab(Tab.SOUL_FIRE)


func _on_soul_fire_tab_pressed(): _switch_tab(Tab.SOUL_FIRE)
func _on_attr_cap_tab_pressed(): _switch_tab(Tab.ATTR_CAP)
func _on_unit_unlock_tab_pressed(): _switch_tab(Tab.UNIT_UNLOCK)


func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()


func _switch_tab(tab: Tab):
	_current_tab = tab
	soul_fire_tab_btn.modulate = Color.WHITE if tab == Tab.SOUL_FIRE else Color(0.5, 0.5, 0.5, 1)
	attr_cap_tab_btn.modulate = Color.WHITE if tab == Tab.ATTR_CAP else Color(0.5, 0.5, 0.5, 1)
	if unit_unlock_tab_btn:
		unit_unlock_tab_btn.modulate = Color.WHITE if tab == Tab.UNIT_UNLOCK else Color(0.5, 0.5, 0.5, 1)

	if tab == Tab.SOUL_FIRE:
		left_title.text = "— 魂火 —"
		_clear_unit_list()
		_refresh_soul_fire_panel()
	elif tab == Tab.ATTR_CAP:
		left_title.text = "— 单位 —"
		_build_unit_list()
		_refresh_attr_cap_panel()
	else:
		left_title.text = "— 残魂 —"
		_build_locked_unit_list()
		_refresh_unit_unlock_panel()


func _clear_unit_list():
	for c in unit_list.get_children():
		unit_list.remove_child(c); c.queue_free()


# ============================================================
#  Tab 1 · 魂火
# ============================================================
func _refresh_soul_fire_panel():
	_clear_attr_container()
	unit_sprite.visible = false
	unit_name_label.text = "魂火祭坛"
	unit_desc_label.text = ""

	var lv : int = SoulFireManager.altar_level
	var max_lv : int = SoulFireManager.MAX_CARRIED_LEVELS.size() - 1
	var cur_max : int = SoulFireManager.get_max_carried()
	var next_max : int = SoulFireManager.MAX_CARRIED_LEVELS[mini(lv + 1, max_lv)]
	var cost : int = SoulFireManager.get_upgrade_cost()

	attr_container.add_child(_make_title("— 携带上限 —"))
	attr_container.add_child(_make_info("当前等级：Lv %d / %d" % [lv, max_lv]))
	attr_container.add_child(_make_info("当前上限：%d 魂火" % cur_max))
	if cost >= 0:
		attr_container.add_child(_make_info("下一级上限：%d 魂火" % next_max))
		attr_container.add_child(_make_upgrade_row("升级上限", cost,
			func(): _on_upgrade_soul_fire_max()))
	else:
		attr_container.add_child(_make_info("已达最高等级"))

	attr_container.add_child(HSeparator.new())

	var init_lv : int = GameState.soul_fire_initial_level
	var init_max : int = SoulFireManager.INITIAL_LEVELS.size() - 1
	var cur_init : int = SoulFireManager.get_initial_soul_fire()
	var init_cost : int = SoulFireManager.get_initial_upgrade_cost()

	attr_container.add_child(_make_title("— 初始魂火 —"))
	attr_container.add_child(_make_info("当前等级：Lv %d / %d" % [init_lv, init_max]))
	attr_container.add_child(_make_info("每局开始携带：%d 魂火" % cur_init))
	if init_cost >= 0:
		var next_init : int = SoulFireManager.INITIAL_LEVELS[init_lv + 1]
		attr_container.add_child(_make_info("下一级：%d 魂火" % next_init))
		attr_container.add_child(_make_upgrade_row("升级初始", init_cost,
			func(): _on_upgrade_soul_fire_initial()))
	else:
		attr_container.add_child(_make_info("已达最高等级"))


func _on_upgrade_soul_fire_max():
	if SoulFireManager.upgrade_altar():
		_refresh_soul()
		_refresh_soul_fire_panel()
		_show_msg("魂火上限已提升")


func _on_upgrade_soul_fire_initial():
	if SoulFireManager.upgrade_initial():
		_refresh_soul()
		_refresh_soul_fire_panel()
		_show_msg("初始魂火已提升")


# ============================================================
#  Tab 2 · 属性上限（v4.1 重做）
# ============================================================
func _build_unit_list():
	for c in unit_list.get_children():
		unit_list.remove_child(c); c.queue_free()

	var all_units = UnitDataManager.get_all_unit_ids()
	for unit_type in all_units:
		if not Globals.is_unit_unlocked(unit_type): continue
		# 只显示有 attr_cap_levels 配置的单位
		if not UnitDataManager.has_attr_cap_levels(unit_type): continue

		var btn = Button.new()
		var type_display = UnitDataManager.get_unit_type_display_name(unit_type)
		var cap_lv : int = int(GameState.unit_attr_cap.get(unit_type, 0))
		var levels : Array = UnitDataManager.get_attr_cap_levels(unit_type)
		btn.text = "%s  [Lv %d/%d]" % [type_display, cap_lv, levels.size()]
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE if unit_type == _current_unit_type else Color(0.7, 0.7, 0.7, 1)
		btn.pressed.connect(_on_unit_selected.bind(unit_type))
		unit_list.add_child(btn)

	# 默认选中第一个
	if _current_unit_type == "" or not _is_unit_in_list(_current_unit_type):
		for child in unit_list.get_children():
			if child is Button:
				var ut = child.get_meta("unit_type", "")
				if ut != "":
					_current_unit_type = ut
					break


func _is_unit_in_list(unit_type: String) -> bool:
	for child in unit_list.get_children():
		if child is Button and child.get_meta("unit_type", "") == unit_type:
			return true
	return false


func _on_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			if ut != "":
				child.modulate = Color.WHITE if ut == unit_type else Color(0.7, 0.7, 0.7, 1)
	_refresh_attr_cap_panel()


func _refresh_attr_cap_panel():
	_clear_attr_container()
	if _current_unit_type == "":
		unit_name_label.text = "（未选择）"
		unit_desc_label.text = ""
		unit_sprite.visible = false
		return

	var display : String = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	var dict : Dictionary = UnitDataManager.get_unit_data(_current_unit_type)
	var cur_lv : int = int(GameState.unit_attr_cap.get(_current_unit_type, 0))
	var levels : Array = UnitDataManager.get_attr_cap_levels(_current_unit_type)
	var max_lv : int = levels.size()

	unit_name_label.text = "%s   上限 Lv %d / %d" % [display, cur_lv, max_lv]
	unit_desc_label.text = dict.get("description", "")
	unit_sprite.visible = true
	_load_unit_sprite(_current_unit_type)

	# ---- 已获得加成 ----
	attr_container.add_child(_make_title("— 已获得加成 —"))
	var total : Dictionary = UnitDataManager.get_attr_cap_total_bonus(_current_unit_type, cur_lv)
	if total.is_empty():
		attr_container.add_child(_make_info("（尚无，升级后生效）"))
	else:
		attr_container.add_child(_make_info(_format_bonus_dict(total)))

	# ---- 下一级预览 ----
	if cur_lv < max_lv:
		var next_dict : Dictionary = levels[cur_lv]
		attr_container.add_child(_make_title("— 下一级 Lv%d 预览 —" % (cur_lv + 1)))
		attr_container.add_child(_make_info(_format_bonus_dict(next_dict)))

		var cost : int = ATTR_CAP_COSTS[cur_lv] if cur_lv < ATTR_CAP_COSTS.size() else -1
		if cost > 0:
			attr_container.add_child(_make_upgrade_row("升级", cost,
				func(): _on_upgrade_attr_cap()))
	else:
		attr_container.add_child(_make_title("— 已达最高等级 —"))

	# ---- 不可升级属性 ----
	attr_container.add_child(HSeparator.new())
	attr_container.add_child(_make_title("— 不可升级 —"))
	var all_attrs : Array = ["vitality", "strength", "dexterity", "intelligence", "faith", "arcane"]
	var upgradable : Dictionary = {}
	for lv_dict in levels:
		if lv_dict is Dictionary:
			for k in lv_dict:
				upgradable[k] = true
	var blocked : Array = []
	for a in all_attrs:
		if not upgradable.has(a):
			blocked.append(a)
	if blocked.is_empty():
		attr_container.add_child(_make_info("（全部可升级）"))
	else:
		var names : Array = []
		for a in blocked:
			names.append(_attr_cn(a))
		var lb := Label.new()
		lb.text = " · ".join(names)
		lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		lb.modulate = Color(0.6, 0.6, 0.6, 1)
		attr_container.add_child(lb)

	# ---- 提示 ----
	var note := Label.new()
	note.text = "升级后将于下一局生效。"
	note.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.55, 0.55, 0.55, 1)
	attr_container.add_child(note)


func _on_upgrade_attr_cap():
	if _current_unit_type == "": return
	var levels : Array = UnitDataManager.get_attr_cap_levels(_current_unit_type)
	var cur_lv : int = int(GameState.unit_attr_cap.get(_current_unit_type, 0))
	if cur_lv >= levels.size(): return
	var cost : int = ATTR_CAP_COSTS[cur_lv] if cur_lv < ATTR_CAP_COSTS.size() else -1
	if cost <= 0 or GameState.soul < cost: return

	GameState.soul -= cost
	GameState.unit_attr_cap[_current_unit_type] = cur_lv + 1
	SaveManager.auto_save()

	_refresh_soul()
	_build_unit_list()
	_refresh_attr_cap_panel()
	_show_msg("%s 已升至 Lv%d（下一局生效）" % [
		UnitDataManager.get_unit_type_display_name(_current_unit_type), cur_lv + 1])


# ============================================================
#  Tab 3 · 唤醒残魂（单位解锁）
# ============================================================
func _build_locked_unit_list():
	for c in unit_list.get_children():
		unit_list.remove_child(c); c.queue_free()

	var costs : Dictionary = Globals.unlock_config.get("unlock_costs", {})
	var eligible : Array = Globals.get_eligible_units()

	# 候选池 = unlock_costs keys ∪ eligible_units
	var all_candidates : Array = []
	for k in costs:
		all_candidates.append(k)
	for k in eligible:
		if k not in all_candidates:
			all_candidates.append(k)

	# 排除已正式解锁的
	var locked : Array = []
	for unit_type in all_candidates:
		if Globals.is_unit_unlocked(unit_type):
			continue
		if UnitDataManager.get_unit_data(unit_type).is_empty():
			continue
		locked.append(unit_type)

	if locked.is_empty():
		var lb := Label.new()
		lb.text = "（所有残魂已唤醒）"
		lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		lb.modulate = Color(0.6, 0.6, 0.6, 1)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unit_list.add_child(lb)
		return

	for unit_type in locked:
		var btn := Button.new()
		var display = UnitDataManager.get_unit_type_display_name(unit_type)
		btn.text = display
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.set_meta("unit_type", unit_type)
		btn.modulate = Color.WHITE if unit_type == _current_unit_type else Color(0.7, 0.7, 0.7, 1)
		btn.pressed.connect(_on_locked_unit_selected.bind(unit_type))
		unit_list.add_child(btn)

	if _current_unit_type == "" or Globals.is_unit_unlocked(_current_unit_type):
		_current_unit_type = locked[0]


func _on_locked_unit_selected(unit_type: String):
	_current_unit_type = unit_type
	for child in unit_list.get_children():
		if child is Button:
			var ut = child.get_meta("unit_type", "")
			if ut != "":
				child.modulate = Color.WHITE if ut == unit_type else Color(0.7, 0.7, 0.7, 1)
	_refresh_unit_unlock_panel()


func _refresh_unit_unlock_panel():
	_clear_attr_container()

	var costs : Dictionary = Globals.unlock_config.get("unlock_costs", {})
	var eligible : Array = Globals.get_eligible_units()

	var all_candidates : Array = []
	for k in costs:
		all_candidates.append(k)
	for k in eligible:
		if k not in all_candidates:
			all_candidates.append(k)

	var any_locked : bool = false
	for unit_type in all_candidates:
		if Globals.is_unit_unlocked(unit_type):
			continue
		if UnitDataManager.get_unit_data(unit_type).is_empty():
			continue
		any_locked = true
		break

	if not any_locked:
		unit_sprite.visible = false
		unit_name_label.text = "所有残魂已唤醒"
		unit_desc_label.text = "守火者的火光照亮了每一个角落。"
		attr_container.add_child(_make_info("—— 无待唤醒的残魂 ——"))
		return

	if _current_unit_type == "" or Globals.is_unit_unlocked(_current_unit_type):
		for unit_type in all_candidates:
			if not Globals.is_unit_unlocked(unit_type):
				if UnitDataManager.get_unit_data(unit_type).is_empty():
					continue
				_current_unit_type = unit_type
				break

	if _current_unit_type == "":
		return

	var display : String = UnitDataManager.get_unit_type_display_name(_current_unit_type)
	var dict : Dictionary = UnitDataManager.get_unit_data(_current_unit_type)
	var cost : int = Globals.get_unit_unlock_cost(_current_unit_type)
	var can_afford : bool = GameState.soul >= cost

	unit_name_label.text = "%s   （未唤醒）" % display
	unit_desc_label.text = dict.get("description", "")
	unit_sprite.visible = true
	_load_unit_sprite(_current_unit_type)

	attr_container.add_child(_make_title("— 残魂信息 —"))
	attr_container.add_child(_make_info("HP：%d" % int(dict.get("max_hp", 0))))
	attr_container.add_child(_make_info("力量：%d    灵巧：%d" % [
		int(dict.get("strength", 0)), int(dict.get("dexterity", 0))]))
	attr_container.add_child(_make_info("智力：%d    信仰：%d    感应：%d" % [
		int(dict.get("intelligence", 0)),
		int(dict.get("faith", 0)),
		int(dict.get("arcane", 0))]))
	attr_container.add_child(_make_info("移动力：%d" % int(dict.get("move_range", 0))))

	attr_container.add_child(HSeparator.new())
	attr_container.add_child(_make_title("— 唤醒代价 —"))
	attr_container.add_child(_make_info("需要魂：%d" % cost))
	attr_container.add_child(_make_info("当前魂：%d" % GameState.soul))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lb := Label.new()
	lb.text = "唤醒此残魂？"
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lb)
	var btn := Button.new()
	btn.text = "唤醒"
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(50, 0)
	btn.disabled = not can_afford
	if can_afford:
		btn.pressed.connect(_on_unlock_unit_pressed)
	row.add_child(btn)
	attr_container.add_child(row)

	if not can_afford:
		var warn := Label.new()
		warn.text = "⚠ 魂不足"
		warn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_TINY)
		warn.modulate = Color(1.0, 0.6, 0.6, 1)
		attr_container.add_child(warn)


func _on_unlock_unit_pressed():
	if _current_unit_type == "": return
	var cost : int = Globals.get_unit_unlock_cost(_current_unit_type)
	if GameState.soul < cost: return
	if Globals.is_unit_unlocked(_current_unit_type): return

	GameState.soul -= cost
	Globals.unlock_unit(_current_unit_type)
	SaveManager.auto_save()

	_refresh_soul()
	_show_msg("★ %s 已唤醒！" % UnitDataManager.get_unit_type_display_name(_current_unit_type))

	_current_unit_type = ""
	_build_locked_unit_list()
	_refresh_unit_unlock_panel()


# ============================================================
#  辅助
# ============================================================
func _make_title(text: String) -> Label:
	var lb = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.modulate = Color(0.7, 0.8, 1.0)
	return lb


func _make_info(text: String) -> Label:
	var lb = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return lb


func _make_upgrade_row(label_text: String, cost: int, cb: Callable) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lb = Label.new()
	lb.text = "%s：%d 魂" % [label_text, cost]
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lb)

	var btn = Button.new()
	btn.text = "升级"
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(50, 0)
	btn.disabled = (GameState.soul < cost)
	btn.pressed.connect(cb)
	row.add_child(btn)
	return row


func _refresh_soul():
	soul_label.text = "魂: " + str(GameState.soul)


func _clear_attr_container():
	for c in attr_container.get_children():
		attr_container.remove_child(c); c.queue_free()


func _load_unit_sprite(unit_type: String):
	var path = UnitDataManager.get_sprite_frames_path(unit_type)
	if path != "" and ResourceLoader.exists(path):
		var frames = load(path) as SpriteFrames
		if frames:
			unit_sprite.sprite_frames = frames
			if frames.has_animation("idle"):
				unit_sprite.play("idle")
			unit_sprite.visible = true
			unit_sprite.position = Vector2(13, 8)
			return
	unit_sprite.visible = false


func _show_msg(msg: String):
	if not hint_label: return
	hint_label.visible = true
	hint_label.text = msg
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(hint_label):
		hint_label.visible = false
		hint_label.text = ""


## 属性 key → 中文简称
func _attr_cn(key: String) -> String:
	match key:
		"vitality":     return "HP"
		"strength":     return "力量"
		"dexterity":    return "灵巧"
		"intelligence": return "智力"
		"faith":        return "信仰"
		"arcane":       return "感应"
		"move_range":   return "移动"
		_: return key


## {"strength": 1, "vitality": 2} → "力量 +1   HP +2"
func _format_bonus_dict(dict : Dictionary) -> String:
	var parts : Array = []
	# 固定顺序：力、灵、智、信、感、HP
	var order : Array = ["strength", "dexterity", "intelligence", "faith", "arcane", "vitality"]
	for k in order:
		if dict.has(k):
			parts.append("%s +%d" % [_attr_cn(k), int(dict[k])])
	# 兜底：不在顺序里的键
	for k in dict:
		if k not in order:
			parts.append("%s +%d" % [_attr_cn(k), int(dict[k])])
	return "    ".join(parts)
