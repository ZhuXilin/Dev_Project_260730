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
@export var hero_shrine_music : AudioStream            # ★ 英灵殿 BGM
@export var hero_shrine_convert_music : AudioStream    # ★ 转职演出音乐

# ---- 对话音乐 ----
@export var dialogue_music : AudioStream
@export var battle_start_dialogue_music : AudioStream
