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

	if _bf.end_turn_button:
		_bf.end_turn_button.text = "鼠标中键结束回合"
		_bf.end_turn_button.visible = true
		_bf.end_turn_button.modulate = Color.WHITE

	if _bf._battle_start_event_id != "":
		print("检测到非战斗地图事件：", _bf._battle_start_event_id)
		var music = MusicManager.config.battle_start_dialogue_music if MusicManager.config else null
		if EventManager and EventManager.has_event(_bf._battle_start_event_id):
			await EventManager.trigger_event(_bf._battle_start_event_id, null, music)
		else:
			if DialogueManager.has_dialogue(_bf._battle_start_event_id):
				DialogueManager.start_dialogue(_bf._battle_start_event_id, music)
				await DialogueManager.dialogue_finished
			else:
				print("警告：非战斗地图事件/对话不存在: ", _bf._battle_start_event_id)
		print("非战斗地图事件结束")

	print("非战斗模式设置完成，回合系统已启动，等待玩家操作")


func on_non_combat_complete() -> void:
	print("非战斗节点完成，显示胜利面板")
	TurnManager.is_game_over = true
	MusicManager._saved_stream = null
	MusicManager._saved_position = 0.0
	_bf._on_request_show_victory(0)
