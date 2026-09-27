extends RefCounted
## Shared photo/trailer camera bindings, deadzones and movement-speed ladder.
const MOVE_SPEED_LEVELS := [0.625, 1.25, 2.5, 5.0, 10.0, 20.0, 40.0, 80.0, 160.0, 320.0]

static func axis(axes: Dictionary, index: int, deadzone: float = 0.15) -> float:
	var value := float(axes.get(index, 0.0))
	return signf(value) * maxf(0.0, (absf(value) - deadzone) / (1.0 - deadzone))

static func pad_motion(axes: Dictionary, buttons: Dictionary) -> Dictionary:
	return {
		"move": Vector3(axis(axes, JOY_AXIS_LEFT_X), float(buttons.get(JOY_BUTTON_RIGHT_SHOULDER, false)) - float(buttons.get(JOY_BUTTON_LEFT_SHOULDER, false)), axis(axes, JOY_AXIS_LEFT_Y)),
		"look": Vector2(axis(axes, JOY_AXIS_RIGHT_X), axis(axes, JOY_AXIS_RIGHT_Y)),
		"roll": float(buttons.get(JOY_BUTTON_DPAD_LEFT, false)) - float(buttons.get(JOY_BUTTON_DPAD_RIGHT, false)),
		"zoom": maxf(0.0, axis(axes, JOY_AXIS_TRIGGER_LEFT, 0.05)) - maxf(0.0, axis(axes, JOY_AXIS_TRIGGER_RIGHT, 0.05))}
