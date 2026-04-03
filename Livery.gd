extends Node
## Livery — Autoload singleton that stores the player's chosen colors
## and applies them to aircraft and the carrier.
##
## Aircraft materials "upper fuselage" / "lower fuselage" use the chosen colors.
## Carrier materials "blue plasteel" / "dark blue plasteel" derive from upper_color
## so the whole fleet matches.
##
## Insignia decals are placed at Marker3D nodes named "InsigniaRight" / "InsigniaLeft"
## in each aircraft scene. Adjust marker position/rotation in the editor per aircraft.

@export var upper_color := Color(0.28, 0.33, 0.38)   # Dark blue-grey
@export var lower_color := Color(0.72, 0.73, 0.74)   # Light grey
## How much darker "dark blue plasteel" is relative to the base carrier color.
@export var carrier_dark_factor := 0.6
## Target width of the insignia on the wing (height adjusts to match aspect ratio).
@export var insignia_width := 1.0
## Decal projection depth — how far into the wing the decal reaches.
@export var insignia_depth := 0.6
## Carrier hull insignia scale (much larger than wing insignia).
@export var carrier_insignia_width := 3.0
@export var carrier_insignia_depth := 2.0

## Insignia textures — loaded at startup.
var insignia_textures: Array[Texture2D] = []
var insignia_index: int = 0   # Which insignia is active

func _ready() -> void:
	for path in _find_insignia_paths():
		var tex := load(path) as Texture2D
		if tex:
			insignia_textures.append(tex)

var _c_was_pressed := false
var _v_was_pressed := false

func _process(_delta: float) -> void:
	var c_now := Input.is_key_pressed(KEY_C)
	var v_now := Input.is_key_pressed(KEY_V)
	if c_now and not _c_was_pressed:
		randomize_upper_color()
	if v_now and not _v_was_pressed:
		cycle_insignia()
	_c_was_pressed = c_now
	_v_was_pressed = v_now

func _find_insignia_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://")
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
		paths.append("res://" + file_name)
	dir.list_dir_end()
	paths.sort()
	return paths

func randomize_upper_color() -> void:
	upper_color = Color.from_hsv(randf(), randf_range(0.3, 0.7), randf_range(0.3, 0.7))
	_reapply_all()

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
	# Remove old decals
	for child in aircraft.get_children():
		if child.is_in_group("livery_insignia"):
			child.queue_free()

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
	for side in [1.0, -1.0]:
		var decal := Decal.new()
		decal.name = "InsigniaWingDecal_R" if side > 0.0 else "InsigniaWingDecal_L"
		decal.add_to_group("livery_insignia")
		decal.texture_albedo = tex
		decal.size = decal_size
		var t := marker.transform
		t.origin.x *= side
		t.basis = t.basis * Basis(Vector3.UP, PI)
		decal.transform = t
		aircraft.add_child(decal)

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
