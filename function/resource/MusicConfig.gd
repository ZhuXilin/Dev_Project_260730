extends Resource
class_name MusicConfig

# ---- 场景音乐 ----
@export var main_menu_music : AudioStream
@export var camp_music : AudioStream
@export var unit_select_music : AudioStream
@export var map_music : AudioStream
@export var non_combat_music : AudioStream

# ---- 战斗音乐 ----
@export var player_turn_music : AudioStream
@export var enemy_turn_music : AudioStream
@export var boss_player_turn_music : AudioStream
@export var boss_enemy_turn_music : AudioStream
@export var victory_music : AudioStream
@export var defeat_music : AudioStream
@export var win_game_music : AudioStream

# ---- 营地子界面音乐 ----
@export var soul_altar_music : AudioStream
@export var anvil_tavern_music : AudioStream
@export var arena_music : AudioStream
@export var arena_battle_music : AudioStream
@export var hero_shrine_music : AudioStream
@export var hero_shrine_convert_music : AudioStream

# ---- 对话音乐 ----
@export var dialogue_music : AudioStream
@export var battle_start_dialogue_music : AudioStream

# ============================================================
#  ★ Chip 音乐（8-bit）
# ============================================================
## 自动扫描这些目录里的 .json 作为 chip 音乐
## 文件名（去 .json）= slot 名
## 例：main_menu.json → 主菜单 chip
## 优先级：本字典手动覆盖 > 自动扫描
@export var chip_music_dirs: Array[String] = [
	"res://content/music/",
	"res://content/sound/",
]

## 手动指定 slot → JSON 路径（覆盖自动扫描）
## key: slot 名（main_menu / player_turn / ...）
## value: JSON 资源路径
@export var chip_replacements: Dictionary = {}
