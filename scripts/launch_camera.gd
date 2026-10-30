extends Node3D

const Earth := preload("res://scripts/world_physics.gd")
# The standard single-precision renderer loses directional shadow-map
# stability far from the launch-site origin. Hysteresis keeps the lighting
# stable near the boundary. Direct sunlight remains enabled at all distances.
const SHADOW_DISABLE_DISTANCE := 100000.0
const SHADOW_RESTORE_DISTANCE := 80000.0
# Frame the capsule and its two small drogues while their lines extend. Keep
# this as a temporary composition offset so mouse-wheel zoom remains relative
# to the player's chosen distance and rewinding reconstructs the same view.
const DROGUE_FRAME_HEIGHT := 14.0
const DROGUE_FRAME_DISTANCE := 30.0
const DRAGON_DEFAULT_DISTANCE := 35.0
const DROGUE_FRAME_RELEASE_SECONDS := 8.0

## Inspection camera for the assembled launch site. It does not control the rocket.
@export var target := Vector3(0.0, 41.0, 0.0)
@export var distance := 180.0
@export var yaw := -0.95
@export var pitch := 0.20
@export var min_distance := 25.0
@export var max_distance := 2200.0
@onready var camera: Camera3D = $Camera3D

var _dragging := false
var _follow_rocket := true
var _follow_upper := false
var _follow_dragon := false
var _follow_planet := false
@onready var rocket: Node3D = get_node("../Falcon9_CrewDragon")
@onready var sun: DirectionalLight3D = get_node_or_null("../Sun") as DirectionalLight3D
var _sun_shadows_initially_enabled := false
var _distant_shadows_suppressed := false

func _ready() -> void:
    # The inspection camera never zooms closer than 25 m. A 0.5 m near
    # plane retains ample clearance while improving depth buffer precision
    # for thin overlapping panels, markings and parachute lines.
    camera.near = 0.5
    _sun_shadows_initially_enabled = is_instance_valid(sun) and sun.shadow_enabled
    _update_camera()

func _process(_delta: float) -> void:
    if _follow_planet:
        _update_camera()
    elif _follow_upper:
        target = _dragon_target() if _follow_dragon else _upper_target()
        if _follow_dragon and is_instance_valid(rocket.dragon_vehicle):
            var dynamics = rocket.dragon_vehicle.dynamics
            var amount: float = dynamics.main_fraction
            target += dynamics.up() * (DROGUE_FRAME_HEIGHT * _drogue_frame_amount())
            if amount > 0.01:
                distance = move_toward(distance, maxf(distance, 145.0), maxf(_delta, 0.0) * 18.0)
                target += dynamics.up() * (20.0 * amount)
        _update_camera()
    elif _follow_rocket:
        target = rocket.to_global(Vector3(0.0, 24.0 if rocket.stage_separated else 41.0, 0.0))
        _update_camera()

func _input(event: InputEvent) -> void:
    # Mouse-up may be consumed by a HUD control if a drag ends over it.
    # Always clear dragging here; starting an orbit still requires the press
    # to pass through _unhandled_input, so clicking UI does not rotate the view.
    if event is InputEventMouseButton and not event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
            _dragging = false
        return
    # Use the physical number row as well as logical/numpad keys: on a Czech
    # layout the same keys can otherwise report +, ě, š instead of 1, 2, 3.
    # _input also works while the HUD's start button has keyboard focus.
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if _key_matches(event, KEY_1, KEY_KP_1):
        _follow_planet = false
        _follow_rocket = true
        _follow_upper = false
        _follow_dragon = false
        target = rocket.to_global(Vector3(0.0, 24.0 if rocket.stage_separated else 41.0, 0.0))
        _reset_view()
    elif _key_matches(event, KEY_2, KEY_KP_2):
        _follow_planet = false
        _follow_rocket = false
        _follow_upper = true
        _follow_dragon = false
        target = _upper_target()
        _reset_view()
        distance = 90.0
        _update_camera()
    elif _key_matches(event, KEY_3, KEY_KP_3):
        _follow_planet = false
        _follow_rocket = false
        _follow_upper = true
        _follow_dragon = true
        target = _dragon_target()
        _reset_view()
        distance = DRAGON_DEFAULT_DISTANCE
        if is_instance_valid(rocket.dragon_vehicle):
            var dynamics = rocket.dragon_vehicle.dynamics
            target += dynamics.up() * (DROGUE_FRAME_HEIGHT * _drogue_frame_amount())
            if dynamics.main_fraction > 0.01:
                target += dynamics.up() * (20.0 * dynamics.main_fraction)
        _update_camera()
    elif _key_matches(event, KEY_4, KEY_KP_4):
        _follow_planet = false
        _follow_rocket = false
        _follow_upper = false
        _follow_dragon = false
        target = Vector3(-2000.0, 0.0, 0.0)
        _reset_view()
    elif _key_matches(event, KEY_5, KEY_KP_5):
        _follow_planet = true
        _follow_rocket = false
        _follow_upper = false
        _follow_dragon = false
        _update_camera()
    elif _key_matches(event, KEY_R):
        _follow_planet = false
        _follow_rocket = true
        _follow_upper = false
        _follow_dragon = false
        target = rocket.to_global(Vector3(0.0, 41.0, 0.0))
        _reset_view()
    else:
        return
    if is_instance_valid(rocket):
        rocket._publish_telemetry()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
            _dragging = event.pressed
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _set_framed_distance(maxf(min_distance, _framed_distance() * 0.88))
            _update_camera()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _set_framed_distance(minf(max_distance, _framed_distance() * 1.14))
            _update_camera()
    elif event is InputEventMouseMotion and _dragging:
        yaw -= event.relative.x * 0.006
        pitch = clampf(pitch + event.relative.y * 0.006, -0.1, 1.35)
        _update_camera()

func _key_matches(event: InputEventKey, key: Key, alternate: Key = KEY_NONE) -> bool:
    return event.keycode == key or event.physical_keycode == key or (alternate != KEY_NONE and (event.keycode == alternate or event.physical_keycode == alternate))

func _upper_target() -> Vector3:
    if is_instance_valid(rocket.upper_vehicle):
        return rocket.upper_vehicle.to_global(Vector3(0.0, 7.0, 0.0))
    if is_instance_valid(rocket._upper_stage):
        return rocket._upper_stage.to_global(Vector3(0.0, 7.0, 0.0))
    return rocket.to_global(Vector3(0.0, 55.0, 0.0))

func _dragon_target() -> Vector3:
    if is_instance_valid(rocket._dragon_root):
        return rocket._dragon_root.to_global(Vector3(0.0, 1.7, 0.0))
    return _upper_target()

func _drogue_frame_amount() -> float:
    if not _follow_dragon or not is_instance_valid(rocket.dragon_vehicle):
        return 0.0
    # Match the drogue's line-stretch animation rather than waiting for the
    # inflated canopy: the complete cluster remains framed as it opens.
    var dynamics = rocket.dragon_vehicle.dynamics
    var amount := smoothstep(0.0, 0.4, dynamics.drogue_fraction)
    if dynamics.phase == "MAIN":
        # The small chutes release in two seconds. Let their framing hand off
        # more gently to the main-chute view, including after a time seek.
        amount = maxf(amount, 1.0 - smoothstep(0.0, DROGUE_FRAME_RELEASE_SECONDS, dynamics.phase_time))
    return amount

func _framed_distance() -> float:
    # The default view includes the whole drogue cluster. As the player
    # zooms closer, fade that extra framing distance out so the same 25 m
    # closest view remains available as in other flight phases.
    var range := maxf(DRAGON_DEFAULT_DISTANCE - min_distance, 0.001)
    var fraction := clampf((distance - min_distance) / range, 0.0, 1.0)
    return distance + DROGUE_FRAME_DISTANCE * _drogue_frame_amount() * fraction

func _set_framed_distance(value: float) -> void:
    # Invert the framing function so each wheel notch adjusts the distance
    # actually seen by the player, including during drogue deployment.
    var extra := DROGUE_FRAME_DISTANCE * _drogue_frame_amount()
    var range := maxf(DRAGON_DEFAULT_DISTANCE - min_distance, 0.001)
    if value >= DRAGON_DEFAULT_DISTANCE + extra:
        distance = value - extra
    else:
        distance = min_distance + (value - min_distance) / (1.0 + extra / range)

func _reset_view() -> void:
    distance = 180.0
    yaw = -0.95
    pitch = 0.20
    _update_camera()

func _update_camera() -> void:
    if _follow_planet:
        # A visual overview several radii from the planet; no spacecraft is
        # moved and the analytic sky renders the globe without a giant mesh.
        var center := Vector3(0.0, -Earth.EARTH_RADIUS, 0.0)
        camera.position = center + Vector3(0.0, Earth.EARTH_RADIUS * 1.8, Earth.EARTH_RADIUS * 3.5)
        camera.look_at(center, Vector3.UP)
        _refresh_sky()
        return
    var framed_distance := _framed_distance()
    var horizontal := cos(pitch) * framed_distance
    var offset := Vector3(sin(yaw) * horizontal, sin(pitch) * framed_distance, cos(yaw) * horizontal)
    var up := Vector3.UP
    if _follow_dragon and is_instance_valid(rocket.dragon_vehicle):
        up = rocket.dragon_vehicle.dynamics.up().normalized()
        offset = Quaternion(Vector3.UP, up) * offset
    camera.position = target + offset
    camera.look_at(target, up)
    _refresh_sky()

func _refresh_sky() -> void:
    _refresh_directional_shadows()
    var sky := get_parent().get_node_or_null("FlightSky")
    if sky != null and sky.has_method("refresh_camera"):
        sky.refresh_camera()

func _refresh_directional_shadows() -> void:
    if not is_instance_valid(sun) or not _sun_shadows_initially_enabled:
        return
    var distance_from_origin := camera.global_position.length()
    if not _distant_shadows_suppressed and distance_from_origin > SHADOW_DISABLE_DISTANCE:
        # Shadow-map precision causes the capsule to alternate between bright
        # and nearly black as it moves. Preserve sun lighting, only drop the
        # unstable shadow map until a camera returns near the launch scene.
        _distant_shadows_suppressed = true
        sun.shadow_enabled = false
    elif _distant_shadows_suppressed and distance_from_origin < SHADOW_RESTORE_DISTANCE:
        _distant_shadows_suppressed = false
        sun.shadow_enabled = true
