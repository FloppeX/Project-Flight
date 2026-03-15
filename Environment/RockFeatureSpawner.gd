extends Node3D
class_name RockFeatureSpawner

## Scatters procedural rock features (pillars, clusters, arches) across the terrain.
## Reads colour parameters directly from the LowPolyTerrain node so features match.
## Add this node anywhere in the scene (position doesn't matter — features use world coords).

@export_group("Counts")
@export var pillar_count:  int = 30
@export var cluster_count: int = 20
@export var arch_count:    int = 12

@export_group("Placement")
## All features are placed within this radius of world origin.
@export var spawn_radius_m: float = 5500.0
## Don't spawn within this radius of origin (carrier start zone).
@export var inner_exclusion_m: float = 300.0
@export var rng_seed: int = 7777

@export_group("Pillar Size Range")
@export var pillar_height_min: float = 35.0
@export var pillar_height_max: float = 130.0
@export var pillar_radius_min: float = 8.0
@export var pillar_radius_max: float = 28.0

@export_group("Arch Size Range")
@export var arch_span_min:      float = 60.0
@export var arch_span_max:      float = 160.0
@export var arch_height_min:    float = 35.0
@export var arch_height_max:    float = 90.0
@export var arch_thickness_min: float = 12.0
@export var arch_thickness_max: float = 24.0

func _ready() -> void:
	if TerrainNavGrid.is_ready():
		_spawn()
	else:
		TerrainNavGrid.bake_complete.connect(_spawn, CONNECT_ONE_SHOT)

func _spawn() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as LowPolyTerrain

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var jobs: Array = [
		[RockFeature.FeatureType.PILLAR,  pillar_count],
		[RockFeature.FeatureType.CLUSTER, cluster_count],
		[RockFeature.FeatureType.ARCH,    arch_count],
	]
	var placed := 0
	for job in jobs:
		var ftype: int  = job[0]
		var count: int  = job[1]
		for _i in count:
			if _place_one(ftype, rng, terrain):
				placed += 1

	print("[RockFeatureSpawner] Placed %d features" % placed)

func _place_one(ftype: int, rng: RandomNumberGenerator, terrain: LowPolyTerrain) -> bool:
	# Centre placement on the terrain node so features land on the actual map.
	var cx := terrain.global_position.x if terrain else 0.0
	var cz := terrain.global_position.z if terrain else 0.0

	# Try up to 12 random positions; skip impassable (cliff/void) cells.
	for _attempt in 12:
		var angle := rng.randf() * TAU
		var dist  := rng.randf_range(inner_exclusion_m, spawn_radius_m)
		var wx    := cx + cos(angle) * dist
		var wz    := cz + sin(angle) * dist
		var wy    := TerrainNavGrid.sample_height(wx, wz)
		if wy <= TerrainNavGrid.IMPASSABLE * 0.5:
			continue

		var feature := RockFeature.new()
		feature.feature_type = ftype
		feature.rng_seed     = rng.randi()

		# Copy colour palette from terrain node
		if terrain:
			feature.canyon_floor_color   = terrain.canyon_floor_color
			feature.canyon_wall_color    = terrain.canyon_wall_color
			feature.canyon_upper_color   = terrain.canyon_upper_color
			feature.plateau_color        = terrain.plateau_color
			feature.steep_slope_color    = terrain.steep_slope_color
			feature.color_noise_strength = terrain.color_noise_strength
			feature.steep_slope_min_ny   = terrain.steep_slope_min_ny
			feature.steep_slope_band     = terrain.steep_slope_band
			feature.steep_slope_strength = terrain.steep_slope_strength
			# Height range for colour gradient (same formula as LowPolyTerrain._append_face)
			var floor_y := (terrain.base_height_offset_m
				+ terrain.plateau_height_m - terrain.canyon_max_depth_m
				+ terrain.global_position.y)
			var top_y   := (terrain.base_height_offset_m
				+ terrain.plateau_height_m + terrain.plateau_surface_amplitude_m * 0.5
				+ terrain.global_position.y)
			feature.color_floor_y = floor_y
			feature.color_top_y   = top_y

		# Randomise size
		match ftype:
			RockFeature.FeatureType.PILLAR, RockFeature.FeatureType.CLUSTER:
				feature.pillar_height = rng.randf_range(pillar_height_min, pillar_height_max)
				feature.pillar_radius = rng.randf_range(pillar_radius_min, pillar_radius_max)
			RockFeature.FeatureType.ARCH:
				feature.arch_span      = rng.randf_range(arch_span_min,      arch_span_max)
				feature.arch_height    = rng.randf_range(arch_height_min,    arch_height_max)
				feature.arch_thickness = rng.randf_range(arch_thickness_min, arch_thickness_max)

		# Place at terrain surface; arches partially buried so legs look embedded.
		var bury := feature.arch_thickness * 0.4 if ftype == RockFeature.FeatureType.ARCH else 0.0
		feature.position = Vector3(wx, wy - bury, wz)

		# Random yaw (arches benefit from this so you can approach from any direction)
		feature.rotation.y = rng.randf() * TAU

		add_child(feature)
		# build() is called inside _ready(), which fires when add_child completes.
		# global_position.y is valid at that point so colour lookups are correct.
		return true

	return false
