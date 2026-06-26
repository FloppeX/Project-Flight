extends AircraftModule
class_name AircraftModule_ControlFlaps

@export var ControlActive: bool = true
@export var FlapStep: float = 0.2   # how much each press/hold changes flap position per tick

var flaps_module: Node = null

func _ready() -> void:
	# We’re polling, not using events
	ReceiveInput = false

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node
	var found = aircraft.find_modules_by_type("flaps")
	if not found.is_empty():
		flaps_module = found.pop_front()
	pass

func _physics_process(delta: float) -> void:
	if (not ControlActive) or (flaps_module == null):
		return
	if _cockpit_interaction_consumed_this_press():
		return

	# Increment flaps down (B or gamepad button)
	if Input.is_action_pressed("flaps_down"):
		flaps_module.flap_increase_position(FlapStep)

	# Increment flaps up (G or another button)
	if Input.is_action_pressed("flaps_up"):
		flaps_module.flap_increase_position(-FlapStep)

func receive_input(_event: InputEvent) -> void:
	# Polling mode, keep stub for framework compatibility
	pass


func _cockpit_interaction_consumed_this_press() -> bool:
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	if not Input.is_action_pressed("flaps_down"):
		return false
	if not aircraft.has_meta("cockpit_interaction_consumed_physics_frame"):
		return false
	var consumed_frame := int(aircraft.get_meta("cockpit_interaction_consumed_physics_frame"))
	return Engine.get_physics_frames() - consumed_frame <= 1
