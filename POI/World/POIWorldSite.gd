extends Node3D

## Base behavior for lightweight physical POI sites. POIManager stores the
## authoritative location/state; this node supplies world presentation and
## follows floating-origin shifts with the rest of the scene.


func _ready() -> void:
	add_to_group("origin_shifter")


func apply_origin_shift(offset: Vector3) -> void:
	global_position -= offset
