extends SceneTree

## Tests actual Godot physics callback ordering at stage separation. A fast
## booster must not advance a whole tick while a newly-created upper stage
## is still waiting for its first physics callback.
class SeparationObserver extends Node:
    var rocket
    var initial_upper_position: Vector3
    var interface_in_booster: Vector3
    var initial_booster_velocity: Vector3
    var failed := ""
    var observed_frames := 0
    var first_upper_elapsed := -1.0
    var first_gap := 0.0
    var first_lateral := 0.0
    var initial_axis: Vector3
    var first_ignition_clearance := -1.0
    var done := false

    func _physics_process(delta: float) -> void:
        if done or not rocket.stage_separated or not is_instance_valid(rocket.upper_vehicle):
            return
        var upper = rocket.upper_vehicle
        var tip: Vector3 = rocket.to_global(interface_in_booster)
        var upper_interface: Vector3 = rocket._upper_stage.global_position
        var axis: Vector3 = rocket.global_basis.y.normalized()
        var offset: Vector3 = upper_interface - tip
        var axial: float = offset.dot(axis)
        var lateral: float = (offset - axis * axial).length()
        var clearance: float = rocket._separation_clearance()
        if observed_frames == 0:
            first_upper_elapsed = upper.elapsed
            first_gap = axial
            first_lateral = lateral
            # From the end of the preceding tick to the end of this tick both
            # bodies should travel together, with only the separation impulse.
            var expected: Vector3 = initial_upper_position + initial_booster_velocity * delta
            var motion_error: float = upper_interface.distance_to(expected)
            if upper_interface.distance_to(upper.global_position) > 0.05:
                failed = "stage geometry jumped relative to its controller"
            elif motion_error > 3.0:
                failed = "upper stage missed or doubled a physics tick: motion error %.2f m, delta %.3f" % [motion_error, delta]
            elif upper.elapsed <= 0.001:
                failed = "upper stage was shifted without advancing its physics"
            elif absf(upper.elapsed - delta) > 0.025:
                failed = "upper stage time is not synchronized: upper %.3f s, delta %.3f s" % [upper.elapsed, delta]
            elif axial < -0.5:
                failed = "upper stage appeared %.2f m below the separation interface" % axial
            elif lateral > 2.0:
                failed = "upper stage jumped %.2f m sideways at separation" % lateral
        elif axial < -0.5:
            failed = "upper stage moved through booster: axial offset %.2f m" % axial
        if clearance < rocket.SEPARATION_NOZZLE_CLEARANCE and axis.dot(initial_axis) < cos(deg_to_rad(0.1)):
            failed = "booster rotated before the nozzle cleared the interstage"
        if upper.actual_throttle > 0.0 and first_ignition_clearance < 0.0:
            first_ignition_clearance = clearance
            if clearance < upper.SAFE_PLUME_CLEARANCE - 0.15:
                failed = "upper engine ignited at %.2f m, before safe plume clearance" % clearance
        observed_frames += 1
        if upper.elapsed > 15.0 and first_ignition_clearance < 0.0:
            failed = "upper-stage ignition did not occur after separation"
        if not failed.is_empty() or first_ignition_clearance >= 0.0:
            done = true

func _initialize() -> void:
    call_deferred("_test")

func _run_case(multiplier: float) -> bool:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    rocket.set_physics_process(false)
    world.get_node("MissionTimeline").set_process(false)
    rocket.position = Vector3(44582, 59760, 0)
    rocket.velocity = Vector3(1351.4, 1015.8, 0)
    rocket.rotation.z = -deg_to_rad(55.0)
    rocket.left_pad = true
    rocket.fuel = rocket.RESERVE_FUEL
    rocket.separation_timer = 0.01
    rocket.engine_on = false
    rocket.actual_throttle = 0.0
    var observer := SeparationObserver.new()
    observer.process_physics_priority = 1000
    observer.rocket = rocket
    observer.initial_upper_position = rocket._upper_stage.global_position
    observer.interface_in_booster = rocket.to_local(rocket._upper_stage.global_position)
    observer.initial_booster_velocity = rocket.velocity
    observer.initial_axis = rocket.global_basis.y.normalized()
    world.add_child(observer)
    Engine.time_scale = multiplier
    rocket.set_physics_process(true)
    while not observer.done:
        await process_frame
    var ok := observer.failed.is_empty()
    print("SEPARATION %.0fx: initial axial %.3f m, lateral %.3f m, upper elapsed %.3f s, ignition clearance %.2f m, frames %d" % [multiplier, observer.first_gap, observer.first_lateral, observer.first_upper_elapsed, observer.first_ignition_clearance, observer.observed_frames])
    if not ok:
        push_error("SEPARATION SYNC FAILED %.0fx: %s" % [multiplier, observer.failed])
    rocket.set_physics_process(false)
    if is_instance_valid(rocket.upper_vehicle):
        rocket.upper_vehicle.set_physics_process(false)
    world.queue_free()
    Engine.time_scale = 1.0
    await process_frame
    return ok

func _test() -> void:
    for multiplier in [1.0, 10.0]:
        if not await _run_case(multiplier):
            quit(1)
            return
    print("SEPARATION SYNC PASSED: real physics frames, continuity and no overlap")
    quit()
