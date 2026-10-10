extends Node

const MAX_DURATION : int = 3

var ROUTES : Dictionary = {
	"ruins":   {"name": "废墟",   "tags": ["烈焰"],  "soul_min": 1, "soul_max": 3, "dur": 1},
	"forest":  {"name": "密林",   "tags": ["轮回"],  "soul_min": 2, "soul_max": 3, "dur": 2},
	"mine":    {"name": "矿坑",   "tags": ["灰烬"],  "soul_min": 1, "soul_max": 2, "dur": 1},
	"shrine":  {"name": "古神殿", "tags": ["守护"],  "soul_min": 2, "soul_max": 3, "dur": 3},
	"abyss":   {"name": "深渊",   "tags": ["献祭"],  "soul_min": 3, "soul_max": 3, "dur": 3},
	"volcano": {"name": "火口",   "tags": ["余烬"],  "soul_min": 2, "soul_max": 3, "dur": 2},
}

var unlocked_routes : Array = ["ruins"]
var active_dispatches : Array = []

signal dispatch_started(unit_name: String, route_id: String)
signal dispatch_completed(results: Array)
signal routes_changed()


func get_unlocked_routes() -> Array:
	return unlocked_routes.duplicate()


func is_unit_dispatched(unit_name: String) -> bool:
	for d in active_dispatches:
		if d.unit_name == unit_name: return true
	return false


func get_dispatched_unit_names() -> Array:
	var names : Array = []
	for d in active_dispatches:
		names.append(d.unit_name)
	return names


func dispatch(units: Array, route_id: String) -> bool:
	if units.is_empty() or units.size() > 2: return false
	if not unlocked_routes.has(route_id): return false
	if not ROUTES.has(route_id): return false
	for u in units:
		if is_unit_dispatched(u): return false
	var dur : int = ROUTES[route_id]["dur"]
	# ★ 方向 6：游魂向导亲密度 ≥10 → 派遣时长 -1 局
	if StoryManager.get_affinity("guide") >= 10:
		dur = maxi(1, dur - 1)
	for u in units:
		active_dispatches.append({"unit_name": u, "route_id": route_id, "remaining_runs": dur})
		dispatch_started.emit(u, route_id)
	SaveManager.auto_save()
	return true


func advance_run():
	var completed : Array = []
	var still_active : Array = []
	for d in active_dispatches:
		d.remaining_runs -= 1
		if d.remaining_runs <= 0:
			completed.append(d)
		else:
			still_active.append(d)
	active_dispatches = still_active
	if not completed.is_empty():
		_resolve_completion(completed)


func _resolve_completion(completed: Array):
	var results : Array = []
	for d in completed:
		var route : Dictionary = ROUTES.get(d.route_id, {})
		var soul_min : int = int(route.get("soul_min", 1))
		var soul_max : int = int(route.get("soul_max", 3))
		var gained : int = randi() % (soul_max - soul_min + 1) + soul_min
		GameState.soul += gained
		results.append({"unit_name": d.unit_name, "route_id": d.route_id, "soul": gained})
	GameState.total_dispatch_count += completed.size()
	dispatch_completed.emit(results)


func rotate_routes():
	if unlocked_routes.size() <= 1: return
	var n : int = 1 if unlocked_routes.size() <= 3 else 2
	for i in range(n):
		if unlocked_routes.size() <= 1: break
		var idx : int = randi() % unlocked_routes.size()
		unlocked_routes.remove_at(idx)
	routes_changed.emit()


func unlock_route(route_id: String) -> bool:
	if unlocked_routes.has(route_id): return false
	if not ROUTES.has(route_id): return false
	unlocked_routes.append(route_id)
	SaveManager.auto_save()
	routes_changed.emit()
	return true
