extends Node

const PATHS : Dictionary = {
	# JSON 数据
	"ITEM_DATA":        "res://content/data/item_data.json",
	"ITEM_UNLOCK":      "res://content/data/item_unlock.json",
	"UNIT_DATA":        "res://content/data/unit_data.json",
	"UNIT_UNLOCK":      "res://content/data/unit_unlock.json",
	"RELIC_DATA":       "res://content/data/relic_data.json",
	"RELIC_UNLOCK":     "res://content/data/relic_unlock.json",
	"TALENT_DATA":      "res://content/data/talents.json",
	"DIALOGUE_DATA":    "res://content/data/dialogues.json",
	"EVENT_DATA":       "res://content/data/events.json",
	"RECIPE_DATA":      "res://content/data/recipes.json",
	"STORY_DATA":       "res://content/data/stories.json",

	# 配置资源
	"MUSIC_CONFIG":     "res://content/scenes/levels/MusicConfig.tres",
	"SOUND_CONFIG":     "res://content/scenes/levels/SoundConfig.tres",
	"UNIT_LEVEL_MAP":   "res://content/scenes/levels/UnitLevelMap.tres",
	"LEVEL_LIST":       "res://content/scenes/levels/LevelList.tres",

	# 样式 / 着色器
	"STYLEBOX_8BIT":        "res://content/resource/stylebox/8bit_style_box_flat.tres",
	"SHADER_REPLACE_COLOR": "res://content/resource/shader/replace_color.gdshader",
	"SHADER_GRAY":          "res://content/resource/shader/gray.gdshader",

	# 场景：关卡 / 单位
	"UNIT_SCENE":           "res://content/scenes/units/Unit.tscn",
	"BATTLEFIELD_SCENE":    "res://content/scenes/levels/Battlefield.tscn",

	# 场景：UI
	"MAIN_MENU":            "res://content/scenes/ui/MainMenu.tscn",
	"CAMP":                 "res://content/scenes/ui/Camp.tscn",
	"LOADING":              "res://content/scenes/ui/Loading.tscn",
	"MAP_SCENE":            "res://content/scenes/ui/MapScene.tscn",
	"UNIT_SELECT_UI":       "res://content/scenes/ui/UnitSelectUI.tscn",
	"EQUIPMENT_CONFIG":     "res://content/scenes/ui/EquipmentConfig.tscn",
	"SAVE_SELECT_UI":       "res://content/scenes/ui/SaveSelectUI.tscn",
	"UNIT_INFO_UI":         "res://content/scenes/ui/UnitInfoUI.tscn",
	"ITEM_INFO_UI":         "res://content/scenes/ui/ItemInfoUI.tscn",
	"CONFIRM_UI":           "res://content/scenes/ui/ConfirmUI.tscn",
	"DIALOGUE_UI":          "res://content/scenes/ui/DialogueUI.tscn",
	"ITEM_GET_POPUP":       "res://content/scenes/ui/ItemGetPopup.tscn",
	"ITEM_DETAIL_POPUP":    "res://content/scenes/ui/ItemDetailPopup.tscn",
	"RELIC_SELECT_UI":      "res://content/scenes/ui/RelicSelectUI.tscn",
	"REWARD_SUMMARY_UI":    "res://content/scenes/ui/RewardSummaryUI.tscn",
	"TREASURE_UI":          "res://content/scenes/ui/Treasure.tscn",
	"ANVIL_TAVERN_UI":      "res://content/scenes/ui/AnvilTavern.tscn",

	# 脚本
	"DAMAGE_POPUP_SCRIPT":      "res://function/script/DamagePopup.gd",
	"SHOP_MANAGER_SCRIPT":      "res://function/script/ShopManager.gd",
	"MAP_SCENE_SCRIPT":         "res://function/script/MapScene.gd",
	"EQUIPMENT_CONFIG_SCRIPT":  "res://function/script/EquipmentConfig.gd",

	# 图片 / 纹理
	"CURSOR_TEXTURE":       "res://content/images/system/选择框.png",
}
