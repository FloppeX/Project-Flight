extends RefCounted
## Curated primary gameplay scenes shown by the main-menu Technical Index.
## Helper scenes, destroyed variants, holders, projectiles, and templates are
## deliberately excluded so the guide describes usable vehicles and equipment.

const CATEGORY_ORDER: Array[String] = [
	"LAND CARRIER",
	"AIRPLANES",
	"HELICOPTERS",
	"STRUCTURES",
	"WEAPONS",
]

static var CATALOG: Dictionary = {
	"LAND CARRIER": [
		{
			"name": "LAND CARRIER",
			"scene": "res://LandCarrier/LandCarrier2.tscn",
			"description": "Mobile carrier and operational base supporting flight, recovery, repair, and ground-force deployment.",
			"stats": {"CLASS": "MOBILE CARRIER", "SYSTEMS": "FLIGHT DECK / HANGAR / VEHICLE BAY"},
		},
		{
			"name": "DECK TRACTOR",
			"scene": "res://LandCarrier/TractorBot.tscn",
			"description": "Compact deck-handling vehicle used to position aircraft around the carrier's operating surfaces.",
			"stats": {"CLASS": "DECK SUPPORT", "CREW": "AUTONOMOUS"},
		},
		{
			"name": "CARRIER DEFENSE TURRET",
			"scene": "res://LandCarrier/CarrierDefenseTurret.tscn",
			"description": "Carrier-mounted defensive weapon assembly for local air and surface protection.",
			"stats": {"CLASS": "DEFENSIVE TURRET", "MOUNT": "CARRIER"},
		},
	],
	"AIRPLANES": [
		_aircraft_entry(1),
		_aircraft_entry(2),
		_aircraft_entry(3),
		_aircraft_entry(4),
		_aircraft_entry(5),
		_aircraft_entry(6),
		_aircraft_entry(7),
		_aircraft_entry(8),
	],
	"HELICOPTERS": [
		_helicopter_entry(9),
		_helicopter_entry(10),
		_helicopter_entry(11),
		{
			"name": "HELICOPTER 12",
			"scene": "res://Aircraft/Aircraft_12.tscn",
			"description": "Rotary-wing aircraft configuration 12. Values shown are read from the active scene definition.",
			"stats": {"CLASS": "ROTARY-WING", "CONFIGURATION": "12"},
		},
	],
	"STRUCTURES": [
		_structure_entry("AIRFIELD", "res://Buildings/building_enemy_airfield.tscn", "Complete hostile airfield complex used to support local aviation operations."),
		_structure_entry("RUNWAY", "res://Buildings/building_enemy_runway.tscn", "Prepared operating strip associated with an enemy airfield."),
		_structure_entry("BASE STRUCTURE", "res://Buildings/building_enemy_base_structure.tscn", "Primary hardened structure used within enemy base installations."),
		_structure_entry("BARRACKS", "res://Buildings/building_barracks.tscn", "Personnel and logistics structure used by enemy ground forces."),
		_structure_entry("WIND TURBINE", "res://Buildings/building_wind_turbine.tscn", "Power-generation structure supplying regional infrastructure."),
		_structure_entry("GUN EMPLACEMENT", "res://Buildings/gun_emplacement.tscn", "Fixed defensive position mounting a traversable weapon system."),
	],
	"WEAPONS": [
		_weapon_entry("10 MM MACHINE GUN", "res://Weapons/Guns/Hardpoint/10mm_machine_gun_hardpoint.tscn", "HARDPOINT", "10 MM"),
		_weapon_entry("15 MM MACHINE GUN", "res://Weapons/Guns/Hardpoint/15mm_machine_gun_hardpoint.tscn", "HARDPOINT", "15 MM"),
		_weapon_entry("20 MM AUTOCANNON", "res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn", "HARDPOINT", "20 MM"),
		_weapon_entry("25 MM AUTOCANNON", "res://Weapons/Guns/Hardpoint/25mm_autocannon_hardpoint.tscn", "HARDPOINT", "25 MM"),
		_weapon_entry("40 MM AUTOCANNON", "res://Weapons/Guns/Hardpoint/40mm_autocannon_hardpoint.tscn", "HARDPOINT", "40 MM"),
		_weapon_entry("10 MM GUN TURRET", "res://Weapons/Guns/Turrets/10mm_machine_gun_turret_weapon.tscn", "TURRET", "10 MM"),
		_weapon_entry("15 MM GUN TURRET", "res://Weapons/Guns/Turrets/15mm_machine_gun_turret_weapon.tscn", "TURRET", "15 MM"),
		_weapon_entry("20 MM GUN TURRET", "res://Weapons/Guns/Turrets/20mm_autocannon_turret_weapon.tscn", "TURRET", "20 MM"),
		_weapon_entry("25 MM GUN TURRET", "res://Weapons/Guns/Turrets/25mm_autocannon_turret_weapon.tscn", "TURRET", "25 MM"),
		_weapon_entry("40 MM GUN TURRET", "res://Weapons/Guns/Turrets/40mm_autocannon_turret_weapon.tscn", "TURRET", "40 MM"),
		_weapon_entry("ROCKET POD", "res://Weapons/RocketPod/rocket_pod.tscn", "HARDPOINT", "ROCKET"),
		_weapon_entry("AA MISSILE LAUNCHER", "res://Weapons/AA_Missile/aa_missile_launcher.tscn", "HARDPOINT", "GUIDED"),
		_weapon_entry("AG MISSILE", "res://Weapons/AG_Missile/missile_visual.tscn", "AIR-LAUNCHED", "GUIDED"),
		_weapon_entry("GENERAL-PURPOSE BOMB", "res://Weapons/Bomb/bomb.tscn", "AIR-LAUNCHED", "UNGUIDED"),
	],
}


static func categories() -> Array[String]:
	return CATEGORY_ORDER.duplicate()


static func entries_for(category: String) -> Array[Dictionary]:
	var source: Array = CATALOG.get(category, [])
	var entries: Array[Dictionary] = []
	for entry_variant in source:
		if entry_variant is Dictionary:
			entries.append((entry_variant as Dictionary).duplicate(true))
	return entries


static func _aircraft_entry(index: int) -> Dictionary:
	return {
		"name": "AIRCRAFT %02d" % index,
		"scene": "res://Aircraft/Aircraft_%d.tscn" % index,
		"description": "Fixed-wing aircraft configuration %02d. Values shown are read from the active scene definition." % index,
		"stats": {"CLASS": "FIXED-WING", "CONFIGURATION": "%02d" % index},
	}


static func _helicopter_entry(index: int) -> Dictionary:
	return {
		"name": "HELICOPTER %02d" % index,
		"scene": "res://Aircraft/Aircraft_%d.tscn" % index,
		"description": "Rotary-wing aircraft configuration %02d. Values shown are read from the active scene definition." % index,
		"stats": {"CLASS": "ROTARY-WING", "CONFIGURATION": "%02d" % index},
	}


static func _structure_entry(name: String, scene_path: String, description: String) -> Dictionary:
	return {
		"name": name,
		"scene": scene_path,
		"description": description,
		"stats": {"CLASS": "STRUCTURE"},
	}


static func _weapon_entry(name: String, scene_path: String, mount: String, caliber: String) -> Dictionary:
	return {
		"name": name,
		"scene": scene_path,
		"description": "Operational weapon assembly. Performance values are read from the configured scene when available.",
		"stats": {"CLASS": "WEAPON", "MOUNT": mount, "CALIBER / TYPE": caliber},
	}
