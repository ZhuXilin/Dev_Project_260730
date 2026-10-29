class_name SecretMerchantUI
extends CanvasLayer

signal closed

const KEY_COST : int = 200
const PIN_COST : int = 100
const THRESHOLD_COST : int = 120
const INTEL_COST : int = 40

const ARMOR_TAGS : Array = ["守护", "烈焰", "灰烬", "轮回", "献祭", "余烬"]

const INTEL_OPTIONS : Array = [
	{ "text": "Day1 魂火窃贼：不足 2 魂火时全队 -10% HP", "flag": "intel_day1_boss" },
	{ "text": "Day2 灰烬护盾：破盾需 1 魂火，最多叠 3 层", "flag": "intel_day2_boss" },
	{ "text": "Day3 三形态：每次复活临时扣 3 魂火上限", "flag": "intel_day3_boss" },
]

@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var hint_label : Label = $Panel/VBox/HintLabel
@onready var back_btn : Button = $Panel/VBox/BackBtn

var _item_list : VBoxContainer = null
var _tag_picker_overlay : Control = null
var _info_panel : Control = null
var _closed : bool = false

# 记录悬停的商品信息
var _hover_item : Dictionary = {}
var _hover_type : String = ""

func _ready():
	layer = 25
	MusicManager.play_secret_merchant_music()
	_build_layout()
	_refresh_ui()

	if not back_btn.pressed.is_connected(_on_back_pressed):
		back_btn.pressed.connect(_on_back_pressed)

func _build_layout():
	# 1. 左侧商品列表（滚动）
	var scroll := ScrollContainer.new()
	scroll.name = "ItemScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	$Panel/VBox.add_child(scroll)
	
	var vbox = $Panel/VBox
	var desc_idx : int = 0
	for i in range(vbox.get_child_count()):
		if vbox.get_child(i).name == "DescLabel":
			desc_idx = i
			break
	vbox.move_child(scroll, desc_idx + 1)

	_item_list = VBoxContainer.new()
	_item_list.name = "ItemList"
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_item_list)

	# 2. 右侧信息面板
	var info_scene = load("res://content/scenes/ui/components/ItemInfoPanel.tscn")
	if info_scene:
		_info_panel = info_scene.instantiate()
		_info_panel.name = "RightInfoPanel"
		_info_panel.custom_minimum_size = Vector2(110, 0)
		_info_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
		_info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var hbox = HBoxContainer.new()
		hbox.name = "MainHBox"
		hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(hbox)
		
		vbox.remove_child(scroll)
		hbox.add_child(scroll)
		hbox.add_child(_info_panel)
		
		var back_idx = back_btn.get_index()
		vbox.move_child(hbox, back_idx) # 放在返回按钮上面

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _hover_type != "" and _info_panel:
			Globals.toggle_info_mode()
			_refresh_info_panel()
			get_viewport().set_input_as_handled()

func _refresh_ui():
	soul_label.text = "当前魂: %d" % GameState.soul
	if _item_list == null: return
	for c in _item_list.get_children():
		_item_list.remove_child(c)
		c.queue_free()

	# 1. 死眠之钥
	_add_item_row(
		"死眠之钥", "可在宝箱高级隐藏开启，单局 1 把",
		KEY_COST, GameState.keys < 1 and GameState.soul >= KEY_COST,
		"已达携带上限" if GameState.keys >= 1 else "魂不足",
		_on_buy_key, {"kind": "key", "name": "死眠之钥", "desc": "可以在开启宝箱时使用，必出史诗防具或极高概率出遗物。", "stats": "单局最多持有 1 把。"}
	)

	# 2. 标签定向器
	var pin_active : bool = GameState.pending_tag_pin != ""
	var pin_label : String = "标签定向器"
	if pin_active: pin_label += "（已挂起：%s）" % GameState.pending_tag_pin
	_add_item_row(
		pin_label, "下一局商店前 7 格偏向指定标签",
		PIN_COST, not pin_active and GameState.soul >= PIN_COST,
		"已挂起" if pin_active else "魂不足",
		_on_buy_tag_pin, {"kind": "pin", "name": "标签定向器", "desc": "在下一局游戏的商店中，大幅提高所选标签防具的出现概率。", "stats": "不可叠加。"}
	)

	# 3. 魂火阈值调节器
	var threshold_active : bool = GameState.soul_fire_threshold_override > 0.0
	_add_item_row(
		"魂火阈值调节器", "本局燃烧线 50% → 40%（更易进入燃烧）",
		THRESHOLD_COST, not threshold_active and GameState.soul >= THRESHOLD_COST,
		"本局已使用" if threshold_active else "魂不足",
		_on_buy_threshold, {"kind": "threshold", "name": "魂火阈值调节器", "desc": "下调进入【燃烧】状态所需的魂火比例，让高爆发更容易触发。", "stats": "仅对当前局有效。"}
	)

	# 4. Boss 情报
	_add_item_row(
		"Boss 情报", "揭示一条 Boss 机制（Day1/2/3）",
		INTEL_COST, GameState.soul >= INTEL_COST,
		"魂不足",
		_on_buy_intel, {"kind": "intel", "name": "Boss 情报", "desc": "从黑市买来的小道消息，或许能让你在面对首领时占得先机。", "stats": "购买后永久记录。"}
	)

func _add_item_row(title : String, desc : String, price : int, can_buy : bool, disabled_reason : String, cb : Callable, hover_data : Dictionary):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)

	var title_lb := Label.new()
	title_lb.text = title
	title_lb.add_theme_font_size_override("font_size", 8)
	info.add_child(title_lb)

	var desc_lb := Label.new()
	desc_lb.text = desc
	desc_lb.add_theme_font_size_override("font_size", 6)
	desc_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lb.modulate = Color(0.7, 0.7, 0.7)
	info.add_child(desc_lb)

	var buy_btn := Button.new()
	buy_btn.add_theme_font_size_override("font_size", 7)
	buy_btn.custom_minimum_size = Vector2(70, 24)
	if can_buy:
		buy_btn.text = "%d 魂" % price
		buy_btn.disabled = false
		buy_btn.pressed.connect(cb)
	else:
		buy_btn.text = disabled_reason
		buy_btn.disabled = true
		buy_btn.modulate = Color(0.5, 0.5, 0.5)
	row.add_child(buy_btn)
	
	# 悬停绑定
	row.mouse_entered.connect(_on_item_hover.bind(hover_data))
	row.mouse_exited.connect(_on_item_exit)
	# 给子节点也绑定，确保全覆盖
	title_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_item_list.add_child(row)

func _on_item_hover(data: Dictionary):
	_hover_type = data.get("kind", "")
	_hover_item = data
	_refresh_info_panel()

func _on_item_exit():
	_hover_type = ""
	if _info_panel and _info_panel.has_method("clear_info"):
		_info_panel.clear_info()

func _refresh_info_panel():
	if not _info_panel: return
	if FlavorManager.is_narrative_mode():
		# 用一段模糊的叙事替代
		var flavor = "这是一件不应存在于现世的东西。\n商人说，每一件货物都有自己的代价。"
		_info_panel.show_info({"name": _hover_item.get("name", "未知"), "desc": flavor})
		return
		
	_info_panel.show_info({
		"name": _hover_item.get("name", "未知"),
		"type_str": "黑市商品",
		"desc": _hover_item.get("desc", ""),
		"stats": _hover_item.get("stats", "")
	})

func _on_buy_key():
	if GameState.keys >= 1 or GameState.soul < KEY_COST: return
	GameState.soul -= KEY_COST
	GameState.keys = 1
	GameState.keys_bought += 1 # ★ 文档要求：跨局累计
	SaveManager.auto_save()
	_show_hint("★ 已获得死眠之钥！")
	_refresh_ui()

func _on_buy_tag_pin():
	if GameState.pending_tag_pin != "" or GameState.soul < PIN_COST: return
	_show_tag_picker()

func _on_buy_threshold():
	if GameState.soul_fire_threshold_override > 0.0 or GameState.soul < THRESHOLD_COST: return
	GameState.soul -= THRESHOLD_COST
	GameState.soul_fire_threshold_override = 0.4
	SaveManager.auto_save()
	_show_hint("★ 本局燃烧线已降至 40%。")
	_refresh_ui()

func _on_buy_intel():
	if GameState.soul < INTEL_COST: return
	_show_intel_picker()

func _show_hint(text : String):
	if hint_label:
		hint_label.text = text
		hint_label.modulate = Color(0.7, 1.0, 0.7)

func _close_overlay():
	if _tag_picker_overlay and is_instance_valid(_tag_picker_overlay):
		if _tag_picker_overlay.get_parent():
			_tag_picker_overlay.get_parent().remove_child(_tag_picker_overlay)
		_tag_picker_overlay.free()
	_tag_picker_overlay = null

func _show_tag_picker():
	_close_overlay()

	_tag_picker_overlay = Control.new()
	_tag_picker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_picker_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_tag_picker_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_picker_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -120
	panel.offset_right = 120
	panel.offset_top = -80
	panel.offset_bottom = 80
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.12)
	sb.border_color = Color(0.6, 0.5, 0.8)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	_tag_picker_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择定向标签（下一局商店前 7 格）"
	title.add_theme_font_size_override("font_size", 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	vbox.add_child(grid)

	for tag in ARMOR_TAGS:
		var btn := Button.new()
		btn.text = tag
		btn.add_theme_font_size_override("font_size", 8)
		btn.custom_minimum_size = Vector2(80, 24)
		btn.pressed.connect(_on_tag_selected.bind(tag))
		grid.add_child(btn)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 7)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_close_overlay)
	vbox.add_child(cancel)

func _on_tag_selected(tag : String):
	if GameState.soul < PIN_COST:
		_close_overlay()
		return
	GameState.soul -= PIN_COST
	GameState.pending_tag_pin = tag
	SaveManager.auto_save()
	_close_overlay()
	_show_hint("★ 已挂起标签定向器：%s。下一局商店生效。" % tag)
	_refresh_ui()

func _show_intel_picker():
	_close_overlay()

	_tag_picker_overlay = Control.new()
	_tag_picker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_picker_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_tag_picker_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_picker_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -140
	panel.offset_right = 140
	panel.offset_top = -80
	panel.offset_bottom = 80
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.12)
	sb.border_color = Color(0.6, 0.5, 0.8)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	_tag_picker_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择要购买的情报（每条只买一次）"
	title.add_theme_font_size_override("font_size", 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for opt in INTEL_OPTIONS:
		var text : String = opt.get("text", "")
		var flag : String = opt.get("flag", "")
		var already : bool = flag in GameState.npc_dialogue_flags

		var btn := Button.new()
		btn.text = text + ("（已购）" if already else "")
		btn.add_theme_font_size_override("font_size", 7)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(240, 28)
		btn.disabled = already
		if already:
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.pressed.connect(_on_intel_selected.bind(text, flag))
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 7)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_close_overlay)
	vbox.add_child(cancel)

func _on_intel_selected(text : String, flag : String):
	if GameState.soul < INTEL_COST:
		_close_overlay()
		return
	GameState.soul -= INTEL_COST
	if not (flag in GameState.npc_dialogue_flags):
		GameState.npc_dialogue_flags.append(flag)
	if not (text in GameState.revealed_intel):
		GameState.revealed_intel.append(text)
	SaveManager.auto_save()
	_close_overlay()
	_show_hint("★ 已记入情报簿：%s" % text)
	_refresh_ui()

func _on_back_pressed():
	if _closed: return
	_closed = true
	_close_overlay()
	closed.emit()
	queue_free()
