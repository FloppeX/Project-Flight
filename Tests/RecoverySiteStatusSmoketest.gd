extends SceneTree

class Terrain extends Node:
	var height := -1000.0
	func get_height(_position: Vector3) -> float:
		return height

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var carrier := Node3D.new()
	root.add_child(carrier)
	var deck: Node = load("res://Tests/Fixtures/RecoverySiteTestDeck.gd").new()
	deck.name = "FlightDeckManager"
	# Avoid starting deck operations; only exercise the public site assessment.
	carrier.add_child(deck)
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.add_to_group("terrain_provider")
	assert(deck.get_recovery_site_status(true).status == "clear")
	terrain.height = 10000.0
	assert(deck.get_recovery_site_status(true).status == "obstructed")
	deck.landing_terrain_check_enabled = false
	assert(deck.get_recovery_site_status(true).status == "unchecked")
	deck.landing_terrain_check_enabled = true
	terrain.remove_from_group("terrain_provider")
	assert(deck.get_recovery_site_status(true).status == "unchecked")
	terrain.add_to_group("terrain_provider")
	terrain.height = -1000.0
	assert(deck.get_recovery_site_status(true).status == "clear")
	var damage: Node = load("res://LandCarrier/CarrierDamageControl.gd").new()
	carrier.add_child(damage)
	var page: Control = load("res://UI/CarrierPage.gd").new()
	root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.bind_damage_control(damage)
	assert(page._recovery_site.text == "Fixed-wing final approach: terrain clear")
	terrain.height = 10000.0
	deck.get_recovery_site_status(true)
	page._refresh()
	assert("obstructed" in page._recovery_site.text)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		root.content_scale_size = Vector2i(1920, 1080)
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://recovery_site_warning.png")
	print("RECOVERY_SITE_STATUS_PASS")
	quit()
