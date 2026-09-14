extends CanvasLayer

signal closed

enum Tab { RECIPE, CODEX }
var current_tab : Tab = Tab.RECIPE

@onready var materials_label : Label = $Panel/VBox/TitleBar/MaterialsLabel
@onready var recipe_tab_btn : Button = $Panel/VBox/TabBar/RecipeTabBtn
@onready var codex_tab_btn : Button = $Panel/VBox/TabBar/CodexTabBtn
@onready var content_container : VBoxContainer = $Panel/VBox/ContentScroll/ContentContainer


func _ready():
	_refresh_materials()
	_switch_tab(Tab.RECIPE)


# ============================================================
#  信号
# ============================================================
func _on_recipe_tab_pressed(): _switch_tab(Tab.RECIPE)
func _on_codex_tab_pressed():  _switch_tab(Tab.CODEX)

func _on_back_pressed():
	closed.emit()
	queue_free()


# ============================================================
#  Tab 切换
# ============================================================
func _switch_tab(tab: Tab):
	current_tab = tab
	_update_tab_style()
	_clear_content()
	match tab:
		Tab.RECIPE: _build_recipe_tab()
		Tab.CODEX:  _build_codex_tab()


func _update_tab_style():
	recipe_tab_btn.modulate = Color.WHITE if current_tab == Tab.RECIPE else Color(0.5, 0.5, 0.5)
	codex_tab_btn.modulate  = Color.WHITE if current_tab == Tab.CODEX  else Color(0.5, 0.5, 0.5)


func _clear_content():
	for child in content_container.get_children():
		content_container.remove_child(child)
		child.queue_free()


func _refresh_materials():
	var mats = GameState.get_all_materials()
	var parts = []
	for name in ["粗铁", "精钢", "秘银", "龙鳞"]:
		var count = mats.get(name, 0)
		if count > 0:
			parts.append("%s:%d" % [name, count])
	materials_label.text = "材料: " + (" ".join(parts) if not parts.is_empty() else "无")


# ============================================================
#  Tab 1: 配方
# ============================================================
func _build_recipe_tab():
	var all_recipes = RecipeManager.get_all_recipes()
	if all_recipes.is_empty():
		content_container.add_child(_make_hint("暂无配方数据"))
		return

	# 未解锁在前，已解锁在后
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

	# ---- 第一行：产物名称 + 品质 ----
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

	# ---- 第二行：合成输入 ----
	var input_names = []
	for input_id in recipe.inputs:
		var d = ItemManager.get_item_data(input_id)
		input_names.append(d.name if d else input_id)
	var input_label = Label.new()
	input_label.text = "  合成: " + " + ".join(input_names)
	input_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	box.add_child(input_label)

	# ---- 第三行：解锁材料 + 按钮 ----
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
	# ---- 扣材料 ----
	for mat_name in recipe.unlock_cost:
		GameState.materials[mat_name] -= recipe.unlock_cost[mat_name]
	# ---- 加入已解锁 ----
	GameState.unlocked_recipes.append(recipe_id)
	SaveManager.auto_save()
	_show_message("已解锁：" + recipe_id)
	_refresh_materials()
	_switch_tab(Tab.RECIPE)


# ============================================================
#  Tab 2: 图鉴（嵌入 ItemInfoUI）
# ============================================================
func _build_codex_tab():
	var scene = load(Config.PATHS.ITEM_INFO_UI)
	if not scene:
		content_container.add_child(_make_hint("图鉴面板未找到"))
		return
	var item_info = scene.instantiate()
	# 重置 anchors，避免与容器冲突
	item_info.anchor_right = 0
	item_info.anchor_bottom = 0
	item_info.custom_minimum_size = Vector2(0, 320)
	item_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(item_info)
	if item_info.has_method("_refresh_list"):
		item_info._refresh_list()


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
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(label):
		label.queue_free()
