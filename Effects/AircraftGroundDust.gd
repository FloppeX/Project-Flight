extends DustEffect
## Contact-driven dirt trails. Uses the shared effect budget, puff pool and
## particle lifetime manager; proximity to the ground alone never emits dust.

var emitted_puffs := 0
var emitted_wheel_puffs := 0
var emitted_skid_puffs := 0
var _emission_timer := 0.0
static var _contact_mesh: SphereMesh

func _init() -> void:
	pooled_puff_count = 16
	max_pooled_puff_count = 128
	puff_lifetime_s = 3.0
	spawn_interval_s = 0.05
	full_speed_mps = 55.0
	min_speed_mps = 2.0
	max_effect_distance_m = 1000.0

func _create_pooled_puff() -> void:
	super._create_pooled_puff()
	if _puff_pool.is_empty(): return
	if _contact_mesh == null:
		_contact_mesh = SphereMesh.new()
		_contact_mesh.radius = 1.0
		_contact_mesh.height = 2.0
		_contact_mesh.radial_segments = 6
		_contact_mesh.rings = 3
	var puff: MeshInstance3D = _puff_pool.back()
	puff.mesh = _contact_mesh
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Dirt obscures the ground; additive blending would make it luminous.
	puff.material_override.blend_mode = BaseMaterial3D.BLEND_MODE_MIX

func _physics_process(delta: float) -> void:
	var craft := _parent_node as Aircraft
	if craft == null or craft.freeze or craft._has_exploded: return
	_emission_timer = maxf(_emission_timer - delta, 0.0)
	if not visual_budget_enabled or not dust_enabled or not _should_emit_for_camera(delta): return
	var contact: RefCounted = craft._regional_ground_contact
	if contact == null or Engine.get_physics_frames() - contact.dust_contact_frame > 1: return
	if _emission_timer > 0.0: return
	var skid := false
	var emitted := false
	for point: Dictionary in contact.dust_contacts.values():
		if point.gear and bool(craft.get_meta("gear_collapsed", false)): continue
		var normal: Vector3 = point.normal
		var offset: Vector3 = point.position - craft.global_position
		var velocity := craft.linear_velocity + craft.angular_velocity.cross(offset)
		var speed := velocity.slide(normal).length()
		if speed < min_speed_mps: continue
		_emit_contact_puff(point.position, normal, velocity, speed, not point.gear)
		skid = skid or not point.gear
		emitted = true
	if emitted: _emission_timer = 0.055 if skid else 0.12

func _emit_contact_puff(point: Vector3, normal: Vector3, velocity: Vector3, speed: float, skid: bool) -> void:
	var puff := _acquire_pooled_puff()
	if puff == null: return
	var strength := clampf(speed / full_speed_mps, 0.0, 1.0)
	var radius := lerpf(0.65, 1.65, strength) if skid else lerpf(0.25, 0.6, strength)
	radius *= randf_range(0.8, 1.2)
	puff.global_position = point + normal * radius * 0.35
	puff.scale = Vector3(radius, radius * 0.6, radius)
	puff.rotation = Vector3(0, randf() * TAU, 0)
	var surface_color: Variant = _get_terrain_surface_color(point)
	var tint := _sanitize_dust_color(surface_color if surface_color is Color else _shared_dust_color)
	var mat := puff.material_override as StandardMaterial3D
	mat.albedo_color = Color(tint.r, tint.g, tint.b, lerpf(0.16, 0.32, strength) if skid else lerpf(0.1, 0.22, strength))
	puff.visible = true
	var side := normal.cross(velocity).normalized() * randf_range(-2.5, 2.5)
	var drift := velocity.slide(normal) * 0.08 + side
	ParticleManager.add_outward_dust(puff, puff_lifetime_s, puff.scale, drift,
		1.0 if skid else 0.6, randf_range(-0.4, 0.4), {"on_finish": Callable(self, "_release_pooled_puff")})
	emitted_puffs += 1
	if skid: emitted_skid_puffs += 1
	else: emitted_wheel_puffs += 1
