# Engine controls via InputMap (keyboard + Xbox, etc.)
extends AircraftModule
class_name AircraftModule_ControlEngine

@export var RestrictEngineToTag: bool = false
@export var SearchTag: String = ""
@export var ControlActive: bool = true

@export var ThrottleRate: float = 0.6        # power change per second when holding up/down
@export var UseAbsoluteThrottle: bool = true  # if true, RT can set absolute throttle 0..1
@export var AbsoluteSmoothing: float = 6.0    # higher = quicker to RT value

var engine_modules: Array = []
var target_power: float = 0.0  # 0..1

func _ready() -> void:
	# We poll every frame instead of using event callbacks.
	ReceiveInput = false

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node
	if RestrictEngineToTag:
		engine_modules = aircraft.find_modules_by_type_and_tag("engine", SearchTag)
	else:
		engine_modules = aircraft.find_modules_by_type("engine")
	print("engines found: %s" % str(engine_modules))

func _physics_process(delta: float) -> void:
	if not ControlActive or engine_modules.is_empty():
		return

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

	# Start/stop
	if Input.is_action_just_pressed("engine_start"):
		send_to_engines("engine_start")
	if Input.is_action_just_pressed("engine_stop"):
		send_to_engines("engine_stop")

	# Apply power
	send_to_engines("engine_set_power", [target_power])

func receive_input(_event: InputEvent) -> void:
	# Polling mode; keep to satisfy the aircraft loop if it calls us.
	pass

func send_to_engines(method_name: String, arguments: Array = []) -> void:
	for engine in engine_modules:
		engine.callv(method_name, arguments)
