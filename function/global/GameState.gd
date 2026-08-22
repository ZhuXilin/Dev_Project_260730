extends Node

# ---- 队伍数据 ----
var party: Array[UnitData] = []
var max_party_size: int = 3
var main_unit_name: String = ""          # 记录主单位类型名称
var main_unit_index: int = 0

# ---- 地图进度 ----
var current_day: int = 1                 # 当前天数（1、2、3）
var current_map_index: int = 0
var visited_nodes: Dictionary = {}       # 记录已访问节点，key: "x_y", value: true
var current_node_key: String = ""        # 记录当前进入战斗的节点 key，用于中断时撤销访问
var is_map_mode: bool = false
var cached_map_level_data: MapLevelData = null   # 当前天的地图缓存
var cached_day: int = -1                 # 缓存对应的天数
var last_selected_node_type: int = -1
var current_map_data: MapData = null     # 当前正在战斗的地图数据
var should_advance_day: bool = false     # Boss胜利后推进天数的标志
var resume_node_id: String = ""          # 加载存档后要定位的节点ID

# ---- 资源 ----
var soul: int = 0          # 永久魂
var temp_soul: int = 0     # 本轮临时魂
var temp_gold: int = 0     # 本轮临时金币
var reward_items: Array = []             # 获得物品 ID 列表（用于结算）

# ---- 单次奖励（用于结算界面） ----
var current_reward_gold: int = 0
var current_reward_soul: int = 0

# ---- 游戏状态 ----
var interrupt_state: int = 0   # 0=无, 1=营地, 2=地图, 3=战场
var battlefield_data: Dictionary = {}   # 预留战场数据

# ---- 装备系统 ----
var global_relics: Array[ItemInstance] = []   # 全局遗物
var current_faction: String = ""              # 当前阵营

# ---- 存档辅助 ----
var pending_save_slot: int = -1

# ============================================================
#  队伍初始化
# ============================================================
func initialize_party(selected_units: Array[String], main_index: int):
	party.clear()
	for unit_name in selected_units:
		var data = UnitDataManager.create_unit_data(unit_name)
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
		party_unit.hit_points = battle_unit.hit_points
		# 同步武器和防具
		party_unit.weapon_slot = battle_unit.weapon_slot
		party_unit.armor_slots = battle_unit.armor_slots.duplicate()
		party_unit.max_armor_slots = battle_unit.max_armor_slots

# ============================================================
#  进度重置
# ============================================================
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
	
	for unit_data in party:
		unit_data.armor_slots.clear()
		unit_data.max_armor_slots = 2
		var default_weapon = UnitDataManager.get_default_weapon_id(unit_data.unit_name)
		if default_weapon != "":
			var inst = ItemInstance.new()
			inst.item_id = default_weapon
			inst.count = 1
			unit_data.weapon_slot = inst
		else:
			unit_data.weapon_slot = null
	global_relics.clear()

func finish_cycle():
	finish_day()          # 合并魂并清零

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
	temp_soul = 0
	temp_gold = 0
	interrupt_state = 0
	global_relics.clear()
	current_faction = ""

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
	temp_soul = 0
	temp_gold = 0
	interrupt_state = 0
	global_relics.clear()
	current_faction = ""

# ============================================================
#  魂与装备
# ============================================================
func finish_day():
	soul += temp_soul
	temp_soul = 0
	for unit_data in party:
		unit_data.armor_slots.append(null)
		unit_data.max_armor_slots += 1
	print("每天结束：soul=", soul, " temp_soul 已清零，槽位增加")

func abandon_and_return_to_camp():
	finish_day()
	abandon_cycle()
	reset_all()
	interrupt_state = 1
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")

func show_abandon_confirmation(parent: Node):
	Globals.show_confirm(
		parent,
		"确定放弃本局游戏吗？进度将丢失，已获得的临时资源将丢弃。",
		"放弃",
		"取消",
		abandon_and_return_to_camp,
		func(): pass
	)

# ============================================================
#  遗物管理
# ============================================================
func add_global_relic(instance: ItemInstance):
	global_relics.append(instance)

func remove_global_relic(instance: ItemInstance):
	global_relics.erase(instance)

func get_global_relics() -> Array[ItemInstance]:
	return global_relics.duplicate()

func get_global_relic_stats() -> Dictionary:
	var bonus = {}
	for relic in global_relics:
		var data = ItemManager.get_item_data(relic.item_id)
		if data and data.stats:
			for key in data.stats:
				bonus[key] = bonus.get(key, 0) + data.stats[key]
	return bonus

# ============================================================
#  中断战斗撤销
# ============================================================
func undo_battle_entry():
	# 只清除当前节点键，但保留访问标记，以保持地图进度
	current_node_key = ""
	# 不要删除 visited_nodes 中的条目
	should_advance_day = false

# ============================================================
#  奖励物品记录（用于结算界面）
# ============================================================
func add_reward_item(item_id: String):
	if item_id not in reward_items:
		reward_items.append(item_id)

func clear_reward_items():
	reward_items.clear()

# ============================================================
#  单次奖励记录（用于结算界面）
# ============================================================
func clear_current_reward():
	current_reward_gold = 0
	current_reward_soul = 0
