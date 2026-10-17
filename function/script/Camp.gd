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
	_ensure_default_party()
	update_display()
	_play_camp_music()

	DispatchManager.rotate_routes()
	_show_dispatch_results()
	_check_secret_merchant()


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
		if not btn:
			continue
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

	_update_affinity_display()


func _ensure_default_party():
	if not GameState.party.is_empty():
		return
	var defaults : Array = Globals.unlock_config.get("default_unlocked", [])
	if defaults.is_empty():
		push_warning("[Camp] unlock_config.default_unlocked 为空，无法填充默认队伍")
		return
	var take : int = mini(3, defaults.size())
	var selected : Array[String] = []
	for i in range(take):
		var u : Variant = defaults[i]
		if u is String and (u as String) != "":
			selected.append(u)
	if selected.is_empty():
		return
	GameState.initialize_party(selected, 0)
	print("[Camp] 自动填充默认队伍：" + str(selected))


func update_display():
	if soul_label:
		soul_label.text = "魂: %d" % GameState.soul
	if soul_fire_label:
		soul_fire_label.text = "魂火: %d / %d" % [
			SoulFireManager.current, SoulFireManager.get_max_carried()
		]
	_update_affinity_display()


func _show_dispatch_results():
	var results : Array = DispatchManager.consume_pending_results()
	if results.is_empty():
		return

	var lines : Array = []
	for r in results:
		var unit : String = str(r.get("unit_name", "?"))
		var route : String = str(r.get("route_name", r.get("route_id", "?")))
		var soul : int = int(r.get("soul", 0))
		var bonus : int = int(r.get("bonus", 0))
		var line : String = "%s 从「%s」归来：+%d 魂" % [unit, route, soul]
		if bonus > 0:
			line += "（★ 标签匹配 +1）"
		lines.append(line)

	var toast_text : String = "\n".join(lines)
	_show_floating_toast(toast_text)


func _show_floating_toast(text : String):
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 8)
	toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 3)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -140
	toast.offset_right = 140
	toast.offset_top = 40
	toast.offset_bottom = 100
	add_child(toast)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(toast, "modulate:a", 0.0, 0.5).set_delay(3.0)
	tw.tween_callback(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)


func _update_affinity_display():
	var npcs : Array = [
		["soul_keeper", soul_keeper_btn],
		["blacksmith", blacksmith_btn],
		["guide", guide_btn],
		["gladiator", gladiator_btn],
	]
	for pair in npcs:
		var npc_id : String = pair[0]
		var btn : TextureButton = pair[1]
		if not btn:
			continue
		var aff : int = StoryManager.get_affinity(npc_id)
		var plate = btn.get_node_or_null("NamePlate")
		if plate:
			var base_name : String = str(plate.text)
			if base_name == "":
				base_name = npc_id
			var sp : PackedStringArray = base_name.split(" ")
			if sp.size() > 0:
				base_name = sp[0]
			if aff >= 15:
				plate.text = base_name + "  ❤❤❤"
			elif aff >= 10:
				plate.text = base_name + "  ❤❤"
			elif aff >= 5:
				plate.text = base_name + "  ❤"
			else:
				plate.text = base_name


func _play_camp_music():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)


func _restore_camp_music():
	_play_camp_music()


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
	if not is_inside_tree():
		return
	_open_facility(Config.PATHS.SOUL_ALTAR_UI, "SoulAltar")


func _on_blacksmith_pressed():
	await _npc_intro("blacksmith")
	if not is_inside_tree():
		return
	var scene = load(Config.PATHS.ANVIL_TAVERN_UI)
	if not scene:
		return
	if get_node_or_null("AnvilTavern"):
		return
	var tavern = scene.instantiate()
	tavern.name = "AnvilTavern"
	tavern.setup(0)
	add_child(tavern)
	await tavern.closed
	if not is_inside_tree():
		return
	_restore_camp_music()
	update_display()


func _on_guide_pressed():
	await _npc_intro("guide")
	if not is_inside_tree():
		return
	_open_facility("res://content/scenes/ui/DispatchUI.tscn", "DispatchUI")


func _on_gladiator_pressed():
	await _npc_intro("gladiator")
	if not is_inside_tree():
		return
	_open_facility(Config.PATHS.ARENA_UI, "Arena")


func _open_facility(path: String, node_name: String):
	if get_node_or_null(node_name):
		return
	if not ResourceLoader.exists(path):
		push_warning("[Camp] 设施未找到: " + path)
		return
	var scene = load(path)
	var inst = scene.instantiate()
	inst.name = node_name
	add_child(inst)
	await inst.closed
	if not is_inside_tree():
		return
	_restore_camp_music()
	update_display()


func _npc_intro(npc_id: String):
	var played : bool = StoryManager.play_next_dialogue(npc_id)
	if not played:
		return
	if DialogueManager.has_pending_choices():
		var result = await DialogueManager.choice_selected
		if result is Array and result.size() == 2:
			var data : Dictionary = result[1]
			var flag : String = data.get("flag", "")
			if flag != "":
				StoryManager.record_choice(npc_id, flag)
	await DialogueManager.dialogue_finished

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
			msg = "★ 新光环：%s" % AuraManager.get_display_name(uid)
		"transform_branch":
			msg = "★ 隐藏质变分支解锁"
		"route":
			var route : Dictionary = DispatchManager.ROUTES.get(uid, {})
			msg = "★ 新派遣路线：%s" % route.get("name", uid)
		"talent":
			var td = TalentManager.get_talent_data(uid)
			msg = "★ 新词条：%s" % (td.display_name if td else uid)
	if msg == "":
		return
	print("[Camp] " + _log_safe(msg))
	_show_floating_toast(msg)


static func escape_bbcode(text : String) -> String:
	return text.replace("[", "&#91;")


func _log_safe(s : Variant) -> String:
	return str(s).replace("\n", "\\n").replace("\t", "\\t")


func _on_back_pressed():
	GameState.interrupt_state = GameState.InterruptState.CAMP
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")


# ============================================================
#  隐藏商人（死眠商人）
# ============================================================
func _check_secret_merchant():
	if get_node_or_null("SecretMerchantBtn") != null:
		return

	var should_appear := false
	if GameState.total_run_count > 0 and GameState.total_run_count % 3 == 0:
		should_appear = true
	if GameState.soul >= 300:
		should_appear = true

	if not should_appear:
		return

	var btn := TextureButton.new()
	btn.name = "SecretMerchantBtn"
	btn.position = Vector2(200, 80)
	btn.size = Vector2(64, 64)
	btn.custom_minimum_size = Vector2(64, 64)

	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.1, 0.3, 0.8))
	var tex := ImageTexture.create_from_image(img)
	btn.texture_normal = tex

	var label := Label.new()
	label.text = "黑市商人"
	label.position = Vector2(0, -16)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.8, 0.7, 1.0))
	btn.add_child(label)

	btn.pressed.connect(_on_secret_merchant_pressed)
	add_child(btn)


func _on_secret_merchant_pressed():
	var scene = load("res://content/scenes/ui/SecretMerchantUI.tscn")
	if not scene:
		push_warning("[Camp] SecretMerchantUI.tscn 未找到")
		return
	var ui = scene.instantiate()
	add_child(ui)
	await ui.closed
	update_display()
