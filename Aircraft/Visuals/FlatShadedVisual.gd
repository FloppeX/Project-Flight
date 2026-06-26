extends Node3D

const PilotVisualMaterials = preload("res://Models/Characters/PilotVisualMaterials.gd")

@export var enabled: bool = true


func _ready() -> void:
	if enabled:
		PilotVisualMaterials.apply_flat_shading(self)
