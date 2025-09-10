extends Node3D

# =============================================================================
# GROUND COLLISION TEST - Check if ground has collision shapes
# =============================================================================

var land_carrier: RigidBody3D
var ground_collision_found = false

func _ready():
	print("=== Ground Collision Test ===")
	print("Testing if ground has collision shapes...")
	
	# Get the land carrier
	land_carrier = $LandCarrier
	
	if land_carrier:
		print("✅ Carrier found!")
		print("Carrier position: ", land_carrier.global_position)
		print("Carrier mass: ", land_carrier.mass)
		
		# Check for ground collision shapes
		check_ground_collision()
		
		# Set up collision monitoring
		land_carrier.contact_monitor = true
		land_carrier.max_contacts_reported = 10
		land_carrier.body_entered.connect(_on_carrier_body_entered)
		land_carrier.body_exited.connect(_on_carrier_body_exited)
		
		# Start monitoring
		print("Monitoring carrier collisions...")
	else:
		print("❌ No carrier found!")

func check_ground_collision():
	print("\n--- Checking for Ground Collision Shapes ---")
	
	# Look for StaticBody3D nodes (ground)
	var static_bodies = get_tree().get_nodes_in_group("ground")
	if static_bodies.is_empty():
		print("❌ No ground StaticBody3D found in 'ground' group")
		
		# Look for any StaticBody3D
		var all_static_bodies = []
		find_static_bodies_recursive(get_tree().current_scene, all_static_bodies)
		
		if all_static_bodies.is_empty():
			print("❌ No StaticBody3D found anywhere in scene!")
			print("This means there's no ground collision for the carrier to hit!")
		else:
			print("Found StaticBody3D nodes:")
			for body in all_static_bodies:
				print("  - ", body.name, " at ", body.global_position)
				check_collision_shapes(body)
	else:
		print("✅ Found ground StaticBody3D nodes:")
		for body in static_bodies:
			print("  - ", body.name, " at ", body.global_position)
			check_collision_shapes(body)

func find_static_bodies_recursive(node: Node, result: Array):
	if node is StaticBody3D:
		result.append(node)
	
	for child in node.get_children():
		find_static_bodies_recursive(child, result)

func check_collision_shapes(body: StaticBody3D):
	print("    Checking collision shapes for ", body.name)
	
	var collision_shapes = []
	find_collision_shapes_recursive(body, collision_shapes)
	
	if collision_shapes.is_empty():
		print("    ❌ No CollisionShape3D found!")
	else:
		print("    ✅ Found ", collision_shapes.size(), " collision shapes:")
		for shape in collision_shapes:
			print("      - ", shape.name, " shape: ", shape.shape)

func find_collision_shapes_recursive(node: Node, result: Array):
	if node is CollisionShape3D:
		result.append(node)
	
	for child in node.get_children():
		find_collision_shapes_recursive(child, result)

func _on_carrier_body_entered(body):
	print("🎯 Carrier collided with: ", body.name)
	ground_collision_found = true

func _on_carrier_body_exited(body):
	print("📤 Carrier stopped colliding with: ", body.name)

func _process(delta):
	if land_carrier and Engine.get_process_frames() % 60 == 0:
		print("Carrier Y: ", land_carrier.global_position.y, " Velocity Y: ", land_carrier.linear_velocity.y)
		
		if land_carrier.global_position.y < -10:
			print("⚠️ Carrier fell below Y=-10, no ground collision detected!")
			if not ground_collision_found:
				print("❌ CONFIRMED: No ground collision shapes found!")
				print("The carrier is falling through the ground because there's no collision to stop it!")

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Manual Test ---")
		if land_carrier:
			# Move carrier to a known position
			land_carrier.global_position = Vector3(0, 10, 0)
			land_carrier.linear_velocity = Vector3.ZERO
			land_carrier.angular_velocity = Vector3.ZERO
			print("Carrier moved to Y=10, should fall and land on terrain")
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
