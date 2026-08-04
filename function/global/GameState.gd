extends Node

# 队伍数据
var party: Array[UnitData] = []
var max_party_size: int = 3
var main_unit_name: String = ""          # 记录主单位名称
var main_unit_index: int = 0

# 地图进度
var current_day: int = 1
var current_map_index: int = 0
var visited_nodes: Dictionary = {}       # 地图节点访问记录（可由 MapScene 迁移到此处）
var is_map_mode: bool = false
var cached_map_level_data: MapLevelData = null
var cached_day: int = -1
var last_selected_node_type: int = -1
var current_map_data: MapData = null
var should_advance_day: bool = false

# 初始化队伍
func initialize_party(selected_units: Array[String], main_index: int):
	party.clear()
	for unit_name in selected_units:
		var data = UnitData.new()
		var stats = UnitDataManager.get_default_stats(unit_name)
		data.unit_name = unit_name
		data.team_id = 0
		data.max_hp = stats.max_hp
		data.hit_points = stats.max_hp
		data.defense = stats.defense
		data.magic_defense = stats.magic_defense
		data.skill = stats.skill
		data.speed = stats.speed
		data.luck = stats.luck
		data.move_range = stats.move_range
		data.ignore_terrain_cost = stats.ignore_terrain_cost
		# 默认武器
		var default_weapon = UnitDataManager.get_default_weapon_id(unit_name)
		if default_weapon != "":
			var inst = ItemInstance.new()
			inst.item_id = default_weapon
			inst.count = 1
			data.inventory.append(inst)
			data.equipped_weapon = default_weapon
		party.append(data)
	main_unit_index = main_index
	main_unit_name = selected_units[main_index] if selected_units.size() > main_index else ""

func get_party_units() -> Array[UnitData]:
	return party

func get_main_unit() -> UnitData:
	if party.size() > main_unit_index:
		return party[main_unit_index]
	return null

# 战斗后同步单位状态
func sync_units_from_battlefield(battle_units: Array):
	for i in range(min(party.size(), battle_units.size())):
		var battle_unit = battle_units[i]
		var party_unit = party[i]
		# ... 同步 HP ...
		# 同步库存
		var inv = battle_unit.serialize_inventory()
		party_unit.inventory.clear()
		for entry in inv:
			var inst = ItemInstance.new()
			inst.item_id = entry["item_id"]
			inst.count = entry["count"]
			party_unit.inventory.append(inst)
		party_unit.equipped_weapon = battle_unit.get_equipped_weapon_id()
		# 在 sync_units_from_battlefield 中
		print("战斗单位 ", battle_unit.unit_stats.unit_name, " 库存: ", inv)
		print("同步后队伍单位库存: ", party_unit.inventory)

func reset_all():
	party.clear()
	main_unit_name = ""
	visited_nodes.clear()
	current_day = 1
	current_map_index = 0
	is_map_mode = false
	should_advance_day = false
