extends CanvasLayer

# ============================================================
#  Camp — 营地 / 祭祀场
#  v4.5：横向三屏探索（左右箭头导航）+ 隐藏商人
# ============================================================

const SCREEN_LEFT : int = -1
const SCREEN_CENTER : int = 0
const SCREEN_RIGHT : int = 1

const SLIDE_DURATION : float = 0.35
const ARROW_W : int = 26
const ARROW_H : int = 64

@onready var soul_label : Label = $ResourcePanel/SoulLabel
@onready var soul_fire_label : Label = $ResourcePanel/SoulFireLabel
@onready var fire_sprite : TextureRect = $FireSprite

@onready var entrance_gate : TextureButton = $EntranceGate
@onready var soul_keeper_btn : TextureButton = $NpcGrid/SoulKeeperBtn
@onready var blacksmith_btn : TextureButton = $NpcGrid/BlacksmithBtn
@onready var guide_btn : TextureButton = $NpcGrid/GuideBtn
@onready var gladiator_btn : TextureButton = $NpcGrid/GladiatorBtn
@onready var back_btn : Button = $BackButton

# ---- 横向世界 ----
var _screen_w : int = 400
var _screen_h : int = 240
var _viewport : Control = null
var _world : Control = null
var _screen_center : Control = null
var _left_arrow : Button = null
var _right_arrow : Button = null
var _slide_tween : Tween = null
var _secret_blink_tween : Tween = null
var _current_screen : int = SCREEN_CENTER
var _secret_side : int = 0
var _secret_btn : TextureButton = null


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.is_transitioning = false

	_connect_buttons()
	_load_art()
	_ensure_default_party()
	update_display()
	_play_camp_music()

	DispatchManager.rotate_routes()
	_show_dispatch_results()

	_setup_scroll_world()
	_check_secret_merchant()


# ============================================================
#  横向探索世界
# ============================================================
func _setup_scroll_world():
	var vp_size : Vector2 = get_viewport().get_visible_rect().size
	_screen_w = int(vp_size.x)
	_screen_h = int(vp_size.y)
	if _screen_w <= 0:
		_screen_w = 400
	if _screen_h <= 0:
		_screen_h = 240

	# 1. 视口：裁切世界
	_viewport = Control.new()
	_viewport.name = "CampViewport"
	_viewport.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.clip_contents = true
	add_child(_viewport)

	# 2. 世界：3 屏宽，初始显示中间屏
	_world = Control.new()
	_world.name = "CampWorld"
	_world.size = Vector2(_screen_w * 3, _screen_h)
	_world.position = Vector2(-_screen_w, 0)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_world)

	# 3. 中央屏容器（1 屏大小，位于 world 中间）
	_screen_center = Control.new()
	_screen_center.name = "ScreenCenter"
	_screen_center.size = Vector2(_screen_w, _screen_h)
	_screen_center.position = Vector2(_screen_w, 0)
	_screen_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_screen_center)

	# 3.5 ★ 中屏背景（随 world 一起左右滑动）
	#     先添加 → 处于 _screen_center 子节点第 0 位 → 最底层，
	#     后续移入的 FireSprite / EntranceGate / NpcGrid 会覆盖在其上。
	var center_bg_path : String = "res://content/images/ui/camp_001.png"
	if ResourceLoader.exists(center_bg_path):
		var center_bg_tex := TextureRect.new()
		center_bg_tex.name = "CampBackground"
		center_bg_tex.texture = load(center_bg_path)
		center_bg_tex.size = Vector2(_screen_w, _screen_h)
		center_bg_tex.position = Vector2.ZERO
		center_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		center_bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		center_bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen_center.add_child(center_bg_tex)
	else:
		# 兜底：缺图时使用纯色，保持原 Camp.tscn 的底色
		var center_bg_rect := ColorRect.new()
		center_bg_rect.name = "CampBackground"
		center_bg_rect.color = Color(0.08, 0.07, 0.06, 1)
		center_bg_rect.size = Vector2(_screen_w, _screen_h)
		center_bg_rect.position = Vector2.ZERO
		center_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen_center.add_child(center_bg_rect)

	# 4. 把可滑动的场景节点从 Camp 移入中央屏
	for nname in ["FireSprite", "EntranceGate", "NpcGrid"]:
		var node = get_node_or_null(nname)
		if node:
			remove_child(node)
			_screen_center.add_child(node)

	# 5. 左右探索区
	_build_exploration_areas()

	# 6. 固定 UI 置顶：Title / ResourcePanel / BackButton
	for nname in ["Title", "ResourcePanel", "BackButton"]:
		var node = get_node_or_null(nname)
		if node:
			move_child(node, -1)

	# 7. 左右导航箭头（永远置顶）
	_build_nav_arrows()


func _build_exploration_areas():
	_build_explore_room(SCREEN_LEFT, "废弃的侧厅", Color(0.08, 0.07, 0.06))
	_build_explore_room(SCREEN_RIGHT, "灰烬的角落", Color(0.08, 0.07, 0.06))


func _build_explore_room(side : int, title : String, bg_color : Color):
	var room := Control.new()
	room.name = "ExploreRoom_%d" % side
	room.size = Vector2(_screen_w, _screen_h)
	room.position = Vector2(0 if side < 0 else _screen_w * 2, 0)
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ★ 背景：左屏 background_002.png，右屏 background_003.png
	var bg_path : String = ""
	if side < 0:
		bg_path = "res://content/images/ui/camp_002.png"
	else:
		bg_path = "res://content/images/ui/camp_003.png"

	if bg_path != "" and ResourceLoader.exists(bg_path):
		var bg_tex := TextureRect.new()
		bg_tex.name = "RoomBackground"
		bg_tex.texture = load(bg_path)
		bg_tex.size = Vector2(_screen_w, _screen_h)
		bg_tex.position = Vector2.ZERO
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		room.add_child(bg_tex)
	else:
		# 兜底：缺图时回退到原纯色
		var bg := ColorRect.new()
		bg.color = bg_color
		bg.size = Vector2(_screen_w, _screen_h)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		room.add_child(bg)

	var title_lb := Label.new()
	title_lb.text = title
	title_lb.position = Vector2(0, 20)
	title_lb.size = Vector2(_screen_w, 20)
	title_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lb.add_theme_font_size_override("font_size", 8)
	title_lb.modulate = Color(0.5, 0.5, 0.5, 0.7)
	room.add_child(title_lb)

	_world.add_child(room)


# ============================================================
#  左右导航箭头
# ============================================================
func _build_nav_arrows():
	_left_arrow = _make_arrow_button("◀")
	_left_arrow.name = "LeftArrow"
	_left_arrow.position = Vector2(2, (_screen_h - ARROW_H) / 2.0)
	_left_arrow.size = Vector2(ARROW_W, ARROW_H)
	_left_arrow.pressed.connect(_on_left_arrow_pressed)
	add_child(_left_arrow)

	_right_arrow = _make_arrow_button("▶")
	_right_arrow.name = "RightArrow"
	_right_arrow.position = Vector2(_screen_w - ARROW_W - 2, (_screen_h - ARROW_H) / 2.0)
	_right_arrow.size = Vector2(ARROW_W, ARROW_H)
	_right_arrow.pressed.connect(_on_right_arrow_pressed)
	add_child(_right_arrow)

	_refresh_arrows()


func _make_arrow_button(text : String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.6, 0.6, 0.7))
	b.add_theme_color_override("font_disabled_color", Color(0.25, 0.25, 0.3))

	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 0
	empty.content_margin_right = 0
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("disabled", empty)
	b.add_theme_stylebox_override("focus", empty)
	return b


func _on_left_arrow_pressed():
	if _current_screen <= SCREEN_LEFT:
		return
	_current_screen -= 1
	_slide_to_screen(_current_screen)


func _on_right_arrow_pressed():
	if _current_screen >= SCREEN_RIGHT:
		return
	_current_screen += 1
	_slide_to_screen(_current_screen)


func _slide_to_screen(screen : int):
	if _world == null:
		return
	var target_x : float = -float(_screen_w) * float(screen + 1)

	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_ignore_time_scale(true)
	_slide_tween.tween_property(_world, "position:x", target_x, SLIDE_DURATION) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_QUAD)

	_refresh_arrows()


func _refresh_arrows():
	if _left_arrow:
		_left_arrow.disabled = (_current_screen <= SCREEN_LEFT)
	if _right_arrow:
		_right_arrow.disabled = (_current_screen >= SCREEN_RIGHT)

	# 停止旧闪烁
	if _secret_blink_tween and _secret_blink_tween.is_valid():
		_secret_blink_tween.kill()
	_secret_blink_tween = null

	if _left_arrow:
		_left_arrow.modulate = Color.WHITE
	if _right_arrow:
		_right_arrow.modulate = Color.WHITE

	if _secret_side == 0:
		return
	if _secret_side == _current_screen:
		return

	var target_arrow : Button = _left_arrow if _secret_side < 0 else _right_arrow
	if target_arrow == null or target_arrow.disabled:
		return

	target_arrow.modulate = Color(1.0, 0.85, 0.3)
	_secret_blink_tween = create_tween()
	_secret_blink_tween.set_ignore_time_scale(true)
	_secret_blink_tween.set_loops(-1)
	_secret_blink_tween.tween_property(target_arrow, "modulate:a", 0.5, 0.5)
	_secret_blink_tween.tween_property(target_arrow, "modulate:a", 1.0, 0.5)


# ============================================================
#  隐藏商人
# ============================================================
func _should_show_secret_merchant() -> bool:
	if GameState.total_run_count <= 0:
		return false
	if GameState.total_run_count % 3 != 0:
		return false
	var flag : String = "met_secret_merchant_run_%d" % GameState.total_run_count
	return not (flag in GameState.npc_dialogue_flags)


func _check_secret_merchant():
	if _world == null:
		return
	if _world.get_node_or_null("SecretMerchantBtn") != null:
		return
	if not _should_show_secret_merchant():
		return

	_secret_side = SCREEN_LEFT if randf() < 0.5 else SCREEN_RIGHT
	_spawn_secret_merchant(_secret_side)
	_refresh_arrows()

	# 首次出现时给一次性提示
	var notice_flag : String = "notified_secret_merchant_run_%d" % GameState.total_run_count
	if not (notice_flag in GameState.npc_dialogue_flags):
		GameState.npc_dialogue_flags.append(notice_flag)
		var side_cn : String = "左" if _secret_side < 0 else "右"
		_show_floating_toast("……%s边好像有动静" % side_cn)


func _spawn_secret_merchant(side : int):
	_secret_btn = TextureButton.new()
	_secret_btn.name = "SecretMerchantBtn"

	var cx : float = 0.0
	if side < 0:
		cx = float(_screen_w) * 0.5
	else:
		cx = float(_screen_w) * 2.5
	_secret_btn.position = Vector2(cx - 32.0, 80.0)
	_secret_btn.size = Vector2(64, 64)
	_secret_btn.custom_minimum_size = Vector2(64, 64)

	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.1, 0.3, 0.85))
	var tex := ImageTexture.create_from_image(img)
	_secret_btn.texture_normal = tex

	var label := Label.new()
	label.text = "黑市商人"
	label.position = Vector2(0, -16)
	label.size = Vector2(64, 14)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_secret_btn.add_child(label)

	_secret_btn.pressed.connect(_on_secret_merchant_pressed)
	_world.add_child(_secret_btn)


func _on_secret_merchant_pressed():
	# 记录本局已访问，避免同一局重复出现
	var flag : String = "met_secret_merchant_run_%d" % GameState.total_run_count
	if not (flag in GameState.npc_dialogue_flags):
		GameState.npc_dialogue_flags.append(flag)
		SaveManager.auto_save()

	# ★ 不再对话前切到 secret_merchant 音乐：让 DialogueManager 走正常的"暂停/恢复"
	#   对话结束后由 SecretMerchantUI._ready() 播商人音乐
	var played : bool = StoryManager.play_next_dialogue("secret_merchant")
	if played:
		await DialogueManager.dialogue_finished
	if not is_inside_tree():
		return

	# 再弹交易 UI（UI 内部 _ready() 播 secret_merchant 音乐）
	var scene = load("res://content/scenes/ui/SecretMerchantUI.tscn")
	if not scene:
		push_warning("[Camp] SecretMerchantUI.tscn 未找到")
		return
	var ui = scene.instantiate()
	ui.name = "SecretMerchantUI"
	add_child(ui)

	# ★ 防止同名残留：如果已经有一个同名 CanvasLayer（极少见），先清掉
	var stale = get_node_or_null("SecretMerchantUI")
	if stale and stale != ui:
		stale.queue_free()

	await ui.closed

	if not is_inside_tree():
		return
	# ★ 检查 ui 是否真的关闭：ui 已被 queue_free 但引用仍在，下一帧才会失效
	#   这里强制把引用断开，防止后续 is_instance_valid 误判
	ui = null
	update_display()
	_restore_camp_music()

	# 交易完成后移除商人，箭头恢复
	if is_instance_valid(_secret_btn):
		_secret_btn.queue_free()
	_secret_btn = null
	_secret_side = 0
	_refresh_arrows()


# ============================================================
#  原有：按钮连接
# ============================================================
func _connect_buttons():
	var pairs = [
		[entrance_gate, _on_deploy_pressed],
		[soul_keeper_btn, _on_soul_keeper_pressed],
		[blacksmith_btn, _on_blacksmith_pressed],
		[guide_btn, _on_guide_pressed],
		[gladiator_btn, _on_gladiator_pressed],
		[back_btn, _on_back_pressed],
	]
	for pair in pairs:
		var btn = pair[0]
		var cb = pair[1]
		if not btn:
			continue
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)
		btn.pressed.connect(cb)


# ============================================================
#  原有：美术加载
# ============================================================
func _load_art():
	var bg_path = "res://content/images/sanctuary/bg.png"
	if ResourceLoader.exists(bg_path):
		var tex = load(bg_path)
		if tex and $Background is TextureRect:
			$Background.texture = tex

	var fire_path = "res://content/images/sanctuary/fire.png"
	if fire_sprite and ResourceLoader.exists(fire_path):
		fire_sprite.texture = load(fire_path)

	var npc_arts = {
		"soul_keeper": [soul_keeper_btn, "res://content/images/sanctuary/npc_soul_keeper.png"],
		"blacksmith": [blacksmith_btn, "res://content/images/sanctuary/npc_blacksmith.png"],
		"guide": [guide_btn, "res://content/images/sanctuary/npc_guide.png"],
		"gladiator": [gladiator_btn, "res://content/images/sanctuary/npc_gladiator.png"],
	}
	for key in npc_arts:
		var btn = npc_arts[key][0]
		var path = npc_arts[key][1]
		if btn and ResourceLoader.exists(path):
			btn.texture_normal = load(path)

	var gate_path = "res://content/images/sanctuary/gate.png"
	if entrance_gate and ResourceLoader.exists(gate_path):
		entrance_gate.texture_normal = load(gate_path)

	_update_affinity_display()


# ============================================================
#  原有：默认队伍
# ============================================================
func _ensure_default_party():
	if not GameState.party.is_empty():
		return
	var defaults : Array = Globals.unlock_config.get("default_unlocked", [])
	if defaults.is_empty():
		push_warning("[Camp] unlock_config.default_unlocked 为空，无法填充默认队伍")
		return
	var take : int = mini(3, defaults.size())
	var selected : Array[String] = []
	for i in range(take):
		var u : Variant = defaults[i]
		if u is String and (u as String) != "":
			selected.append(u)
	if selected.is_empty():
		return
	GameState.initialize_party(selected, 0)
	print("[Camp] 自动填充默认队伍：" + str(selected))


# ============================================================
#  原有：显示刷新
# ============================================================
func update_display():
	if soul_label:
		soul_label.text = "魂: %d" % GameState.soul
	if soul_fire_label:
		soul_fire_label.text = "魂火: %d / %d" % [
			SoulFireManager.current, SoulFireManager.get_max_carried()
		]
	
	# ★ v4.5：显示死眠之钥
	var key_label = get_node_or_null("ResourcePanel/KeyLabel")
	if key_label == null:
		key_label = Label.new()
		key_label.name = "KeyLabel"
		key_label.add_theme_font_size_override("font_size", 8)
		key_label.modulate = Color(1.0, 0.85, 0.3)
		$ResourcePanel.add_child(key_label)
		
	if GameState.keys > 0:
		key_label.text = "🗝 死眠之钥: %d / 1" % GameState.keys
		key_label.visible = true
	else:
		key_label.visible = false
		
	_update_affinity_display()


func _show_dispatch_results():
	var results : Array = DispatchManager.consume_pending_results()
	if results.is_empty():
		return

	var lines : Array = []
	for r in results:
		var unit : String = str(r.get("unit_name", "?"))
		var route : String = str(r.get("route_name", r.get("route_id", "?")))
		var soul : int = int(r.get("soul", 0))
		var bonus : int = int(r.get("bonus", 0))
		var line : String = "%s 从「%s」归来：+%d 魂" % [unit, route, soul]
		if bonus > 0:
			line += "（★ 标签匹配 +1）"
		lines.append(line)

	_show_floating_toast("\n".join(lines))


func _show_floating_toast(text : String):
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 8)
	toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 3)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -140
	toast.offset_right = 140
	toast.offset_top = 40
	toast.offset_bottom = 100
	add_child(toast)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(toast, "modulate:a", 0.0, 0.5).set_delay(3.0)
	tw.tween_callback(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)


func _update_affinity_display():
	var npcs : Array = [
		["soul_keeper", soul_keeper_btn],
		["blacksmith", blacksmith_btn],
		["guide", guide_btn],
		["gladiator", gladiator_btn],
	]
	for pair in npcs:
		var npc_id : String = pair[0]
		var btn : TextureButton = pair[1]
		if not btn:
			continue
		var aff : int = StoryManager.get_affinity(npc_id)
		var plate = btn.get_node_or_null("NamePlate")
		if plate:
			var base_name : String = str(plate.text)
			if base_name == "":
				base_name = npc_id
			var sp : PackedStringArray = base_name.split(" ")
			if sp.size() > 0:
				base_name = sp[0]
			if aff >= 15:
				plate.text = base_name + "  ❤❤❤"
			elif aff >= 10:
				plate.text = base_name + "  ❤❤"
			elif aff >= 5:
				plate.text = base_name + "  ❤"
			else:
				plate.text = base_name


func _play_camp_music():
	if MusicManager.config and MusicManager.config.camp_music:
		MusicManager.play_music(MusicManager.config.camp_music)


func _restore_camp_music():
	_play_camp_music()


# ============================================================
#  原有：NPC 入口
# ============================================================
func _on_deploy_pressed():
	if GameState.cached_map_level_data != null and not GameState.party.is_empty():
		Globals.show_confirm(self, "当前有未完成的冒险，确定重新开始吗？",
			"重新开始", "取消", _confirm_deploy, func(): pass, true)
		return
	_confirm_deploy()


func _confirm_deploy():
	GameState.reset_all()
	GameState.start_new_cycle()
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")


func _on_soul_keeper_pressed():
	await _npc_intro("soul_keeper")
	if not is_inside_tree():
		return
	_open_facility(Config.PATHS.SOUL_ALTAR_UI, "SoulAltar")


func _on_blacksmith_pressed():
	await _npc_intro("blacksmith")
	if not is_inside_tree():
		return
	var scene = load(Config.PATHS.ANVIL_TAVERN_UI)
	if not scene:
		return
	if get_node_or_null("AnvilTavern"):
		return
	var tavern = scene.instantiate()
	tavern.name = "AnvilTavern"
	tavern.setup(0)
	add_child(tavern)
	await tavern.closed
	if not is_inside_tree():
		return
	_restore_camp_music()
	update_display()


func _on_guide_pressed():
	await _npc_intro("guide")
	if not is_inside_tree():
		return
	_open_facility("res://content/scenes/ui/DispatchUI.tscn", "DispatchUI")


func _on_gladiator_pressed():
	await _npc_intro("gladiator")
	if not is_inside_tree():
		return
	_open_facility(Config.PATHS.ARENA_UI, "Arena")


func _open_facility(path: String, node_name: String):
	if get_node_or_null(node_name):
		return
	if not ResourceLoader.exists(path):
		push_warning("[Camp] 设施未找到: " + path)
		return
	var scene = load(path)
	var inst = scene.instantiate()
	inst.name = node_name
	add_child(inst)
	await inst.closed
	if not is_inside_tree():
		return
	_restore_camp_music()
	update_display()


func _npc_intro(npc_id: String):
	var played : bool = StoryManager.play_next_dialogue(npc_id)
	if not played:
		return
	if DialogueManager.has_pending_choices():
		var result = await DialogueManager.choice_selected
		if result is Array and result.size() == 2:
			var data : Dictionary = result[1]
			var flag : String = data.get("flag", "")
			if flag != "":
				StoryManager.record_choice(npc_id, flag)
	await DialogueManager.dialogue_finished

	var newly = StoryManager.check_and_apply_unlocks(npc_id)
	if newly.size() > 0:
		for u in newly:
			_show_unlock_toast(u.get("type", ""), u.get("id", ""))


func _show_unlock_toast(utype: String, uid: String):
	var msg : String = ""
	match utype:
		"unit":
			msg = "★ 新残魂加入：%s" % UnitDataManager.get_unit_type_display_name(uid)
		"relic":
			var rd = RelicManager.get_relic_data(uid)
			msg = "★ 新遗物：%s" % rd.get("name", uid)
		"aura":
			msg = "★ 新光环：%s" % AuraManager.get_display_name(uid)
		"transform_branch":
			msg = "★ 隐藏质变分支解锁"
		"route":
			var route : Dictionary = DispatchManager.ROUTES.get(uid, {})
			msg = "★ 新派遣路线：%s" % route.get("name", uid)
		"talent":
			var td = TalentManager.get_talent_data(uid)
			msg = "★ 新词条：%s" % (td.display_name if td else uid)
	if msg == "":
		return
	print("[Camp] " + _log_safe(msg))
	_show_floating_toast(msg)


static func escape_bbcode(text : String) -> String:
	return text.replace("[", "&#91;")


func _log_safe(s : Variant) -> String:
	return str(s).replace("\n", "\\n").replace("\t", "\\t")


func _on_back_pressed():
	GameState.interrupt_state = GameState.InterruptState.CAMP
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")
