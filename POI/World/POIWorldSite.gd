extends Node3D

## Base behavior for lightweight physical POI sites. POIManager stores the
## authoritative location/state; this node supplies world presentation and
## follows floating-origin shifts through the scene hierarchy. FloatingOrigin
## already moves the site or its resource-source parent; there are no cached
## world coordinates here to shift a second time.
