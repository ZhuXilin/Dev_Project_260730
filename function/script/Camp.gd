extends CanvasLayer

@onready var soul_label = $ResourcePanel/SoulLabel

func _ready():
	update_display()
	_play_camp_music()

func _play_camp_music():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	else:
		pass

func update_display():
	soul_label.text = str(GameState.soul + GameState.temp_soul)
	
func _on_deploy_pressed():
	if GameState.cached_map_level_data != null and not GameState.party.is_empty():
		Globals.show_confirm(
			self,
			"当前有未完成的冒险，确定重新开始吗？",
			"重新开始",
			"取消",
			_confirm_deploy,
			func(): pass,
			true
		)
		return
	_confirm_deploy()

func _confirm_deploy():
	GameState.reset_all()
	GameState.start_new_cycle()
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")

func _on_unit_pressed():
	var existing = get_node_or_null("UnitInfoUI")
	if existing:
		existing.visible = !existing.visible
		if existing.visible:
			existing.populate_list()
		return
	var panel_scene = load("res://content/scenes/ui/UnitInfoUI.tscn")
	if panel_scene:
		var panel = panel_scene.instantiate()
		add_child(panel)
		panel.name = "UnitInfoUI"
		panel.populate_list()

func _on_item_pressed():
	var existing = get_node_or_null("ItemInfoUI")
	if existing:
		existing.visible = !existing.visible
		if existing.visible:
			existing._refresh_list()
		return
	var panel_scene = load("res://content/scenes/ui/ItemInfoUI.tscn")
	if panel_scene:
		var panel = panel_scene.instantiate()
		add_child(panel)
		panel.name = "ItemInfoUI"

func _on_back_pressed():
	GameState.interrupt_state = 1
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")
