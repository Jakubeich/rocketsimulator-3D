extends SceneTree

## Run with: Godot --headless --path <project> --script res://tests/flight_smoke_test.gd
func _initialize() -> void:
    call_deferred("_test")

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("FLIGHT TEST FAILED: " + message)
        quit(1)
        return false
    return true

func _send_key(code: Key, down: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = down
    Input.parse_input_event(event)

func _test() -> void:
    var packed := load("res://scenes/launch_site.tscn") as PackedScene
    if not _check(packed != null, "launch scene must load"): return
    var world := packed.instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    var effects = rocket.get_node("EngineEffects")
    if not _check(effects._plumes.size() == 9, "all nine engine markers must resolve"): return
    if not _check(not rocket.engine_on and rocket.fuel == rocket.INITIAL_FUEL, "initial state"): return
    _send_key(KEY_SPACE, true)
    await process_frame
    _send_key(KEY_SPACE, false)
    if not _check(rocket.countdown > 9.0, "Space must start countdown"): return
    for i in range(60): rocket._physics_process(0.1)
    if not _check(not rocket.engine_on and rocket.position.y == 0.0, "hold before ignition"): return
    for i in range(20): rocket._physics_process(0.1)
    if not _check(rocket.engine_on and rocket.actual_throttle > 0.0 and rocket.position.y == 0.0, "ignite before release"): return
    if not _check(rocket.fuel < rocket.INITIAL_FUEL, "ignition consumes fuel"): return
    for i in range(40): rocket._physics_process(0.1)
    if not _check(rocket.left_pad and rocket.position.y > 0.0 and rocket.velocity.y > 0.0, "rocket must lift off"): return
    var fuel_at_cutoff: float = rocket.fuel
    rocket.toggle_engine()
    rocket._physics_process(0.1)
    if not _check(not rocket.engine_on and rocket.actual_throttle == 0.0 and rocket.fuel == fuel_at_cutoff, "shutdown stops thrust and fuel consumption"): return
    rocket.engine_on = true
    rocket.fuel = 0.01
    rocket._physics_process(0.1)
    if not _check(rocket.fuel == 0.0 and not rocket.engine_on, "fuel depletion shuts off engine"): return
    rocket.reset_flight()
    if not _check(rocket.position == Vector3.ZERO and rocket.velocity == Vector3.ZERO and rocket.fuel == rocket.INITIAL_FUEL, "reset restores state"): return
    rocket.left_pad = true
    rocket.position.y = 20.0
    rocket.engine_on = true
    _send_key(KEY_RIGHT, true)
    await physics_frame
    await physics_frame
    await process_frame
    _send_key(KEY_RIGHT, false)
    if not _check(rocket.rotation.z > 0.0, "arrow keys steer"): return
    _send_key(KEY_S, true)
    await physics_frame
    await physics_frame
    await process_frame
    _send_key(KEY_S, false)
    if not _check(rocket.commanded_throttle < 1.0, "S reduces throttle"): return
    rocket.rotation = Vector3(0, 0, -0.25)
    rocket.velocity = Vector3.ZERO
    rocket._physics_process(0.1)
    if not _check(absf(rocket.velocity.x) > 0.01, "tilt redirects thrust"): return
    rocket.position = Vector3(-2000, -5.5, 0)
    rocket.velocity = Vector3(0, -20, 0)
    rocket.engine_on = false
    rocket._physics_process(0.1)
    if not _check(rocket.crashed and is_equal_approx(rocket.position.y, -5.54), "fast landing-zone impact crashes"): return
    _send_key(KEY_R, true)
    await process_frame
    _send_key(KEY_R, false)
    if not _check(rocket.position == Vector3.ZERO and not rocket.engine_on and not rocket.crashed, "R resets after impact"): return
    print("FLIGHT TEST PASSED: countdown, ignition, thrust, fuel, controls and impact")
    quit()
