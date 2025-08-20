extends AircraftModule
class_name AircraftModule_ControlSteering

@export var ControlActive: bool = true
@export var input_curve: float = 1.8   # 1.0 = linear; >1 soft near center
@export var deadzone: float = 0.05

var steering_module: Node = null
var aero_forces: Node = null   # optional; will point to Aircraft/AeroForces if present
var _aero_has_cmds := false    # cache whether cmd_* properties exist

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node

	# Grab the steering module provided by the addon
	var list = aircraft.find_modules_by_type("steering")
	if list and list.size() > 0:
		steering_module = list.pop_front()
	print("steering found: %s" % str(steering_module))

	# Try to find a node named "AeroForces" under the Aircraft (optional)
	aero_forces = aircraft.get_node_or_null("AeroForces")
	if aero_forces == null:
		aero_forces = aircraft.find_child("AeroForces", true, false)

	if aero_forces:
		print("AeroForces found at: %s" % aero_forces.get_path())
		# Detect if it exposes cmd_* properties
		_aero_has_cmds = _node_has_properties(aero_forces, ["cmd_pitch", "cmd_roll", "cmd_yaw"])

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

	# Feed the same to AeroForces if present and compatible
	if aero_forces and _aero_has_cmds:
		aero_forces.set("cmd_pitch", pitch)
		aero_forces.set("cmd_roll",  -roll)
		aero_forces.set("cmd_yaw",   yaw)

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

