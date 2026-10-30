extends "res://scripts/rocket_flight.gd"

var contact_speed := -1.0

func _advance_flight(delta: float) -> void:
    var before: Vector3 = velocity
    super._advance_flight(delta)
    if (landed or crashed) and contact_speed < 0.0:
        contact_speed = before.length()
