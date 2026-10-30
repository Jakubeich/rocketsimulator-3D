extends RefCounted

## Approximate free flight and return of a Crew Dragon capsule. The simulation
## is deliberately separate from its visual representation. World positions
## are kept as scalar doubles because Godot's Vector3 uses single precision.
const Earth := preload("res://scripts/world_physics.gd")
const CAPSULE_MASS := 9600.0
const DRAGON_MASS := 12500.0
const DEORBIT_SECONDS := 720.0
const DEORBIT_ACCEL := 0.22 # effective mean deceleration, m/s²
const DROGUE_ALTITUDE := 5486.4
const MAIN_ALTITUDE := 1828.8
const DROGUE_CDA := 60.0
const MAIN_CDA := 2500.0
const BODY_CDA := 12.0 # approximate blunt-body CdA, not a flight-qualified aerodynamic model
const MAX_STEP := 0.02

var x := 0.0
var y := 0.0
var z := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var elapsed := 0.0
var phase := "ORBIT"
var phase_time := 0.0
var drogue_time := -1.0
var main_time := -1.0
var drogue_fraction := 0.0
var main_fraction := 0.0
var landed := false
var impact_speed := 0.0
var trunk_attached := true
var trunk_release_time := -1.0

func initialize(pos: Vector3, vel: Vector3) -> void:
    x = pos.x
    y = pos.y
    z = pos.z
    vx = vel.x
    vy = vel.y
    vz = vel.z

func position() -> Vector3:
    return Vector3(x, y, z)

func velocity() -> Vector3:
    return Vector3(vx, vy, vz)

func altitude() -> float:
    return maxf(sqrt(x*x + (Earth.EARTH_RADIUS+y)*(Earth.EARTH_RADIUS+y) + z*z) - Earth.EARTH_RADIUS, 0.0)

func up() -> Vector3:
    var r := Earth.EARTH_RADIUS + altitude()
    return Vector3(x/r, (Earth.EARTH_RADIUS+y)/r, z/r)

func start_return() -> bool:
    if phase != "ORBIT" or landed:
        return false
    phase = "DEORBIT"
    phase_time = 0.0
    return true

func step(dt: float) -> void:
    if landed or dt <= 0.0 or not is_finite(dt):
        return
    var count := maxi(1, ceili(dt / MAX_STEP))
    var substep := dt / count
    for index in range(count):
        _step_once(substep)
        if landed:
            break

func _step_once(dt: float) -> void:
    elapsed += dt
    phase_time += dt
    var pos := position()
    var vel := velocity()
    var height := altitude()
    var vertical := vel.dot(up())
    var acceleration: Vector3 = Earth.gravity(pos) + Earth.rotating_frame_acceleration(pos, vel)
    if phase == "DEORBIT":
        var inertial: Vector3 = Earth.inertial_velocity(pos, vel)
        acceleration -= inertial.normalized() * DEORBIT_ACCEL
        if phase_time >= DEORBIT_SECONDS:
            phase = "ENTRY"
            phase_time = 0.0
            trunk_attached = false
            trunk_release_time = elapsed
    if phase == "ENTRY" and height <= DROGUE_ALTITUDE and vertical < 0.0 and vel.length() < 210.0:
        phase = "DROGUE"
        phase_time = 0.0
        drogue_time = elapsed
    if phase == "DROGUE":
        drogue_fraction = smoothstep(0.0, 8.0, phase_time)
        if height <= MAIN_ALTITUDE and vertical < 0.0 and vel.length() < 100.0:
            phase = "MAIN"
            phase_time = 0.0
            main_time = elapsed
    if phase == "MAIN":
        # The two drogues release while the main canopies progressively inflate.
        drogue_fraction = 1.0 - smoothstep(0.0, 2.0, phase_time)
        main_fraction = smoothstep(0.0, 15.0, phase_time)
    var density: float = Earth.atmosphere(height).density
    var cda := BODY_CDA + DROGUE_CDA * drogue_fraction + MAIN_CDA * main_fraction
    var mass := DRAGON_MASS if trunk_attached else CAPSULE_MASS
    if vel.length_squared() > 0.0:
        acceleration -= vel * (0.5 * density * cda * vel.length() / mass)
    vx += float(acceleration.x) * dt
    vy += float(acceleration.y) * dt
    vz += float(acceleration.z) * dt
    x += vx * dt
    y += vy * dt
    z += vz * dt
    var radius := sqrt(x*x + (Earth.EARTH_RADIUS+y)*(Earth.EARTH_RADIUS+y) + z*z)
    if radius <= Earth.EARTH_RADIUS:
        impact_speed = velocity().length()
        var factor := Earth.EARTH_RADIUS / maxf(radius, 1.0)
        x *= factor
        y = (Earth.EARTH_RADIUS+y)*factor - Earth.EARTH_RADIUS
        z *= factor
        vx = 0.0
        vy = 0.0
        vz = 0.0
        landed = true
        phase = "LANDED" if main_fraction > 0.95 and impact_speed < 12.0 else "IMPACT"

# The snapshot uses scalar doubles for world coordinates and velocity.  Using a
# Vector3 here would quantize a rewind at multi-thousand-kilometre distances.
func get_state() -> Dictionary:
    return {
        "x": x, "y": y, "z": z, "vx": vx, "vy": vy, "vz": vz,
        "elapsed": elapsed, "phase": phase, "phase_time": phase_time,
        "drogue_time": drogue_time, "main_time": main_time,
        "drogue_fraction": drogue_fraction, "main_fraction": main_fraction,
        "trunk_attached": trunk_attached, "trunk_release_time": trunk_release_time,
        "landed": landed, "impact_speed": impact_speed,
    }

func set_state(state: Dictionary) -> void:
    x = float(state.x)
    y = float(state.y)
    z = float(state.z)
    vx = float(state.vx)
    vy = float(state.vy)
    vz = float(state.vz)
    elapsed = float(state.elapsed)
    phase = str(state.phase)
    phase_time = float(state.phase_time)
    drogue_time = float(state.drogue_time)
    main_time = float(state.main_time)
    drogue_fraction = float(state.drogue_fraction)
    main_fraction = float(state.main_fraction)
    trunk_attached = bool(state.trunk_attached)
    trunk_release_time = float(state.trunk_release_time)
    landed = bool(state.landed)
    impact_speed = float(state.impact_speed)
