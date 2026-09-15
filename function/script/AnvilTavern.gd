extends CanvasLayer

signal closed

enum Tab { RECIPE, CODEX, STORY }
var current_tab : Tab = Tab.RECIPE

var _current_npc : Dictionary = {}
var _story_npc_list : VBoxContainer = null
var _story_topic_list : VBoxContainer = null

@onready var materials_label : Label = $Panel/VBox/TitleBar/MaterialsLabel
@onready var recipe_tab_btn : Button = $Panel/VBox/TabBar/RecipeTabBtn
@onready var codex_tab_btn : Button = $Panel/VBox/TabBar/CodexTabBtn
@onready var story_tab_btn : Button = $Panel/VBox/TabBar/StoryTabBtn
@onready var content_container : VBoxContainer = $Panel/VBox/ContentScroll/ContentContainer

func _ready():
	recipe_tab_btn.text = "工坊"
	codex_tab_btn.text  = "武备库"
	story_tab_btn.text  = "酒馆"

	MusicManager.play_anvil_tavern_music()   # ← 新增

	_refresh_materials()
	_switch_tab(Tab.RECIPE)

# ============================================================
#  信号
# ============================================================
func _on_recipe_tab_pressed(): _switch_tab(Tab.RECIPE)
func _on_codex_tab_pressed():  _switch_tab(Tab.CODEX)
func _on_story_tab_pressed():  _switch_tab(Tab.STORY)

func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()
	
# ============================================================
#  Tab 切换
# ============================================================
func _switch_tab(tab: Tab):
	current_tab = tab
	_update_tab_style()
	_clear_content()
	_story_npc_list = null
	_story_topic_list = null
	_current_npc = {}

	match tab:
		Tab.RECIPE: _build_recipe_tab()
		Tab.CODEX:  _build_codex_tab()
		Tab.STORY:  _build_story_tab()


func _update_tab_style():
	recipe_tab_btn.modulate = Color.WHITE if current_tab == Tab.RECIPE else Color(0.5, 0.5, 0.5)
	codex_tab_btn.modulate  = Color.WHITE if current_tab == Tab.CODEX  else Color(0.5, 0.5, 0.5)
	story_tab_btn.modulate  = Color.WHITE if current_tab == Tab.STORY  else Color(0.5, 0.5, 0.5)


func _clear_content():
	for child in content_container.get_children():
		content_container.remove_child(child)
		child.queue_free()


func _refresh_materials():
	var mats = GameState.get_all_materials()
	var parts = []
	for mat_name in ["粗铁", "精钢", "秘银", "龙鳞"]:
		var count = mats.get(mat_name, 0)
		if count > 0:
			parts.append("%s:%d" % [mat_name, count])
	materials_label.text = "材料: " + (" ".join(parts) if not parts.is_empty() else "无")


# ============================================================
#  Tab 1: 工坊（配方解锁）
# ============================================================
func _build_recipe_tab():
	var all_recipes = RecipeManager.get_all_recipes()
	if all_recipes.is_empty():
		content_container.add_child(_make_hint("暂无配方数据"))
		return

	var locked : Array = []
	var done : Array = []
	for r in all_recipes:
		if r.id in GameState.unlocked_recipes:
			done.append(r)
		else:
			locked.append(r)

	for r in locked:
		content_container.add_child(_build_recipe_row(r, false))
	for r in done:
		content_container.add_child(_build_recipe_row(r, true))


func _build_recipe_row(recipe: RecipeData, unlocked: bool) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var output_data = ItemManager.get_item_data(recipe.id)
	var name_label = Label.new()
	name_label.text = output_data.name if output_data else recipe.id
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
	if output_data:
		var color = UIConst.QUALITY_COLORS.get(output_data.quality, Color.WHITE)
		name_label.add_theme_color_override("font_color", color)
	header.add_child(name_label)

	var quality_label = Label.new()
	quality_label.text = "[" + _quality_display(output_data.quality if output_data else "common") + "]"
	quality_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	header.add_child(quality_label)

	box.add_child(header)

	var input_names = []
	for input_id in recipe.inputs:
		var d = ItemManager.get_item_data(input_id)
		input_names.append(d.name if d else input_id)
	var input_label = Label.new()
	input_label.text = "  合成: " + " + ".join(input_names)
	input_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	box.add_child(input_label)

	var cost_row = HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 8)

	var cost_label = Label.new()
	cost_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if unlocked:
		cost_label.text = "  已解锁"
		cost_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		var parts = []
		for k in recipe.unlock_cost:
			var need = recipe.unlock_cost[k]
			var have = GameState.get_material(k)
			parts.append("%s×%d(%d)" % [k, need, have])
		cost_label.text = "  解锁: " + " ".join(parts)
	cost_row.add_child(cost_label)

	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	if unlocked:
		btn.text = "已解锁"
		btn.disabled = true
	else:
		btn.text = "解锁"
		btn.disabled = not _can_unlock(recipe)
		btn.pressed.connect(_on_unlock_pressed.bind(recipe.id))
	cost_row.add_child(btn)

	box.add_child(cost_row)
	return box


func _quality_display(quality: String) -> String:
	match quality:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return quality


func _can_unlock(recipe: RecipeData) -> bool:
	for mat_name in recipe.unlock_cost:
		if GameState.get_material(mat_name) < recipe.unlock_cost[mat_name]:
			return false
	return true


func _on_unlock_pressed(recipe_id: String):
	var recipe = RecipeManager.get_recipe(recipe_id)
	if not recipe:
		return
	if not _can_unlock(recipe):
		_show_message("材料不足")
		return
	for mat_name in recipe.unlock_cost:
		GameState.materials[mat_name] -= recipe.unlock_cost[mat_name]
	GameState.unlocked_recipes.append(recipe_id)
	SaveManager.auto_save()
	_show_message("已解锁：" + recipe_id)
	_refresh_materials()
	_switch_tab(Tab.RECIPE)


# ============================================================
#  Tab 2: 武备库（图鉴）
# ============================================================
func _build_codex_tab():
	var scene = load(Config.PATHS.ITEM_INFO_UI)
	if not scene:
		content_container.add_child(_make_hint("图鉴面板未找到"))
		return
	var item_info = scene.instantiate()

	item_info.anchor_left = 0
	item_info.anchor_top = 0
	item_info.anchor_right = 0
	item_info.anchor_bottom = 0
	item_info.offset_left = 0
	item_info.offset_top = 0
	item_info.offset_right = 0
	item_info.offset_bottom = 0

	item_info.custom_minimum_size = Vector2(0, 320)
	item_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_info.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var back_btn = item_info.get_node_or_null("VBoxContainer/BackButton")
	if back_btn:
		back_btn.visible = false

	content_container.add_child(item_info)


# ============================================================
#  Tab 3: 酒馆（NPC 对话）
# ============================================================
func _build_story_tab():
	var npcs = StoryManager.get_npcs()
	if npcs.is_empty():
		content_container.add_child(_make_hint("暂无酒馆数据"))
		return

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(hbox)

	# ---- 左：NPC 列表 ----
	_story_npc_list = VBoxContainer.new()
	_story_npc_list.custom_minimum_size = Vector2(80, 0)
	_story_npc_list.add_theme_constant_override("separation", 2)
	hbox.add_child(_story_npc_list)

	# ---- 右：话题列表 ----
	_story_topic_list = VBoxContainer.new()
	_story_topic_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_topic_list.add_theme_constant_override("separation", 2)
	hbox.add_child(_story_topic_list)

	# ---- 填充 NPC 按钮 ----
	for npc in npcs:
		var btn = Button.new()
		btn.text = npc["name"]
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.pressed.connect(_on_npc_selected.bind(npc))
		_story_npc_list.add_child(btn)

	# ---- 默认选中第一个 ----
	_on_npc_selected(npcs[0])


func _on_npc_selected(npc: Dictionary):
	_current_npc = npc
	_refresh_topic_list()


func _refresh_topic_list():
	if not _story_topic_list or not is_instance_valid(_story_topic_list):
		return
	for child in _story_topic_list.get_children():
		_story_topic_list.remove_child(child)
		child.queue_free()

	var topics = _current_npc.get("topics", [])
	var any_visible = false
	for topic in topics:
		if not StoryManager.check_condition(topic.get("condition", "")):
			continue
		any_visible = true

		var seen = topic["id"] in GameState.unlocked_stories
		var btn = Button.new()
		btn.text = topic["title"] + ("（已阅）" if seen else "")
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if seen:
			btn.modulate = Color(0.6, 0.6, 0.6)
		btn.pressed.connect(_on_topic_pressed.bind(topic))
		_story_topic_list.add_child(btn)

	if not any_visible:
		var hint = _make_hint("（暂无可聊话题）")
		_story_topic_list.add_child(hint)

func _on_topic_pressed(topic: Dictionary):
	var lines = topic.get("lines", [])
	if lines.is_empty():
		_show_message("该话题暂无内容")
		return

	# ---- 标记 seen ----
	if topic["id"] not in GameState.unlocked_stories:
		GameState.unlocked_stories.append(topic["id"])
		SaveManager.auto_save()

	# ---- 播放内联对话 ----
	DialogueManager.start_inline_dialogue(lines)
	await DialogueManager.dialogue_finished

	# ---- 刷新话题列表 ----
	_refresh_topic_list()

# ============================================================
#  辅助
# ============================================================
func _make_hint(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(0.6, 0.6, 0.6)
	return label

func _show_message(msg: String):
	var label = Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_container.add_child(label)
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(label):
		label.queue_free()
