extends Node3D
class_name Explosion

enum VisualPreset {
	AUTO,
	LIGHT,
	STANDARD,
	HEAVY,
}

@export var blast_radius: float = 25.0
@export var flash_duration: float = 1.0
@export var debris_count: int = 25
@export var effect_duration: float = 8.0
@export var explosion_sounds: Array[AudioStream] = []
@export var use_line_of_sight: bool = true
@export var debug_enabled: bool = false
@export_group("Presentation")
@export var visual_preset: VisualPreset = VisualPreset.AUTO
@export var visual_effects_enabled: bool = true
@export var blast_wave_enabled: bool = true
@export var play_explosion_audio: bool = true
@export var scorch_mark_lifetime_s: float = 45.0
@export_range(0.0, 0.5, 0.01) var visual_spread_duration_s: float = 0.20

# Damage properties remain independent of presentation budgets. Visual effects may
# be culled at distance, but every detonation still performs its gameplay query.
@export_group("Damage")
@export var max_damage: float = 100.0
@export var min_damage: float = 10.0
@export var knockback_impulse_at_center: float = 2500.0
@export var knockback_impulse_at_edge: float = 250.0
@export var max_damage_query_results: int = 128

var sfx_explosion: AudioStreamPlayer3D = null
var source_attacker: Node = null
var _triggered: bool = false
var _visual_events: Array[Dictionary] = []
var _visual_event_index: int = 0
var _visual_elapsed_s: float = 0.0

func _ready() -> void:
	# Callers configure radius/damage/preset immediately after add_child(). Deferring
	# the trigger ensures those values are applied before any work is performed.
	call_deferred("trigger_explosion")

func trigger_explosion() -> void:
	if _triggered or is_queued_for_deletion():
		return
	_triggered = true
	if debug_enabled:
		print("=== TRIGGERING EXPLOSION === radius=", blast_radius, " preset=", _resolved_visual_preset())

	_spawn_visual_effects()
	_setup_and_play_explosion_audio()
	call_deferred("deal_explosion_damage")

	# Visuals are owned by ParticleManager and scorch marks by BulletImpactBudget,
	# so this coordinator only needs to live long enough for its audio and deferred
	# damage query. Previously it never freed itself.
	var cleanup_delay_s: float = maxf(0.25, visual_spread_duration_s + 0.1)
	# Audio is normally detached into ParticleManager's pool. The fallback player
	# remains a child, so retain the coordinator only in that exceptional path.
	if is_instance_valid(sfx_explosion) and sfx_explosion.stream != null:
		cleanup_delay_s = maxf(cleanup_delay_s, sfx_explosion.stream.get_length() + 0.1)
	get_tree().create_timer(cleanup_delay_s).timeout.connect(cleanup_explosion)

func _spawn_visual_effects() -> void:
	if not visual_effects_enabled or get_node_or_null("/root/ParticleManager") == null:
		return
	var preset: VisualPreset = _resolved_visual_preset()
	var burst_count: int = 3
	var visual_debris_count: int = mini(maxi(debris_count, 0), 6)
	var debris_lifetime_s: float = minf(maxf(effect_duration, 0.2), 2.5)
	var spawn_wave: bool = blast_wave_enabled
	match preset:
		VisualPreset.LIGHT:
			burst_count = 2
			visual_debris_count = mini(maxi(debris_count, 0), 3)
			debris_lifetime_s = minf(maxf(effect_duration, 0.2), 1.2)
			spawn_wave = false
		VisualPreset.HEAVY:
			visual_debris_count = mini(maxi(debris_count, 4), 8)
			debris_lifetime_s = minf(maxf(effect_duration, 0.5), 3.5)

	var colors: Array[Dictionary] = [
		{"albedo": Color(1.0, 0.08, 0.02, 0.82), "emission": Color.ORANGE_RED},
		{"albedo": Color(1.0, 0.86, 0.08, 0.78), "emission": Color.YELLOW},
		{"albedo": Color(1.0, 0.38, 0.03, 0.80), "emission": Color.ORANGE},
	]
	var important: bool = preset == VisualPreset.HEAVY
	var target_scale := Vector3.ONE * maxf(blast_radius * 0.8, 0.2)
	for i in range(burst_count):
		var color_data: Dictionary = colors[i % colors.size()]
		_visual_events.append({
			"kind": "flash",
			"target_scale": target_scale,
			"albedo": color_data["albedo"],
			"emission": color_data["emission"],
			"duration_s": maxf(flash_duration, 0.05),
			"rotation": Vector3(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0), randf_range(-10.0, 10.0)),
			"important": important,
		})

	var debris_size_m: float = clampf(blast_radius * 0.035, 0.14, 0.8)
	for i in range(visual_debris_count):
		var launch_direction := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.35, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		var launch_speed: float = randf_range(5.0, 10.0) * clampf(blast_radius / 8.0, 0.7, 2.0)
		_visual_events.append({
			"kind": "debris",
			"size": Vector3.ONE * debris_size_m * randf_range(0.65, 1.15),
			"color": Color(1.0, randf_range(0.3, 0.8), 0.02, 0.9),
			"velocity": launch_direction * launch_speed,
			"lifetime_s": debris_lifetime_s,
			"important": important,
		})

	if spawn_wave:
		_visual_events.append({
			"kind": "wave",
			"radius": blast_radius,
			"duration_s": minf(maxf(flash_duration * 1.5, 0.25), 0.65),
			"important": important,
		})

	_visual_event_index = 0
	_visual_elapsed_s = 0.0
	if visual_spread_duration_s <= 0.0:
		while _visual_event_index < _visual_events.size():
			_spawn_next_visual_event()
		set_process(false)
		return
	# Keep the initial flash and sound immediate; stage secondary flashes, debris,
	# and the blast wave over the following fraction of a second.
	_spawn_next_visual_event()
	set_process(_visual_event_index < _visual_events.size())

func _process(delta: float) -> void:
	if _visual_event_index >= _visual_events.size():
		set_process(false)
		return
	_visual_elapsed_s += maxf(delta, 0.0)
	var interval_s := visual_spread_duration_s / float(maxi(_visual_events.size() - 1, 1))
	var due_time_s := interval_s * float(_visual_event_index)
	if _visual_elapsed_s >= due_time_s:
		# At most one allocation group per rendered frame. If rendering falls behind,
		# the presentation stretches instead of recreating the original spike.
		_spawn_next_visual_event()

func _spawn_next_visual_event() -> void:
	if _visual_event_index >= _visual_events.size():
		return
	var particle_manager := get_node_or_null("/root/ParticleManager")
	if particle_manager == null:
		_visual_event_index = _visual_events.size()
		return
	var event: Dictionary = _visual_events[_visual_event_index]
	_visual_event_index += 1
	match str(event.get("kind", "")):
		"flash":
			particle_manager.call("spawn_explosion_flash",
				global_position,
				event["target_scale"],
				event["albedo"],
				event["emission"],
				float(event["duration_s"]),
				event["rotation"],
				bool(event["important"])
			)
		"debris":
			particle_manager.call("spawn_managed_debris",
				global_position,
				event["size"],
				event["color"],
				event["velocity"],
				float(event["lifetime_s"]),
				5.0,
				bool(event["important"])
			)
		"wave":
			particle_manager.call("spawn_blast_wave",
				global_position,
				float(event["radius"]),
				float(event["duration_s"]),
				bool(event["important"])
			)

func _resolved_visual_preset() -> VisualPreset:
	if visual_preset != VisualPreset.AUTO:
		return visual_preset
	if blast_radius <= 5.0:
		return VisualPreset.LIGHT
	if blast_radius <= 15.0:
		return VisualPreset.STANDARD
	return VisualPreset.HEAVY

func _setup_and_play_explosion_audio() -> void:
	if not play_explosion_audio:
		return
	var selected_sound: AudioStream = null
	if not explosion_sounds.is_empty():
		selected_sound = explosion_sounds[randi() % explosion_sounds.size()]
	else:
		selected_sound = load("res://Audio/explosion/explosion_large_01.wav")
	if selected_sound == null:
		return
	var particle_manager := get_node_or_null("/root/ParticleManager")
	if particle_manager != null:
		particle_manager.call("play_explosion_sound", selected_sound, global_position, 0.0, randf_range(0.96, 1.04))
		return
	sfx_explosion = AudioStreamPlayer3D.new()
	sfx_explosion.stream = selected_sound
	sfx_explosion.volume_db = 0.0
	sfx_explosion.max_distance = 800.0
	sfx_explosion.unit_size = 50.0
	sfx_explosion.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	sfx_explosion.add_to_group("3d_audio")
	add_child(sfx_explosion)
	sfx_explosion.play()

func cleanup_explosion() -> void:
	if _visual_event_index < _visual_events.size():
		get_tree().create_timer(0.1).timeout.connect(cleanup_explosion)
		return
	if debug_enabled:
		print("=== CLEANING UP EXPLOSION ===")
	queue_free()

func create_scorch_mark(
	excluded_colliders: Array[CollisionObject3D] = [],
	force_spawn: bool = false
) -> void:
	var scene_root: Node = get_tree().current_scene if get_tree() != null else null
	if scene_root == null:
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3.UP * 5.0
	var end: Vector3 = global_position - Vector3.UP * 200.0
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	var exclusion_rids: Array[RID] = []
	for collider in excluded_colliders:
		if is_instance_valid(collider):
			exclusion_rids.append(collider.get_rid())
	params.exclude = exclusion_rids
	params.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = space_state.intersect_ray(params)
	var hit_pos: Vector3 = global_position + Vector3.UP * 0.02
	if not hit.is_empty() and hit.has("position"):
		hit_pos = hit.position + Vector3.UP * 0.02

	var impact_budget: Node = get_node_or_null("/root/BulletImpactBudget")
	# Bomb craters are persistent scene information rather than disposable impact
	# particles. They still use the global decal cap/lifetime, but must not vanish
	# merely because the main camera is distant or looking through another viewport.
	if impact_budget and not force_spawn \
			and not bool(impact_budget.call("should_spawn_visual", hit_pos)):
		return
	var decal: Decal = impact_budget.call("acquire_decal", scene_root) as Decal if impact_budget else Decal.new()
	if decal == null:
		return
	if impact_budget == null:
		scene_root.add_child(decal)
	decal.texture_albedo = preload("res://Projectiles/Explosion/scorch_mark.png")
	decal.size = Vector3(maxf(blast_radius, 0.1), 10.0, maxf(blast_radius, 0.1))
	decal.sorting_offset = 20.0
	decal.global_position = hit_pos
	decal.global_basis = Basis.IDENTITY
	decal.rotation.y = randf() * TAU
	decal.modulate = Color.WHITE
	if impact_budget:
		impact_budget.call("register_decal", decal, scorch_mark_lifetime_s)
	else:
		var decal_ref: WeakRef = weakref(decal)
		get_tree().create_timer(maxf(scorch_mark_lifetime_s, 0.1)).timeout.connect(func() -> void:
			var decal_obj: Object = decal_ref.get_ref()
			if decal_obj is Node and is_instance_valid(decal_obj):
				(decal_obj as Node).queue_free()
		)

func deal_explosion_damage() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var safe_radius: float = maxf(blast_radius, 0.01)
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = safe_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), global_position)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = (1 << 0) | (1 << 3)
	params.exclude = [self]

	var results: Array[Dictionary] = space_state.intersect_shape(params, maxi(max_damage_query_results, 1))
	var targets_hit: int = 0
	var damaged_target_ids: Dictionary = {}
	for hit in results:
		var collider_variant: Variant = hit.get("collider", null)
		if typeof(collider_variant) != TYPE_OBJECT or not is_instance_valid(collider_variant):
			continue
		if not (collider_variant is Node3D):
			continue
		var target := collider_variant as Node3D
		if target == self or (not target.has_method("take_damage") and not (target is RigidBody3D)):
			continue
		var target_instance_id := target.get_instance_id()
		if damaged_target_ids.has(target_instance_id):
			continue
		damaged_target_ids[target_instance_id] = true
		var distance: float = minf(global_position.distance_to(target.global_position), safe_radius)
		if use_line_of_sight:
			var ray_params := PhysicsRayQueryParameters3D.create(global_position, target.global_position)
			ray_params.exclude = [self, target]
			var ray_hit: Dictionary = space_state.intersect_ray(ray_params)
			if not ray_hit.is_empty() and ray_hit.get("collider", null) != target:
				continue
		var damage_ratio: float = clampf(1.0 - distance / safe_radius, 0.0, 1.0)
		var damage_amount: float = lerpf(min_damage, max_damage, damage_ratio)
		if target.has_method("take_damage"):
			_report_damage_credit(target, damage_amount)
			if target.has_method("take_damage_at"):
				target.call("take_damage_at", damage_amount, global_position, -1)
			else:
				target.take_damage(damage_amount)
			targets_hit += 1
		if target is RigidBody3D:
			var body := target as RigidBody3D
			var direction: Vector3 = (body.global_position - global_position).normalized()
			var impulse_strength: float = lerpf(knockback_impulse_at_edge, knockback_impulse_at_center, damage_ratio)
			body.apply_central_impulse(direction * impulse_strength)
	if debug_enabled:
		print("Explosion hit ", targets_hit, " targets")

func _report_damage_credit(damage_target: Node, damage_amount: float) -> void:
	if source_attacker == null or not is_instance_valid(source_attacker):
		return
	if PilotRoster == null or not is_instance_valid(PilotRoster) or not PilotRoster.has_method("report_damage"):
		return
	PilotRoster.report_damage(source_attacker, damage_target, damage_amount)
