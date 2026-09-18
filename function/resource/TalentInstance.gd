extends Resource
class_name TalentInstance

@export var talent_id: String = ""
@export var current_stack: int = 0
@export var is_ready: bool = false
@export var is_active: bool = true
@export var cooldown_remaining: int = 0      # ★ 新增

func reset():
	current_stack = 0
	is_ready = false
	is_active = true
	# 注意：不重置 cooldown_remaining（由 TalentManager.reset_talent 单独设置）
