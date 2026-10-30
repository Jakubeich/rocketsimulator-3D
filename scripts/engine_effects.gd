extends Node3D

## Runtime-only Merlin exhaust visuals. Attach this as a child of the rocket
## model; its nine FX_MERLIN_01..09 markers define nozzle positions.  The
## flight controller calls set_throttle() with a value between zero and one.

const CORE_HEIGHT := 4.3
const HALO_HEIGHT := 7.0
const RESPONSE_PER_SECOND := 3.0
# Centre engine first; then opposite pairs to keep return burns symmetric.
const ENGINE_ORDER := [0, 1, 5, 3, 7, 2, 6, 4, 8]

var _target_throttle := 0.0
var _engine_count := 9
var _visible_throttle := 0.0
var _plumes: Array[Node3D] = []
var _core_material: ShaderMaterial
var _halo_material: ShaderMaterial
var _engine_light: OmniLight3D


func _ready() -> void:
    var rocket := get_parent()
    if rocket == null:
        push_warning("Engine effects need the rocket model as their parent.")
        return

    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float plume_height = 4.3;
uniform float opacity = 0.5;
uniform float strength = 0.0;
uniform float outer_shell = 0.0;
varying float height_fraction;
void vertex() {
    height_fraction = clamp((VERTEX.y / plume_height) + 0.5, 0.0, 1.0);
}
void fragment() {
    float h = clamp(height_fraction, 0.0, 1.0);
    vec3 orange = vec3(1.0, 0.18, 0.015);
    vec3 gold = vec3(1.0, 0.55, 0.10);
    vec3 hot = vec3(1.0, 0.82, 0.42);
    vec3 core = mix(orange, gold, smoothstep(0.0, 0.55, h));
    core = mix(core, hot, smoothstep(0.38, 0.90, h));
    vec3 halo = mix(vec3(0.8, 0.045, 0.003), vec3(1.0, 0.38, 0.025), h);
    float pulse = 0.88 + 0.12 * sin(TIME * 27.0 + UV.x * 16.0 + UV.y * 28.0);
    float fade_tip = smoothstep(0.0, 0.20, h);
    EMISSION = mix(core, halo, outer_shell) * pulse;
    ALPHA = opacity * strength * fade_tip * pulse;
}
"""
    _core_material = _make_material(shader, CORE_HEIGHT, 0.24, 0.0)
    _halo_material = _make_material(shader, HALO_HEIGHT, 0.07, 1.0)
    var core_mesh := _make_cone(0.35, 0.025, CORE_HEIGHT)
    var halo_mesh := _make_cone(0.60, 0.035, HALO_HEIGHT)

    for index in range(1, 10):
        var marker := rocket.find_child("FX_MERLIN_%02d" % index, true, false) as Node3D
        if marker == null:
            push_warning("Missing engine marker FX_MERLIN_%02d." % index)
            continue
        var plume := Node3D.new()
        plume.name = "MerlinExhaust%02d" % index
        marker.add_child(plume)
        plume.visible = false
        var halo := MeshInstance3D.new()
        halo.name = "OuterGlow"
        halo.mesh = halo_mesh
        halo.material_override = _halo_material
        halo.position.y = -HALO_HEIGHT * 0.5
        halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        plume.add_child(halo)
        var core := MeshInstance3D.new()
        core.name = "HotCore"
        core.mesh = core_mesh
        core.material_override = _core_material
        core.position.y = -CORE_HEIGHT * 0.5
        core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        plume.add_child(core)
        _plumes.append(plume)
        if index == 1:
            _engine_light = OmniLight3D.new()
            _engine_light.name = "EngineGlow"
            _engine_light.light_color = Color(1.0, 0.38, 0.09)
            _engine_light.light_energy = 0.0
            _engine_light.omni_range = 18.0
            _engine_light.shadow_enabled = false
            _engine_light.position.y = -1.5
            marker.add_child(_engine_light)


func set_throttle(value: float) -> void:
    _target_throttle = clampf(value, 0.0, 1.0)


func set_engine_count(count: int) -> void:
    _engine_count = clampi(count, 0, 9)


func _process(delta: float) -> void:
    _visible_throttle = move_toward(_visible_throttle, _target_throttle, delta * RESPONSE_PER_SECOND)
    if _core_material == null:
        return
    _core_material.set_shader_parameter("strength", _visible_throttle)
    _halo_material.set_shader_parameter("strength", _visible_throttle)
    if _engine_light != null:
        _engine_light.light_energy = 3.0 * _visible_throttle
    var active := _visible_throttle > 0.005
    var time_s := float(Time.get_ticks_msec()) * 0.001
    for index in _plumes.size():
        var plume := _plumes[index]
        plume.visible = active and ENGINE_ORDER.find(index) < _engine_count
        if plume.visible:
            var flicker := 0.95 + 0.05 * sin(time_s * 21.0 + float(index) * 1.73)
            plume.scale = Vector3(1.0, (0.36 + 0.64 * _visible_throttle) * flicker, 1.0)


func _make_material(shader: Shader, height: float, opacity: float, outer: float) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("plume_height", height)
    material.set_shader_parameter("opacity", opacity)
    material.set_shader_parameter("strength", 0.0)
    material.set_shader_parameter("outer_shell", outer)
    return material


func _make_cone(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
    var cone := CylinderMesh.new()
    cone.top_radius = top_radius
    cone.bottom_radius = bottom_radius
    cone.height = height
    cone.radial_segments = 20
    cone.rings = 4
    return cone
