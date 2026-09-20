class_name EquipmentConfigDetail
extends RefCounted

const Style = preload("res://function/script/EquipmentConfig/EquipmentConfigStyle.gd")

const DETAIL_LABEL_PATH = "VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/DetailLabel"

var panel = null


func _init(p):
	panel = p


# ============================================================
#  详情区显示 / 清除
# ============================================================
func show_in_zone(text: String):
	if not is_instance_valid(panel):
		return
	var detail_label : Label = panel.get_node_or_null(DETAIL_LABEL_PATH)
	if detail_label:
		detail_label.text = text


func clear_zone():
	if not is_instance_valid(panel):
		return
	var detail_label : Label = panel.get_node_or_null(DETAIL_LABEL_PATH)
	if detail_label:
		detail_label.text = "选中物品详情"


# ============================================================
#  物品详情
# ============================================================
func show_item(item_id: String):
	var relic_data : Dictionary = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		show_relic(relic_data)
		return
	var data : ItemData = ItemManager.get_item_data(item_id)
	if not data:
		return
	var lines : Array = []
	lines.append(data.name)
	if data.quality and data.quality != "":
		lines.append("品质: " + Style.get_quality_display_name(data.quality))
	if data.description and data.description != "":
		lines.append(data.description)
	if data.type == "weapon":
		lines.append("基础攻击: " + str(data.base_attack))
		lines.append("射程: " + str(data.min_attack_range) + "~" + str(data.attack_range))
		if data.modifier and not data.modifier.is_empty():
			var mod_str : String = ""
			for key in data.modifier:
				var v : Variant = data.modifier[key]
				mod_str += Style.get_attr_display_name(key) + "+" + str(v) + " "
			lines.append("补正: " + mod_str.strip_edges())
	elif data.type == "armor":
		if data.defense > 0:
			lines.append("防御: +" + str(data.defense))
		if data.slot_count > 0:
			lines.append("占用格数: " + str(data.slot_count))
		if data.modifier and not data.modifier.is_empty():
			var mod_str : String = ""
			for key in data.modifier:
				var v : Variant = data.modifier[key]
				mod_str += Style.get_attr_display_name(key) + "+" + str(v) + " "
			lines.append("属性加成: " + mod_str.strip_edges())
	if data.price > 0:
		lines.append("价格: " + str(data.price) + "G")
	show_in_zone("\n".join(lines))


func hide_item():
	clear_zone()


# ============================================================
#  遗物详情
# ============================================================
func show_relic(data: Dictionary):
	var lines : Array = []
	lines.append(data.get("name", "未知遗物"))
	lines.append(data.get("description", ""))
	show_in_zone("\n".join(lines))


# ============================================================
#  特技详情
# ============================================================
func show_talent(data: TalentData):
	var lines : Array = []
	lines.append(data.display_name)
	lines.append(data.description)
	lines.append("稀有度: " + data.rarity)
	lines.append("流派: " + data.school)
	lines.append("积累: " + str(data.accumulation_threshold) + "回合")
	var compatible_units : Array = data.compatible_units if data.compatible_units != null else []
	if not compatible_units.is_empty():
		var unit_names : Array = []
		for unit_key in compatible_units:
			var display : String = UnitDataManager.get_unit_type_display_name(unit_key)
			if display != "":
				unit_names.append(display)
		lines.append("可装备: " + "/".join(unit_names))
	else:
		lines.append("可装备: 全部")
	show_in_zone("\n".join(lines))


# ============================================================
#  悬停回调
# ============================================================
func on_button_hover_entered(item_id: String):
	show_item(item_id)


func on_button_hover_exited():
	clear_zone()


func on_talent_hover_entered(talent_id: String):
	var data : TalentData = TalentManager.get_talent_data(talent_id)
	if data:
		show_talent(data)


func on_talent_hover_exited():
	clear_zone()


func on_relic_hover_entered(relic_id: String):
	var data : Dictionary = RelicManager.get_relic_data(relic_id)
	if not data.is_empty():
		show_relic(data)


func on_relic_hover_exited():
	clear_zone()


func on_refine_hover_entered(refine_id: String):
	var recipe : Dictionary = RefineManager.get_recipe(refine_id)
	if recipe.is_empty():
		return
	var lines : Array = []
	lines.append(recipe.get("name", refine_id))
	lines.append(recipe.get("description", ""))
	show_in_zone("\n".join(lines))


func on_refine_hover_exited():
	clear_zone()
