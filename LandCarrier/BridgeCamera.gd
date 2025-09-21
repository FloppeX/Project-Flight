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
		print("[BridgeCamera] Tried aircraft_path: ", aircraft_path, " -> ", aircraft)
	
	if not aircraft:
		aircraft = get_tree().get_first_node_in_group("aircraft")
		print("[BridgeCamera] Tried aircraft group search -> ", aircraft)
	
	# If still no aircraft, try broader search
	if not aircraft:
		var all_aircraft = get_tree().get_nodes_in_group("aircraft")
		print("[BridgeCamera] All aircraft in group: ", all_aircraft.size())
		for i in range(all_aircraft.size()):
			print("[BridgeCamera] - Aircraft[", i, "]: ", all_aircraft[i].name)
		if all_aircraft.size() > 0:
			aircraft = all_aircraft[0]
	
	# Create camera if it doesn't exist
	setup_camera()
	
	print("[BridgeCamera] Bridge camera initialized at: ", global_position)
	print("[BridgeCamera] Aircraft found: ", aircraft.name if aircraft else "NONE")
	print("[BridgeCamera] Camera found: ", bridge_camera.name if bridge_camera else "NONE")
	print("[BridgeCamera] Tracking enabled: ", enable_tracking)

func setup_camera():
	# Look for the specific CameraBridge child
	print("[BridgeCamera] Looking for CameraBridge child...")
	print("[BridgeCamera] Children count: ", get_children().size())
	
	# Try direct name search first
	bridge_camera = get_node_or_null("CameraBridge") as Camera3D
	if bridge_camera:
		print("[BridgeCamera] Found CameraBridge by name: ", bridge_camera.name)
	else:
		# Fallback to searching all children
		for child in get_children():
			print("[BridgeCamera] Child: ", child.name, " (", child.get_class(), ")")
			if child is Camera3D:
				bridge_camera = child
				print("[BridgeCamera] Found Camera3D child: ", child.name)
				break
	
	if bridge_camera:
		print("[BridgeCamera] Using bridge camera: ", bridge_camera.name)
		print("[BridgeCamera] Camera position: ", bridge_camera.position)
	else:
		print("[BridgeCamera] ERROR: No Camera3D found as child!")

func _process(delta):
	# Safety check - if we're a duplicate instance without children, disable ourselves
	if get_children().size() == 0 and bridge_camera == null:
		# We're probably a duplicate instance - disable processing
		set_process(false)
		print("[BridgeCamera] Disabling duplicate instance with no children")
		return
	
	# Try to re-find aircraft if we lost the reference
	if not aircraft:
		aircraft = get_tree().get_first_node_in_group("aircraft")
		if aircraft:
			print("[BridgeCamera] Re-found aircraft: ", aircraft.name)
		else:
			# Try alternative search methods
			var all_nodes = get_tree().current_scene.get_children()
			for node in all_nodes:
				if node.name == "CompleteFighterJet" or node.is_in_group("aircraft"):
					aircraft = node
					print("[BridgeCamera] Found aircraft by direct search: ", node.name)
					break
	
	# Try to find camera if we don't have it (but only a few times)
	if not bridge_camera:
		if setup_attempts < 3:
			setup_attempts += 1
			print("[BridgeCamera] Camera is null - calling setup_camera() (attempt ", setup_attempts, ")")
			setup_camera()
			print("[BridgeCamera] After setup_camera() - Camera: ", bridge_camera != null)
		else:
			# After 3 attempts, stop trying and disable processing
			print("[BridgeCamera] Failed to find camera after 3 attempts - disabling")
			set_process(false)
			return
	
	if not aircraft or not bridge_camera or not enable_tracking:
		if randf() < 0.01:  # Print occasionally
			print("[BridgeCamera] Not tracking - Aircraft: ", aircraft != null, " Camera: ", bridge_camera != null, " Enabled: ", enable_tracking)
			if not aircraft:
				var all_aircraft = get_tree().get_nodes_in_group("aircraft")
				print("[BridgeCamera] Aircraft search: found ", all_aircraft.size(), " aircraft in group")
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
	
	# Debug output (can be removed later)
	if randf() < 0.05:  # Only print occasionally
		var distance = global_position.distance_to(aircraft.global_position)
		print("[BridgeCamera] Tracking aircraft - Distance: ", int(distance), "m, Pitch: ", int(rad_to_deg(new_pitch)), "°")
		print("[BridgeCamera] Bridge pos: ", global_position, " Aircraft pos: ", aircraft.global_position)

func get_camera() -> Camera3D:
	return bridge_camera

func set_aircraft_reference(aircraft_node: Node3D):
	print("[BridgeCamera] Attempting to set aircraft reference to: ", aircraft_node.name if aircraft_node else "NULL INPUT")
	aircraft = aircraft_node
	print("[BridgeCamera] Aircraft reference after assignment: ", aircraft.name if aircraft else "ASSIGNMENT FAILED")
	
	# Verify the reference is working
	if aircraft and aircraft.has_method("get_global_position"):
		print("[BridgeCamera] Aircraft position test: ", aircraft.global_position)
	else:
		print("[BridgeCamera] Aircraft position test FAILED")

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
