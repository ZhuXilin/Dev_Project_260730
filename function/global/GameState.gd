extends Node

# ---- 队伍数据 ----
var party: Array[UnitData] = []
var max_party_size: int = 3
var main_unit_name: String = ""          # 记录主单位名称
var main_unit_index: int = 0

# ---- 地图进度 ----
var current_day: int = 1                 # 当前天数（1、2、3）
var current_map_index: int = 0
var visited_nodes: Dictionary = {}       # 记录已访问节点，key: "x_y", value: true
var is_map_mode: bool = false
var cached_map_level_data: MapLevelData = null   # 当前天的地图缓存
var cached_day: int = -1                 # 缓存对应的天数
var last_selected_node_type: int = -1
var current_map_data: MapData = null     # 当前正在战斗的地图数据
var should_advance_day: bool = false     # Boss胜利后推进天数的标志
var resume_node_id: String = ""          # 加载存档后要定位的节点ID

var soul: int = 0          # 永久魂
var temp_soul: int = 0     # 本轮临时魂
var temp_gold: int = 0     # 本轮临时金币
var interrupt_state: int = 0   # 0=无, 1=营地, 2=地图, 3=战场
var battlefield_data: Dictionary = {}   # 预留战场数据

# ---- 存档辅助 ----
var pending_save_slot: int = -1          # 用于新建存档时记录槽位（实际已移至Globals，但保留）

# ============================================================
#  队伍初始化
# ============================================================
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

# ============================================================
#  队伍查询
# ============================================================
func get_party_units() -> Array[UnitData]:
	return party

func get_main_unit() -> UnitData:
	if party.size() > main_unit_index:
		return party[main_unit_index]
	return null

# ============================================================
#  战斗后同步单位状态
# ============================================================
func sync_units_from_battlefield(battle_units: Array):
	for i in range(min(party.size(), battle_units.size())):
		var battle_unit = battle_units[i]
		var party_unit = party[i]
		# 同步 HP（假设 battle_unit 有 hit_points）
		party_unit.hit_points = battle_unit.hit_points
		# 同步库存
		var inv = battle_unit.serialize_inventory()
		party_unit.inventory.clear()
		for entry in inv:
			var inst = ItemInstance.new()
			inst.item_id = entry["item_id"]
			inst.count = entry["count"]
			party_unit.inventory.append(inst)
		party_unit.equipped_weapon = battle_unit.get_equipped_weapon_id()
		print("战斗单位 ", battle_unit.unit_stats.unit_name, " 库存: ", inv)
		print("同步后队伍单位库存: ", party_unit.inventory)


func reset_progress():
	visited_nodes.clear()
	current_day = 1
	cached_map_level_data = null
	cached_day = -1
	resume_node_id = ""
	should_advance_day = false
	current_map_data = null
	last_selected_node_type = -1
	# 保留 party 不变（由 initialize_party 重新设置）

func start_new_cycle():
	temp_soul = 0
	temp_gold = 0

func finish_cycle():
	soul += temp_soul
	temp_soul = 0
	temp_gold = 0

func abandon_cycle():
	temp_soul = 0
	temp_gold = 0

func reset_for_new_cycle():
	party.clear()
	main_unit_name = ""
	visited_nodes.clear()
	current_day = 1
	cached_map_level_data = null
	cached_day = -1
	resume_node_id = ""
	should_advance_day = false
	current_map_data = null
	last_selected_node_type = -1
	LevelManager.current_day = 0
	LevelManager.current_level_index = 0
	# 保留 soul, gold
	temp_soul = 0
	temp_gold = 0
	interrupt_state = 0

func reset_all():
	party.clear()
	main_unit_name = ""
	visited_nodes.clear()
	current_day = 1
	current_map_index = 0
	is_map_mode = false
	should_advance_day = false
	resume_node_id = ""
	cached_map_level_data = null
	cached_day = -1
	current_map_data = null
	last_selected_node_type = -1
	LevelManager.reset()
	# 保留 soul, gold
	temp_soul = 0
	temp_gold = 0
	interrupt_state = 0
