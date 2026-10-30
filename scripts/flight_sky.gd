extends Node3D

## Camera-relative, visual-only analytic globe. No million-metre mesh or
## enlarged far plane is needed: nearby scene geometry occludes the sky.
const MAX_FOG_DENSITY := 0.0001
const Earth := preload("res://scripts/world_physics.gd")
const EARTH_SHADER := preload("res://scripts/earth_sky.gdshader")
const EARTH_MAP := preload("res://assets/textures/earth_blue_marble_200407.jpg")
const CLOUD_MAP := preload("res://assets/textures/earth_clouds_nasa_2002.jpg")
const FOG_SCALE_HEIGHT := 8500.0
const UPDATE_INTERVAL_M := 120.0

var _environment: Environment
var _material: ShaderMaterial
var _last_altitude := -INF
var _stars: Node3D
var _distant_land: GeometryInstance3D
var _distant_ocean: GeometryInstance3D
var _last_camera_pos := Vector3(INF, INF, INF)
var _last_landing_region := false

func _ready() -> void:
    var world := get_parent().get_node_or_null("Environment") as WorldEnvironment
    if world == null or world.environment == null:
        push_warning("FlightSky: WorldEnvironment Environment is missing.")
        return
    _environment = world.environment.duplicate(true) as Environment
    world.environment = _environment
    _material = ShaderMaterial.new()
    _material.shader = EARTH_SHADER
    _material.set_shader_parameter("earth_map", EARTH_MAP)
    _material.set_shader_parameter("cloud_map", CLOUD_MAP)
    var sky := Sky.new()
    sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
    sky.radiance_size = Sky.RADIANCE_SIZE_64
    sky.sky_material = _material
    _environment.sky = sky
    _environment.background_mode = Environment.BG_SKY
    _environment.fog_sky_affect = 0.0
    # The former star mesh sat in front of the whole sky and could shine
    # through Earth. The shader now draws stars behind the planetary disc.
    _distant_land = get_parent().get_node_or_null("DistantLand") as GeometryInstance3D
    _distant_ocean = get_parent().get_node_or_null("DistantOcean") as GeometryInstance3D
    _stars = get_parent().get_node_or_null("Stars") as Node3D
    if _stars != null:
        _stars.visible = false
    update_altitude(0.0)

func _process(_delta: float) -> void:
    refresh_camera()

func refresh_camera() -> void:
    var camera := get_viewport().get_camera_3d()
    if camera == null or _material == null:
        return
    var pos: Vector3 = camera.global_position
    var rig = get_parent().get_node_or_null("InspectionCamera")
    var rocket = get_parent().get_node_or_null("Falcon9_CrewDragon")
    var landing_region: bool = rig != null and rig._follow_dragon and rocket != null and is_instance_valid(rocket.dragon_vehicle)
    if pos == _last_camera_pos and landing_region == _last_landing_region:
        return
    _last_camera_pos = pos
    _last_landing_region = landing_region
    _material.set_shader_parameter("landing_region", landing_region)
    var radius := Earth.EARTH_RADIUS
    # Use scalar arithmetic before constructing Vector3 to avoid constructing
    # a 6,371-km world-space vector at rendering precision.
    var relative := Vector3(float(pos.x) / radius, (radius + float(pos.y)) / radius, float(pos.z) / radius)
    _material.set_shader_parameter("camera_earth", relative)
    update_altitude(Earth.altitude(pos))

func update_altitude(altitude_m: float) -> void:
    if _environment == null or _material == null:
        return
    var altitude := maxf(0.0, altitude_m)
    # The older giant tangent planes visibly cut across the globe from orbit.
    # Fade them away at altitude, retaining the detailed local scenery.
    var plane_fade := smoothstep(1800.0, 6500.0, altitude)
    for surface in [_distant_land, _distant_ocean]:
        if is_instance_valid(surface):
            surface.transparency = plane_fade
            surface.visible = plane_fade < 0.999
    _material.set_shader_parameter("altitude_m", altitude)
    if is_finite(_last_altitude) and absf(altitude - _last_altitude) < UPDATE_INTERVAL_M:
        return
    _last_altitude = altitude
    _environment.fog_density = MAX_FOG_DENSITY * exp(-altitude / FOG_SCALE_HEIGHT)
