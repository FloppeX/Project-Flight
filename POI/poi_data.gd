class_name POIData
extends Resource

enum Category { RESOURCE_CACHE, WATER, SETTLEMENT, BLUEPRINT, INTEL, HAZARD }

@export var id: String = ""
@export var title: String = ""
@export var body: String = ""
@export var category: Category = Category.RESOURCE_CACHE
@export var image: Texture2D = null
## Optional choices shown as buttons. Empty = single Confirm button.
@export var choices: Array[String] = []
## Detection radius in meters (default 800m).
@export var detection_radius_m: float = 800.0
## If true, POI requires line-of-sight to be discovered (terrain won't block obvious ones).
@export var requires_line_of_sight: bool = true

