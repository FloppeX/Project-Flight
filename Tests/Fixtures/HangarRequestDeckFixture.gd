extends FlightDeckManager


func _ready() -> void:
	pass


func _ensure_pilot_assigned_for_data(_aircraft_data: Dictionary) -> bool:
	return true


func start_hangar_retrieval() -> void:
	current_state = DeckState.RETRIEVING_FROM_HANGAR
