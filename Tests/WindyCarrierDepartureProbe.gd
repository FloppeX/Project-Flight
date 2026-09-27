extends "res://Tests/NaturalCarrierDepartureProbe.gd"

func _ready() -> void:
	add_child(load("res://Weather/ContinuousTurbulence.tscn").instantiate())
	super._ready()
