extends Resource
class_name MapLayout

@export var layout_name: String = "默认布局"
## 每天的变体池（每次进图从变体里随机抽一个）
@export var day1_variants: Array[MapLayoutDay] = []
@export var day2_variants: Array[MapLayoutDay] = []
@export var day3_variants: Array[MapLayoutDay] = []


func get_day(day: int) -> MapLayoutDay:
	var arr : Array = []
	match day:
		1: arr = day1_variants
		2: arr = day2_variants
		3: arr = day3_variants
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]


func has_day(day: int) -> bool:
	var arr : Array = []
	match day:
		1: arr = day1_variants
		2: arr = day2_variants
		3: arr = day3_variants
	return not arr.is_empty()
