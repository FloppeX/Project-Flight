class_name PIDController
extends RefCounted

## PID Controller for smooth control similar to human pilot
## Proportional-Integral-Derivative controller

var kp: float = 1.0  # Proportional gain
var ki: float = 0.0  # Integral gain
var kd: float = 0.0  # Derivative gain

var integral: float = 0.0
var last_error: float = 0.0
var integral_limit: float = 10.0  # Anti-windup limit

func _init(p: float = 1.0, i: float = 0.0, d: float = 0.0):
	kp = p
	ki = i
	kd = d

func update(error: float, delta: float) -> float:
	"""
	Calculate control output based on error
	error = desired_value - current_value
	"""

	# Proportional term
	var p_term = kp * error

	# Integral term (with anti-windup)
	integral += error * delta
	integral = clamp(integral, -integral_limit, integral_limit)
	var i_term = ki * integral

	# Derivative term
	var derivative = (error - last_error) / delta if delta > 0 else 0.0
	var d_term = kd * derivative

	last_error = error

	return p_term + i_term + d_term

func reset():
	"""Reset controller state"""
	integral = 0.0
	last_error = 0.0

func set_gains(p: float, i: float, d: float):
	"""Update PID gains"""
	kp = p
	ki = i
	kd = d
