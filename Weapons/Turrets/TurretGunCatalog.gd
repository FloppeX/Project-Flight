extends RefCounted

const CALIBERS: Array[int] = [10, 15, 20, 25, 40]
const PROFILE_PATHS := {
	10: "res://Weapons/Guns/Profiles/10mm_machine_gun.tres",
	15: "res://Weapons/Guns/Profiles/15mm_machine_gun.tres",
	20: "res://Weapons/Guns/Profiles/20mm_autocannon.tres",
	25: "res://Weapons/Guns/Profiles/25mm_autocannon.tres",
	40: "res://Weapons/Guns/Profiles/40mm_autocannon.tres",
}

static func get_profile(caliber: int) -> Resource:
	if not PROFILE_PATHS.has(caliber):
		return null
	return load(PROFILE_PATHS[caliber])

static func get_barrel_scene(caliber: int) -> PackedScene:
	if not CALIBERS.has(caliber):
		return null
	return load("res://Models/Turrets/gun barrel %d mm.glb" % caliber) as PackedScene
