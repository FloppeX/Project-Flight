extends RefCounted
## One impact per region/contact episode, then time-based wear on the parts
## actually scraping. Several contact points must not multiply crash damage.
const CONTACT_GAP_FRAMES := 12
const APPENDAGES := [&"left_wing", &"right_wing", &"tail"]
var previous_velocity := Vector3.ZERO
var previous_angular_velocity := Vector3.ZERO
var last_contact_frame := -1000
var pending: Dictionary = {}
var _last_region_contact: Dictionary = {}
var _episode_impacts: Dictionary = {}
var _scrape_time: Dictionary = {}
var _scrape_wear: Dictionary = {}
var dust_contacts: Dictionary = {}
var dust_contact_frame := -1000
var _pending_dust: Dictionary = {}

func suspension_touchdown(impact: float, normal: Vector3, point: Vector3, shape_index: int, dirt: bool = false, surface: String = "terrain", surface_velocity: Vector3 = Vector3.ZERO) -> void:
	_queue_contact(&"gear", {"impact": impact, "normal": normal, "position": point, "shape": shape_index, "gear": true, "dirt": dirt, "surface": surface, "surface_velocity": surface_velocity})

func _queue_contact(zone: StringName, contact: Dictionary) -> void:
	var frame := Engine.get_physics_frames()
	if frame - int(_last_region_contact.get(zone, -1000)) > CONTACT_GAP_FRAMES:
		_episode_impacts[zone] = 0.0
	_last_region_contact[zone] = frame
	last_contact_frame = frame
	if bool(contact.get("dirt", false)) and Vector3(contact.normal).dot(Vector3.UP) > 0.55:
		var dust_key := StringName("wheel_%d" % int(contact.shape)) if contact.gear else zone
		_pending_dust[dust_key] = contact
	if not pending.has(zone) or float(contact.impact) > float(pending[zone].impact):
		pending[zone] = contact

static func is_dirt_surface(node: Node) -> bool:
	while node != null:
		if node.is_in_group("terrain") or node.is_class("Terrain3D"):
			return true
		node = node.get_parent()
	return false

func apply_origin_shift(offset: Vector3) -> void:
	for contact: Dictionary in pending.values():
		contact.position -= offset
	# Fresh contacts repopulate visuals next tick; do not emit old world points.
	dust_contacts = {}
	_pending_dust = {}
	dust_contact_frame = -1000

func sample(craft: RigidBody3D, state: PhysicsDirectBodyState3D) -> void:
	var damage := craft.get_node("PartDamageModel") as AircraftPartDamageModel
	var support_normal := Vector3.ZERO
	for index in state.get_contact_count():
		var other := state.get_contact_collider_object(index) as Node
		if other == null or craft._is_runway_surface(other):
			continue
		var carrier: bool = craft._is_carrier_body(other)
		var shape_index := state.get_contact_local_shape(index)
		var collider := craft.shape_owner_get_owner(craft.shape_find_owner(shape_index))
		var gear_contact: bool = craft.safe_colliders.has(collider)
		# Use the real contact normal and incoming velocity on a deck too. A
		# resting belly must not take fresh collision damage every time it rocks.
		if carrier:
			if not bool(craft.get_meta("is_helicopter", false)) or craft._is_managed_by_carrier_deck_ops(): continue
		elif not craft._is_ground_or_terrain(other):
			continue
		var normal := state.get_contact_local_normal(index).normalized()
		var point := state.get_contact_local_position(index)
		var surface_velocity := state.get_contact_collider_velocity_at_position(index)
		if carrier:
			# Carrier child colliders can report zero physics velocity while the
			# carrier moves by transform. Match suspension and deck operations.
			surface_velocity = craft._get_carrier_contact_velocity(other)
		var relative := state.get_contact_local_velocity_at_position(index) - surface_velocity
		var incoming := previous_velocity + previous_angular_velocity.cross(point - state.transform.origin) - surface_velocity
		var impact := maxf(maxf(-incoming.dot(normal), -relative.dot(normal)), 0.0)
		var zone := damage.resolve_zone_from_contact(shape_index)
		if zone in [&"horizontal_stabilizer", &"vertical_stabilizer"]:
			zone = &"tail"
		if gear_contact:
			zone = &"gear"
		elif normal.y > 0.55 and normal.y > support_normal.y:
			support_normal = normal
		_queue_contact(zone, {"normal": normal, "impact": impact, "gear": gear_contact, "shape": shape_index, "position": point, "dirt": is_dirt_surface(other), "surface": "carrier" if carrier else "terrain", "surface_velocity": surface_velocity})
	if support_normal != Vector3.ZERO:
		craft.set_meta("ground_body_contact_frame", Engine.get_physics_frames())
		# Resist spin across the ground strongly, but allow impact-induced tipping
		# and rolling to settle physically. No damping is carried into flight.
		var spin := support_normal * state.angular_velocity.dot(support_normal)
		var tipping := state.angular_velocity - spin
		state.angular_velocity = spin * exp(-5.0 * state.step) + tipping * exp(-2.5 * state.step)
	previous_velocity = state.linear_velocity
	previous_angular_velocity = state.angular_velocity

func update(craft: Aircraft, delta: float) -> void:
	dust_contacts = _pending_dust
	_pending_dust = {}
	dust_contact_frame = Engine.get_physics_frames()
	if pending.is_empty():
		return
	var contacts := pending
	pending = {}
	var damage := craft.get_node("PartDamageModel") as AircraftPartDamageModel
	var gear := craft.get_node_or_null("LandingGear")
	var strongest: Dictionary = {}
	var sliding_normal := Vector3.ZERO
	var sliding_surface_velocity := Vector3.ZERO
	# Publish support before destroying parts, so their airborne failure forces
	# cannot spin a grounded wreck back into the air.
	craft.set_meta("ground_contact_frame", last_contact_frame)
	for contact_zone: StringName in contacts:
		var contact: Dictionary = contacts[contact_zone]
		var normal: Vector3 = contact.normal
		var impact: float = contact.impact
		var upright := craft.global_basis.y.dot(normal) > 0.7
		var surface_landing := normal.dot(Vector3.UP) > 0.55
		var wheels: bool = contact.gear and upright and surface_landing and not (gear != null and bool(gear.get("damage_collapsed")))
		# A queued wheel impact still belongs to gear after a preceding contact
		# sheared it off. Never reinterpret it as a fresh body strike.
		var zone: StringName = &"fuselage" if contact.gear else contact_zone
		var safe_impact := 6.0 if contact.gear else 3.0
		var excess := maxf(impact - maxf(float(_episode_impacts.get(contact_zone, 0.0)), safe_impact), 0.0)
		_episode_impacts[contact_zone] = maxf(float(_episode_impacts.get(contact_zone, 0.0)), impact)
		var surface: String = contact.get("surface", "terrain")
		var surface_velocity: Vector3 = contact.get("surface_velocity", Vector3.ZERO)
		var hard_threshold := maxf(craft.max_landing_force, 0.0) if surface == "carrier" else safe_impact
		var details := {"surface": surface, "descent_speed_mps": impact, "relative_speed_mps": (craft.linear_velocity - surface_velocity).length(), "hard": impact > hard_threshold, "damaging": excess > 0.0, "belly": not wheels, "position": contact.position}
		if strongest.is_empty() or impact > float(strongest.descent_speed_mps):
			strongest = details
		if excess > 0.0:
			craft.crashed.emit(impact)
			var damage_fraction := excess * (0.045 if contact.gear else (0.1 if zone in APPENDAGES else 0.065))
			if not upright: damage_fraction *= 1.5
			damage.damage_zone(zone, damage.get_zone_max_health(zone) * damage_fraction)
			if contact.gear and impact > 9.0 and gear != null:
				gear.shear_from_damage()
				damage.systems.refresh()
			# A wingtip/tail strike can tear that part away without exploding a
			# sound fuselage or killing a pilot whose cockpit was not struck.
			if impact >= 24.0 and zone in [&"fuselage", &"cockpit", &"engine"]:
				craft.explode()
				return
		if not contact.gear and surface_landing:
			if normal.y > sliding_normal.y:
				sliding_normal = normal
				sliding_surface_velocity = surface_velocity
			var speed := (craft.linear_velocity - surface_velocity).slide(normal).length()
			if speed > 3.0 and not damage.is_zone_destroyed(zone):
				var wear_rate := 0.25 if zone in APPENDAGES else 0.018
				_scrape_time[zone] = float(_scrape_time.get(zone, 0.0)) + delta
				_scrape_wear[zone] = float(_scrape_wear.get(zone, 0.0)) + minf(speed / 60.0, 2.0) * wear_rate * delta
				if float(_scrape_time[zone]) >= 0.25:
					damage.damage_zone(zone, damage.get_zone_max_health(zone) * float(_scrape_wear[zone]))
					_scrape_time[zone] = 0.0
					_scrape_wear[zone] = 0.0
	craft.set_meta("ground_landing_mode", "belly" if sliding_normal != Vector3.ZERO else "wheels")
	craft._publish_touchdown(strongest)
	if sliding_normal != Vector3.ZERO:
		var tangent := (craft.linear_velocity - sliding_surface_velocity).slide(sliding_normal)
		var speed := tangent.length()
		if speed > 0.2:
			craft.apply_central_force(-tangent.normalized() * minf(speed / maxf(delta, 0.001), 3.5) * craft.mass)
		craft.set_meta("belly_slide_speed_mps", speed)
