extends CanvasLayer

signal closed

enum Tab { RECIPE, CODEX, STORY }
var current_tab : Tab = Tab.RECIPE

@onready var materials_label : Label = $Panel/VBox/TitleBar/MaterialsLabel
@onready var recipe_tab_btn : Button = $Panel/VBox/TabBar/RecipeTabBtn
@onready var codex_tab_btn : Button = $Panel/VBox/TabBar/CodexTabBtn
@onready var story_tab_btn : Button = $Panel/VBox/TabBar/StoryTabBtn
@onready var content_container : VBoxContainer = $Panel/VBox/ContentScroll/ContentContainer


func _ready():
	_refresh_materials()
	_switch_tab(Tab.RECIPE)


# ============================================================
#  信号
# ============================================================
func _on_recipe_tab_pressed(): _switch_tab(Tab.RECIPE)
func _on_codex_tab_pressed():  _switch_tab(Tab.CODEX)
func _on_story_tab_pressed():  _switch_tab(Tab.STORY)

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
	for name in ["粗铁", "精钢", "秘银", "龙鳞"]:
		var count = mats.get(name, 0)
		if count > 0:
			parts.append("%s:%d" % [name, count])
	materials_label.text = "材料: " + (" ".join(parts) if not parts.is_empty() else "无")


# ============================================================
#  Tab 1: 配方
# ============================================================
func _build_recipe_tab():
	var all_armors = _get_all_armors_with_recipe()
	if all_armors.is_empty():
		content_container.add_child(_make_hint("暂无可用配方"))
		return

	# 未解锁在前，已解锁在后
	var locked : Array = []
	var done : Array = []
	for data in all_armors:
		if data.id in GameState.unlocked_recipes:
			done.append(data)
		else:
			locked.append(data)

	for data in locked:
		content_container.add_child(_build_recipe_row(data, false))
	for data in done:
		content_container.add_child(_build_recipe_row(data, true))


func _get_all_armors_with_recipe() -> Array:
	var result : Array = []
	for item_id in ItemManager._item_db.keys():
		var data = ItemManager.get_item_data(item_id)
		if data and data.type == "armor" and not data.unlock_cost.is_empty():
			result.append(data)
	return result


func _build_recipe_row(data: ItemData, unlocked: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# ---- 名称 ----
	var name_label = Label.new()
	name_label.text = data.name
	name_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# ---- 材料需求 ----
	var cost_label = Label.new()
	cost_label.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	if unlocked:
		cost_label.text = "已解锁"
		cost_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		var parts = []
		for k in data.unlock_cost:
			parts.append("%s×%d" % [k, data.unlock_cost[k]])
		cost_label.text = " ".join(parts)
	row.add_child(cost_label)

	# ---- 按钮 ----
	var btn = Button.new()
	btn.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_SMALL)
	if unlocked:
		btn.text = "已解锁"
		btn.disabled = true
	else:
		btn.text = "解锁"
		btn.disabled = not _can_unlock(data)
		btn.pressed.connect(_on_unlock_pressed.bind(data.id))
	row.add_child(btn)

	return row


func _can_unlock(data: ItemData) -> bool:
	for mat_name in data.unlock_cost:
		var need = data.unlock_cost[mat_name]
		if GameState.get_material(mat_name) < need:
			return false
	return true


func _on_unlock_pressed(item_id: String):
	var data = ItemManager.get_item_data(item_id)
	if not data:
		return
	if not _can_unlock(data):
		_show_message("材料不足")
		return
	# ---- 扣材料 ----
	for mat_name in data.unlock_cost:
		GameState.materials[mat_name] -= data.unlock_cost[mat_name]
	# ---- 加入已解锁 ----
	GameState.unlocked_recipes.append(item_id)
	SaveManager.auto_save()
	_show_message("已解锁：" + data.name)
	_refresh_materials()
	_switch_tab(Tab.RECIPE)


# ============================================================
#  Tab 2: 图鉴（骨架）
# ============================================================
func _build_codex_tab():
	# ---- 实例化 ItemInfoUI，挂到 ContentContainer 里 ----
	var item_info_scene = load(Config.PATHS.ITEM_INFO_UI)
	if not item_info_scene:
		content_container.add_child(_make_hint("图鉴面板未找到"))
		return
	var item_info = item_info_scene.instantiate()
	# ItemInfoUI 是 PanelContainer，anchor 全屏会冲突，改为填充容器
	item_info.anchor_right = 0
	item_info.anchor_bottom = 0
	item_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(item_info)
	# 调它的 _refresh_list()
	if item_info.has_method("_refresh_list"):
		item_info._refresh_list()

# ============================================================
#  Tab 3: 故事（骨架）
# ============================================================
func _build_story_tab():
	content_container.add_child(_make_hint("故事功能开发中"))


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
