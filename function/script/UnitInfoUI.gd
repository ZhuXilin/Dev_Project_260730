extends PanelContainer

@onready var unit_list = $VBoxContainer/HBoxContainer/ScrollContainer/UnitList
@onready var sprite_container = $VBoxContainer/HBoxContainer/InfoPanel/SpriteContainer
@onready var unit_sprite = $VBoxContainer/HBoxContainer/InfoPanel/SpriteContainer/UnitSprite
@onready var detail_label = $VBoxContainer/HBoxContainer/InfoPanel/DetailLabel

func _ready():
	populate_list()

func populate_list():
	for child in unit_list.get_children():
		child.queue_free()

	var unlocked = Globals.get_unlocked_units()
	unlocked.sort()

	for unit_name in unlocked:
		var btn = Button.new()
		btn.text = unit_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_unit_selected.bind(unit_name))
		unit_list.add_child(btn)

func _on_unit_selected(unit_name: String):
	var frames_path = UnitDataManager.get_sprite_frames_path(unit_name)
	if frames_path != "" and ResourceLoader.exists(frames_path):
		var frames = load(frames_path) as SpriteFrames
		if frames:
			unit_sprite.sprite_frames = frames
			unit_sprite.visible = true
			if frames.has_animation("idle"):
				unit_sprite.play("idle")
			else:
				var anims = frames.get_animation_names()
				if anims.size() > 0:
					unit_sprite.play(anims[0])
			unit_sprite.position = Vector2(0, 0)
			
			# 调整容器高度以适应精灵（无额外间距）
			var frame = unit_sprite.sprite_frames.get_frame_texture("idle", 0)
			if frame:
				var sprite_size = frame.get_size()   # 修正：避免与基类冲突
				sprite_container.custom_minimum_size = Vector2(0, sprite_size.y)
			else:
				sprite_container.custom_minimum_size = Vector2.ZERO
		else:
			unit_sprite.visible = false
			sprite_container.custom_minimum_size = Vector2.ZERO
	else:
		unit_sprite.visible = false
		sprite_container.custom_minimum_size = Vector2.ZERO

	# 更新文本
	var unit_data = UnitDataManager.get_unit_data(unit_name)
	var display_name = unit_data.get("display_name", unit_name)
	var faction = unit_data.get("faction", "")
	var desc = unit_data.get("description", "暂无描述")
	var text = "姓名：%s\n" % display_name
	text += "类型：%s\n" % unit_name
	if faction != "":
		text += "阵营：%s\n" % faction
	text += "HP：%d\n" % unit_data.get("max_hp", 0)
	text += "防御：%d\n" % unit_data.get("defense", 0)
	text += "魔防：%d\n" % unit_data.get("magic_defense", 0)
	text += "技能：%d\n" % unit_data.get("skill", 0)
	text += "速度：%d\n" % unit_data.get("speed", 0)
	text += "幸运：%d\n" % unit_data.get("luck", 0)
	text += "移动力：%d\n" % unit_data.get("move_range", 0)
	text += "描述：%s" % desc
	detail_label.text = text

func _on_back_button_pressed():
	queue_free()
