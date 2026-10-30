extends RefCounted

## Flight guidance for a simplified RTLS recovery. All translation comes from
## thrust, gravity, atmospheric drag and bounded grid-fin lift; there is no
## free lateral acceleration in vacuum.
## Body rotation is rate-limited by the rocket controller, not by this pilot.
const Earth := preload("res://scripts/world_physics.gd")
const TARGET := Vector3(-2000.0, -5.54, 0.0)
const BOOSTBACK_LIMIT := 65.0
const BOOSTBACK_REMAINING_FUEL := 20000.0
const ENTRY_REMAINING_FUEL := 12000.0
const ENTRY_SPEED := 650.0
const LANDING_MAX_TILT := deg_to_rad(20.0)
const ALIGNMENT_DOT := 0.99756 # cos(4 degrees)
const PREDICTION_DRAG_FACTOR := 0.8992
const GRID_FIN_AREA := 6.0 # Approximate combined controllable area, m².
const GRID_FIN_LIFT_COEFFICIENT := 0.8 # Simplified bounded lift response.

var phase := "FLIP"
var phase_time := 0.0
var _landing_engines := 3
var _boost_direction := Vector3.ZERO

func step(pos: Vector3, velocity: Vector3, fuel: float, mass: float, delta: float, body_axis: Vector3 = Vector3.UP, total_thrust: float = 8227000.0) -> Dictionary:
    phase_time += delta
    var height := maxf(pos.y - TARGET.y, 0.0)
    var gravity: float = Earth.gravity(pos).length()
    var direction := Vector3.UP
    var throttle := 0.0 # Fraction of the full nine-engine thrust.
    var engines := 3
    var horizontal_position := Vector2(pos.x - TARGET.x, pos.z - TARGET.z)
    var horizontal_velocity := Vector2(velocity.x, velocity.z)

    match phase:
        "FLIP":
            # Mostly retrograde/downrange correction, with a modest downward
            # component. Recompute the target during the turn so that small
            # crossrange disturbances are not locked in at separation.
            var to_target := -horizontal_position.normalized()
            if to_target.length_squared() < 0.01:
                to_target = -horizontal_velocity.normalized()
            if to_target.length_squared() < 0.01:
                to_target = Vector2(-1.0, 0.0)
            # Approximately compensate for crossrange velocity and rotating
            # Earth drift by aiming the real engine thrust. The fixed lookahead
            # is a simple RTLS guidance approximation, not precision guidance.
            var side := Vector2(-to_target.y, to_target.x)
            var frame_accel: Vector3 = Earth.rotating_frame_acceleration(pos, velocity)
            var cross_accel := Vector2(frame_accel.x, frame_accel.z).dot(side)
            var cross_velocity := horizontal_velocity.dot(side)
            var heading_correction := clampf(-cross_accel * 0.0028 - cross_velocity / 1800.0, -0.03, 0.03)
            to_target = (to_target + side * heading_correction).normalized()
            _boost_direction = Vector3(to_target.x * cos(deg_to_rad(5.0)), -sin(deg_to_rad(5.0)), to_target.y * cos(deg_to_rad(5.0)))
            direction = _boost_direction
            if body_axis.normalized().dot(direction) >= ALIGNMENT_DOT:
                _advance("BOOSTBACK")
        "BOOSTBACK":
            direction = _boost_direction
            engines = 3
            throttle = 1.0 / 3.0
            # A simple atmospheric correction to ballistic impact prediction;
            # the actual trajectory remains fully integrated, not interpolated.
            var t_ground := (velocity.y + sqrt(velocity.y * velocity.y + 2.0 * gravity * height)) / maxf(gravity, 0.1)
            var predicted := horizontal_position + horizontal_velocity * t_ground * PREDICTION_DRAG_FACTOR
            if phase_time >= 5.0:
                # Ease the three engines down near predicted cutoff; the
                # 40% floor represents an approximate Merlin throttle limit.
                var miss := predicted.dot(horizontal_position.normalized())
                throttle *= clampf(miss / 8000.0, 0.4, 1.0)
            if (phase_time >= 5.0 and predicted.dot(horizontal_position) <= 0.0) or phase_time >= BOOSTBACK_LIMIT or fuel <= BOOSTBACK_REMAINING_FUEL:
                throttle = 0.0
                _advance("COAST")
        "COAST":
            # Turn tail-first for entry while still coasting through space.
            direction = Vector3.UP
            if height <= 55000.0 and velocity.y < -50.0 and velocity.length() > ENTRY_SPEED:
                _advance("ENTRY_ALIGN")
        "ENTRY_ALIGN":
            direction = -velocity.normalized() if velocity.length() > 1.0 else Vector3.UP
            if body_axis.normalized().dot(direction) >= ALIGNMENT_DOT:
                _advance("ENTRY_BURN")
        "ENTRY_BURN":
            direction = -velocity.normalized() if velocity.length() > 1.0 else Vector3.UP
            engines = 3
            throttle = 1.0 / 3.0
            if velocity.length() <= ENTRY_SPEED or fuel <= ENTRY_REMAINING_FUEL or phase_time >= 25.0:
                throttle = 0.0
                _advance("ENTRY_COAST")
        "ENTRY_COAST":
            direction = Vector3.UP
            var max_decel := maxf(1.0, total_thrust / 3.0 / maxf(mass, 1.0) - gravity)
            var stopping_distance := velocity.y * velocity.y / (2.0 * max_decel)
            if velocity.y < 0.0 and height <= stopping_distance * 1.15 + 500.0:
                _advance("LANDING_BURN")
        "LANDING_BURN":
            # Use the modeled contact surface below the booster rather than
            # the landing-pad height. Outside the pad the curved ground is
            # lower; targeting pad height there can stall the descent above
            # ground until the minimum engine throttle exhausts the fuel.
            var ground_height := TARGET.y if horizontal_position.length() < 43.0 else sqrt(maxf(Earth.EARTH_RADIUS * Earth.EARTH_RADIUS - float(pos.x) * pos.x - float(pos.z) * pos.z, 0.0)) - Earth.EARTH_RADIUS - 6.15
            height = maxf(pos.y - ground_height, 0.0)
            # Constant-deceleration landing guidance: required upward
            # acceleration depends on remaining height and descent speed.
            var required_up := gravity
            if velocity.y < 0.0:
                required_up += maxf(0.0, (velocity.y * velocity.y - 1.0) / (2.0 * maxf(height - 1.0, 1.0)))
            var error := -horizontal_position
            var horizontal_accel := (error * 0.01 - horizontal_velocity * 0.45).limit_length(8.0)
            direction = Vector3(horizontal_accel.x, maxf(required_up, 1.0), horizontal_accel.y).normalized()
            var lateral := Vector2(direction.x, direction.z)
            if lateral.length() > sin(LANDING_MAX_TILT):
                lateral = lateral.normalized() * sin(LANDING_MAX_TILT)
                direction = Vector3(lateral.x, cos(LANDING_MAX_TILT), lateral.y)
            # Use the current axis for vertical force. This accounts for finite
            # rotation rather than applying the desired force instantaneously.
            var vertical_fraction := maxf(body_axis.normalized().y, 0.5)
            var force := maxf(mass, 1.0) * required_up / vertical_fraction
            var center_engine := total_thrust / 9.0
            if _landing_engines == 1 and force > center_engine * 0.95:
                _landing_engines = 3
            elif _landing_engines == 3 and force < center_engine * 0.8:
                _landing_engines = 1
            engines = _landing_engines
            throttle = clampf(force / maxf(total_thrust, 1.0), 0.0, float(engines) / 9.0)
            # Approximate a 40% minimum throttle for each firing engine.
            if throttle > 0.0:
                throttle = maxf(throttle, 0.4 * float(engines) / 9.0)
    if fuel <= 0.0:
        throttle = 0.0

    # Approximate grid-fin lift: controlled acceleration perpendicular to
    # airflow, bounded by dynamic pressure, area and lift coefficient. This
    # produces no correction in vacuum and is not a detailed fin CFD model.
    var fin_accel := Vector3.ZERO
    if phase in ["ENTRY_ALIGN", "ENTRY_BURN", "ENTRY_COAST", "LANDING_BURN"] and velocity.y < -1.0:
        var density: float = Earth.atmosphere(Earth.altitude(pos)).density
        if density > 0.0000001 and velocity.length_squared() > 1.0:
            var desired_xy := (-horizontal_position * 0.004 - horizontal_velocity * 0.35).limit_length(3.0)
            var desired_lift := Vector3(desired_xy.x, 0.0, desired_xy.y)
            var flow := velocity.normalized()
            desired_lift -= flow * desired_lift.dot(flow)
            var max_lift := 0.5 * density * velocity.length_squared() * GRID_FIN_AREA * GRID_FIN_LIFT_COEFFICIENT / maxf(mass, 1.0)
            fin_accel = desired_lift.limit_length(max_lift)

    var labels := {
        "FLIP": "PŘETOČENÍ BOOSTERU", "BOOSTBACK": "NÁVRATOVÝ ZÁŽEH",
        "COAST": "BALISTICKÝ NÁVRAT", "ENTRY_ALIGN": "ORIENTACE PRO VSTUP",
        "ENTRY_BURN": "VSTUPNÍ ZÁŽEH", "ENTRY_COAST": "SESTUP ATMOSFÉROU",
        "LANDING_BURN": "PŘISTÁVACÍ ZÁŽEH"
    }
    return {"throttle": throttle, "engines": engines, "direction": direction, "lateral_accel": fin_accel, "label": labels.get(phase, phase)}

func _advance(next_phase: String) -> void:
    phase = next_phase
    phase_time = 0.0
