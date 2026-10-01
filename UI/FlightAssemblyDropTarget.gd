extends PanelContainer
var assembly: Node
var flight_name := ""
signal assigned(id: String, flight: String)

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("airframe_id") or assembly == null:
		return false
	return assembly.can_assign(str(data.airframe_id), flight_name).is_empty()

func _drop_data(_position: Vector2, data: Variant) -> void:
	assigned.emit(str(data.airframe_id), flight_name)
