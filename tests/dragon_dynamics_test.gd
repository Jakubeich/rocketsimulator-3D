extends SceneTree

## A complete, deterministic return from a representative simulated orbit.
## Run: Godot --headless --path . --script res://tests/dragon_dynamics_test.gd
const Dragon := preload("res://scripts/dragon_dynamics.gd")

func _initialize() -> void:
    call_deferred("_test")

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("DRAGON DYNAMICS FAILED: " + message)
        quit(1)
    return condition

func _test() -> void:
    var d = Dragon.new()
    # State from the existing upper-stage ascent and orbital insertion test.
    d.initialize(Vector3(1252680.0, 109887.0, 12597.31), Vector3(7199.998, -1372.231, 90.02341))
    if not _check(d.start_return() and not d.start_return(), "one return command only"): return
    var initial_state: Dictionary = d.get_state()
    var started: float = d.elapsed
    d.step(-1.0)
    if not _check(d.elapsed == started, "negative time cannot advance the simulation"): return
    var order: Array[String] = []
    var drogue_speed := 0.0
    var main_speed := 0.0
    var drogue_height := 0.0
    var main_height := 0.0
    var deployed_snapshot := {}
    var previous_phase := ""
    for i in range(30000):
        d.step(0.1)
        if d.phase != previous_phase:
            order.append(d.phase)
            previous_phase = d.phase
            if d.phase == "DROGUE":
                drogue_speed = d.velocity().length()
                drogue_height = d.altitude()
            elif d.phase == "MAIN":
                main_speed = d.velocity().length()
                main_height = d.altitude()
        if d.phase == "DEORBIT" and not _check(d.trunk_attached and d.trunk_release_time < 0.0, "trunk remains attached during deorbit"): return
        if d.phase == "ENTRY" and not _check(not d.trunk_attached and d.trunk_release_time >= Dragon.DEORBIT_SECONDS, "trunk release follows deorbit"): return
        if d.phase == "MAIN" and d.main_fraction > 0.3 and deployed_snapshot.is_empty():
            deployed_snapshot = d.get_state()
        if d.landed:
            break
    if not _check(order == ["DEORBIT", "ENTRY", "DROGUE", "MAIN", "LANDED"], "ordered phases: " + str(order)): return
    if not _check(drogue_height > 5400.0 and drogue_height <= Dragon.DROGUE_ALTITUDE, "drogue altitude"): return
    if not _check(main_height > 1750.0 and main_height <= Dragon.MAIN_ALTITUDE, "main altitude"): return
    # NASA reports approximately 156 m/s and 53 m/s at deployment. These
    # bands allow the intentionally simplified atmosphere and entry model.
    if not _check(drogue_speed > 130.0 and drogue_speed < 190.0, "drogue speed: " + str(drogue_speed)): return
    if not _check(main_speed > 40.0 and main_speed < 65.0, "main speed: " + str(main_speed)): return
    if not _check(d.impact_speed > 6.0 and d.impact_speed < 10.0 and d.main_fraction > 0.99, "parachute descent speed"): return
    if not _check(d.altitude() < 0.01 and not deployed_snapshot.is_empty(), "spherical ground and deployment snapshot"): return
    var frozen: Dictionary = d.get_state()
    d.step(10.0)
    if not _check(d.get_state() == frozen, "flight stops after impact"): return

    # Restore a snapshot taken during inflation, then verify replay, including
    # the scalar-double coordinates that preserve sub-metre motion far away.
    d.set_state(deployed_snapshot)
    var resumed = Dragon.new()
    resumed.set_state(deployed_snapshot)
    d.step(10.0)
    for i in range(100): resumed.step(0.1)
    if not _check(absf(d.x-resumed.x) < 0.001 and absf(d.y-resumed.y) < 0.001 and absf(d.z-resumed.z) < 0.001, "rewind replay preserves position"): return
    if not _check(absf(d.vx-resumed.vx) < 0.001 and absf(d.vy-resumed.vy) < 0.001 and d.phase == resumed.phase and absf(d.main_fraction-resumed.main_fraction) < 0.0001, "rewind replay preserves velocity and inflation"): return
    resumed.set_state(initial_state)
    if not _check(resumed.get_state() == initial_state and resumed.trunk_attached, "rewind restores trunk and all state"): return

    # Arming logic never fires on ascent or on an unsafe fast trajectory.
    var fast = Dragon.new()
    fast.initialize(Vector3(0, 5400, 0), Vector3(0, -300, 0))
    fast.phase = "ENTRY"
    fast.trunk_attached = false
    fast.step(0.02)
    if not _check(fast.phase == "ENTRY" and fast.drogue_time < 0.0, "unsafe speed must not open drogues"): return
    var ascending = Dragon.new()
    ascending.initialize(Vector3(0, 5400, 0), Vector3(0, 100, 0))
    ascending.phase = "ENTRY"
    ascending.trunk_attached = false
    ascending.step(0.02)
    if not _check(ascending.phase == "ENTRY", "ascent must not open drogues"): return
    print("DRAGON DYNAMICS PASSED: full orbit-to-ground return; drogues %.0f m/s at %.0f m, mains %.0f m/s at %.0f m, contact %.2f m/s" % [drogue_speed, drogue_height, main_speed, main_height, float(frozen.impact_speed)])
    quit()
