extends SceneTree
const Earth := preload("res://scripts/world_physics.gd")
func _initialize() -> void:
    call_deferred("_test")
func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rig = world.get_node("InspectionCamera")
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = KEY_5
    rig._input(event)
    var center := Vector3(0, -Earth.EARTH_RADIUS, 0)
    var distance: float = rig.camera.global_position.distance_to(center)
    var forward: Vector3 = -rig.camera.global_basis.z.normalized()
    if not rig._follow_planet or distance < Earth.EARTH_RADIUS * 3.0 or forward.dot((center - rig.camera.global_position).normalized()) < 0.999:
        push_error("PLANET CAMERA FAILED: full-Earth overview should look at planet from outside")
        quit(1)
        return
    event.keycode = KEY_3
    rig._input(event)
    if rig._follow_planet or not rig._follow_dragon or not rig._follow_upper:
        push_error("PLANET CAMERA FAILED: key 3 must return to Dragon")
        quit(1)
        return
    event.keycode = KEY_1
    rig._input(event)
    if rig._follow_planet or not rig._follow_rocket:
        push_error("PLANET CAMERA FAILED: key 1 must return to booster")
        quit(1)
        return
    print("PLANET CAMERA PASSED: full-Earth overview and return to flight cameras")
    world.queue_free()
    await process_frame
    quit()
