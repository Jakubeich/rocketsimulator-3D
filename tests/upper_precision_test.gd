extends SceneTree

# At 1.75 million metres, the 32-bit spacing of Vector3 coordinates is 0.125 m.
# Repeated sub-pixel displacement used to round down every time, causing drift
# against the independent Dragon trajectory.
func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var upper := Node3D.new()
    upper.set_script(load("res://scripts/upper_stage.gd"))
    root.add_child(upper)
    upper.set_physics_process(false)
    upper.global_position = Vector3(1750000, 180000, 0)
    for i in range(1000):
        upper._translate_precisely(Vector3(0.03, 0.0, 0.0))
    var advanced: float = upper.global_position.x - 1750000.0
    if absf(advanced - 30.0) > 0.13:
        push_error("UPPER PRECISION FAILED: expected 30 m, got %.3f m" % advanced)
        quit(1)
        return
    # Explicit position changes, such as editor manipulation and test fixtures,
    # must not carry a residual from the old location to the new one.
    upper.position_residual = Vector3(0.06, 0, 0)
    upper.global_position = Vector3(1750010, 180000, 0)
    upper._translate_precisely(Vector3.ZERO)
    if upper.position_residual.length_squared() > 0.000001:
        push_error("UPPER PRECISION FAILED: stale residual after external reposition")
        quit(1)
        return
    upper.queue_free()
    print("UPPER PRECISION PASSED: sub-ULP motion preserved, external reposition resets remainder")
    quit()
