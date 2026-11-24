extends Node

# ============================================================
#  SoulFireManager — 魂火（局内唯一核心战斗资源）
#  v5.0：
#    - 获得：命中 +N，击杀 +M，一击多杀额外 +K（全部来自战斗）
#    - 消耗：技能 / 急救 / 局内购买光环
#    - 兑现：删除（不再 1:1 换魂）
#    - 状态（v6.62z 两态）：BURNING（燃烧）/ NORMAL（正常无增益）。
#      归零并入 NORMAL，仅通过 HUD「熄」标记提示，不是负面状态、也不给额外增益。
#      余烬「魂火耗尽下击必暴」是该流派机制，不是通用低魂火收益。
# ============================================================

## ★ v6.62z：两态——燃烧 / 正常。归零并入 NORMAL（无增益、无惩罚）。
enum State { NORMAL, BURNING }

const MAX_CARRIED_LEVELS : Array[int] = [8, 12, 16, 22, 30, 40, 50]
const UPGRADE_COSTS      : Array[int] = [0, 30, 80, 180, 350, 600, 1000]
const INITIAL_LEVELS     : Array[int] = [0, 1, 2, 3]
const INITIAL_COSTS      : Array[int] = [0, 50, 200, 800]

# ★ 主动技能魂火消耗兜底常量（CombatManager._get_active_skill_cost 使用）
# 技能在 talents.json 里显式配 soul_fire_cost（2 或 3）时走显式值；
# 未配置时按效果类型兜底：普通攻击类 2、治疗类 3。
const COST_SKILL_MIN : int = 2
const COST_SKILL_MAX : int = 3

# ★ v5.0：从 combat_config.json 读取，下列是默认值
var HIT_GAIN : int = 1
var KILL_GAIN : int = 3
var MULTI_KILL_BONUS : int = 2

var current : int = 0
var altar_level : int = 0
var _boss_penalty : int = 0

# ★ 我方单位阵亡时的魂火补偿
var ALLY_DEATH_GAIN : int = 5

signal soul_fire_changed(current: int, max_carried: int)
signal state_changed(new_state: State)


func _ready():
	altar_level = GameState.soul_fire_altar_level
	current = clampi(GameState.soul_fire_current, 0, get_max_carried())
	_load_config()


func _load_config():
	var cfg : Dictionary = GameConfigManager.get_value("combat_config.json", "soul_fire_gain", {})
	if cfg.is_empty():
		return
	HIT_GAIN = int(cfg.get("hit", HIT_GAIN))
	KILL_GAIN = int(cfg.get("kill", KILL_GAIN))
	MULTI_KILL_BONUS = int(cfg.get("multi_kill_bonus", MULTI_KILL_BONUS))
	ALLY_DEATH_GAIN = int(cfg.get("ally_death", ALLY_DEATH_GAIN))
	print("[SoulFire] 获得配置: hit=%d, kill=%d, multi_kill_bonus=%d, ally_death=%d" % [
		HIT_GAIN, KILL_GAIN, MULTI_KILL_BONUS, ALLY_DEATH_GAIN])


func get_max_carried() -> int:
	var base : int = MAX_CARRIED_LEVELS[clampi(altar_level, 0, MAX_CARRIED_LEVELS.size() - 1)]
	if LevelManager.current_resonance.get("type", "") == "soul_fire_max":
		base += int(LevelManager.current_resonance.get("value", 0))

	var flame_bonus : int = 0
	if _has_eternal_flame():
		flame_bonus = 5
	# v5.1：余烬套装 2 件生效（+3），含史诗质变（+6），随 tier 自动取档
	var set_bonus : int = int(SetBonusManager.get_team_tag_effect_value("余烬", "soul_fire_max"))
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
	# ★ v6.62z：两态——燃烧 / 正常。归零并入正常（无增益、无惩罚），
	#   仅用 is_exhausted() + HUD「熄」标记提示，不再有枯竭态与枯竭暴伤。
	var r : float = get_ratio()
	var burning_threshold : float = 0.5
	var override : float = GameState.soul_fire_threshold_override
	if override > 0.0 and override < burning_threshold:
		burning_threshold = override
	if r > burning_threshold:
		return State.BURNING
	return State.NORMAL


## 归零标记（不占状态枚举）：当前魂火为 0
func is_exhausted() -> bool:
	return current <= 0


func get_move_bonus() -> int:
	return 1 if get_state() == State.BURNING else 0

func get_splash_percent() -> float:
	return 0.5 if get_state() == State.BURNING else 0.0

## ★ v6.62z：删除枯竭暴伤——低魂火/归零不提供任何额外增益。
##   保留 API 返回 0 供旧调用点兼容；余烬「耗尽必暴」走 CombatManager 的独立机制。
func get_crit_damage_bonus() -> float:
	return 0.0

# ★ v5.0：删除 DEPLETED 的受伤放大，始终 1.0
func get_damage_taken_mult() -> float:
	return 1.0


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


func get_emergency_heal_cost() -> int:
	var cap : int = get_max_carried()
	return maxi(2, int(ceil(float(cap) * 0.15)))


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


# ★ v5.0：settle() 不再把魂火兑换成魂，仅清空
# 保留 API 以兼容 GameState.finish_day / abandon_and_return_to_camp
func settle() -> int:
	current = 0
	GameState.soul_fire_current = 0
	_emit_changes()
	return 0


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
#  ★ v5.0：战斗中获得魂火
# ============================================================
## 攻击命中敌人（未击杀）。由 CombatManager 在每次命中结算完成后调用。
## hit_count：本次攻击命中多少个敌人（AOE 时 > 1）
## 返回实际获得的魂火
func on_hit(hit_count: int = 1) -> int:
	if hit_count <= 0:
		return 0
	return add(HIT_GAIN * hit_count)


## 攻击击杀敌人。由 CombatManager 在击杀结算完成后调用。
## kill_count：本次攻击击杀多少个敌人（AOE 时 > 1）
## 返回实际获得的魂火
func on_kill(kill_count: int = 1) -> int:
	if kill_count <= 0:
		return 0
	var base : int = KILL_GAIN * kill_count
	if kill_count > 1:
		base += (kill_count - 1) * MULTI_KILL_BONUS

	var mult : float = 1.0
	if GameState.current_map_data != null:
		mult = maxf(1.0, GameState.current_map_data.reward_multiplier)
	var gain : int = maxi(1, int(round(float(base) * mult)))
	# ★ v5.17：原 ZERO 态击杀 +1 的「触底反弹」补偿保留，改用 is_exhausted() 判定
	if is_exhausted():
		gain += 1
	return add(gain)


# ============================================================
#  回合开始钩子（保留空实现以兼容 TurnManager 调用）
# ============================================================
func tick_turn_start(_units: Array) -> void:
	pass


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
