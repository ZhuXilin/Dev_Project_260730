extends CanvasLayer

@onready var soul_label : Label = $ResourcePanel/SoulLabel
@onready var soul_fire_label : Label = $ResourcePanel/SoulFireLabel
@onready var fire_sprite : TextureRect = $FireSprite

@onready var entrance_gate : TextureButton = $EntranceGate
@onready var soul_keeper_btn : TextureButton = $NpcGrid/SoulKeeperBtn
@onready var blacksmith_btn : TextureButton = $NpcGrid/BlacksmithBtn
@onready var guide_btn : TextureButton = $NpcGrid/GuideBtn
@onready var gladiator_btn : TextureButton = $NpcGrid/GladiatorBtn
@onready var back_btn : Button = $BackButton


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_transitioning = false

	_connect_buttons()
	_load_art()
	update_display()
	_play_camp_music()

	DispatchManager.rotate_routes()


func _connect_buttons():
	var pairs = [
		[entrance_gate, _on_deploy_pressed],
		[soul_keeper_btn, _on_soul_keeper_pressed],
		[blacksmith_btn, _on_blacksmith_pressed],
		[guide_btn, _on_guide_pressed],
		[gladiator_btn, _on_gladiator_pressed],
		[back_btn, _on_back_pressed],
	]
	for pair in pairs:
		var btn = pair[0]
		var cb = pair[1]
		if not btn: continue
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)
		btn.pressed.connect(cb)


func _load_art():
	var bg_path = "res://content/images/sanctuary/bg.png"
	if ResourceLoader.exists(bg_path):
		var tex = load(bg_path)
		if tex and $Background is TextureRect:
			$Background.texture = tex

	var fire_path = "res://content/images/sanctuary/fire.png"
	if fire_sprite and ResourceLoader.exists(fire_path):
		fire_sprite.texture = load(fire_path)

	var npc_arts = {
		"soul_keeper": [soul_keeper_btn, "res://content/images/sanctuary/npc_soul_keeper.png"],
		"blacksmith": [blacksmith_btn, "res://content/images/sanctuary/npc_blacksmith.png"],
		"guide": [guide_btn, "res://content/images/sanctuary/npc_guide.png"],
		"gladiator": [gladiator_btn, "res://content/images/sanctuary/npc_gladiator.png"],
	}
	for key in npc_arts:
		var btn = npc_arts[key][0]
		var path = npc_arts[key][1]
		if btn and ResourceLoader.exists(path):
			btn.texture_normal = load(path)

	var gate_path = "res://content/images/sanctuary/gate.png"
	if entrance_gate and ResourceLoader.exists(gate_path):
		entrance_gate.texture_normal = load(gate_path)


func update_display():
	if soul_label:
		soul_label.text = "魂: %d" % GameState.soul
	if soul_fire_label:
		soul_fire_label.text = "魂火: %d / %d" % [
			SoulFireManager.current, SoulFireManager.get_max_carried()
		]


func _play_camp_music():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)


func _restore_camp_music():
	_play_camp_music()


# ============================================================
#  NPC 入口
# ============================================================
func _on_deploy_pressed():
	if GameState.cached_map_level_data != null and not GameState.party.is_empty():
		Globals.show_confirm(self, "当前有未完成的冒险，确定重新开始吗？",
			"重新开始", "取消", _confirm_deploy, func(): pass, true)
		return
	_confirm_deploy()


func _confirm_deploy():
	GameState.reset_all()
	GameState.start_new_cycle()
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")


func _on_soul_keeper_pressed():
	await _npc_intro("soul_keeper")
	if not is_inside_tree(): return
	_open_facility(Config.PATHS.SOUL_ALTAR_UI, "SoulAltar")


func _on_blacksmith_pressed():
	await _npc_intro("blacksmith")
	if not is_inside_tree(): return
	var scene = load(Config.PATHS.ANVIL_TAVERN_UI)
	if not scene: return
	if get_node_or_null("AnvilTavern"): return
	var tavern = scene.instantiate()
	tavern.name = "AnvilTavern"
	tavern.setup(0)
	add_child(tavern)
	await tavern.closed
	if not is_inside_tree(): return
	_restore_camp_music()
	update_display()


func _on_guide_pressed():
	await _npc_intro("guide")
	if not is_inside_tree(): return
	_open_facility("res://content/scenes/ui/DispatchUI.tscn", "DispatchUI")


func _on_gladiator_pressed():
	await _npc_intro("gladiator")
	if not is_inside_tree(): return
	_open_facility(Config.PATHS.ARENA_UI, "Arena")


func _open_facility(path: String, node_name: String):
	if get_node_or_null(node_name): return
	if not ResourceLoader.exists(path):
		push_warning("[Camp] 设施未找到: " + path)
		return
	var scene = load(path)
	var inst = scene.instantiate()
	inst.name = node_name
	add_child(inst)
	await inst.closed
	if not is_inside_tree(): return
	_restore_camp_music()
	update_display()


# ============================================================
#  NPC 对话触发
# ============================================================
func _npc_intro(npc_id: String):
	var played : bool = StoryManager.play_next_dialogue(npc_id)
	if not played:
		return
	# 有选项 → 等玩家选
	if DialogueManager.has_pending_choices():
		var result = await DialogueManager.choice_selected
		if result is Array and result.size() == 2:
			var data : Dictionary = result[1]
			var flag : String = data.get("flag", "")
			if flag != "":
				StoryManager.record_choice(npc_id, flag)
	await DialogueManager.dialogue_finished

	# 检查解锁
	var newly = StoryManager.check_and_apply_unlocks(npc_id)
	if newly.size() > 0:
		for u in newly:
			_show_unlock_toast(u.get("type", ""), u.get("id", ""))


func _show_unlock_toast(utype: String, uid: String):
	var msg : String = ""
	match utype:
		"unit":
			msg = "★ 新残魂加入：%s" % UnitDataManager.get_unit_type_display_name(uid)
		"relic":
			var rd = RelicManager.get_relic_data(uid)
			msg = "★ 新遗物：%s" % rd.get("name", uid)
		"aura":
			msg = "★ 新光环：%s" % uid
		"transform_branch":
			msg = "★ 隐藏质变分支解锁"
	if msg == "": return
	print("[Camp] " + msg)


# ============================================================
#  离开
# ============================================================
func _on_back_pressed():
	GameState.interrupt_state = GameState.InterruptState.CAMP
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")
