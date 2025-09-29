extends Node3D
class_name BridgeCamera

# =============================================================================
# BRIDGE CAMERA - Tracks aircraft from carrier bridge
# =============================================================================
# Node3D rotates horizontally (yaw) to follow aircraft
# Camera child rotates vertically (pitch) to look at aircraft
# =============================================================================

@export var aircraft_path: NodePath
@export var camera_distance: float = 3.0  # Distance from center to camera
@export var camera_height: float = 1.0    # Height offset for camera
@export var tracking_smoothing: float = 2.0  # How smooth the tracking is
@export var pitch_limit_deg: float = 60.0   # Max up/down angle
@export var enable_tracking: bool = true    # Can disable for manual control

var aircraft: Node3D
var bridge_camera: Camera3D
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var setup_attempts: int = 0

func _ready():
	# Initialize the bridge camera system
	initialize_bridge_camera()

func initialize_bridge_camera():
	# Add to carrier_cam group so camera controller can find us
	add_to_group("carrier_cam")

	# Find aircraft (try multiple methods)
	if aircraft_path != NodePath():
		aircraft = get_node_or_null(aircraft_path)

	if not aircraft:
		aircraft = get_tree().get_first_node_in_group("aircraft")

	# If still no aircraft, try broader search
	if not aircraft:
		var all_aircraft = get_tree().get_nodes_in_group("aircraft")
		if all_aircraft.size() > 0:
			aircraft = all_aircraft[0]

	# Create camera if it doesn't exist
	setup_camera()

func setup_camera():
	# Look for the specific CameraBridge child

	# Try direct name search first
	bridge_camera = get_node_or_null("CameraBridge") as Camera3D
	if bridge_camera:
		pass
	else:
		# Fallback to searching all children
		for child in get_children():
			if child is Camera3D:
				bridge_camera = child
				break

func _process(delta):
	# Safety check - if we're a duplicate instance without children, disable ourselves
	if get_children().size() == 0 and bridge_camera == null:
		# We're probably a duplicate instance - disable processing
		set_process(false)
		return

	# Try to re-find aircraft if we lost the reference
	if not aircraft:
		aircraft = get_tree().get_first_node_in_group("aircraft")
		if not aircraft:
			# Try alternative search methods
			var all_nodes = get_tree().current_scene.get_children()
			for node in all_nodes:
				if node.name == "CompleteFighterJet" or node.is_in_group("aircraft"):
					aircraft = node
					break

	# Try to find camera if we don't have it (but only a few times)
	if not bridge_camera:
		if setup_attempts < 3:
			setup_attempts += 1
			setup_camera()
		else:
			# After 3 attempts, stop trying and disable processing
			set_process(false)
			return

	if not aircraft or not bridge_camera or not enable_tracking:
		return

	update_tracking(delta)

func update_tracking(delta):
	# Use look_at for horizontal tracking (Node3D holder)
	var aircraft_pos = aircraft.global_position
	var holder_pos = global_position

	# Create a horizontal target (same Y level as holder)
	var horizontal_target = Vector3(aircraft_pos.x, holder_pos.y, aircraft_pos.z)

	# Make the holder look at the aircraft horizontally
	look_at(horizontal_target, Vector3.UP)
	# Rotate 180 degrees to face the correct direction
	rotation.y += PI

	# Now handle vertical pitch for the camera
	var to_aircraft = aircraft_pos - holder_pos
	var distance_2d = Vector2(to_aircraft.x, to_aircraft.z).length()
	var height_difference = to_aircraft.y
	target_pitch = atan2(height_difference, distance_2d)
	target_pitch = clamp(target_pitch, deg_to_rad(-pitch_limit_deg), deg_to_rad(pitch_limit_deg))

	# Smooth the pitch
	var current_pitch = bridge_camera.rotation.x
	var new_pitch = lerp_angle(current_pitch, target_pitch, tracking_smoothing * delta)
	bridge_camera.rotation.x = new_pitch

func get_camera() -> Camera3D:
	return bridge_camera

func set_aircraft_reference(aircraft_node: Node3D):
	aircraft = aircraft_node

func set_tracking_enabled(enabled: bool):
	enable_tracking = enabled

func manual_rotate(yaw_delta: float, pitch_delta: float):
	# Allow manual control when tracking is disabled
	if enable_tracking:
		return

	rotation.y += yaw_delta
	if bridge_camera:
		bridge_camera.rotation.x = clamp(
			bridge_camera.rotation.x + pitch_delta,
			deg_to_rad(-pitch_limit_deg),
			deg_to_rad(pitch_limit_deg)
		)
