extends SceneTree

func _initialize() -> void: call_deferred("_test")
func _fail(message: String) -> void:
    push_error("UPPER STAGE TEST FAILED: " + message)
    quit(1)
func _test() -> void:
    var world := (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    rocket.set_physics_process(false)
    rocket.position = Vector3(100, 40000, -50)
    rocket.rotation.z = 0.2
    rocket.velocity = Vector3(40, 600, 0)
    var marker = rocket._upper_stage.find_child("FX_MERLIN_VAC", true, false)
    var marker_child_count = marker.get_child_count()
    var original: Transform3D = rocket._upper_stage.global_transform
    var before_velocity: Vector3 = rocket.velocity
    var booster_mass: float = rocket.BOOSTER_DRY_MASS + rocket.fuel
    var upper_mass: float = rocket.UPPER_MASS
    rocket._separate_stage()
    var upper = rocket.upper_vehicle
    if upper.is_physics_processing():
        _fail("owned upper stage must be integrated only by the booster controller")
        return
    upper.set_physics_process(false)
    # Compare mass-weighted velocity to avoid float32 precision loss from
    # forming enormous momentum vectors with full-scale rocket masses.
    var momentum_error: Vector3 = rocket.velocity * (booster_mass / (booster_mass + upper_mass)) + upper.velocity * (upper_mass / (booster_mass + upper_mass)) - before_velocity
    if momentum_error.length() > 0.001:
        _fail("separation must conserve linear momentum")
        return
    if not rocket._upper_stage.global_transform.is_equal_approx(original):
        _fail("separation changed the visible upper stage transform")
        return
    if upper.global_position.distance_to(original.origin) > 0.05:
        _fail("upper-stage origin must be at stage interface, not booster base")
        return
    if upper.contact_clearance <= 0.0 or upper.contact_clearance > 30.0:
        _fail("invalid measured ground clearance: %s" % upper.contact_clearance)
        return
    if not is_instance_valid(upper.exhaust_fx) or not is_instance_valid(upper.exhaust_fx._plume):
        _fail("vacuum engine exhaust must be attached after separation")
        return
    rocket.crashed = true
    var upper_elapsed_before_crash: float = upper.elapsed
    rocket._physics_process(0.05)
    if upper.elapsed <= upper_elapsed_before_crash:
        _fail("upper stage must keep moving after the booster crashes")
        return
    rocket.crashed = false
    upper.elapsed = upper.IGNITION_DELAY
    upper.ignition_clearance_met = false
    upper._physics_process(0.1)
    if upper.exhaust_fx._target != 0.0 or upper.actual_throttle != 0.0:
        _fail("vacuum engine must stay off without separation clearance")
        return
    upper.ignition_clearance_met = true
    upper._physics_process(0.1)
    upper._physics_process(0.1)
    if upper.exhaust_fx._target <= 0.0:
        _fail("vacuum engine exhaust must respond to ignition")
        return
    upper.fuel = upper.fuel_reserve
    upper._physics_process(0.1)
    if upper.exhaust_fx._target != 0.0:
        _fail("vacuum engine exhaust must shut down with the engine")
        return
    var cam = world.get_node("InspectionCamera")
    rocket.rotation.z = PI
    cam._follow_rocket = true
    cam._follow_upper = false
    cam._process(0.016)
    if not cam.target.is_equal_approx(rocket.to_global(Vector3(0, 24, 0))):
        _fail("camera must follow the centre of a flipped booster")
        return
    cam._follow_rocket = false
    cam._follow_upper = true
    upper.actual_throttle = 0.75
    upper.fuel = upper.INITIAL_FUEL * 0.25
    rocket._publish_telemetry()
    var hud = world.get_node("FlightHUD")
    if hud._latest.get("vehicle_label") != "2. STUPEŇ + DRAGON" or absf(hud._latest.get("fuel_fraction") - 0.25) > 0.001:
        _fail("upper-stage camera must show actual upper-stage telemetry")
        return
    upper.global_position = Vector3(100, upper.contact_clearance - 6.0, 0)
    upper.velocity = Vector3(0, -100, 0)
    upper.elapsed = 0.0
    upper._physics_process(0.1)
    if not upper.impacted or absf(upper.global_position.y - upper.contact_clearance + 6.15) > 0.01:
        _fail("upper-stage contact must use its geometry")
        return
    rocket.reset_flight()
    await process_frame
    await process_frame
    if marker.get_child_count() != marker_child_count:
        _fail("vacuum exhaust must be cleaned up when resetting")
        return
    if rocket._upper_stage.get_parent() != rocket._upper_parent:
        _fail("reset must reassemble upper stage")
        return
    print("UPPER STAGE PASSED: separation, contact, camera telemetry and reset")
    quit()
