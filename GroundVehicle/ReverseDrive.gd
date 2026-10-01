extends RefCounted
## Shared direction selection. Hysteresis prevents gear hunting near sideways.

static func choose_reverse(forward_dot: float, reversing: bool) -> bool:
	return forward_dot < 0.25 if reversing else forward_dot < -0.5

static func approach_speed(current: float, target: float, acceleration: float, braking: float, delta: float) -> float:
	# Reach zero before engaging the opposite direction, even on a coarse tick.
	if current * target < 0.0:
		return move_toward(current, 0.0, maxf(braking, 0.0) * delta)
	var rate := braking if absf(target) < absf(current) else acceleration
	return move_toward(current, target, maxf(rate, 0.0) * delta)
