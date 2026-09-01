extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
const VISUAL_FOCUS_HELPER = preload("res://Effects/VisualFocus.gd")
const AircraftPresentationDormancy = preload("res://Aircraft/AircraftPresentationDormancy.gd")
const DistantEnemyContrast = preload("res://Effects/DistantEnemyContrast.gd")
const PRE_TREE_PRESENTATION_META: StringName = &"visual_budget_pre_tree_presentation_prepared"
const PRE_TREE_DETACHED_COUNT_META: StringName = &"visual_budget_pre_tree_detached_nodes"
const PRESENTATION_STAGING_META: StringName = &"visual_budget_presentation_staging"
const PRESENTATION_KEEP_ATTACHED_META: StringName = &"visual_budget_presentation_keep_attached"

enum BudgetBand { HUMAN, NEAR, MID, FAR, CULLED }

@export var enabled: bool = true
@export var update_interval_s: float = 0.18
@export var max_units_per_update: int = 10
@export var near_distance_m: float = 900.0
@export var mid_distance_m: float = 2200.0
@export var far_distance_m: float = 4800.0
@export var air_shadow_distance_m: float = 1800.0
@export var ground_shadow_distance_m: float = 1300.0
@export var effect_distance_m: float = 1000.0
@export var ai_aircraft_detail_distance_m: float = 1400.0
@export var ai_aircraft_audio_distance_m: float = 1200.0
@export var detach_ai_presentation_subtrees: bool = true
@export_group("Distant Enemy Contrast")
@export var distant_enemy_contrast_enabled: bool = true
@export_range(1, 100, 1) var max_contrast_units_per_update: int = 24
@export_range(0.0, 10000.0, 100.0) var enemy_contrast_start_distance_m: float = 1800.0
@export_range(100.0, 12000.0, 100.0) var enemy_contrast_full_distance_m: float = 5200.0
@export_range(0.0, 0.3, 0.01) var enemy_max_contrast_strength: float = 0.18
@export var enemy_sky_contrast_color: Color = Color(0.025, 0.03, 0.035, 1.0)
@export var enemy_terrain_contrast_color: Color = Color(0.78, 0.80, 0.76, 1.0)
@export_range(-45.0, 45.0, 0.5) var enemy_terrain_angle_deg: float = -5.0
@export_range(-45.0, 45.0, 0.5) var enemy_sky_angle_deg: float = 1.0
@export_group("Aircraft Physics Budget")
@export var budget_distant_aircraft_contact_monitoring: bool = true
@export_range(500.0, 8000.0, 100.0) var aircraft_contact_monitor_distance_m: float = 2600.0
@export_range(100.0, 3000.0, 50.0) var aircraft_contact_monitor_min_agl_m: float = 500.0
@export_group("")
@export var require_effect_frustum: bool = true
@export var prune_cache_interval_s: float = 5.0

var _update_timer_s: float = 0.0
var _prune_timer_s: float = 0.0
var _candidate_cursor: int = 0
var _contrast_candidate_cursor: int = 0
var _root_cache: Dictionary = {}
var _contrast_cache: Dictionary = {}
var _stats: Dictionary = {}
var _pre_tree_prepared_total: int = 0
var _pre_tree_nodes_detached_total: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_stats()


func _process(delta: float) -> void:
	if not enabled:
		return
	var profiler_start: int = FrameProfiler.begin("EnemyVisualBudget.process")
	_update_timer_s -= maxf(delta, 0.0)
	_prune_timer_s -= maxf(delta, 0.0)
	if _update_timer_s <= 0.0:
		_update_timer_s = maxf(update_interval_s, 0.02)
		_update_visual_budget()
	if _prune_timer_s <= 0.0:
		_prune_timer_s = maxf(prune_cache_interval_s, 1.0)
		_prune_cache()
	FrameProfiler.end("EnemyVisualBudget.process", profiler_start)


func get_report_stats() -> Dictionary:
	var copy := _stats.duplicate(true)
	copy["cache_roots"] = _root_cache.size()
	copy["contrast_cache_roots"] = _contrast_cache.size()
	copy["enabled"] = enabled
	copy["pre_tree_prepared_total"] = _pre_tree_prepared_total
	copy["pre_tree_nodes_detached_total"] = _pre_tree_nodes_detached_total
	return copy


## Inventories an off-tree aircraft while every authored node is still present,
## then detaches player-only presentation branches before SceneTree entry. The
## cached dormancy session owns those exact instances until focus restores them.
func prepare_ai_aircraft_for_tree_entry(unit: Node3D) -> Dictionary:
	var result: Dictionary = {
		"prepared": false,
		"detached_nodes": 0,
	}
	if unit == null or not is_instance_valid(unit) or unit.is_inside_tree():
		return result
	if not enabled or not detach_ai_presentation_subtrees:
		return result

	var profiler_start: int = FrameProfiler.begin("EnemyVisualBudget.prepare_ai_aircraft_for_tree_entry")
	var cache := _get_cache_for_root(unit)
	var session = cache.get("presentation_session")
	if session == null:
		FrameProfiler.end("EnemyVisualBudget.prepare_ai_aircraft_for_tree_entry", profiler_start)
		return result

	var detached_nodes: int = int(session.detach())
	var prepared: bool = session.is_detached()
	unit.set_meta(PRE_TREE_PRESENTATION_META, prepared)
	unit.set_meta(PRE_TREE_DETACHED_COUNT_META, detached_nodes)
	if prepared:
		_pre_tree_prepared_total += 1
		_pre_tree_nodes_detached_total += detached_nodes
	result["prepared"] = prepared
	result["detached_nodes"] = detached_nodes
	FrameProfiler.end("EnemyVisualBudget.prepare_ai_aircraft_for_tree_entry", profiler_start)
	return result


## Hangar retrieval uses the otherwise idle elevator travel to admit one
## presentation root per frame. The keep-attached lock prevents the regular AI
## budget from immediately undoing that warm-up before launch.
func prepare_aircraft_presentation_for_staged_tree_entry(unit: Node3D) -> Dictionary:
	if unit == null or not is_instance_valid(unit):
		return {"prepared": false, "detached_nodes": 0, "detached_roots": 0}
	var result := prepare_ai_aircraft_for_tree_entry(unit)
	var prepared := bool(result.get("prepared", false))
	unit.set_meta(PRESENTATION_STAGING_META, prepared)
	unit.set_meta(PRESENTATION_KEEP_ATTACHED_META, prepared)
	if prepared:
		var cache := _get_cache_for_root(unit)
		var session = cache.get("presentation_session")
		if session != null:
			result["detached_roots"] = int(session.get_detached_root_count())
			result["root_names"] = session.get_detached_root_names()
	return result


func restore_next_staged_aircraft_presentation_root(unit: Node3D) -> Dictionary:
	var result: Dictionary = {
		"restored": false,
		"root_name": "",
		"node_count": 0,
		"remaining_roots": 0,
		"remaining_nodes": 0,
		"complete": true,
	}
	if unit == null or not is_instance_valid(unit):
		return result
	var cache := _get_cache_for_root(unit)
	var session = cache.get("presentation_session")
	if session == null:
		unit.remove_meta(PRESENTATION_STAGING_META)
		return result
	result = session.restore_next_root(false)
	if bool(result.get("complete", false)):
		unit.remove_meta(PRESENTATION_STAGING_META)
	return result


func complete_aircraft_presentation_staging(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var cache := _get_cache_for_root(unit)
	var session = cache.get("presentation_session")
	if session != null:
		while session.is_detached():
			session.restore_next_root(false)
	unit.remove_meta(PRESENTATION_STAGING_META)


func release_aircraft_presentation_keep_attached(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.remove_meta(PRESENTATION_STAGING_META)
	unit.remove_meta(PRESENTATION_KEEP_ATTACHED_META)


## Releases a cached aircraft immediately. Dematerialization uses discard=true
## because detached presentation nodes are no longer children of the aircraft and
## would otherwise wait for the periodic cache-prune pass before being freed.
func release_aircraft_cache(unit: Node3D, discard_presentation: bool = true) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var id := unit.get_instance_id()
	var cached: Dictionary = _root_cache.get(id, {})
	var root_ref: WeakRef = cached.get("root_ref", null) as WeakRef
	var cached_root: Object = root_ref.get_ref() if root_ref != null else null
	if not cached.is_empty() and cached_root == unit:
		var session = cached.get("presentation_session")
		if session != null:
			if discard_presentation:
				session.discard_detached()
			else:
				session.dispose()
		_root_cache.erase(id)
	var contrast_cached: Dictionary = _contrast_cache.get(id, {})
	var contrast_root_ref: WeakRef = contrast_cached.get("root_ref", null) as WeakRef
	var contrast_root: Object = contrast_root_ref.get_ref() if contrast_root_ref != null else null
	if not contrast_cached.is_empty() and contrast_root == unit:
		var contrast_session = contrast_cached.get("contrast_session")
		if contrast_session != null:
			contrast_session.dispose()
		_contrast_cache.erase(id)
	unit.remove_meta(PRE_TREE_PRESENTATION_META)
	unit.remove_meta(PRE_TREE_DETACHED_COUNT_META)
	unit.remove_meta(PRESENTATION_STAGING_META)
	unit.remove_meta(PRESENTATION_KEEP_ATTACHED_META)


func ensure_aircraft_presentation_attached(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var cache := _get_cache_for_root(unit)
	var session = cache.get("presentation_session")
	if session != null:
		session.restore()


func _update_visual_budget() -> void:
	var camera := _get_active_camera()
	var candidates := _collect_candidates()
	var contrast_candidates := _collect_contrast_candidates()
	_reset_stats()
	_stats["candidate_count"] = candidates.size()
	_stats["contrast_candidate_count"] = contrast_candidates.size()
	if not candidates.is_empty():
		var update_count: int = mini(maxi(max_units_per_update, 1), candidates.size())
		if _candidate_cursor >= candidates.size():
			_candidate_cursor = 0

		for i in range(update_count):
			var index: int = (_candidate_cursor + i) % candidates.size()
			var unit := candidates[index] as Node3D
			if unit == null or not is_instance_valid(unit):
				continue
			_apply_budget_to_unit(unit, camera)

		_candidate_cursor = (_candidate_cursor + update_count) % candidates.size()
	else:
		_candidate_cursor = 0
	_update_enemy_contrast(contrast_candidates, camera)


func _collect_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var seen: Dictionary = {}
	var tree := get_tree()
	if tree == null:
		return result

	for node_value in tree.get_nodes_in_group("ai_aircraft"):
		var node := node_value as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if _is_player_controlled(node):
			continue
		var id := node.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		result.append(node)

	for node_value in tree.get_nodes_in_group("enemies"):
		var node := node_value as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if not (node.is_in_group("ground_vehicles") or node.is_in_group("aircraft") or node.is_in_group("ai_aircraft")):
			continue
		if _is_player_controlled(node):
			continue
		var id := node.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		result.append(node)

	return result


func _collect_contrast_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var tree := get_tree()
	if tree == null:
		return result
	for node_value in tree.get_nodes_in_group("enemies"):
		var node := node_value as Node3D
		if node == null or not is_instance_valid(node) or _is_player_controlled(node):
			continue
		result.append(node)
	return result


func _update_enemy_contrast(candidates: Array[Node3D], camera: Camera3D) -> void:
	if candidates.is_empty():
		_contrast_candidate_cursor = 0
		return
	var update_count: int = mini(maxi(max_contrast_units_per_update, 1), candidates.size())
	if _contrast_candidate_cursor >= candidates.size():
		_contrast_candidate_cursor = 0
	for i in range(update_count):
		var index: int = (_contrast_candidate_cursor + i) % candidates.size()
		var unit := candidates[index] as Node3D
		if unit == null or not is_instance_valid(unit):
			continue
		_apply_distant_enemy_contrast(unit, camera)
	_contrast_candidate_cursor = (_contrast_candidate_cursor + update_count) % candidates.size()


func _apply_budget_to_unit(unit: Node3D, camera: Camera3D) -> void:
	var cache := _get_cache_for_root(unit)
	var distance_m: float = _distance_to_camera(unit, camera)
	var player_focused: bool = _is_unit_player_focused(unit, camera)
	var target_feed_focused: bool = VISUAL_FOCUS_HELPER.is_node_in_target_camera_focus(self, unit)
	var focused: bool = player_focused or target_feed_focused
	var in_frustum: bool = _is_unit_in_frustum(unit, camera)
	var is_air: bool = unit.is_in_group("ai_aircraft") or unit.is_in_group("aircraft")
	# The inset target feed is a visual focus, not a player-control focus. Keep
	# distance-based AI cadence instead of promoting its pilot to the human band.
	var band: int = _classify_band(distance_m, player_focused)
	var shadow_distance: float = air_shadow_distance_m if is_air else ground_shadow_distance_m
	var allow_shadows: bool = focused or distance_m <= shadow_distance
	var allow_effects: bool = focused or (distance_m <= effect_distance_m and (in_frustum or not require_effect_frustum))
	var allow_ai_detail: bool = focused or (distance_m <= ai_aircraft_detail_distance_m and in_frustum)
	var allow_ai_audio: bool = player_focused or distance_m <= ai_aircraft_audio_distance_m

	_stats["units_touched"] = int(_stats["units_touched"]) + 1
	if is_air:
		_stats["air_units"] = int(_stats["air_units"]) + 1
		# A target-feed aircraft needs exterior detail, but not its cockpit HUD,
		# instrument viewports, audio manager, cameras, or pooled occupant. Restoring
		# those player-only roots on each target change caused the visible hitch.
		_apply_ai_aircraft_player_only_budget(unit, player_focused, cache)
		_apply_ai_aircraft_detail_budget(_resolve_ref_array(cache.get("ai_detail_refs", [])), allow_ai_detail)
		_apply_aircraft_engine_budget(_resolve_ref_array(cache.get("aircraft_engine_refs", [])), allow_ai_detail, allow_ai_audio)
		_apply_aircraft_audio_budget(_resolve_ref_array(cache.get("audio_refs", [])), allow_ai_audio)
		_apply_aircraft_contact_monitor_budget(unit, player_focused, distance_m)
	else:
		_stats["ground_units"] = int(_stats["ground_units"]) + 1
	match band:
		BudgetBand.HUMAN:
			_stats["human"] = int(_stats["human"]) + 1
		BudgetBand.NEAR:
			_stats["near"] = int(_stats["near"]) + 1
		BudgetBand.MID:
			_stats["mid"] = int(_stats["mid"]) + 1
		BudgetBand.FAR:
			_stats["far"] = int(_stats["far"]) + 1
		_:
			_stats["culled"] = int(_stats["culled"]) + 1

	_apply_shadow_budget(_resolve_ref_array(cache.get("geometry_refs", [])), allow_shadows)
	_apply_effect_budget(_resolve_ref_array(cache.get("effect_refs", [])), allow_effects)

	unit.set_meta("visual_budget_band", _band_name(band))
	unit.set_meta("visual_budget_distance_m", distance_m)
	unit.set_meta("visual_budget_shadows_enabled", allow_shadows)
	unit.set_meta("visual_budget_effects_enabled", allow_effects)
	if is_air:
		unit.set_meta("visual_budget_ai_detail_enabled", allow_ai_detail)
		unit.set_meta("visual_budget_ai_audio_enabled", allow_ai_audio)


func _apply_aircraft_contact_monitor_budget(unit: Node3D, focused: bool, distance_m: float) -> void:
	if not (unit is RigidBody3D):
		return
	var body := unit as RigidBody3D
	if not body.has_meta("visual_budget_original_contact_monitor"):
		body.set_meta("visual_budget_original_contact_monitor", body.contact_monitor)
	var original_monitor: bool = bool(body.get_meta("visual_budget_original_contact_monitor", body.contact_monitor))
	var may_sleep_monitor: bool = budget_distant_aircraft_contact_monitoring \
		and original_monitor \
		and not focused \
		and distance_m >= maxf(aircraft_contact_monitor_distance_m, 0.0) \
		and _is_safe_for_distant_aircraft_contact_budget(body)
	# Never change monitoring while the body is already reporting a contact. This
	# avoids suppressing the exit half of an active collision and makes restoration
	# deterministic when an aircraft crosses a budget boundary during contact.
	if may_sleep_monitor and body.contact_monitor and body.get_contact_count() > 0:
		may_sleep_monitor = false
	var should_monitor: bool = original_monitor and not may_sleep_monitor
	body.contact_monitor = should_monitor
	body.set_meta("visual_budget_contact_monitor_enabled", should_monitor)
	if original_monitor and not should_monitor:
		_stats["aircraft_contact_monitors_disabled"] = int(_stats["aircraft_contact_monitors_disabled"]) + 1


func _is_safe_for_distant_aircraft_contact_budget(body: RigidBody3D) -> bool:
	# Contact callbacks are required for deck/terrain crash and landing handling.
	# Only steady, high-altitude prop-plane navigation states are eligible.
	for meta_name in ["controls_disabled", "parking_brake", "carrier_transport_mode", "arresting_engaged"]:
		if bool(body.get_meta(meta_name, false)):
			return false
	if body.has_meta("arresting_cable"):
		return false
	var altitude_agl_m: float = float(body.get("local_altitude"))
	if altitude_agl_m < maxf(aircraft_contact_monitor_min_agl_m, 0.0):
		return false
	var pilot := body.find_child("AIPilot", true, false) as AIPilot
	if pilot == null or not is_instance_valid(pilot):
		return false
	return pilot.current_state in [
		AIPilot.State.CLIMBING,
		AIPilot.State.TRANSIT,
		AIPilot.State.SEARCH,
		AIPilot.State.RTB,
	]


func _get_cache_for_root(root: Node3D) -> Dictionary:
	var id := root.get_instance_id()
	var cached: Dictionary = _root_cache.get(id, {})
	var root_ref: WeakRef = cached.get("root_ref", null) as WeakRef
	var cached_root: Object = root_ref.get_ref() if root_ref != null else null
	if not cached.is_empty() and cached_root == root:
		cached["last_seen_frame"] = Engine.get_process_frames()
		_root_cache[id] = cached
		return cached

	var geometry: Array[GeometryInstance3D] = []
	var effects: Array[Node] = []
	var player_only_nodes: Array[Node] = []
	var ai_detail_nodes: Array[Node] = []
	var audio_nodes: Array[Node] = []
	var aircraft_engine_nodes: Array[Node] = []
	_collect_budget_nodes(root, geometry, effects, player_only_nodes, ai_detail_nodes, audio_nodes, aircraft_engine_nodes)
	cached = {
		"root_ref": weakref(root),
		"geometry_refs": _make_ref_array(geometry),
		"effect_refs": _make_ref_array(effects),
		"player_only_refs": _make_ref_array(player_only_nodes),
		"ai_detail_refs": _make_ref_array(ai_detail_nodes),
		"audio_refs": _make_ref_array(audio_nodes),
		"aircraft_engine_refs": _make_ref_array(aircraft_engine_nodes),
		"presentation_session": AircraftPresentationDormancy.new(root),
		"last_seen_frame": Engine.get_process_frames(),
	}
	_root_cache[id] = cached
	return cached


func _apply_distant_enemy_contrast(unit: Node3D, camera: Camera3D) -> void:
	var cache := _get_contrast_cache_for_root(unit)
	var session = cache.get("contrast_session")
	if session == null:
		return
	session.configure(
		enemy_contrast_start_distance_m,
		enemy_contrast_full_distance_m,
		enemy_max_contrast_strength,
		enemy_sky_contrast_color,
		enemy_terrain_contrast_color,
		enemy_terrain_angle_deg,
		enemy_sky_angle_deg
	)
	session.set_enabled(distant_enemy_contrast_enabled)
	session.refresh_for_camera(camera)
	if session.is_active():
		_stats["contrast_units_active"] = int(_stats["contrast_units_active"]) + 1
		_stats["contrast_geometry_active"] = int(_stats["contrast_geometry_active"]) + int(session.get_eligible_geometry_count())


func _get_contrast_cache_for_root(root: Node3D) -> Dictionary:
	var id := root.get_instance_id()
	var cached: Dictionary = _contrast_cache.get(id, {})
	var root_ref: WeakRef = cached.get("root_ref", null) as WeakRef
	var cached_root: Object = root_ref.get_ref() if root_ref != null else null
	if not cached.is_empty() and cached_root == root:
		cached["last_seen_frame"] = Engine.get_process_frames()
		_contrast_cache[id] = cached
		return cached
	cached = {
		"root_ref": weakref(root),
		"contrast_session": DistantEnemyContrast.new(root),
		"last_seen_frame": Engine.get_process_frames(),
	}
	_contrast_cache[id] = cached
	return cached


func _collect_budget_nodes(
		node: Node,
		geometry: Array[GeometryInstance3D],
		effects: Array[Node],
		player_only_nodes: Array[Node],
		ai_detail_nodes: Array[Node],
		audio_nodes: Array[Node],
		aircraft_engine_nodes: Array[Node]) -> void:
	if node is GeometryInstance3D:
		geometry.append(node as GeometryInstance3D)
	if _is_budget_effect_node(node):
		effects.append(node)
	if _is_player_only_aircraft_node(node):
		player_only_nodes.append(node)
	if _is_ai_aircraft_detail_node(node):
		ai_detail_nodes.append(node)
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		audio_nodes.append(node)
	if node.has_method("set_aircraft_visual_budget_enabled") or node.has_method("set_aircraft_audio_budget_enabled"):
		aircraft_engine_nodes.append(node)
	for child: Node in node.get_children():
		_collect_budget_nodes(child, geometry, effects, player_only_nodes, ai_detail_nodes, audio_nodes, aircraft_engine_nodes)


func _apply_shadow_budget(geometry_nodes: Array, allow_shadows: bool) -> void:
	for node_value in geometry_nodes:
		var geometry := node_value as GeometryInstance3D
		if geometry == null or not is_instance_valid(geometry):
			continue
		if not geometry.has_meta("visual_budget_original_shadow"):
			geometry.set_meta("visual_budget_original_shadow", int(geometry.cast_shadow))
		var original_shadow: int = int(geometry.get_meta("visual_budget_original_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
		_stats["shadow_nodes"] = int(_stats["shadow_nodes"]) + 1
		if allow_shadows:
			if geometry.cast_shadow != original_shadow:
				geometry.cast_shadow = original_shadow
		else:
			if original_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				_stats["shadows_disabled"] = int(_stats["shadows_disabled"]) + 1
			if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apply_effect_budget(effect_nodes: Array, allow_effects: bool) -> void:
	for node_value in effect_nodes:
		var effect := node_value as Node
		if effect == null or not is_instance_valid(effect):
			continue
		_stats["effect_nodes"] = int(_stats["effect_nodes"]) + 1
		if effect.has_method("set_visual_budget_enabled"):
			effect.call("set_visual_budget_enabled", allow_effects)
		elif "visual_budget_enabled" in effect:
			effect.set("visual_budget_enabled", allow_effects)
		else:
			effect.set_physics_process(allow_effects)
		if not allow_effects:
			_stats["effects_disabled"] = int(_stats["effects_disabled"]) + 1


func _apply_ai_aircraft_player_only_budget(unit: Node3D, focused: bool, cache: Dictionary) -> void:
	var presentation_session = cache.get("presentation_session")
	if bool(unit.get_meta(PRESENTATION_STAGING_META, false)):
		return
	var keep_attached := bool(unit.get_meta(PRESENTATION_KEEP_ATTACHED_META, false))
	if presentation_session != null:
		if focused:
			presentation_session.restore()
		elif keep_attached:
			if presentation_session.is_detached():
				presentation_session.restore(false)
		elif not detach_ai_presentation_subtrees:
			presentation_session.restore()
	var player_only_nodes: Array = _resolve_ref_array(cache.get("player_only_refs", []))
	for node_value in player_only_nodes:
		var node := node_value as Node
		if node == null or not is_instance_valid(node):
			continue
		_store_original_node_state(node)
		if node.has_method("set_view_updates_active"):
			node.call("set_view_updates_active", focused)
		if focused:
			# FlightDirector owns the live UI/camera state of the aircraft being
			# watched. AI aircraft are commonly spawned with these nodes disabled,
			# so restoring the cached spawn state here blanks the HUD for one frame
			# every visual-budget update before FlightDirector enables it again.
			continue
		else:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			if node is CanvasItem:
				(node as CanvasItem).visible = false
			elif node is Node3D:
				(node as Node3D).visible = false
			_stop_audio_players_recursive(node)
			_stats["player_only_disabled"] = int(_stats["player_only_disabled"]) + 1
	if not focused and not keep_attached and detach_ai_presentation_subtrees and presentation_session != null:
		var detached_nodes: int = int(presentation_session.detach())
		if detached_nodes > 0:
			_stats["presentation_aircraft_detached"] = int(_stats["presentation_aircraft_detached"]) + 1
			_stats["presentation_nodes_detached"] = int(_stats["presentation_nodes_detached"]) + detached_nodes


func _apply_ai_aircraft_detail_budget(detail_nodes: Array, allow_detail: bool) -> void:
	for node_value in detail_nodes:
		var node: Node = node_value as Node
		if node == null or not is_instance_valid(node):
			continue
		_store_original_node_state(node)
		_stats["ai_detail_nodes"] = int(_stats["ai_detail_nodes"]) + 1
		if allow_detail:
			_restore_node_state(node)
		else:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			if node is Node3D:
				(node as Node3D).visible = false
			elif node is CanvasItem:
				(node as CanvasItem).visible = false
			_stop_audio_players_recursive(node)
			_stats["ai_detail_disabled"] = int(_stats["ai_detail_disabled"]) + 1


func _apply_aircraft_engine_budget(engine_nodes: Array, allow_visuals: bool, allow_audio: bool) -> void:
	for node_value in engine_nodes:
		var node: Node = node_value as Node
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("set_aircraft_visual_budget_enabled"):
			node.call("set_aircraft_visual_budget_enabled", allow_visuals)
			if not allow_visuals:
				_stats["ai_engine_visual_disabled"] = int(_stats["ai_engine_visual_disabled"]) + 1
		if node.has_method("set_aircraft_audio_budget_enabled"):
			node.call("set_aircraft_audio_budget_enabled", allow_audio)
			if not allow_audio:
				_stats["ai_engine_audio_disabled"] = int(_stats["ai_engine_audio_disabled"]) + 1


func _apply_aircraft_audio_budget(audio_nodes: Array, allow_audio: bool) -> void:
	for node_value in audio_nodes:
		var node: Node = node_value as Node
		if node == null or not is_instance_valid(node):
			continue
		_stats["ai_audio_nodes"] = int(_stats["ai_audio_nodes"]) + 1
		if allow_audio:
			# Presentation dormancy may temporarily detach an AI aircraft subtree.
			# Audio players remain valid Objects while detached, but Godot rejects
			# play() until they are back in the SceneTree.
			if not node.is_inside_tree():
				continue
			if node.has_meta("visual_budget_audio_was_playing") and bool(node.get_meta("visual_budget_audio_was_playing")):
				if node is AudioStreamPlayer:
					var audio_2d: AudioStreamPlayer = node as AudioStreamPlayer
					if not audio_2d.playing:
						audio_2d.play()
				elif node is AudioStreamPlayer3D:
					var audio_3d: AudioStreamPlayer3D = node as AudioStreamPlayer3D
					if not audio_3d.playing:
						audio_3d.play()
			continue
		_stop_audio_player(node)
		_stats["ai_audio_disabled"] = int(_stats["ai_audio_disabled"]) + 1


func _stop_audio_players_recursive(node: Node) -> void:
	_stop_audio_player(node)
	for child: Node in node.get_children():
		_stop_audio_players_recursive(child)


func _stop_audio_player(node: Node) -> void:
	if node is AudioStreamPlayer:
		var audio_2d: AudioStreamPlayer = node as AudioStreamPlayer
		if not audio_2d.has_meta("visual_budget_audio_was_playing"):
			audio_2d.set_meta("visual_budget_audio_was_playing", audio_2d.playing)
		if audio_2d.playing:
			audio_2d.stop()
	elif node is AudioStreamPlayer3D:
		var audio_3d: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		if not audio_3d.has_meta("visual_budget_audio_was_playing"):
			audio_3d.set_meta("visual_budget_audio_was_playing", audio_3d.playing)
		if audio_3d.playing:
			audio_3d.stop()


func _store_original_node_state(node: Node) -> void:
	if node.has_meta("visual_budget_original_process"):
		return
	node.set_meta("visual_budget_original_process", node.is_processing())
	node.set_meta("visual_budget_original_physics", node.is_physics_processing())
	node.set_meta("visual_budget_original_input", node.is_processing_input())
	if node is CanvasItem:
		node.set_meta("visual_budget_original_visible", (node as CanvasItem).visible)
	elif node is Node3D:
		node.set_meta("visual_budget_original_visible", (node as Node3D).visible)


func _restore_node_state(node: Node) -> void:
	node.set_process(bool(node.get_meta("visual_budget_original_process", node.is_processing())))
	node.set_physics_process(bool(node.get_meta("visual_budget_original_physics", node.is_physics_processing())))
	node.set_process_input(bool(node.get_meta("visual_budget_original_input", node.is_processing_input())))
	if node is CanvasItem:
		(node as CanvasItem).visible = bool(node.get_meta("visual_budget_original_visible", (node as CanvasItem).visible))
	elif node is Node3D:
		(node as Node3D).visible = bool(node.get_meta("visual_budget_original_visible", (node as Node3D).visible))


func _is_budget_effect_node(node: Node) -> bool:
	return node is DustEffect or node is RotorWashEffect or node is WingtipVortexEffect


func _is_player_only_aircraft_node(node: Node) -> bool:
	var node_name := str(node.name)
	return node_name in [
		"CameraController",
		"HeadsUpDisplay",
		"InstrumentPanel",
		"ControlTargeting",
		"AudioManager3D",
		"CockpitCanopyVisibility",
	]


func _is_ai_aircraft_detail_node(node: Node) -> bool:
	# Player-only roots have their own stricter lifecycle. Do not let the broader
	# near-aircraft detail pass restore a hidden cockpit UI node afterward.
	if _is_player_only_aircraft_node(node):
		return false
	var node_name: String = str(node.name)
	if node_name in [
		"CockpitPilot",
		"CameraCockpit",
		"CameraChase",
		"CameraCinematic",
		"CameraTarget",
	]:
		return true
	var lowered_name: String = node_name.to_lower()
	return lowered_name.find("instrument") >= 0 \
		or lowered_name.find("cockpit") >= 0


func _make_ref_array(nodes: Array) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for node_value in nodes:
		if node_value is Object and is_instance_valid(node_value):
			refs.append(weakref(node_value))
	return refs


func _resolve_ref_array(refs: Array) -> Array:
	var nodes: Array = []
	for ref_value in refs:
		var ref: WeakRef = ref_value as WeakRef
		if ref == null:
			continue
		var node: Object = ref.get_ref()
		if node == null or not is_instance_valid(node):
			continue
		nodes.append(node)
	return nodes


func _classify_band(distance_m: float, focused: bool) -> int:
	if focused:
		return BudgetBand.HUMAN
	if distance_m <= near_distance_m:
		return BudgetBand.NEAR
	if distance_m <= mid_distance_m:
		return BudgetBand.MID
	if distance_m <= far_distance_m:
		return BudgetBand.FAR
	return BudgetBand.CULLED


func _band_name(band: int) -> String:
	match band:
		BudgetBand.HUMAN:
			return "human"
		BudgetBand.NEAR:
			return "near"
		BudgetBand.MID:
			return "mid"
		BudgetBand.FAR:
			return "far"
		_:
			return "culled"


func _distance_to_camera(unit: Node3D, camera: Camera3D) -> float:
	if camera == null or not is_instance_valid(camera):
		return INF
	return unit.global_position.distance_to(camera.global_position)


func _is_unit_focused(unit: Node3D, camera: Camera3D) -> bool:
	return _is_unit_player_focused(unit, camera) \
		or VISUAL_FOCUS_HELPER.is_node_in_target_camera_focus(self, unit)


func _is_unit_player_focused(unit: Node3D, camera: Camera3D) -> bool:
	if _is_player_controlled(unit):
		return true
	var director := get_node_or_null("/root/FlightDirector")
	if director != null and director.get("current_viewed_aircraft") == unit:
		# Camera handoffs can briefly leave the viewport without the final camera.
		# The director's viewed-aircraft record is the stable authority for UI
		# budgeting during that handoff.
		return true
	if camera != null and is_instance_valid(camera) and _is_ancestor_of(unit, camera):
		return true
	return false


func _is_unit_in_frustum(unit: Node3D, camera: Camera3D) -> bool:
	if camera == null or not is_instance_valid(camera):
		return false
	if camera.is_position_in_frustum(unit.global_position):
		return true
	var up_offset: float = 18.0 if unit.is_in_group("ai_aircraft") or unit.is_in_group("aircraft") else 4.0
	return camera.is_position_in_frustum(unit.global_position + Vector3.UP * up_offset)


func _is_player_controlled(unit: Node3D) -> bool:
	var director := get_node_or_null("/root/FlightDirector")
	if director == null:
		return false
	var controlled: Variant = director.get("player_controlled_plane")
	return controlled == unit


func _is_ancestor_of(root: Node, possible_child: Node) -> bool:
	var current := possible_child
	while current != null:
		if current == root:
			return true
		current = current.get_parent()
	return false


func _get_active_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var camera := viewport.get_camera_3d()
	return camera if camera != null and is_instance_valid(camera) else null


func _prune_cache() -> void:
	var stale_ids: Array[int] = []
	var current_frame := Engine.get_process_frames()
	for id in _root_cache.keys():
		var cached: Dictionary = _root_cache[id]
		var root_ref: WeakRef = cached.get("root_ref", null) as WeakRef
		var root: Object = root_ref.get_ref() if root_ref != null else null
		if root == null or not is_instance_valid(root):
			var dead_session = cached.get("presentation_session")
			if dead_session != null:
				dead_session.discard_detached()
			stale_ids.append(int(id))
			continue
		if current_frame - int(cached.get("last_seen_frame", current_frame)) > 600:
			var stale_session = cached.get("presentation_session")
			if stale_session != null:
				stale_session.dispose()
			stale_ids.append(int(id))
	for id in stale_ids:
		_root_cache.erase(id)

	var stale_contrast_ids: Array[int] = []
	for id in _contrast_cache.keys():
		var cached: Dictionary = _contrast_cache[id]
		var root_ref: WeakRef = cached.get("root_ref", null) as WeakRef
		var root: Object = root_ref.get_ref() if root_ref != null else null
		if root != null and is_instance_valid(root) \
				and current_frame - int(cached.get("last_seen_frame", current_frame)) <= 600:
			continue
		var contrast_session = cached.get("contrast_session")
		if contrast_session != null:
			contrast_session.dispose()
		stale_contrast_ids.append(int(id))
	for id in stale_contrast_ids:
		_contrast_cache.erase(id)


func _reset_stats() -> void:
	_stats = {
		"enabled": enabled,
		"candidate_count": 0,
		"contrast_candidate_count": 0,
		"units_touched": 0,
		"air_units": 0,
		"ground_units": 0,
		"human": 0,
		"near": 0,
		"mid": 0,
		"far": 0,
		"culled": 0,
		"shadow_nodes": 0,
		"shadows_disabled": 0,
		"effect_nodes": 0,
		"effects_disabled": 0,
		"contrast_units_active": 0,
		"contrast_geometry_active": 0,
		"player_only_disabled": 0,
		"presentation_aircraft_detached": 0,
		"presentation_nodes_detached": 0,
		"aircraft_contact_monitors_disabled": 0,
		"ai_detail_nodes": 0,
		"ai_detail_disabled": 0,
		"ai_audio_nodes": 0,
		"ai_audio_disabled": 0,
		"ai_engine_visual_disabled": 0,
		"ai_engine_audio_disabled": 0,
		"cache_roots": _root_cache.size(),
	}
