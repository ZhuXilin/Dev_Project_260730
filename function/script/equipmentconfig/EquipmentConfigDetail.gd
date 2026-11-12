class_name EquipmentConfigDetail
extends RefCounted

const Style = preload("res://function/script/equipmentconfig/EquipmentConfigStyle.gd")

var panel = null
var _info_ui : Control = null
var _hover_ref : Dictionary = {}   # {"kind": "item/relic/talent/aura/unit", "id": "..."}

func _init(p):
	panel = p
	_info_ui = panel.get_node_or_null("VBoxContainer/MainHBox/LeftInfoColumn/DetailZone/ItemInfoPanel")

func has_hover() -> bool:
	return not _hover_ref.is_empty()

func get_hover_ref() -> Dictionary:
	return _hover_ref.duplicate()

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

func clear_zone():
	_hover_ref.clear()
	if _info_ui and _info_ui.has_method("clear_info"):
		_info_ui.clear_info()


func show_unit(unit : UnitData):
	_hover_ref = {"kind": "unit", "unit_data": unit}
	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("units", unit.unit_name)
		if flavor == "": flavor = "（暂无叙事）"
		_show_raw("", "", "", flavor, "")
		return

	var display : String = unit.display_name if unit.display_name != "" else unit.unit_name
	var type_name : String = UnitDataManager.get_unit_type_display_name(unit.unit_name)
	
	if unit.advanced_class != "":
		type_name = AdvancedClassManager.get_display_name(unit.advanced_class)

	var desc = ""
	if unit.is_dead: desc += "【已冻结】可通过英灵殿或复活圣油解冻\n"
	
	# 获取 1 级基础数据用于对比
	var base_dict = UnitDataManager.get_unit_data(unit.unit_name)
	var base_hp = int(base_dict.get("max_hp", 0))
	var base_str = int(base_dict.get("strength", 0))
	var base_dex = int(base_dict.get("dexterity", 0))
	var base_int = int(base_dict.get("intelligence", 0))
	var base_fai = int(base_dict.get("faith", 0))
	var base_mov = int(base_dict.get("move_range", 0))

	var stats : Array = []
	
	var fmt_attr = func(base_v, cur_v):
		var diff = cur_v - base_v
		if diff > 0:
			return "%d(+%d)" % [cur_v, diff]
		return str(cur_v)

	# 精简字段名，压缩宽度
	stats.append("HP: %s" % fmt_attr.call(base_hp, unit.max_hp))
	stats.append("力:%s  灵:%s" % [
		fmt_attr.call(base_str, unit.strength), 
		fmt_attr.call(base_dex, unit.dexterity)
	])
	stats.append("智:%s  信:%s" % [
		fmt_attr.call(base_int, unit.intelligence), 
		fmt_attr.call(base_fai, unit.faith)
	])
	stats.append("移动: %s" % fmt_attr.call(base_mov, unit.move_range))

	if unit.weapon_name != "":
		stats.append("武器: %s" % unit.weapon_name)

	_show_raw(display, type_name, desc, "", "\n".join(stats))


# ============================================================
#  show_item（v5.0 扩展：连通组信息）
# ============================================================
func show_item(item_id: String, affixes: Array = [], link_group_size: int = 0, link_unit_count: int = 0):
	_hover_ref = {"kind": "item", "id": item_id}

	var relic_data : Dictionary = RelicManager.get_relic_data(item_id)
	if not relic_data.is_empty():
		show_relic(relic_data, item_id)
		_hover_ref = {"kind": "relic", "id": item_id}
		return

	var data : ItemData = ItemManager.get_item_data(item_id)
	if not data:
		clear_zone()
		return

	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("items", item_id)
		if flavor == "": flavor = "（暂无叙事）"
		_show_raw(data.name, "", "", flavor, "", data.icon)
		return

	var type_str = ""
	if data.quality: type_str += Style.get_quality_display_name(data.quality) + " "
	if data.tags: type_str += "[" + "/".join(data.tags) + "]"

	var desc = data.description if data.description else ""
	
	var stats_arr : Array = []
	if data.type == "weapon":
		stats_arr.append("攻击: %d" % data.base_attack)
		stats_arr.append("射程: %d~%d" % [data.min_attack_range, data.attack_range])
		if data.modifier and not data.modifier.is_empty():
			var mods = []
			for k in data.modifier: mods.append(Style.get_attr_display_name(k) + "+" + str(data.modifier[k]))
			stats_arr.append("补正: " + " ".join(mods))
	elif data.type == "armor":
		if data.defense > 0: stats_arr.append("防御: +%d" % data.defense)
		if data.modifier and not data.modifier.is_empty():
			var mods = []
			for k in data.modifier: mods.append(Style.get_attr_display_name(k) + "+" + str(data.modifier[k]))
			stats_arr.append("属性: " + " ".join(mods))

		# ★ v5.0：连通组反馈
		if link_group_size >= 2:
			stats_arr.append("★ 当前已链接：%d 件防具（跨 %d 个单位）" % [link_group_size, link_unit_count])
		elif data.enable_direction:
			stats_arr.append("· 未形成连通组（相邻槽位方向不对接）")
	
	if not affixes.is_empty():
		stats_arr.append("--- 词条 ---")
		for a in affixes:
			stats_arr.append("· " + AffixManager.format_description(a.get("id", ""), int(a.get("value", 0))))

	var set_hint : String = _build_set_hint(data)
	if set_hint != "": stats_arr.append(set_hint)

	_show_raw(data.name, type_str, desc, "", "\n".join(stats_arr), data.icon, UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE))


# ============================================================
#  v5.0 新增：带连通组信息的防具 hover 入口
# ============================================================
func on_button_hover_entered_with_link(item_id: String, group_size: int, unit_count: int):
	show_item(item_id, [], group_size, unit_count)


func show_relic(data: Dictionary, item_id: String = ""):
	_hover_ref = {"kind": "relic", "id": item_id}

	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("relics", item_id)
		if flavor == "": flavor = "（暂无叙事）"
		if GameState.is_relic_refined(item_id): flavor = "★ 已精炼\n\n" + flavor
		_show_raw(data.get("name", ""), "", "", flavor, "")
		return

	var name_text : String = data.get("name", "未知遗物")
	if item_id != "" and GameState.is_relic_refined(item_id): name_text = "★ " + name_text
	var desc = data.get("description", "")
	if item_id != "" and GameState.is_relic_refined(item_id): desc += "\n（已精炼）"
	
	var icon : Texture2D = null
	var icon_data = data.get("icon", null)
	if icon_data is Texture2D:
		icon = icon_data
	elif icon_data is String and icon_data != "":
		icon = IconManager.get_icon_or_null(icon_data)
	
	_show_raw(name_text, "遗物", desc, "", "", icon, Color(1.0, 0.85, 0.3))

func show_talent(data: TalentData):
	_hover_ref = {"kind": "talent", "id": data.id}

	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("talents", data.id)
		if flavor == "": flavor = "（暂无叙事）"
		_show_raw(data.display_name, "", "", flavor, "")
		return

	var type_str = "稀有度: " + data.rarity + " | 流派: " + data.school
	var stats = "积累: %d回合" % data.accumulation_threshold
	if data.is_active_skill: stats = "主动技能 | 冷却: %d" % data.skill_cooldown
	
	var compatible_units : Array = data.compatible_units if data.compatible_units != null else []
	if not compatible_units.is_empty():
		var unit_names : Array = []
		for unit_key in compatible_units: unit_names.append(UnitDataManager.get_unit_type_display_name(unit_key))
		stats += "\n可装备: " + "/".join(unit_names)
	else:
		stats += "\n可装备: 全部"

	var icon : Texture2D = TalentManager.get_talent_icon(data.id)

	_show_raw(data.display_name, type_str, data.description, "", stats, icon, Style.get_rarity_color(data.rarity))

func show_aura(aura_id: String):
	_hover_ref = {"kind": "aura", "id": aura_id}

	var ad : Dictionary = AuraManager.get_aura(aura_id)
	if ad.is_empty():
		clear_zone()
		return

	if FlavorManager.is_narrative_mode():
		var flavor : String = FlavorManager.get_flavor("auras", aura_id)
		if flavor == "": flavor = "（暂无叙事）"
		_show_raw(ad.get("name", aura_id), "", "", flavor, "")
		return

	var type_str = "光环 [" + str(ad.get("tag", "")) + "]"
	var stats = "研究时长: %d 天\n购买价: %d 魂火" % [int(ad.get("research_time", 2)), int(ad.get("buy_cost", 6))]
	
	_show_raw(ad.get("name", aura_id), type_str, ad.get("description", ""), "", stats, null, Color(0.7, 0.9, 1.0))

func _show_raw(name: String, type_str: String, desc: String, flavor: String, stats: String, icon: Texture2D = null, name_color: Color = Color.WHITE):
	if not _info_ui: return
	
	var final_desc = flavor if flavor != "" else desc
	_info_ui.show_info({
		"name": name,
		"name_color": name_color,
		"type_str": type_str,
		"desc": final_desc,
		"stats": stats,
		"icon": icon
	})

func _build_set_hint(data : ItemData) -> String:
	if data.tags.is_empty(): return ""
	var parts : Array = []
	for tag in data.tags:
		var b : Dictionary = SetBonusManager.get_bonus(tag)
		if not b.is_empty(): parts.append("【%s】%s" % [tag, b.get("description", "")])
	if parts.is_empty(): return ""
	return "--- 套装（3件）---\n" + "\n".join(parts)

func show_in_zone(text: String):
	if _info_ui: _info_ui.show_info({"name": "", "desc": text})

func on_button_hover_entered(item_id: String): show_item(item_id)
func on_button_hover_exited(): clear_zone()
func on_talent_hover_entered(talent_id: String):
	var data = TalentManager.get_talent_data(talent_id)
	if data: show_talent(data)
func on_talent_hover_exited(): clear_zone()
func on_relic_hover_entered(relic_id: String):
	var data = RelicManager.get_relic_data(relic_id)
	if not data.is_empty(): show_relic(data, relic_id)
func on_relic_hover_exited(): clear_zone()
