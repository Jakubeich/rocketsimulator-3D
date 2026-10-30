extends SceneTree

## Exercise the actual snapshot/restore path across both separations, including
## replay of an in-progress canopy inflation and high-precision position.
func _initialize() -> void:
    call_deferred("_test")

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("DRAGON TIMELINE FAILED: " + message)
        quit(1)
    return condition

func _test() -> void:
    var world := (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    var timeline = world.get_node("MissionTimeline")
    rocket.set_physics_process(false)
    timeline.set_process(false)
    rocket.left_pad = true
    rocket.position = Vector3(0, 30000, 0)
    rocket.velocity = Vector3(1200, 900, 0)
    timeline.elapsed = 100.0
    timeline._capture()
    var assembled: Dictionary = timeline._history[-1].duplicate(true)

    rocket._separate_stage()
    rocket.upper_vehicle.global_position = Vector3(800000, 120000, 0)
    rocket.upper_vehicle.velocity = Vector3(7200, 150, 20)
    rocket.upper_vehicle.orbit_target_met = true
    rocket.dragon_separation_timer = 17.5
    timeline.elapsed = 110.0
    timeline._capture()
    var attached: Dictionary = timeline._history[-1].duplicate(true)
    var attached_parent: Node = rocket._dragon_root.get_parent()
    var attached_transform: Transform3D = rocket._dragon_root.transform
    var upper_velocity: Vector3 = rocket.upper_vehicle.velocity

    rocket._detach_dragon()
    if not _check(is_instance_valid(rocket.dragon_vehicle), "detachment must create an independent Dragon"): return
    var dragon = rocket.dragon_vehicle
    var d = dragon.dynamics
    d.x = 5000000.125
    d.y = -1800000.375
    d.z = 380000.0625
    d.vx = 11.125
    d.vy = -27.25
    d.vz = 8.5
    d.phase = "MAIN"
    d.phase_time = 7.5
    d.main_fraction = 0.45
    d.drogue_fraction = 0.2
    d.trunk_attached = false
    dragon.landing_elapsed = 3.5
    dragon.update_visuals()
    timeline.elapsed = 120.0
    timeline._capture()
    var separated: Dictionary = timeline._history[-1].duplicate(true)
    var saved_state: Dictionary = d.get_state().duplicate(true)

    # Back across Dragon separation, then across Falcon stage separation.
    timeline._restore(attached)
    if not _check(not is_instance_valid(rocket.dragon_vehicle), "rewinding must reattach Dragon"): return
    if not _check(rocket._dragon_root.get_parent() == attached_parent and rocket._dragon_root.transform.is_equal_approx(attached_transform), "rewinding must restore the exact model hierarchy and local transform"): return
    if not _check(rocket.upper_vehicle.carries_dragon and rocket.upper_vehicle.velocity.is_equal_approx(upper_velocity), "rewinding must restore upper stage mass and velocity"): return
    if not _check(is_equal_approx(rocket.dragon_separation_timer, 17.5), "rewinding restores separation countdown"): return
    timeline._restore(assembled)
    if not _check(not rocket.stage_separated and not is_instance_valid(rocket.upper_vehicle) and not is_instance_valid(rocket.dragon_vehicle), "rewinding both separations keeps the complete spacecraft"): return
    if not _check(is_instance_valid(rocket._dragon_root) and rocket._upper_stage.is_ancestor_of(rocket._dragon_root), "rewinding cannot lose imported Dragon geometry"): return

    # Forward from the fully assembled snapshot recreates both bodies and their
    # independent state, without applying the separation impulse twice.
    timeline._restore(separated)
    if not _check(is_instance_valid(rocket.upper_vehicle) and is_instance_valid(rocket.dragon_vehicle), "replay reconstructs both independent bodies"): return
    if not _check(not rocket.upper_vehicle.carries_dragon, "detached stage must not retain Dragon's mass"): return
    if not _check(rocket.dragon_vehicle.dynamics.get_state() == saved_state, "replay restores exact dynamics and canopy state"): return
    if not _check(is_equal_approx(rocket.dragon_vehicle.landing_elapsed, 3.5), "replay restores post-contact canopy animation"): return
    timeline._restore(attached)
    rocket.reset_flight()
    if not _check(not is_instance_valid(rocket.dragon_vehicle) and not is_instance_valid(rocket.upper_vehicle), "reset safely reassembles the model"): return
    print("DRAGON TIMELINE PASSED: snapshot, both separations, exact replay, canopy and reset")
    quit()
