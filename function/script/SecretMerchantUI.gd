class_name SecretMerchantUI
extends CanvasLayer

signal closed

var cost_key : int = 200

@onready var soul_label : Label = $Panel/VBox/TitleBar/SoulLabel
@onready var buy_btn : Button = $Panel/VBox/BuyBtn
@onready var hint_label : Label = $Panel/VBox/HintLabel
@onready var back_btn : Button = $Panel/VBox/BackBtn


func _ready():
	layer = 25
	_refresh_ui()

	if not buy_btn.pressed.is_connected(_on_buy_pressed):
		buy_btn.pressed.connect(_on_buy_pressed)
	if not back_btn.pressed.is_connected(_on_back_pressed):
		back_btn.pressed.connect(_on_back_pressed)


func _refresh_ui():
	soul_label.text = "当前魂: %d" % GameState.soul

	if GameState.keys >= 1:
		buy_btn.text = "已达单局携带上限"
		buy_btn.disabled = true
	elif GameState.soul < cost_key:
		buy_btn.text = "购买死眠之钥（%d 魂）\n魂不足" % cost_key
		buy_btn.disabled = true
	else:
		buy_btn.text = "购买死眠之钥（%d 魂）" % cost_key
		buy_btn.disabled = false


func _on_buy_pressed():
	if GameState.keys >= 1:
		return
	if GameState.soul < cost_key:
		return

	GameState.soul -= cost_key
	GameState.keys = 1
	GameState.keys_bought += 1
	SaveManager.auto_save()
	_refresh_ui()

	if hint_label:
		hint_label.text = "★ 已获得死眠之钥！去局内寻找宝箱吧。"
		hint_label.modulate = Color(0.7, 1.0, 0.7)


func _on_back_pressed():
	closed.emit()
	queue_free()
