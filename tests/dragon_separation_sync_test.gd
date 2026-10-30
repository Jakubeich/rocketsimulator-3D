extends SceneTree

class Observer extends Node:
    var rocket
    var initial_position: Vector3
    var initial_velocity: Vector3
    var count := 0
    var failure := ""
    var done := false
    func _physics_process(delta: float) -> void:
        if done or not is_instance_valid(rocket.dragon_vehicle):
            return
        var d = rocket.dragon_vehicle
        var upper = rocket.upper_vehicle
        if count == 0:
            var expected: Vector3 = initial_position + initial_velocity * delta
            var error: float = d.global_position.distance_to(expected)
            if error > 4.0:
                failure = "Dragon missed or doubled a physics callback: %.2f m" % error
            if d.global_position.distance_to(rocket._dragon_root.global_position) > 0.1:
                failure = "the visible Dragon jumped relative to its controller"
            if not upper.orbit_target_met or upper.carries_dragon:
                failure = "Dragon detached before cutoff or upper-stage state is wrong"
        else:
            var offset: Vector3 = d.global_position - upper.to_global(Vector3(0, 10.99, 0))
            if offset.dot(upper.global_basis.y.normalized()) < -0.5:
                failure = "Dragon moved through the upper stage"
        count += 1
        if count >= 4 or not failure.is_empty():
            done = true

func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    for multiplier in [1.0, 10.0]:
        var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
        root.add_child(world)
        current_scene = world
        await process_frame
        var rocket = world.get_node("Falcon9_CrewDragon")
        rocket.set_physics_process(false)
        world.get_node("MissionTimeline").set_process(false)
        rocket._separate_stage()
        rocket.landed = true
        var upper = rocket.upper_vehicle
        upper.global_position = Vector3(50000, 180000, 0)
        upper.velocity = Vector3(1400, 250, 0)
        upper.orbit_target_met = true
        rocket.dragon_separation_timer = 0.001
        var observer := Observer.new()
        observer.rocket = rocket
        observer.process_physics_priority = 1000
        observer.initial_position = rocket._dragon_root.global_position
        observer.initial_velocity = upper.velocity
        world.add_child(observer)
        Engine.time_scale = multiplier
        rocket.set_physics_process(true)
        while not observer.done:
            await process_frame
        if not observer.failure.is_empty():
            push_error("DRAGON SEPARATION %.0fx FAILED: %s" % [multiplier, observer.failure])
            Engine.time_scale = 1.0
            quit(1)
            return
        rocket.set_physics_process(false)
        world.queue_free()
        Engine.time_scale = 1.0
        await process_frame
    print("DRAGON SEPARATION PASSED: synchronized real physics callbacks at 1x and 10x")
    quit(0)
