extends SceneTree

# The Sun continues illuminating the craft; only unstable distant shadow maps
# are suppressed. Test view switches, hysteresis, pause and the rewind path.
func _initialize() -> void:
    call_deferred("_test")

func check(ok: bool, message: String) -> bool:
    if not ok:
        push_error("DISTANT SHADOW TEST FAILED: " + message)
        quit(1)
    return ok

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    var rig = world.get_node("InspectionCamera")
    var sun = world.get_node("Sun")
    var timeline = world.get_node("MissionTimeline")
    rocket.set_physics_process(false)
    timeline.set_process(false)
    if not check(sun.shadow_enabled, "launch shadows must be enabled"): return
    rocket._separate_stage()
    rocket.upper_vehicle.global_position = Vector3(1750000, -6000, 26000)
    rocket.upper_vehicle.velocity = Vector3(7250, -1600, 50)
    rocket._detach_dragon()
    var d = rocket.dragon_vehicle
    rig._follow_rocket = false
    rig._follow_upper = true
    rig._follow_dragon = true
    rig._process(0.0)
    if not check(not sun.shadow_enabled and sun.light_energy > 0.0, "distant Dragon suppresses shadow map but keeps direct sunlight"): return
    timeline.elapsed = 120.0
    timeline._capture()
    var distant: Dictionary = timeline._history[-1].duplicate(true)
    var key := InputEventKey.new()
    key.pressed = true
    key.keycode = KEY_4
    rig._input(key)
    if not check(sun.shadow_enabled, "LZ-1 camera restores near-field shadows"): return
    key.keycode = KEY_3
    rig._input(key)
    if not check(not sun.shadow_enabled, "returning to Dragon suppresses unstable shadows again"): return
    key.keycode = KEY_5
    rig._input(key)
    if not check(not sun.shadow_enabled, "planet overview also suppresses distant shadows"): return
    key.keycode = KEY_1
    rig._input(key)
    if not check(sun.shadow_enabled, "booster view near the launch site restores shadows"): return
    key.keycode = KEY_3
    rig._input(key)
    paused = true
    timeline._restore(distant)
    if not check(not sun.shadow_enabled and paused, "rewinding while paused updates shadows from restored camera position"): return
    key.keycode = KEY_1
    rig._input(key)
    if not check(sun.shadow_enabled, "view changes continue working while paused"): return
    paused = false
    rig._follow_rocket = false
    rig._follow_upper = false
    rig._follow_dragon = false
    rig._follow_planet = false
    rig.target = Vector3(101000, 0, 0)
    rig._update_camera()
    if not check(not sun.shadow_enabled, "crossing the outer boundary suppresses shadows"): return
    rig.target = Vector3(90000, 0, 0)
    rig._update_camera()
    if not check(not sun.shadow_enabled, "shadows stay off within the hysteresis band"): return
    rig.target = Vector3(79000, 0, 0)
    rig._update_camera()
    if not check(sun.shadow_enabled, "crossing the inner boundary restores shadows"): return
    rig.target = Vector3(90000, 0, 0)
    rig._update_camera()
    if not check(sun.shadow_enabled, "shadows stay on within the hysteresis band"): return
    world.queue_free()
    await process_frame
    print("DISTANT SHADOW TEST PASSED: stable sunlight, camera changes and paused rewind")
    quit(0)
