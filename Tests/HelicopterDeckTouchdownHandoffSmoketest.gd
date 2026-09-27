extends SceneTree


class BottomElevator:
	extends Node
	var shaft_depth := 10.0
	var platform_size := Vector3(8.0, 1.0, 8.0)

	func get_platform_local_y() -> float:
		return -shaft_depth

class EngineStub:
	extends Node
	var is_engine_working := true
	var target_power := 0.0

class SkidGear:
	extends Node
	var gear_collision_shapes: Array[CollisionShape3D] = []
	var nose_gear_index := 1
	var deck_contact_visual_offset_m := 0.25
	var _wheel_on_carrier_surface: Array[bool] = []

class BridgeCameraProvider:
	extends Node
	var camera: Camera3D

	func get_camera() -> Camera3D:
		return camera

	func activate_view_mode(_mode: int) -> Camera3D:
		return camera


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "HelicopterDeckTouchdownHandoffSmoketest"
	root.add_child(scene)
	current_scene = scene

	var carrier := CharacterBody3D.new()
	carrier.name = "CarrierTestDouble"
	carrier.velocity = Vector3(10.0, 0.0, 0.0)
	carrier.add_to_group("carrier")
	scene.add_child(carrier)

	var deck_marker := Marker3D.new()
	deck_marker.name = "DeckMarker"
	carrier.add_child(deck_marker)

	# Attach after insertion so the full scenario-oriented _ready() setup is not
	# needed for this focused touchdown test.
	var flight_deck_manager := Node.new()
	flight_deck_manager.name = "FlightDeckManager"
	carrier.add_child(flight_deck_manager)
	flight_deck_manager.set_script(load("res://LandCarrier/FlightDeckManager.gd") as Script)
	flight_deck_manager.set("deck_marker", deck_marker)
	flight_deck_manager.add_to_group("flight_deck_manager")

	var helicopter := RigidBody3D.new()
	helicopter.name = "Aircraft_11_TouchdownRegression"
	helicopter.add_to_group("ai_aircraft")
	scene.add_child(helicopter)
	helicopter.global_position = Vector3(0.0, 2.0, 0.0)
	helicopter.linear_velocity = Vector3(10.0, 0.8, 0.0)

	for gear_name in ["LeftGearCollider", "RightGearCollider"]:
		var gear := CollisionShape3D.new()
		gear.name = gear_name
		gear.position = Vector3(-1.0 if gear_name.begins_with("Left") else 1.0, -2.0, 0.0)
		helicopter.add_child(gear)

	helicopter.set_meta("is_helicopter", true)
	helicopter.set_meta("parking_brake", true)
	helicopter.global_position.y = 7.9
	helicopter.linear_velocity = carrier.velocity
	if bool(flight_deck_manager.call("_is_helicopter_ready_for_deck_recovery", helicopter)):
		_fail("hovering helicopter was selected for automatic deck recovery")
		return
	flight_deck_manager.call("start_post_arrest_recovery", helicopter)
	if helicopter.freeze or bool(helicopter.get_meta("controls_disabled", false)):
		_fail("recovery froze a helicopter whose skids were above the deck")
		return

	helicopter.global_position.y = 2.2
	helicopter.linear_velocity = Vector3(10.0, 0.8, 0.0)
	if bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", helicopter)):
		_fail("deck manager accepted gear still 20 cm above the deck")
		return
	helicopter.global_position.y = 2.0

	if not bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", helicopter)):
		_fail("deck manager did not recognize low-speed upright skid contact")
		return
	flight_deck_manager.set("deck_aircraft", helicopter)
	flight_deck_manager.set("current_state", 1) # FlightDeckManager.DeckState.AIRCRAFT_ON_DECK
	if bool(flight_deck_manager.call("_is_helicopter_ready_for_deck_recovery", helicopter)):
		_fail("outbound helicopter was recovered before leaving its launch position")
		return
	flight_deck_manager.set("deck_aircraft", null)
	flight_deck_manager.set("current_state", 0) # FlightDeckManager.DeckState.IDLE
	var flight_director := root.get_node_or_null("FlightDirector")
	if flight_director == null:
		_fail("FlightDirector autoload is missing")
		return
	var previous_player_control: bool = bool(flight_director.get("is_player_controlling"))
	var previous_player_aircraft: Variant = flight_director.get("player_controlled_plane")
	flight_director.set("is_player_controlling", true)
	flight_director.set("player_controlled_plane", helicopter)
	var running_engine := EngineStub.new()
	running_engine.name = "Engine"
	helicopter.add_child(running_engine)
	if bool(flight_deck_manager.call("_is_helicopter_ready_for_deck_recovery", helicopter)) \
			or flight_deck_manager.call("_find_stopped_aircraft_in_recovery_zone") == helicopter:
		_fail("running player-controlled helicopter was selected for automatic deck recovery")
		return
	flight_deck_manager.call("start_post_arrest_recovery", helicopter)
	if helicopter.freeze or bool(helicopter.get_meta("controls_disabled", false)):
		_fail("deck recovery took control of a helicopter with its engine running")
		return
	flight_director.set("player_controlled_plane", previous_player_aircraft)
	flight_director.set("is_player_controlling", previous_player_control)
	running_engine.is_engine_working = false
	if not bool(flight_deck_manager.call("_is_helicopter_ready_for_deck_recovery", helicopter)):
		_fail("automatic recovery missed a settled helicopter on its skids")
		return
	helicopter.linear_velocity.y = 1.2
	if bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", helicopter)):
		_fail("deck manager accepted excessive vertical touchdown speed")
		return
	helicopter.linear_velocity.y = 0.8
	helicopter.rotation.x = deg_to_rad(60.0)
	if bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", helicopter)):
		_fail("deck manager accepted a helicopter already tipping over")
		return
	helicopter.rotation = Vector3.ZERO

	# This is deliberately above HelicopterPilot's legacy 0.55 m/s vertical gate
	# and has no LandingGear module. The shared deck check must therefore be the
	# reason touchdown completes.
	var pilot := Node.new()
	pilot.name = "HelicopterPilot"
	helicopter.add_child(pilot)
	pilot.set_script(load("res://AI/HelicopterPilot.gd") as Script)
	pilot.set("aircraft", helicopter)
	pilot.set("state", 4) # HelicopterPilot.State.LANDING
	pilot.set("mission_phase", 2) # HelicopterPilot.MissionPhase.INBOUND
	pilot.set("_landing_on_carrier", true)
	pilot.set("destination", Vector3.ZERO)
	pilot.set("_has_destination", true)
	pilot.set("_physics_delta", 0.2)
	pilot.set("carrier_landing_touchdown_settle_time_s", 0.35)

	pilot.call("_try_finish_landing")
	if helicopter.freeze:
		_fail("touchdown secured before the settle dwell elapsed")
		return
	pilot.call("_try_finish_landing")

	if not helicopter.freeze \
			or not bool(helicopter.get_meta("parking_brake", false)) \
			or not bool(helicopter.get_meta("carrier_transport_mode", false)):
		_fail("confirmed touchdown did not engage the carrier deck hold")
		return
	if int(pilot.get("state")) != 0 or int(pilot.get("mission_phase")) != 3:
		_fail("pilot did not complete LANDING/INBOUND to IDLE/AT_CARRIER handoff")
		return
	flight_deck_manager.set("deck_aircraft", helicopter)
	flight_deck_manager.set("_pending_store_aircraft", helicopter)
	var bottom_elevator := BottomElevator.new()
	carrier.add_child(bottom_elevator)
	flight_deck_manager.set("elevator", bottom_elevator)
	flight_deck_manager.set("current_state", 3) # FlightDeckManager.DeckState.RECOVERY_IN_PROGRESS
	flight_deck_manager.call("_on_elevator_at_bottom")
	if not is_instance_valid(helicopter) or helicopter.is_queued_for_deletion() \
			or not flight_deck_manager.get("stored_aircraft").is_empty():
		_fail("tractor-fetch bottom signal stored an aircraft still on deck")
		return
	flight_deck_manager.set("current_state", 4) # FlightDeckManager.DeckState.STORING_IN_HANGAR
	flight_deck_manager.call("_on_elevator_at_bottom")
	if helicopter.is_queued_for_deletion() or not flight_deck_manager.get("stored_aircraft").is_empty():
		_fail("hangar storage ran without an aircraft elevator ride")
		return
	flight_deck_manager.set("_recovery_elevator_ride_completed_aircraft", helicopter)
	flight_deck_manager.call("_on_elevator_at_bottom")
	if helicopter.is_queued_for_deletion() or not flight_deck_manager.get("stored_aircraft").is_empty():
		_fail("aircraft still on deck was stored while the elevator was at the bottom")
		return
	helicopter.global_position.y = -8.0
	flight_deck_manager.call("_on_elevator_at_bottom")
	if not helicopter.is_queued_for_deletion() or flight_deck_manager.get("stored_aircraft").size() != 1:
		_fail("aircraft was not stored after reaching hangar level on the elevator")
		return

	# Aircraft_13 has four 18 cm skid collision boxes and a 25 cm visual
	# placement offset. At rest their bottoms are 4.6 cm above the deck.
	var bridge_camera := Camera3D.new()
	carrier.add_child(bridge_camera)
	var bridge_provider := BridgeCameraProvider.new()
	bridge_provider.camera = bridge_camera
	bridge_provider.add_to_group("carrier_cam")
	carrier.add_child(bridge_provider)
	var parked_heli := RigidBody3D.new()
	parked_heli.name = "Aircraft_13_ParkedSkidRegression"
	parked_heli.add_to_group("aircraft")
	parked_heli.set_meta("is_helicopter", true)
	parked_heli.set_meta("parking_brake", true)
	scene.add_child(parked_heli)
	parked_heli.global_position = Vector3(8.0, 1.386, -35.0)
	parked_heli.linear_velocity = carrier.velocity
	var cockpit_camera := Camera3D.new()
	cockpit_camera.name = "CockpitTestCamera"
	parked_heli.add_child(cockpit_camera)
	cockpit_camera.current = true
	var parked_gear := SkidGear.new()
	parked_gear.name = "LandingGear"
	parked_heli.add_child(parked_gear)
	for side in [-1.0, 1.0]:
		for longitudinal in [-0.3, 1.38]:
			var contact := CollisionShape3D.new()
			contact.name = "SkidContact"
			contact.position = Vector3(side * 0.93, -1.25, longitudinal)
			var contact_shape := BoxShape3D.new()
			contact_shape.size = Vector3(0.18, 0.18, 0.24)
			contact.shape = contact_shape
			parked_heli.add_child(contact)
			parked_gear.gear_collision_shapes.append(contact)
	var parked_engine := EngineStub.new()
	parked_engine.name = "Engine"
	parked_heli.add_child(parked_engine)
	flight_deck_manager.set("current_state", 0)
	flight_deck_manager.set("deck_aircraft", null)
	flight_deck_manager.set("_pending_store_aircraft", null)
	flight_deck_manager.set("_recovery_job_dispatched", false)
	flight_director.set("aircraft_view_transition_enabled", false)
	flight_director.set("current_viewed_aircraft", parked_heli)
	flight_director.set("current_category", 1) # FlightDirector.Category.FRIENDLY
	flight_director.set("is_player_controlling", true)
	flight_director.set("player_controlled_plane", parked_heli)
	if bool(flight_deck_manager.call("_is_helicopter_ready_for_deck_recovery", parked_heli)):
		_fail("running Aircraft_13 was offered for automatic collection")
		return
	parked_engine.is_engine_working = false
	if not bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", parked_heli)):
		_fail("parked Aircraft_13 skid boxes were not recognized on deck")
		return
	parked_heli.global_position.y += 0.15
	if bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", parked_heli)):
		_fail("Aircraft_13 was selected while its skids hovered above the deck")
		return
	parked_heli.global_position.y -= 0.15
	if flight_deck_manager.call("_find_stopped_aircraft_in_recovery_zone") != parked_heli:
		_fail("parked player helicopter was not selected for collection")
		return
	flight_deck_manager.call("start_post_arrest_recovery", parked_heli)
	if not bool(flight_director.get("is_player_controlling")) \
			or flight_director.get("current_viewed_aircraft") != parked_heli \
			or root.get_camera_3d() != cockpit_camera \
			or not parked_heli.freeze \
			or not bool(parked_heli.get_meta("controls_disabled", false)):
		_fail("parked helicopter did not retain cockpit view and player identity during collection")
		return
	flight_deck_manager.set("current_state", 4) # FlightDeckManager.DeckState.STORING_IN_HANGAR
	flight_deck_manager.set("_recovery_elevator_ride_completed_aircraft", parked_heli)
	flight_deck_manager.call("_on_elevator_at_bottom")
	if parked_heli.is_queued_for_deletion() \
			or not bool(flight_director.get("is_player_controlling")) \
			or root.get_camera_3d() != cockpit_camera:
		_fail("aircraft or cockpit view was removed before reaching hangar level")
		return
	parked_heli.global_position.y = -8.0
	flight_deck_manager.call("_on_elevator_at_bottom")
	if not parked_heli.is_queued_for_deletion() \
			or flight_deck_manager.get("stored_aircraft").size() != 2 \
			or bool(flight_director.get("is_player_controlling")) \
			or flight_director.get("current_viewed_aircraft") == parked_heli \
			or root.get_camera_3d() != bridge_camera:
		_fail("completed elevator ride did not store helicopter and switch to bridge")
		return
	var arrested_plane := RigidBody3D.new()
	arrested_plane.name = "PlayerArrestedPlaneRegression"
	arrested_plane.add_to_group("aircraft")
	scene.add_child(arrested_plane)
	var plane_cockpit_camera := Camera3D.new()
	arrested_plane.add_child(plane_cockpit_camera)
	plane_cockpit_camera.current = true
	flight_director.set("current_viewed_aircraft", arrested_plane)
	flight_director.set("current_category", 1)
	flight_director.set("is_player_controlling", true)
	flight_director.set("player_controlled_plane", arrested_plane)
	flight_deck_manager.call("start_post_arrest_recovery", arrested_plane)
	if not arrested_plane.freeze \
			or not bool(arrested_plane.get_meta("controls_disabled", false)) \
			or not bool(flight_director.get("is_player_controlling")) \
			or root.get_camera_3d() != plane_cockpit_camera:
		_fail("player-controlled fixed-wing recovery did not preserve cockpit through pickup")
		return

	print("[HelicopterDeckTouchdownHandoffSmoketest] PASS deck_confirmed=true settle_dwell=true secured=true outbound_held=true no_premature_store=true completed_ride_stored=true cockpit_retained_until_hangar=true fixed_wing_cockpit_retained=true")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[HelicopterDeckTouchdownHandoffSmoketest] FAIL %s" % reason)
	quit(1)
