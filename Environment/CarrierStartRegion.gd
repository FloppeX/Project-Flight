extends RefCounted
## Pick the starting clearing first, then frame the playable map north of it.
## Sampling happens before terrain/scene children enter the tree or navigation bakes.

static func find(terrain: LowPolyTerrain, half_extent: float, edge_padding: float,
		settings: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var nav_cell: float = settings.nav_cell
	var margin: float = settings.margin
	var max_x := terrain.quads_x * terrain.cell_size_m * 0.5 - half_extent - edge_padding - nav_cell
	var max_z := terrain.quads_z * terrain.cell_size_m * 0.5 - half_extent - edge_padding - nav_cell
	if max_x <= 0.0 or max_z <= 0.0:
		return {}
	var low_ceiling := terrain.base_height_offset_m + terrain.plateau_height_m - terrain.canyon_max_depth_m + 40.0
	for attempt in range(2048):
		var site := terrain.position + Vector3(rng.randf_range(-max_x, max_x), 0,
			rng.randf_range(-max_z, max_z) + half_extent - margin)
		var center := site + Vector3(0, 0, margin - half_extent)
		center.x = snappedf(center.x, nav_cell)
		center.z = snappedf(center.z, nav_cell)
		site = center + Vector3(0, 0, half_extent - margin)
		var local := site - terrain.position
		# Reject cliffs/high plateaus cheaply before building exact surface samples.
		var rough_h := terrain.get_local_height(local, false)
		if not is_finite(rough_h) or rough_h > low_ceiling:
			continue
		var radius: float = settings.radius + 72.0 # pad for nav/query cell neighbourhoods
		var variation: float = minf(settings.variation, settings.max_slope)
		var flat := true
		for offset in [Vector3(radius, 0, 0), Vector3(-radius, 0, 0),
				Vector3(0, 0, radius), Vector3(0, 0, -radius)]:
			var h := terrain.get_local_height(local + offset, false)
			if not is_finite(h) or absf(h - rough_h) > variation:
				flat = false
				break
		if not flat:
			continue
		var ground := terrain.get_local_height(local)
		var min_h := ground
		var max_h := ground
		for z in range(-int(radius), int(radius) + 1, 24):
			for x in range(-int(radius), int(radius) + 1, 24):
				if Vector2(x, z).length_squared() > radius * radius:
					continue
				var h := terrain.get_local_height(local + Vector3(x, 0, z))
				min_h = minf(min_h, h)
				max_h = maxf(max_h, h)
				if not is_finite(h) or max_h - min_h > variation:
					flat = false
					break
			if not flat:
				break
		if not flat:
			continue
		for angle in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0, 45.0]:
			var heading := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
			var right := Vector3(-heading.z, 0, heading.x)
			var clear := true
			for along in range(0, int(settings.distance) + 40, 40):
				for lateral in [-float(settings.half_width), 0.0, float(settings.half_width)]:
					var h := terrain.get_local_height(local + heading * along + right * lateral)
					if not is_finite(h) or h - ground > float(settings.max_rise):
						clear = false
						break
				if not clear:
					break
			if clear:
				site.y = ground + terrain.position.y
				return {"center": center, "position": site, "heading": heading, "attempts": attempt + 1}
	return {}
