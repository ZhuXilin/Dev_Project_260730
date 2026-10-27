extends Node

# ============================================================
#  SoulFireManager — 魂火（局内唯一核心资源）
# ============================================================

enum State { NORMAL, BURNING, DEPLETED, ZERO }

const MAX_CARRIED_LEVELS : Array[int] = [5, 8, 12, 18, 25, 33, 42]
const UPGRADE_COSTS      : Array[int] = [0, 30, 80, 180, 350, 600, 1000]
const INITIAL_LEVELS     : Array[int] = [0, 1, 2, 3]
const INITIAL_COSTS      : Array[int] = [0, 50, 200, 800]

var REWARD_ON_KILL : Dictionary = {
	MapNode.NodeType.START:   1,
	MapNode.NodeType.NORMAL:  1,
	MapNode.NodeType.ELITE:   2,
	MapNode.NodeType.BOSS:    4,
}
var REWARD_EXTRA_BOSS : int = 2
var REWARD_KILL_STREAK : int = 1
var REWARD_NO_DAMAGE : int = 1

const COST_SKILL_MIN : int = 2
const COST_SKILL_MAX : int = 3
const COST_AURA_MIN : int = 5
const COST_AURA_MAX : int = 8
const COST_ATTR_BASE : int = 1
const COST_SHOP_RESET : int = 5

var current : int = 0
var altar_level : int = 0
var _boss_penalty : int = 0

signal soul_fire_changed(current: int, max_carried: int)
signal state_changed(new_state: State)


func _ready():
	altar_level = GameState.soul_fire_altar_level
	current = clampi(GameState.soul_fire_current, 0, get_max_carried())


func get_max_carried() -> int:
	var base : int = MAX_CARRIED_LEVELS[clampi(altar_level, 0, MAX_CARRIED_LEVELS.size() - 1)]
	if LevelManager.current_resonance.get("type", "") == "soul_fire_max":
		base += int(LevelManager.current_resonance.get("value", 0))

	var flame_bonus : int = 0
	if _has_eternal_flame():
		flame_bonus = 5
	var set_bonus : int = 0
	if SetBonusManager.team_has_set("余烬"):
		var b : Dictionary = SetBonusManager.get_bonus("余烬")
		set_bonus = int(b.get("value", 3))
	base += maxi(flame_bonus, set_bonus)

	if StoryManager.get_affinity("soul_keeper") >= 10:
		base += 1
	return maxi(0, base - _boss_penalty)


func get_initial_soul_fire() -> int:
	var base : int = INITIAL_LEVELS[clampi(GameState.soul_fire_initial_level, 0, INITIAL_LEVELS.size() - 1)]
	if LevelManager.current_resonance.get("type", "") == "soul_fire_initial":
		base += int(LevelManager.current_resonance.get("value", 0))
	if StoryManager.get_affinity("soul_keeper") >= 15:
		base += 1
	return base


func get_ratio() -> float:
	var m : int = get_max_carried()
	return float(current) / float(m) if m > 0 else 0.0


func get_state() -> State:
	if current <= 0:
		return State.ZERO
	var r : float = get_ratio()

	var burning_threshold : float = 0.5
	var depleted_threshold : float = 0.2
	var override : float = GameState.soul_fire_threshold_override
	if override > 0.0 and override < burning_threshold:
		burning_threshold = override

	if r > burning_threshold:
		return State.BURNING
	elif r < depleted_threshold:
		return State.DEPLETED
	return State.NORMAL


func get_move_bonus() -> int:
	return 1 if get_state() == State.BURNING else 0

func get_splash_percent() -> float:
	return 0.5 if get_state() == State.BURNING else 0.0

func get_crit_damage_bonus() -> float:
	return 0.5 if get_state() == State.DEPLETED else 0.0

func get_damage_taken_mult() -> float:
	return 1.3 if get_state() == State.DEPLETED else 1.0


func can_spend(amount: int) -> bool:
	return current >= amount


func get_upgrade_cost() -> int:
	if altar_level >= MAX_CARRIED_LEVELS.size() - 1:
		return -1
	return UPGRADE_COSTS[altar_level + 1]


func get_initial_upgrade_cost() -> int:
	var lv : int = GameState.soul_fire_initial_level
	if lv >= INITIAL_LEVELS.size() - 1:
		return -1
	return INITIAL_COSTS[lv + 1]


func add(amount: int) -> int:
	if amount <= 0: return 0
	var before : int = current
	current = mini(current + amount, get_max_carried())
	var actual : int = current - before
	if actual > 0:
		_emit_changes()
	return actual


func spend(amount: int) -> bool:
	if amount <= 0: return true
	if current < amount: return false
	current -= amount
	_emit_changes()
	return true


func settle() -> int:
	var gained : int = current
	GameState.soul += gained
	current = 0
	GameState.soul_fire_current = 0
	_emit_changes()
	return gained


func reset_for_new_run():
	current = get_initial_soul_fire()
	_boss_penalty = 0
	GameState.soul_fire_current = current
	_emit_changes()


func upgrade_altar() -> bool:
	var cost : int = get_upgrade_cost()
	if cost < 0 or GameState.soul < cost: return false
	GameState.soul -= cost
	altar_level += 1
	_emit_changes()
	SaveManager.auto_save()
	return true


func upgrade_initial() -> bool:
	var cost : int = get_initial_upgrade_cost()
	if cost < 0 or GameState.soul < cost: return false
	GameState.soul -= cost
	GameState.soul_fire_initial_level += 1
	SaveManager.auto_save()
	return true


# ============================================================
#  回合开始钩子
#  v4.6：去掉"归零扣 5% max HP"惩罚。归零不再有战斗惩罚，
#  只保留 State.ZERO 状态用于 UI 显示"魂火耗尽"。
#  保留函数签名，TurnManager 继续调它，行为为空。
# ============================================================
func tick_turn_start(_units: Array) -> void:
	pass


func on_kill() -> void:
	var mult : float = 1.0
	if GameState.current_map_data != null:
		mult = maxf(1.0, GameState.current_map_data.reward_multiplier)
	var gain : int = maxi(1, int(round(1.0 * mult)))
	if get_state() == State.ZERO:
		gain += 1
	add(gain)


func _has_eternal_flame() -> bool:
	for u in GameState.party:
		if u.is_dead: continue
		for slot in u.armor_slots:
			if slot and slot.item_id == "eternal_flame":
				return true
	return false


# ============================================================
#  Boss 三形态：临时上限惩罚
# ============================================================
func add_boss_penalty(amount: int) -> void:
	_boss_penalty += amount
	current = mini(current, get_max_carried())
	_emit_changes()
	print("[SoulFire] Boss 惩罚 +%d，本场上限 → %d" % [amount, get_max_carried()])


func reset_boss_penalty() -> void:
	if _boss_penalty != 0:
		print("[SoulFire] 清除 Boss 上限惩罚（-%d）" % _boss_penalty)
	_boss_penalty = 0
	_emit_changes()


func get_boss_penalty() -> int:
	return _boss_penalty


func _emit_changes():
	soul_fire_changed.emit(current, get_max_carried())
	state_changed.emit(get_state())
