extends CanvasLayer

@onready var soul_label = $ResourcePanel/SoulLabel
@onready var materials_container = $ResourcePanel/MaterialsContainer
@onready var item_btn : Button = $ButtonPanel/ItemButton

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_transitioning = false

	# ---- 文本设置（本地化预留） ----
	#item_btn.text = tr("ui_anvil_tavern")   # 找不到翻译时 tr() 返回 key 本身
	# 临时方案：还没做翻译文件时，直接用中文：
	item_btn.text = "铁砧酒馆"

	update_display()
	_play_camp_music()

func _play_camp_music():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)

func update_display():
	# ---- 更新魂 ----
	soul_label.text = "魂:" + str(EconomyManager.get_soul() + EconomyManager.get_temp_soul())
	
	# ---- 更新材料 ----
	_update_materials_display()

func _update_materials_display():
	# 清空旧显示
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
			# ---- 添加材料颜色 ----
			var color = _get_material_color(material_name)
			if color:
				label.add_theme_color_override("font_color", color)
			materials_container.add_child(label)
	
	# 如果没有材料，显示提示
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
	get_tree().change_scene_to_file(Config.PATHS.UNIT_SELECT_UI)

func _on_unit_pressed():
	var existing = get_node_or_null("UnitInfoUI")
	if existing:
		existing.visible = !existing.visible
		if existing.visible:
			existing.populate_list()
		return
	var panel_scene = load(Config.PATHS.UNIT_INFO_UI)
	if panel_scene:
		var panel = panel_scene.instantiate()
		add_child(panel)
		panel.name = "UnitInfoUI"
		panel.populate_list()

func _on_item_pressed():
	var existing = get_node_or_null("AnvilTavern")
	if existing:
		return
	var scene = load(Config.PATHS.ANVIL_TAVERN_UI)
	if not scene:
		push_error("AnvilTavern 场景未找到")
		return
	var tavern = scene.instantiate()
	tavern.name = "AnvilTavern"
	add_child(tavern)
	await tavern.closed

func _on_back_pressed():
	GameState.interrupt_state = GameState.InterruptState.CAMP
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file(Config.PATHS.MAIN_MENU)
