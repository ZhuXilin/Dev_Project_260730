extends Node

enum TerrainType {
	PLAIN,
	FOREST,
	MOUNTAIN,
	BUILDING,
	IMPASSABLE,
	IMPASSABLE_ALL   # 新增：完全阻挡，任何单位不可通行
}

const TERRAIN_DATA = {
	TerrainType.PLAIN:    { "move_cost": 1, "physical_reduction": 0.00, "magic_reduction": 0.00, "passable": true },
	TerrainType.FOREST:   { "move_cost": 2, "physical_reduction": 0.10, "magic_reduction": 0.00, "passable": true },
	TerrainType.MOUNTAIN: { "move_cost": 3, "physical_reduction": 0.20, "magic_reduction": 0.00, "passable": false },
	TerrainType.BUILDING: { "move_cost": 1, "physical_reduction": 0.25, "magic_reduction": 0.15, "passable": true },
	TerrainType.IMPASSABLE:{ "move_cost": 0, "physical_reduction": 0.00, "magic_reduction": 0.00, "passable": false },
	TerrainType.IMPASSABLE_ALL:{ "move_cost": 0, "physical_reduction": 0.00, "magic_reduction": 0.00, "passable": false }
}

var terrain_grid : Array = []
var grid_size : Vector2i = Vector2i.ZERO

func load_from_tilemap(tilemap: TileMapLayer, map_size: Vector2i):
	var grid = []
	for y in range(map_size.y):
		var row = []
		for x in range(map_size.x):
			var cell = Vector2i(x, y)
			var tile_data = tilemap.get_cell_tile_data(cell)
			var terrain_type = TerrainType.PLAIN
			if tile_data:
				var custom_type = tile_data.get_custom_data("terrain_type")
				if custom_type != null and custom_type is int:
					terrain_type = custom_type
				else:
					var source_id = tile_data.get_source_id()
					terrain_type = _map_source_id_to_terrain(source_id)
			row.append(terrain_type)
		grid.append(row)
	terrain_grid = grid
	grid_size = map_size

func _map_source_id_to_terrain(source_id: int) -> int:
	match source_id:
		0: return TerrainType.PLAIN
		1: return TerrainType.FOREST
		2: return TerrainType.MOUNTAIN
		3: return TerrainType.BUILDING
		4: return TerrainType.IMPASSABLE
		5: return TerrainType.IMPASSABLE_ALL   # 新增映射
		_: return TerrainType.PLAIN

func get_terrain(cell: Vector2i) -> int:
	if cell.y < 0 or cell.y >= terrain_grid.size() or cell.x < 0 or cell.x >= terrain_grid[cell.y].size():
		return TerrainType.PLAIN
	return terrain_grid[cell.y][cell.x]

# ---- 统一的地形名称函数（非静态，因为单例） ----
func get_terrain_name(type: int) -> String:
	match type:
		TerrainType.PLAIN: return "平地"
		TerrainType.FOREST: return "树林"
		TerrainType.MOUNTAIN: return "山"
		TerrainType.BUILDING: return "建筑"
		TerrainType.IMPASSABLE: return "不可通行"
		TerrainType.IMPASSABLE_ALL: return "墙"
		_: return "未知"
