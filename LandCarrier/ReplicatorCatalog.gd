extends RefCounted
## Shared recipe definitions: UI, transactions, delivery and chamber visuals.
const STARTER_IDS: Array[String] = ["aircraft_5", "aircraft_11", "kmv_explorer", "harvester", "bombs", "rockets", "bullets", "gun_10mm"]
const VEHICLE_STAGES: Array[String] = ["LOWER STRUCTURE", "LOWER ASSEMBLY", "BODY ASSEMBLY", "UPPER ASSEMBLY", "FINAL SYSTEMS"]
const AIRFRAME_STAGES: Array[String] = ["LOWER STRUCTURE", "LOWER ASSEMBLY", "AIRFRAME ASSEMBLY", "UPPER ASSEMBLY", "FINAL SYSTEMS"]
const ORDNANCE_STAGES: Array[String] = ["BASE ASSEMBLY", "LOWER ASSEMBLY", "BODY ASSEMBLY", "UPPER ASSEMBLY", "SEAL / INSPECT"]
const BLUEPRINTS: Array[Dictionary] = [
	{"id": "harvester", "name": "RESOURCE HARVESTER", "type": "SIX-WHEELED COLLECTION VEHICLE", "category": "VEHICLES", "plasteel": 120, "corium": 18, "duration_s": 110.0, "output_count": 1, "destination": "VEHICLE BAY", "scene": "res://GroundVehicle/Harvester.tscn", "description": "Unarmed industrial collector. Deploy from Active Platoons to gather corium deposits and salvage plasteel; carries 160 units home per trip.", "stages": VEHICLE_STAGES},
	{"id": "aircraft_5", "name": "SNA JAS-44 KESTREL", "type": "AIRCRAFT 5 / MULTIROLE FIGHTER", "category": "AIRFRAMES", "plasteel": 260, "corium": 90, "duration_s": 240.0, "output_count": 1, "destination": "FLIGHT HANGAR", "scene": "res://Aircraft/Aircraft_5.tscn", "description": "Delta-canard multirole fighter. Delivered unassigned to the hangar for flight assembly.", "stages": AIRFRAME_STAGES},
	{"id": "aircraft_11", "name": "AD UH-8 HUMMINGBIRD", "type": "AIRCRAFT 11 / UTILITY HELICOPTER", "category": "AIRFRAMES", "plasteel": 180, "corium": 55, "duration_s": 180.0, "output_count": 1, "destination": "FLIGHT HANGAR", "scene": "res://Aircraft/Aircraft_11.tscn", "description": "Agile utility helicopter. Delivered to the hangar for rescue and carrier operations.", "stages": AIRFRAME_STAGES},
	{"id": "kmv_explorer", "name": "KMV EXPLORER", "type": "GROUND VEHICLE 1 / SCOUT / UTILITY", "category": "VEHICLES", "plasteel": 80, "corium": 12, "duration_s": 90.0, "output_count": 1, "destination": "VEHICLE BAY", "scene": "res://GroundVehicle/ground_vehicle_1.tscn", "description": "Reliable four-wheeled scout/utility vehicle, but lacking in armor. Mounts a 10 mm machine gun and can recover downed pilots.", "stages": VEHICLE_STAGES},
	# Preserve the legacy recipe ID for existing unlocked blueprints and queued builds.
	{"id": "light_combat_vehicle", "name": "KMV DEFENDER", "type": "GROUND VEHICLE 2 / LIGHT ATTACK / TRANSPORT", "category": "VEHICLES", "plasteel": 80, "corium": 12, "duration_s": 90.0, "output_count": 1, "destination": "VEHICLE BAY", "scene": "res://GroundVehicle/ground_vehicle_2.tscn", "description": "Six-wheeled light attack/transport vehicle. Rolled into the vehicle bay for platoon deployment.", "stages": VEHICLE_STAGES},
	{"id": "bombs", "build_scene": "res://Models/Weapons/ReplicatorWeaponsCrate.tscn", "name": "GENERAL-PURPOSE BOMB", "type": "ONE UNGUIDED BOMB", "category": "ORDNANCE", "plasteel": 15, "corium": 6, "duration_s": 25.0, "output_count": 1, "destination": "ORDNANCE STORES", "scene": "res://Weapons/Bomb/bomb.tscn", "description": "One general-purpose bomb, packed into carrier ordnance stores.", "stages": ORDNANCE_STAGES},
	{"id": "rockets", "build_scene": "res://Models/Weapons/ReplicatorWeaponsCrate.tscn", "name": "UNGUIDED ROCKETS", "type": "BATCH / 6 ROCKETS", "category": "ORDNANCE", "plasteel": 24, "corium": 10, "duration_s": 35.0, "output_count": 6, "destination": "ORDNANCE STORES", "scene": "res://Models/Weapons/rocket.glb", "description": "Six unguided rockets per batch, packed into carrier ordnance stores.", "stages": ORDNANCE_STAGES},
	{"id": "bullets", "build_scene": "res://Models/Weapons/ReplicatorWeaponsCrate.tscn", "name": "10 MM BULLETS", "type": "BATCH / 200 ROUNDS", "category": "ORDNANCE", "plasteel": 12, "corium": 2, "duration_s": 20.0, "output_count": 200, "destination": "ORDNANCE STORES", "scene": "", "description": "Two hundred 10 mm rounds per ammunition box, stored separately from finished guns.", "stages": ORDNANCE_STAGES},
	{"id": "gun_10mm", "name": "10 MM MACHINE GUN", "type": "ONE HARDPOINT GUN / UNLOADED", "category": "ORDNANCE", "plasteel": 25, "corium": 15, "duration_s": 45.0, "output_count": 1, "destination": "ORDNANCE STORES", "scene": "res://Weapons/Guns/Hardpoint/10mm_machine_gun_hardpoint.tscn", "description": "One reusable 10 mm hardpoint gun assembly. Bullets are fabricated separately.", "stages": ORDNANCE_STAGES},
]

static func recipe(id: String) -> Dictionary:
	for blueprint in BLUEPRINTS:
		if str(blueprint.id) == id:
			return blueprint
	return {}
