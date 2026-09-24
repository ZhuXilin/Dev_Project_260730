class_name ChapelUI
extends CanvasLayer

signal closed

var _chosen : bool = false

@onready var panel : Panel = $Panel
@onready var title_label : Label = $Panel/VBox/Title
@onready var hint_label : Label = $Panel/VBox/Hint
@onready var option_row : HBoxContainer = $Panel/VBox/OptionRow
@onready var item_row : HBoxContainer = $Panel/VBox/ItemRow
@onready var back_btn : Button = $Panel/VBox/BottomBar/BackBtn


func _ready():
	layer = 24
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)
	_build_main_options()


# ============================================================
#  主界面
# ============================================================
func _build_main_options():
	_clear_row(option_row)
	_clear_row(item_row)
	option_row.visible = true
	item_row.visible = false
	back_btn.visible = true

	if title_label:
		title_label.text = "圣坛"
	if hint_label:
		hint_label.text = "选择一项祝福"

	_add_option_button("回血", _on_choose_heal)
	_add_option_button("复活", _on_choose_revive)
	_add_option_button("熔铸单位", _on_choose_sacrifice)


func _add_option_button(text: String, cb: Callable):
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 60)
	btn.add_theme_font_size_override("font_size", 9)
	btn.pressed.connect(cb)
	option_row.add_child(btn)


# ============================================================
#  选项 1：回血
# ============================================================
func _on_choose_heal():
	if _chosen: return
	_chosen = true
	for ud in GameState.party:
		if ud.is_dead: continue
		ud.hit_points = ud.max_hp
	SaveManager.auto_save()
	print("[圣坛] 全队 HP 回满")
	if hint_label:
		hint_label.text = "全队 HP 已回满"
	await get_tree().create_timer(0.8, true, false, true).timeout
	_close()


# ============================================================
#  选项 2：复活
# ============================================================
func _on_choose_revive():
	if _chosen: return
	var dead : Array = GameState.get_dead_party()
	if dead.is_empty():
		if hint_label:
			hint_label.text = "没有阵亡单位"
		return
	_show_revive_submenu()


func _show_revive_submenu():
	_clear_row(option_row)
	if hint_label:
		hint_label.text = "选择一名单位复活"

	var dead_units : Array = GameState.get_dead_party()
	for ud in dead_units:
		var btn := Button.new()
		btn.text = "%s（%s）" % [
			ud.display_name,
			UnitDataManager.get_unit_type_display_name(ud.unit_name)
		]
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_revive_unit.bind(ud.unit_name, ud.display_name))
		option_row.add_child(btn)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(100, 40)
	back.add_theme_font_size_override("font_size", 8)
	back.pressed.connect(func(): _build_main_options())
	option_row.add_child(back)


func _on_revive_unit(unit_name: String, display_name: String):
	if _chosen: return
	_chosen = true
	if GameState.revive_unit(unit_name, display_name):
		SaveManager.auto_save()
		print("[圣坛] 复活 %s" % display_name)
		if hint_label:
			hint_label.text = "%s 已复活" % display_name
		await get_tree().create_timer(0.8, true, false, true).timeout
	_close()


# ============================================================
#  选项 3：熔铸
# ============================================================
func _on_choose_sacrifice():
	if _chosen: return
	var alive : Array = []
	for ud in GameState.party:
		if not ud.is_dead:
			alive.append(ud)
	if alive.size() <= 1:
		if hint_label:
			hint_label.text = "至少保留 1 个存活单位，无法熔铸"
		return
	_show_sacrifice_submenu()


func _show_sacrifice_submenu():
	_clear_row(option_row)
	var next_count : int = GameState.sacrifice_count + 1
	var preview : Dictionary = SacrificeHelper.get_reward_preview(next_count)
	var hint_text : String = "熔铸：获得 %d 金币 + %d 件史诗防具" % [
		preview["gold"], preview["epic_count"]
	]
	if preview["relic"]:
		hint_text += " + 1 遗物"
	if hint_label:
		hint_label.text = hint_text

	for ud in GameState.party:
		if ud.is_dead: continue
		var btn := Button.new()
		btn.text = ud.display_name
		btn.custom_minimum_size = Vector2(110, 40)
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_sacrifice_unit_picked.bind(ud))
		option_row.add_child(btn)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(100, 40)
	back.add_theme_font_size_override("font_size", 8)
	back.pressed.connect(func(): _build_main_options())
	option_row.add_child(back)


func _on_sacrifice_unit_picked(u: UnitData):
	if _chosen: return
	Globals.show_confirm(
		self,
		"确定熔铸 %s？\n该单位将被冻结，本局不可用。" % u.display_name,
		"熔铸", "取消",
		func(): _do_sacrifice_and_close(u),
		func(): pass
	)


func _do_sacrifice_and_close(u: UnitData):
	if _chosen: return
	_chosen = true

	var result : Dictionary = SacrificeHelper.do_sacrifice(GameState.party, u)
	print("[圣坛] 熔铸 %s：+%dG +%d 史诗" % [u.display_name, result["gold"], result["epic_count"]])

	var msg : String = "已熔铸 %s\n+%d 金币 +%d 史诗防具（已进待领取）" % [
		u.display_name, result["gold"], result["epic_count"]
	]
	if result["relic_id"] != "":
		var rd : Dictionary = RelicManager.get_relic_data(result["relic_id"])
		msg += "\n★ 遗物：" + rd.get("name", result["relic_id"])
	if hint_label:
		hint_label.text = msg
	await get_tree().create_timer(1.2, true, false, true).timeout
	_close()


# ============================================================
#  辅助
# ============================================================
func _clear_row(row: Node):
	if not row: return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()


func _on_back_pressed():
	if _chosen: return
	close_without_choice()


func close_without_choice():
	_chosen = true
	SaveManager.auto_save()
	_close()


func _close():
	if not is_inside_tree(): return
	closed.emit()
	queue_free()
