extends AIPilot

var assignments := 0

func _ready() -> void:
	pass

func assign_air_task(task: Variant) -> bool:
	assignments += 1
	current_air_task = task
	current_state = State.ATTACK_POSITIONING if task.kind == AirTask.Kind.ATTACK_TARGET else State.RTB if task.kind == AirTask.Kind.RETURN_TO_BASE else State.SEARCH
	if task.kind == AirTask.Kind.INTERCEPT_TARGET:
		combat_target = task.get_target()
		current_state = State.DOGFIGHT
	return true
