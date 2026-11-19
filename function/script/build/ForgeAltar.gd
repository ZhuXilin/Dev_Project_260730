extends CanvasLayer
const BuildUI = preload("res://function/script/build/BuildUI.gd")
## ============================================================
##  ForgeAltar — v6 魂栈专用：熔铸单位（单一功能节点）
## ============================================================
##  魂栈节点 v6 只保留"熔铸单位"：牺牲一名单位换其专属防具。
##  商店 / 铁匠铺 / 光环页已移除。
## ============================================================

signal closed

const FS_TITLE: int = 10
const FS_BODY: int = 7
const FS_SMALL: int = 6

var _root: Panel = null
var _list: VBoxContainer = null
var _info: Label = null
var _gold_color := Color(0.98, 0.75, 0.25)


func _ready() -> void:
	layer = 20
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_root = Panel.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "魂栈 · 熔铸单位"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", _gold_color)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "牺牲一名单位，获得该职业专属防具（无流派，随亡者绑定）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", FS_SMALL)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62))
	vbox.add_child(hint)

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", FS_SMALL)
	_info.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	vbox.add_child(_info)

	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	vbox.add_child(_list)

	var close := Button.new()
	close.text = "离开"
	close.custom_minimum_size = Vector2(0, 14)
	BuildUI.style_button(close, _gold_color)
	close.pressed.connect(_on_close)
	vbox.add_child(close)


func _refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()

	var alive: Array = []
	for ud in GameState.party:
		if ud != null and not ud.is_dead:
			alive.append(ud)

	if alive.size() <= 1:
		_info.text = "已无可熔铸单位（熔铸最后一名单位将导致全灭）"
		return
	_info.text = "存活单位 %d / %d" % [alive.size(), GameState.party.size()]

	for ud in alive:
		var btn := Button.new()
		var melt_id := SacrificeHelper.get_melt_item_id(ud.unit_name)
		var melt_data: ItemData = ItemManager.get_item_data(melt_id)
		var melt_name := melt_data.name if melt_data else "专属防具"
		btn.text = "熔铸 %s → %s" % [ud.display_name, melt_name]
		btn.add_theme_font_size_override("font_size", FS_BODY)
		BuildUI.style_button(btn, _gold_color)
		btn.pressed.connect(_on_sacrifice.bind(ud))
		_list.add_child(btn)


func _on_sacrifice(ud: UnitData) -> void:
	if ud == null or ud.is_dead:
		return
	var melt_id := SacrificeHelper.get_melt_item_id(ud.unit_name)
	var melt_data: ItemData = ItemManager.get_item_data(melt_id)
	var melt_name := melt_data.name if melt_data else "专属防具"
	var alive_count := 0
	for m in GameState.party:
		if m != null and not m.is_dead:
			alive_count += 1
	var msg := "确定熔铸 %s？\n将获得：【%s】" % [ud.display_name, melt_name]
	if alive_count <= 1:
		msg += "\n\n熔铸后全灭，本局将结束并返回营地。"

	Globals.show_confirm(self, msg, "熔铸", "取消",
		func(): _do_sacrifice(ud), func(): pass)


func _do_sacrifice(ud: UnitData) -> void:
	var result: Dictionary = SacrificeHelper.do_sacrifice(GameState.party, ud)

	# 把产出的熔铸防具挂到一个存活单位（无流派，仅作属性防具）
	var melt_id := str(result.get("melt_item_id", ""))
	if melt_id != "":
		var recipient: UnitData = null
		for m in GameState.party:
			if m != null and not m.is_dead:
				recipient = m
				break
		if recipient:
			BuildManager.append_plain_armor(recipient, melt_id)

	var alive_count := 0
	for m in GameState.party:
		if m != null and not m.is_dead:
			alive_count += 1
	if alive_count <= 0:
		GameState.abandon_and_return_to_camp()
		_on_close()
		return

	_refresh()


func _on_close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_close()
