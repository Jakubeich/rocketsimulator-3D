extends SceneTree

## Verifies the actual 50x control, callback duration and landing velocity at
## the last integration substep rather than the previous rendered frame.
const Probe := preload("res://tests/helpers/rocket_impact_probe.gd")
const Dragon := preload("res://scripts/dragon_dynamics.gd")

class ClockObserver extends Node:
    var seconds := 0.0
    var last_delta := 0.0
    func _physics_process(delta: float) -> void:
        seconds += delta
        last_delta = delta

func _initialize() -> void:
    call_deferred("_test")

func _check(ok: bool, message: String) -> bool:
    if not ok:
        push_error("TIMEWARP 50X FAILED: " + message)
        Engine.time_scale = 1.0
        quit(1)
    return ok

func _dragon_return(step: float) -> Dictionary:
    var dragon = Dragon.new()
    dragon.initialize(Vector3(1252680.0, 109887.0, 12597.31), Vector3(7199.998, -1372.231, 90.02341))
    dragon.start_return()
    var phases := []
    var last := ""
    for i in range(4000 * 5):
        dragon.step(step)
        if last != dragon.phase:
            phases.append(dragon.phase)
            last = dragon.phase
        if dragon.landed:
            break
    return {"phase": dragon.phase, "order": phases, "time": dragon.elapsed, "speed": dragon.impact_speed, "x": dragon.x, "y": dragon.y, "z": dragon.z}

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    var rocket = world.get_node("Falcon9_CrewDragon")
    rocket.set_script(Probe)
    root.add_child(world)
    current_scene = world
    await process_frame
    var timeline = world.get_node("MissionTimeline")
    var hud = world.get_node("FlightHUD")
    if not _check(hud._time_rates.has(50.0), "50x button is missing"): return
    hud._time_rates[50.0].pressed.emit()
    if not _check(timeline.rate == 50.0 and Engine.time_scale == 50.0 and rocket._time_index == 4, "50x rate must be selected"): return
    rocket._publish_telemetry()
    var clock := ClockObserver.new()
    world.add_child(clock)
    var warmup := Time.get_ticks_msec()
    while Time.get_ticks_msec() - warmup < 250:
        await process_frame
    clock.seconds = 0.0
    var before := Time.get_ticks_msec()
    while Time.get_ticks_msec() - before < 1000:
        await process_frame
    var wall := (Time.get_ticks_msec() - before) / 1000.0
    if not _check(absf(clock.last_delta - 50.0 / 60.0) < 0.005, "physics callback must advance by 50/60 seconds at 60 Hz"): return
    if not _check(clock.seconds / wall > 5.0, "actual callbacks must advance faster than real time: %.2fx" % (clock.seconds / wall)): return
    timeline._on_action("pause")
    if not _check(paused and timeline.rate == 50.0, "pause retains 50x selection"): return
    timeline._on_action("forward")
    if not _check(not paused and timeline.rate == 10.0, "forward at live edge uses bounded 10x"): return
    timeline._on_action("pause")
    if not _check(paused and timeline.rate == 50.0 and Engine.time_scale == 50.0, "cancelling a forward jump restores 50x"): return
    timeline._on_action("pause")
    timeline.cycle_rate()
    if not _check(timeline.rate == 1.0 and Engine.time_scale == 1.0, "cycle after 50x must return to 1x"): return
    var actual_multiplier := clock.seconds / wall
    clock.queue_free()
    rocket.set_physics_process(false)
    timeline.set_process(false)
    rocket.reset_flight()
    rocket.start_countdown()
    var legs = rocket.get_node("LandingLegs")
    var elapsed := 0.0
    while elapsed < 800.0 and not rocket.crashed and not rocket.landed:
        rocket._physics_process(50.0 / 60.0)
        legs._process(50.0 / 60.0)
        elapsed += 50.0 / 60.0
    var miss := Vector2(rocket.position.x + 2000.0, rocket.position.z).length()
    if not _check(rocket.landed and not rocket.crashed and miss < 43.0 and rocket.contact_speed >= 0.0 and rocket.contact_speed < 5.1, "50x full booster return at substep resolution: miss %.2f m, speed %.2f m/s" % [miss, rocket.contact_speed]): return
    var upper = rocket.upper_vehicle
    if not _check(is_instance_valid(upper), "upper stage is available for snapshot"): return
    upper.position_residual = Vector3(0.12, -0.14, 0.06)
    timeline.elapsed = elapsed
    timeline._capture()
    var saved: Dictionary = timeline._history[-1].duplicate(true)
    upper.position_residual = Vector3.ZERO
    timeline._restore(saved)
    if not _check(upper.position_residual.is_equal_approx(Vector3(0.12, -0.14, 0.06)) and upper._last_integrated_position == upper.global_position, "rewind restores upper-stage precision residual"): return
    var normal := _dragon_return(0.2)
    var fast := _dragon_return(50.0 / 60.0)
    var position_difference := Vector3(normal.x - fast.x, normal.y - fast.y, normal.z - fast.z).length()
    if not _check(fast.phase == "LANDED" and fast.order == normal.order and absf(fast.speed - normal.speed) < 0.2 and absf(fast.time - normal.time) < 3.0 and position_difference < 300.0, "50x Dragon return must preserve phase order and final descent: normal %s, fast %s, offset %.1f m" % [normal, fast, position_difference]): return
    print("TIMEWARP 50X PASSED: callbacks %.1fx real time; booster miss %.1f m and contact %.2f m/s; Dragon offset %.1f m" % [actual_multiplier, miss, rocket.contact_speed, position_difference])
    world.queue_free()
    await process_frame
    quit(0)
