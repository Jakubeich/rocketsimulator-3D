extends SceneTree

## Run: Godot --headless --path <project> --script res://tests/menu_start_test.gd
func _initialize() -> void:
    call_deferred("_test")

func _check(ok: bool, message: String) -> bool:
    if not ok:
        push_error("MENU TEST FAILED: " + message)
        quit(1)
        return false
    return true

func _test() -> void:
    var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
    root.add_child(menu)
    current_scene = menu
    await process_frame
    if not _check(menu._scenario_buttons.size() == 2, "both scenarios must be selectable"): return
    menu._open_help()
    if not _check(is_instance_valid(menu._modal), "help must open"): return
    menu._close_modal()
    await process_frame
    menu._open_settings()
    if not _check(is_instance_valid(menu._modal), "settings must open"): return
    menu._close_modal()
    await process_frame
    for index in [0, 1]:
        menu._scenario_buttons[index].pressed.emit()
        var expected := "full_return" if index == 0 else "iss_mission"
        if not _check(menu.selected_scenario == expected, "scenario selection"): return
        menu._start_button.pressed.emit()
        await process_frame
        await process_frame
        await process_frame
        var world := current_scene
        if not _check(world != null and world.name == "LaunchSite", "mission must load launch scene"): return
        var rocket = world.get_node("Falcon9_CrewDragon")
        if not _check(rocket.scenario_id == expected and rocket.countdown > 8.0, "selected mission must start countdown"): return
        if not _check(not has_meta("auto_start"), "autostart must be consumed"): return
        var space := InputEventKey.new()
        space.keycode = KEY_SPACE
        space.pressed = true
        Input.parse_input_event(space)
        await process_frame
        if not _check(rocket.countdown > 0.0, "Space must not accidentally cancel active countdown"): return
        var cancel := InputEventKey.new()
        cancel.keycode = KEY_X
        cancel.pressed = true
        Input.parse_input_event(cancel)
        await process_frame
        var hud = world.get_node("FlightHUD")
        if not _check(rocket.countdown < 0.0 and hud._start_button.visible, "X must abort and show restart button"): return
        hud._start_button.pressed.emit()
        if not _check(rocket.countdown == 10.0, "start button must restart countdown"): return
        rocket.set_physics_process(false)
        for step in range(120): rocket._physics_process(0.1)
        if not _check(rocket.left_pad and rocket.position.y > 0 and rocket.fuel < rocket.INITIAL_FUEL, "automatic countdown must result in ignition and liftoff"): return
        if not _check(rocket.get_node("EngineEffects")._target_throttle > 0.0 and world.get_node("LaunchSmoke")._strength > 0.0, "launch effects must react to thrust"): return
        rocket._separate_stage()
        if not _check(rocket.upper_vehicle.fuel_reserve == 1000.0, "both scenarios use the configured upper-stage reserve"): return
        var escape := InputEventKey.new()
        escape.keycode = KEY_ESCAPE
        escape.pressed = true
        Input.parse_input_event(escape)
        await process_frame
        await process_frame
        menu = current_scene
        if not _check(menu != null and menu.name == "MainMenu", "Escape must return to menu"): return
    print("MENU TEST PASSED: help, settings, both missions and automatic countdown")
    quit()
