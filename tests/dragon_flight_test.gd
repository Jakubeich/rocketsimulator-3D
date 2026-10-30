extends SceneTree
const Earth := preload("res://scripts/world_physics.gd")
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
    rocket.start_countdown()
    var stage_time := -1.0
    for i in range(3000):
        rocket._physics_process(0.2)
        if is_instance_valid(rocket.dragon_vehicle):
            stage_time = i * 0.2
            break
    if stage_time < 0.0:
        return _fail("Dragon did not separate after nominal launch and cutoff")
    var upper = rocket.upper_vehicle
    var dragon = rocket.dragon_vehicle
    if upper.carries_dragon or not upper.orbit_target_met or dragon.model.get_parent() != dragon:
        return _fail("wrong separation hierarchy or upper-stage state")
    var distance: float = dragon.global_position.distance_to(rocket._dragon_root.global_position)
    if distance > 0.1:
        return _fail("Dragon model changed pose at separation")
    if not dragon.dynamics.start_return():
        return _fail("return could not be started")
    var phases := {}
    for i in range(24000):
        rocket._physics_process(0.2)
        var d = dragon.dynamics
        if not phases.has(d.phase):
            phases[d.phase] = [d.elapsed, d.altitude(), d.velocity().length()]
        if d.landed: break
    var d = dragon.dynamics
    if d.phase != "LANDED":
        return _fail("nominal trajectory did not reach field: phase %s altitude %.1f speed %.1f phases %s" % [d.phase, d.altitude(), d.velocity().length(), phases])
    if not phases.has("DROGUE") or not phases.has("MAIN") or d.impact_speed > 12.0:
        return _fail("parachute phases or landing speed incorrect: %s" % [phases])
    print("DRAGON FULL FLIGHT PASSED separation %.1f s, phases %s, contact %.2f m/s" % [stage_time, phases, d.impact_speed])
    rocket.reset_flight()
    if is_instance_valid(rocket.dragon_vehicle) or rocket._dragon_root.get_parent() != rocket._dragon_parent:
        return _fail("reset did not reassemble Dragon")
    world.queue_free()
    await process_frame
    quit(0)
func _fail(message: String) -> void:
    push_error("DRAGON FULL FLIGHT FAILED: " + message)
    quit(1)
