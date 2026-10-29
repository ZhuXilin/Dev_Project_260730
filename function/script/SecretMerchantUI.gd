class_name SecretMerchantUI
extends CanvasLayer

signal closed

@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var hint_label : Label = $Panel/VBox/HintLabel
@onready var back_btn : Button = $Panel/VBox/BackBtn

var _item_list : VBoxContainer = null
var _tag_picker_overlay : Control = null
var _info_panel : Control = null
var _closed : bool = false

var _hover_item : Dictionary = {}
var _hover_type : String = ""
var _special_items : Dictionary = {}

func _ready():
	layer = 25
	MusicManager.play_secret_merchant_music()
	
	# 加载特殊道具数据
	_special_items = _load_special_items()
	
	_build_layout()
	_refresh_ui()

	if not back_btn.pressed.is_connected(_on_back_pressed):
		back_btn.pressed.connect(_on_back_pressed)


func _load_special_items() -> Dictionary:
	var path : String = Config.PATHS.SPECIAL_ITEM_DATA
	if not FileAccess.file_exists(path):
		push_error("特殊道具数据不存在: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		push_error("特殊道具 JSON 解析失败")
		return {}
	return data


func _build_layout():
	var panel = $Panel
	
	# 恢复居中锚点
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
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.offset_left = 0
		bg.offset_top = 0
		bg.offset_right = 0
		bg.offset_bottom = 0

	var vbox = panel.get_node("VBox")
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
	_item_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_item_list)

	var info_scene = load("res://content/scenes/ui/components/UnitInfoPanel.tscn")
	if info_scene:
		_info_panel = info_scene.instantiate()
		_info_panel.name = "RightInfoPanel"
		_info_panel.custom_minimum_size = Vector2(105, 0)
		_info_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
		_info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.add_child(_info_panel)
		
		var inner_vbox = _info_panel.get_node_or_null("VBox")
		if inner_vbox:
			inner_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		if _info_panel.has_method("clear_info"): _info_panel.clear_info()

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

	for item_id in _special_items:
		var item_data : Dictionary = _special_items[item_id]
		var price : int = int(item_data.get("price", 0))
		
		var can_buy : bool = true
		var disabled_reason : String = str(item_data.get("disabled_reason", "无法购买"))

		# 判断购买状态
		match item_id:
			"key_of_sleep":
				if GameState.keys >= 1:
					can_buy = false
			"tag_pin":
				if GameState.pending_tag_pin != "":
					can_buy = false
					disabled_reason = "已挂起: %s" % GameState.pending_tag_pin
			"sf_threshold":
				if GameState.soul_fire_threshold_override > 0.0:
					can_buy = false
			"boss_intel":
				# 如果所有情报都买了，就不能再买了
				var all_bought := true
				var options : Array = item_data.get("options", [])
				for opt in options:
					if not (str(opt.get("flag", "")) in GameState.npc_dialogue_flags):
						all_bought = false
						break
				if all_bought:
					can_buy = false
					disabled_reason = "已全部购买"

		if can_buy and GameState.soul < price:
			can_buy = false
			disabled_reason = "魂不足"

		_add_item_row(item_data, can_buy, disabled_reason)


func _add_item_row(item_data : Dictionary, can_buy : bool, disabled_reason : String):
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
	
	var icon_path = str(item_data.get("icon", ""))
	if icon_path != "":
		icon_rect.texture = IconManager.get_icon_or_null(icon_path)
	row.add_child(icon_rect)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)

	var title_lb := Label.new()
	title_lb.text = str(item_data.get("name", ""))
	title_lb.add_theme_font_size_override("font_size", 8)
	title_lb.clip_text = true
	info.add_child(title_lb)

	var desc_lb := Label.new()
	desc_lb.text = str(item_data.get("desc", ""))
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
	
	var price : int = int(item_data.get("price", 0))
	if can_buy:
		buy_btn.text = "%d 魂" % price
		buy_btn.disabled = false
		buy_btn.pressed.connect(_on_buy_item.bind(item_data))
	else:
		buy_btn.text = disabled_reason
		buy_btn.disabled = true
		buy_btn.modulate = Color(0.5, 0.5, 0.5)
	row.add_child(buy_btn)
	
	row.mouse_entered.connect(_on_item_hover.bind(item_data))
	row.mouse_exited.connect(_on_item_exit)
	title_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_item_list.add_child(row)
	
	if _item_list.get_child_count() == 1:
		_on_item_hover(item_data)


func _on_item_hover(data: Dictionary):
	_hover_type = str(data.get("id", ""))
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
		"type_str": "特殊道具",
		"desc": _hover_item.get("desc", ""),
		"stats": "价格: %d 魂" % int(_hover_item.get("price", 0))
	})


# ============================================================
#  购买入口分发
# ============================================================
func _on_buy_item(item_data : Dictionary):
	var price : int = int(item_data.get("price", 0))
	if GameState.soul < price: return

	match str(item_data.get("effect_type", "")):
		"grant_key":
			_do_buy_key(item_data)
		"tag_pin":
			_show_option_picker(item_data)
		"sf_threshold":
			_do_buy_threshold(item_data)
		"boss_intel":
			_show_option_picker(item_data)


func _do_buy_key(item_data : Dictionary):
	GameState.soul -= int(item_data.get("price", 0))
	GameState.keys = 1
	GameState.keys_bought += 1
	SaveManager.auto_save()
	_show_hint("★ 已获得死眠之钥！")
	_refresh_ui()


func _do_buy_threshold(item_data : Dictionary):
	GameState.soul -= int(item_data.get("price", 0))
	GameState.soul_fire_threshold_override = float(item_data.get("override_value", 0.4))
	SaveManager.auto_save()
	_show_hint("★ 本局燃烧线已降至 %d%%。" % int(GameState.soul_fire_threshold_override * 100))
	_refresh_ui()


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


# ============================================================
#  通用选项弹窗（用于标签定向器和 Boss 情报）
# ============================================================
func _show_option_picker(item_data : Dictionary):
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
	title.text = "选择：%s" % item_data.get("name", "")
	title.add_theme_font_size_override("font_size", 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(list_vbox)

	var options : Array = item_data.get("options", [])
	for opt in options:
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 8)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		if opt is String:
			# 字符串类型（如标签）
			btn.text = opt
			btn.pressed.connect(_on_option_selected.bind(item_data, opt, ""))
		elif opt is Dictionary:
			# 字典类型（如 Boss 情报）
			var text : String = str(opt.get("text", ""))
			var flag : String = str(opt.get("flag", ""))
			var already : bool = flag in GameState.npc_dialogue_flags
			btn.text = text + ("（已购）" if already else "")
			btn.disabled = already
			if already:
				btn.modulate = Color(0.5, 0.5, 0.5)
			else:
				btn.pressed.connect(_on_option_selected.bind(item_data, text, flag))
		
		list_vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 7)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_close_overlay)
	vbox.add_child(cancel)


func _on_option_selected(item_data : Dictionary, text_or_tag : String, flag : String):
	var price : int = int(item_data.get("price", 0))
	if GameState.soul < price:
		_close_overlay()
		return
		
	GameState.soul -= price
	_close_overlay()
	
	var effect_type = str(item_data.get("effect_type", ""))
	if effect_type == "tag_pin":
		GameState.pending_tag_pin = text_or_tag
		SaveManager.auto_save()
		_show_hint("★ 已挂起标签定向器：%s。下一局商店生效。" % text_or_tag)
	elif effect_type == "boss_intel":
		if not (flag in GameState.npc_dialogue_flags):
			GameState.npc_dialogue_flags.append(flag)
		if not (text_or_tag in GameState.revealed_intel):
			GameState.revealed_intel.append(text_or_tag)
		SaveManager.auto_save()
		_show_hint("★ 已记入情报簿：%s" % text_or_tag)
		
	_refresh_ui()


func _on_back_pressed():
	if _closed: return
	_closed = true
	_close_overlay()
	closed.emit()
	queue_free()
