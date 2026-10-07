extends AircraftPartDamageModel
## Reuses regional health, contact routing and debris without fixed-wing failure forces.
@export var aircraft_number := 9
var coaxial := false
var rotor_areas: Array[Area3D] = []
var _rotor_nodes: Dictionary = {}
var _tail_visuals: Array[Node3D] = []
var _phase := 0.0
var _wear_time := 0.0
var flight: HelicopterFlight
var rotor: Node3D
var engine: AircraftModule_Engine
var cockpit_camera: Node
const CUTS := {9:-2.4, 10:-1.0, 11:-1.8, 12:-2.3, 13:-1.2, 15:-2.0}

func _ready() -> void:
	# Aircraft initializes after its authored children finish entering the tree.
	_aircraft = get_parent() as RigidBody3D
	set_physics_process(false)

func initialize() -> void:
	_aircraft = get_parent() as RigidBody3D
	flight = _aircraft.get_node("SimpleAero") as HelicopterFlight
	rotor = _aircraft.get_node("RotorAssembly")
	engine = _aircraft.get_node("Engine")
	for node in _aircraft.find_children("*", "Node", true, false):
		if node.has_method("set_airflow_buffet_intensity"): cockpit_camera = node
	coaxial = rotor.get_node_or_null("LowerRotor") != null
	tail_cut_local_z = CUTS[aircraft_number]
	for zone in [&"fuselage", &"cockpit", &"engine", &"tail", &"main_rotor"]:
		_zone_max_health[zone] = maxf(_aircraft.max_health * region_health_fraction_of_legacy_total, 1.0)
	_zone_max_health[&"lower_rotor" if coaxial else &"tail_rotor"] = _zone_max_health[&"main_rotor"]
	_zone_health = _zone_max_health.duplicate()
	_aircraft.set_meta("regional_damage_enabled", true)
	_cache_helicopter_geometry()
	systems = preload("res://Aircraft/HelicopterDamageSystems.gd").new()
	systems.name = "RegionalSystems"
	add_child(systems)
	systems.refresh()
	set_physics_process(true)

func _cache_helicopter_geometry() -> void:
	var hull := _aircraft.get_node("CollisionShape3D") as CollisionShape3D
	hull.set_meta("damage_zone", &"fuselage")
	_zone_colliders[&"fuselage"] = hull
	var model := _aircraft.get_node("aircraft_%d" % aircraft_number)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("TailBreakaway") or str(mesh.name).begins_with("TailSupportBreakaway") \
		or (aircraft_number == 13 and str(mesh.name).begins_with("stabilizer")) \
		or (aircraft_number == 15 and str(mesh.name) == "tail assembly"):
			_tail_visuals.append(mesh)
	var tail_bounds := _bounds_of(_tail_visuals)
	var old_tail := _aircraft.get_node_or_null("tail boom") as CollisionShape3D
	if old_tail != null:
		old_tail.set_meta("damage_zone", &"tail")
		_zone_colliders[&"tail"] = old_tail
	else:
		_add_box(&"tail", tail_bounds)
	var front := {9:2.8,10:2.6,11:1.5,12:2.8,13:0.95,15:1.9}
	_add_box(&"cockpit", AABB(Vector3(-0.65,-0.55,front[aircraft_number]-0.65),Vector3(1.3,1.3,1.3)))
	var upper := rotor.get_node("UpperRotor") as Node3D
	var centre := _aircraft.to_local(upper.global_position)
	var engine_bounds := AABB(Vector3(-0.65,centre.y-1.3,-0.75),Vector3(1.3,0.9,1.5))
	if aircraft_number == 13:
		engine_bounds = _bounds_of([model.get_node("Engine")])
	_add_box(&"engine", engine_bounds)
	_make_rotor(&"main_rotor", upper, false)
	if coaxial:
		_make_rotor(&"lower_rotor", rotor.get_node("LowerRotor"), false)
	elif engine.propeller is Node3D:
		_make_rotor(&"tail_rotor", engine.propeller, true)
		_tail_visuals.append(engine.propeller)
		if is_instance_valid(engine.get_node_or_null(engine.propeller_disc_node)) and not engine.propeller_disc_node.is_empty():
			_tail_visuals.append(engine.get_node(engine.propeller_disc_node))

func _add_box(zone: StringName, bounds: AABB) -> void:
	var collider := CollisionShape3D.new()
	collider.name = "%sDamageCollider" % str(zone).to_pascal_case()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * 0.12)
	collider.shape = box
	collider.position = bounds.get_center()
	collider.set_meta("damage_zone", zone)
	_aircraft.add_child(collider)
	_zone_colliders[zone] = collider

func _bounds_of(roots: Array[Node3D]) -> AABB:
	var bounds := AABB()
	var first := true
	for root in roots:
		var meshes: Array[Node] = [root]
		meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
		for mesh in meshes:
			if not mesh is MeshInstance3D: continue
			var local: Transform3D = _aircraft.global_transform.affine_inverse() * mesh.global_transform
			var box: AABB = local * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	return bounds

func _make_rotor(zone: StringName, visual: Node3D, tail: bool) -> void:
	if tail and not engine.propeller_disc_node.is_empty():
		# The authored blur disc supplies the blade plane and hub, including
		# older meshes whose object origin is away from the actual tail rotor.
		var disc: MeshInstance3D = engine.get_node(engine.propeller_disc_node)
		var disc_pose := _aircraft.global_transform.affine_inverse() * disc.global_transform
		var disc_radius := (disc.mesh as CylinderMesh).top_radius * maxf(disc_pose.basis.get_scale().x,disc_pose.basis.get_scale().z)
		disc_pose.basis = disc_pose.basis.orthonormalized()
		var pivot := Node3D.new()
		pivot.name = "TailRotorDrive"
		_aircraft.add_child(pivot)
		pivot.transform = disc_pose
		visual.reparent(pivot,true)
		engine.propeller = pivot
		engine.propeller_spin_axis_local = Vector3.UP
		_rotor_nodes[zone] = pivot
		var tail_area := preload("res://Aircraft/HelicopterRotorArea.gd").new()
		tail_area.name = "TailRotorStrikeDisc"
		_aircraft.add_child(tail_area)
		tail_area.transform = disc_pose
		tail_area.setup(self,zone,disc_radius,4)
		rotor_areas.append(tail_area)
		return
	_rotor_nodes[zone] = visual
	var pose := _aircraft.global_transform.affine_inverse() * visual.global_transform
	var radius := 0.0
	var count := 0
	for child in visual.get_children():
		if str(child.name).begins_with("Blade"): count += 1
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).to_lower().contains("disc"): continue
		for i in 8:
			var point: Vector3 = visual.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(i)))
			radius = maxf(radius, Vector2(point.x,point.y).length() if tail else Vector2(point.x,point.z).length())
	# An imported tail rotor can itself be a mesh.
	if visual is MeshInstance3D:
		for i in 8:
			var point: Vector3 = visual.get_aabb().get_endpoint(i)
			radius = maxf(radius, Vector2(point.x,point.y).length())
	var area := preload("res://Aircraft/HelicopterRotorArea.gd").new()
	area.name = "%sStrikeDisc" % str(zone).to_pascal_case()
	_aircraft.add_child(area)
	var scaling := pose.basis.get_scale().abs()
	radius *= maxf(scaling.x,maxf(scaling.y,scaling.z))
	pose.basis = pose.basis.orthonormalized()
	area.transform = pose * (Transform3D(Basis(Vector3.RIGHT,PI*0.5),Vector3.ZERO) if tail else Transform3D.IDENTITY)
	area.setup(self,zone,maxf(radius,0.05),count if count > 0 else 4)
	rotor_areas.append(area)

func _physics_process(delta: float) -> void:
	_phase += delta
	var unfolded: bool = rotor._fold_t < 0.02
	for area in rotor_areas:
		area.active = unfolded and not is_zone_destroyed(area.zone) and not (area.zone == &"tail_rotor" and is_zone_destroyed(&"tail"))
		area.collision_layer = area.BULLET_LAYER if area.active else 0
		area.check_contact()
	_wear_time += delta
	if _wear_time >= 0.25:
		for zone in [&"main_rotor", &"lower_rotor", &"tail_rotor"]:
			if not _zone_health.has(zone): continue
			var health: float = systems.fraction(zone)
			if health > 0.0 and health < 0.55:
				var stress := flight.rotor_energy.rpm ** 2 * (0.15 + flight.rotor_energy.collective ** 2)
				damage_zone(zone, get_zone_max_health(zone) * (0.55-health) * stress * 0.035 * _wear_time)
		_wear_time = 0.0
	var vibration := flight.damage_vibration * flight.rotor_energy.rpm ** 2
	_aircraft.set_meta("structural_damage_buffet", vibration * 0.35)
	if is_instance_valid(cockpit_camera): cockpit_camera.set_airflow_buffet_intensity(vibration * 0.65)
	_aircraft.set_meta("helicopter_rotor_rpm", flight.rotor_energy.rpm)
	if vibration > 0.0 and not _aircraft.freeze:
		var wave := Vector3(sin(_phase*31.0),sin(_phase*43.0)*0.2,cos(_phase*37.0))
		_aircraft.apply_torque(_aircraft.global_basis * wave * vibration * _aircraft.mass * 3.0)
		_aircraft.apply_central_force(_aircraft.global_basis.x * sin(_phase*29.0) * vibration * _aircraft.mass * 0.8)

func reset_contact_history() -> void:
	for area in rotor_areas: area.reset_contact_history()

func resolve_zone_from_hit(point: Vector3, index: int = -1) -> StringName:
	var collider := _shape_node_for_local_index(index)
	var zone := _zone_for_collider(collider)
	if zone != &"" and zone != &"fuselage": return zone
	if point.is_finite():
		for candidate in [&"cockpit", &"engine", &"tail"]:
			if not is_zone_destroyed(candidate) and _distance_to_collider(point,_zone_colliders[candidate]) < 0.12:
				return candidate
	return &"fuselage"

func _destroy_zone(zone: StringName) -> void:
	if is_zone_destroyed(zone): return
	_destroyed_zones[zone] = true
	_zone_health[zone] = 0.0
	if zone == &"tail":
		_detach_roots(_tail_visuals, &"tail_section")
		_zone_colliders[&"tail"].set_deferred("disabled",true)
		var hull: CollisionShape3D = _zone_colliders[&"fuselage"]
		if hull.shape is CapsuleShape3D:
			var capsule := hull.shape.duplicate() as CapsuleShape3D
			var front := hull.position.z + capsule.height*0.5
			capsule.height = maxf(front-tail_cut_local_z,capsule.radius*2.0)
			hull.shape = capsule
			hull.position.z = front-capsule.height*0.5
		if not coaxial:
			_zone_health[&"tail_rotor"] = 0.0
			_destroyed_zones[&"tail_rotor"] = true
	elif zone in [&"main_rotor", &"lower_rotor"]:
		var visual: Node3D = _rotor_nodes[zone]
		for blade in visual.get_children():
			if str(blade.name).begins_with("Blade"): _detach_roots([blade],zone)
	elif zone == &"tail_rotor":
		_detach_roots([_rotor_nodes[zone]],zone)
	elif zone in [&"cockpit", &"fuselage"]:
		_apply_zone_failure(zone)
	# Engine failure leaves physical structure in place and allows a rotor freewheel.
	if not _restoring_damage_state: zone_destroyed.emit(zone)

func _detach_roots(roots: Array[Node3D], zone: StringName) -> void:
	var meshes: Array[MeshInstance3D] = []
	for root in roots:
		var candidates: Array[Node] = [root]
		candidates.append_array(root.find_children("*", "MeshInstance3D",true,false))
		for mesh in candidates:
			if mesh is MeshInstance3D and mesh.is_visible_in_tree() and not str(mesh.name).to_lower().contains("disc") and not meshes.has(mesh): meshes.append(mesh)
	_spawn_visual_debris(meshes,zone)
	for root in roots:
		root.hide()
		root.set_meta("damage_detached",true)

func get_damage_state() -> Dictionary:
	var state := {}
	for zone in _zone_health:
		state[zone] = {"health":get_zone_health(zone),"max_health":get_zone_max_health(zone),"destroyed":is_zone_destroyed(zone)}
	return state

func restore_damage_state(state: Dictionary) -> void:
	_restoring_damage_state = true
	for zone in _zone_health:
		var entry: Dictionary = state.get(zone,{})
		if entry.is_empty(): continue
		_zone_health[zone] = clampf(float(entry.health),0.0,get_zone_max_health(zone))
		if bool(entry.destroyed): _destroy_zone(zone)
	_restoring_damage_state = false
	systems.refresh()

func get_structural_zones() -> Array[StringName]:
	var zones: Array[StringName] = [&"fuselage",&"tail",&"main_rotor"]
	zones.append(&"lower_rotor" if coaxial else &"tail_rotor")
	return zones
