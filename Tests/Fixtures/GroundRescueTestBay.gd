extends "res://LandCarrier/VehicleBayManager.gd"
var returned: Array[Node3D] = []
func _ready() -> void: pass
func can_retrieve_vehicles() -> bool:
	return state == BayState.IDLE
func retrieve_vehicles(vehicles: Array[Node3D]) -> void:
	returned = vehicles.duplicate()
