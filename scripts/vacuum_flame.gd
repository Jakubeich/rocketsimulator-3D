extends Node3D

## Visual-only Merlin Vacuum plume. Attach after the upper stage has been
## reparented under the flight controller, then call set_throttle(0..1).
## Can also be attached directly below the FX_MERLIN_VAC marker.
const OUTER_LENGTH := 19.0
const CORE_LENGTH := 8.5
const RESPONSE := 4.0

var _target := 0.0
var _power := 0.0
var _plume: Node3D
var _outer_material: ShaderMaterial
var _core_material: ShaderMaterial
var _light: OmniLight3D

func _ready() -> void:
    var parent := get_parent()
    if parent == null:
        return
    var marker := parent as Node3D if parent.name == "FX_MERLIN_VAC" else parent.find_child("FX_MERLIN_VAC", true, false) as Node3D
    if marker == null:
        push_warning("Merlin Vacuum exhaust marker FX_MERLIN_VAC not found.")
        return

    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float length_m = 19.0;
uniform float strength = 0.0;
uniform float opacity = 0.07;
uniform vec3 nozzle_color : source_color = vec3(0.8, 0.88, 1.0);
uniform vec3 exhaust_color : source_color = vec3(0.25, 0.38, 1.0);
varying float plume_fraction;
void vertex() {
    plume_fraction = clamp((VERTEX.y / length_m) + 0.5, 0.0, 1.0);
}
void fragment() {
    float h = clamp(plume_fraction, 0.0, 1.0);
    float soft_tail = smoothstep(0.0, 0.32, h);
    float noise = 0.94 + 0.06 * sin(TIME * 15.0 + UV.y * 12.0);
    EMISSION = mix(exhaust_color, nozzle_color, smoothstep(0.2, 0.95, h)) * noise;
    ALPHA = opacity * strength * soft_tail * noise;
}
"""
    _outer_material = _make_material(shader, OUTER_LENGTH, 0.085, Color(0.70, 0.81, 1.0), Color(0.24, 0.35, 0.94))
    _core_material = _make_material(shader, CORE_LENGTH, 0.32, Color(1.0, 0.93, 0.82), Color(0.40, 0.56, 1.0))
    _plume = Node3D.new()
    _plume.name = "VacuumExhaust"
    _plume.visible = false
    marker.add_child(_plume)
    _add_cone("OuterPlume", OUTER_LENGTH, 0.9, 3.2, _outer_material)
    _add_cone("HotCore", CORE_LENGTH, 0.55, 0.25, _core_material)
    _light = OmniLight3D.new()
    _light.name = "VacuumExhaustLight"
    _light.position.y = -1.2
    _light.light_color = Color(0.68, 0.78, 1.0)
    _light.light_energy = 0.0
    _light.omni_range = 15.0
    _light.shadow_enabled = false
    marker.add_child(_light)

func _exit_tree() -> void:
    # The marker may be reparented during reset; do not leave stale exhaust
    # nodes behind when the separate upper-stage controller is removed.
    if is_instance_valid(_plume):
        _plume.queue_free()
    if is_instance_valid(_light):
        _light.queue_free()

func set_throttle(value: float) -> void:
    _target = clampf(value, 0.0, 1.0)

func restore_visual_state(power: float, target: float) -> void:
    _power = clampf(power, 0.0, 1.0)
    _target = clampf(target, 0.0, 1.0)
    _process(0.0)

func clear_visuals() -> void:
    # The marker can be reparented before this node is freed on the next
    # frame. Hide its children immediately so rewind never doubles a plume.
    if is_instance_valid(_plume):
        _plume.visible = false
        _plume.queue_free()
    if is_instance_valid(_light):
        _light.light_energy = 0.0
        _light.queue_free()

func _process(delta: float) -> void:
    _power = move_toward(_power, _target, maxf(delta, 0.0) * RESPONSE)
    if not is_instance_valid(_plume):
        return
    _outer_material.set_shader_parameter("strength", _power)
    _core_material.set_shader_parameter("strength", _power)
    _light.light_energy = 1.6 * _power
    _plume.visible = _power > 0.005
    if _plume.visible:
        var flicker := 0.97 + 0.03 * sin(float(Time.get_ticks_msec()) * 0.017)
        _plume.scale = Vector3(1.0, (0.4 + 0.6 * _power) * flicker, 1.0)

func _make_material(shader: Shader, height: float, opacity: float, near_color: Color, far_color: Color) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = shader
    mat.set_shader_parameter("length_m", height)
    mat.set_shader_parameter("opacity", opacity)
    mat.set_shader_parameter("nozzle_color", near_color)
    mat.set_shader_parameter("exhaust_color", far_color)
    mat.set_shader_parameter("strength", 0.0)
    return mat

func _add_cone(piece_name: String, height: float, nozzle_radius: float, tail_radius: float, material: Material) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = nozzle_radius
    mesh.bottom_radius = tail_radius
    mesh.height = height
    mesh.radial_segments = 32
    mesh.rings = 6
    var piece := MeshInstance3D.new()
    piece.name = piece_name
    piece.mesh = mesh
    piece.material_override = material
    piece.position.y = -height * 0.5
    piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _plume.add_child(piece)
