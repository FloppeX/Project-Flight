extends "res://LandCarrier/LandCarrier.gd"

# Exercise the actual persistence hooks, but omit navigation/world startup.
# Loaded at runtime so SceneTree --script tests initialize autoloads first.
func _ready() -> void:
	pass
