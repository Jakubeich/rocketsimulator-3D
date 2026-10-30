extends SceneTree

## In orbit the newly released Dragon and the upper stage should drift apart
## according to their separation impulse, not accumulate float32 integration
## error simply because their absolute coordinates are large.
func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    rocket.set_physics_process(false)
    world.get_node("MissionTimeline").set_process(false)
    rocket.landed = true
    rocket._separate_stage()
    var upper = rocket.upper_vehicle
    upper.global_position = Vector3(1750000, -6000, 26000)
    upper.velocity = Vector3(7250, -1600, 50)
    upper.orbit_target_met = true
    rocket._detach_dragon()
    var d = rocket.dragon_vehicle.dynamics
    var initial_offset: Vector3 = d.position() - upper.global_position
    var relative_velocity: Vector3 = d.velocity() - upper.velocity
    for i in range(600):
        rocket._physics_process(0.2)
    var delta: Vector3 = d.position() - upper.global_position - initial_offset
    var prediction: Vector3 = relative_velocity * 120.0
    var deviation: float = delta.distance_to(prediction)
    # Small differences from gravity gradients, rotation and drag are real;
    # cumulative float-coordinate integration bias must not dominate them.
    if deviation > 5.0:
        push_error("RELATIVE ORBIT FAILED: unexpected drift %.2f m in 120 s" % deviation)
        quit(1)
        return
    print("RELATIVE ORBIT PASSED: %.2f m deviation over 120 s" % deviation)
    world.queue_free()
    await process_frame
    quit()
