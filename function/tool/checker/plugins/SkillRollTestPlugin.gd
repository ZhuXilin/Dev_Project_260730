extends TestPlugin

## 技能轮盘测试：直接拉起 SkillRollUI，验证开始/停止、单位头像落位、三行滚动效果。
## ★ 不做阻塞式 await：启动后立即返回，GM 面板恢复显示，1 键可随时再次开关。

var _ui = null


func get_key() -> String: return "skill_roll"
func get_category() -> String: return "轮盘测试"
func get_display_name() -> String: return "技能轮盘 roll"


func build_params(container: VBoxContainer, on_ready: Callable):
	container.add_child(_make_label("启动后直接打开开局技能轮盘（3 个单位）。", 7))
	container.add_child(_make_label("点右侧按钮开始/停止，停下后点头像落位。", 6))
	container.add_child(_make_label("启动后按 1 键可随时隐藏 / 再次唤出 GM 面板。", 6))
	on_ready.call()


func on_deactivate():
	_close_ui()


func _close_ui():
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


func _on_ui_finished():
	# UI 自身也会 queue_free，这里只清引用，保证可重复启动
	_ui = null


func launch():
	_close_ui()
	# GM 面板 layer=200 会盖住轮盘 layer=30，启动后保持隐藏；按 1 键仍可随时唤出
	set_keep_hidden(true)
	var harness := _get_harness()
	if harness:
		harness.visible = false
	# 测试用队伍：清空技能槽，确保 roll 池可用
	if GameState.party.is_empty():
		for key in ["swordsman", "archer", "axeman"]:
			GameState.party.append(UnitDataManager.create_unit_data(key))
	var names: Array = []
	for ud in GameState.party:
		if ud == null:
			continue
		BuildManager.reset_unit_build(ud)
		names.append(ud.unit_name)
	if names.size() < 3:
		while names.size() < 3:
			var key: String = str(["swordsman", "archer", "axeman"][names.size()])
			var ud := UnitDataManager.create_unit_data(key)
			BuildManager.reset_unit_build(ud)
			GameState.party.append(ud)
			names.append(key)

	_ui = load(Config.PATHS.SKILL_ROLL_UI).instantiate()
	# ★ v6.57：SkillRollUI 已合入 ArmorRollUI——先标记技能模式，再进树
	_ui.set_skill_mode()
	_attach_to_root(_ui)
	_ui.skill_finished.connect(_on_ui_finished)
	_ui.setup_skill(names)
	print("[SkillRollTestPlugin] 技能轮盘已启动")
