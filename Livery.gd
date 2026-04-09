extends Node
## Livery — Autoload singleton that stores the player's chosen colors
## and applies them to aircraft and the carrier.
##
## Aircraft materials "upper fuselage" / "lower fuselage" use the chosen colors.
## Carrier materials "blue plasteel" / "dark blue plasteel" derive from upper_color
## so the whole fleet matches.
##
## Insignia decals use markers in aircraft scenes:
## - "InsigniaWing" (mirrored to left/right wings)
## - "InsigniaTail" (mirrored to left/right tail sides)
## Adjust marker position in the editor per aircraft.

@export var upper_color := Color(0.28, 0.33, 0.38)   # Dark blue-grey
@export var lower_color := Color(0.72, 0.73, 0.74)   # Light grey
## How much darker "dark blue plasteel" is relative to the base carrier color.
@export var carrier_dark_factor := 0.6
## Target width of the insignia on the wing (height adjusts to match aspect ratio).
@export var insignia_width := 1.0
## Decal projection depth — how far into the wing the decal reaches.
@export var insignia_depth := 0.6
## Tail insignia size (smaller than wing insignia).
@export var tail_insignia_width := 0.65
@export var tail_insignia_depth := 0.35
## Carrier hull insignia scale (much larger than wing insignia).
@export var carrier_insignia_width := 3.0
@export var carrier_insignia_depth := 2.0

## Insignia textures — loaded at startup.
var insignia_textures: Array[Texture2D] = []
var insignia_index: int = 0   # Which insignia is active
var _upper_color_preset_index: int = 0

const PRESET_UPPER_COLORS: Array[Color] = [
	Color(0.03, 0.03, 0.03),  # Black
	Color(0.96, 0.93, 0.82),  # Cream
	Color(0.93, 0.62, 0.74),  # Rose Pink
	Color(0.86, 0.28, 0.55),  # Hot Pink
	Color(0.78, 0.16, 0.16),  # Red
	Color(0.53, 0.09, 0.18),  # Crimson
	Color(0.55, 0.24, 0.12),  # Rust
	Color(0.86, 0.42, 0.14),  # Orange
	Color(0.90, 0.66, 0.18),  # Amber
	Color(0.62, 0.52, 0.14),  # Mustard
	Color(0.36, 0.38, 0.17),  # Olive
	Color(0.16, 0.47, 0.20),  # Green
	Color(0.10, 0.28, 0.14),  # Forest
	Color(0.47, 0.68, 0.56),  # Sage Mint
	Color(0.12, 0.46, 0.45),  # Teal
	Color(0.17, 0.62, 0.67),  # Cyan
	Color(0.46, 0.68, 0.86),  # Sky Blue
	Color(0.20, 0.33, 0.73),  # Cobalt
	Color(0.09, 0.13, 0.30),  # Navy
	Color(0.48, 0.32, 0.64),  # Violet
	Color(0.31, 0.17, 0.40),  # Plum
	Color(0.73, 0.60, 0.44),  # Tan
	Color(0.37, 0.24, 0.15),  # Brown
	Color(0.36, 0.40, 0.44),  # Steel Grey
]

func _ready() -> void:
	for path in _find_insignia_paths():
		var tex := load(path) as Texture2D
		if tex:
			insignia_textures.append(tex)
	_upper_color_preset_index = _nearest_upper_color_preset_index(upper_color)

var _c_was_pressed := false
var _v_was_pressed := false

func _process(_delta: float) -> void:
	var c_now := Input.is_key_pressed(KEY_C)
	var v_now := Input.is_key_pressed(KEY_V)
	if c_now and not _c_was_pressed:
		cycle_upper_color()
	if v_now and not _v_was_pressed:
		cycle_insignia()
	_c_was_pressed = c_now
	_v_was_pressed = v_now

func _find_insignia_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://Images/Insignia")
	if dir == null:
		return paths

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		var lower_name := file_name.to_lower()
		if not lower_name.begins_with("insignia_"):
			continue
		if not (lower_name.ends_with(".png") or lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg") or lower_name.ends_with(".webp")):
			continue
		paths.append("res://Images/Insignia/" + file_name)
	dir.list_dir_end()
	paths.sort()
	return paths

func randomize_upper_color() -> void:
	# Backward-compatible alias: C now cycles fixed presets instead of random.
	cycle_upper_color()

func cycle_upper_color() -> void:
	if PRESET_UPPER_COLORS.is_empty():
		return
	_upper_color_preset_index = (_upper_color_preset_index + 1) % PRESET_UPPER_COLORS.size()
	upper_color = PRESET_UPPER_COLORS[_upper_color_preset_index]
	_reapply_all()

func _nearest_upper_color_preset_index(col: Color) -> int:
	if PRESET_UPPER_COLORS.is_empty():
		return 0
	var best_idx: int = 0
	var best_dist_sq: float = INF
	for i in range(PRESET_UPPER_COLORS.size()):
		var p: Color = PRESET_UPPER_COLORS[i]
		var dr: float = col.r - p.r
		var dg: float = col.g - p.g
		var db: float = col.b - p.b
		var d_sq: float = dr * dr + dg * dg + db * db
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_idx = i
	return best_idx

func cycle_insignia() -> void:
	if insignia_textures.is_empty():
		return
	insignia_index = (insignia_index + 1) % insignia_textures.size()
	_reapply_all()

func _reapply_all() -> void:
	var seen := {}
	for group in ["aircraft", "ai_aircraft", "friendlies", "ground_vehicles"]:
		for node in get_tree().get_nodes_in_group(group):
			if node.get("team") == 1 and not seen.has(node):
				seen[node] = true
				apply(node)
	for carrier in get_tree().get_nodes_in_group("carrier"):
		apply(carrier)

## Apply livery colors and insignia to all matching surfaces under `root`.
func apply(root: Node) -> void:
	_apply_recursive(root)
	if root is RigidBody3D and root.get("team") != null:
		_apply_insignia(root)
	if root.is_in_group("carrier"):
		_apply_carrier_insignia(root)

func _apply_insignia(aircraft: Node) -> void:
	# Remove old decals from the full aircraft subtree.
	for decal in get_tree().get_nodes_in_group("livery_insignia"):
		if decal is Node and _is_descendant_of(decal as Node, aircraft):
			(decal as Node).queue_free()

	if insignia_textures.is_empty() or insignia_index < 0:
		return
	var tex: Texture2D = insignia_textures[insignia_index]

	# Compute aspect-correct decal size from texture dimensions
	var tex_w := float(tex.get_width())
	var tex_h := float(tex.get_height())
	var aspect := tex_h / maxf(tex_w, 1.0)
	var decal_size := Vector3(insignia_width, insignia_depth, insignia_width * aspect)

	# Single marker "InsigniaWing" — placed on one wing, mirrored to the other via X flip
	var marker: Marker3D = aircraft.get_node_or_null("InsigniaWing") as Marker3D
	if marker == null:
		return

	var aircraft_3d: Node3D = aircraft as Node3D
	if aircraft_3d == null:
		return
	var wing_hosts := _resolve_wing_hosts(aircraft)
	var right_wing_host: Node3D = wing_hosts["right"] as Node3D
	var left_wing_host: Node3D = wing_hosts["left"] as Node3D
	var x_sorted_hosts := _resolve_wing_hosts_by_aircraft_x(aircraft_3d, left_wing_host, right_wing_host)
	var positive_x_host: Node3D = x_sorted_hosts["positive"] as Node3D
	var negative_x_host: Node3D = x_sorted_hosts["negative"] as Node3D

	for side in [1.0, -1.0]:
		var t_local_to_aircraft := marker.transform
		t_local_to_aircraft.origin.x *= side
		t_local_to_aircraft.basis = t_local_to_aircraft.basis * Basis(Vector3.UP, PI)

		# Place +X marker copy on whichever wing is actually at +X in aircraft space.
		# This avoids left/right swaps on aircraft whose node names don't match X sign.
		var side_host: Node3D = positive_x_host if side > 0.0 else negative_x_host
		if side_host == null:
			side_host = right_wing_host if side > 0.0 else left_wing_host
		if side_host == null:
			side_host = aircraft_3d

		var decal := Decal.new()
		decal.name = "InsigniaWingDecal_R" if side > 0.0 else "InsigniaWingDecal_L"
		decal.add_to_group("livery_insignia")
		decal.texture_albedo = tex
		decal.size = decal_size
		side_host.add_child(decal)

		# Convert marker-based transform (authored in aircraft space) into host-local
		# so decals follow folding wing parts when applicable.
		var wing_local_t := _marker_transform_to_host_local(aircraft_3d, side_host, t_local_to_aircraft)
		decal.transform = wing_local_t

	# Optional tail insignia marker (mirrored and projected laterally into tail section).
	var tail_marker: Marker3D = aircraft.get_node_or_null("InsigniaTail") as Marker3D
	if tail_marker != null:
		var tail_size := Vector3(tail_insignia_width, tail_insignia_depth, tail_insignia_width * aspect)
		for side in [1.0, -1.0]:
			var tail_decal := Decal.new()
			tail_decal.name = "InsigniaTailDecal_R" if side > 0.0 else "InsigniaTailDecal_L"
			tail_decal.add_to_group("livery_insignia")
			tail_decal.texture_albedo = tex
			tail_decal.size = tail_size
			aircraft_3d.add_child(tail_decal)

			var t_tail := tail_marker.transform
			t_tail.origin.x *= side
			var local_y_axis: Vector3 = Vector3.RIGHT * side
			# Keep decal "up" consistent on both sides so the insignia is not upside down.
			var local_z_axis: Vector3 = Vector3.UP
			var local_x_axis: Vector3 = local_y_axis.cross(local_z_axis).normalized()
			t_tail.basis = Basis(local_x_axis, local_y_axis, local_z_axis)
			# Godot decal UV orientation on lateral projection needs a 180° roll
			# around the projection axis to keep the insignia readable.
			t_tail.basis = t_tail.basis * Basis(local_y_axis.normalized(), PI)
			tail_decal.transform = t_tail

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var cur: Node = node
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false

func _find_node3d_by_names(root: Node, names: Array[String]) -> Node3D:
	var desired: Array[String] = []
	for n in names:
		desired.append(n.to_lower())
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Node3D:
			var cur_name: String = cur.name.to_lower()
			if desired.has(cur_name):
				return cur as Node3D
		for child in cur.get_children():
			if child is Node:
				stack.append(child as Node)
	return null

func _resolve_wing_hosts(aircraft: Node) -> Dictionary:
	var left_host: Node3D = null
	var right_host: Node3D = null

	# Prefer explicit wing references captured by wing-fold scripts.
	var wing_fold5: Node = aircraft.get_node_or_null("WingFold5")
	if wing_fold5 != null:
		var left_variant: Variant = wing_fold5.get("_left_wing")
		var right_variant: Variant = wing_fold5.get("_right_wing")
		if left_variant is Node3D:
			left_host = left_variant as Node3D
		if right_variant is Node3D:
			right_host = right_variant as Node3D

	var wing_fold: Node = aircraft.get_node_or_null("WingFold")
	if wing_fold != null:
		if left_host == null:
			var left_variant: Variant = wing_fold.get("_left_wing")
			if left_variant is Node3D:
				left_host = left_variant as Node3D
		if right_host == null:
			var right_variant: Variant = wing_fold.get("_right_wing")
			if right_variant is Node3D:
				right_host = right_variant as Node3D

	# Fallback to name search for aircraft without wing-fold scripts.
	if right_host == null:
		right_host = _find_node3d_by_names(aircraft, ["outer wing right", "right outer wing"])
	if left_host == null:
		left_host = _find_node3d_by_names(aircraft, ["outer wing left", "left outer wing"])

	return {
		"left": left_host,
		"right": right_host,
	}

func _resolve_wing_hosts_by_aircraft_x(aircraft_root: Node3D, left_host: Node3D, right_host: Node3D) -> Dictionary:
	var hosts: Array[Node3D] = []
	if left_host != null:
		hosts.append(left_host)
	if right_host != null and right_host != left_host:
		hosts.append(right_host)
	if hosts.is_empty():
		return {"positive": null, "negative": null}

	var positive_host: Node3D = hosts[0]
	var negative_host: Node3D = hosts[0]
	var positive_x: float = _host_origin_x_in_aircraft_space(aircraft_root, hosts[0])
	var negative_x: float = positive_x
	for i in range(1, hosts.size()):
		var h: Node3D = hosts[i]
		var x: float = _host_origin_x_in_aircraft_space(aircraft_root, h)
		if x > positive_x:
			positive_x = x
			positive_host = h
		if x < negative_x:
			negative_x = x
			negative_host = h
	return {"positive": positive_host, "negative": negative_host}

func _host_origin_x_in_aircraft_space(aircraft_root: Node3D, host: Node3D) -> float:
	var rest_local_variant: Variant = _resolve_host_rest_local_transform(aircraft_root, host)
	var host_global: Transform3D
	if rest_local_variant is Transform3D:
		var host_parent: Node3D = host.get_parent() as Node3D
		if host_parent != null:
			host_global = host_parent.global_transform * (rest_local_variant as Transform3D)
		else:
			host_global = host.global_transform
	else:
		host_global = host.global_transform
	var host_in_aircraft: Transform3D = aircraft_root.global_transform.affine_inverse() * host_global
	return host_in_aircraft.origin.x

func _marker_transform_to_host_local(aircraft_root: Node3D, host: Node3D, marker_local_to_aircraft: Transform3D) -> Transform3D:
	var target_global: Transform3D = aircraft_root.global_transform * marker_local_to_aircraft
	var rest_local_variant: Variant = _resolve_host_rest_local_transform(aircraft_root, host)
	if rest_local_variant is Transform3D:
		var host_parent: Node3D = host.get_parent() as Node3D
		if host_parent != null:
			var host_rest_global: Transform3D = host_parent.global_transform * (rest_local_variant as Transform3D)
			return host_rest_global.affine_inverse() * target_global
	return host.global_transform.affine_inverse() * target_global

func _resolve_host_rest_local_transform(aircraft_root: Node3D, host: Node3D) -> Variant:
	var meta_rest: Variant = host.get_meta("livery_rest_transform_local", null)
	if meta_rest is Transform3D:
		return meta_rest

	# Fallback: ask wing-fold scripts for authored rest values if metadata
	# was not populated yet when livery was first applied.
	var wing_fold5: Node = aircraft_root.get_node_or_null("WingFold5")
	var rest_from_wf5: Variant = _resolve_rest_from_wing_fold5(wing_fold5, host)
	if rest_from_wf5 is Transform3D:
		return rest_from_wf5

	var wing_fold: Node = aircraft_root.get_node_or_null("WingFold")
	var rest_from_wf: Variant = _resolve_rest_from_wing_fold(wing_fold, host)
	if rest_from_wf is Transform3D:
		return rest_from_wf

	return null

func _resolve_rest_from_wing_fold5(wing_fold5: Node, host: Node3D) -> Variant:
	if wing_fold5 == null:
		return null
	var left_wing: Variant = wing_fold5.get("_left_wing")
	if left_wing == host:
		var left_quat: Variant = wing_fold5.get("_left_rest_quat")
		var left_pos: Variant = wing_fold5.get("_left_rest_pos")
		if left_quat is Quaternion and left_pos is Vector3:
			return Transform3D(Basis(left_quat as Quaternion), left_pos as Vector3)
	var right_wing: Variant = wing_fold5.get("_right_wing")
	if right_wing == host:
		var right_quat: Variant = wing_fold5.get("_right_rest_quat")
		var right_pos: Variant = wing_fold5.get("_right_rest_pos")
		if right_quat is Quaternion and right_pos is Vector3:
			return Transform3D(Basis(right_quat as Quaternion), right_pos as Vector3)
	return null

func _resolve_rest_from_wing_fold(wing_fold: Node, host: Node3D) -> Variant:
	if wing_fold == null:
		return null
	var left_wing: Variant = wing_fold.get("_left_wing")
	if left_wing == host:
		var left_quat: Variant = wing_fold.get("_left_rest_quat")
		var left_pos: Variant = wing_fold.get("_left_rest_pos")
		if left_quat is Quaternion and left_pos is Vector3:
			return Transform3D(Basis(left_quat as Quaternion), left_pos as Vector3)
	var right_wing: Variant = wing_fold.get("_right_wing")
	if right_wing == host:
		var right_quat: Variant = wing_fold.get("_right_rest_quat")
		var right_pos: Variant = wing_fold.get("_right_rest_pos")
		if right_quat is Quaternion and right_pos is Vector3:
			return Transform3D(Basis(right_quat as Quaternion), right_pos as Vector3)
	return null

func _apply_carrier_insignia(carrier: Node) -> void:
	# Remove old carrier decals
	for child in carrier.get_children():
		if child.is_in_group("livery_carrier_insignia"):
			child.queue_free()

	if insignia_textures.is_empty() or insignia_index < 0:
		return
	var tex: Texture2D = insignia_textures[insignia_index]

	var tex_w := float(tex.get_width())
	var tex_h := float(tex.get_height())
	var aspect := tex_h / maxf(tex_w, 1.0)
	var decal_size := Vector3(carrier_insignia_width, carrier_insignia_depth, carrier_insignia_width * aspect)

	# Place a decal at each InsigniaHull marker. Only position matters — rotation is ignored.
	# Name ending with "R" projects toward +X (starboard), otherwise toward -X (port).
	for child in carrier.get_children():
		if child is Marker3D and child.name.begins_with("InsigniaHull"):
			var inward := -1.0 if child.name.ends_with("R") else 1.0
			var decal := Decal.new()
			decal.name = child.name + "Decal"
			decal.add_to_group("livery_carrier_insignia")
			decal.texture_albedo = tex
			decal.size = decal_size
			decal.transform.origin = child.transform.origin
			decal.transform.basis = Basis(
				Vector3(0, 0, -1),         # decal X → carrier aft
				Vector3(inward, 0, 0),     # decal -Y → projects into wall
				Vector3(0, -1, 0)          # decal Z → down
			)
			carrier.add_child(decal)

func _apply_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				var mat = mesh.surface_get_material(i)
				if mat == null:
					continue
				var mat_name: String = mat.resource_name.to_lower()
				var target_color := Color(-1, 0, 0)  # sentinel
				if "upper fuselage" in mat_name or "upper_fuselage" in mat_name:
					target_color = upper_color
				elif "lower fuselage" in mat_name or "lower_fuselage" in mat_name:
					target_color = lower_color
				elif "dark blue plasteel" in mat_name:
					target_color = Color(
						upper_color.r * carrier_dark_factor,
						upper_color.g * carrier_dark_factor,
						upper_color.b * carrier_dark_factor,
						upper_color.a
					)
				elif "blue plasteel" in mat_name:
					target_color = upper_color
				if target_color.r >= 0.0:
					var override: StandardMaterial3D
					if mat is StandardMaterial3D:
						override = mat.duplicate() as StandardMaterial3D
					else:
						override = StandardMaterial3D.new()
					override.albedo_color = target_color
					mi.set_surface_override_material(i, override)
	for child in node.get_children():
		_apply_recursive(child)
