extends Node
## UIButtonManager — 全局按钮统一统筹（autoload）
##
## 所有游戏内按钮（BaseButton：Button / TextureButton）进入场景树时自动获得：
##   1. 五态统一套用 8bit 按钮 stylebox（仅 Button；TextureButton 无 stylebox）：
##        normal/disabled/focus → 8bit_style_box_button.tres
##        hover                 → 8bit_style_box_button_hover.tres   (提亮)
##        pressed               → 8bit_style_box_button_pressed.tres (压暗)
##      样式参数（颜色 / 边距 / 纹理）全在 .tres 里配置，代码只做「套用资源」，
##      不硬编码任何样式数值——符合「设置交给引擎编辑功能」的项目约定。
##   2. pressed 播放 click 音效（SoundManager.play_select_sound 内短去抖，
##      避免与业务回调里已有的同名调用同一次点击连播两遍）
##
## hover / pressed 反馈由 Godot 按钮原生状态机 + 不同 stylebox 资源实现，
## 不再用 self_modulate——避免与业务代码常用的 modulate 状态色打架。
##
## 分层处理（★ v6.72ap）：
##   - 皮肤：跳过「头像 / 图标按钮」——它们在 UnitDataManager / MapNodeButton 里
##     显式用 StyleBoxEmpty 做透明底（「头像下不垫任何 UI 块」），套皮肤会垫出框。
##   - 音效：所有 BaseButton 都接（含头像图 / 立绘门 / 商店这类纯图按钮），
##     只要它可点击就出声。皮肤归皮肤、音效归音效，两件事分开判断，
##     别用一个排除开关同时管两头（v6.72ao 之前就是被同一个排除开关一起挡掉的）。
##   - 编辑器工具 UI：脚本路径含 /tool/ 的节点及其子树完全不介入（不套皮肤也不播音效）。

const STYLE_NORMAL  : String = "res://content/resource/stylebox/8bit_style_box_button.tres"
const STYLE_HOVER   : String = "res://content/resource/stylebox/8bit_style_box_button_hover.tres"
const STYLE_PRESSED : String = "res://content/resource/stylebox/8bit_style_box_button_pressed.tres"
const STYLE_CARD    : String = "res://content/resource/stylebox/8bit_style_box_card.tres"
const META_DONE : StringName = &"ui_button_manager_done"

var _sb_normal  : StyleBox = null
var _sb_hover   : StyleBox = null
var _sb_pressed : StyleBox = null
var _sb_card    : StyleBox = null

# 待处理按钮队列（WeakRef）：用弱引用入队，避免持有已释放节点的强引用
var _queue : Array = []
var _flush_queued : bool = false


func _ready() -> void:
	_sb_normal  = load(STYLE_NORMAL)
	_sb_hover   = load(STYLE_HOVER)
	_sb_pressed = load(STYLE_PRESSED)
	_sb_card    = load(STYLE_CARD)
	get_tree().node_added.connect(_on_node_added)
	# autoload 可能晚于首批 UI 入树，补扫一次
	call_deferred("_setup_existing")


## 给「代码动态创建」的卡片 / 面板套 8bit 卡片皮肤。
## 用在无法写进 .tscn 的运行时卡片上（如单位卡片、奖励卡片、选择卡片）。
## 样式参数（纹理 / 边距 / 拉伸）全在 .tres 里，代码只做「套用资源」。
func apply_card_style(ctrl : Control) -> void:
	if not is_instance_valid(ctrl):
		return
	if _sb_card == null:
		_sb_card = load(STYLE_CARD)
	if _sb_card == null:
		return
	ctrl.add_theme_stylebox_override("panel", _sb_card)


func _on_node_added(node : Node) -> void:
	if node is BaseButton:
		# 延迟到本帧末尾，确保脚本 _ready / 创建流程里设置的覆盖样式先生效，
		# 再由本管理器统一覆盖成 8bit 按钮版。
		#
		# ★ v6.72al：不能 call_deferred("_setup_button", node) 直接把节点对象传进去。
		#   弹窗关闭 / 卡片重建时按钮常在帧末前就被 queue_free，延迟调用真正执行时
		#   对象已释放，Godot 在「参数类型转换」阶段就报
		#   Cannot convert argument 1 from Object to Object，函数体里的 is_instance_valid 来不及生效。
		#   改用 WeakRef 排队 + 无参延迟回调，取引用时判存活。
		_queue.append(weakref(node))
		if not _flush_queued:
			_flush_queued = true
			call_deferred("_flush_queue")


func _flush_queue() -> void:
	_flush_queued = false
	var list : Array = _queue
	_queue = []
	for w in list:
		if w is WeakRef:
			var b : Variant = w.get_ref()
			# 节点可能已在帧末前被 queue_free —— 这里静默跳过即可
			if b != null and is_instance_valid(b) and b is BaseButton:
				_setup_button(b)


func _setup_existing() -> void:
	_walk_setup(get_tree().root)


func _walk_setup(node : Node) -> void:
	if node is BaseButton:
		_setup_button(node)
	for child in node.get_children():
		_walk_setup(child)


func _setup_button(btn : BaseButton) -> void:
	if not is_instance_valid(btn):
		return
	if btn.has_meta(META_DONE):
		return
	# 编辑器工具 UI 完全不介入（不套皮肤、不接音效）
	if _is_tool_ui(btn):
		return
	btn.set_meta(META_DONE, true)

	# 1) 统一样式：hover/pressed 用各自资源，Godot 原生状态机负责切换反馈。
	#    只处理 Button（TextureButton 没有 stylebox 概念，靠贴图本身出反馈）；
	#    头像 / 图标按钮（显式 StyleBoxEmpty 透明底）跳过——套皮肤会在图片下垫出框。
	if btn is Button and not _is_transparent_button(btn):
		if _sb_normal != null:
			btn.add_theme_stylebox_override("normal", _sb_normal)
			btn.add_theme_stylebox_override("focus", _sb_normal)
			btn.add_theme_stylebox_override("disabled", _sb_normal)
		if _sb_hover != null:
			btn.add_theme_stylebox_override("hover", _sb_hover)
		if _sb_pressed != null:
			btn.add_theme_stylebox_override("pressed", _sb_pressed)

	# 2) 点击音效：所有可点击按钮都接（含头像 / 图标按钮）。
	#    去抖在 SoundManager 内，兼容业务回调里已有的播放调用。
	btn.pressed.connect(_on_button_pressed.bind(weakref(btn)))


## 按钮被点击 → 播放 click 音效。
## 用 WeakRef 绑定，避免把 Node 强引用进信号闭包（与 v6.72al 的延迟队列同理）。
func _on_button_pressed(w : WeakRef) -> void:
	var b : Variant = w.get_ref()
	if b == null or not is_instance_valid(b):
		return
	SoundManager.play_select_sound()


## 头像 / 图标类按钮：normal 态是最简 StyleBoxEmpty（图片下不垫任何 UI 块）。
func _is_transparent_button(btn : Button) -> bool:
	# ★ get_theme_stylebox() 返回的就是包含覆盖在内的实际生效样式，
	#   直接判断它是不是 StyleBoxEmpty 即可——不依赖 has_*_override()
	#   （本 Godot 版本没有 get_theme_stylebox_override / has_theme_style_override）
	var cur : StyleBox = btn.get_theme_stylebox("normal")
	return cur is StyleBoxEmpty


## 编辑器工具 UI：向上遍历，脚本路径含 /tool/ 则判为工具节点。
func _is_tool_ui(btn : BaseButton) -> bool:
	var node : Node = btn
	while node != null:
		var s : Script = node.get_script()
		if s != null and s.resource_path.contains("/tool/"):
			return true
		node = node.get_parent()
	return false
