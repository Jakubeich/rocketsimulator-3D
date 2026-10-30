extends Node3D

## Visual indications only; neither heating nor plume particle flow is a
## flight-qualified thermal or propulsion model.
var _plasma: MeshInstance3D
var _plasma_material: ShaderMaterial
var _thrusters: Array[MeshInstance3D] = []

func _ready() -> void:
    _plasma = MeshInstance3D.new()
    var shell := SphereMesh.new()
    shell.radius = 2.45
    shell.height = 5.5
    shell.radial_segments = 24
    shell.rings = 12
    _plasma.mesh = shell
    _plasma.position.y = 5.75
    var shader := Shader.new()
    shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float strength = 0.0;
uniform float motion = 0.0;
void fragment() {
    float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
    float flicker = 0.8 + 0.2 * sin(UV.y * 25.0 + motion * 9.0);
    ALBEDO = vec3(1.0, 0.24, 0.035);
    EMISSION = vec3(1.0, 0.14, 0.012) * strength * (0.7 + edge);
    ALPHA = strength * (0.08 + edge * 0.25) * flicker;
}
"""
    _plasma_material = ShaderMaterial.new()
    _plasma_material.shader = shader
    _plasma.material_override = _plasma_material
    _plasma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_plasma)
    var plume_mesh := SphereMesh.new()
    plume_mesh.radius = 0.15
    plume_mesh.height = 1.0
    var plume_material := StandardMaterial3D.new()
    plume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    plume_material.albedo_color = Color(0.58, 0.76, 1.0, 0.55)
    plume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    plume_material.emission_enabled = true
    plume_material.emission = Color(0.22, 0.40, 0.85)
    plume_material.emission_energy_multiplier = 1.5
    plume_mesh.material = plume_material
    for i in range(4):
        var angle := float(i) * TAU / 4.0
        var direction := Vector3(cos(angle), 0.0, sin(angle))
        var plume := MeshInstance3D.new()
        plume.mesh = plume_mesh
        plume.position = direction * 2.05 + Vector3.UP * 5.3
        plume.quaternion = Quaternion(Vector3.UP, direction)
        plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(plume)
        _thrusters.append(plume)
    update_visuals("ORBIT", 200000.0, 0.0, 0.0)

func update_visuals(phase: String, altitude: float, speed: float, elapsed: float) -> void:
    if not is_instance_valid(_plasma):
        return
    var heat := smoothstep(105000.0, 70000.0, altitude) * smoothstep(2500.0, 5000.0, speed)
    _plasma.visible = heat > 0.001 and phase == "ENTRY"
    _plasma_material.set_shader_parameter("strength", heat)
    _plasma_material.set_shader_parameter("motion", elapsed)
    for i in range(_thrusters.size()):
        var plume := _thrusters[i]
        plume.visible = phase == "DEORBIT"
        plume.scale.y = 0.85 + 0.15 * sin(elapsed * 13.0 + float(i))
