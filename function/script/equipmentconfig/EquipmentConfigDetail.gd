class_name EquipmentConfigDetail
extends RefCounted

const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")

const DETAIL_LABEL_PATH = "VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/DetailLabel"
const DETAIL_ZONE_PATH = "VBoxContainer/MainHBox/LeftInfoColumn/DetailZone"

var panel = null

# ★ 碎片化叙事：记录当前 hover 的内容，切换模式后能重新渲染
var _hover_ref : Dictionary = {}   # {"kind": "item"/"relic"/"talent"/"aura", "id": "..."}

func _init(p):
	panel = p


func has_hover() -> bool:
	return not _hover_ref.is_empty()


func get_hover_ref() -> Dictionary:
	return _hover_ref.duplicate()


# function/script/equipmentconfig/EquipmentConfigDetail.gd

# --- 替换 refresh() 方法 ---
func refresh():
	if _hover_ref.is_empty():
		clear_zone()
		return
	var kind : String = _hover_ref.get("kind", "")
	var id : String = _hover_ref.get("id", "")
	match kind:
		"item":   show_item(id)
		"relic":  on_relic_hover_entered(id)
		"talent": on_talent_hover_entered(id)
		"aura":   show_aura(id)
		"unit":   
			var u_data = _hover_ref.get("unit_data", null)
			if u_data: show_unit(u_data)
		_: clear_zone()

# --- 新增 show_unit() 方法（放到 show_aura 后面即可） ---
func show_unit(unit : UnitData):
	_hover_ref = {"kind": "unit", "unit_data": unit}

	# ★ 叙事模式
	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("units", unit.unit_name)
		if flavor == "":
			flavor = "（暂无叙事）"
		show_in_zone(flavor)
		return

	# ---- 玩法模式（把原本在 EquipmentConfig 里的拼装逻辑搬过来）----
	var display : String = unit.display_name if unit.display_name != "" else unit.unit_name
	var type_name : String = UnitDataManager.get_unit_type_display_name(unit.unit_name)

	var lines : Array = []
	lines.append("%s（%s）" % [display, type_name])
	if unit.is_dead:
		lines.append("【已冻结】可通过圣坛或复活圣油解冻")
	lines.append("")

	lines.append("HP: %d / %d" % [unit.hit_points, unit.max_hp])
	lines.append("力量: %d    灵巧: %d" % [unit.strength, unit.dexterity])
	lines.append("智力: %d    信仰: %d" % [unit.intelligence, unit.faith])
	lines.append("感应: %d    移动力: %d" % [unit.arcane, unit.move_range])

	lines.append("")
	if unit.weapon_slot:
		var wdata : ItemData = ItemManager.get_item_data(unit.weapon_slot.item_id)
		if wdata:
			var lv_txt : String = ""
			if unit.weapon_slot.upgrade_level > 0:
				lv_txt = "+%d" % unit.weapon_slot.upgrade_level
			lines.append("武器: %s%s" % [wdata.name, lv_txt])
			if wdata.type == "weapon":
				lines.append("  攻击 %d  射程 %d~%d" % [
					wdata.base_attack, wdata.min_attack_range, wdata.attack_range])
	else:
		lines.append("武器: 无")

	var armor_names : Array = []
	for s in unit.armor_slots:
		if s:
			var adata : ItemData = ItemManager.get_item_data(s.item_id)
			if adata:
				armor_names.append(adata.name)
	if armor_names.size() > 0:
		lines.append("防具: " + ", ".join(armor_names))
	else:
		lines.append("防具: 无")

	var talent_names : Array = []
	for t in unit.talent_slots:
		if t and t.is_active:
			var tdata : TalentData = TalentManager.get_talent_data(t.talent_id)
			if tdata:
				talent_names.append(tdata.display_name)
	if talent_names.size() > 0:
		lines.append("特技: " + ", ".join(talent_names))

	if unit.advanced_talent_id != "":
		var adv_data : TalentData = TalentManager.get_talent_data(unit.advanced_talent_id)
		if adv_data:
			var lv : int = TalentManager.get_talent_level(unit.unit_name, unit.advanced_talent_id)
			if TalentManager.is_talent_max_level(unit.unit_name, unit.advanced_talent_id):
				lines.append("职业: %s Lv%d MAX" % [adv_data.display_name, lv])
			else:
				var cur_exp : int = TalentManager.get_talent_exp_in_level(unit.unit_name, unit.advanced_talent_id)
				var need_exp : int = TalentManager.get_level_required_exp(unit.unit_name, unit.advanced_talent_id)
				lines.append("职业: %s Lv%d %d/%d" % [adv_data.display_name, lv, cur_exp, need_exp])

	show_in_zone("\n".join(lines))


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
	_hover_ref.clear()


# ============================================================
#  物品
# ============================================================
func show_item(item_id: String, affixes: Array = []):
	_hover_ref = {"kind": "item", "id": item_id}

	var relic_data : Dictionary = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		show_relic(relic_data, item_id)
		_hover_ref = {"kind": "relic", "id": item_id}
		return

	if FlavorManager.is_narrative_mode():
		var data : ItemData = ItemManager.get_item_data(item_id)
		if not data:
			show_in_zone("（未知物品）")
			return
		var flavor : String = FlavorManager.get_flavor("items", item_id)
		if flavor == "":
			flavor = "（暂无叙事）"
		show_in_zone(flavor)
		return

	# ---- 玩法模式（原逻辑）----
	var data2 : ItemData = ItemManager.get_item_data(item_id)
	if not data2:
		return
	var lines : Array = []
	lines.append(data2.name)
	if data2.quality and data2.quality != "":
		lines.append("品质: " + Style.get_quality_display_name(data2.quality))
	if data2.description and data2.description != "":
		lines.append(data2.description)
	if data2.tags and not data2.tags.is_empty():
		lines.append("标签: " + "/".join(data2.tags))

	if data2.type == "weapon":
		lines.append("基础攻击: " + str(data2.base_attack))
		lines.append("射程: " + str(data2.min_attack_range) + "~" + str(data2.attack_range))
		if data2.modifier and not data2.modifier.is_empty():
			var mod_str : String = ""
			for key in data2.modifier:
				var v : Variant = data2.modifier[key]
				mod_str += Style.get_attr_display_name(key) + "+" + str(v) + " "
			lines.append("补正: " + mod_str.strip_edges())
	elif data2.type == "armor":
		if data2.defense > 0:
			lines.append("防御: +" + str(data2.defense))
		if data2.slot_count > 0:
			lines.append("占用格数: " + str(data2.slot_count))
		if data2.modifier and not data2.modifier.is_empty():
			var mod_str2 : String = ""
			for key in data2.modifier:
				var v2 : Variant = data2.modifier[key]
				mod_str2 += Style.get_attr_display_name(key) + "+" + str(v2) + " "
			lines.append("属性加成: " + mod_str2.strip_edges())

	if data2.price > 0:
		lines.append("价格: " + str(data2.price) + "G")

	if not affixes.is_empty():
		lines.append("--- 词条 ---")
		for a in affixes:
			var aid : String = a.get("id", "")
			var val : int = int(a.get("value", 0))
			lines.append("· " + AffixManager.format_description(aid, val))

	var set_line : String = _build_set_hint(data2)
	if set_line != "":
		lines.append(set_line)

	show_in_zone("\n".join(lines))


func _category_key_for_item(data : ItemData) -> String:
	if data.type == "weapon":
		return "weapons"
	elif data.type == "armor":
		return "armors"
	return "items"


func hide_item():
	clear_zone()


func _build_set_hint(data : ItemData) -> String:
	if data.tags.is_empty():
		return ""
	var parts : Array = []
	for tag in data.tags:
		var b : Dictionary = SetBonusManager.get_bonus(tag)
		if b.is_empty():
			continue
		parts.append("【%s】%s" % [tag, b.get("description", "")])
	if parts.is_empty():
		return ""
	return "--- 套装（3件）---\n" + "\n".join(parts)


# ============================================================
#  遗物
# ============================================================
func show_relic(data: Dictionary, item_id: String = ""):
	_hover_ref = {"kind": "relic", "id": item_id}

	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("relics", item_id)
		if flavor == "":
			flavor = "（暂无叙事）"
		if GameState.is_relic_refined(item_id):
			flavor = "★ 已精炼\n\n" + flavor
		show_in_zone(flavor)
		return

	var lines : Array = []
	var name_text : String = data.get("name", "未知遗物")
	if item_id != "" and GameState.is_relic_refined(item_id):
		name_text = "★ " + name_text
	lines.append(name_text)
	lines.append(data.get("description", ""))
	if item_id != "" and GameState.is_relic_refined(item_id):
		lines.append("（已精炼）")
	show_in_zone("\n".join(lines))


# ============================================================
#  特技
# ============================================================
func show_talent(data: TalentData):
	_hover_ref = {"kind": "talent", "id": data.id}

	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("talents", data.id)
		if flavor == "":
			flavor = "（暂无叙事）"
		show_in_zone(flavor)
		return

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
#  光环（EquipmentConfig 里调用）
# ============================================================
func show_aura(aura_id: String):
	_hover_ref = {"kind": "aura", "id": aura_id}

	var ad : Dictionary = AuraManager.get_aura(aura_id)
	if ad.is_empty():
		show_in_zone("（未知光环）")
		return

	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("auras", aura_id)
		if flavor == "":
			flavor = "（暂无叙事）"
		show_in_zone(flavor)
		return

	var lines : Array = []
	lines.append("【%s】%s" % [ad.get("tag", ""), ad.get("name", aura_id)])
	lines.append(ad.get("description", ""))
	lines.append("研究时长: %d 天" % int(ad.get("research_time", 2)))
	lines.append("购买价: %d◆" % int(ad.get("buy_cost", 6)))
	show_in_zone("\n".join(lines))


# ============================================================
#  鼠标事件
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
		show_relic(data, relic_id)


func on_relic_hover_exited():
	clear_zone()
