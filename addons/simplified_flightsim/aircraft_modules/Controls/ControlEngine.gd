# Engine controls via InputMap (keyboard + Xbox, etc.)
extends AircraftModule
class_name AircraftModule_ControlEngine

@export var RestrictEngineToTag: bool = false
@export var SearchTag: String = ""
@export var ControlActive: bool = true

@export var ThrottleRate: float = 0.6        # power change per second when holding up/down
@export var UseAbsoluteThrottle: bool = true  # if true, RT can set absolute throttle 0..1
@export var AbsoluteSmoothing: float = 6.0    # higher = quicker to RT value
@export var AutoStartPowerLimit: float = 1.0  # caps throttle during auto-start; 1.0 keeps old behavior
@export var AutoStartLimitRequiresThrottleRelease: bool = false

var engine_modules: Array = []
var target_power: float = 0.0  # 0..1
var _auto_start_power_limited: bool = false

func _ready() -> void:
	# We poll every frame instead of using event callbacks.
	ReceiveInput = false

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node
	if RestrictEngineToTag:
		engine_modules = aircraft.find_modules_by_type_and_tag("engine", SearchTag)
	else:
		engine_modules = aircraft.find_modules_by_type("engine")
	pass

func _physics_process(delta: float) -> void:
	if not ControlActive or engine_modules.is_empty():
		return
		
	# If controls are disabled by an external system (e.g., catapult), do nothing.
	if is_instance_valid(aircraft) and aircraft.has_meta("controls_disabled"):
		return

	# Store previous power for comparison
	var previous_power = target_power

	# Incremental throttle (e.g., D-pad up/down or keys)
	var up: float = Input.get_action_strength("throttle_up")
	var down: float = Input.get_action_strength("throttle_down")
	var inc: float = (up - down) * ThrottleRate * delta
	target_power = clamp(target_power + inc, 0.0, 1.0)

	# Absolute throttle (e.g., RT trigger mapped to 0..1)
	if UseAbsoluteThrottle:
		var abs_throttle: float = Input.get_action_strength("throttle_abs")
		if abs_throttle > 0.01:
			var t: float = clamp(AbsoluteSmoothing * delta, 0.0, 1.0)
			target_power = lerp(target_power, abs_throttle, t)

	# Automatic engine start/stop based on throttle
	handle_automatic_engine_control(previous_power)
	_apply_auto_start_power_limit()

	# Apply power
	send_to_engines("engine_set_power", [target_power])

func handle_automatic_engine_control(previous_power: float):
	"""Automatically start/stop engines based on throttle position"""
	# Check if any engine is currently working
	var any_engine_working := _any_engine_working()
	
	# Start engines if throttle increased from 0 and engines are stopped
	if target_power > 0.01 and not any_engine_working and previous_power <= 0.01:
		print("Auto-starting engines (throttle increased)")
		if AutoStartPowerLimit < 0.999:
			target_power = minf(target_power, clampf(AutoStartPowerLimit, 0.0, 1.0))
			_auto_start_power_limited = true
		send_to_engines("engine_start")
	
	# Stop engines if throttle reached 0 and engines are running
	elif target_power <= 0.01 and any_engine_working:
		print("Auto-stopping engines (throttle at 0)")
		_auto_start_power_limited = false
		send_to_engines("engine_stop")

func set_target_power(power: float) -> void:
	target_power = clamp(power, 0.0, 1.0)
	handle_automatic_engine_control(target_power - 0.01 if target_power > 0.01 else 0.0)
	_apply_auto_start_power_limit()
	send_to_engines("engine_set_power", [target_power])

func receive_input(_event: InputEvent) -> void:
	# Polling mode; keep to satisfy the aircraft loop if it calls us.
	pass

func send_to_engines(method_name: String, arguments: Array = []) -> void:
	for engine in engine_modules:
		engine.callv(method_name, arguments)

func _apply_auto_start_power_limit() -> void:
	if not _auto_start_power_limited:
		return

	var limit := clampf(AutoStartPowerLimit, 0.0, 1.0)
	if limit >= 0.999:
		_auto_start_power_limited = false
		return

	if _any_engine_working():
		var throttle_released := Input.get_action_strength("throttle_up") <= 0.01
		if UseAbsoluteThrottle:
			throttle_released = throttle_released and Input.get_action_strength("throttle_abs") <= 0.01
		if not AutoStartLimitRequiresThrottleRelease or throttle_released:
			_auto_start_power_limited = false
			return

	target_power = minf(target_power, limit)

func _any_engine_working() -> bool:
	for engine in engine_modules:
		if engine.is_engine_working:
			return true
	return false
