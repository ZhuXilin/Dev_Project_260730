class_name AnvilTavern
extends CanvasLayer

signal closed

enum Tab { ARSENAL, ALCHEMY, TAVERN }

# ★ 入口参数（普通 var，不走 @export）
var _entry_tab : int = 0

# ★ 由 Camp 在 add_child 前调用
func setup(tab: int) -> void:
	_entry_tab = tab

enum ArsenalSub { WEAPON, ARMOR }
var _arsenal_sub : ArsenalSub = ArsenalSub.WEAPON

enum AlchemySub { RECIPE, REFINE }
var _alchemy_sub : AlchemySub = AlchemySub.RECIPE

# ★ 新增：酒馆子页
enum TavernSub { STORY, RELIC }
var _tavern_sub : TavernSub = TavernSub.STORY

var current_tab : Tab = Tab.ARSENAL

var _current_npc : Dictionary = {}
var _story_npc_list : VBoxContainer = null
var _story_topic_list : VBoxContainer = null

# 次级标签栏（固定，不随滑块滚动）
var _sub_tab_bar : HBoxContainer = null

# ★ 场景节点引用
@onready var title_label : Label = $Panel/VBox/TitleBar/TitleLabel
@onready var materials_label : Label = $Panel/VBox/TitleBar/MaterialsLabel
@onready var top_tab_bar : HBoxContainer = $Panel/VBox/TabBar
@onready var recipe_tab_btn : Button = $Panel/VBox/TabBar/RecipeTabBtn
@onready var codex_tab_btn : Button = $Panel/VBox/TabBar/CodexTabBtn
@onready var story_tab_btn : Button = $Panel/VBox/TabBar/StoryTabBtn
@onready var content_container : VBoxContainer = $Panel/VBox/ContentScroll/ContentContainer


func _ready():
	print("[AnvilTavern] _ready, _entry_tab =", _entry_tab)

	if top_tab_bar:
		top_tab_bar.visible = false

	_ensure_sub_tab_bar()
	MusicManager.play_anvil_tavern_music()

	var entry_tab : Tab = _entry_tab as Tab
	match entry_tab:
		Tab.ARSENAL:
			if title_label: title_label.text = "武器作坊"
		Tab.ALCHEMY:
			if title_label: title_label.text = "炼金坊"
		Tab.TAVERN:
			if title_label: title_label.text = "酒馆"

	_refresh_materials()
	_switch_tab(entry_tab)


# ============================================================
#  次级标签栏（固定）
# ============================================================
func _ensure_sub_tab_bar():
	if _sub_tab_bar and is_instance_valid(_sub_tab_bar):
		return
	_sub_tab_bar = HBoxContainer.new()
	_sub_tab_bar.name = "SubTabBar"
	_sub_tab_bar.add_theme_constant_override("separation", 4)
	var vbox : VBoxContainer = $Panel/VBox
	vbox.add_child(_sub_tab_bar)
	vbox.move_child(_sub_tab_bar, top_tab_bar.get_index() + 1)


func _clear_sub_tab_bar():
	if not _sub_tab_bar or not is_instance_valid(_sub_tab_bar):
		return
	for child in _sub_tab_bar.get_children():
		_sub_tab_bar.remove_child(child)
		child.queue_free()


# ============================================================
#  Tab 切换
# ============================================================
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
	_clear_sub_tab_bar()
	_story_npc_list = null
	_story_topic_list = null
	_current_npc = {}

	match tab:
		Tab.ARSENAL: _build_arsenal_tab()
		Tab.ALCHEMY: _build_alchemy_tab()
		Tab.TAVERN:  _build_story_tab()


func _update_tab_style():
	if not recipe_tab_btn: return
	recipe_tab_btn.modulate = Color.WHITE if current_tab == Tab.ARSENAL else Color(0.5, 0.5, 0.5, 1)
	codex_tab_btn.modulate  = Color.WHITE if current_tab == Tab.ALCHEMY else Color(0.5, 0.5, 0.5, 1)
	story_tab_btn.modulate  = Color.WHITE if current_tab == Tab.TAVERN  else Color(0.5, 0.5, 0.5, 1)


func _clear_content():
	for child in content_container.get_children():
		content_container.remove_child(child)
		child.queue_free()


func _refresh_materials():
	var mats : Dictionary = GameState.get_all_materials()
	var parts : Array = []
	for mat_name in ["粗铁", "精钢", "秘银", "龙鳞"]:
		var count : int = mats.get(mat_name, 0)
		if count > 0:
			parts.append("%s:%d" % [mat_name, count])
	materials_label.text = "材料: " + (" ".join(parts) if not parts.is_empty() else "无")


# ============================================================
#  Tab 1 · 武器作坊（武器 / 防具）
# ============================================================
func _build_arsenal_tab():
	var weapon_btn = Button.new()
	weapon_btn.text = "武器"
	weapon_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	weapon_btn.pressed.connect(_on_arsenal_sub.bind(ArsenalSub.WEAPON))
	weapon_btn.modulate = Color.WHITE if _arsenal_sub == ArsenalSub.WEAPON else Color(0.5, 0.5, 0.5, 1)
	_sub_tab_bar.add_child(weapon_btn)

	var armor_btn = Button.new()
	armor_btn.text = "防具"
	armor_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	armor_btn.pressed.connect(_on_arsenal_sub.bind(ArsenalSub.ARMOR))
	armor_btn.modulate = Color.WHITE if _arsenal_sub == ArsenalSub.ARMOR else Color(0.5, 0.5, 0.5, 1)
	_sub_tab_bar.add_child(armor_btn)

	match _arsenal_sub:
		ArsenalSub.WEAPON: _build_arsenal_list("weapon")
		ArsenalSub.ARMOR:  _build_arsenal_list("armor")


func _on_arsenal_sub(sub: ArsenalSub):
	_arsenal_sub = sub
	_switch_tab(Tab.ARSENAL)


func _build_arsenal_list(item_type: String):
	var unlocked_list : Array = []
	var locked_list : Array = []

	for item_id in ItemManager._item_db.keys():
		var data : ItemData = ItemManager.get_item_data(item_id)
		if not data or data.type != item_type:
			continue
		var is_unlocked : bool = _is_item_unlocked(item_id, item_type)
		if is_unlocked:
			unlocked_list.append(item_id)
		else:
			locked_list.append(item_id)

	# ---- 排序：价格（越便宜越靠前），同价按 id 字母序 ----
	unlocked_list.sort_custom(_sort_by_price)
	locked_list.sort_custom(_sort_by_price)

	# ---- 已解锁分组 ----
	if unlocked_list.size() > 0:
		content_container.add_child(_make_section_title("— 已解锁 —"))
		for item_id in unlocked_list:
			content_container.add_child(_build_arsenal_row(item_id, true))

	# ---- 未解锁分组 ----
	if locked_list.size() > 0:
		if unlocked_list.size() > 0:
			content_container.add_child(_make_separator())
		content_container.add_child(_make_section_title("— 未解锁 —"))
		for item_id in locked_list:
			content_container.add_child(_build_arsenal_row(item_id, false))


func _sort_by_price(a: String, b: String) -> bool:
	var da : ItemData = ItemManager.get_item_data(a)
	var db : ItemData = ItemManager.get_item_data(b)
	if not da or not db:
		return a < b
	if da.price != db.price:
		return da.price < db.price
	return a < b


func _make_section_title(text: String) -> Label:
	var lb = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	lb.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lb


func _make_separator() -> HSeparator:
	var sep = HSeparator.new()
	sep.modulate = Color(0.4, 0.4, 0.4, 1)
	return sep


func _is_item_unlocked(item_id: String, _item_type: String) -> bool:
	return Globals.is_item_unlocked(item_id)


func _build_arsenal_row(item_id: String, unlocked: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var data : ItemData = ItemManager.get_item_data(item_id)

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

	var quality_label = Label.new()
	quality_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	quality_label.custom_minimum_size = Vector2(50, 0)
	quality_label.text = "[" + _quality_display(data.quality) + "]"
	if not unlocked:
		quality_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(quality_label)

	var cost_label = Label.new()
	cost_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not unlocked:
		var unlock_cost : Dictionary = _get_unlock_cost(item_id)
		var parts : Array = []
		for k in unlock_cost:
			parts.append("%s×%d(%d)" % [k, unlock_cost[k], GameState.get_material(k)])
		cost_label.text = " ".join(parts)
	row.add_child(cost_label)

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
	var data : ItemData = ItemManager.get_item_data(item_id)
	if data and not data.unlock_cost.is_empty():
		return data.unlock_cost
	var recipe : RecipeData = RecipeManager.get_recipe(item_id)
	if recipe and not recipe.unlock_cost.is_empty():
		return recipe.unlock_cost
	# 兜底：普通武器/防具无解锁成本（已经默认解锁，不该走到这）
	return { "粗铁": 3 }


func _can_unlock_item(item_id: String) -> bool:
	var cost : Dictionary = _get_unlock_cost(item_id)
	for mat in cost:
		if GameState.get_material(mat) < cost[mat]:
			return false
	return true


func _on_unlock_item(item_id: String):
	var cost : Dictionary = _get_unlock_cost(item_id)
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
#  Tab 2 · 炼金坊（合成配方 / 精炼）
# ============================================================
func _build_alchemy_tab():
	var recipe_btn = Button.new()
	recipe_btn.text = "合成配方"
	recipe_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	recipe_btn.pressed.connect(_on_alchemy_sub.bind(AlchemySub.RECIPE))
	recipe_btn.modulate = Color.WHITE if _alchemy_sub == AlchemySub.RECIPE else Color(0.5, 0.5, 0.5, 1)
	_sub_tab_bar.add_child(recipe_btn)

	var refine_btn = Button.new()
	refine_btn.text = "精炼"
	refine_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	refine_btn.pressed.connect(_on_alchemy_sub.bind(AlchemySub.REFINE))
	refine_btn.modulate = Color.WHITE if _alchemy_sub == AlchemySub.REFINE else Color(0.5, 0.5, 0.5, 1)
	_sub_tab_bar.add_child(refine_btn)

	match _alchemy_sub:
		AlchemySub.RECIPE: _build_recipe_list()
		AlchemySub.REFINE: _build_refine_list()


func _on_alchemy_sub(sub: AlchemySub):
	_alchemy_sub = sub
	_switch_tab(Tab.ALCHEMY)


# ---- 合成配方 ----
func _build_recipe_list():
	var all_recipes : Array = RecipeManager.get_all_recipes()
	if all_recipes.is_empty():
		content_container.add_child(_make_hint("（暂无合成配方）"))
		return

	var unlocked_list : Array = []
	var locked_list : Array = []
	for recipe in all_recipes:
		if recipe.id in GameState.unlocked_recipes:
			unlocked_list.append(recipe)
		else:
			locked_list.append(recipe)

	unlocked_list.sort_custom(_sort_recipe_by_cost)
	locked_list.sort_custom(_sort_recipe_by_cost)

	if unlocked_list.size() > 0:
		content_container.add_child(_make_section_title("— 已解锁 —"))
		for recipe in unlocked_list:
			content_container.add_child(_build_recipe_row(recipe, true))

	if locked_list.size() > 0:
		if unlocked_list.size() > 0:
			content_container.add_child(_make_separator())
		content_container.add_child(_make_section_title("— 未解锁 —"))
		for recipe in locked_list:
			content_container.add_child(_build_recipe_row(recipe, false))


func _sort_recipe_by_cost(a: RecipeData, b: RecipeData) -> bool:
	var ca : int = 0
	for v in a.unlock_cost.values():
		ca += int(v)
	var cb : int = 0
	for v in b.unlock_cost.values():
		cb += int(v)
	if ca != cb:
		return ca < cb
	return a.id < b.id


func _build_recipe_row(recipe: RecipeData, unlocked: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var out_data : ItemData = ItemManager.get_item_data(recipe.id)
	var out_name : String = out_data.name if out_data else recipe.id

	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_LARGE)
	name_label.custom_minimum_size = Vector2(70, 0)
	name_label.clip_text = true
	name_label.text = out_name
	if unlocked:
		var q : String = out_data.quality if out_data else "common"
		name_label.add_theme_color_override("font_color",
			UIConst.QUALITY_COLORS.get(q, Color.WHITE))
	else:
		name_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(name_label)

	var input_label = Label.new()
	input_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	input_label.custom_minimum_size = Vector2(110, 0)
	input_label.clip_text = true
	var input_names : Array = []
	for iid in recipe.inputs:
		var d : ItemData = ItemManager.get_item_data(iid)
		input_names.append(d.name if d else iid)
	input_label.text = " + ".join(input_names)
	if not unlocked:
		input_label.modulate = Color(0.4, 0.4, 0.4, 1)
	row.add_child(input_label)

	var cost_label = Label.new()
	cost_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not unlocked:
		var parts : Array = []
		for k in recipe.unlock_cost:
			parts.append("%s×%d(%d)" % [k, recipe.unlock_cost[k], GameState.get_material(k)])
		cost_label.text = " ".join(parts)
	row.add_child(cost_label)

	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	btn.custom_minimum_size = Vector2(60, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unlocked:
		btn.text = "已解锁"
		btn.disabled = true
	else:
		btn.text = "解锁"
		btn.disabled = not _can_unlock_recipe(recipe)
		btn.pressed.connect(_on_unlock_recipe.bind(recipe.id))
	row.add_child(btn)

	return row


func _can_unlock_recipe(recipe: RecipeData) -> bool:
	for mat in recipe.unlock_cost:
		if GameState.get_material(mat) < recipe.unlock_cost[mat]:
			return false
	return true


func _on_unlock_recipe(recipe_id: String):
	var recipe : RecipeData = RecipeManager.get_recipe(recipe_id)
	if not recipe: return
	if recipe_id in GameState.unlocked_recipes: return

	for mat in recipe.unlock_cost:
		GameState.materials[mat] -= recipe.unlock_cost[mat]
	GameState.unlocked_recipes.append(recipe_id)
	Globals.unlock_item(recipe_id)

	SaveManager.auto_save()
	_refresh_materials()
	_switch_tab(Tab.ALCHEMY)


# ---- 精炼 ----
func _build_refine_list():
	var all_ids : Array = RefineManager.get_all_ids()
	var unlocked_list : Array = []
	var locked_list : Array = []
	for refine_id in all_ids:
		if RefineManager.is_recipe_unlocked(refine_id):
			unlocked_list.append(refine_id)
		else:
			locked_list.append(refine_id)

	unlocked_list.sort_custom(_sort_refine_by_cost)
	locked_list.sort_custom(_sort_refine_by_cost)

	if unlocked_list.size() > 0:
		content_container.add_child(_make_section_title("— 已解锁 —"))
		for refine_id in unlocked_list:
			content_container.add_child(_build_refine_row(refine_id, true))

	if locked_list.size() > 0:
		if unlocked_list.size() > 0:
			content_container.add_child(_make_separator())
		content_container.add_child(_make_section_title("— 未解锁 —"))
		for refine_id in locked_list:
			content_container.add_child(_build_refine_row(refine_id, false))


func _sort_refine_by_cost(a: String, b: String) -> bool:
	var ra : Dictionary = RefineManager.get_recipe(a)
	var rb : Dictionary = RefineManager.get_recipe(b)
	var ca : int = 0
	for v in ra.get("unlock_cost", {}).values():
		ca += int(v)
	var cb : int = 0
	for v in rb.get("unlock_cost", {}).values():
		cb += int(v)
	if ca != cb:
		return ca < cb
	return a < b


func _build_refine_row(refine_id: String, unlocked: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var recipe : Dictionary = RefineManager.get_recipe(refine_id)

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
		var cost : Dictionary = recipe.get("craft_cost", {})
		var parts : Array = []
		for k in cost:
			parts.append("%s×%d(%d)" % [k, cost[k], GameState.get_material(k)])
		cost_label.text = " ".join(parts)
	else:
		var unlock_cost : Dictionary = recipe.get("unlock_cost", {})
		var parts : Array = []
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


# ============================================================
#  Tab 3 · 酒馆（话题 / 遗物图鉴）
# ============================================================
func _build_story_tab():
	# ---- 次级标签：酒馆话题 / 遗物图鉴 ----
	var story_btn = Button.new()
	story_btn.text = "酒馆话题"
	story_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	story_btn.pressed.connect(_on_tavern_sub.bind(TavernSub.STORY))
	story_btn.modulate = Color.WHITE if _tavern_sub == TavernSub.STORY else Color(0.5, 0.5, 0.5, 1)
	_sub_tab_bar.add_child(story_btn)

	var relic_btn = Button.new()
	relic_btn.text = "遗物图鉴"
	relic_btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	relic_btn.pressed.connect(_on_tavern_sub.bind(TavernSub.RELIC))
	relic_btn.modulate = Color.WHITE if _tavern_sub == TavernSub.RELIC else Color(0.5, 0.5, 0.5, 1)
	_sub_tab_bar.add_child(relic_btn)

	match _tavern_sub:
		TavernSub.STORY: _build_story_topic_list()
		TavernSub.RELIC: _build_relic_list()


func _on_tavern_sub(sub: TavernSub):
	_tavern_sub = sub
	_switch_tab(Tab.TAVERN)


# ---- 酒馆话题（原 _build_story_tab 内容） ----
func _build_story_topic_list():
	var npcs : Array = StoryManager.get_npcs()
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

	var topics : Array = _current_npc.get("topics", [])
	var any_visible : bool = false
	for topic in topics:
		if not StoryManager.check_condition(topic.get("condition", "")):
			continue
		any_visible = true

		var seen : bool = topic["id"] in GameState.unlocked_stories
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
	var lines : Array = topic.get("lines", [])
	if lines.is_empty():
		_show_message("该话题暂无内容")
		return

	if topic["id"] not in GameState.unlocked_stories:
		GameState.unlocked_stories.append(topic["id"])
		SaveManager.auto_save()

	DialogueManager.start_inline_dialogue(lines)
	await DialogueManager.dialogue_finished
	_refresh_topic_list()


# ---- 遗物图鉴 ----
func _build_relic_list():
	var all_ids : Array = RelicManager.get_all_relic_ids()
	if all_ids.is_empty():
		content_container.add_child(_make_hint("（暂无遗物数据）"))
		return

	for relic_id in all_ids:
		var data : Dictionary = RelicManager.get_relic_data(relic_id)
		if data.is_empty():
			continue
		var is_unlocked : bool = RelicManager.is_relic_unlocked(relic_id)
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
#  Debug：按 7 加材料
# ============================================================
const DEBUG_MAT_AMOUNT : int = 10
const DEBUG_MATERIALS : Array = ["粗铁", "精钢", "秘银", "龙鳞"]

func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_7:
		return
	if DialogueManager.is_active:
		return
	_debug_add_materials()
	get_viewport().set_input_as_handled()


func _debug_add_materials():
	for mat_name in DEBUG_MATERIALS:
		GameState.materials[mat_name] = GameState.materials.get(mat_name, 0) + DEBUG_MAT_AMOUNT
	SaveManager.auto_save()
	_refresh_materials()
	print("[DEBUG] 材料 +%d（每种）" % DEBUG_MAT_AMOUNT)
