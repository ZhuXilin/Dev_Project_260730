extends TestPlugin

## 防具轮盘测试：直接拉起 ArmorRollUI，验证开始/停止、8 件候选防具与头像落位。
## ★ 不做阻塞式 await：启动后立即返回，GM 面板恢复显示，1 键可随时再次开关。

var _ui = null


func get_key() -> String: return "armor_roll"
func get_category() -> String: return "轮盘测试"
func get_display_name() -> String: return "防具轮盘 roll"


func build_params(container: VBoxContainer, on_ready: Callable):
	container.add_child(_make_label("启动后直接打开战后防具轮盘，并补足测试金币。", 7))
	container.add_child(_make_label("点右侧按钮开始/停止，停下后点头像选择落位单位。", 6))
	container.add_child(_make_label("启动后按 1 键可随时隐藏 / 再次唤出 GM 面板。", 6))
	on_ready.call()


func on_deactivate():
	_close_ui()


func _close_ui():
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


func _on_ui_closed():
	_ui = null


func launch():
	_close_ui()
	if GameState.party.is_empty():
		for key in ["swordsman", "archer", "axeman"]:
			var ud := UnitDataManager.create_unit_data(key)
			BuildManager.reset_unit_build(ud)
			GameState.party.append(ud)
	EconomyManager.add_temp_gold(2000)

	_ui = load(Config.PATHS.ARMOR_ROLL_UI).instantiate()
	_attach_to_root(_ui)
	_ui.closed.connect(_on_ui_closed)
	print("[ArmorRollTestPlugin] 防具轮盘已启动")
