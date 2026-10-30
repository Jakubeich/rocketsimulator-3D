extends SceneTree

func _initialize() -> void:
    call_deferred("_test")

func _check(value: bool, label: String) -> bool:
    if not value:
        push_error("MISSION TIME FAILED: " + label)
        quit(1)
    return value

func _click(button: Button) -> void:
    var point := button.get_global_rect().get_center()
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.position = point
    event.global_position = point
    event.pressed = true
    root.push_input(event, true)
    await process_frame
    event = event.duplicate()
    event.pressed = false
    root.push_input(event, true)
    await process_frame

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    var camera = world.get_node("InspectionCamera")
    var hud = world.get_node("FlightHUD")
    var timeline = world.get_node("MissionTimeline")
    rocket.set_physics_process(false)
    timeline.set_process(false)
    await process_frame
    await _click(hud._time_pause)
    if not _check(paused, "clicking pause in the actual viewport pauses time"): return
    await _click(hud._time_pause)
    if not _check(not paused, "clicking play in the actual viewport resumes time"): return
    rocket.set_physics_process(false)
    for speed in [1.0, 2.0, 5.0, 10.0]:
        hud._time_rates[speed].pressed.emit()
        if not _check(Engine.time_scale == speed and timeline.rate == speed, "each speed button must select its own rate"): return
    if not _check(rocket._time_index == 3, "10x must update the flight status"): return
    timeline.set_rate(1.0)
    rocket.left_pad = true
    rocket.position.y = 20000.0
    rocket.velocity = Vector3(5, 200, 0)
    rocket.fuel = rocket.RESERVE_FUEL + 5000.0
    rocket._attitude_rate = 0.03
    rocket._ascent_manual = true
    timeline.elapsed = 100.0
    timeline._capture()
    rocket._separate_stage()
    rocket.upper_vehicle.set_physics_process(false)
    rocket.upper_vehicle.position.y = 30000.0
    rocket.upper_vehicle.velocity = Vector3(0, 400, 0)
    rocket.upper_vehicle.fuel = rocket.upper_vehicle.INITIAL_FUEL * 0.5
    rocket.return_pilot.phase = "COAST"
    rocket.return_pilot.phase_time = 6.0
    rocket.return_pilot._boost_direction = Vector3(-0.9, -0.1, 0.2).normalized()
    rocket._attitude_rate = 0.08
    rocket._ascent_manual = false
    rocket.upper_vehicle.guidance_start_pitch = 0.7
    rocket.upper_vehicle.guidance_heading = Vector3.RIGHT
    rocket.upper_vehicle.angular_speed = 0.01
    rocket.upper_vehicle.orbit_target_met = true
    rocket.upper_vehicle.separation_axis = Vector3(0.8, 0.6, 0.0)
    rocket.upper_vehicle.ignition_clearance_met = true
    rocket.upper_vehicle.ignition_started_at = 5.6
    rocket.grid_fins.set_state({"amount": 0.5, "target": 1.0, "steering": Vector2(0.2, -0.3)})
    rocket.legs._amount = 0.3
    rocket.legs._target = 1.0
    timeline.elapsed = 110.0
    timeline._capture()
    rocket.position.y = 21000.0
    rocket.upper_vehicle.fuel = rocket.upper_vehicle.INITIAL_FUEL * 0.4
    rocket.upper_vehicle.orbit_target_met = false
    rocket.upper_vehicle.separation_axis = Vector3.UP
    rocket.upper_vehicle.ignition_clearance_met = false
    rocket.upper_vehicle.ignition_started_at = -1.0
    rocket.grid_fins.reset_fins()
    timeline.elapsed = 120.0
    timeline._capture()
    hud._time_back.pressed.emit()
    if not _check(paused and is_equal_approx(timeline.elapsed, 110.0), "rewind pauses and moves back 10 seconds"): return
    if not _check(rocket.stage_separated and is_equal_approx(rocket.upper_vehicle.fuel, rocket.upper_vehicle.INITIAL_FUEL * 0.5) and rocket.return_pilot.phase == "COAST", "rewind restores separated stages, fuel and autopilot"): return
    if not _check(is_equal_approx(rocket.legs._amount, 0.3), "rewind restores landing gear"): return
    if not _check(is_equal_approx(rocket._attitude_rate, 0.08) and is_equal_approx(rocket.grid_fins._amount, 0.5), "rewind restores rotation and grid fins"): return
    if not _check(rocket.upper_vehicle.orbit_target_met and is_equal_approx(rocket.upper_vehicle.guidance_start_pitch, 0.7) and rocket.upper_vehicle.guidance_heading == Vector3.RIGHT, "rewind restores upper-stage guidance and cutoff"): return
    if not _check(rocket.upper_vehicle.separation_axis == Vector3(0.8, 0.6, 0.0) and rocket.upper_vehicle.ignition_clearance_met and is_equal_approx(rocket.upper_vehicle.ignition_started_at, 5.6), "rewind restores separation axis and ignition clearance"): return
    hud._time_back.pressed.emit()
    if not _check(not rocket.stage_separated and rocket.upper_vehicle == null and is_equal_approx(rocket.fuel, rocket.RESERVE_FUEL + 5000.0), "rewind across separation reattaches upper stage"): return
    if not _check(rocket._ascent_manual and is_equal_approx(rocket._attitude_rate, 0.03), "rewind restores ascent control mode and turn rate"): return
    hud._time_forward.pressed.emit()
    if not _check(rocket.stage_separated and is_instance_valid(rocket.upper_vehicle) and is_equal_approx(rocket.upper_vehicle.fuel, rocket.upper_vehicle.INITIAL_FUEL * 0.5), "forward restores recorded separation"): return
    hud._time_forward.pressed.emit()
    if not _check(is_equal_approx(timeline.elapsed, 120.0) and is_equal_approx(rocket.upper_vehicle.fuel, rocket.upper_vehicle.INITIAL_FUEL * 0.4), "forward restores later state"): return
    var before_forward: float = timeline.elapsed
    hud._time_forward.pressed.emit()
    if not _check(not paused and timeline.rate == 10.0, "forward at live edge runs real simulation at 10x"): return
    for step in range(100):
        rocket._physics_process(0.1)
        timeline._process(0.1)
    timeline._process(0.1)
    if not _check(paused and timeline.elapsed >= before_forward + 10.0 and timeline.rate == 1.0, "fast-forward pauses at target and restores speed"): return
    if not _check(not rocket.is_physics_processing(), "paused rocket physics must stop"): return
    if not _check(hud.process_mode == Node.PROCESS_MODE_ALWAYS and camera.process_mode == Node.PROCESS_MODE_ALWAYS, "HUD and camera remain interactive while paused"): return
    var camera_key := InputEventKey.new()
    camera_key.keycode = KEY_2
    camera_key.physical_keycode = KEY_2
    camera_key.pressed = true
    Input.parse_input_event(camera_key)
    await process_frame
    if not _check(camera._follow_upper and hud._latest.vehicle_label == "2. STUPEŇ + DRAGON", "camera and telemetry remain interactive in pause"): return
    hud._help_toggle.pressed.emit()
    await create_timer(0.4, true, false, true).timeout
    if not _check(not hud._help_open and hud._help_toggle.text == "›" and absf(hud._help_panel.offset_right) < 1.0, "help drawer closes during pause"): return
    hud._help_toggle.pressed.emit()
    await create_timer(0.4, true, false, true).timeout
    if not _check(hud._help_open and hud._help_panel.offset_left > 15.0, "help drawer reopens during pause"): return
    hud._time_back.pressed.emit()
    var branch_time: float = timeline.elapsed
    hud._time_pause.pressed.emit()
    if not _check(not paused and timeline._cursor == timeline._history.size() - 1 and float(timeline._history[-1].time) <= branch_time, "resuming from history discards the old future"): return
    rocket.reset_flight()
    if not _check(not paused and Engine.time_scale == 1.0 and is_equal_approx(timeline.elapsed, 0.0), "reset clears timeline and unpauses"): return
    print("MISSION TIME PASSED: rates, pause, rewind, replay, separation, jump and drawer")
    quit()
