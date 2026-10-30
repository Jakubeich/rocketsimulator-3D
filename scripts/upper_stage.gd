extends Node3D

## Simplified Falcon 9 upper stage and attached Dragon. The stage follows a
## gradual pitch program, with a rate-limited attitude, during the burn.
## This is an approximate guidance model, not a full flight computer.
const Earth := preload("res://scripts/world_physics.gd")
const VacuumFlame := preload("res://scripts/vacuum_flame.gd")
const G0 := 9.80665
const THRUST := 981000.0
const ISP := 348.0
const DRY_MASS := 16000.0 # upper dry structure + Crew Dragon, approximately
const INITIAL_FUEL := 107500.0
const BODY_DIAMETER := 3.7
const FRONTAL_AREA := PI * BODY_DIAMETER * BODY_DIAMETER / 4.0
const SIDE_AREA := 20.0 * BODY_DIAMETER # approximate stage + attached Dragon
const IGNITION_DELAY := 5.5
const IGNITION_RAMP := 2.0
# Imported nozzle projects 3.18 m below the interface; the visible plume is
# 19 m long. Keep it clear of the booster before allowing ignition.
const SAFE_PLUME_CLEARANCE := 23.0
const TARGET_ALTITUDE := 230000.0
const GUIDANCE_MIN_TIME_TO_GO := 60.0
const MIN_PITCH := deg_to_rad(45.0) # from local vertical
const MAX_PITCH := deg_to_rad(98.0)
const MIN_ORBIT_PERIAPSIS := 180000.0
const MAX_ORBIT_APOAPSIS := 400000.0
const MAX_TURN_RATE := deg_to_rad(0.9)
const MAX_TURN_ACCEL := deg_to_rad(0.4)
const GROUND_HEIGHT := -6.15
const EARTH_MU := Earth.G0 * Earth.EARTH_RADIUS * Earth.EARTH_RADIUS
var carries_dragon := true
var fuel_reserve := 4000.0
var fuel := INITIAL_FUEL
var velocity := Vector3.ZERO
# Preserve sub-ULP displacement when this body is millions of metres from
# the scene origin. Vector3 is float32 in the standard Godot build: repeatedly
# adding a 0.02 s step to global_position otherwise introduces a systematic
# drift relative to Dragon's scalar-double trajectory.
var position_residual := Vector3.ZERO
var _last_integrated_position := Vector3(INF, INF, INF)
var thrust_axis := Vector3.UP
var elapsed := 0.0
var actual_throttle := 0.0
var active := true
var impacted := false
var impact_speed := 0.0
var contact_clearance := 3.18
var exhaust_fx: Node
# The time rewind system must save and restore these guidance state variables.
var guidance_start_pitch := -1.0
var guidance_heading := Vector3.ZERO
var angular_speed := 0.0
var orbit_target_met := false
var separation_axis := Vector3.UP
var ignition_clearance_met := true # Standalone stages need no parent-booster check.
var ignition_started_at := -1.0

func _physics_process(delta: float) -> void:
    var substeps := maxi(1, ceili(delta / 0.02))
    var step := delta / substeps
    for index in range(substeps):
        _advance_flight(step)
        if not active:
            break
    update_exhaust()

func update_exhaust() -> void:
    if is_instance_valid(exhaust_fx):
        exhaust_fx.set_throttle(actual_throttle)

func attach_exhaust() -> void:
    if is_instance_valid(exhaust_fx):
        return
    exhaust_fx = Node3D.new()
    exhaust_fx.name = "VacuumEngineEffect"
    exhaust_fx.set_script(VacuumFlame)
    add_child(exhaust_fx)

func _advance_flight(delta: float) -> void:
    if not active or delta <= 0.0:
        return
    elapsed += delta
    var ignition_allowed := elapsed >= IGNITION_DELAY and ignition_clearance_met and fuel > fuel_reserve and not orbit_target_met
    if ignition_allowed and ignition_started_at < 0.0:
        ignition_started_at = elapsed
    if ignition_allowed:
        _advance_guidance(delta)
    else:
        angular_speed = move_toward(angular_speed, 0.0, MAX_TURN_ACCEL * delta)
    var altitude := Earth.altitude(global_position)
    var gravity: Vector3 = Earth.gravity(global_position)
    var firing := ignition_allowed
    var requested := clampf((elapsed - ignition_started_at) / IGNITION_RAMP, 0.0, 1.0) if firing else 0.0
    var thrust := THRUST * requested
    actual_throttle = requested
    if firing:
        var requested_fuel := THRUST * requested / (ISP * G0) * delta
        var used := minf(fuel - fuel_reserve, requested_fuel)
        fuel -= used
        if requested_fuel > 0.0:
            actual_throttle *= used / requested_fuel
            thrust = THRUST * actual_throttle
    var density: float = Earth.atmosphere(altitude).density
    var drag: Vector3 = Earth.drag(velocity, thrust_axis, density, 0.3, FRONTAL_AREA, 1.2, SIDE_AREA)
    var mass := maxf(DRY_MASS + fuel - (0.0 if carries_dragon else 12500.0), 1.0)
    var acceleration := gravity + Earth.rotating_frame_acceleration(global_position, velocity) + thrust_axis * thrust / mass + drag / mass
    velocity += acceleration * delta
    _translate_precisely(velocity * delta)
    if actual_throttle > 0.0 and Earth.altitude(global_position) >= MIN_ORBIT_PERIAPSIS:
        var orbit := orbital_elements()
        if orbit.periapsis >= MIN_ORBIT_PERIAPSIS and orbit.apoapsis <= MAX_ORBIT_APOAPSIS:
            orbit_target_met = true
            actual_throttle = 0.0
    # The launch site uses tangent-plane coordinates. Far downrange, checking
    # only Y reports false ground impacts above the curved Earth.
    var px: float = global_position.x
    var py: float = Earth.EARTH_RADIUS + global_position.y
    var pz: float = global_position.z
    var distance := sqrt(px * px + py * py + pz * pz)
    var contact_radius := Earth.EARTH_RADIUS + GROUND_HEIGHT + contact_clearance
    if distance < contact_radius:
        var scale := contact_radius / maxf(distance, 1.0)
        global_position = Vector3(px * scale, py * scale - Earth.EARTH_RADIUS, pz * scale)
        position_residual = Vector3.ZERO
        _last_integrated_position = global_position
        impact_speed = velocity.length()
        actual_throttle = 0.0
        velocity = Vector3.ZERO
        impacted = true
        active = false

func _advance_guidance(delta: float) -> void:
    var local_up := -Earth.gravity(global_position).normalized()
    var current_axis := global_basis.y.normalized()
    if guidance_start_pitch < 0.0:
        guidance_start_pitch = acos(clampf(current_axis.dot(local_up), -1.0, 1.0))
        # Preserve an established flight azimuth. +X is the default when the
        # rocket has no horizontal velocity at stage separation.
        var horizontal := velocity - local_up * velocity.dot(local_up)
        guidance_heading = horizontal.normalized() if horizontal.length() > 10.0 else Vector3.RIGHT
    var tangent := guidance_heading - local_up * guidance_heading.dot(local_up)
    if tangent.length_squared() < 0.000001:
        tangent = Vector3.RIGHT - local_up * Vector3.RIGHT.dot(local_up)
    tangent = tangent.normalized()
    # Approximate powered-flight guidance: steer toward a target orbital
    # altitude at burnout, accounting for current radial velocity, gravity,
    # centrifugal acceleration and remaining burn time. It is deliberately
    # bounded and does not guarantee an orbital insertion.
    var radius := Earth.EARTH_RADIUS + Earth.altitude(global_position)
    var inertial_velocity: Vector3 = Earth.inertial_velocity(global_position, velocity)
    var radial_velocity := inertial_velocity.dot(local_up)
    var lateral_velocity := inertial_velocity - local_up * radial_velocity
    var time_to_go := maxf((fuel - fuel_reserve) * ISP * G0 / THRUST, GUIDANCE_MIN_TIME_TO_GO)
    var altitude_error := TARGET_ALTITUDE - Earth.altitude(global_position)
    var desired_radial_accel := clampf(6.0 * altitude_error / (time_to_go * time_to_go) - 4.0 * radial_velocity / time_to_go, -6.0, 6.0)
    var gravity := Earth.gravity(global_position).length()
    var centrifugal := lateral_velocity.length_squared() / radius
    var thrust_accel := THRUST / maxf(DRY_MASS + fuel, 1.0)
    var upward_component := (desired_radial_accel + gravity - centrifugal) / thrust_accel
    var pitch := acos(clampf(upward_component, cos(MAX_PITCH), cos(MIN_PITCH)))
    var desired := (local_up * cos(pitch) + tangent * sin(pitch)).normalized()
    var error := acos(clampf(current_axis.dot(desired), -1.0, 1.0))
    var target_rate := minf(MAX_TURN_RATE, sqrt(2.0 * MAX_TURN_ACCEL * error))
    angular_speed = move_toward(angular_speed, target_rate, MAX_TURN_ACCEL * delta)
    if error > 0.000001:
        var step := minf(error, angular_speed * delta)
        var correction := Quaternion(current_axis, desired)
        # Rotate around an approximate center of mass, not around the lower
        # stage interface where this node's origin happens to be.
        var pivot := Vector3(0.0, 7.0, 0.0)
        var old_offset := global_basis * pivot
        global_basis = Basis(Quaternion.IDENTITY.slerp(correction, step / error)) * global_basis
        # Compute the correction near the local origin, avoiding cancellation
        # between two large world-space positions.
        _translate_precisely(old_offset - global_basis * pivot)
    thrust_axis = global_basis.y.normalized()

func _translate_precisely(displacement: Vector3) -> void:
    # Tests, reset and timeline restores may explicitly set global_position.
    # A changed position starts a new accumulation rather than applying an
    # unrelated residual from an earlier trajectory.
    if global_position != _last_integrated_position:
        position_residual = Vector3.ZERO
    var before := global_position
    var requested := displacement + position_residual
    global_position = before + requested
    position_residual = requested - (global_position - before)
    _last_integrated_position = global_position

func orbital_elements() -> Dictionary:
    # Instantaneous two-body orbit from Earth-centered inertial velocity;
    # not a prediction including powered flight or atmospheric drag.
    var px: float = global_position.x
    var py: float = Earth.EARTH_RADIUS + global_position.y
    var pz: float = global_position.z
    var radius := sqrt(px * px + py * py + pz * pz)
    var inertial: Vector3 = Earth.inertial_velocity(global_position, velocity)
    var radial_speed := (px * inertial.x + py * inertial.y + pz * inertial.z) / radius
    var speed_squared := float(inertial.x) * inertial.x + float(inertial.y) * inertial.y + float(inertial.z) * inertial.z
    var angular_momentum_squared := radius * radius * maxf(speed_squared - radial_speed * radial_speed, 0.0)
    var energy := speed_squared * 0.5 - EARTH_MU / radius
    var eccentricity := sqrt(maxf(1.0 + 2.0 * energy * angular_momentum_squared / (EARTH_MU * EARTH_MU), 0.0))
    var periapsis := angular_momentum_squared / (EARTH_MU * (1.0 + eccentricity)) - Earth.EARTH_RADIUS
    var apoapsis := INF
    if eccentricity < 1.0:
        apoapsis = angular_momentum_squared / (EARTH_MU * (1.0 - eccentricity)) - Earth.EARTH_RADIUS
    return {"apoapsis": apoapsis, "periapsis": periapsis, "eccentricity": eccentricity}

func configure_contact() -> void:
    # Measure the lowest point of the actual upper-stage geometry once at
    # separation, including the Merlin Vacuum nozzle and Dragon capsule.
    var lowest := 0.0
    for mesh in find_children("*", "MeshInstance3D", true, false):
        if not mesh.visible:
            continue
        var bounds: AABB = mesh.get_aabb()
        for index in range(8):
            var corner: Vector3 = mesh.global_transform * bounds.get_endpoint(index)
            lowest = minf(lowest, corner.y - global_position.y)
    contact_clearance = maxf(-lowest, 0.0)
