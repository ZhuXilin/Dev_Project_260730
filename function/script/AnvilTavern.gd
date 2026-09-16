extends CanvasLayer

signal closed

enum Tab { ARSENAL, ALCHEMY, TAVERN }
var current_tab : Tab = Tab.ARSENAL

enum ArsenalSub { WEAPON, ARMOR }
var _arsenal_sub : ArsenalSub = ArsenalSub.WEAPON

enum AlchemySub { REFINE, RELIC }
var _alchemy_sub : AlchemySub = AlchemySub.REFINE

var _current_npc : Dictionary = {}
var _story_npc_list : VBoxContainer = null
var _story_topic_list : VBoxContainer = null

@onready var materials_label : Label = $Panel/VBox/TitleBar/MaterialsLabel
@onready var recipe_tab_btn : Button = $Panel/VBox/TabBar/RecipeTabBtn
@onready var codex_tab_btn : Button = $Panel/VBox/TabBar/CodexTabBtn
@onready var story_tab_btn : Button = $Panel/VBox/TabBar/StoryTabBtn
@onready var content_container : VBoxContainer = $Panel/VBox/ContentScroll/ContentContainer


func _ready():
	recipe_tab_btn.text = "武备库"
	codex_tab_btn.text = "炼金坊"
	story_tab_btn.text = "酒馆"

	MusicManager.play_anvil_tavern_music()

	_refresh_materials()
	_switch_tab(Tab.ARSENAL)


func _on_recipe_tab_pressed(): _switch_tab(Tab.ARSENAL)
func _on_codex_tab_pressed():  _switch_tab(Tab.ALCHEMY)
func _on_story_tab_pressed():  _switch_tab(Tab.TAVERN)

func _on_back_pressed():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)
	closed.emit()
	queue_free()


func _switch_tab(tab: Tab):
	current_tab = tab
	_update_tab_style()
	_clear_content()
	_story_npc_list = null
	_story_topic_list = null
	_current_npc = {}

	match tab:
		Tab.ARSENAL: _build_arsenal_tab()
		Tab.ALCHEMY: _build_alchemy_tab()
		Tab.TAVERN:  _build_story_tab()


func _update_tab_style():
	recipe_tab_btn.modulate = Color.WHITE if current_tab == Tab.ARSENAL else Color(0.5, 0.5, 0.5, 1)
	codex_tab_btn.modulate  = Color.WHITE if current_tab == Tab.ALCHEMY else Color(0.5, 0.5, 0.5, 1)
	story_tab_btn.modulate  = Color.WHITE if current_tab == Tab.TAVERN  else Color(0.5, 0.5, 0.5, 1)


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
#  Tab 1 · 武备库
# ============================================================
func _build_arsenal_tab():
	var sub_bar = HBoxContainer.new()
	sub_bar.add_theme_constant_override("separation", 4)
	content_container.add_child(sub_bar)

	var weapon_btn = Button.new()
	weapon_btn.text = "武器"
	weapon_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	weapon_btn.pressed.connect(_on_arsenal_sub.bind(ArsenalSub.WEAPON))
	weapon_btn.modulate = Color.WHITE if _arsenal_sub == ArsenalSub.WEAPON else Color(0.5, 0.5, 0.5, 1)
	sub_bar.add_child(weapon_btn)

	var armor_btn = Button.new()
	armor_btn.text = "防具"
	armor_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	armor_btn.pressed.connect(_on_arsenal_sub.bind(ArsenalSub.ARMOR))
	armor_btn.modulate = Color.WHITE if _arsenal_sub == ArsenalSub.ARMOR else Color(0.5, 0.5, 0.5, 1)
	sub_bar.add_child(armor_btn)

	var item_type = "weapon" if _arsenal_sub == ArsenalSub.WEAPON else "armor"
	_build_arsenal_list(item_type)


func _on_arsenal_sub(sub: ArsenalSub):
	_arsenal_sub = sub
	_switch_tab(Tab.ARSENAL)


func _build_arsenal_list(item_type: String):
	var unlocked_list : Array = []
	var locked_list : Array = []

	for item_id in ItemManager._item_db.keys():
		var data = ItemManager.get_item_data(item_id)
		if not data or data.type != item_type:
			continue
		var is_unlocked = _is_item_unlocked(item_id, item_type)
		if is_unlocked:
			unlocked_list.append(item_id)
		else:
			locked_list.append(item_id)

	for item_id in unlocked_list:
		content_container.add_child(_build_arsenal_row(item_id, true))
	for item_id in locked_list:
		content_container.add_child(_build_arsenal_row(item_id, false))


func _is_item_unlocked(item_id: String, item_type: String) -> bool:
	if item_type == "weapon":
		return Globals.is_item_unlocked(item_id)
	# 防具：解锁配方 = 解锁商店
	return item_id in GameState.unlocked_recipes


func _build_arsenal_row(item_id: String, unlocked: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var data = ItemManager.get_item_data(item_id)

	# ---- 名称（未解锁也显示真名，灰色） ----
	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
	name_label.custom_minimum_size = Vector2(90, 0)
	name_label.clip_text = true
	name_label.text = data.name
	if unlocked:
		name_label.add_theme_color_override("font_color",
			UIConst.QUALITY_COLORS.get(data.quality, Color.WHITE))
	else:
		name_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(name_label)

	# ---- 品质 ----
	var quality_label = Label.new()
	quality_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	quality_label.custom_minimum_size = Vector2(50, 0)
	quality_label.text = "[" + _quality_display(data.quality) + "]"
	if not unlocked:
		quality_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(quality_label)

	# ---- 解锁条件 ----
	var cost_label = Label.new()
	cost_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not unlocked:
		var unlock_cost = _get_unlock_cost(item_id)
		var parts = []
		for k in unlock_cost:
			parts.append("%s×%d(%d)" % [k, unlock_cost[k], GameState.get_material(k)])
		cost_label.text = " ".join(parts)
	row.add_child(cost_label)

	# ---- 按钮 ----
	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(60, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unlocked:
		btn.text = "已解锁"
		btn.disabled = true
	else:
		btn.text = "解锁"
		btn.disabled = not _can_unlock_item(item_id)
		btn.pressed.connect(_on_unlock_item.bind(item_id))
	row.add_child(btn)

	return row


func _get_unlock_cost(item_id: String) -> Dictionary:
	var data = ItemManager.get_item_data(item_id)
	if data and not data.unlock_cost.is_empty():
		return data.unlock_cost
	return { "粗铁": 3 }


func _can_unlock_item(item_id: String) -> bool:
	var cost = _get_unlock_cost(item_id)
	for mat in cost:
		if GameState.get_material(mat) < cost[mat]:
			return false
	return true


func _on_unlock_item(item_id: String):
	var cost = _get_unlock_cost(item_id)
	for mat in cost:
		GameState.materials[mat] -= cost[mat]

	Globals.unlock_item(item_id)
	if item_id not in GameState.unlocked_recipes:
		GameState.unlocked_recipes.append(item_id)

	SaveManager.auto_save()
	_refresh_materials()
	_switch_tab(Tab.ARSENAL)


func _quality_display(quality: String) -> String:
	match quality:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return quality


# ============================================================
#  Tab 2 · 炼金坊
# ============================================================
func _build_alchemy_tab():
	var sub_bar = HBoxContainer.new()
	sub_bar.add_theme_constant_override("separation", 4)
	content_container.add_child(sub_bar)

	var refine_btn = Button.new()
	refine_btn.text = "精炼"
	refine_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	refine_btn.pressed.connect(_on_alchemy_sub.bind(AlchemySub.REFINE))
	refine_btn.modulate = Color.WHITE if _alchemy_sub == AlchemySub.REFINE else Color(0.5, 0.5, 0.5, 1)
	sub_bar.add_child(refine_btn)

	var relic_btn = Button.new()
	relic_btn.text = "遗物图鉴"
	relic_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	relic_btn.pressed.connect(_on_alchemy_sub.bind(AlchemySub.RELIC))
	relic_btn.modulate = Color.WHITE if _alchemy_sub == AlchemySub.RELIC else Color(0.5, 0.5, 0.5, 1)
	sub_bar.add_child(relic_btn)

	if _alchemy_sub == AlchemySub.REFINE:
		_build_refine_list()
	else:
		_build_relic_list()


func _on_alchemy_sub(sub: AlchemySub):
	_alchemy_sub = sub
	_switch_tab(Tab.ALCHEMY)


func _build_refine_list():
	var all_ids = RefineManager.get_all_ids()
	var unlocked_list : Array = []
	var locked_list : Array = []
	for refine_id in all_ids:
		if RefineManager.is_recipe_unlocked(refine_id):
			unlocked_list.append(refine_id)
		else:
			locked_list.append(refine_id)

	for refine_id in unlocked_list:
		content_container.add_child(_build_refine_row(refine_id, true))
	for refine_id in locked_list:
		content_container.add_child(_build_refine_row(refine_id, false))


func _build_refine_row(refine_id: String, unlocked: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var recipe = RefineManager.get_recipe(refine_id)

	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
	name_label.custom_minimum_size = Vector2(90, 0)
	name_label.clip_text = true
	name_label.text = recipe.get("name", refine_id)
	if not unlocked:
		name_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(name_label)

	var stock_label = Label.new()
	stock_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	stock_label.custom_minimum_size = Vector2(50, 0)
	if unlocked:
		stock_label.text = "×%d" % RefineManager.get_count(refine_id)
	else:
		stock_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(stock_label)

	var cost_label = Label.new()
	cost_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if unlocked:
		var cost = recipe.get("craft_cost", {})
		var parts = []
		for k in cost:
			parts.append("%s×%d(%d)" % [k, cost[k], GameState.get_material(k)])
		cost_label.text = " ".join(parts)
	else:
		var unlock_cost = recipe.get("unlock_cost", {})
		var parts = []
		for k in unlock_cost:
			parts.append("%s×%d(%d)" % [k, unlock_cost[k], GameState.get_material(k)])
		cost_label.text = "解锁: " + " ".join(parts)
	row.add_child(cost_label)

	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(60, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unlocked:
		btn.text = "精炼"
		btn.disabled = not RefineManager.can_craft(refine_id)
		btn.pressed.connect(_on_craft_refine.bind(refine_id))
	else:
		btn.text = "解锁"
		btn.disabled = not RefineManager.can_unlock_recipe(refine_id)
		btn.pressed.connect(_on_unlock_refine.bind(refine_id))
	row.add_child(btn)

	return row


func _on_unlock_refine(refine_id: String):
	if RefineManager.unlock_recipe(refine_id):
		_refresh_materials()
		_switch_tab(Tab.ALCHEMY)


func _on_craft_refine(refine_id: String):
	if RefineManager.craft(refine_id):
		_refresh_materials()
		_switch_tab(Tab.ALCHEMY)


func _build_relic_list():
	var all_ids = RelicManager.get_all_relic_ids()
	if all_ids.is_empty():
		content_container.add_child(_make_hint("（暂无遗物数据）"))
		return

	for relic_id in all_ids:
		var data = RelicManager.get_relic_data(relic_id)
		if data.is_empty():
			continue
		var is_unlocked = RelicManager.is_relic_unlocked(relic_id)
		content_container.add_child(_build_relic_row(relic_id, data, is_unlocked))


func _build_relic_row(relic_id: String, data: Dictionary, unlocked: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
	name_label.custom_minimum_size = Vector2(90, 0)
	name_label.text = data.get("name", relic_id)
	if not unlocked:
		name_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(name_label)

	var status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	status_label.custom_minimum_size = Vector2(50, 0)
	status_label.text = "已获得" if unlocked else "未获得"
	status_label.modulate = Color.WHITE if unlocked else Color(0.5, 0.5, 0.5, 1)
	row.add_child(status_label)

	var desc_label = Label.new()
	desc_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	desc_label.text = data.get("description", "")
	if not unlocked:
		desc_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(desc_label)

	return row


# ============================================================
#  Tab 3 · 酒馆
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

	_story_npc_list = VBoxContainer.new()
	_story_npc_list.custom_minimum_size = Vector2(80, 0)
	_story_npc_list.add_theme_constant_override("separation", 2)
	hbox.add_child(_story_npc_list)

	_story_topic_list = VBoxContainer.new()
	_story_topic_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_topic_list.add_theme_constant_override("separation", 2)
	hbox.add_child(_story_topic_list)

	for npc in npcs:
		var btn = Button.new()
		btn.text = npc["name"]
		btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
		btn.pressed.connect(_on_npc_selected.bind(npc))
		_story_npc_list.add_child(btn)

	if npcs.size() > 0:
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
		_story_topic_list.add_child(_make_hint("（暂无可聊话题）"))


func _on_topic_pressed(topic: Dictionary):
	var lines = topic.get("lines", [])
	if lines.is_empty():
		_show_message("该话题暂无内容")
		return

	if topic["id"] not in GameState.unlocked_stories:
		GameState.unlocked_stories.append(topic["id"])
		SaveManager.auto_save()

	DialogueManager.start_inline_dialogue(lines)
	await DialogueManager.dialogue_finished
	_refresh_topic_list()


# ============================================================
#  辅助
# ============================================================
func _make_hint(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(0.6, 0.6, 0.6, 1)
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

# ============================================================
#  Debug：按 7 加材料（每种 +10）
# ============================================================
const DEBUG_MAT_AMOUNT : int = 10
const DEBUG_MATERIALS : Array = ["粗铁", "精钢", "秘银", "龙鳞"]

func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_7:
		return
	# 对话进行中不响应，避免误触
	if DialogueManager.is_active:
		return
	_debug_add_materials()
	get_viewport().set_input_as_handled()


func _debug_add_materials():
	for mat_name in DEBUG_MATERIALS:
		GameState.materials[mat_name] = GameState.materials.get(mat_name, 0) + DEBUG_MAT_AMOUNT
	SaveManager.auto_save()          # 只存一次
	_refresh_materials()             # 刷新顶部材料标签
	print("[DEBUG] 材料 +%d（每种）" % DEBUG_MAT_AMOUNT)
