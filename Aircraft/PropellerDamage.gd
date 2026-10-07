extends Node
## Physical disc strikes for the shared fixed-wing propeller. Queries are
## independent of visual budgeting, engine power and the aircraft's body shapes.

const BROKEN_SCENE := preload("res://Models/Aircraft_1/propeller_shattered.glb")
const GEOMETRY := preload("res://Models/Aircraft_1/propeller_strike_geometry.gd")
static var _disc: CylinderShape3D
var engine: Node3D
var craft: RigidBody3D
var propeller: Node3D
var broken := false
var _mount := Transform3D.IDENTITY
var _previous := Transform3D.IDENTITY
var _have_previous := false
var _exclusions: Array[RID] = []
var _query := PhysicsShapeQueryParameters3D.new()
var _broken_visual: Node3D

func setup(owner_engine: Node3D, owner_craft: RigidBody3D, prop: Node3D) -> void:
	engine = owner_engine
	craft = owner_craft
	propeller = prop
	_mount = craft.global_transform.affine_inverse() * propeller.global_transform
	_exclusions.append(craft.get_rid())
	for node in craft.find_children("*", "CollisionObject3D", true, false):
		_exclusions.append(node.get_rid())
	_query.exclude = _exclusions
	_query.collide_with_areas = false
	_query.collision_mask = 0xffffffff
	if _disc == null:
		_disc = CylinderShape3D.new()
		_disc.radius = GEOMETRY.RADIUS
		_disc.height = GEOMETRY.HEIGHT
	_query.shape = _disc

func reset_contact_history() -> void:
	_have_previous = false

func check_contacts(_delta: float) -> void:
	if broken or not is_instance_valid(propeller):
		return
	var parts := craft.get_node_or_null("PartDamageModel")
	if parts != null and parts.engine_attached_to_tail and parts.is_zone_destroyed(&"tail"):
		return
	# CylinderShape3D's height axis is Y; the authored propeller axis is Z.
	# A full disc does not need to spin with the visible blades.
	var pose := craft.global_transform * _mount * Transform3D(Basis(Vector3.RIGHT, PI*0.5), Vector3.ZERO)
	if not _have_previous or _previous.origin.distance_to(pose.origin) > 128.0:
		_previous = pose
		_have_previous = true
	var space := craft.get_world_3d().direct_space_state
	var scale := pose.basis.get_scale().abs()
	var radius := _disc.radius * maxf(scale.x, maxf(scale.y, scale.z))
	_query.transform = pose
	_query.motion = Vector3.ZERO
	_query.margin = 0.005
	if not space.intersect_shape(_query, 1).is_empty():
		shatter()
		return
	var angle := _previous.basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion())
	if _previous.origin.distance_squared_to(pose.origin) > 0.000001 or angle > 0.001:
		var steps := maxi(1, int(ceil(angle / 0.12)))
		for step in steps:
			var start := _previous.interpolate_with(pose, float(step)/steps)
			var end := _previous.interpolate_with(pose, float(step+1)/steps)
			var middle := start.interpolate_with(end, 0.5)
			_query.margin = 0.005 + radius * sin(angle / steps * 0.5)
			_query.transform = Transform3D(middle.basis, start.origin)
			_query.motion = end.origin - start.origin
			if not space.intersect_shape(_query, 1).is_empty():
				shatter()
				return
			if _query.motion.length_squared() > 0.000001:
				var travel := space.cast_motion(_query)
				if not travel.is_empty() and travel[0] < 1.0:
					shatter()
					return
	_previous = pose

func shatter(spawn_fragments: bool = true) -> void:
	if broken:
		return
	broken = true
	var spin := float(engine.current_power) * 50.0 + 5.0 if engine.is_engine_working else 0.0
	engine.propeller_broken = true
	engine.current_power = 0.0
	engine.target_power = 0.0
	engine.throttle_input = 0.0
	engine.is_engine_working = false
	if engine.sfx_tween: engine.sfx_tween.kill()
	if engine.sfx_engine_loop: engine.sfx_engine_loop.stop()
	if engine.sfx_engine_start: engine.sfx_engine_start.stop()
	engine.request_update_interface()
	craft.set_meta("propeller_broken", true)
	_broken_visual = BROKEN_SCENE.instantiate() as Node3D
	_broken_visual.name = "ShatteredPropeller"
	propeller.add_child(_broken_visual)
	for mesh in _broken_visual.find_children("BladeFragment*", "MeshInstance3D", true, false):
		if spawn_fragments:
			_spawn_fragment(mesh, spin)
		else:
			mesh.queue_free()
	engine._apply_propeller_blur_t(0.0)
	var parts := craft.get_node_or_null("PartDamageModel")
	if parts != null:
		# A broken propeller removes thrust, but leaves the engine's structure
		# and collider intact. Regional engine damage is still tracked separately.
		parts.systems.refresh()

func _spawn_fragment(mesh: MeshInstance3D, spin: float) -> void:
	var transform := mesh.global_transform
	var center := transform * mesh.get_aabb().get_center()
	var debris := RigidBody3D.new()
	debris.name = "PropellerFragment"
	debris.set_meta("damage_debris_zone", &"propeller")
	debris.mass = 0.15
	debris.collision_layer = 1
	debris.collision_mask = craft.collision_mask
	debris.continuous_cd = true
	craft.get_parent().add_child(debris)
	debris.global_position = center
	mesh.reparent(debris)
	mesh.global_transform = transform
	var collision := CollisionShape3D.new()
	collision.shape = mesh.mesh.create_convex_shape()
	debris.add_child(collision)
	collision.transform = mesh.transform
	debris.add_collision_exception_with(craft)
	var radial := center - propeller.global_position
	var axis: Vector3 = (propeller.global_basis * engine.propeller_spin_axis_local).normalized()
	debris.linear_velocity = craft.linear_velocity + craft.angular_velocity.cross(center - craft.global_position) \
		+ (axis.cross(radial) * spin).limit_length(65.0) + radial.normalized() * 2.0
	debris.angular_velocity = craft.angular_velocity + axis * randf_range(8.0,16.0)
	preload("res://Recording/CaptureHooks.gd").begin(debris, "detached_part")
	var ref: WeakRef = weakref(debris)
	get_tree().create_timer(12.0).timeout.connect(func():
		var piece = ref.get_ref()
		if is_instance_valid(piece): piece.queue_free())

func get_damage_state() -> Dictionary:
	return {"propeller": {"health": 0.0 if broken else 1.0, "destroyed": broken}}

func restore_damage_state(state: Dictionary) -> void:
	if bool(state.get("propeller", {}).get("destroyed", false)):
		shatter(false)
