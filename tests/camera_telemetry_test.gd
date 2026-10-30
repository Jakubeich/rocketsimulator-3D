extends SceneTree

const UpperStage := preload("res://scripts/upper_stage.gd")

## The selected camera must immediately display the associated vehicle data.
func _initialize() -> void:
    call_deferred("_test")

func _require(ok: bool, message: String) -> bool:
    if not ok:
        push_error("CAMERA TELEMETRY FAILED: " + message)
        quit(1)
    return ok

func _press(key: Key, physical: Key = KEY_NONE) -> void:
    var event := InputEventKey.new()
    event.keycode = key
    event.physical_keycode = physical if physical != KEY_NONE else key
    event.pressed = true
    Input.parse_input_event(event)

func _release(key: Key, physical: Key = KEY_NONE) -> void:
    var event := InputEventKey.new()
    event.keycode = key
    event.physical_keycode = physical if physical != KEY_NONE else key
    event.pressed = false
    Input.parse_input_event(event)

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    var camera = world.get_node("InspectionCamera")
    var hud = world.get_node("FlightHUD")
    rocket.set_physics_process(false)

    # Czech number row: logical characters need not be digits.
    _press(KEY_PLUS, KEY_2)
    await process_frame
    if not _require(camera._follow_upper and not camera._follow_dragon, "physical 2 selects upper stage"): return
    if not _require(hud._latest.vehicle_label == "2. STUPEŇ + DRAGON" and hud._latest.fuel_amount == UpperStage.INITIAL_FUEL, "attached upper-stage fuel must be shown"): return
    if not _require(hud._latest.throttle == 0.0 and hud._start_button.visible, "upper engine is off and countdown remains startable"): return
    _release(KEY_PLUS, KEY_2)
    _press(KEY_BRACKETLEFT, KEY_3)
    await process_frame
    if not _require(hud._latest.vehicle_label == "CREW DRAGON" and hud._latest.fuel_label == "PALIVO 2. STUPNĚ", "Dragon must identify shared stage fuel"): return
    if not _require(str(hud._latest.view_label).contains("SPOJEN"), "Dragon attachment must be explicit"): return
    _release(KEY_BRACKETLEFT, KEY_3)

    rocket.left_pad = true
    rocket.position.y = 20000.0
    rocket.velocity = Vector3(0, 100, 0)
    rocket.fuel = rocket.RESERVE_FUEL + 5000.0
    rocket._separate_stage()
    rocket.upper_vehicle.set_physics_process(false)
    rocket.upper_vehicle.global_position.y = 30000.0
    rocket.upper_vehicle.velocity = Vector3(0, 400, 0)
    rocket.upper_vehicle.fuel = UpperStage.INITIAL_FUEL * 0.4
    rocket.upper_vehicle.actual_throttle = 1.0
    rocket.upper_vehicle.elapsed = 5.0

    _press(KEY_1)
    await process_frame
    if not _require(hud._latest.vehicle_label == "1. STUPEŇ" and is_equal_approx(hud._latest.fuel_amount, rocket.RESERVE_FUEL + 5000.0), "camera 1 displays booster fuel"): return
    var booster_alt: float = hud._latest.altitude
    var booster_speed: float = hud._latest.speed
    _release(KEY_1)
    _press(KEY_2)
    await process_frame
    if not _require(hud._latest.vehicle_label == "2. STUPEŇ + DRAGON" and is_equal_approx(hud._latest.fuel_amount, UpperStage.INITIAL_FUEL * 0.4), "camera 2 displays upper-stage fuel"): return
    if not _require(hud._latest.altitude > booster_alt + 9000.0 and hud._latest.speed > booster_speed + 200.0, "altitude and speed belong to selected vehicle"): return
    if not _require(hud._latest.throttle == 1.0 and hud._latest.engine_on, "upper-stage engine status must be independent"): return
    _release(KEY_2)
    _press(KEY_3)
    await process_frame
    if not _require(hud._latest.vehicle_label == "CREW DRAGON" and is_equal_approx(hud._latest.fuel_amount, UpperStage.INITIAL_FUEL * 0.4), "Dragon camera displays attached upper-stage data"): return
    if not _require(hud._latest.altitude > 30000.0 and hud._latest.speed == 400.0, "Dragon position and shared speed"): return
    _release(KEY_3)
    _press(KEY_KP_4)
    await process_frame
    if not _require(hud._latest.vehicle_label == "1. STUPEŇ" and str(hud._latest.view_label).contains("LZ-1"), "landing camera explicitly identifies booster telemetry"): return
    _release(KEY_KP_4)
    _press(KEY_R)
    await process_frame
    if not _require(not rocket.stage_separated and camera._follow_rocket and hud._latest.vehicle_label == "FALCON 9", "reset returns to assembled rocket telemetry"): return
    if not _require(is_equal_approx(hud._latest.fuel_amount, rocket.INITIAL_FUEL), "reset restores booster fuel"): return
    _release(KEY_R)
    print("CAMERA TELEMETRY PASSED: attached, separated, Dragon, LZ-1 and reset")
    quit()
