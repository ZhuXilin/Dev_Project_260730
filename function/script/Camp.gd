extends CanvasLayer

# ============================================================
#  节点引用
# ============================================================
@onready var soul_label = $ResourcePanel/SoulLabel
@onready var materials_container = $ResourcePanel/MaterialsContainer

# ---- 按钮引用 ----
@onready var deploy_btn : Button = $ButtonPanel/DeployButton
@onready var unit_btn : Button = $ButtonPanel/UnitButton
@onready var item_btn : Button = $ButtonPanel/ItemButton
@onready var arena_btn : Button = $ButtonPanel/ArenaButton
@onready var back_btn : Button = $ButtonPanel/BackButton


# ============================================================
#  生命周期
# ============================================================
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_transitioning = false

	# ---- 按钮文本（全部在代码里设置，不在 .tscn 里硬编码） ----
	if deploy_btn:
		deploy_btn.text = "出战"
	if unit_btn:
		unit_btn.text = "魂铸圣所"
	if item_btn:
		item_btn.text = "铁砧酒馆"
	if arena_btn:
		arena_btn.text = "魂之竞技场"
	if back_btn:
		back_btn.text = "返回"

	# ---- 信号连接（不依赖 .tscn 的 [connection]） ----
	_connect_buttons()

	update_display()
	_play_camp_music()


func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		# 调试：+50 魂
		if event.keycode == KEY_6:
			GameState.soul += 50
			SaveManager.auto_save()
			update_display()
			print("调试：+50 魂，当前 ", GameState.soul)
			get_viewport().set_input_as_handled()

# ============================================================
#  信号连接
# ============================================================
func _connect_buttons():
	# 先断开已有连接，防止重复
	for btn in [deploy_btn, unit_btn, item_btn, arena_btn, back_btn]:
		if not btn:
			continue
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)

	# 重新连接
	if deploy_btn:
		deploy_btn.pressed.connect(_on_deploy_pressed)
	if unit_btn:
		unit_btn.pressed.connect(_on_unit_pressed)
	if item_btn:
		item_btn.pressed.connect(_on_item_pressed)
	if arena_btn:
		arena_btn.pressed.connect(_on_arena_pressed)
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)


# ============================================================
#  音乐
# ============================================================
func _play_camp_music():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)


# ============================================================
#  显示刷新
# ============================================================
func update_display():
	soul_label.text = "魂:" + str(EconomyManager.get_soul() + EconomyManager.get_temp_soul())
	_update_materials_display()


func _update_materials_display():
	for child in materials_container.get_children():
		child.queue_free()

	var materials = GameState.get_all_materials()
	var has_material = false

	for material_name in materials:
		var count = materials[material_name]
		if count > 0:
			has_material = true
			var label = Label.new()
			label.text = material_name + ":" + str(count)
			label.add_theme_font_size_override("font_size", 8)
			var color = _get_material_color(material_name)
			if color:
				label.add_theme_color_override("font_color", color)
			materials_container.add_child(label)

	if not has_material:
		var label = Label.new()
		label.text = "无材料"
		label.add_theme_font_size_override("font_size", 8)
		label.modulate = Color(0.5, 0.5, 0.5)
		materials_container.add_child(label)


func _get_material_color(material_name: String) -> Color:
	match material_name:
		"粗铁": return Color(0.7, 0.6, 0.5)
		"精钢": return Color(0.5, 0.7, 0.8)
		"秘银": return Color(0.3, 0.8, 0.7)
		"龙鳞": return Color(0.8, 0.6, 0.1)
		_: return Color.WHITE


# ============================================================
#  按钮回调
# ============================================================
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


# ---- 魂铸圣所入口 ----
func _on_unit_pressed():
	var existing = get_node_or_null("SoulAltar")
	if existing:
		return
	var scene = load(Config.PATHS.SOUL_ALTAR_UI)
	if not scene:
		push_error("SoulAltar 场景未找到: " + Config.PATHS.SOUL_ALTAR_UI)
		return
	var altar = scene.instantiate()
	altar.name = "SoulAltar"
	add_child(altar)
	await altar.closed
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	update_display()

# ---- 铁砧酒馆入口 ----
func _on_item_pressed():
	var existing = get_node_or_null("AnvilTavern")
	if existing:
		return
	var scene = load(Config.PATHS.ANVIL_TAVERN_UI)
	if not scene:
		push_error("AnvilTavern 场景未找到: " + Config.PATHS.ANVIL_TAVERN_UI)
		return
	var tavern = scene.instantiate()
	tavern.name = "AnvilTavern"
	add_child(tavern)
	await tavern.closed
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	update_display()


# ---- 斗技场入口 ----
func _on_arena_pressed():
	var existing = get_node_or_null("Arena")
	if existing:
		return
	var scene = load(Config.PATHS.ARENA_UI)
	if not scene:
		push_error("Arena 场景未找到: " + Config.PATHS.ARENA_UI)
		return
	var arena = scene.instantiate()
	arena.name = "Arena"
	add_child(arena)
	await arena.closed

	# ---- 切回营地音乐 ----
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)

	update_display()

# ---- 返回主菜单 ----
func _on_back_pressed():
	GameState.interrupt_state = GameState.InterruptState.CAMP
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")
