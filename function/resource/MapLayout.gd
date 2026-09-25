extends Resource
class_name MapLayout

@export var layout_name: String = "默认布局"
@export var day1: MapLayoutDay
@export var day2: MapLayoutDay
@export var day3: MapLayoutDay


func get_day(day: int) -> MapLayoutDay:
	match day:
		1: return day1
		2: return day2
		3: return day3
	return null


func has_day(day: int) -> bool:
	var d : MapLayoutDay = get_day(day)
	return d != null and not d.nodes.is_empty()
