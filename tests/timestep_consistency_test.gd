extends SceneTree
func _initialize() -> void: call_deferred("_test")
func _fly(step: float, count: int) -> Dictionary:
    var w := (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(w)
    var r = w.get_node("Falcon9_CrewDragon")
    r.set_physics_process(false)
    r.start_countdown()
    for index in range(count): r._physics_process(step)
    var result := {"altitude": r.position.y, "speed": r.velocity.y, "fuel": r.fuel}
    w.queue_free()
    return result
func _test() -> void:
    var normal := _fly(1.0 / 60.0, 6600)
    var accelerated := _fly(1.0 / 12.0, 1320)
    var fast := _fly(1.0 / 6.0, 660)
    if absf(normal.altitude - accelerated.altitude) > 2.0 or absf(normal.speed - accelerated.speed) > 0.2 or absf(normal.fuel - accelerated.fuel) > 0.5:
        push_error("TIME STEP TEST FAILED: %s vs %s" % [normal, accelerated])
        quit(1)
        return
    if absf(normal.altitude - fast.altitude) > 50.0 or absf(normal.speed - fast.speed) > 1.0 or absf(normal.fuel - fast.fuel) > 5.0:
        push_error("TIME STEP 10X FAILED: %s vs %s" % [normal, fast])
        quit(1)
        return
    print("TIME STEP PASSED: 1x, 5x and 10x trajectories ", normal, " / ", accelerated, " / ", fast)
    quit()
