extends StaticBody3D
class_name CarrierTread

# Simple visual tread element - no physics, just follows the carrier
# The carrier will handle all positioning and movement

@export var tread_index: int = 0  # Which tread this is (0-5)
@export var carrier_offset: Vector3 = Vector3.ZERO  # Offset from carrier center

var carrier: Node3D = null

func _ready():
	# Find the carrier (parent or grandparent)
	carrier = get_parent()
	if carrier.name != "LandCarrier":
		carrier = carrier.get_parent()
	
	# Set up the offset based on tread index
	setup_tread_offset()

func setup_tread_offset():
	"""Set up the tread's offset from the carrier center based on its index"""
	# Define the 6 tread positions relative to carrier center (original positions)
	var tread_positions = [
		Vector3(-32, -32, -43),  # Tread 4 - Rear left
		Vector3(32, -32, -43),   # Tread 1 - Rear right
		Vector3(-32, -32, 0),    # Tread 5 - Middle left
		Vector3(32, -32, 0),     # Tread 2 - Middle right
		Vector3(32, -32, 43),    # Tread 3 - Front right
		Vector3(-32, -32, 43)    # Tread 6 - Front left
	]
	
	if tread_index < tread_positions.size():
		carrier_offset = tread_positions[tread_index]

func update_position():
	"""Update tread position to follow the carrier"""
	if carrier:
		# Position tread 32m below the carrier
		var tread_position = carrier.global_position + carrier_offset
		tread_position.y = carrier.global_position.y - 32.0  # 32m below carrier
		global_position = tread_position
