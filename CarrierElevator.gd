class_name CarrierElevator
extends Node3D

# =============================================================================
# CARRIER ELEVATOR SYSTEM
# =============================================================================
# Manages the elevator platform and sliding covers for the carrier
# =============================================================================

# Elevator Properties
@export var platform_size: Vector3 = Vector3(20, 1, 20)  # 20x20x1m platform
@export var cover_size: Vector3 = Vector3(20, 0.2, 10)   # 20x10x0.2m covers
@export var shaft_depth: float = 10.0  # How far down the platform goes
@export var move_speed: float = 2.0    # m/s movement speed
@export var cover_slide_speed: float = 3.0  # m/s cover sliding speed

# State
enum ElevatorState {
	AT_TOP,           # Platform at flight deck level
	MOVING_DOWN,      # Platform moving down
	AT_BOTTOM,        # Platform at hangar level
	COVERS_CLOSING,   # Covers sliding in
	COVERS_CLOSED,    # Covers fully closed
	COVERS_OPENING,   # Covers sliding out
	MOVING_UP         # Platform moving up
}

var current_state: ElevatorState = ElevatorState.AT_TOP
var platform: Node3D
var left_cover: Node3D
var right_cover: Node3D
var carrier: Node3D
var covers_started_closing: bool = false
var covers_started_opening: bool = false

# Animation
var platform_target_y: float = 0.0
var left_cover_target_x: float = 0.0
var right_cover_target_x: float = 0.0

# Signals
signal elevator_at_top
signal elevator_at_bottom
signal covers_closed
signal covers_opened
signal aircraft_spawned(aircraft)

func setup(carrier_node: Node3D):
	"""Initialize the elevator system"""
	carrier = carrier_node
	print("Setting up elevator system...")
	create_elevator_components()
	set_initial_state()
	print("Elevator setup complete.")
	print("Platform global position: ", platform.global_position)
	print("Left cover global position: ", left_cover.global_position)
	print("Right cover global position: ", right_cover.global_position)
	print("Carrier global position: ", carrier.global_position)

func create_elevator_components():
	"""Create the platform and cover components"""
	# Create platform
	platform = create_platform()
	add_child(platform)
	
	# Create covers
	left_cover = create_cover("LeftCover")
	right_cover = create_cover("RightCover")
	add_child(left_cover)
	add_child(right_cover)
	
	print("Elevator components created")

func create_platform() -> Node3D:
	"""Create the elevator platform"""
	var platform_node = Node3D.new()
	platform_node.name = "Platform"
	
	# Create platform mesh
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = platform_size
	mesh_instance.mesh = box_mesh
	
	# Create platform material - black elevator
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.1, 0.1, 1.0)  # Black
	material.metallic = 0.3
	material.roughness = 0.7
	material.emission = Color(0.0, 0.0, 0.0, 1.0)  # No glow
	mesh_instance.material_override = material
	
	platform_node.add_child(mesh_instance)
	
	# Add collision shape
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = platform_size
	collision_shape.shape = box_shape
	platform_node.add_child(collision_shape)
	
	# Position platform so its top surface is flush with carrier deck
	platform_node.position.y = -platform_size.y / 2.0  # -0.5m for 1m tall platform
	
	return platform_node

func create_cover(name: String) -> Node3D:
	"""Create a cover plate"""
	var cover_node = Node3D.new()
	cover_node.name = name
	
	# Create cover mesh
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = cover_size
	mesh_instance.mesh = box_mesh
	
	# Create cover material - gray covers
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5, 1.0)  # Gray for both covers
	material.metallic = 0.2
	material.roughness = 0.6
	material.emission = Color(0.0, 0.0, 0.0, 1.0)  # No glow
	mesh_instance.material_override = material
	
	cover_node.add_child(mesh_instance)
	
	# Add collision shape
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = cover_size
	collision_shape.shape = box_shape
	cover_node.add_child(collision_shape)
	
	# Rotate covers 90 degrees so their long sides face each other
	cover_node.rotation.y = PI / 2
	
	# Position covers so their top surface is flush with carrier deck
	cover_node.position.y = -cover_size.y / 2.0  # -0.1m for 0.2m tall covers
	
	return cover_node

func set_initial_state():
	"""Set the initial state of the elevator"""
	# Platform starts at top (flush with deck)
	platform.position.y = -platform_size.y / 2.0  # -0.5m
	platform_target_y = -platform_size.y / 2.0
	
	# Covers start open (retracted) - positioned next to the 20x20m area
	# With 90-degree rotation, covers are 20x10x0.2, so we need to position them
	# so their 10m width is what slides together
	left_cover.position.x = -15.0  # Positioned next to the area
	right_cover.position.x = 15.0  # Positioned next to the area
	left_cover_target_x = left_cover.position.x
	right_cover_target_x = right_cover.position.x
	
	current_state = ElevatorState.AT_TOP
	print("Elevator initialized at top")

func update(delta: float):
	"""Update elevator animation"""
	animate_platform(delta)
	animate_covers(delta)
	check_state_transitions()

func animate_platform(delta: float):
	"""Animate platform movement"""
	if abs(platform.position.y - platform_target_y) > 0.01:
		var direction = sign(platform_target_y - platform.position.y)
		platform.position.y += direction * move_speed * delta
		platform.position.y = clamp(platform.position.y, -shaft_depth, 0.0)
	else:
		platform.position.y = platform_target_y

func animate_covers(delta: float):
	"""Animate cover sliding"""
	# Left cover (sliding along X-axis towards center)
	if abs(left_cover.position.x - left_cover_target_x) > 0.01:
		var direction = sign(left_cover_target_x - left_cover.position.x)
		left_cover.position.x += direction * cover_slide_speed * delta
	else:
		left_cover.position.x = left_cover_target_x
	
	# Right cover (sliding along X-axis towards center)
	if abs(right_cover.position.x - right_cover_target_x) > 0.01:
		var direction = sign(right_cover_target_x - right_cover.position.x)
		right_cover.position.x += direction * cover_slide_speed * delta
	else:
		right_cover.position.x = right_cover_target_x

func start_elevator_sequence():
	"""Start the full elevator sequence"""
	if current_state != ElevatorState.AT_TOP:
		print("Elevator not ready - currently in state: ", current_state)
		return
	
	print("Starting elevator sequence...")
	covers_started_closing = false  # Reset the flags
	covers_started_opening = false
	move_platform_down()

func reverse_elevator_sequence():
	"""Reverse the elevator sequence"""
	# Reset flags when starting any sequence
	covers_started_closing = false
	covers_started_opening = false
	
	match current_state:
		ElevatorState.AT_TOP:
			print("Already at top - starting down sequence")
			start_elevator_sequence()
		ElevatorState.MOVING_DOWN:
			print("Reversing - moving platform up")
			move_platform_up()
		ElevatorState.AT_BOTTOM:
			print("Reversing - opening covers")
			open_covers()
		ElevatorState.COVERS_CLOSING:
			print("Reversing - opening covers")
			open_covers()
		ElevatorState.COVERS_CLOSED:
			print("Reversing - opening covers")
			open_covers()
		ElevatorState.COVERS_OPENING:
			print("Reversing - closing covers")
			close_covers()
		ElevatorState.MOVING_UP:
			print("Reversing - moving platform down")
			move_platform_down()

func start_sequence():
	"""Alias for start_elevator_sequence"""
	start_elevator_sequence()

func move_platform_down():
	"""Move platform down to hangar level"""
	current_state = ElevatorState.MOVING_DOWN
	platform_target_y = -shaft_depth - platform_size.y / 2.0  # Account for platform height
	covers_started_closing = false  # Reset flag
	covers_started_opening = false  # Reset flag
	print("Moving platform down to hangar level")

func move_platform_up():
	"""Move platform up to flight deck level"""
	current_state = ElevatorState.MOVING_UP
	platform_target_y = -platform_size.y / 2.0  # Flush with deck
	covers_started_closing = false  # Reset flag
	covers_started_opening = false  # Reset flag
	print("Moving platform up to flight deck level")

func close_covers():
	"""Close the cover plates"""
	current_state = ElevatorState.COVERS_CLOSING
	# Covers travel 10 meters from their starting position
	left_cover_target_x = -15.0 + 10.0  # -5.0 (traveled 10m from -15.0)
	right_cover_target_x = 15.0 - 10.0  # 5.0 (traveled 10m from 15.0)
	print("Closing covers - traveling 10 meters")

func open_covers():
	"""Open the cover plates"""
	current_state = ElevatorState.COVERS_OPENING
	left_cover_target_x = -15.0   # Slide out to left (next to the area)
	right_cover_target_x = 15.0   # Slide out to right (next to the area)
	print("Opening covers")

func check_state_transitions():
	"""Check for state transitions based on animation completion"""
	match current_state:
		ElevatorState.MOVING_DOWN:
			# Start closing covers when platform has descended 3 meters
			if platform.position.y <= -3.0 - platform_size.y / 2.0 and not covers_started_closing:
				close_covers()
				covers_started_closing = true
			
			if platform.position.y <= -shaft_depth - platform_size.y / 2.0 + 0.1:
				current_state = ElevatorState.AT_BOTTOM
				print("Platform reached bottom")
		
		ElevatorState.COVERS_CLOSING:
			if covers_are_closed():
				current_state = ElevatorState.COVERS_CLOSED
				print("Covers closed")
				emit_signal("covers_closed")
		
		ElevatorState.COVERS_OPENING:
			if covers_are_open():
				current_state = ElevatorState.AT_TOP
				print("Covers opened")
				emit_signal("covers_opened")
		
		ElevatorState.MOVING_UP:
			# Start opening covers when platform is 8.5 meters from top
			if platform.position.y >= -8.5 - platform_size.y / 2.0 and not covers_started_opening:
				open_covers()
				covers_started_opening = true
			
			# Only reach top if covers are fully open
			if covers_are_open() and platform.position.y >= -platform_size.y / 2.0 - 0.1:
				current_state = ElevatorState.AT_TOP
				print("Platform reached top")
				emit_signal("elevator_at_top")

func covers_are_closed() -> bool:
	"""Check if covers are fully closed"""
	var left_closed = abs(left_cover.position.x - (-5.0)) < 0.1
	var right_closed = abs(right_cover.position.x - (5.0)) < 0.1
	return left_closed and right_closed

func covers_are_open() -> bool:
	"""Check if covers are fully open"""
	var left_open = abs(left_cover.position.x - (-15.0)) < 0.1
	var right_open = abs(right_cover.position.x - (15.0)) < 0.1
	return left_open and right_open

func spawn_aircraft_on_platform():
	"""Spawn an aircraft on the platform"""
	if carrier and carrier.has_method("get_hangar") and carrier.get_hangar():
		var hangar = carrier.get_hangar()
		var aircraft = hangar.spawn_aircraft(0)  # Spawn type 0 aircraft
		
		if aircraft:
			# Position aircraft on platform
			aircraft.global_position = platform.global_position + Vector3(0, 1, 0)
			print("Aircraft spawned on platform")
			emit_signal("aircraft_spawned", aircraft)
			
			# Start moving platform up after a delay
			await get_tree().create_timer(2.0).timeout
			move_platform_up()
		else:
			print("Failed to spawn aircraft")
	else:
		print("No hangar available for aircraft spawning - continuing sequence")
		# Continue the sequence even without aircraft spawning
		await get_tree().create_timer(2.0).timeout
		move_platform_up()

func get_status() -> Dictionary:
	"""Get elevator status"""
	return {
		"state": current_state,
		"platform_y": platform.position.y,
		"platform_target_y": platform_target_y,
		"covers_closed": covers_are_closed(),
		"covers_open": covers_are_open()
	}
