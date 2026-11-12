extends Resource
class_name SoundConfig

@export var select_unit : AudioStream
@export var attack : AudioStream
@export var hit : AudioStream
@export var miss : AudioStream
@export var heal : AudioStream

## 我方单位阵亡音效（team_id == 0），也是全项目阵亡音效的默认兜底。
@export var death_ally : AudioStream
## 敌方单位阵亡音效（team_id == 1）。为空则回退到 death_ally。
@export var death_enemy : AudioStream

@export var move_sound : AudioStream
@export var cancel : AudioStream
@export var invalid_click : AudioStream
@export var wait : AudioStream
@export var get_item : AudioStream
