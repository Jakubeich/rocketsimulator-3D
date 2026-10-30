extends SceneTree

## Run: Godot --headless --path <project> --script res://tests/booster_return_test.gd
## A full default flight is simulated deterministically without waiting in real time.
func _initialize() -> void:
    call_deferred("_test")

func _check(ok: bool, message: String) -> bool:
    if not ok:
        push_error("RETURN TEST FAILED: " + message)
        quit(1)
        return false
    return true

func _test() -> void:
    var world := (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    rocket.set_physics_process(false)
    var effects = rocket.get_node("EngineEffects")
    var legs = rocket.get_node("LandingLegs")
    var original_parent = rocket._upper_parent
    var original_transform: Transform3D = rocket._upper_transform
    var phases := {}
    var was_separated := false
    var separation_fuel := 0.0
    var last_velocity := Vector3.ZERO
    var max_turn_rate := 0.0
    var first_separation_time := -1.0
    var boostback_time := -1.0
    var separation_x := 0.0
    var separation_height := 0.0
    var max_downrange := 0.0
    var max_booster_height := 0.0
    var saw_returning_velocity := false
    rocket.toggle_engine()
    for step in range(16000):
        last_velocity = rocket.velocity
        var previous_axis: Vector3 = rocket.basis.y.normalized()
        rocket._physics_process(0.05)
        var current_axis: Vector3 = rocket.basis.y.normalized()
        max_turn_rate = maxf(max_turn_rate, rad_to_deg(acos(clampf(previous_axis.dot(current_axis), -1.0, 1.0))) / 0.05)
        legs._process(0.05)
        if rocket.stage_separated:
            if not was_separated:
                was_separated = true
                separation_fuel = rocket.fuel
                first_separation_time = step * 0.05
                separation_x = rocket.position.x
                separation_height = rocket.position.y
                if not _check(is_instance_valid(rocket.upper_vehicle), "upper stage must exist independently"): return
                if not _check(rocket._upper_stage.get_parent() == rocket.upper_vehicle, "upper stage must be detached"): return
                if not _check(effects._engine_count == 3, "return uses three displayed engines"): return
            phases[rocket.return_pilot.phase] = true
            if rocket.return_pilot.phase == "BOOSTBACK" and boostback_time < 0.0:
                boostback_time = step * 0.05
            if rocket.return_pilot.phase == "FLIP" and not _check(rocket.actual_throttle == 0.0, "flip must not fire the main engines"): return
            max_downrange = maxf(max_downrange, rocket.position.x)
            max_booster_height = maxf(max_booster_height, rocket.position.y)
            saw_returning_velocity = saw_returning_velocity or rocket.velocity.x < -100.0
        if rocket.landed or rocket.crashed:
            break
    if not _check(was_separated and separation_fuel <= rocket.RESERVE_FUEL, "automatic separation at fuel reserve"): return
    for phase in ["FLIP", "BOOSTBACK", "COAST", "ENTRY_ALIGN", "ENTRY_BURN", "ENTRY_COAST", "LANDING_BURN"]:
        if not _check(phases.has(phase), "missing recovery phase " + phase): return
    if not _check(first_separation_time > 100.0 and separation_x > 20000.0 and separation_height > 40000.0, "ascent must pitch downrange before separation"): return
    if not _check(boostback_time - first_separation_time > 10.0 and max_turn_rate < 9.5, "flip must be gradual and rate-limited"): return
    if not _check(max_downrange > separation_x + 10000.0 and max_booster_height > separation_height + 20000.0 and saw_returning_velocity, "booster must coast outward and reverse downrange velocity"): return
    if not _check(rocket.landed and not rocket.crashed, "default flight must land without crashing"): return
    if not _check(Vector2(rocket.position.x + 2000.0, rocket.position.z).length() < 43.0, "booster must land on LZ-1"): return
    if not _check(last_velocity.length() < 5.0, "landing speed must be gentle"): return
    if not _check(rocket.fuel > 0.0, "default return must retain some fuel"): return
    if not _check(legs._amount > 0.99, "landing legs must deploy"): return
    print("RETURN PASSED: LZ-1 ", rocket.position, ", speed ", last_velocity.length(), ", fuel ", rocket.fuel)
    var upper = rocket.upper_vehicle
    var elapsed_at_landing: float = upper.elapsed
    for step in range(6500):
        rocket._physics_process(0.05)
        if upper.orbit_target_met or upper.impacted: break
    if not _check(upper.elapsed > elapsed_at_landing, "upper stage must continue after booster landing"): return
    var orbit: Dictionary = upper.orbital_elements()
    if not _check(upper.orbit_target_met and not upper.impacted and orbit.periapsis >= 170000.0 and orbit.apoapsis <= 400000.0, "upper stage must reach the modeled orbit on the default flight"): return
    print("ORBIT PASSED: perigee %.0f km, apogee %.0f km" % [orbit.periapsis / 1000.0, orbit.apoapsis / 1000.0])
    rocket.reset_flight()
    if not _check(not rocket.stage_separated and rocket._upper_stage.get_parent() == original_parent, "reset must reassemble the rocket"): return
    if not _check(rocket._upper_stage.transform.is_equal_approx(original_transform), "reset must restore upper-stage transform"): return
    if not _check(rocket.fuel == rocket.INITIAL_FUEL and legs._amount == 0.0 and effects._engine_count == 9, "reset must restore fuel, legs and engines"): return
    quit()
