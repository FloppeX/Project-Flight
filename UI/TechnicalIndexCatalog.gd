extends RefCounted
## Curated primary gameplay scenes shown by the main-menu Technical Index.
## Helper scenes, destroyed variants, holders, projectiles, and templates are
## deliberately excluded so the guide describes usable vehicles and equipment.

const CATEGORY_ORDER: Array[String] = [
	"GROUND VEHICLES",
	"AIRPLANES",
	"HELICOPTERS",
	"STRUCTURES",
	"WEAPONS",
]

static var CATALOG: Dictionary = {
	"GROUND VEHICLES": [
		{
			"name": "LAND CARRIER",
			"scene": "res://LandCarrier/LandCarrier2.tscn",
			"description": "Mobile carrier and operational base supporting flight, recovery, repair, and ground-force deployment.",
			"stats": {"CLASS": "MOBILE CARRIER", "ALLEGIANCE": "FRIENDLY", "SYSTEMS": "FLIGHT DECK / HANGAR / VEHICLE BAY"},
		},
		_ground_vehicle_entry("FRIENDLY LIGHT COMBAT VEHICLE", "res://GroundVehicle/vehicle_friendly_light.tscn", "Carrier-aligned six-wheeled combat vehicle used by deployed ground platoons.", "FRIENDLY"),
		_ground_vehicle_entry("ENEMY ATTACK BUGGY", "res://GroundVehicle/vehicle_enemy_buggy.tscn", "Fast, tightly turning light attack vehicle mounting a machine-gun turret.", "HOSTILE"),
		_ground_vehicle_entry("ENEMY ARMED PICKUP", "res://GroundVehicle/vehicle_enemy_pickup.tscn", "Fast armed utility truck with greater durability than the light buggy.", "HOSTILE"),
		_ground_vehicle_entry("ENEMY BATTLE BUS", "res://GroundVehicle/vehicle_enemy_battle_bus.tscn", "Heavy enemy support vehicle carrying both light and heavy defensive weapons.", "HOSTILE"),
	],
	"AIRPLANES": [
		_aircraft_entry(1, "SNA AS-20 Sand Sprite", "Light fighter/attack/recon plane; versatile, modular, but slightly underpowered when loaded."),
		_aircraft_entry(2, "HK A-88 Crusader", "Heavy attack platform; fast, rock-solid bombing platform with low maneuverability."),
		_aircraft_entry(3, "VMFC F-9 Wasp", "Obsolescent, primitive light fighter/attack plane; low-tech, rugged, and easy to maintain."),
		_aircraft_entry(4, "OKB TB-60 Vulture", "Slow, heavily armored attack bomber equipped with defensive gun turrets."),
		_aircraft_entry(5, "SNA JAS-44 Kestrel", "Balanced and capable delta-canard fighter/attack aircraft."),
		_aircraft_entry(6, "OKB Sh-37 Razorback", "Heavy armored ground-attack aircraft; slow, rugged, and stable, built around a centerline high-velocity 40 mm autocannon. Uses an older high-bypass turboprop, making it practically obsolete against modern opponents but devastating in low-threat airspace."),
		_aircraft_entry(7, "OKB I-109 Dagger", "High-speed, high-altitude interceptor built for pure climb and sprint rates."),
		_aircraft_entry(8, "VAS SF/A-21 Ghost", "Stealthy blended-wing attack/fighter aircraft."),
	],
	"HELICOPTERS": [
		_helicopter_entry(9, "VMFC HH-72 Bumblebee", "Heavy rescue/utility helicopter with defensive guns and an armored tub."),
		_helicopter_entry(10, "TAG RA-14 Dune Skimmer", "Light recon/attack helicopter."),
		_helicopter_entry(11, "AD UH-8 Hummingbird", "Zippy, quiet utility/armed recon helicopter built for agility."),
		_helicopter_entry(12, "HK AH-99 Huntsman", "Heavy armored attack helicopter with coaxial rotors and heavy anti-armor ordnance."),
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
		{
			"name": "CARRIER DEFENSE TURRET",
			"scene": "res://LandCarrier/CarrierDefenseTurret.tscn",
			"description": "Carrier-mounted defensive weapon assembly for local air and surface protection.",
			"stats": {"CLASS": "DEFENSIVE TURRET", "MOUNT": "CARRIER"},
		},
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


static func _aircraft_entry(index: int, display_name: String = "", description: String = "") -> Dictionary:
	var resolved_name := display_name if not display_name.is_empty() else "AIRCRAFT %02d" % index
	var resolved_description := description if not description.is_empty() else "Fixed-wing aircraft configuration %02d. Values shown are read from the active scene definition." % index
	return {
		"name": resolved_name,
		"scene": "res://Aircraft/Aircraft_%d.tscn" % index,
		"description": resolved_description,
		"stats": {"CLASS": "FIXED-WING", "CONFIGURATION": "%02d" % index},
	}


static func _helicopter_entry(index: int, display_name: String = "", description: String = "") -> Dictionary:
	var resolved_name := display_name if not display_name.is_empty() else "HELICOPTER %02d" % index
	var resolved_description := description if not description.is_empty() else "Rotary-wing aircraft configuration %02d. Values shown are read from the active scene definition." % index
	return {
		"name": resolved_name,
		"scene": "res://Aircraft/Aircraft_%d.tscn" % index,
		"description": resolved_description,
		"stats": {"CLASS": "ROTARY-WING", "CONFIGURATION": "%02d" % index},
	}


static func _ground_vehicle_entry(name: String, scene_path: String, description: String, allegiance: String) -> Dictionary:
	return {
		"name": name,
		"scene": scene_path,
		"description": description,
		"stats": {"CLASS": "GROUND VEHICLE", "ALLEGIANCE": allegiance},
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
