extends SceneTree

# The rendered camera must be positioned after the shared physics callback,
# particularly when one callback advances a significant distance at high warp.
class Observer extends Node:
    var rocket
    var done := false
    var failure := ""
    var seen := 0
    func _physics_process(_delta: float) -> void:
        if done:
            return
        var rig = rocket.camera_rig
        var target: Vector3 = rocket._dragon_root.to_global(Vector3(0, 1.7, 0))
        var dist: float = rig.camera.global_position.distance_to(target)
        var error: float = absf(dist - rig.distance)
        if error > 1.5:
            failure = "camera lags the Dragon by %.1f m instead of following at %.1f m" % [dist, rig.distance]
        seen += 1
        if seen >= 4 or not failure.is_empty():
            done = true

func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    for multiplier in [1.0, 10.0, 50.0]:
        var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
        root.add_child(world)
        current_scene = world
        await process_frame
        var rocket = world.get_node("Falcon9_CrewDragon")
        rocket.set_physics_process(false)
        world.get_node("MissionTimeline").set_process(false)
        rocket._separate_stage()
        rocket.landed = true
        rocket.upper_vehicle.global_position = Vector3(1750000, -6000, 26000)
        rocket.upper_vehicle.velocity = Vector3(7250, -1600, 50)
        rocket.upper_vehicle.orbit_target_met = true
        rocket._detach_dragon()
        var rig = rocket.camera_rig
        rig._follow_rocket = false
        rig._follow_upper = true
        rig._follow_dragon = true
        rig.distance = 35.0
        var observer := Observer.new()
        observer.rocket = rocket
        observer.process_physics_priority = 1000
        world.add_child(observer)
        Engine.time_scale = multiplier
        rocket.set_physics_process(true)
        while not observer.done:
            await process_frame
        if not observer.failure.is_empty():
            push_error("CAMERA %.0fx: %s" % [multiplier, observer.failure])
            Engine.time_scale = 1.0
            quit(1)
            return
        rocket.set_physics_process(false)
        world.queue_free()
        Engine.time_scale = 1.0
        await process_frame
    print("CAMERA FOLLOW SYNC PASSED: after physics at 1x, 10x and 50x")
    quit()
