extends CanvasLayer

signal closed

enum Tab { CRAFT, UPGRADE }
var current_tab : Tab = Tab.CRAFT

const FORGE_UPGRADE_MAX : int = 3
const FORGE_UPGRADE_BONUS : int = 1
const FORGE_UPGRADE_COST_BASE : int = 100

@onready var gold_label : Label = $Panel/VBoxContainer/TopBar/GoldLabel
@onready var craft_tab_btn : Button = $Panel/VBoxContainer/TabBar/CraftTabBtn
@onready var upgrade_tab_btn : Button = $Panel/VBoxContainer/TabBar/UpgradeTabBtn
@onready var content_container : VBoxContainer = $Panel/VBoxContainer/ContentScroll/ContentContainer

func _ready():
	_refresh_gold()
	_switch_tab(Tab.CRAFT)


# ============================================================
#  信号回调（由 .tscn 连线）
# ============================================================
func _on_craft_tab_pressed():
	_switch_tab(Tab.CRAFT)

func _on_upgrade_tab_pressed():
	_switch_tab(Tab.UPGRADE)

func _on_close_pressed():
	closed.emit()
	queue_free()


# ============================================================
#  Tab 切换
# ============================================================
func _switch_tab(tab: Tab):
	current_tab = tab
	_update_tab_style()
	_clear_content()
	match tab:
		Tab.CRAFT:
			_build_craft_tab()
		Tab.UPGRADE:
			_build_upgrade_tab()


func _update_tab_style():
	craft_tab_btn.modulate = Color.WHITE if current_tab == Tab.CRAFT else Color(0.5, 0.5, 0.5)
	upgrade_tab_btn.modulate = Color.WHITE if current_tab == Tab.UPGRADE else Color(0.5, 0.5, 0.5)


func _clear_content():
	for child in content_container.get_children():
		content_container.remove_child(child)
		child.queue_free()


func _refresh_gold():
	gold_label.text = "金币: " + str(EconomyManager.get_temp_gold())


# ============================================================
#  Tab 1：防具合成
# ============================================================
func _build_craft_tab():
	var unlocked = GameState.unlocked_recipes   # ← 已存在
	if unlocked.is_empty():
		content_container.add_child(_make_hint("暂无已解锁配方\n（前往铁砧酒馆解锁）"))
		return
	for recipe_id in unlocked:
		var data = ItemManager.get_item_data(recipe_id)
		if data:
			content_container.add_child(_build_craft_row(data))

func _build_craft_row(data: ItemData) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label = Label.new()
	name_label.text = data.name
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var cost_label = Label.new()
	cost_label.text = str(data.craft_cost) + "G"
	cost_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	row.add_child(cost_label)

	var craft_btn = Button.new()
	craft_btn.text = "合成"
	craft_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	craft_btn.pressed.connect(_on_craft_pressed.bind(data.id))
	row.add_child(craft_btn)

	return row


func _on_craft_pressed(item_id: String):
	var data = ItemManager.get_item_data(item_id)
	if not data:
		return
	if EconomyManager.get_temp_gold() < data.craft_cost:
		_show_message("金币不足")
		return
	EconomyManager.subtract_temp_gold(data.craft_cost)
	Globals.unlock_item(item_id)
	_refresh_gold()
	_show_message("合成成功：" + data.name)


# ============================================================
#  Tab 2：武器升级
# ============================================================
func _build_upgrade_tab():
	var party = GameState.get_party_units()
	if party.is_empty():
		content_container.add_child(_make_hint("队伍为空"))
		return
	for unit_data in party:
		content_container.add_child(_build_unit_upgrade_row(unit_data))


func _build_unit_upgrade_row(unit_data: UnitData) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var name_label = Label.new()
	var display = unit_data.display_name if unit_data.display_name != "" else unit_data.unit_name
	name_label.text = display
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	box.add_child(name_label)

	if not unit_data.weapon_slot:
		box.add_child(_make_hint("  无武器"))
		return box

	var weapon_data = ItemManager.get_item_data(unit_data.weapon_slot.item_id)
	if not weapon_data:
		return box

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var wname = Label.new()
	wname.text = "  " + weapon_data.name
	wname.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	wname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wname)

	var level = 0   # TODO: 从 weapon_slot 读升级等级
	var level_label = Label.new()
	level_label.text = "+%d / +%d" % [level, FORGE_UPGRADE_MAX]
	level_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	row.add_child(level_label)

	var cost = FORGE_UPGRADE_COST_BASE * (level + 1)
	var upgrade_btn = Button.new()
	upgrade_btn.text = "升级 (%dG)" % cost
	upgrade_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	upgrade_btn.disabled = (level >= FORGE_UPGRADE_MAX)
	upgrade_btn.pressed.connect(_on_upgrade_pressed.bind(unit_data))
	row.add_child(upgrade_btn)

	box.add_child(row)
	return box


func _on_upgrade_pressed(_unit_data: UnitData):
	# TODO: 步骤 3 实现
	_show_message("武器升级功能开发中")


# ============================================================
#  辅助
# ============================================================
func _make_hint(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(0.6, 0.6, 0.6)
	return label


func _show_message(msg: String):
	var label = Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_container.add_child(label)
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(label):
		label.queue_free()
