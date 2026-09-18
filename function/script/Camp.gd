extends CanvasLayer

# ============================================================
#  节点引用
# ============================================================
@onready var soul_label = $ResourcePanel/SoulLabel
@onready var materials_container = $ResourcePanel/MaterialsContainer

# ---- 按钮引用 ----
@onready var deploy_btn : Button = $ButtonPanel/DeployButton
@onready var unit_btn : Button = $ButtonPanel/UnitButton
@onready var weapon_workshop_btn : Button = $ButtonPanel/WeaponWorkshopButton
@onready var alchemy_btn : Button = $ButtonPanel/AlchemyButton
@onready var tavern_btn : Button = $ButtonPanel/TavernButton
@onready var arena_btn : Button = $ButtonPanel/ArenaButton
@onready var back_btn : Button = $ButtonPanel/BackButton


# ============================================================
#  生命周期
# ============================================================
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_transitioning = false

	# ---- 按钮文本（全部在代码里设置） ----
	if deploy_btn: deploy_btn.text = "出战"
	if unit_btn: unit_btn.text = "魂铸圣所"
	if weapon_workshop_btn: weapon_workshop_btn.text = "武器作坊"
	if alchemy_btn: alchemy_btn.text = "炼金坊"
	if tavern_btn: tavern_btn.text = "酒馆"
	if arena_btn: arena_btn.text = "魂之竞技场"
	if back_btn: back_btn.text = "返回"

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
	for btn in [deploy_btn, unit_btn, weapon_workshop_btn, alchemy_btn, tavern_btn, arena_btn, back_btn]:
		if not btn: continue
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)

	if deploy_btn:
		deploy_btn.pressed.connect(_on_deploy_pressed)
	if unit_btn:
		unit_btn.pressed.connect(_on_unit_pressed)
	if weapon_workshop_btn:
		weapon_workshop_btn.pressed.connect(_on_weapon_workshop_pressed)
	if alchemy_btn:
		alchemy_btn.pressed.connect(_on_alchemy_pressed)
	if tavern_btn:
		tavern_btn.pressed.connect(_on_tavern_pressed)
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

	var materials : Dictionary = GameState.get_all_materials()
	var has_material : bool = false

	for material_name in materials:
		var count : int = materials[material_name]
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


# ---- 魂铸圣所 ----
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


# ---- 武器作坊 ----
func _on_weapon_workshop_pressed():
	_open_anvil_tavern(0)   # ARSENAL

# ---- 炼金坊 ----
func _on_alchemy_pressed():
	_open_anvil_tavern(1)   # ALCHEMY

# ---- 酒馆 ----
func _on_tavern_pressed():
	_open_anvil_tavern(2)   # TAVERN


# ---- 通用：打开 AnvilTavern 到指定 tab ----
func _open_anvil_tavern(tab: int):
	var existing = get_node_or_null("AnvilTavern")
	if existing:
		return
	var scene = load(Config.PATHS.ANVIL_TAVERN_UI)
	if not scene:
		push_error("AnvilTavern 场景未找到: " + Config.PATHS.ANVIL_TAVERN_UI)
		return
	var tavern = scene.instantiate()
	tavern.name = "AnvilTavern"
	tavern.setup(tab)   # ★ 用 setup()，不用属性赋值
	add_child(tavern)
	await tavern.closed
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	update_display()


# ---- 魂之竞技场 ----
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
