class_name UIBinder
extends Node

var _bf : Node2D


func _init(bf: Node2D):
	_bf = bf


# ============================================================
#  一次绑定所有
# ============================================================
func bind_all() -> void:
	_initialize_managers()
	_connect_panel_buttons()
	_connect_signal_bus()
	_connect_movement_animator()
	_bf._on_speed_changed(Globals.game_speed)


# ============================================================
#  Managers 初始化
# ============================================================
func _initialize_managers() -> void:
	_bf.ui_manager.initialize({
		"victory_panel": _bf.victory_panel,
		"victory_label": _bf.victory_label,
		"victory_button": _bf.victory_button,
	})
	_bf.highlight_manager.initialize(_bf)
	_bf.turnlayer_manager.initialize(_bf.turn_overlay)
	InputManager.ui_manager = _bf.ui_manager


# ============================================================
#  设置栏按钮
# ============================================================
func _connect_panel_buttons() -> void:
	var pm : PanelManager = _bf._panel_manager
	_safe_connect(_bf.setting_btn.pressed, pm.on_setting_btn_pressed)
	_safe_connect(_bf.item_list_btn.pressed, pm.on_item_list_btn_pressed)
	_safe_connect(_bf.team_view_btn.pressed, pm.on_team_view_btn_pressed)
	if _bf.relic_view_btn:
		_safe_connect(_bf.relic_view_btn.pressed, pm.on_relic_view_btn_pressed)


# ============================================================
#  SignalBus 全部连接
# ============================================================
func _connect_signal_bus() -> void:
	# ---- Battlefield 自身 ----
	_safe_connect(SignalBus.request_move_unit, _bf._on_instant_move)
	_safe_connect(SignalBus.request_move_along_path, _bf._on_request_move_along_path)
	_safe_connect(SignalBus.request_ai_move_along_path, _bf._on_ai_move_along_path)
	_safe_connect(SignalBus.request_show_victory, _bf._victory_handler.on_request_show_victory)
	_safe_connect(SignalBus.turn_changed, _bf._turn_controller.on_turn_changed)
	_safe_connect(SignalBus.request_screen_shake, _bf._on_request_screen_shake)
	_safe_connect(SignalBus.request_damage_popup, _bf._on_request_damage_popup)
	_safe_connect(SignalBus.request_show_info, _bf._on_request_show_info)
	_safe_connect(SignalBus.request_hide_info, _bf._on_request_hide_info)
	_safe_connect(SignalBus.request_show_setting, _bf._on_request_show_setting)
	_safe_connect(SignalBus.request_hide_setting, _bf._on_request_hide_setting)
	_safe_connect(SignalBus.speed_changed, _bf._on_speed_changed)
	_safe_connect(SignalBus.request_show_enemy_preview, _bf._on_show_enemy_preview)
	_safe_connect(SignalBus.request_hint_override, _bf._set_hint_override)

	# ---- 子模块 ----
	_safe_connect(SignalBus.request_clear_highlight, _bf.highlight_manager.clear_highlight)
	_safe_connect(SignalBus.non_combat_complete, _bf._non_combat_handler.on_non_combat_complete)
	_safe_connect(SignalBus.request_dialogue_check, _bf._function_handler.on_dialogue_check)
	_safe_connect(SignalBus.request_highlight_unit, _bf._cursor_controller.show_attack_indicator)
	_safe_connect(SignalBus.request_clear_highlight_unit, _bf._cursor_controller.clear_attack_indicator)
	_safe_connect(SignalBus.request_setting_right_click, _bf._on_request_setting_right_click)


# ============================================================
#  MovementAnimator 回调
# ============================================================
func _connect_movement_animator() -> void:
	_safe_connect(_bf.movement_animator.movement_finished, _bf._on_player_movement_finished)
	_safe_connect(_bf.movement_animator.ai_movement_finished, _bf._on_ai_movement_finished)


# ============================================================
#  辅助：安全连接
# ============================================================
func _safe_connect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
	sig.connect(callable)
