extends SceneTree
const Upper := preload("res://scripts/upper_stage.gd")
const Earth := preload("res://scripts/world_physics.gd")
func _initialize() -> void: call_deferred("_test")
func fail(s: String) -> void: push_error("UPPER GUIDANCE FAILED: " + s); quit(1)
func _test() -> void:
    var upper = Upper.new()
    upper.name = "Stage"
    root.add_child(upper)
    upper.set_physics_process(false)
    # Representative nominal state at separation from the current ascent model.
    upper.global_position = Vector3(44620.0,59786.0,0)
    upper.rotation.z = -deg_to_rad(55)
    upper.thrust_axis = upper.global_basis.y.normalized()
    upper.velocity = Vector3(1353.0,1017.0,0)
    upper.fuel_reserve = 1000.0
    var prev_axis: Vector3 = upper.thrust_axis
    var max_turn := 0.0
    var previous_throttle := 0.0
    var raised := false
    var max_alt := Earth.altitude(upper.global_position)
    for i in range(8000):
        upper._physics_process(0.05)
        var axis: Vector3 = upper.global_basis.y.normalized()
        var angle: float = acos(clampf(axis.dot(prev_axis), -1.0, 1.0))
        max_turn = maxf(max_turn, angle / 0.05)
        prev_axis=axis
        max_alt=maxf(max_alt,Earth.altitude(upper.global_position))
        if upper.elapsed < Upper.IGNITION_DELAY and upper.actual_throttle != 0.0:
            fail("premature ignition"); return
        if upper.elapsed >= Upper.IGNITION_DELAY and upper.elapsed < Upper.IGNITION_DELAY + Upper.IGNITION_RAMP:
            if upper.actual_throttle + 0.001 < previous_throttle:
                fail("ignition thrust is not monotonic"); return
            if upper.actual_throttle > 0: raised=true
            previous_throttle = upper.actual_throttle
        if upper.thrust_axis.distance_to(axis) > 0.001:
            fail("thrust is not aligned with visible motor axis"); return
        if not upper.active or upper.orbit_target_met: break
    print("TURN max deg/s=",rad_to_deg(max_turn)," angular rate state=",rad_to_deg(upper.angular_speed)," alt=",Earth.altitude(upper.global_position)," t=",upper.elapsed," pos=",upper.global_position," speed=",upper.velocity.length()," max_alt=",max_alt," fuel=",upper.fuel," osculating=",upper.orbital_elements())
    if not raised or max_turn > deg_to_rad(1.3): fail("turn-rate limit or ignition ramp"); return
    if upper.impacted: fail("upper stage hit Earth's curved surface unexpectedly"); return
    if Earth.altitude(upper.global_position) < 180000.0 or Earth.altitude(upper.global_position) > 300000.0:
        fail("guided stage missed the approximate ascent altitude range"); return
    if upper.velocity.x < 6000.0 or not upper.orbit_target_met or upper.actual_throttle != 0.0:
        fail("upper stage did not burn to a valid orbit and shut down"); return
    var result_orbit: Dictionary = upper.orbital_elements()
    if result_orbit.periapsis < 180000.0 or result_orbit.apoapsis > 400000.0:
        fail("reported orbit failed the target perigee/apogee limits"); return
    var fuel_at_cutoff: float = upper.fuel
    for i in range(6000):
        upper._physics_process(0.1)
        if upper.impacted:
            fail("stage impacted during the first ten minutes after orbital cutoff"); return
    result_orbit = upper.orbital_elements()
    if upper.actual_throttle != 0.0 or not is_equal_approx(upper.fuel, fuel_at_cutoff):
        fail("second-stage engine reignited after orbital cutoff"); return
    if result_orbit.periapsis < 150000.0:
        fail("orbital perigee did not remain above the atmosphere during coast"); return
    # A weaker separation state must not report an orbit merely because the
    # motor has shut down: the perigee still intersects the atmosphere.
    var weak = Upper.new()
    root.add_child(weak)
    weak.set_physics_process(false)
    weak.global_position = Vector3(40090.0, 52988.0, 0.0)
    weak.rotation.z = -deg_to_rad(55.0)
    weak.thrust_axis = weak.global_basis.y.normalized()
    weak.velocity = Vector3(1228.7, 883.9, 0.0)
    weak.fuel_reserve = 1000.0
    for i in range(8000):
        weak._physics_process(0.05)
        if not weak.active or weak.orbit_target_met: break
    var weak_orbit: Dictionary = weak.orbital_elements()
    if weak.orbit_target_met or weak_orbit.periapsis >= Upper.MIN_ORBIT_PERIAPSIS:
        fail("weak separation must not be misreported as a successful orbit"); return
    # Keep this local rotation check near the origin so float32 position
    # quantization thousands of kilometres downrange cannot mask a defect.
    upper.global_position = Vector3(1000, 50000, 0)
    upper.rotation.z += deg_to_rad(20)
    var before_rotation: Vector3 = upper.to_global(Vector3(0, 7, 0))
    upper._advance_guidance(0.05)
    if upper.to_global(Vector3(0, 7, 0)).distance_to(before_rotation) > 0.02:
        fail("guidance rotation displaced the center of mass"); return
    var probe = Upper.new()
    root.add_child(probe)
    probe.set_physics_process(false)
    probe.fuel=probe.fuel_reserve
    probe.global_position = Vector3(1000000,-5000,0)
    probe._physics_process(0.05)
    if probe.impacted: fail("flat ground should not cause impact at 1,000 km downrange"); return
    probe.global_position = Vector3(0,250000,0)
    var circular_inertial := Vector3(sqrt(probe.EARTH_MU/(Earth.EARTH_RADIUS+250000.0)),0,0)
    probe.velocity = circular_inertial - Earth.inertial_velocity(probe.global_position, Vector3.ZERO)
    var orbit: Dictionary = probe.orbital_elements()
    if absf(orbit.periapsis-250000.0)>1000 or absf(orbit.apoapsis-250000.0)>1000:
        fail("circular orbit helper " + str(orbit)); return
    probe.global_position=Vector3(0,probe.contact_clearance-6.0,0)
    probe.velocity=Vector3(0,-100,0)
    probe._physics_process(0.1)
    if not probe.impacted: fail("actual ground impact missing"); return
    print("UPPER GUIDANCE PASSED: delayed ignition, orbit cutoff, insufficient-energy case, curved-Earth contact")
    quit()
