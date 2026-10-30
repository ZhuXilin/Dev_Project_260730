extends Node

var _config : Dictionary = {}
var _orbs : Dictionary = {}
var _orb_scene : PackedScene = preload("res://content/scenes/entities/ItemBattlefield.tscn")

func _ready():
	_load_config()
	# ★ 监听回合切换
	if not SignalBus.turn_changed.is_connected(_on_turn_changed):
		SignalBus.turn_changed.connect(_on_turn_changed)

func _load_config():
	var path = "res://content/data/item_battlefield_data.json"
	if not FileAccess.file_exists(path):
		push_error("血球配置不存在: " + path)
		return
	var f = FileAccess.open(path, FileAccess.READ)
	_config = JSON.parse_string(f.get_as_text())
	f.close()

# ★ 核心逻辑：处理生命倒计时
func _on_turn_changed(team: int):
	# 只在我方回合开始时（team == PLAYER）进行结算
	if team != TurnManager.Team.PLAYER:
		return
		
	var to_remove : Array = []
	
	# 遍历所有场上的掉落物
	for cell in _orbs:
		var orb = _orbs[cell]
		if is_instance_valid(orb):
			orb.life_time -= 1
			if orb.life_time < 0:
				to_remove.append(cell)
				
	# 统一清理过期的掉落物
	for cell in to_remove:
		if is_instance_valid(_orbs[cell]):
			_orbs[cell].queue_free()
		_orbs.erase(cell)

func try_spawn_orb(cell: Vector2i):
	if randf() > float(_config.get("drop_chance", 0.3)):
		return
	if _orbs.has(cell):
		return
		
	var orb = _orb_scene.instantiate()
	var bf = get_tree().current_scene
	if bf and bf.name == "Battlefield":
		# ★ 必须先 add_child，让 _ready() 跑完，@onready 才有值
		bf.add_child(orb)
		orb.setup(cell, _config.get("icon_id", "item_089"))
		orb.position = bf.grid_to_world(cell)
		_orbs[cell] = orb

func try_pickup(unit: Unit) -> bool:
	if not is_instance_valid(unit) or unit.unit_stats.team_id != 0:
		return false
	if not _orbs.has(unit.grid_cell):
		return false
		
	var orb = _orbs[unit.grid_cell]
	_orbs.erase(unit.grid_cell)
	if is_instance_valid(orb):
		orb.queue_free()
		
	# 回复 25% 最大 HP
	var heal : int = maxi(1, int(unit.unit_stats.max_hp * float(_config.get("heal_percent", 0.25))))
	var old : int = unit.hit_points
	unit.hit_points = mini(unit.hit_points + heal, unit.unit_stats.max_hp)
	var actual : int = unit.hit_points - old
	if actual > 0:
		unit.update_hp_label()
		SignalBus.request_damage_popup.emit(unit.global_position, actual, false, false, true)
		SoundManager.play_heal_sound()
	return true

func clear_all():
	for cell in _orbs:
		if is_instance_valid(_orbs[cell]):
			_orbs[cell].queue_free()
	_orbs.clear()
