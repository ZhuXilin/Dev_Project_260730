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
	var panel = $Panel
	
	# ★ 核心修复：恢复居中锚点，设定一个合适的固定宽高，让背景图回到原位
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -170
	panel.offset_right = 170
	panel.offset_top = -105
	panel.offset_bottom = 105

	var bg = panel.get_node_or_null("BackgroundImage")
	if bg:
		# 确保背景图覆盖面板区域
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.offset_left = 0
		bg.offset_top = 0
		bg.offset_right = 0
		bg.offset_bottom = 0

	var vbox = panel.get_node("VBox")
	# 留出下边距，让离开按钮不要太贴边
	vbox.offset_bottom = -8
	
	var old_buy_btn = vbox.get_node_or_null("BuyBtn")
	if old_buy_btn: old_buy_btn.queue_free()
	var old_desc = vbox.get_node_or_null("DescLabel")
	if old_desc: old_desc.queue_free()

	var title_bar = vbox.get_node_or_null("TitleBar")
	if title_bar:
		title_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var hbox = HBoxContainer.new()
	hbox.name = "MainHBox"
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL 
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(hbox)
	
	var idx = 1
	if title_bar:
		idx = title_bar.get_index() + 1
	vbox.move_child(hbox, idx)

	var scroll := ScrollContainer.new()
	scroll.name = "ItemScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(scroll)

	_item_list = VBoxContainer.new()
	_item_list.name = "ItemList"
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	_item_list.add_theme_constant_override("separation", 2) # 缩小商品间距
	scroll.add_child(_item_list)

	var info_scene = load("res://content/scenes/ui/components/UnitInfoPanel.tscn")
	if info_scene:
		_info_panel = info_scene.instantiate()
		_info_panel.name = "RightInfoPanel"
		_info_panel.custom_minimum_size = Vector2(105, 0)
		_info_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
		_info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.add_child(_info_panel)
		
		# 强制内部 VBox 撑开，防止背景断截
		var inner_vbox = _info_panel.get_node_or_null("VBox")
		if inner_vbox:
			inner_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		if _info_panel.has_method("clear_info"): _info_panel.clear_info()

	# 调整按钮和提示的层级，保证在最下方
	if hint_label:
		vbox.remove_child(hint_label)
		vbox.add_child(hint_label)
		hint_label.size_flags_vertical = Control.SIZE_SHRINK_END
	if back_btn:
		vbox.remove_child(back_btn)
		vbox.add_child(back_btn)
		back_btn.size_flags_vertical = Control.SIZE_SHRINK_END
		back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

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

	_add_item_row(
		"死眠之钥", "可在宝箱高级隐藏开启，单局1把",
		KEY_COST, GameState.keys < 1 and GameState.soul >= KEY_COST,
		"已达上限" if GameState.keys >= 1 else "魂不足",
		_on_buy_key, {"kind": "key", "name": "死眠之钥", "desc": "可以在开启宝箱时使用，必出史诗防具或极高概率出遗物。", "stats": "单局最多持有 1 把。"}
	)

	var pin_active : bool = GameState.pending_tag_pin != ""
	var pin_label : String = "标签定向器"
	if pin_active: pin_label += "（已挂起：%s）" % GameState.pending_tag_pin
	_add_item_row(
		pin_label, "下一局商店前7格偏向指定标签",
		PIN_COST, not pin_active and GameState.soul >= PIN_COST,
		"已挂起" if pin_active else "魂不足",
		_on_buy_tag_pin, {"kind": "pin", "name": "标签定向器", "desc": "在下一局游戏的商店中，大幅提高所选标签防具的出现概率。", "stats": "不可叠加。"}
	)

	var threshold_active : bool = GameState.soul_fire_threshold_override > 0.0
	_add_item_row(
		"魂火阈值调节器", "本局燃烧线50%→40%（更易进入燃烧）",
		THRESHOLD_COST, not threshold_active and GameState.soul >= THRESHOLD_COST,
		"已使用" if threshold_active else "魂不足",
		_on_buy_threshold, {"kind": "threshold", "name": "魂火阈值调节器", "desc": "下调进入【燃烧】状态所需的魂火比例，让高爆发更容易触发。", "stats": "仅对当前局有效。"}
	)

	_add_item_row(
		"Boss 情报", "揭示一条 Boss 机制（Day1/2/3）",
		INTEL_COST, GameState.soul >= INTEL_COST,
		"魂不足",
		_on_buy_intel, {"kind": "intel", "name": "Boss 情报", "desc": "从黑市买来的小道消息，或许能让你在面对首领时占得先机。", "stats": "购买后永久记录。"}
	)

func _add_item_row(title : String, desc : String, price : int, can_buy : bool, disabled_reason : String, cb : Callable, hover_data : Dictionary):
	# ★ 进一步压缩行高，显示更多物品
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 26) 

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(18, 18)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var icon_path = ""
	var kind = hover_data.get("kind", "")
	match kind:
		"key": icon_path = "item/item_021"
		"pin": icon_path = "item/item_054"
		"threshold": icon_path = "item/item_045"
		"intel": icon_path = "item/item_100"
	
	if icon_path != "":
		icon_rect.texture = IconManager.get_icon_or_null(icon_path)
	row.add_child(icon_rect)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)

	var title_lb := Label.new()
	title_lb.text = title
	title_lb.add_theme_font_size_override("font_size", 8)
	title_lb.clip_text = true
	info.add_child(title_lb)

	var desc_lb := Label.new()
	desc_lb.text = desc
	desc_lb.add_theme_font_size_override("font_size", 6)
	desc_lb.modulate = Color(0.7, 0.7, 0.7)
	desc_lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	desc_lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(desc_lb)

	var buy_btn := Button.new()
	buy_btn.add_theme_font_size_override("font_size", 7)
	buy_btn.custom_minimum_size = Vector2(54, 18)
	buy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	if can_buy:
		buy_btn.text = "%d 魂" % price
		buy_btn.disabled = false
		buy_btn.pressed.connect(cb)
	else:
		buy_btn.text = disabled_reason
		buy_btn.disabled = true
		buy_btn.modulate = Color(0.5, 0.5, 0.5)
	row.add_child(buy_btn)
	
	row.mouse_entered.connect(_on_item_hover.bind(hover_data))
	row.mouse_exited.connect(_on_item_exit)
	title_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_item_list.add_child(row)
	
	if _item_list.get_child_count() == 1:
		_on_item_hover(hover_data)

func _on_item_hover(data: Dictionary):
	_hover_type = data.get("kind", "")
	_hover_item = data
	_refresh_info_panel()

func _on_item_exit():
	_hover_type = ""

func _refresh_info_panel():
	if not _info_panel: return
	if FlavorManager.is_narrative_mode():
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
	GameState.keys_bought += 1
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
		_tag_picker_overlay.queue_free()
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
