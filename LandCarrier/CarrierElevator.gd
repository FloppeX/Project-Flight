extends Node3D
class_name CarrierElevator

# Simple elevator system for carrier hangar operations
# Moves platform up/down and manages covers

signal elevator_at_top
signal elevator_at_bottom
signal covers_closed
signal covers_opened

@export var platform_size: Vector3 = Vector3(20, 1, 20)
@export var cover_size: Vector3 = Vector3(20, 0.2, 10)
@export var shaft_depth: float = 10.0
@export var move_speed: float = 2.0
@export var cover_slide_speed: float = 3.0

enum ElevatorState {
	AT_TOP,
	MOVING_DOWN,
	AT_BOTTOM,
	COVERS_CLOSING,
	COVERS_CLOSED,
	COVERS_OPENING,
	MOVING_UP
}

var current_state: ElevatorState = ElevatorState.AT_TOP
var platform: Node3D
var left_cover: Node3D
var right_cover: Node3D
var covers_started_closing: bool = false
var covers_started_opening: bool = false

# Animation targets
var platform_target_y: float = 0.0
var left_cover_target_x: float = 0.0
var right_cover_target_x: float = 0.0

func _ready():
	print("Setting up elevator system...")
	create_elevator_components()
	set_initial_state()
	print("Elevator setup complete.")

func create_elevator_components():
	# Create platform
	platform = create_platform()
	add_child(platform)
	
	# Create covers
	left_cover = create_cover("LeftCover")
	right_cover = create_cover("RightCover")
	add_child(left_cover)
	add_child(right_cover)

func create_platform() -> Node3D:
	var platform_node = Node3D.new()
	platform_node.name = "Platform"
	
	# Create platform mesh
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = platform_size
	mesh_instance.mesh = box_mesh
	
	# Create platform material - black elevator
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.1, 0.1, 1.0)
	material.metallic = 0.3
	material.roughness = 0.7
	mesh_instance.material_override = material
	
	platform_node.add_child(mesh_instance)
	
	# Position platform so its top surface is flush with carrier deck
	platform_node.position.y = -platform_size.y / 2.0
	
	return platform_node

func create_cover(name: String) -> Node3D:
	var cover_node = Node3D.new()
	cover_node.name = name
	
	# Create cover mesh
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = cover_size
	mesh_instance.mesh = box_mesh
	
	# Create cover material - gray covers
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5, 1.0)
	material.metallic = 0.2
	material.roughness = 0.6
	mesh_instance.material_override = material
	
	cover_node.add_child(mesh_instance)
	
	# Rotate covers 90 degrees so their long sides face each other
	cover_node.rotation.y = PI / 2
	
	# Position covers so their top surface is flush with carrier deck
	cover_node.position.y = -cover_size.y / 2.0
	
	return cover_node

func set_initial_state():
	# Platform starts at top (flush with deck)
	platform.position.y = -platform_size.y / 2.0
	platform_target_y = -platform_size.y / 2.0
	
	# Covers start open (retracted)
	left_cover.position.x = -15.0
	right_cover.position.x = 15.0
	left_cover_target_x = left_cover.position.x
	right_cover_target_x = right_cover.position.x
	
	current_state = ElevatorState.AT_TOP
	print("Elevator initialized at top")

func _physics_process(delta: float):
	animate_platform(delta)
	animate_covers(delta)
	check_state_transitions()

	pass

func animate_platform(delta: float):
	if abs(platform.position.y - platform_target_y) > 0.01:
		var direction = sign(platform_target_y - platform.position.y)
		platform.position.y += direction * move_speed * delta
		platform.position.y = clamp(platform.position.y, -shaft_depth, -platform_size.y / 2.0)
		# Debug: Print movement occasionally (disabled for cleaner output)
		# if Engine.get_process_frames() % 30 == 0:  # Every half second at 60fps
		#	print("[Elevator] Moving - Current Y: ", platform.position.y, " Target Y: ", platform_target_y, " State: ", current_state)
	else:
		platform.position.y = platform_target_y

func animate_covers(delta: float):
	# Left cover
	if abs(left_cover.position.x - left_cover_target_x) > 0.01:
		var direction = sign(left_cover_target_x - left_cover.position.x)
		left_cover.position.x += direction * cover_slide_speed * delta
	else:
		left_cover.position.x = left_cover_target_x
	
	# Right cover
	if abs(right_cover.position.x - right_cover_target_x) > 0.01:
		var direction = sign(right_cover_target_x - right_cover.position.x)
		right_cover.position.x += direction * cover_slide_speed * delta
	else:
		right_cover.position.x = right_cover_target_x

func move_platform_down():
	current_state = ElevatorState.MOVING_DOWN
	platform_target_y = -shaft_depth
	covers_started_closing = false
	covers_started_opening = false

func move_platform_up():
	current_state = ElevatorState.MOVING_UP
	platform_target_y = -platform_size.y / 2.0
	covers_started_closing = false
	covers_started_opening = false

func close_covers():
	current_state = ElevatorState.COVERS_CLOSING
	left_cover_target_x = -5.0
	right_cover_target_x = 5.0

func open_covers():
	current_state = ElevatorState.COVERS_OPENING
	left_cover_target_x = -15.0
	right_cover_target_x = 15.0

func check_state_transitions():
	match current_state:
		ElevatorState.MOVING_DOWN:
			# Start closing covers when platform has descended 3 meters
			if platform.position.y <= -3.0 - platform_size.y / 2.0 and not covers_started_closing:
				close_covers()
				covers_started_closing = true

			var target_bottom = -shaft_depth + 0.1  # Simple: -10 + 0.1 = -9.9
			if platform.position.y <= target_bottom:
				current_state = ElevatorState.AT_BOTTOM
				emit_signal("elevator_at_bottom")
		
		ElevatorState.COVERS_CLOSING:
			if covers_are_closed():
				current_state = ElevatorState.COVERS_CLOSED
				emit_signal("covers_closed")
		
		ElevatorState.COVERS_CLOSED:
			# Check if we've reached bottom while covers were closing
			var target_bottom = -shaft_depth + 0.1  # -9.9
			if platform.position.y <= target_bottom and current_state != ElevatorState.AT_BOTTOM:
				current_state = ElevatorState.AT_BOTTOM
				emit_signal("elevator_at_bottom")
		
		ElevatorState.COVERS_OPENING:
			if covers_are_open():
				current_state = ElevatorState.AT_TOP
				emit_signal("covers_opened")
		
		ElevatorState.MOVING_UP:
			# Start opening covers when platform is 8.5 meters from top
			if platform.position.y >= -8.5 - platform_size.y / 2.0 and not covers_started_opening:
				open_covers()
				covers_started_opening = true
			
			# Only reach top if covers are fully open
			if covers_are_open() and platform.position.y >= -platform_size.y / 2.0 - 0.1:
				current_state = ElevatorState.AT_TOP
				emit_signal("elevator_at_top")

func covers_are_closed() -> bool:
	var left_closed = abs(left_cover.position.x - (-5.0)) < 0.1
	var right_closed = abs(right_cover.position.x - (5.0)) < 0.1
	return left_closed and right_closed

func covers_are_open() -> bool:
	var left_open = abs(left_cover.position.x - (-15.0)) < 0.1
	var right_open = abs(right_cover.position.x - (15.0)) < 0.1
	return left_open and right_open

func get_status() -> Dictionary:
	return {
		"state": current_state,
		"platform_y": platform.position.y,
		"platform_target_y": platform_target_y,
		"covers_closed": covers_are_closed(),
		"covers_open": covers_are_open()
	}
