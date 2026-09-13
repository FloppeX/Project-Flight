extends SceneTree

const Cache := preload("res://HUD/PanelSurfaceCache.gd")

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2, 2)
	var first := Cache.arrays(mesh, 0)
	var again := Cache.arrays(mesh, 0)
	assert(first == again, "same geometry reused")
	assert((mesh.get_meta(Cache.KEY) as Dictionary).surfaces.size() == 1)
	mesh.size = Vector2(4, 4)
	assert((mesh.get_meta(Cache.KEY) as Dictionary).surfaces.is_empty(), "resource edits invalidate geometry")
	var changed := Cache.arrays(mesh, 0)
	assert(changed[Mesh.ARRAY_VERTEX] != first[Mesh.ARRAY_VERTEX], "fresh geometry after edit")
	var copy := mesh.duplicate() as PlaneMesh
	Cache.arrays(copy, 0)
	copy.size = Vector2(6, 6)
	assert((copy.get_meta(Cache.KEY) as Dictionary).surfaces.is_empty(), "clone gets independent invalidation")
	assert((mesh.get_meta(Cache.KEY) as Dictionary).surfaces.size() == 1, "clone edit preserves original cache")
	print("PANEL_SURFACE_CACHE_SMOKE_PASS reuse=true edits=true duplicate=true")
	quit()
