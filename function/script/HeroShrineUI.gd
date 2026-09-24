extends CanvasLayer

signal closed

const COST_PER_CLASS : int = 800
const PERFORMANCE_DURATION : float = 2.0
const POST_SWITCH_DURATION : float = 0.8

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/TopBar/TitleLabel
@onready var gold_label : Label = $Panel/VBox/TopBar/GoldLabel
@onready var cost_label : Label = $Panel/VBox/TopBar/CostLabel
@onready var hint_label : Label = $Panel/VBox/HintLabel
@onready var unit_row : HBoxContainer = $Panel/VBox/UnitRow
@onready var close_btn : Button = $Panel/VBox/BottomBar/CloseButton

@onready var performance_layer : Control = $PerformanceLayer
@onready var perf_sprite : AnimatedSprite2D = $PerformanceLayer/CenterBox/SpriteBox/UnitSprite
@onready var perf_label : Label = $PerformanceLayer/CenterBox/PerfLabel

var _is_performing : bool = false
var _mode : String = "map"
var _arena_ref = null
var _custom_party : Array = []


# ============================================================
#  上下文设置
# ============================================================
func setup_arena(arena_node, unit_data) -> void:
	_mode = "arena"
	_arena_ref = arena_node
	_custom_party = [unit_data] if unit_data else []
	if is_node_ready():
		_rebuild()


func setup_map() -> void:
	_mode = "map"
	_arena_ref = null
	_custom_party = []
	if is_node_ready():
		_rebuild()


func _rebuild():
	_refresh_gold_display()
	_build_unit_row()


func _get_party() -> Array:
	if not _custom_party.is_empty():
		return _custom_party
	return GameState.party


func _get_gold() -> int:
	if _mode == "arena" and _arena_ref != null:
		return _arena_ref._arena_gold
	return GameState.temp_gold


func _subtract_gold(amount: int) -> void:
	if _mode == "arena" and _arena_ref != null:
		_arena_ref._arena_gold -= amount
	else:
		GameState.temp_gold -= amount


# ============================================================
#  初始化
# ============================================================
func _ready():
	performance_layer.visible = false
	cost_label.text = "  |  转职: %dG" % COST_PER_CLASS
	MusicManager.play_hero_shrine_music()
	_refresh_gold_display()
	_build_unit_row()


func _refresh_gold_display():
	if gold_label:
		gold_label.text = "金币: %d" % _get_gold()


func _build_unit_row():
	for child in unit_row.get_children():
		unit_row.remove_child(child)
		child.queue_free()

	var party : Array = _get_party()
	print("[HeroShrine] 构建单位列表：", party.size(), " 个，mode=", _mode)
	for i in range(party.size()):
		unit_row.add_child(_build_unit_card(i))


# ============================================================
#  单位卡片
# ============================================================
func _build_unit_card(unit_idx: int) -> PanelContainer:
	var party : Array = _get_party()
	if unit_idx < 0 or unit_idx >= party.size():
		return PanelContainer.new()
	var unit : UnitData = party[unit_idx]
	var unit_display : String = unit.display_name if unit.display_name != "" else unit.unit_name
	var type_cn : String = UnitDataManager.get_unit_type_display_name(unit.unit_name)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(130, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	var name_lb = Label.new()
	name_lb.add_theme_font_size_override("font_size", 9)
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lb)

	var status_lb = Label.new()
	status_lb.add_theme_font_size_override("font_size", 7)
	status_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(status_lb)

	# ---- 已转职 ----
	if unit.advanced_class != "":
		var adv_name : String = AdvancedClassManager.get_display_name(unit.advanced_class)
		name_lb.text = unit_display + "\n" + type_cn
		name_lb.modulate = Color(0.55, 0.55, 0.55, 1)
		status_lb.text = "★ " + adv_name + "\n（已转职）"
		status_lb.modulate = Color(0.55, 0.55, 0.55, 1)
		card.modulate = Color(0.7, 0.7, 0.7, 1)
		return card

	# ---- 无进阶定义 ----
	var adv : AdvancedClassData = AdvancedClassManager.get_class_for_unit(unit.unit_name)
	if adv == null:
		name_lb.text = unit_display + "\n" + type_cn
		status_lb.text = "无转职"
		status_lb.modulate = Color(0.55, 0.55, 0.55, 1)
		card.modulate = Color(0.7, 0.7, 0.7, 1)
		return card

	# ---- 可转职 ----
	name_lb.text = unit_display + "\n" + type_cn

	var stat_parts : Array = []
	for key in adv.stat_bonus:
		stat_parts.append("+%d%s" % [int(adv.stat_bonus[key]), _attr_short(key)])
	var stat_str : String = " ".join(stat_parts)

	var talent_str : String = ""
	if adv.granted_talent != "":
		var tdata : TalentData = TalentManager.get_talent_data(adv.granted_talent)
		talent_str = tdata.display_name if tdata else adv.granted_talent

	status_lb.text = "→ ★ %s\n%s\n授予:%s" % [adv.name, stat_str, talent_str]

	var can_afford : bool = _get_gold() >= COST_PER_CLASS
	if not can_afford:
		status_lb.modulate = Color(0.55, 0.55, 0.55, 1)
		card.modulate = Color(0.7, 0.7, 0.7, 1)
	else:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_input.bind(unit_idx))
		card.mouse_entered.connect(_on_card_hover_enter.bind(card))
		card.mouse_exited.connect(_on_card_hover_exit.bind(card))

	return card


func _attr_short(key: String) -> String:
	match key:
		"max_hp":       return "HP"
		"strength":     return "力"
		"dexterity":    return "灵"
		"intelligence": return "智"
		"faith":        return "信"
		"arcane":       return "感"
		"move_range":   return "移"
		_:              return key


func _on_card_hover_enter(card: PanelContainer):
	card.modulate = Color(1.2, 1.2, 1.2, 1)


func _on_card_hover_exit(card: PanelContainer):
	card.modulate = Color.WHITE


func _on_card_input(event: InputEvent, unit_idx: int):
	if _is_performing:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_on_card_clicked(unit_idx)


# ============================================================
#  点击卡片 → 二次确认
# ============================================================
func _on_card_clicked(unit_idx: int):
	if _is_performing:
		return
	var party : Array = _get_party()
	if unit_idx < 0 or unit_idx >= party.size():
		return
	if _get_gold() < COST_PER_CLASS:
		return

	var unit : UnitData = party[unit_idx]
	if unit.advanced_class != "":
		return

	var adv : AdvancedClassData = AdvancedClassManager.get_class_for_unit(unit.unit_name)
	if adv == null:
		return

	var unit_display : String = unit.display_name if unit.display_name != "" else unit.unit_name
	Globals.show_confirm(
		self,
		"将 %s 转职为「%s」？\n消耗 %d 金币，不可撤销。" % [unit_display, adv.name, COST_PER_CLASS],
		"确定转职",
		"取消",
		func(): _begin_convert(unit, adv),
		func(): pass,
		true
	)


# ============================================================
#  转职流程
# ============================================================
func _begin_convert(unit : UnitData, adv : AdvancedClassData):
	if _is_performing:
		return
	if _get_gold() < COST_PER_CLASS:
		return

	_is_performing = true

	# ---- 0. 诊断日志 ----
	print("[HeroShrine][DEBUG] _begin_convert unit=%s/%s adv=%s granted_talent=%s" % [
		unit.unit_name, unit.display_name, adv.id, adv.granted_talent])

	# 1. 立即扣金币 + 记录
	_subtract_gold(COST_PER_CLASS)
	unit.advanced_class = adv.id

	for key in adv.stat_bonus:
		var val : int = int(adv.stat_bonus[key])
		match key:
			"max_hp":
				unit.max_hp += val
				unit.hit_points += val
			"strength":     unit.strength += val
			"dexterity":    unit.dexterity += val
			"intelligence": unit.intelligence += val
			"faith":        unit.faith += val
			"arcane":       unit.arcane += val
			"move_range":   unit.move_range += val

	# ★ 职业特技：写入独立字段，不占普通词条槽
	if adv.granted_talent != "":
		unit.advanced_talent_id = adv.granted_talent
		print("[HeroShrine][DEBUG]   → unit.advanced_talent_id = %s（对象 id=%d）" % [
			unit.advanced_talent_id, unit.get_instance_id()])
		var t_inst := TalentInstance.new()
		t_inst.talent_id = adv.granted_talent
		t_inst.is_active = true
		var tdata = TalentManager.get_talent_data(adv.granted_talent)
		if tdata and tdata.is_active_skill:
			t_inst.is_ready = true
			t_inst.cooldown_remaining = 0
		unit.advanced_talent_inst = t_inst

	if adv.sprite_frames_path != "":
		unit.override_sprite_path = adv.sprite_frames_path

	if _mode == "map":
		SaveManager.auto_save()
	else:
		_sync_advanced_class_to_gamestate(unit)
		SaveManager.auto_save()
	print("[HeroShrine] %s 转职为 %s（%s 模式，金币已扣）" % [unit.display_name, adv.name, _mode])

	# 2. 隐藏主界面，显示演出层
	panel.visible = false
	performance_layer.visible = true
	performance_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	perf_label.text = "英灵降临..."

	# 3. 加载基础 sprite
	var base_path : String = UnitDataManager.get_sprite_frames_path(unit.unit_name)
	_load_sprite_into(perf_sprite, base_path)

	# 4. 播放转职音乐
	MusicManager.play_hero_shrine_convert_music()

	# 5. 等待演出
	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout

	# 6. 切换进阶 sprite
	var adv_path : String = adv.sprite_frames_path if adv.sprite_frames_path != "" else base_path
	_load_sprite_into(perf_sprite, adv_path)
	perf_label.text = "★ " + adv.name

	await get_tree().create_timer(POST_SWITCH_DURATION, true, false, true).timeout

	# 7. 恢复界面
	performance_layer.visible = false
	performance_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = true
	MusicManager.play_hero_shrine_music()

	_refresh_gold_display()
	_build_unit_row()

	_is_performing = false


func _load_sprite_into(sprite: AnimatedSprite2D, path: String):
	if path == "" or not ResourceLoader.exists(path):
		sprite.visible = false
		return
	var frames = load(path) as SpriteFrames
	if not frames:
		sprite.visible = false
		return
	sprite.sprite_frames = frames
	sprite.visible = true
	if frames.has_animation("idle"):
		sprite.play("idle")
	else:
		var anims = frames.get_animation_names()
		if anims.size() > 0:
			sprite.play(anims[0])


# ============================================================
#  关闭
# ============================================================
func _on_close_pressed():
	if _is_performing:
		return
	closed.emit()
	queue_free()


# ============================================================
#  竞技场模式：同步到 GameState.party
# ============================================================
func _sync_advanced_class_to_gamestate(src_unit: UnitData):
	if src_unit == null: return
	print("[HeroShrine][DEBUG] _sync_advanced_class_to_gamestate src=%s/%s class=%s talent=%s" % [
		src_unit.unit_name, src_unit.display_name,
		src_unit.advanced_class, src_unit.advanced_talent_id])
	print("[HeroShrine][DEBUG]   队伍共 %d 个" % GameState.party.size())
	for i in range(GameState.party.size()):
		var u : UnitData = GameState.party[i]
		var match_flag : String = "✅" if (u.unit_name == src_unit.unit_name and u.display_name == src_unit.display_name) else "❌"
		print("[HeroShrine][DEBUG]   [%d] %s/%s %s" % [i, u.unit_name, u.display_name, match_flag])
		if u.unit_name == src_unit.unit_name and u.display_name == src_unit.display_name:
			print("[HeroShrine][DEBUG]     → 匹配，写入 party 单位")
			u.advanced_class = src_unit.advanced_class
			u.advanced_talent_id = src_unit.advanced_talent_id
			u.advanced_talent_inst = src_unit.advanced_talent_inst
			u.override_sprite_path = src_unit.override_sprite_path
			u.max_hp = src_unit.max_hp
			u.strength = src_unit.strength
			u.dexterity = src_unit.dexterity
			u.intelligence = src_unit.intelligence
			u.faith = src_unit.faith
			u.arcane = src_unit.arcane
			u.move_range = src_unit.move_range
			return
	print("[HeroShrine][DEBUG]   → 未匹配到 party 单位")
