extends SceneTree
const Earth := preload("res://scripts/world_physics.gd")

func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var world := (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rig = world.get_node("InspectionCamera")
    rig.set_process(false)
    world.get_node("Falcon9_CrewDragon").set_physics_process(false)
    var sky = world.get_node("FlightSky")
    var camera = rig.get_node("Camera3D")
    camera.global_position = Vector3(0, 240000, 0)
    sky.refresh_camera()
    var relative: Vector3 = sky._material.get_shader_parameter("camera_earth")
    if not _check(absf(relative.y - (1.0 + 240000.0 / Earth.EARTH_RADIUS)) < 0.000001, "sphere receives actual camera altitude"): return
    if not _check(absf(float(sky._material.get_shader_parameter("altitude_m")) - 240000.0) < 1.0, "sky uses correct height"): return
    if not _check(sky._material.get_shader_parameter("earth_map") != null and sky._material.get_shader_parameter("cloud_map") != null, "NASA surface and cloud textures are bound"): return
    if not _check(not world.get_node("Stars").visible and not world.get_node("DistantLand").visible, "foreground stars and flat land do not obscure the Earth"): return
    camera.global_position = Vector3(0, 100, 0)
    sky.refresh_camera()
    if not _check(world.get_node("DistantLand").visible and float(world.get_node("DistantLand").transparency) < 0.01, "local terrain remains visible at low altitude"): return
    camera.global_position = Vector3(0, 4000, 0)
    sky.refresh_camera()
    var fade: float = world.get_node("DistantLand").transparency
    if not _check(fade > 0.0 and fade < 1.0, "local terrain fades rather than disappearing suddenly"): return
    print("EARTH SKY PASSED: camera position, NASA maps, foreground, smooth terrain transition")
    world.queue_free()
    await process_frame
    quit(0)

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("EARTH SKY FAILED: " + message)
        quit(1)
    return condition
