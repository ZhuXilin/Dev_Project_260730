class_name GridPushManager
extends RefCounted

## ============================================================
##  GridPushManager — 击退 / 撞墙 / 连撞 / 危险地形（v6.68）
## ============================================================
##  位置后果系统的地基：把目标沿方向逐格推开，判定边界/不可通行地形/
##  单位占位造成的撞击。撞墙则受额外伤害并眩晕；撞单位则把对方继续沿同方向
##  推（递归，深度与循环双重上限），碰撞伤害逐层衰减。最终落点是灰烬地块时
##  生成危险地形伤害事件。
##  与 v6.63 体系兼容：不改变攻击按钮；所有位置伤害只产出事件，由 CombatManager
##  统一走 _apply_damage_with_effects(..., trigger_abnormal=false) 结算。
##  配置来自 soulfire_identity.json 的 knockback / position 段。
## ============================================================

const CFG_FILE: String = "soulfire_identity.json"


static func get_config() -> Dictionary:
	var raw: Variant = GameConfigManager.get_value(CFG_FILE, "knockback", null)
	return raw as Dictionary if raw is Dictionary else {}


## 按爆发阈值取默认击退格数（快爆1/中节奏2/慢攒1）
static func get_cells_for_threshold(threshold: int) -> int:
	var cfg: Dictionary = get_config()
	var by: Dictionary = cfg.get("cells_by_threshold", {})
	var v: Variant = by.get(str(threshold), 1)
	return maxi(0, int(v))


## 世界坐标（与 Battlefield.grid_to_world 同口径，避免依赖场景实例）
static func _world_of(cell: Vector2i) -> Vector2:
	var ox: float = cell.x * MapConst.CELL_SIZE + MapConst.CELL_SIZE / 2.0
	var oy: float = cell.y * MapConst.CELL_SIZE + MapConst.CELL_SIZE / 2.0
	return Vector2(ox, oy)


static func _attacker_attack(attacker: Unit) -> int:
	if is_instance_valid(attacker) and attacker.unit_stats != null:
		return maxi(0, int(attacker.unit_stats.attack))
	return 0


static func _block_at(cell: Vector2i, ignore_unit: Unit) -> Dictionary:
	var gs: Vector2i = TerrainManager.grid_size
	if gs.x <= 0 or gs.y <= 0:
		gs = MapConst.DEFAULT_MAP_SIZE
	if cell.x < 0 or cell.y < 0 or cell.x >= gs.x or cell.y >= gs.y:
		return {"blocked": true, "unit": null}
	var td: Dictionary = TerrainManager.TERRAIN_DATA.get(TerrainManager.get_terrain(cell), {})
	if not bool(td.get("passable", true)):
		return {"blocked": true, "unit": null}
	var occupant: Unit = UnitManager.get_unit_at_cell(cell)
	if occupant != null and occupant != ignore_unit:
		return {"blocked": true, "unit": occupant}
	return {"blocked": false, "unit": null}


## 格子是否可站立（在边界内 + 地形可通行 + 无单位占位）
static func _can_stand(cell: Vector2i, ignore_unit: Unit) -> bool:
	return not bool(_block_at(cell, ignore_unit).get("blocked", true))


## 从 unit 当前格沿 dir 最多走 cells 步，停在第一个阻挡物前。
static func _resolve_steps(unit: Unit, cells: int, dir: Vector2i) -> Dictionary:
	var cur: Vector2i = unit.grid_cell
	var moved: int = 0
	var blocked: bool = false
	var blocker: Unit = null
	for _i in range(cells):
		var nxt: Vector2i = cur + dir
		var block: Dictionary = _block_at(nxt, unit)
		if bool(block.get("blocked", false)):
			blocked = true
			blocker = block.get("unit", null)
			break
		cur = nxt
		moved += 1
	return {"cur": cur, "moved": moved, "blocked": blocked, "blocker": blocker}


static func _add_event(ctx: Dictionary, victim: Unit, source: Unit, kind: String, \
		damage: int, stun: int, cell: Vector2i) -> void:
	var events: Array = ctx.get("events", [])
	events.append({
		"unit": victim,
		"source": source,
		"kind": kind,
		"damage": damage,
		"stun": stun,
		"cell": cell,
	})
	ctx["events"] = events


## 递归推链。ctx 在整条链内共享：events 收集伤害事件，visited 防循环。
static func _push_chain(attacker: Unit, unit: Unit, cells: int, dir: Vector2i, \
		depth: int, ctx: Dictionary) -> Dictionary:
	var res: Dictionary = {"moved": 0, "final_cell": unit.grid_cell if is_instance_valid(unit) else Vector2i.ZERO, \
		"hit_wall": false, "wall_damage": 0, "stun": 0, "chained": 0}
	if not is_instance_valid(unit) or unit.hit_points <= 0 or cells <= 0 or dir == Vector2i.ZERO:
		return res
	var uid: int = unit.get_instance_id()
	var visited: Dictionary = ctx.get("visited", {})
	if visited.has(uid):
		return res
	visited[uid] = true
	ctx["visited"] = visited

	var cfg: Dictionary = get_config()
	var atk: int = _attacker_attack(attacker)
	var step_info: Dictionary = _resolve_steps(unit, cells, dir)
	var blocker_v: Variant = step_info.get("blocker", null)
	var blocker: Unit = null
	if blocker_v is Unit:
		blocker = blocker_v as Unit
	var max_depth: int = clampi(int(cfg.get("max_chain_depth", 3)), 1, 8)

	# 1) 撞到单位：先推前面那个（深度优先），它让开后本单位可能继续前进。
	if blocker != null and depth < max_depth and not visited.has(blocker.get_instance_id()):
		var remain: int = cells - int(step_info.get("moved", 0))
		var chain_cells: int = maxi(maxi(1, int(cfg.get("min_chain_cells", 1))), remain)
		await _push_chain(attacker, blocker, chain_cells, dir, depth + 1, ctx)
		var falloff: float = pow(maxf(0.0, float(cfg.get("chain_damage_falloff", 0.6))), float(depth))
		var collide_dmg: int = maxi(1, int(float(atk) * float(cfg.get("push_damage", 0.15)) * falloff))
		_add_event(ctx, blocker, attacker, "unit_collision", collide_dmg, 0, blocker.grid_cell)
		ctx["chain_depth"] = maxi(int(ctx.get("chain_depth", 0)), depth + 1)
		var chained_units: Array = ctx.get("chain_units", [])
		chained_units.append(blocker.get_instance_id())
		ctx["chain_units"] = chained_units
		res["chained"] = depth + 1
		# 前单位已经移动，重算本单位路径（可能被完全让开）
		step_info = _resolve_steps(unit, cells, dir)
		blocker_v = step_info.get("blocker", null)
		blocker = null
		if blocker_v is Unit:
			blocker = blocker_v as Unit

	# 2) 仍被阻挡（墙/边界/不可通行/无法再推的单位）→ 撞墙结算
	if bool(step_info.get("blocked", false)):
		var remain: int = cells - int(step_info.get("moved", 0))
		if remain > 0:
			var wall_dmg: int = maxi(1, int(float(atk) * float(cfg.get("wall_damage_per_cell", 0.2)) * float(remain)))
			var wall_stun: int = maxi(0, int(cfg.get("wall_stun_rounds", 1)))
			var final_cell: Vector2i = step_info.get("cur", unit.grid_cell)
			_add_event(ctx, unit, attacker, "wall", wall_dmg, wall_stun, final_cell)
			res["hit_wall"] = true
			res["wall_damage"] = wall_dmg
			res["stun"] = wall_stun
			unit.play_hit_effect(Vector2(dir), true)

	# 3) 逐格位移动画（最后移动，保证连撞的视觉顺序是"前面先走、后面跟上"）
	var cur: Vector2i = step_info.get("cur", unit.grid_cell)
	var moved: int = int(step_info.get("moved", 0))
	if moved > 0:
		var step_frames: int = maxi(1, int(cfg.get("step_frames", 3)))
		var step_dur: float = 0.12 / float(step_frames) * 2.0
		var tw := unit.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(unit, "position", _world_of(cur), step_dur * float(moved))
		unit.update_position(cur)
		await tw.finished

	res["moved"] = moved
	res["final_cell"] = cur

	# 4) 危险地形：落入敌方灰烬地块 → 一次性伤害事件（地块消费掉）。
	#    己方地块不伤自己，保留给敌人踩。
	if PositionManager.is_danger_cell(cur) and PositionManager.danger_enabled():
		var tile_v: Variant = CombatManager.ash_tiles.get(cur, null)
		if tile_v is Dictionary:
			var tile: Dictionary = tile_v as Dictionary
			if unit.unit_stats == null or int(tile.get("team", -1)) != unit.unit_stats.team_id:
				var danger_dmg: int = PositionManager.danger_damage(cur)
				if danger_dmg > 0:
					var source: Unit = PositionManager.danger_owner(cur)
					if source == null or not is_instance_valid(source):
						source = attacker
					CombatManager.ash_tiles.erase(cur)
					_add_event(ctx, unit, source, "danger", danger_dmg, 0, cur)
					unit.play_hit_effect(Vector2(dir), true)
	return res


## 击退主入口（async）。
##   attacker: 施加击退者（伤害与击杀归属的默认来源）
##   target: 被推单位
##   cells: 最多推几格
##   dir: 推动方向（单位向量，通常从攻击者指向目标的延长线）
## 返回：{moved, hit_wall, wall_damage, stun, final_cell, chained, events, chain_depth, chain_units}
##   events 内每条：{unit, source, kind, damage, stun, cell}
static func push(attacker: Unit, target: Unit, cells: int, dir: Vector2i) -> Dictionary:
	var result: Dictionary = {"moved": 0, "hit_wall": false, "wall_damage": 0, "stun": 0, \
		"final_cell": target.grid_cell if is_instance_valid(target) else Vector2i.ZERO, \
		"chained": 0, "events": [], "chain_depth": 0, "chain_units": []}
	if not is_instance_valid(target) or target.hit_points <= 0 or cells <= 0:
		return result
	if dir == Vector2i.ZERO:
		return result
	var ctx: Dictionary = {"events": [], "visited": {}, "chain_depth": 0, "chain_units": []}
	var chain_res: Dictionary = await _push_chain(attacker, target, cells, dir, 0, ctx)
	for k in ["moved", "hit_wall", "wall_damage", "stun", "final_cell", "chained"]:
		result[k] = chain_res.get(k, result[k])
	result["events"] = ctx.get("events", [])
	result["chain_depth"] = int(ctx.get("chain_depth", 0))
	result["chain_units"] = ctx.get("chain_units", [])
	return result
