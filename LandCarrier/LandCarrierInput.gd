extends Node3D
class_name LandCarrierInput

# =============================================================================
# LAND CARRIER INPUT CONTROLS
# =============================================================================
# Simple input handler for Land Carrier movement and elevator control
# =============================================================================

@export var land_carrier: LandCarrier
@export var speed_increment: float = 10.0  # m/s speed change per key press
@export var max_speed: float = 100.0  # m/s maximum speed
@export var min_speed: float = 0.0   # m/s minimum speed
@export var enable_legacy_keyboard_controls: bool = false

var current_speed: float = 0.0
var current_direction: float = 0.0  # Direction in degrees


func _ready():
	# Find the land carrier if not assigned
	if not land_carrier:
		# If this script is a child of LandCarrier, get the parent
		if get_parent() is LandCarrier:
			land_carrier = get_parent()
		else:
			# Try to find the LandCarrier node in the scene
			land_carrier = get_node("../LandCarrier")
			if not land_carrier or not land_carrier is LandCarrier:
				# Try alternative paths
				land_carrier = get_node("../../LandCarrier")
				if not land_carrier or not land_carrier is LandCarrier:
					# Search for any LandCarrier in the scene
					land_carrier = get_tree().get_first_node_in_group("land_carrier")

	if not land_carrier or not land_carrier is LandCarrier:
		print("Error: No LandCarrier found for input controls")
		return

	print("Land Carrier Input Controls Ready!")
	print("  PageUp/PageDown - Adjust carrier speed by %.0f m/s" % speed_increment)
	print("  T - Cycle tread debug view")
	print("  Shift+T - Freeze/unfreeze tread scroll")
	if enable_legacy_keyboard_controls:
		print("Controls:")
		print("  E - Move elevator up")
		print("  D - Move elevator down")
		print("  W - Increase speed")
		print("  S - Decrease speed")
		print("  A - Turn left")
		print("  D - Turn right")
		print("  ESC - Quit")


func _input(event):
	if not land_carrier:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func increase_speed():
	"""Increase carrier speed"""
	_adjust_carrier_speed(speed_increment)
	current_speed = land_carrier.get_speed()
	print("Speed increased to: ", current_speed, " m/s")


func decrease_speed():
	"""Decrease carrier speed"""
	_adjust_carrier_speed(-speed_increment)
	current_speed = land_carrier.get_speed()
	print("Speed decreased to: ", current_speed, " m/s")


func _adjust_carrier_speed(delta_mps: float) -> void:
	if not land_carrier:
		return
	land_carrier.max_speed = clampf(land_carrier.max_speed + delta_mps, min_speed, max_speed)
	current_speed = land_carrier.max_speed
	print("[Carrier] Speed -> %.0f m/s" % land_carrier.max_speed)


func turn_left():
	"""Turn carrier left"""
	land_carrier.turn_left(15.0)
	current_direction = land_carrier.get_direction()
	print("Turning left to: ", current_direction, " degrees")


func turn_right():
	"""Turn carrier right"""
	land_carrier.turn_right(15.0)
	current_direction = land_carrier.get_direction()
	print("Turning right to: ", current_direction, " degrees")


func get_status() -> Dictionary:
	"""Get current input status"""
	return {
		"current_speed": current_speed,
		"current_direction": current_direction,
		"max_speed": max_speed,
		"min_speed": min_speed
	}


func _get_tread_nodes() -> Array:
	if not land_carrier:
		return []
	if land_carrier.treads.is_empty() and land_carrier.has_method("find_treads"):
		land_carrier.find_treads()
	return land_carrier.treads


func _cycle_tread_debug_mode() -> void:
	var tread_nodes := _get_tread_nodes()
	if tread_nodes.is_empty():
		print("[CarrierTread] No tread nodes found")
		return

	for tread in tread_nodes:
		if tread and tread.has_method("cycle_belt_debug_mode"):
			tread.cycle_belt_debug_mode()

	var first_tread = tread_nodes[0]
	var mode_name := "Unknown"
	if first_tread and first_tread.has_method("get_belt_debug_mode_name"):
		mode_name = str(first_tread.get_belt_debug_mode_name())
	print("[CarrierTread] Debug view -> %s" % mode_name)


func _toggle_tread_debug_freeze() -> void:
	var tread_nodes := _get_tread_nodes()
	if tread_nodes.is_empty():
		print("[CarrierTread] No tread nodes found")
		return

	var frozen := false
	for tread in tread_nodes:
		if tread and tread.has_method("toggle_belt_debug_freeze"):
			tread.toggle_belt_debug_freeze()
			frozen = bool(tread.get("belt_debug_freeze_scroll"))

	print("[CarrierTread] Scroll freeze -> %s" % ("ON" if frozen else "OFF"))
