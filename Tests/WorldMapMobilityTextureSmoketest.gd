extends SceneTree

const WorldMapTextureBuilder = preload("res://UI/WorldMapTextureBuilder.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cols := 5
	var rows := 5
	var heights := PackedFloat32Array()
	var clearance := PackedFloat32Array()
	heights.resize(cols * rows)
	clearance.resize(cols * rows)
	for gz in range(rows):
		for gx in range(cols):
			var idx := gz * cols + gx
			heights[idx] = float(gx * 20 + gz * 5)
			clearance[idx] = 0.0
	clearance[2 * cols + 1] = 80.0
	clearance[2 * cols + 2] = 160.0

	var layers := WorldMapTextureBuilder.build_images_from_data(
		heights,
		clearance,
		cols,
		rows,
		40.0
	)
	_expect(not layers.is_empty(), "synthetic map layers were not generated")
	var relief := layers.get("relief") as Image
	var mobility := layers.get("mobility") as Image
	_expect(relief != null, "relief image is missing")
	_expect(mobility != null, "mobility image is missing")
	if relief != null:
		_expect(relief.get_pixel(0, 0) != relief.get_pixel(4, 4), "continuous elevation tint did not change with height")
	if mobility != null:
		var blocked := mobility.get_pixel(0, 0)
		var vehicle := mobility.get_pixel(1, 2)
		var carrier := mobility.get_pixel(2, 2)
		_expect(blocked.r <= 0.001 and blocked.g <= 0.001, "blocked cell received a mobility mask")
		_expect(vehicle.r > 0.1 and vehicle.g <= 0.001, "vehicle-only cell was not encoded in the red mask channel")
		_expect(carrier.g > 0.1 and carrier.r <= 0.001, "carrier corridor was not encoded in the green mask channel")

	_expect(
		WorldMapTextureBuilder.mobility_class_for_clearance(59.9) == WorldMapTextureBuilder.MobilityClass.BLOCKED,
		"clearance below 60 m was not blocked"
	)
	_expect(
		WorldMapTextureBuilder.mobility_class_for_clearance(60.0) == WorldMapTextureBuilder.MobilityClass.VEHICLE,
		"60 m clearance was not vehicle-safe"
	)
	_expect(
		WorldMapTextureBuilder.mobility_class_for_clearance(120.0) == WorldMapTextureBuilder.MobilityClass.CARRIER,
		"120 m clearance was not carrier-safe"
	)
	_expect(float(layers.get("contour_interval_m", 0.0)) > 0.0, "contour interval was not selected")

	print("WORLD_MAP_MOBILITY_TEXTURE_SMOKETEST ", JSON.stringify({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"vehicle_cells": int(layers.get("vehicle_cells", -1)),
		"carrier_cells": int(layers.get("carrier_cells", -1)),
		"contour_interval_m": float(layers.get("contour_interval_m", 0.0)),
		"failures": _failures,
	}))
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[WorldMapMobilityTextureSmoketest] %s" % message)
