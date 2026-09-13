extends Node

enum InterruptState {
	NONE,
	CAMP,
	MAP,
	BATTLEFIELD,
}

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

const MAX_RELIC_SLOTS = 3

# ---- 地图快照（当前天的地图骨架） ----
var map_snapshot: Dictionary = {}

# ---- 本轮三天基线（用于结算显示） ----
var cycle_start_soul: int = 0
var cycle_start_materials: Dictionary = {}

# ---- 资源 ----
var soul: int = 0          # 永久魂
var temp_soul: int = 0     # 本轮临时魂
var temp_gold: int = 0     # 本轮临时金币
var reward_items: Array = []             # 获得物品 ID 列表（用于结算）

# ---- 材料库存 ----
var materials: Dictionary = {
	"粗铁": 0,
	"精钢": 0,
	"秘银": 0,
	"龙鳞": 0
}

# ---- 单次奖励（用于结算界面） ----
var current_reward_gold: int = 0
var current_reward_soul: int = 0
var current_reward_materials: Dictionary = {}

# ---- 游戏状态 ----
var interrupt_state: InterruptState = InterruptState.NONE
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
	should_advance_day = false
	map_snapshot.clear()

func start_new_cycle():
	temp_soul = 0
	temp_gold = 0
	cycle_start_soul = soul
	cycle_start_materials = materials.duplicate()
	
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
	init_relic_slots()

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
	interrupt_state = InterruptState.NONE
	init_relic_slots()
	current_faction = ""
	map_snapshot.clear()
	cycle_start_soul = 0
	cycle_start_materials.clear()

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
	interrupt_state = InterruptState.NONE
	init_relic_slots()
	current_faction = ""
	map_snapshot.clear()
	cycle_start_soul = 0
	cycle_start_materials.clear()
	
# ============================================================
#  魂与装备
# ============================================================
func finish_day():
	soul += temp_soul
	temp_soul = 0
	for unit_data in party:
		unit_data.armor_slots.append(null)
		unit_data.max_armor_slots += 1
		# ---- 打印验证 ----
		print("finish_day: 单位 ", unit_data.unit_name, " 当前槽位数: ", unit_data.armor_slots.size(), " max_armor_slots: ", unit_data.max_armor_slots)
	print("每天结束：soul=", soul, " temp_soul 已清零")

func abandon_and_return_to_camp():
	# ---- 先弹结算 ----
	await Globals.show_cycle_reward()
	
	# ---- 执行放弃逻辑 ----
	finish_day()
	abandon_cycle()
	reset_all()
	interrupt_state = InterruptState.CAMP
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
# 初始化为 [null, null, null]
func init_relic_slots():
	global_relics.clear()
	for i in range(MAX_RELIC_SLOTS):
		global_relics.append(null)

# 添加到第一个空槽，返回是否成功
func add_global_relic(instance: ItemInstance) -> bool:
	# 确保槽位存在
	while global_relics.size() < MAX_RELIC_SLOTS:
		global_relics.append(null)
	
	for i in range(MAX_RELIC_SLOTS):
		if global_relics[i] == null:
			global_relics[i] = instance
			print("遗物放入槽 ", i, ": ", instance.item_id)
			return true
	
	print("遗物槽已满，无法添加: ", instance.item_id)
	return false

# 按槽位移除，保留空位
func remove_global_relic_at_slot(slot_idx: int):
	if slot_idx >= 0 and slot_idx < global_relics.size():
		global_relics[slot_idx] = null

# 获取全部（含 null）
func get_global_relics() -> Array[ItemInstance]:
	return global_relics.duplicate()

# 获取非空遗物（用于战斗加成计算）
func get_active_relics() -> Array:
	var result = []
	for r in global_relics:
		if r != null:
			result.append(r)
	return result

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
	current_reward_materials = {}

func add_material(material_name: String, amount: int):
	if materials.has(material_name):
		materials[material_name] += amount
	else:
		materials[material_name] = amount
	print("材料增加: ", material_name, " +", amount, " (当前: ", materials[material_name], ")")
	
	# ---- 材料变化后自动保存 ----
	SaveManager.auto_save()

func get_material(material_name: String) -> int:
	return materials.get(material_name, 0)

func get_all_materials() -> Dictionary:
	return materials.duplicate()

func reset_materials():
	for key in materials.keys():
		materials[key] = 0

func get_global_relic_stats() -> Dictionary:
	var bonus = {}
	for relic in global_relics:
		if relic == null:   # ← 跳过 null
			continue
		var data = RelicManager.get_relic_data(relic.item_id)
		if data.is_empty():
			continue
		var stats = data.get("stats", {})
		for key in stats:
			bonus[key] = bonus.get(key, 0) + stats[key]
	return bonus
