extends Resource
class_name TalentInstance

@export var talent_id: String = ""
@export var current_stack: int = 0
@export var is_ready: bool = false
@export var is_active: bool = true

func reset():
	current_stack = 0
	is_ready = false
	is_active = true
