extends RefCounted
## Loaded after autoload initialization by RecoverySequencingSmoketest.

class Deck extends "res://LandCarrier/FlightDeckManager.gd":
	var deck_clear := false
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _can_grant_landing_clearance_to(_requester: RigidBody3D = null) -> bool: return deck_clear
	func _damage_control_allows(_systems: Array) -> bool: return true
	func _queued_fixed_wing_recovery_has_clear_corridor() -> bool: return false

class Pilot extends "res://AI/AIPilot.gd":
	var waved_off := false
	var caught := false
	var recalled := false
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _update_landing_arrest_controls() -> bool: return caught
	func _begin_missed_approach() -> void: waved_off = true
	func start_recovery() -> bool:
		recalled = true
		return true
