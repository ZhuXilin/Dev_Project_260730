class_name TestPlugin
extends RefCounted

# ============================================================
#  状态
# ============================================================
var _keep_hidden_after_launch : bool = false

# ============================================================
#  接口（子类覆写）
# ============================================================
func get_key() -> String: return ""
func get_category() -> String: return "未分类"
func get_display_name() -> String: return get_key()

## 构建参数控件
func build_params(_container: VBoxContainer, _on_ready: Callable) -> void:
	pass

## 启动（不要加 -> void，否则无法被 await）
func launch():
	pass

## 前置检查
func validate() -> String:
	return ""

# ============================================================
#  keep_hidden 控制
# ============================================================
func reset_keep_hidden():
	_keep_hidden_after_launch = false

func set_keep_hidden(v: bool):
	_keep_hidden_after_launch = v

func should_keep_hidden() -> bool:
	return _keep_hidden_after_launch


# ============================================================
#  SceneTree / Autoload 访问（RefCounted 无 get_tree()）
# ============================================================
func _get_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _attach_to_root(node: Node) -> void:
	var tree := _get_tree()
	if tree:
		tree.root.add_child(node)
	else:
		push_error("[TestPlugin] 无法获取 SceneTree")


func _change_scene(path: String) -> void:
	var tree := _get_tree()
	if tree:
		tree.change_scene_to_file(path)


## 拿到 TestHarness autoload（用于控制它的显隐）
func _get_harness() -> Node:
	var tree := _get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TestHarness")


# ============================================================
#  UI 工具
# ============================================================
func _make_label(text: String, font_size: int = 8) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", font_size)
	return lb


func _make_button(text: String, font_size: int = 8) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	return btn


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## 状态文本（显示在 TestHarness 底部 InfoBar 右侧）
## 子类覆写，返回 "" 表示无状态
func get_status_text() -> String:
	return ""

## 状态变化时调用，通知 TestHarness 刷新
func _notify_status_changed():
	var harness := _get_harness()
	if harness and harness.has_method("_refresh_status_text"):
		harness._refresh_status_text()
