extends Node

# ============================================================
#  测试插件注册表
# ============================================================

var _plugins : Array = []
var _ready_done : bool = false


func _ready():
	if _ready_done:
		return
	_ready_done = true
	_register_all()


func _register_all():
	var plugin_scripts : Array = [
		preload("res://function/tool/Checker/plugins/NodeTestPlugin.gd"),
		preload("res://function/tool/Checker/plugins/RewardSummaryTestPlugin.gd"),
		preload("res://function/tool/Checker/plugins/DialogueTestPlugin.gd"),
		preload("res://function/tool/Checker/plugins/HeroShrineTestPlugin.gd"),
		preload("res://function/tool/Checker/plugins/ChipMusicTestPlugin.gd"),
	]
	for s in plugin_scripts:
		var p = s.new()
		_plugins.append(p)
	print("[TestRegistry] 已注册 %d 个测试插件" % _plugins.size())


func get_all() -> Array:
	return _plugins.duplicate()


## 按分类分组：{ category: [plugins] }
func get_by_category() -> Dictionary:
	var result : Dictionary = {}
	for p in _plugins:
		var cat : String = p.get_category()
		if not result.has(cat):
			result[cat] = []
		result[cat].append(p)
	return result
