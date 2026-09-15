extends CanvasLayer

signal closed

var winner_team : int = -1   # 0 = 玩家胜，1 = 敌人胜

var _player : UnitData
var _enemy : UnitData
var _player_hp : int = 0
var _enemy_hp : int = 0
var _battle_running : bool = false

@onready var player_name : Label = $Panel/VBox/BattleHBox/PlayerPanel/PlayerName
@onready var player_hp_bar : ProgressBar = $Panel/VBox/BattleHBox/PlayerPanel/PlayerHpBar
@onready var player_hp_label : Label = $Panel/VBox/BattleHBox/PlayerPanel/PlayerHpLabel
@onready var enemy_name : Label = $Panel/VBox/BattleHBox/EnemyPanel/EnemyName
@onready var enemy_hp_bar : ProgressBar = $Panel/VBox/BattleHBox/EnemyPanel/EnemyHpBar
@onready var enemy_hp_label : Label = $Panel/VBox/BattleHBox/EnemyPanel/EnemyHpLabel
@onready var log_label : Label = $Panel/VBox/LogLabel
@onready var result_label : Label = $Panel/VBox/ResultLabel
@onready var close_btn : Button = $Panel/VBox/CloseButton


func setup(player_data: UnitData, enemy_data: UnitData):
	_player = player_data
	_enemy = enemy_data
	_player_hp = player_data.max_hp
	_enemy_hp = enemy_data.max_hp

	var p_display = player_data.display_name if player_data.display_name != "" else player_data.unit_name
	var e_display = enemy_data.display_name if enemy_data.display_name != "" else enemy_data.unit_name
	player_name.text = p_display
	enemy_name.text = e_display

	player_hp_bar.max_value = player_data.max_hp
	player_hp_bar.value = _player_hp
	enemy_hp_bar.max_value = enemy_data.max_hp
	enemy_hp_bar.value = _enemy_hp

	_refresh_hp_labels()
	_run_battle()


func _run_battle():
	if _battle_running:
		return
	_battle_running = true

	log_label.text = "战斗开始！"
	await get_tree().create_timer(0.5, true, false, true).timeout

	var player_first = _player.dexterity >= _enemy.dexterity
	var attacker_first = _player if player_first else _enemy
	var attacker_second = _enemy if player_first else _player

	var turn = 0
	while _player_hp > 0 and _enemy_hp > 0 and turn < 50:
		await _do_attack(attacker_first, attacker_second)
		if _player_hp <= 0 or _enemy_hp <= 0:
			break
		await _do_attack(attacker_second, attacker_first)
		if _player_hp <= 0 or _enemy_hp <= 0:
			break
		turn += 1

	if _player_hp > 0 and _enemy_hp <= 0:
		winner_team = 0
		result_label.text = "胜利！"
		result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
	elif _enemy_hp > 0 and _player_hp <= 0:
		winner_team = 1
		result_label.text = "失败……"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1))
	else:
		winner_team = 0 if _player_hp >= _enemy_hp else 1
		result_label.text = "平局判定"

	close_btn.visible = true


func _do_attack(attacker: UnitData, defender: UnitData):
	if _player_hp <= 0 or _enemy_hp <= 0:
		return

	var damage = _calc_damage(attacker, defender)

	var is_player_attacker = (attacker == _player)
	if is_player_attacker:
		_enemy_hp = max(0, _enemy_hp - damage)
		enemy_hp_bar.value = _enemy_hp
	else:
		_player_hp = max(0, _player_hp - damage)
		player_hp_bar.value = _player_hp

	var atk_name = attacker.display_name if attacker.display_name != "" else attacker.unit_name
	var def_name = defender.display_name if defender.display_name != "" else defender.unit_name
	log_label.text = "%s 攻击 %s，造成 %d 伤害" % [atk_name, def_name, damage]

	_refresh_hp_labels()
	await get_tree().create_timer(0.6, true, false, true).timeout


func _calc_damage(attacker: UnitData, defender: UnitData) -> int:
	if not attacker.weapon_slot:
		return 1
	var weapon_data = ItemManager.get_item_data(attacker.weapon_slot.item_id)
	if not weapon_data:
		return 1

	var quality_mult = CombatManager.QUALITY_MULT.get(weapon_data.quality, 1.0)
	var upgrade_bonus = attacker.weapon_slot.upgrade_level
	var base_attack = (weapon_data.base_attack + upgrade_bonus) * quality_mult

	var atk_bonus = 0.0
	for attr in weapon_data.modifier:
		var val = 0
		match attr:
			"strength": val = attacker.strength
			"dexterity": val = attacker.dexterity
			"intelligence": val = attacker.intelligence
			"faith": val = attacker.faith
			"arcane": val = attacker.arcane
		atk_bonus += val * weapon_data.modifier[attr]

	var total_attack = base_attack + atk_bonus

	var armor_defense = 0
	for slot in defender.armor_slots:
		if slot:
			var item_data = ItemManager.get_item_data(slot.item_id)
			if item_data:
				var armor_quality_mult = CombatManager.QUALITY_MULT.get(item_data.quality, 1.0)
				armor_defense += item_data.defense * armor_quality_mult
	var def_value = defender.strength * CombatManager.STRENGTH_DEF_FACTOR + armor_defense

	return max(1, int(total_attack - def_value))


func _refresh_hp_labels():
	player_hp_label.text = "%d/%d" % [_player_hp, _player.max_hp]
	enemy_hp_label.text = "%d/%d" % [_enemy_hp, _enemy.max_hp]


func _on_close_pressed():
	closed.emit()
	queue_free()
