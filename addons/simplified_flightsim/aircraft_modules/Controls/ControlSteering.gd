extends AircraftModule
class_name AircraftModule_ControlSteering

@export var ControlActive: bool = true
@export var input_curve: float = 1.8   # 1.0 = linear; >1 soft near center
@export var deadzone: float = 0.05

var steering_module: Node = null
var simple_aero: Node = null   # Add this line
var aero_has_cmds := false

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node

	# Grab the steering module provided by the addon
	var list = aircraft.find_modules_by_type("steering")
	if list and list.size() > 0:
		steering_module = list.pop_front()
	print("steering found: %s" % str(steering_module))
	simple_aero = aircraft.get_node_or_null("SimpleAero")
	if simple_aero == null:
		simple_aero = aircraft.find_child("SimpleAero", true, false)

func _physics_process(_delta: float) -> void:
	if (not ControlActive) or (steering_module == null):
		return

	# Raw inputs (actions must exist in InputMap)
	var roll_raw  := Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")
	var pitch_raw := Input.get_action_strength("pitch_up")   - Input.get_action_strength("pitch_down")
	var yaw_raw   := Input.get_action_strength("yaw_left")   - Input.get_action_strength("yaw_right")

	# Shape them
	var roll  := _shape_input(roll_raw)
	var pitch := _shape_input(pitch_raw)
	var yaw   := _shape_input(yaw_raw)

	# Drive control surfaces (addon uses z=roll, x=pitch, y=yaw)
	steering_module.set_z(roll)
	steering_module.set_x(pitch)
	steering_module.set_y(yaw)

	# Feed the same to SimpleAero if present and compatible
	simple_aero.pitch_input = pitch
	simple_aero.roll_input = -roll
	simple_aero.yaw_input = yaw

func _shape_input(v: float) -> float:
	if absf(v) < deadzone:
		return 0.0
	var s := (absf(v) - deadzone) / (1.0 - deadzone)
	if input_curve != 1.0:
		s = pow(s, input_curve)
	return s * signf(v)

func _node_has_properties(n: Object, names: Array) -> bool:
	var plist := n.get_property_list()
	var have := {}
	for p in plist:
		have[p.name] = true
	for name in names:
		if not have.has(name):
			return false
	return true
