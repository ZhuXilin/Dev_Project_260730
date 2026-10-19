class_name NonCombatHandler
extends Node

var _bf : Node2D

func _init(bf: Node2D):
	_bf = bf


func setup_non_combat_mode() -> void:
	print("进入非战斗模式：", GameState.current_map_data.map_name if GameState.current_map_data else "未知地图")
	_bf.is_non_combat_mode = true
	Globals.is_non_combat_mode = true

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_bf.cursor.visible = false

	var music_stream = null
	if MusicManager.config and MusicManager.config.non_combat_music:
		music_stream = MusicManager.config.non_combat_music
	elif MusicManager.config and MusicManager.config.map_music:
		music_stream = MusicManager.config.map_music
	if music_stream:
		MusicManager.play_music(music_stream)

	if _bf.setting_panel: _bf.setting_panel.visible = false

	# v4.6：map_enter 事件驱动（有匹配才弹，没有就算了）
	var md : MapData = GameState.current_map_data
	var ctx : Dictionary = {
		"node_type": md.node_type if md != null else -1,
		"current_day": GameState.current_day,
		"map_name": md.map_name if md != null else "",
		"tutorial_stage": GameState.tutorial_stage,
		"total_run_count": GameState.total_run_count,
	}
	if StoryManager.trigger("map_enter", ctx):
		print("[NonCombat] 触发 map_enter 对话")
		await DialogueManager.dialogue_finished
		print("[NonCombat] map_enter 对话结束")

	print("非战斗模式设置完成，回合系统已启动，等待玩家操作")


func on_non_combat_complete() -> void:
	print("非战斗节点完成，显示胜利面板")
	TurnManager.is_game_over = true
	MusicManager._saved_stream = null
	MusicManager._saved_position = 0.0
	_bf._victory_handler.on_request_show_victory(0)
