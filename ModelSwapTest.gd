extends Node3D

# =============================================================================
# MODEL SWAP TEST
# =============================================================================
# Simple test to verify the new model integration works
# =============================================================================

var land_carrier: LandCarrier

func _ready():
	# Get reference to the land carrier
	land_carrier = $LandCarrier
	
	print("=== Model Swap Test ===")
	print("Testing new Land Carrier model integration...")
	
	# Test model references
	test_model_references()
	
	# Test basic movement
	test_basic_movement()

func test_model_references():
	"""Test that all model references are working"""
	print("\n--- Testing Model References ---")
	
	if land_carrier.carrier_model:
		print("✅ Carrier model loaded: ", land_carrier.carrier_model.name)
	else:
		print("❌ Carrier model not found")
	
	if land_carrier.treads_model:
		print("✅ Treads model loaded: ", land_carrier.treads_model.name)
	else:
		print("❌ Treads model not found")
	
	if land_carrier.tread_helper:
		print("✅ Tread helper loaded: ", land_carrier.tread_helper.name)
		print("   Tread positions: ", land_carrier.tread_helper.get_tread_positions().size())
	else:
		print("❌ Tread helper not found")

func test_basic_movement():
	"""Test basic carrier movement"""
	print("\n--- Testing Basic Movement ---")
	
	# Test setting target position
	var test_position = global_position + Vector3(50, 0, 0)
	land_carrier.set_target_position(test_position)
	print("✅ Set target position: ", test_position)
	
	# Wait a bit then test rotation
	await get_tree().create_timer(2.0).timeout
	land_carrier.set_target_rotation(PI/2)
	print("✅ Set target rotation: 90 degrees")

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Manual Test ---")
		var random_pos = global_position + Vector3(randf_range(-100, 100), 0, randf_range(-100, 100))
		land_carrier.set_target_position(random_pos)
		print("Moving to random position: ", random_pos)
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
