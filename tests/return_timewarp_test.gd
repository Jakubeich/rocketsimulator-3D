extends SceneTree

func _initialize() -> void:
    call_deferred("_test")

func _fly(dt: float) -> Dictionary:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    var rocket = world.get_node("Falcon9_CrewDragon")
    var legs = rocket.get_node("LandingLegs")
    rocket.set_physics_process(false)
    rocket.start_countdown()
    var elapsed := 0.0
    var previous_velocity := Vector3.ZERO
    while elapsed < 800.0 and not rocket.crashed and not rocket.landed:
        previous_velocity = rocket.velocity
        rocket._physics_process(dt)
        legs._process(dt)
        elapsed += dt
    var result := {"landed": rocket.landed, "crashed": rocket.crashed, "x": rocket.position.x, "z": rocket.position.z, "speed": previous_velocity.length(), "fuel": rocket.fuel, "time": elapsed}
    world.queue_free()
    return result

func _test() -> void:
    for multiplier in [1.0, 2.0, 5.0, 10.0]:
        var result := _fly(multiplier / 60.0)
        var miss := Vector2(result.x + 2000.0, result.z).length()
        if not result.landed or result.crashed or miss >= 43.0 or result.speed >= 5.0 or result.fuel <= 0.0:
            push_error("RETURN TIMEWARP FAILED at %.0fx: %s" % [multiplier, result])
            quit(1)
            return
        print("RETURN TIMEWARP %.0fx: LZ miss %.1f m, speed %.2f m/s, fuel %.0f kg" % [multiplier, miss, result.speed, result.fuel])
    quit()
