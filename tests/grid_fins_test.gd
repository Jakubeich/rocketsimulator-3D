extends SceneTree

const GridFins := preload("res://scripts/grid_fins.gd")

func _initialize() -> void:
    call_deferred("_test")

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("GRID FINS FAILED: " + message)
        quit(1)
    return condition

func _max_radius(booster: Node3D, pivot: Node3D) -> float:
    var maximum := 0.0
    for mesh in pivot.find_children("*", "MeshInstance3D", true, false):
        var bounds: AABB = mesh.get_aabb()
        for index in range(8):
            var point: Vector3 = booster.to_local(mesh.global_transform * bounds.get_endpoint(index))
            maximum = maxf(maximum, Vector2(point.x, point.z).length())
    return maximum

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var booster = world.get_node("Falcon9_CrewDragon")
    booster.set_physics_process(false)
    var fins = booster.get_node("GridFins")
    fins.set_process(false)
    if not _check(fins._usable and fins._pivots.size() == 4, "all original grid fin pivots must resolve"): return
    var stowed_radii: Array[float] = []
    for pivot in fins._pivots:
        stowed_radii.append(_max_radius(booster, pivot))
    fins.set_deployed(true)
    fins._process(GridFins.DEPLOY_TIME * 0.5)
    if not _check(is_equal_approx(fins._amount, 0.5), "deployment must be gradual"): return
    fins._process(GridFins.DEPLOY_TIME * 0.5)
    if not _check(is_equal_approx(fins._amount, 1.0), "deployment must reach its target"): return
    for index in range(4):
        if not _check(_max_radius(booster, fins._pivots[index]) > stowed_radii[index] + 0.7, "fin %d must extend outward" % index): return
        if not _check(fins._pivots[index].transform.origin.is_equal_approx(fins._originals[index].origin), "hinge position must not move"): return
    var neutral: Array[Transform3D] = []
    for pivot in fins._pivots:
        neutral.append(pivot.transform)
    fins.set_steering(Vector2(1.0, 1.0))
    fins._process(1.0)
    var deflected := false
    for index in range(4):
        var angle := neutral[index].basis.get_rotation_quaternion().angle_to(fins._pivots[index].basis.get_rotation_quaternion())
        if not _check(angle <= GridFins.MAX_STEERING_ANGLE + 0.001, "steering must stay within its limit"): return
        deflected = deflected or angle > 0.01
    if not _check(deflected, "steering must visibly deflect a deployed fin"): return
    var saved: Dictionary = fins.get_state()
    var steered: Array[Transform3D] = []
    for pivot in fins._pivots:
        steered.append(pivot.transform)
    fins.reset_fins()
    for index in range(4):
        if not _check(fins._pivots[index].transform.is_equal_approx(fins._originals[index]), "reset must restore original stowed transform"): return
    fins.set_state(saved)
    for index in range(4):
        if not _check(fins._pivots[index].transform.is_equal_approx(steered[index]), "snapshot must restore exact fin pose"): return
    if not _check(fins.process_mode == Node.PROCESS_MODE_PAUSABLE, "deployment must pause with the flight"): return
    print("GRID FINS PASSED: four pivots, outward deployment, limited steering, rewind and reset")
    quit()
