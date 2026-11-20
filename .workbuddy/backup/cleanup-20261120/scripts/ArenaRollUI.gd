extends CanvasLayer
## ============================================================
##  ArenaRollUI — v6.10 竞技场专用防具老虎机
## ============================================================
##  复用主线 SlotMachineUI + BuildManager 数值口径，但使用竞技场独立金币
##  与单单位（不碰 GameState.party / temp_gold）。
##  每场胜利后由 Arena 拉起，抽到防具后直接落位到该单位并重建机制。
##  用法：
##    var ui := ArenaRollUI.new()
##    add_child(ui)
##    ui.setup(unit_data, get_arena_gold, set_arena_gold)
##    await ui.closed
## ============================================================

signal closed

const BuildUI = preload("res://function/script/build/BuildUI.gd")
const SlotMachineUI = preload("res://function/script/build/SlotMachineUI.gd")

const FS_TITLE: int = 10
const FS_BODY: int = 8
const FS_SMALL: int = 6

var _unit: UnitData = null
var _get_gold: Callable = Callable()
var _set_gold: Callable = Callable()
var _machine = null
var _gold_label: Label = null
var _msg: Label = null
var _current: Dictionary = {}
var _quality_level: int = 0
var _roll_count: int = 0
var _closing: bool = false

var _gold_color := Color(0.98, 0.75, 0.25)
var _dim_color := Color(0.6, 0.6, 0.65)


func setup(unit: UnitData, get_gold: Callable, set_gold: Callable) -> void:
	_unit = unit
	_get_gold = get_gold
	_set_gold = set_gold
	_build_ui()
	_machine.setup(BuildManager.get_armor_roll_pool(_quality_level, 8), "竞技场防具抽取")
	_machine.set_start_enabled(_gold() >= _roll_cost())
	_update_gold()


func _gold() -> int:
	return int(_get_gold.call()) if _get_gold.is_valid() else 0


func _set_gold_value(v: int) -> void:
	if _set_gold.is_valid():
		_set_gold.call(v)


func _roll_cost() -> int:
	return 100 + 50 * _roll_count


func _upgrade_cost() -> int:
	var costs: Array = [200, 500, 1200, 2500, 5000]
	if _quality_level >= costs.size():
		return -1
	return int(costs[_quality_level])


func _build_ui() -> void:
	layer = 30
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16)
	sb.set_border_width_all(2)
	sb.border_color = _gold_color
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "竞技场 · 防具老虎机"
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", _gold_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", FS_BODY)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_gold_label)

	_machine = SlotMachineUI.new()
	_machine.custom_minimum_size = Vector2(0, 96)
	vbox.add_child(_machine)
	_machine.started.connect(_on_spin_started)
	_machine.stopped.connect(_on_stopped)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var equip_btn := Button.new()
	equip_btn.text = "装备抽到的防具"
	equip_btn.add_theme_font_size_override("font_size", FS_BODY)
	equip_btn.custom_minimum_size = Vector2(100, 20)
	equip_btn.pressed.connect(_on_equip)
	btn_row.add_child(equip_btn)

	var up_btn := Button.new()
	up_btn.text = "升级品质"
	up_btn.add_theme_font_size_override("font_size", FS_BODY)
	up_btn.custom_minimum_size = Vector2(80, 20)
	up_btn.pressed.connect(_on_upgrade)
	btn_row.add_child(up_btn)

	var leave := Button.new()
	leave.text = "离开"
	leave.add_theme_font_size_override("font_size", FS_BODY)
	leave.custom_minimum_size = Vector2(60, 20)
	leave.pressed.connect(_on_close)
	vbox.add_child(leave)

	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", FS_SMALL)
	_msg.add_theme_color_override("font_color", _dim_color)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.custom_minimum_size = Vector2(240, 0)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_msg)


func _update_gold() -> void:
	if _gold_label:
		_gold_label.text = "竞技金币：%d ｜ 本次抽取 %dG ｜ 品质 Lv%d" % [_gold(), _roll_cost(), _quality_level]
	if _machine:
		_machine.set_start_enabled(_gold() >= _roll_cost())


func _on_spin_started() -> void:
	_msg.text = "看准中奖线，按「停！」"


func _on_stopped(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var cost: int = _roll_cost()
	if _gold() < cost:
		_msg.text = "金币不足"
		return
	_set_gold_value(_gold() - cost)
	_roll_count += 1
	_current = entry.duplicate()
	var school: String = str(entry.get("school", ""))
	_msg.text = "抽到：%s（%s）%s — 点「装备」落位" % [
		str(entry.get("name", "?")), str(entry.get("quality", "common")),
		"（%s）" % school if school != "" else ""]
	_update_gold()


func _on_equip() -> void:
	if _current.is_empty() or _unit == null:
		_msg.text = "请先抽取防具"
		return
	var iid: String = str(_current.get("item_id", ""))
	var quality: String = str(_current.get("quality", "common"))
	if iid == "":
		return
	var result: Dictionary = BuildManager.apply_armor(_unit, iid, quality)
	match str(result.get("result", "")):
		"awaken", "merge", "plain":
			_msg.text = "已落位：%s" % str(_current.get("name", "?"))
			_current = {}
		"full":
			# 竞技场单单位机制槽少，满槽时覆盖最早的一个流派
			var mechs: Array = BuildManager.get_unit_mechanisms(_unit)
			if mechs.is_empty():
				_msg.text = "无法落位"
				return
			var skill_to_remove: String = str(mechs[0]["school"])
			BuildManager.overwrite_school(_unit, skill_to_remove, iid, quality)
			_msg.text = "已覆盖【%s】并落位：%s" % [skill_to_remove, str(_current.get("name", "?"))]
			_current = {}
		_:
			_msg.text = "无法落位"
	_update_gold()


func _on_upgrade() -> void:
	var cost: int = _upgrade_cost()
	if cost < 0:
		_msg.text = "品质已满"
		return
	if _gold() < cost:
		_msg.text = "金币不足，无法升级"
		return
	_set_gold_value(_gold() - cost)
	_quality_level += 1
	_machine.setup(BuildManager.get_armor_roll_pool(_quality_level, 8), "竞技场防具抽取")
	_msg.text = "品质提升至 Lv%d" % _quality_level
	_update_gold()


func _on_close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
