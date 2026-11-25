extends CanvasLayer

signal closed

var COST_PER_CLASS : int = 0

const PERFORMANCE_DURATION : float = 2.0
const POST_SWITCH_DURATION : float = 0.8

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/TopBar/TitleLabel
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

var _max_conversions : int = 1
var _converted_count : int = 0

var _is_chapel_mode : bool = false

# ============================================================
#  上下文设置
# ============================================================
func setup_arena(arena_node, unit_data) -> void:
	_mode = "arena"
	_arena_ref = arena_node
	_custom_party = [unit_data] if unit_data else []
	_max_conversions = 1
	_converted_count = 0
	if is_node_ready():
		_rebuild()


func setup_map(max_conversions: int = 1) -> void:
	_mode = "map"
	_arena_ref = null
	_custom_party = []
	_max_conversions = max_conversions
	_converted_count = 0
	if is_node_ready():
		_rebuild()


func _rebuild():
	_build_unit_row()


func _get_party() -> Array:
	if not _custom_party.is_empty():
		return _custom_party
	return GameState.party


func _get_soul() -> int:
	return GameState.soul


func _subtract_soul(amount: int) -> void:
	GameState.soul -= amount


func _reached_limit() -> bool:
	return _max_conversions >= 0 and _converted_count >= _max_conversions


# ============================================================
#  初始化
# ============================================================
func _ready():
	COST_PER_CLASS = 0
	# ★ v6.62i：英灵殿无资源消费（转职免费 / 献祭赋能不花钱），已删除持有魂与费用文字节点
	performance_layer.visible = false
	
	var sprite_box = get_node_or_null("PerformanceLayer/CenterBox/SpriteBox")
	if sprite_box:
		sprite_box.custom_minimum_size = Vector2(32, 32)
	if perf_sprite:
		perf_sprite.position = Vector2(16, 16)
		perf_sprite.scale = Vector2(1, 1)

	MusicManager.play_hero_shrine_music()
	_build_unit_row()


func setup_as_chapel():
	_is_chapel_mode = true
	if is_node_ready():
		# 修改顶部提示语
		if hint_label:
			hint_label.text = "选择一个单位转职或复活"
		# 重新构建UI以应用阵亡单位的点击逻辑
		_build_unit_row()


func _on_revive_unit(unit_name: String, display_name: String):
	# ★ v6.66：复活统一 400G（资源成本代替次数限制）
	var res: Dictionary = GameState.revive_unit_with_cost(unit_name, display_name)
	if bool(res.get("ok", false)):
		SaveManager.auto_save()
		if hint_label:
			hint_label.text = "%s 已复活（花费 %dG），现在可以选择转职" % [display_name, int(res.get("cost", 0))]
		_build_unit_row()
		SoundManager.play_heal_sound()
		MusicManager.play_hero_shrine_music()
	else:
		_show_hint(str(res.get("reason", "复活失败")))

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

	# ★ v6.62p：赋能单位统一用 overlord 图片/动画
	var idle_path : String = UnitDataManager.EMPOWERED_FRAMES_PATH if unit.is_empowered else unit.override_sprite_path
	var texture_rect = UnitDataManager.create_idle_texture_rect(unit.unit_name, Vector2(32, 32), idle_path)
	texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(texture_rect)

	var name_lb = Label.new()
	name_lb.add_theme_font_size_override("font_size", 9)
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lb)

	var status_lb = Label.new()
	status_lb.add_theme_font_size_override("font_size", 7)
	status_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(status_lb)

	if unit.advanced_class != "":
		var adv_name : String = AdvancedClassManager.get_display_name(unit.advanced_class)
		name_lb.text = unit_display + "\n" + type_cn
		var suffix : String = "（已转职）"
		var dim_color : Color = Color(0.55, 0.55, 0.55, 1)
		var card_color : Color = Color(0.7, 0.7, 0.7, 1)
		if unit.is_dead:
			suffix = "（已转职 · 已阵亡）"
			dim_color = Color(0.4, 0.4, 0.4, 1)
			card_color = Color(0.5, 0.5, 0.5, 1)
		name_lb.modulate = dim_color
		status_lb.text = "★ " + adv_name + "\n" + suffix
		status_lb.modulate = dim_color
		card.modulate = card_color
		texture_rect.modulate = card_color
		return card

	if unit.is_dead:
		name_lb.text = unit_display + "\n" + type_cn
		name_lb.modulate = Color(0.4, 0.4, 0.4, 1)
		
		# ★ 核心修复：移除 _is_chapel_mode 判断，所有阵亡单位都可以点击复活
		status_lb.text = "已阵亡\n(点击复活)"
		status_lb.modulate = Color(0.8, 0.6, 0.6, 1)
		card.modulate = Color(0.8, 0.8, 0.8, 1)
		texture_rect.modulate = Color(0.6, 0.6, 0.6, 1)
		
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_dead_card_input.bind(unit_idx))
		card.mouse_entered.connect(_on_card_hover_enter.bind(card))
		card.mouse_exited.connect(_on_card_hover_exit.bind(card))
		return card

	var branches : Array = AdvancedClassManager.get_branches_for_unit(unit.unit_name)
	if branches.is_empty():
		name_lb.text = unit_display + "\n" + type_cn
		status_lb.text = "无转职"
		status_lb.modulate = Color(0.55, 0.55, 0.55, 1)
		card.modulate = Color(0.7, 0.7, 0.7, 1)
		return card

	name_lb.text = unit_display + "\n" + type_cn
	if unit.is_empowered:
		# ★ v6.59：已赋能单位显示超级化标记，不能转职
		status_lb.text = "★ 已超级化\n（不可转职）\nHP %d / 攻 %d" % [unit.max_hp, int(unit.attack)]
		status_lb.modulate = Color(1.0, 0.82, 0.3)
		card.modulate = Color(1.0, 0.95, 0.75)
		return card
	# ★ v6.62：红框的转职分支详情（★分支列表 / 点击查看）不再显示，只留极简状态
	status_lb.text = "可转职"

	var reached : bool = _reached_limit()
	if reached:
		status_lb.modulate = Color(0.55, 0.55, 0.55, 1)
		card.modulate = Color(0.7, 0.7, 0.7, 1)
		status_lb.text = "本次已转职"
	else:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_input.bind(unit_idx))
		card.mouse_entered.connect(_on_card_hover_enter.bind(card))
		card.mouse_exited.connect(_on_card_hover_exit.bind(card))

	return card


func _build_unit_row():
	for child in unit_row.get_children():
		unit_row.remove_child(child)
		child.queue_free()

	var party : Array = _get_party()
	print("[HeroShrine] 构建单位列表：", party.size(), " 个，mode=", _mode)
	for i in range(party.size()):
		# ★ v6.59：每个单位卡片下方加献祭按钮（献祭=赋能到幸存单位）
		var wrapper := VBoxContainer.new()
		wrapper.add_theme_constant_override("separation", 4)
		wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var card_ctrl : PanelContainer = _build_unit_card(i)
		card_ctrl.custom_minimum_size = Vector2(118, 0)  # 三卡并排需适配 400px 视口
		wrapper.add_child(card_ctrl)
		var sac_btn := Button.new()
		var unit : UnitData = party[i]
		if unit == null: continue
		# 献祭按钮与卡片等宽，紧随卡片下方
		sac_btn.custom_minimum_size = Vector2(118, 20)
		sac_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sac_btn.add_theme_font_size_override("font_size", 9)
		if unit.is_dead:
			sac_btn.text = "（已阵亡）"
			sac_btn.disabled = true
		elif unit.is_empowered:
			sac_btn.text = "（已赋能）"
			sac_btn.disabled = true
		else:
			sac_btn.text = "献祭"
			sac_btn.disabled = false
			sac_btn.pressed.connect(_on_sacrifice_requested.bind(i))
		wrapper.add_child(sac_btn)
		unit_row.add_child(wrapper)


# ============================================================
#  ★ v6.59 献祭赋能流程（合入英灵殿）
# ============================================================
func _on_sacrifice_requested(source_idx: int) -> void:
	var party : Array = _get_party()
	if source_idx < 0 or source_idx >= party.size(): return
	var source : UnitData = party[source_idx]
	if source == null or source.is_dead or source.is_empowered: return

	# 候选 = 其余存活、且未被赋能的单位
	var candidates : Array = []
	for i in range(party.size()):
		if i == source_idx: continue
		var u : UnitData = party[i]
		if u != null and not u.is_dead and not u.is_empowered:
			candidates.append({"idx": i, "unit": u})
	if candidates.is_empty():
		_show_hint("没有可赋能的存活单位")
		return

	var src_name : String = source.display_name if source.display_name != "" else source.unit_name
	# 两张候选卡片（用单位头像 + 名称），点击即赋能
	var data_a : Dictionary = {}
	var data_b : Dictionary = {}
	if candidates.size() >= 1:
		data_a = _make_empower_choice(candidates[0], source)
	if candidates.size() >= 2:
		data_b = _make_empower_choice(candidates[1], source)
	if data_a.is_empty():
		_show_hint("至少需要一名存活单位接受赋能")
		return

	var picked_cb : Callable = data_a.get("cb", Callable())
	if data_b.is_empty():
		Globals.show_confirm(self,
			"献祭 %s —— 让 %s 接受赋能？" % [src_name, data_a.get("title", "")],
			"确认赋能", "取消", picked_cb, func(): _show_hint("已取消献祭"))
	else:
		# ★ v6.62：两个候选左右并排，均为单位头像按钮
		Globals.show_choice(self,
			"献祭 %s —— 选择接受赋能的单位" % src_name,
			data_a, data_b,
			func(): _show_hint("已取消献祭"), true)


func _make_empower_choice(candidate: Dictionary, source: UnitData) -> Dictionary:
	var u : UnitData = candidate["unit"]
	var dname : String = u.display_name if u.display_name != "" else u.unit_name
	# ★ v6.62d：头像下方数据区显示"赋能后"的单位数值，作为玩家判断依据
	var idx : int = int(candidate["idx"])
	var lines : Array = ["【%s 赋能后】" % dname]
	lines.append("HP   %d → %d" % [u.max_hp, u.max_hp + int(source.max_hp)])
	lines.append("攻击 %d → %d" % [int(u.attack), int(u.attack + source.attack)])
	lines.append("力量 %d → %d" % [int(u.strength), int(u.strength + source.strength)])
	lines.append("敏捷 %d → %d" % [int(u.dexterity), int(u.dexterity + source.dexterity)])
	lines.append("智力 %d → %d" % [int(u.intelligence), int(u.intelligence + source.intelligence)])
	lines.append("信仰 %d → %d" % [int(u.faith), int(u.faith + source.faith)])
	return {
		"title": dname,
		"detail": "\n".join(lines),
		"avatar_unit": u.unit_name,
		"color": Color(0.6, 0.65, 0.72),
		"cb": func(): _do_empower(source, u, idx),
	}


func _do_empower(source: UnitData, target: UnitData, _target_idx: int) -> void:
	var result : Dictionary = SacrificeHelper.empower_unit(source, target)
	if not bool(result.get("ok", false)):
		_show_hint("赋能失败")
		return
	SoundManager.play_get_item_sound()
	_show_hint("%s 已超级化（献祭 %s）" % [
		target.display_name if target.display_name != "" else target.unit_name,
		source.display_name if source.display_name != "" else source.unit_name])
	_build_unit_row()
	# 同步竞技场上下文（若在竞技场模式）
	if _mode == "arena" and not _custom_party.is_empty():
		_custom_party = _get_party().duplicate()


func _show_hint(text: String) -> void:
	if hint_label:
		hint_label.text = text


func _make_picker_panel(unit : UnitData, branches : Array) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var center_box := CenterContainer.new()
	center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center_box)

	var picker_panel := PanelContainer.new()
	picker_panel.custom_minimum_size = Vector2(440, 0)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	picker_panel.add_theme_stylebox_override("panel", sb)
	center_box.add_child(picker_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	picker_panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择转职方向"
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vbox.add_child(row)

	for b in branches:
		var adv : AdvancedClassData = b
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(130, 0)
		col.add_theme_constant_override("separation", 6)
		col.alignment = BoxContainer.ALIGNMENT_BEGIN
		
		var sprite_wrapper := Control.new()
		sprite_wrapper.custom_minimum_size = Vector2(32, 32) 
		sprite_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(sprite_wrapper)

		# ★ 恢复为读取序列帧动画（局内图标）
		var texture_rect = null
		if adv.sprite_frames_path != "" and ResourceLoader.exists(adv.sprite_frames_path):
			var frames = load(adv.sprite_frames_path) as SpriteFrames
			if frames and frames.has_animation("idle"):
				texture_rect = TextureRect.new()
				texture_rect.custom_minimum_size = Vector2(32, 32)
				texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				
				# 初始帧
				texture_rect.texture = frames.get_frame_texture("idle", 0)
				
				# 加入动画循环逻辑
				var timer := Timer.new()
				timer.wait_time = 0.25
				timer.autostart = true
				texture_rect.add_child(timer)
				var frame_count := frames.get_frame_count("idle")
				var idx := {"value": 0}
				timer.timeout.connect(func():
					if not is_instance_valid(texture_rect): return
					idx["value"] = (idx["value"] + 1) % frame_count
					var t = frames.get_frame_texture("idle", idx["value"])
					if t: texture_rect.texture = t
				)
		
		# 如果没有专属转职动画，则显示基础单位的局内动画
		if not texture_rect:
			texture_rect = UnitDataManager.create_idle_texture_rect(unit.unit_name, Vector2(32, 32))

		sprite_wrapper.add_child(texture_rect)

		var name_lb := Label.new()
		name_lb.text = "★ " + adv.name
		name_lb.add_theme_font_size_override("font_size", 10)
		name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_lb)

		var desc_lb := Label.new()
		desc_lb.text = adv.description
		desc_lb.add_theme_font_size_override("font_size", 7)
		desc_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(desc_lb)

		var stats_lb := Label.new()
		var stats_text : Array = []
		for k in adv.stat_bonus:
			stats_text.append("%s +%d" % [_attr_short(k), int(adv.stat_bonus[k])])
		stats_lb.text = "\n".join(stats_text)
		stats_lb.add_theme_font_size_override("font_size", 7)
		stats_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_lb.modulate = Color(0.7, 0.9, 0.7)
		col.add_child(stats_lb)

		# ★ v6.64：转职爽点预告——让玩家在选之前就看到"魂火玩法怎么变"
		var ident_lb := Label.new()
		var ident : Dictionary = SoulFireIdentity.resolve(unit.unit_name, adv.id)
		var burn_d : Dictionary = ident.get("burn_trait", {})
		var burst_d : Dictionary = ident.get("burst_trait", {})
		var burn_desc : String = str(burn_d.get("desc", "")) if burn_d is Dictionary else ""
		var burst_desc : String = str(burst_d.get("desc", "")) if burst_d is Dictionary else ""
		ident_lb.text = "燃烧：%s\n爆发：%s" % [burn_desc if burn_desc != "" else "—", burst_desc if burst_desc != "" else "—"]
		ident_lb.add_theme_font_size_override("font_size", 6)
		ident_lb.add_theme_color_override("font_color", Color(1.0, 0.72, 0.35))
		ident_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ident_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(ident_lb)

		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(spacer)

		var btn := Button.new()
		btn.text = "选择"
		btn.add_theme_font_size_override("font_size", 9)
		btn.custom_minimum_size = Vector2(80, 22)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(func():
			overlay.queue_free()
			_begin_convert(unit, adv)
		)
		col.add_child(btn)

		row.add_child(col)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 8)
	cancel.custom_minimum_size = Vector2(80, 20)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(cancel)

	return overlay

func _attr_short(key: String) -> String:
	match key:
		"max_hp":       return "HP"
		"strength":     return "力"
		"dexterity":    return "灵"
		"intelligence": return "智"
		"faith":        return "信"
		"move_range":   return "移"
		_:              return key


func _on_card_hover_enter(card: PanelContainer):
	card.modulate = Color(1.2, 1.2, 1.2, 1)


func _on_card_hover_exit(card: PanelContainer):
	card.modulate = Color.WHITE


func _on_dead_card_input(event: InputEvent, unit_idx: int):
	if _is_performing:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
		
	var party : Array = _get_party()
	if unit_idx < 0 or unit_idx >= party.size(): return
	var unit : UnitData = party[unit_idx]
	
	# 直接调用复活逻辑
	_on_revive_unit(unit.unit_name, unit.display_name)


func _on_card_input(event: InputEvent, unit_idx: int):
	if _is_performing:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_on_card_clicked(unit_idx)


# ============================================================
#  点击卡片 → 二选一弹窗
# ============================================================
func _on_card_clicked(unit_idx: int):
	if _is_performing: return
	if _reached_limit(): return
	var party : Array = _get_party()
	if unit_idx < 0 or unit_idx >= party.size(): return
	if _get_soul() < COST_PER_CLASS: return

	var unit : UnitData = party[unit_idx]
	if unit.advanced_class != "": return
	if unit.is_dead: return # 阵亡单位走 _on_dead_card_input，这里拦截一下防误触
	if unit.is_empowered:
		_show_hint("已赋能单位不能转职，复活被献祭单位解除赋能后再转职")
		return

	var branches : Array = AdvancedClassManager.get_branches_for_unit(unit.unit_name)
	if branches.is_empty():
		return
	if branches.size() == 1:
		_begin_convert(unit, branches[0])
		return
	_show_branch_picker(unit, branches)


func _show_branch_picker(unit : UnitData, branches : Array):
	var picker := _make_picker_panel(unit, branches)
	add_child(picker)


# ============================================================
#  转职流程
# ============================================================
func _begin_convert(unit : UnitData, adv : AdvancedClassData):
	if _is_performing:
		return
	if _get_soul() < COST_PER_CLASS:
		return
	if _reached_limit():
		return

	_is_performing = true

	print("[HeroShrine][DEBUG] _begin_convert unit=%s/%s adv=%s granted_talent=%s" % [
		unit.unit_name, unit.display_name, adv.id, adv.granted_talent])

	# 1. 立即扣魂 + 记录
	_subtract_soul(COST_PER_CLASS)
	unit.advanced_class = adv.id
	# ★ v6.64：转职 = 魂火身份升级——名号变化 + 定格提示（爆发/燃烧玩法已由身份表接管）
	var adv_name : String = SoulFireIdentity.get_advanced_name(adv.id)
	if adv_name != "":
		unit.display_name = adv_name
		SignalBus.request_hint_override.emit("转职完成 · %s" % adv_name, 1.0)

	unit.tags.clear()
	for t in adv.tags:
		unit.tags.append(t)

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
			"move_range":   unit.move_range += val

	if adv.granted_talent != "":
		# ★ v6.63：体系「1 主动 + 1 转职被动」——转职主动一律降为残响被动（combo），
		#   不再产生第二个攻击按钮；原 active 的流派标签由防具词条承载。
		var granted : String = TalentManager.resolve_granted_talent(adv.granted_talent)
		unit.advanced_talent_id = granted
		var t_inst := TalentInstance.new()
		t_inst.talent_id = granted
		t_inst.is_active = true
		var tdata = TalentManager.get_talent_data(granted)
		if tdata and tdata.is_active_skill:
			t_inst.is_ready = true
			t_inst.cooldown_remaining = 0
		unit.advanced_talent_inst = t_inst

	if adv.sprite_frames_path != "":
		unit.override_sprite_path = adv.sprite_frames_path

	_converted_count += 1

	if _mode == "map":
		SaveManager.auto_save()
	else:
		_sync_advanced_class_to_gamestate(unit)
		SaveManager.auto_save()
	print("[HeroShrine] %s 转职为 %s（%s 模式，魂已扣，本次已转 %d/%d）" % [
		unit.display_name, adv.name, _mode, _converted_count, _max_conversions])

	# 2. 演出
	panel.visible = false
	performance_layer.visible = true
	performance_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	perf_label.text = "英灵降临..."

	var base_path : String = UnitDataManager.get_sprite_frames_path(unit.unit_name)
	_load_sprite_into(perf_sprite, base_path)

	MusicManager.play_hero_shrine_convert_music()
	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout

	var adv_path : String = adv.sprite_frames_path if adv.sprite_frames_path != "" else base_path
	_load_sprite_into(perf_sprite, adv_path)
	perf_label.text = "★ " + adv.name

	await get_tree().create_timer(POST_SWITCH_DURATION, true, false, true).timeout

	# 3. 恢复界面
	performance_layer.visible = false
	performance_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = true
	MusicManager.play_hero_shrine_music()

	_build_unit_row()

	if _reached_limit():
		if hint_label:
			hint_label.text = "本次转职已完成"
		if close_btn:
			close_btn.text = "完成"

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

	for i in range(GameState.party.size()):
		var u : UnitData = GameState.party[i]
		if u.unit_name == src_unit.unit_name and u.display_name == src_unit.display_name:
			u.advanced_class = src_unit.advanced_class
			u.advanced_talent_id = src_unit.advanced_talent_id
			u.advanced_talent_inst = src_unit.advanced_talent_inst
			u.override_sprite_path = src_unit.override_sprite_path
			u.max_hp = src_unit.max_hp
			u.strength = src_unit.strength
			u.dexterity = src_unit.dexterity
			u.intelligence = src_unit.intelligence
			u.faith = src_unit.faith
			# ★ 已移除：u.arcane = src_unit.arcane（UnitData无此字段）
			u.move_range = src_unit.move_range

			u.tags.clear()
			for t in src_unit.tags:
				u.tags.append(t)
			return
