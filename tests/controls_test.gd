extends SceneTree

## End-to-end input routing, including physical keys on non-US keyboard layouts.
func _initialize() -> void:
    call_deferred("_test")

func _require(ok: bool, message: String) -> bool:
    if not ok:
        push_error("CONTROLS TEST FAILED: " + message)
        quit(1)
    return ok

func _press(logical: Key, physical: Key = KEY_NONE) -> void:
    var event := InputEventKey.new()
    event.keycode = logical
    event.physical_keycode = physical if physical != KEY_NONE else logical
    event.pressed = true
    Input.parse_input_event(event)

func _release(logical: Key, physical: Key = KEY_NONE) -> void:
    var event := InputEventKey.new()
    event.keycode = logical
    event.physical_keycode = physical if physical != KEY_NONE else logical
    event.pressed = false
    Input.parse_input_event(event)

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    var camera = world.get_node("InspectionCamera")
    rocket.set_physics_process(false)
    var start_button: Button = world.get_node("FlightHUD")._start_button
    start_button.focus_mode = Control.FOCUS_ALL
    start_button.grab_focus()

    # Czech unshifted keys differ from their physical 1/2/3 positions.
    _press(KEY_PLUS, KEY_2)
    await process_frame
    if not _require(not camera._follow_rocket and camera._follow_upper and not camera._follow_dragon and camera.target.is_equal_approx(camera._upper_target()), "physical 2 must select upper stage even when a button has focus"): return
    _release(KEY_PLUS, KEY_2)
    _press(KEY_BRACKETLEFT, KEY_3)
    await process_frame
    if not _require(camera._follow_upper and camera._follow_dragon and not camera._follow_rocket and camera.target.is_equal_approx(camera._dragon_target()), "physical 3 must follow Dragon before separation"): return
    _release(KEY_BRACKETLEFT, KEY_3)
    _press(KEY_KP_4)
    await process_frame
    if not _require(not camera._follow_upper and not camera._follow_rocket and camera.target.is_equal_approx(Vector3(-2000, 0, 0)), "numpad 4 must select landing zone"): return
    _release(KEY_KP_4)
    _press(KEY_KP_1)
    await process_frame
    if not _require(camera._follow_rocket and not camera._follow_upper, "numpad 1 must select the rocket"): return
    _release(KEY_KP_1)

    var original_distance: float = camera.distance
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    camera._unhandled_input(wheel)
    if not _require(camera.distance < original_distance, "mouse wheel must zoom"): return
    var zoomed_in: float = camera.distance
    wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
    camera._unhandled_input(wheel)
    if not _require(camera.distance > zoomed_in, "mouse wheel down must zoom out"): return
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    camera._unhandled_input(click)
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(20, 10)
    var old_yaw: float = camera.yaw
    camera._unhandled_input(motion)
    if not _require(camera.yaw != old_yaw, "mouse drag must orbit"): return
    click.pressed = false
    # Simulate release over GUI: it reaches _input but not _unhandled_input.
    camera._input(click)
    old_yaw = camera.yaw
    camera._unhandled_input(motion)
    if not _require(not camera._dragging and camera.yaw == old_yaw, "releasing mouse over HUD must stop drag"): return

    _press(KEY_SPACE)
    await process_frame
    if not _require(rocket.countdown > 0.0, "Space must start countdown"): return
    _release(KEY_SPACE)
    _press(KEY_X)
    await process_frame
    if not _require(rocket.countdown < 0.0, "X must cancel countdown"): return
    _release(KEY_X)

    rocket.commanded_throttle = 0.5
    _press(KEY_W)
    await process_frame
    rocket._physics_process(0.25)
    if not _require(rocket.commanded_throttle > 0.5, "W must increase throttle"): return
    _release(KEY_W)
    await process_frame
    var high: float = rocket.commanded_throttle
    _press(KEY_S)
    await process_frame
    rocket._physics_process(0.25)
    if not _require(rocket.commanded_throttle < high, "S must decrease throttle"): return
    _release(KEY_S)
    await process_frame

    rocket.left_pad = true
    rocket.position.y = 10000.0
    rocket._publish_telemetry()
    _press(KEY_SPACE)
    await process_frame
    if not _require(rocket.engine_on, "Space must enable engines during flight"): return
    _release(KEY_SPACE)
    await process_frame
    _press(KEY_SPACE)
    await process_frame
    if not _require(not rocket.engine_on, "Space must disable engines during flight"): return
    _release(KEY_SPACE)
    await process_frame
    _press(KEY_RIGHT)
    await process_frame
    rocket._physics_process(0.1)
    if not _require(rocket.rotation.z > 0.0, "right arrow must tilt rocket in flight"): return
    _release(KEY_RIGHT)
    await process_frame
    var right_angle: float = rocket.rotation.z
    _press(KEY_LEFT)
    await process_frame
    rocket._physics_process(0.1)
    if not _require(rocket.rotation.z < right_angle, "left arrow must tilt rocket in the other direction"): return
    _release(KEY_LEFT)
    await process_frame
    _press(KEY_DOWN)
    await process_frame
    rocket._physics_process(0.1)
    if not _require(rocket.rotation.x > 0.0, "down arrow must tilt the other axis"): return
    _release(KEY_DOWN)
    await process_frame
    var down_angle: float = rocket.rotation.x
    _press(KEY_UP)
    await process_frame
    rocket._physics_process(0.1)
    if not _require(rocket.rotation.x < down_angle, "up arrow must tilt the other axis back"): return
    _release(KEY_UP)
    await process_frame
    _press(KEY_E)
    await process_frame
    if not _require(rocket.separation_timer < 0.0 and rocket._warning_timer > 0.0, "E must reject separation below 20 km"): return
    _release(KEY_E)
    rocket.position.y = 21000.0
    _press(KEY_E)
    await process_frame
    if not _require(rocket.separation_timer > 0.0, "E must start separation above 20 km"): return
    _release(KEY_E)
    rocket._physics_process(2.1)
    if not _require(rocket.stage_separated, "manual separation must finish after BECO delay"): return
    _press(KEY_3)
    await process_frame
    # The upper stage may have moved in a physics tick since the input event.
    # Update the camera synchronously before comparing its tracked target.
    camera._process(0.0)
    if not _require(camera._follow_upper and camera._follow_dragon and camera.target.is_equal_approx(camera._dragon_target()), "3 must follow Dragon after separation"): return
    _release(KEY_3)
    _press(KEY_T)
    await process_frame
    if not _require(is_equal_approx(Engine.time_scale, 2.0), "T must speed up time"): return
    _release(KEY_T)
    await process_frame
    _press(KEY_T)
    await process_frame
    if not _require(is_equal_approx(Engine.time_scale, 5.0), "T must select 5x time"): return
    _release(KEY_T)
    await process_frame
    _press(KEY_T)
    await process_frame
    if not _require(is_equal_approx(Engine.time_scale, 10.0), "T must select 10x time"): return
    _release(KEY_T)
    await process_frame
    _press(KEY_T)
    await process_frame
    if not _require(is_equal_approx(Engine.time_scale, 50.0), "T must select 50x time"): return
    _release(KEY_T)
    await process_frame
    _press(KEY_T)
    await process_frame
    if not _require(is_equal_approx(Engine.time_scale, 1.0), "T must cycle back to normal time"): return
    _release(KEY_T)
    await process_frame
    _press(KEY_R)
    await process_frame
    if not _require(not rocket.stage_separated and not rocket.left_pad and camera._follow_rocket and is_equal_approx(Engine.time_scale, 1.0), "R must reset flight, camera and time"): return
    _release(KEY_R)
    _press(KEY_ESCAPE)
    await process_frame
    await process_frame
    if not _require(current_scene != null and current_scene.name == "MainMenu", "Escape must return to menu"): return
    print("CONTROLS PASSED: physical and numpad cameras, mouse, start/cancel, throttle, steering, separation, time, reset and menu")
    quit()
