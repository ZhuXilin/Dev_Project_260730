class_name UnitDataManager
extends RefCounted

static var GROWTH_HP_PER_POINT : int = 1
static var _growth_loaded : bool = false

static func _ensure_growth_config():
	if _growth_loaded: return
	_growth_loaded = true
	GROWTH_HP_PER_POINT = int(GameConfigManager.get_value("progression_config.json", "growth_hp_per_point", 1))


static var _weapon_category_display: Dictionary = {
	"sword": "剑", "spear": "枪", "axe": "斧", "bow": "弓",
	"shield": "盾", "crossbow": "弩", "staff": "法杖",
	"spellbook": "魔法书", "dragonstone": "龙石"
}

static var _unit_display_name: Dictionary = {
	"swordsman": "剑士", "spearman": "枪兵", "axeman": "斧兵",
	"archer": "弓兵", "pegasus": "飞马", "mage": "法师",
	"cleric": "修女", "dragonborn": "龙人", "armored": "重甲兵"
}

static var _cn_to_en_unit: Dictionary = {
	"剑士": "swordsman", "枪兵": "spearman", "斧兵": "axeman",
	"弓兵": "archer", "飞马": "pegasus", "法师": "mage",
	"修女": "cleric", "龙人": "dragonborn", "重甲兵": "armored"
}

static var _unit_data_cache: Dictionary = {}
static var _data_loaded: bool = false


static func _load_unit_data():
	if _data_loaded: return
	_data_loaded = true
	var path = Config.PATHS.UNIT_DATA
	if not FileAccess.file_exists(path):
		push_error("单位数据 JSON 文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("JSON 解析失败")
		return
	_unit_data_cache = data


# ============================================================
#  ★ 让静态缓存失效，下次读取时重载
#  正确位置：这里（RefCounted class_name），不是 UnitManager.gd（Node autoload）
# ============================================================
static func reload_all() -> void:
	_data_loaded = false
	_unit_data_cache.clear()
	_load_unit_data()
	print("[UnitDataManager] 数据已重载，共 %d 个单位" % _unit_data_cache.size())
	# 联动刷新 TalentManager（如果它可用）
	if TalentManager:
		TalentManager.reload_all()


static func _normalize_unit_key(unit_name: String) -> String:
	return _cn_to_en_unit.get(unit_name, unit_name)


static func normalize_unit_key(unit_name: String) -> String:
	return _normalize_unit_key(unit_name)


static func get_unit_data(unit_name: String) -> Dictionary:
	_load_unit_data()
	var key = _normalize_unit_key(unit_name)
	return _unit_data_cache.get(key, {})


static func get_all_unit_data() -> Dictionary:
	_load_unit_data()
	return _unit_data_cache


static func get_sprite_frames_path(unit_name: String) -> String:
	return get_unit_data(unit_name).get("sprite_frames_path", "")


static func get_default_stats(unit_name: String) -> UnitData:
	var dict = get_unit_data(unit_name)
	var data = UnitData.new()
	data.max_hp = dict.get("max_hp", 20)
	data.hit_points = data.max_hp
	data.strength = dict.get("strength", 5)
	data.dexterity = dict.get("dexterity", 5)
	data.intelligence = dict.get("intelligence", 3)
	data.faith = dict.get("faith", 3)
	data.arcane = dict.get("arcane", 3)
	data.move_range = dict.get("move_range", 5)
	data.ignore_terrain_cost = dict.get("ignore_terrain_cost", false)
	return data


static func get_default_weapon_id(unit_name: String) -> String:
	return get_unit_data(unit_name).get("default_weapon", "")


static func get_sacrifice_buff(unit_name: String) -> Dictionary:
	return get_unit_data(unit_name).get("sacrifice_buff", {})


static func get_sacrifice_buff_display(unit_name: String) -> String:
	var buff : Dictionary = get_sacrifice_buff(unit_name)
	if buff.is_empty(): return ""
	return buff.get("display", "")


static func get_display_name(unit_name: String) -> String:
	var key = _normalize_unit_key(unit_name)
	var data = get_unit_data(key)
	if data.is_empty():
		return _unit_display_name.get(key, key)
	var display = data.get("display_name", "")
	if display == "":
		display = _unit_display_name.get(key, key)
	return display


# ============================================================
#  ★ 第六批：缺数据时也保持 name|faction|type 格式，避免 UI split 崩
# ============================================================
static func get_display_name_full(unit_name: String) -> String:
	var key = _normalize_unit_key(unit_name)
	var data = get_unit_data(key)
	if data.is_empty():
		# ★ 修复：原来返回裸 key，格式与其他分支不一致
		# 现在统一为 "display|faction|type" 格式
		var fallback_display : String = _unit_display_name.get(key, key)
		return "%s|无|%s" % [fallback_display, key]
	var display = data.get("display_name", "")
	if display == "":
		display = _unit_display_name.get(key, key)
	var faction = data.get("faction", "无")
	var type_name = _unit_display_name.get(key, key)
	return "%s|%s|%s" % [display, faction, type_name]


static func get_faction(unit_name: String) -> String:
	return get_unit_data(unit_name).get("faction", "")


static func get_description(unit_name: String) -> String:
	return get_unit_data(unit_name).get("description", "")


static func get_weapon_category_display(category: String) -> String:
	return _weapon_category_display.get(category, category)


static func get_all_unit_ids() -> Array:
	_load_unit_data()
	var ids : Array = []
	for key in _unit_data_cache.keys():
		ids.append(key)
	ids.sort()
	return ids


# ============================================================
#  创建单位
# ============================================================
static func create_unit_data(unit_name: String) -> UnitData:
	var key = _normalize_unit_key(unit_name)
	var dict = get_unit_data(key)
	var data = get_default_stats(key)
	data.unit_name = key
	data.display_name = dict.get("display_name", "")
	if data.display_name == "":
		data.display_name = _unit_display_name.get(key, key)
	data.faction = dict.get("faction", "")
	data.team_id = 0
	data.experience = 0
	data.level = 1

	data.tags.clear()
	var tags_raw : Variant = dict.get("tags", [])
	if tags_raw is Array:
		for t in tags_raw:
			if t is String:
				data.tags.append(t)

	data.core_trait = dict.get("core_trait", "")
	data.avatar = dict.get("avatar", "")

	var default_weapon = get_default_weapon_id(key)
	if default_weapon != "":
		var inst = ItemInstance.new()
		inst.item_id = default_weapon
		inst.count = 1
		if GameState.unit_growth.has(key):
			var lv : int = int(GameState.unit_growth[key].get("weapon_lv_" + default_weapon, 0))
			inst.upgrade_level = lv
		data.weapon_slot = inst

	data.talent_slots.clear()
	var default_talents = dict.get("default_talents", [])
	var talent_cap : int = int(dict.get("max_talent_slots", 1))
	for talent_id in default_talents:
		if data.talent_slots.size() >= talent_cap:
			break
		var talent_inst = TalentInstance.new()
		talent_inst.talent_id = talent_id
		talent_inst.current_stack = 0
		talent_inst.is_active = true
		var tdata = TalentManager.get_talent_data(talent_id)
		if tdata and tdata.is_active_skill:
			talent_inst.is_ready = true
			talent_inst.cooldown_remaining = 0
		else:
			talent_inst.is_ready = false
		data.talent_slots.append(talent_inst)
	while data.talent_slots.size() < talent_cap:
		data.talent_slots.append(null)

	data.armor_slots = [null, null]
	data.max_armor_slots = 2
	data.max_talent_slots = talent_cap

	_apply_attr_points_to_unit(key, data)
	_apply_attr_cap_bonus(key, data)
	return data


# ============================================================
#  单位属性上限
# ============================================================
static func get_attr_cap_levels(unit_type: String) -> Array:
	var key : String = normalize_unit_key(unit_type)
	var dict : Dictionary = get_unit_data(key)
	var levels : Variant = dict.get("attr_cap_levels", [])
	if levels is Array:
		return (levels as Array).duplicate(true)
	return []


static func has_attr_cap_levels(unit_type: String) -> bool:
	return not get_attr_cap_levels(unit_type).is_empty()


static func get_attr_cap_total_bonus(unit_type: String, cur_lv: int) -> Dictionary:
	var levels : Array = get_attr_cap_levels(unit_type)
	var total : Dictionary = {}
	for i in range(cur_lv):
		var lv_dict : Dictionary = {}
		
		if i < levels.size():
			lv_dict = levels[i]
		elif not levels.is_empty():
			# ★ 核心修改：如果超出了 JSON 配置的最大等级，以最后一级为基准，属性按倍数膨胀
			# 比如 JSON 有 3 级，第 4 级倍率 1.5，第 5 级倍率 2.0
			var base_dict : Dictionary = levels.back()
			var mult : float = 1.0 + (i - levels.size() + 1) * 0.5 
			for k in base_dict:
				lv_dict[k] = int(base_dict[k] * mult)
		
		for k in lv_dict:
			total[k] = total.get(k, 0) + int(lv_dict[k])
	return total


static func _apply_attr_cap_bonus(unit_key: String, data: UnitData) -> void:
	var cur_lv : int = int(GameState.unit_attr_cap.get(unit_key, 0))
	if cur_lv <= 0: return
	var total : Dictionary = get_attr_cap_total_bonus(unit_key, cur_lv)
	if total.is_empty(): return
	for k in total:
		_apply_one_attr(data, k, int(total[k]))
	print("[属性上限] %s 已应用 Lv%d 加成：%s" % [unit_key, cur_lv, total])


static func _apply_attr_points_to_unit(unit_key: String, data: UnitData):
	var points_dict : Dictionary = GameState.unit_attr_points.get(unit_key, {})
	if points_dict.is_empty():
		return
	for attr_key in points_dict:
		var pts : int = int(points_dict[attr_key])
		if pts <= 0: continue
		_apply_one_attr(data, attr_key, pts)
	print("[加点] %s 已应用：%s" % [unit_key, points_dict])


static func _apply_one_attr(data: UnitData, attr_key: String, amount: int):
	match attr_key:
		"vitality":
			data.max_hp += amount
			data.hit_points += amount
		"strength":     data.strength += amount
		"dexterity":    data.dexterity += amount
		"intelligence": data.intelligence += amount
		"faith":        data.faith += amount
		"arcane":       data.arcane += amount
		"move_range":   data.move_range += amount


# ============================================================
#  辅助
# ============================================================
static func get_total_attr_points(unit_key: String) -> int:
	var total : int = 0
	var d : Dictionary = GameState.unit_attr_points.get(unit_key, {})
	for k in d:
		total += int(d[k])
	return total


static func get_attr_points_for(unit_key: String, attr_key: String) -> int:
	var d : Dictionary = GameState.unit_attr_points.get(unit_key, {})
	return int(d.get(attr_key, 0))


static func get_attr_cap(unit_key: String) -> int:
	const LEVELS : Array[int] = [0, 2, 5, 8, 12, 16, 20, 25]
	var lv : int = int(GameState.unit_attr_cap.get(unit_key, 0))
	return LEVELS[clampi(lv, 0, LEVELS.size() - 1)]


static func get_display_name_from_unit(unit: Unit) -> String:
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	var faction = unit.unit_stats.faction if unit.unit_stats.faction != "" else "无"
	return "%s|%s|%s" % [display_name, faction, unit.unit_stats.unit_name]


static func get_unit_type_display_name(unit_name: String) -> String:
	var key = _normalize_unit_key(unit_name)
	return _unit_display_name.get(key, key)


static func apply_growth(stats: UnitData, unit_type: String) -> void:
	if GameState.unit_growth.is_empty(): return
	if not GameState.unit_growth.has(unit_type): return
	var g = GameState.unit_growth[unit_type]
	stats.max_hp += int(g.get("vitality", 0)) * GROWTH_HP_PER_POINT
	stats.strength += int(g.get("strength", 0))
	stats.dexterity += int(g.get("dexterity", 0))
	stats.intelligence += int(g.get("intelligence", 0))
	stats.faith += int(g.get("faith", 0))
	stats.arcane += int(g.get("arcane", 0))


# ============================================================
#  ★ 新增：统一的单位贴图（SpriteFrames）和 UI 图标管理
# ============================================================
static var _sprite_frames_cache : Dictionary = {}
static var _idle_texture_cache : Dictionary = {}

# 获取统一的 SpriteFrames（带缓存，供战斗使用）
static func get_sprite_frames(unit_name: String) -> SpriteFrames:
	var key := normalize_unit_key(unit_name)
	if _sprite_frames_cache.has(key):
		return _sprite_frames_cache[key]
		
	var path = get_sprite_frames_path(key)
	if path != "" and ResourceLoader.exists(path):
		var sf = load(path) as SpriteFrames
		if sf:
			_sprite_frames_cache[key] = sf
			return sf
	return null

# 获取 idle 第一帧作为静态图标（带缓存）
static func get_idle_texture(unit_name: String) -> Texture2D:
	var key := normalize_unit_key(unit_name)
	if _idle_texture_cache.has(key):
		return _idle_texture_cache[key]
		
	var sf = get_sprite_frames(key)
	if sf and sf.has_animation("idle") and sf.get_frame_count("idle") > 0:
		var tex = sf.get_frame_texture("idle", 0)
		_idle_texture_cache[key] = tex
		return tex
	return null


static func create_idle_texture_rect(unit_name: String, icon_size: Vector2 = Vector2(32, 32), override_path: String = "") -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = icon_size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sf: SpriteFrames = null
	# ★ 修复：优先读取转职后的覆盖贴图
	if override_path != "" and ResourceLoader.exists(override_path):
		sf = load(override_path) as SpriteFrames
	else:
		sf = get_sprite_frames(unit_name)
		
	if sf and sf.has_animation("idle") and sf.get_frame_count("idle") > 0:
		rect.texture = sf.get_frame_texture("idle", 0)
		
		var timer := Timer.new()
		timer.wait_time = 0.25
		timer.autostart = true
		rect.add_child(timer)
		
		var frame_count := sf.get_frame_count("idle")
		var idx := {"value": 0}
		timer.timeout.connect(func():
			if not is_instance_valid(rect): return
			idx["value"] = (idx["value"] + 1) % frame_count
			var t = sf.get_frame_texture("idle", idx["value"])
			if t: rect.texture = t
		)
	else:
		rect.visible = false
		
	return rect
