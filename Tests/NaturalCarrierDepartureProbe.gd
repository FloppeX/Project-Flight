extends "res://Tests/CarrierLaunchContactProbe.gd"

var _release_ticks := 0
var _release_height := 0.0
var _lowest_height := INF
var _peak_bank := 0.0

func _ready() -> void:
	release_observation_ticks = 600
	super._ready()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(aircraft) or not aircraft.has_meta("carrier_launch_contact_grace_until_msec"):
		return
	_release_ticks += 1
	if _release_ticks == 1: _release_height = aircraft.global_position.y
	_lowest_height = minf(_lowest_height, aircraft.global_position.y)
	_peak_bank = maxf(_peak_bank, absf(rad_to_deg(atan2(aircraft.global_basis.x.y, aircraft.global_basis.y.y))))
	if _release_ticks == 590:
		check(aircraft.global_position.y > _release_height + 10.0, "departure must develop a sustained climb")
		check(_peak_bank < 15.0, "calm departure must not introduce a large bank")
		print("NATURAL_CARRIER_DEPARTURE aircraft=%d mass=%.1f dip=%.3f height_gain=%.2f climb_rate=%.2f peak_bank=%.3f" % [aircraft_number, aircraft.mass, _release_height - _lowest_height, aircraft.global_position.y - _release_height, aircraft.linear_velocity.y, _peak_bank])
