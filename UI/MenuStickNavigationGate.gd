extends RefCounted

## Converts noisy left-stick motion into one menu navigation press per deflection.
## The stick must return near center before the same direction can fire again.

const ACTIVATION_THRESHOLD := 0.72
const RELEASE_THRESHOLD := 0.38

var _held_directions: Dictionary = {}


func should_suppress(event: InputEvent) -> bool:
	if not event is InputEventJoypadMotion:
		return false
	var motion := event as InputEventJoypadMotion
	if motion.axis != JOY_AXIS_LEFT_X and motion.axis != JOY_AXIS_LEFT_Y:
		return false

	var key := Vector2i(motion.device, motion.axis)
	var held_direction := int(_held_directions.get(key, 0))
	var magnitude := absf(motion.axis_value)
	if magnitude <= RELEASE_THRESHOLD:
		_held_directions[key] = 0
		return true
	if magnitude < ACTIVATION_THRESHOLD:
		return true

	var direction := 1 if motion.axis_value > 0.0 else -1
	if direction == held_direction:
		return true
	_held_directions[key] = direction
	return false
