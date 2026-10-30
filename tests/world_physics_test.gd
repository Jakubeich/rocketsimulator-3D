extends SceneTree
const EnvironmentModel := preload("res://scripts/world_physics.gd")

func _initialize() -> void:
    var checks := [
        [0.0, 1.2250], [11000.0, 0.3648], [20000.0, 0.08891],
        [40000.0, 0.003996], [60000.0, 0.000310], [80000.0, 0.0000185],
        [100000.0, 5.604e-7], [400000.0, 2.803e-12], [1000000.0, 3.561e-15]
    ]
    for row in checks:
        var density: float = EnvironmentModel.atmosphere(row[0]).density
        if absf(density - row[1]) / row[1] > 0.035:
            push_error("Unexpected atmospheric density at %s m: %s" % [row[0], density])
            quit(1)
            return
    var reference: Vector3 = EnvironmentModel.gravity(Vector3.ZERO)
    if absf(reference.length() - 9.80665) > 0.00001:
        push_error("Sea-level gravity is wrong")
        quit(1)
        return
    var orbit_position := Vector3(0, 400000, 0)
    var orbit: Vector3 = EnvironmentModel.gravity(orbit_position)
    if orbit.length() >= reference.length() or orbit.y >= 0.0:
        push_error("Gravity must decrease with height and point toward Earth")
        quit(1)
        return
    var horizontally_offset := Vector3(200000, 0, 0)
    if EnvironmentModel.gravity(horizontally_offset).x >= 0.0:
        push_error("Gravity must point to Earth centre")
        quit(1)
        return
    var inertial := EnvironmentModel.inertial_velocity(Vector3.ZERO, Vector3.ZERO)
    if absf(inertial.x - 408.5) > 2.0 or absf(inertial.y) > 0.01 or absf(inertial.z) > 0.01:
        push_error("Earth-fixed surface must have the expected eastward inertial velocity")
        quit(1)
        return
    var centrifugal := EnvironmentModel.rotating_frame_acceleration(Vector3.ZERO, Vector3.ZERO)
    if centrifugal.y <= 0.0 or centrifugal.z <= 0.0 or centrifugal.length() > 0.04:
        push_error("Centrifugal acceleration in the rotating frame is incorrect")
        quit(1)
        return
    var moving := EnvironmentModel.rotating_frame_acceleration(Vector3.ZERO, Vector3(1000, 0, 0))
    if moving.is_equal_approx(centrifugal):
        push_error("Coriolis acceleration must depend on velocity")
        quit(1)
        return
    var air: Vector3 = EnvironmentModel.drag(Vector3(25, 100, 0), Vector3.UP, 1.225, 0.3, 5, 1.2, 87.5)
    if air.dot(Vector3(25, 100, 0)) > 0.0:
        push_error("Drag must oppose air-relative velocity")
        quit(1)
        return
    print("WORLD PHYSICS PASSED: atmosphere, gravity, rotating Earth and drag")
    quit()
