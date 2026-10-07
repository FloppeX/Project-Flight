extends RefCounted
## Shared direction selection. Hysteresis prevents gear hunting near sideways.

# Ground vehicles may back into a nearby position, but not follow an entire
# route (or a moving formation slot) in reverse. Carrier controls still use
# the unrestricted angle selector below.
const MAX_NAVIGATION_REVERSE_DISTANCE_M := 15.0
const MAX_NAVIGATION_REVERSE_SECONDS := 3.0
var _navigation_reversing := false
var _reverse_seconds := 0.0
var _turn_forward_required := false

func reset_navigation() -> void:
	_navigation_reversing = false
	_reverse_seconds = 0.0
	_turn_forward_required = false

func choose_navigation_reverse(forward_dot: float, destination_distance_m: float,
		delta: float, permitted: bool = true) -> bool:
	if forward_dot >= 0.5:
		reset_navigation()
	if _navigation_reversing:
		_reverse_seconds += maxf(delta, 0.0)
		if _reverse_seconds >= MAX_NAVIGATION_REVERSE_SECONDS:
			_turn_forward_required = true
	_navigation_reversing = permitted and not _turn_forward_required \
		and destination_distance_m <= MAX_NAVIGATION_REVERSE_DISTANCE_M \
		and choose_reverse(forward_dot, _navigation_reversing)
	return _navigation_reversing

static func choose_reverse(forward_dot: float, reversing: bool) -> bool:
	return forward_dot < 0.25 if reversing else forward_dot < -0.5

static func approach_speed(current: float, target: float, acceleration: float, braking: float, delta: float) -> float:
	# Reach zero before engaging the opposite direction, even on a coarse tick.
	if current * target < 0.0:
		return move_toward(current, 0.0, maxf(braking, 0.0) * delta)
	var rate := braking if absf(target) < absf(current) else acceleration
	return move_toward(current, target, maxf(rate, 0.0) * delta)
