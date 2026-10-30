extends SceneTree

## Regression: small temporary attitude disturbances with guidance enabled
## must still permit a powered LZ-1 return.
## Run with Godot --headless --path <project> --script res://tests/return_tilt_test.gd
func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    for case in [
        {"axis": "z", "degrees": 5.0},
        {"axis": "z", "degrees": -5.0},
        {"axis": "x", "degrees": 5.0},
        {"axis": "x", "degrees": -5.0},
    ]:
        var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
        root.add_child(world)
        current_scene = world
        await process_frame
        var rocket = world.get_node("Falcon9_CrewDragon")
        rocket.set_physics_process(false)
        var legs = rocket.get_node("LandingLegs")
        rocket.toggle_engine()
        var applied := false
        var landing_engine_seen := false
        var last_velocity := Vector3.ZERO
        for step in range(16000):
            if rocket.left_pad and rocket.position.y > 200.0 and not applied:
                if case.axis == "x":
                    rocket.rotation.x = deg_to_rad(case.degrees)
                else:
                    rocket.rotation.z = deg_to_rad(case.degrees)
                applied = true
            last_velocity = rocket.velocity
            rocket._physics_process(0.05)
            legs._process(0.05)
            if rocket.stage_separated:
                if rocket.return_pilot.phase == "LANDING_BURN" and rocket._active_engine_count == 1:
                    landing_engine_seen = true
            if rocket.landed or rocket.crashed:
                break
        var distance: float = Vector2(rocket.position.x + 2000.0, rocket.position.z).length()
        if not applied or not rocket.landed or rocket.crashed or distance >= 43.0 or rocket.fuel <= 0.0 or not landing_engine_seen:
            push_error("TILT RETURN FAILED: " + str(case) + " landed=" + str(rocket.landed) + " crashed=" + str(rocket.crashed) + " LZ error=" + str(distance) + " fuel=" + str(rocket.fuel) + " single landing engine=" + str(landing_engine_seen))
            quit(1)
            return
        print("TILT RETURN PASSED: ", case, " LZ error ", distance, " m, speed ", last_velocity.length(), " m/s, fuel ", rocket.fuel, " kg")
        world.queue_free()
        current_scene = null
        await process_frame
    quit()
