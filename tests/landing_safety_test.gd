extends SceneTree
func _initialize() -> void: call_deferred("_test")
func _fail(message: String) -> void:
    push_error("SAFETY TEST FAILED: " + message)
    quit(1)
func _test() -> void:
    var world := (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var r = world.get_node("Falcon9_CrewDragon")
    r.set_physics_process(false)
    r.commanded_throttle = 0.3
    r.start_countdown()
    for index in range(240): r._physics_process(0.1)
    if r.engine_on or r.left_pad or r.landed or r._pad_abort.is_empty() or r.fuel <= r.RESERVE_FUEL:
        _fail("low-thrust start must abort on pad without false landing or wasting reserve")
        return
    r.commanded_throttle = 1.0
    r.start_countdown()
    if r.countdown < 9.9 or not r._pad_abort.is_empty():
        _fail("pilot must be able to retry after low-thrust abort")
        return
    r.reset_flight()
    r.left_pad = true
    r.stage_separated = true
    r.position = Vector3(-2000.0, -5.53, 0.0)
    r.velocity = Vector3(0, -1, 0)
    r.rotation.z = deg_to_rad(75.0)
    r.get_node("LandingLegs")._amount = 1.0
    r._physics_process(0.1)
    if not r.crashed or r.landed:
        _fail("a sideways booster must not be treated as safely landed")
        return
    print("SAFETY PASSED: abort and unstable attitude cannot report successful landing")
    quit()
