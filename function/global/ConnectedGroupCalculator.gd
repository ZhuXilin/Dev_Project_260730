class_name ConnectedGroupCalculator
extends RefCounted

# ============================================================
#  ConnectedGroupCalculator — 防具连通组计算
#  输入：3 个单位的防具槽（含空槽）
#  输出：连通组列表（每组：防具集合、跨单位数、是否含双箭头）
# ============================================================

## 一个"格位"= (unit_index, row)
class Cell:
	var unit_index: int
	var row: int
	func _init(u: int, r: int):
		unit_index = u
		row = r
	func key() -> String:
		return "%d_%d" % [unit_index, row]


## 一个"连通组"
class Group:
	var cells: Array = []          # Array[Cell]
	var items: Array = []          # Array[ItemInstance]
	var unit_indices: Dictionary = {}
	var has_double_arrow: bool = false
	var edge_count: int = 0

	func size() -> int: return cells.size()
	func unit_count() -> int: return unit_indices.size()


## 主入口
## slots: Array[Array[ItemInstance]]  长度=3，每个内层长度=该单位的槽数
## 返回：Array[Group]
static func compute_groups(slots: Array) -> Array:
	var nodes : Dictionary = {}    # cell_key -> Cell
	var items : Dictionary = {}    # cell_key -> ItemInstance
	for u in range(slots.size()):
		for r in range(slots[u].size()):
			var inst = slots[u][r]
			if inst == null: continue
			if inst.direction == Direction.Value.NONE: continue
			var c := Cell.new(u, r)
			nodes[c.key()] = c
			items[c.key()] = inst

	var parent : Dictionary = {}
	for k in nodes:
		parent[k] = k

	# 检查每对相邻格是否连通
	for u in range(slots.size()):
		for r in range(slots[u].size()):
			var key_a : String = "%d_%d" % [u, r]
			if not nodes.has(key_a): continue
			var a_inst : ItemInstance = items[key_a]

			# 单位内：A 向下连 → A 下方槽（r+1）
			if r + 1 < slots[u].size():
				var key_b : String = "%d_%d" % [u, r + 1]
				if nodes.has(key_b):
					var b_inst : ItemInstance = items[key_b]
					if _linked_vertical(a_inst.direction, b_inst.direction):
						_union(parent, key_a, key_b)

			# 跨单位向右：A 的"右/斜线"→ U+1 的 r 行 / r±1 行
			if u + 1 < slots.size():
				# 对齐：RIGHT ↔ LEFT
				if r < slots[u + 1].size():
					var key_r : String = "%d_%d" % [u + 1, r]
					if nodes.has(key_r):
						var b_inst2 : ItemInstance = items[key_r]
						if _linked_horizontal(a_inst.direction, b_inst2.direction):
							_union(parent, key_a, key_r)
				# 斜线：A 的 DIAG_NE_SW → U+1 的 r-1（右上）
				if r - 1 >= 0 and r - 1 < slots[u + 1].size():
					var key_d1 : String = "%d_%d" % [u + 1, r - 1]
					if nodes.has(key_d1):
						var b_inst3 : ItemInstance = items[key_d1]
						if _linked_diag_ur(a_inst.direction, b_inst3.direction):
							_union(parent, key_a, key_d1)
				# 斜线：A 的 DIAG_NW_SE → U+1 的 r+1（右下）
				if r + 1 < slots[u + 1].size():
					var key_d2 : String = "%d_%d" % [u + 1, r + 1]
					if nodes.has(key_d2):
						var b_inst4 : ItemInstance = items[key_d2]
						if _linked_diag_dr(a_inst.direction, b_inst4.direction):
							_union(parent, key_a, key_d2)

	# 按 root 分组
	var groups_map : Dictionary = {}
	for k in nodes:
		var root = _find(parent, k)
		if not groups_map.has(root):
			groups_map[root] = []
		groups_map[root].append(k)

	var groups : Array = []
	for root in groups_map:
		var cell_keys : Array = groups_map[root]
		if cell_keys.size() < 2: continue
		var g := Group.new()
		for ck in cell_keys:
			g.cells.append(nodes[ck])
			g.items.append(items[ck])
			g.unit_indices[nodes[ck].unit_index] = true
			var inst2 : ItemInstance = items[ck]
			if inst2.is_double_arrow():
				g.has_double_arrow = true
		g.edge_count = cell_keys.size() - 1   # 树状结构，边数 = 节点数 - 1
		groups.append(g)

	return groups


# ============================================================
#  连通判定
# ============================================================
static func _linked_vertical(a_dir: int, b_dir: int) -> bool:
	# A 有 DOWN 或 VERTICAL 且 B 有 UP 或 VERTICAL
	var a_down : bool = (a_dir == Direction.Value.DOWN or a_dir == Direction.Value.VERTICAL)
	var b_up : bool = (b_dir == Direction.Value.UP or b_dir == Direction.Value.VERTICAL)
	return a_down and b_up


static func _linked_horizontal(a_dir: int, b_dir: int) -> bool:
	# A 有 RIGHT 或 HORIZONTAL 且 B 有 LEFT 或 HORIZONTAL
	var a_right : bool = (a_dir == Direction.Value.RIGHT or a_dir == Direction.Value.HORIZONTAL)
	var b_left : bool = (b_dir == Direction.Value.LEFT or b_dir == Direction.Value.HORIZONTAL)
	return a_right and b_left


static func _linked_diag_ur(a_dir: int, b_dir: int) -> bool:
	# A 的 DIAG_NE_SW (⤢) → B 的 DIAG_NW_SE (⤡)（A 在左，B 在右上方）
	return a_dir == Direction.Value.DIAG_NE_SW and b_dir == Direction.Value.DIAG_NW_SE


static func _linked_diag_dr(a_dir: int, b_dir: int) -> bool:
	# A 的 DIAG_NW_SE (⤡) → B 的 DIAG_NE_SW (⤢)（A 在左，B 在右下方）
	return a_dir == Direction.Value.DIAG_NW_SE and b_dir == Direction.Value.DIAG_NE_SW


# ============================================================
#  并查集
# ============================================================
static func _find(parent: Dictionary, k: String) -> String:
	if parent[k] == k: return k
	parent[k] = _find(parent, parent[k])
	return parent[k]


static func _union(parent: Dictionary, a: String, b: String):
	var ra : String = _find(parent, a)
	var rb : String = _find(parent, b)
	if ra != rb:
		parent[ra] = rb


# ============================================================
#  ★ 评分：连通组 → buff 数值
# ============================================================
## 返回：{ attack_pct, defense_pct, hp_pct, total_groups, cross_3_groups }
static func evaluate_groups(groups: Array) -> Dictionary:
	var result : Dictionary = {
		"attack_pct": 0.0,
		"defense_pct": 0.0,
		"hp_pct": 0.0,
		"total_groups": groups.size(),
		"cross_3_groups": 0,
	}

	if groups.is_empty():
		return result

	var total_attack : float = 0.0
	var total_defense : float = 0.0
	var total_hp : float = 0.0

	for g in groups:
		if g.size() < 2: continue
		var base_a : float = _group_attack_value(g.size())
		var base_d : float = _group_defense_value(g.size())
		var base_h : float = _group_hp_value(g.size())

		# 跨单位倍率
		var cross_mult : float = 1.0
		match g.unit_count():
			2: cross_mult = 1.3
			3: cross_mult = 2.0
			4: cross_mult = 2.5
		if g.unit_count() >= 3 and g.has_double_arrow:
			cross_mult = 2.5

		total_attack += base_a * cross_mult
		total_defense += base_d * cross_mult
		total_hp += base_h * cross_mult

		if g.unit_count() >= 3:
			result["cross_3_groups"] += 1

	# 多组倍率
	var multi_mult : float = 1.0
	match groups.size():
		2: multi_mult = 1.25
		3, 4, 5, 6, 7, 8: multi_mult = 1.5
		_: multi_mult = 1.0

	# 总倍率封顶 2.5（跨三+双箭头已封顶）
	var final_attack : float = total_attack * multi_mult
	var final_defense : float = total_defense * multi_mult
	var final_hp : float = total_hp * multi_mult

	# 属性封顶 +30%
	result["attack_pct"] = minf(final_attack, 30.0) / 100.0
	result["defense_pct"] = minf(final_defense, 30.0) / 100.0
	result["hp_pct"] = minf(final_hp, 30.0) / 100.0
	return result


static func _group_attack_value(n: int) -> float:
	if n == 2: return 2.0
	if n == 3: return 5.0
	if n == 4: return 8.0
	if n == 5: return 12.0
	return 15.0

static func _group_defense_value(n: int) -> float:
	if n == 2: return 1.0
	if n == 3: return 3.0
	if n == 4: return 5.0
	if n == 5: return 8.0
	return 10.0

static func _group_hp_value(n: int) -> float:
	if n == 2: return 1.0
	if n == 3: return 3.0
	if n == 4: return 5.0
	if n == 5: return 8.0
	return 10.0
