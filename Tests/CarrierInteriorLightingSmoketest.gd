extends SceneTree

const LIGHTING_SCENE := preload("res://LandCarrier/CarrierInteriorLighting.tscn")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier_scene := ResourceLoader.load("res://LandCarrier/LandCarrier2.tscn") as PackedScene
	_expect(carrier_scene != null, "LandCarrier2 could not be loaded")
	var carrier_state := carrier_scene.get_state() if carrier_scene != null else null
	var carrier_has_lighting := false
	if carrier_state != null:
		for node_index in range(carrier_state.get_node_count()):
			if carrier_state.get_node_name(node_index) == &"CarrierInteriorLighting":
				carrier_has_lighting = true
				break
	_expect(carrier_has_lighting, "LandCarrier2 does not instance the interior lighting scene")

	var lighting := LIGHTING_SCENE.instantiate()
	root.add_child(lighting)

	var fixtures := get_nodes_in_group("carrier_interior_fixture")
	var lights := get_nodes_in_group("carrier_interior_light")
	_expect(fixtures.size() == 2, "expected one fixture in each carrier control room")
	_expect(lights.size() == 3, "expected one command-room fill and two Air Ops surface lights")

	for fixture_variant in fixtures:
		var fixture := fixture_variant as Node3D
		_expect(fixture != null, "fixture is not a Node3D")
		if fixture == null:
			continue
		var panel := fixture.get_node_or_null("EmissivePanel") as MeshInstance3D
		_expect(panel != null and panel.mesh != null, "%s has no emissive panel" % fixture.name)
		if panel == null or panel.mesh == null:
			continue
		var material := panel.mesh.surface_get_material(0) as StandardMaterial3D
		_expect(material != null, "%s panel material is missing" % fixture.name)
		if material != null:
			_expect(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "%s panel is affected by room lighting" % fixture.name)
			_expect(material.emission_enabled, "%s panel emission is disabled" % fixture.name)
			_expect(material.emission_energy_multiplier > 1.5, "%s panel will not clear the main-scene glow threshold" % fixture.name)

	for light_variant in lights:
		var light := light_variant as Light3D
		_expect(light != null, "surface light is not a Light3D")
		if light == null:
			continue
		_expect(not light.shadow_enabled, "%s unexpectedly casts expensive overlapping shadows" % light.name)
		_expect(light.light_energy > 0.0, "%s has no energy" % light.name)
		if light is SpotLight3D:
			var spot := light as SpotLight3D
			_expect(spot.spot_range >= 4.0, "%s does not reach the room floor" % spot.name)
			var downward := (-spot.global_basis.z).normalized()
			_expect(downward.dot(Vector3.DOWN) > 0.9, "%s is not primarily aimed down" % spot.name)
		elif light is OmniLight3D:
			_expect((light as OmniLight3D).omni_range >= 3.0, "%s does not fill the command room" % light.name)

	lighting.queue_free()
	if _failed:
		quit(1)
	else:
		print("[CarrierInteriorLightingSmoketest] PASS fixtures=%d shadowless_lights=%d" % [fixtures.size(), lights.size()])
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[CarrierInteriorLightingSmoketest] %s" % message)
