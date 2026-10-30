extends RefCounted

## Shared Earth gravity and idealized 1976 standard atmosphere.
## Coordinates are metres relative to the launch site; +Y is local up.
## USSA's lower layers extend to 86 km geometric altitude; at 86–1000 km
## density and pressure use log interpolation of NASA's abbreviated tables.
## Above 1000 km a simple scale-height extrapolation is used.
const EARTH_RADIUS := 6371000.0
const GEOPOTENTIAL_RADIUS := 6356766.0
const G0 := 9.80665
const GAS_CONSTANT := 287.05287
const SEA_LEVEL_PRESSURE := 101325.0
const EARTH_ROTATION := 0.00007292115
const LAUNCH_LATITUDE := deg_to_rad(28.5)
const HEIGHTS := [0.0, 11000.0, 20000.0, 32000.0, 47000.0, 51000.0, 71000.0, 84852.0]
const TEMPERATURES := [288.15, 216.65, 216.65, 228.65, 270.65, 270.65, 214.65, 186.946]
const PRESSURES := [101325.0, 22632.06, 5474.889, 868.0187, 110.9063, 66.93887, 3.956420, 0.373384]
const LAPSE_RATES := [-0.0065, 0.0, 0.001, 0.0028, 0.0, -0.0028, -0.002]
# NASA/TP-2007-214904, table A-6-3: heights m, density kg/m^3,
# pressure Pa (table values converted from g/cm^3 and millibars).
const UPPER_HEIGHTS := [86000.0, 100000.0, 120000.0, 140000.0, 160000.0, 180000.0, 200000.0, 300000.0, 400000.0, 500000.0, 600000.0, 800000.0, 1000000.0]
const UPPER_DENSITIES := [6.958e-6, 5.604e-7, 2.222e-8, 3.831e-9, 1.233e-9, 5.194e-10, 2.541e-10, 1.916e-11, 2.803e-12, 5.215e-13, 1.137e-13, 1.136e-14, 3.561e-15]
const UPPER_PRESSURES := [0.373384, 0.032011, 0.0025382, 0.00072028, 0.00030395, 0.00015271, 0.000084736, 0.0000087704, 0.0000014518, 0.00000030236, 0.00000008213, 0.000000017036, 0.0000000075138]
const UPPER_TEMPERATURES := [186.946, 195.08, 360.0, 559.63, 696.29, 790.07, 854.56, 976.01, 995.83, 999.24, 999.85, 999.99, 1000.0]

static func altitude(position: Vector3) -> float:
    # Scalar arithmetic avoids losing metre-level precision by constructing a
    # float32 Vector3 at the Earth's centre, millions of metres from origin.
    var x: float = position.x
    var y: float = EARTH_RADIUS + position.y
    var z: float = position.z
    return maxf(sqrt(x*x + y*y + z*z) - EARTH_RADIUS, 0.0)

static func gravity(position: Vector3) -> Vector3:
    var x: float = position.x
    var y: float = EARTH_RADIUS + position.y
    var z: float = position.z
    var distance := sqrt(x*x + y*y + z*z)
    if distance < EARTH_RADIUS:
        distance = EARTH_RADIUS
    var acceleration := G0 * pow(EARTH_RADIUS / distance, 2.0)
    return Vector3(-x / distance, -y / distance, -z / distance) * acceleration

static func inertial_velocity(position: Vector3, velocity: Vector3) -> Vector3:
    # Local axes are east (+X), up (+Y), south (+Z). The surface and the
    # atmosphere rotate with Earth; orbital elements need inertial velocity.
    var omega_y := EARTH_ROTATION * sin(LAUNCH_LATITUDE)
    var omega_z := -EARTH_ROTATION * cos(LAUNCH_LATITUDE)
    var x: float = position.x
    var y: float = EARTH_RADIUS + position.y
    var z: float = position.z
    return velocity + Vector3(omega_y * z - omega_z * y, omega_z * x, -omega_y * x)

static func rotating_frame_acceleration(position: Vector3, velocity: Vector3) -> Vector3:
    # Coriolis and centrifugal acceleration in the Earth-fixed launch frame.
    var omega := Vector3(0.0, EARTH_ROTATION * sin(LAUNCH_LATITUDE), -EARTH_ROTATION * cos(LAUNCH_LATITUDE))
    var radius := Vector3(position.x, EARTH_RADIUS + position.y, position.z)
    return -2.0 * omega.cross(velocity) - omega.cross(omega.cross(radius))

static func atmosphere(geometric_height: float) -> Dictionary:
    var height := maxf(geometric_height, 0.0)
    var geopotential := GEOPOTENTIAL_RADIUS * height / (GEOPOTENTIAL_RADIUS + height)
    if geopotential >= HEIGHTS[7]:
        if height >= UPPER_HEIGHTS[-1]:
            var scale := exp(-(height - UPPER_HEIGHTS[-1]) / 288203.0)
            return {"density": UPPER_DENSITIES[-1] * scale, "pressure": UPPER_PRESSURES[-1] * scale, "temperature": UPPER_TEMPERATURES[-1]}
        var upper_layer := 0
        for index in range(1, UPPER_HEIGHTS.size()):
            if height < UPPER_HEIGHTS[index]:
                break
            upper_layer = index
        var t: float = (height - UPPER_HEIGHTS[upper_layer]) / (UPPER_HEIGHTS[upper_layer + 1] - UPPER_HEIGHTS[upper_layer])
        var density := exp(lerpf(log(UPPER_DENSITIES[upper_layer]), log(UPPER_DENSITIES[upper_layer + 1]), t))
        var pressure := exp(lerpf(log(UPPER_PRESSURES[upper_layer]), log(UPPER_PRESSURES[upper_layer + 1]), t))
        return {"density": density, "pressure": pressure, "temperature": lerpf(UPPER_TEMPERATURES[upper_layer], UPPER_TEMPERATURES[upper_layer + 1], t)}
    var layer := 0
    for index in range(1, HEIGHTS.size()):
        if geopotential < HEIGHTS[index]:
            break
        layer = index
    var base_temperature: float = TEMPERATURES[layer]
    var base_pressure: float = PRESSURES[layer]
    var lapse: float = LAPSE_RATES[layer]
    var offset: float = geopotential - HEIGHTS[layer]
    var temperature := base_temperature + lapse * offset
    var pressure: float
    if is_zero_approx(lapse):
        pressure = base_pressure * exp(-G0 * offset / (GAS_CONSTANT * base_temperature))
    else:
        pressure = base_pressure * pow(base_temperature / temperature, G0 / (GAS_CONSTANT * lapse))
    return {"density": pressure / (GAS_CONSTANT * temperature), "pressure": pressure, "temperature": temperature}

static func drag(velocity: Vector3, body_axis: Vector3, density: float, axial_cd: float, frontal_area: float, lateral_cd: float, side_area: float) -> Vector3:
    var axis := body_axis.normalized()
    var axial_speed := velocity.dot(axis)
    var lateral_speed := velocity - axis * axial_speed
    var force := -0.5 * density * axial_cd * frontal_area * axial_speed * absf(axial_speed) * axis
    force -= 0.5 * density * lateral_cd * side_area * lateral_speed.length() * lateral_speed
    return force
