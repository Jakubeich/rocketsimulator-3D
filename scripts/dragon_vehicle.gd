extends Node3D

## Dragon is advanced by rocket_flight.gd in the same physics substeps as
## both rocket stages. The model is reparented here without changing its pose.
const Dynamics := preload("res://scripts/dragon_dynamics.gd")
const Parachutes := preload("res://scripts/dragon_parachutes.gd")
const ReturnEffects := preload("res://scripts/dragon_return_effects.gd")
const Earth := preload("res://scripts/world_physics.gd")
var dynamics = Dynamics.new()
var model: Node3D
var trunk: Node3D
var trunk_transform: Transform3D
var parachutes: Node3D
var return_effects: Node3D
var field: Node3D
var _field_anchored := false
var _field_anchor_position := Vector3.ZERO
# After touchdown, draw the canopy and suspension lines in the field's local
# frame. The unmodified airborne meshes remain attached to the Dragon.
var _ground_frame: Node3D
var _ground_canopies: MultiMeshInstance3D
var _ground_lines: MultiMeshInstance3D
var _ground_canopy_poses: Array[Transform3D] = []
var _ground_line_poses: Array[Transform3D] = []
const CAPSULE_BOTTOM := 3.588
const GROUND_CLEARANCE := 0.08
var landing_elapsed := 0.0

func configure(dragon_model: Node3D, initial_velocity: Vector3) -> void:
    model = dragon_model
    dynamics.initialize(global_position, initial_velocity)
    trunk = model.find_child("01 | TRUNK", true, false) as Node3D
    if trunk != null:
        trunk_transform = trunk.transform
    var mount := model.find_child("DRAGON_PARACHUTE_MOUNT", true, false) as Node3D
    if mount != null:
        parachutes = Parachutes.new()
        parachutes.name = "Parachutes"
        mount.add_child(parachutes)
    return_effects = ReturnEffects.new()
    return_effects.name = "ReturnEffects"
    add_child(return_effects)
    _create_field()
    update_visuals()

func _advance_flight(delta: float) -> void:
    if dynamics.landed:
        landing_elapsed += delta
    dynamics.step(delta)
    global_position = dynamics.position()
    if not dynamics.trunk_attached:
        # Stable capsule attitude is an approximation to aerodynamic and
        # thruster control, with a gradual transition to heat-shield first.
        var axis := global_basis.y.normalized()
        var desired: Vector3 = dynamics.up()
        var angle := acos(clampf(axis.dot(desired), -1.0, 1.0))
        if angle > 0.00001:
            var q := Quaternion(axis, desired)
            global_basis = Basis(Quaternion.IDENTITY.slerp(q, minf(1.0, delta * deg_to_rad(7.0) / angle))) * global_basis

func update_visuals() -> void:
    if is_instance_valid(return_effects):
        return_effects.update_visuals(dynamics.phase, dynamics.altitude(), dynamics.velocity().length(), dynamics.elapsed)
    if is_instance_valid(trunk):
        trunk.transform = trunk_transform
        if not dynamics.trunk_attached:
            var release_age: float = maxf(0.0, dynamics.elapsed - dynamics.trunk_release_time)
            trunk.position.y -= minf(250.0, release_age * 1.5)
            trunk.visible = release_age < 150.0
        else:
            trunk.visible = true
    if is_instance_valid(field):
        var camera = get_parent().get_node_or_null("InspectionCamera")
        var show: bool = camera != null and camera._follow_dragon and dynamics.altitude() < 22000.0
        field.visible = show
        if show or dynamics.landed:
            var up: Vector3 = dynamics.up()
            var pos: Vector3 = dynamics.position()
            var altitude: float = dynamics.altitude()
            var ground := pos - up * float(altitude - CAPSULE_BOTTOM)
            if not _field_anchored or _field_anchor_position.distance_to(ground) > 4000.0:
                field.global_position = ground
                field.global_basis = Basis(Quaternion(Vector3.UP, up))
                _field_anchor_position = field.global_position
                _field_anchored = true
            # The field is tangent at its anchor, which may be several km from
            # the capsule. Blend out the curvature-induced height mismatch on
            # descent, along the existing plane normal only: the vegetation and
            # the horizontal anchor do not jump when the capsule touches down.
            var normal := field.global_basis.y.normalized()
            var delta_x: float = dynamics.x - float(_field_anchor_position.x) - float(up.x) * (altitude - CAPSULE_BOTTOM)
            var delta_y: float = dynamics.y - float(_field_anchor_position.y) - float(up.y) * (altitude - CAPSULE_BOTTOM)
            var delta_z: float = dynamics.z - float(_field_anchor_position.z) - float(up.z) * (altitude - CAPSULE_BOTTOM)
            var correction := delta_x * normal.x + delta_y * normal.y + delta_z * normal.z
            var settle := 1.0 - smoothstep(0.0, 1000.0, altitude)
            field.global_position = _field_anchor_position + normal * float(correction * settle)
        else:
            _field_anchored = false
    if is_instance_valid(parachutes):
        var collapse := clampf(landing_elapsed / 10.0, 0.0, 1.0)
        parachutes.update_visuals(dynamics.drogue_fraction, dynamics.main_fraction, dynamics.elapsed + landing_elapsed, collapse)
        _update_landed_parachutes(collapse)

func _field_from_parachutes() -> Transform3D:
    # Compute the difference in scalar doubles before making a Vector3. Using
    # affine_inverse() on two multi-million-metre transforms loses the small
    # offset of the chute relative to the landing field.
    var a := field.global_position
    var b := parachutes.global_position
    var offset := Vector3(float(b.x) - float(a.x), float(b.y) - float(a.y), float(b.z) - float(a.z))
    var inverse := field.global_basis.inverse()
    return Transform3D(inverse * parachutes.global_basis, inverse * offset)

func _ensure_ground_parachutes() -> void:
    if is_instance_valid(_ground_canopies) or parachutes._main.is_empty():
        return
    var canopy: MeshInstance3D = parachutes._main[0].canopy
    # Sibling rather than child of field: changing camera while paused must
    # not hide the only visible canopy geometry when field.visible changes.
    _ground_frame = Node3D.new()
    _ground_frame.name = "LandedParachuteFrame"
    get_parent().add_child(_ground_frame)
    _ground_frame.global_transform = field.global_transform
    var canopy_instances := MultiMesh.new()
    canopy_instances.transform_format = MultiMesh.TRANSFORM_3D
    canopy_instances.mesh = canopy.mesh
    canopy_instances.instance_count = parachutes._main.size()
    _ground_canopies = MultiMeshInstance3D.new()
    _ground_canopies.name = "LandedCanopies"
    _ground_canopies.multimesh = canopy_instances
    _ground_canopies.material_override = _landed_surface_material(true)
    _ground_canopies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _ground_frame.add_child(_ground_canopies)

    var line_instances := MultiMesh.new()
    line_instances.transform_format = MultiMesh.TRANSFORM_3D
    line_instances.mesh = parachutes._line_mesh
    line_instances.instance_count = parachutes._main.size() * parachutes.ROPES * 2
    _ground_lines = MultiMeshInstance3D.new()
    _ground_lines.name = "LandedSuspensionLines"
    _ground_lines.multimesh = line_instances
    _ground_lines.material_override = _landed_surface_material(false)
    _ground_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _ground_frame.add_child(_ground_lines)

func _landed_surface_material(vertex_colored: bool) -> ShaderMaterial:
    # The plain is transparent and its depth at planetary coordinates can
    # differ by metres from geometry on it. Bias only the rendered depth, not
    # the actual positions, and preserve occlusion by opaque scene objects.
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;
uniform sampler2D opaque_depth : hint_depth_texture, filter_nearest;
uniform bool vertex_colored = true;
void fragment() {
    float depth = texture(opaque_depth, SCREEN_UV).r;
    if (depth > 0.0) {
        vec4 projected = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
        float opaque_distance = -projected.z / projected.w;
        if (opaque_distance + 0.05 < -VERTEX.z) {
            discard;
        }
    }
    // Reverse-Z depth for the same fragment two metres closer to the camera.
    // Geometry stays on the plain; the opaque depth test above prevents the
    // bias from pulling fabric in front of the capsule or vegetation.
    vec4 near_point = INV_PROJECTION_MATRIX * vec4(0.0, 0.0, 1.0, 1.0);
    float near_z = near_point.z / near_point.w;
    float biased_z = min(VERTEX.z + 2.0, near_z - 0.001);
    vec4 biased = PROJECTION_MATRIX * vec4(VERTEX.xy, biased_z, 1.0);
    DEPTH = biased.z / biased.w;
    ALBEDO = vertex_colored ? COLOR.rgb : vec3(0.84, 0.84, 0.79);
    ROUGHNESS = 0.92;
    ALPHA = 1.0;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.render_priority = 1
    material.set_shader_parameter("vertex_colored", vertex_colored)
    return material

func _update_landed_parachutes(collapse: float) -> void:
    var use_ground_frame: bool = dynamics.landed and is_instance_valid(field) and dynamics.main_fraction > 0.0
    if not use_ground_frame:
        if is_instance_valid(_ground_canopies):
            _ground_canopies.visible = false
            _ground_lines.visible = false
        # Restore original airborne geometry when the camera or time changes.
        for chute in parachutes._main:
            chute.canopy.visible = true
            for line in chute.lines:
                line.visible = true
        return
    _ensure_ground_parachutes()
    if not is_instance_valid(_ground_canopies):
        return
    _ground_frame.global_transform = field.global_transform
    _ground_canopies.visible = true
    _ground_lines.visible = true
    _ground_canopy_poses.clear()
    _ground_line_poses.clear()
    var field_from_mount := _field_from_parachutes()
    var settled := smoothstep(0.0, 1.0, clampf(collapse, 0.0, 1.0))
    var line_index := 0
    for i in range(parachutes._main.size()):
        var chute: Dictionary = parachutes._main[i]
        var canopy: MeshInstance3D = chute.canopy
        var pose: Transform3D = field_from_mount * canopy.transform
        var nominal_ground: Vector3 = chute.offset.normalized() * 32.0 + Vector3.UP * (parachutes.GROUND_Y + 0.12)
        var final_height: float = (field_from_mount * nominal_ground).y
        var correction := (GROUND_CLEARANCE - final_height) * settled
        pose.origin.y += correction
        # Align flattened fabric with the field, including its perimeter, not
        # just its centre. This avoids clipping on the tangent plane.
        pose.basis.x.y = lerpf(pose.basis.x.y, 0.0, settled)
        pose.basis.z.y = lerpf(pose.basis.z.y, 0.0, settled)
        pose.basis.y.x = lerpf(pose.basis.y.x, 0.0, settled)
        pose.basis.y.z = lerpf(pose.basis.y.z, 0.0, settled)
        _ground_canopy_poses.append(pose)
        _ground_canopies.multimesh.set_instance_transform(i, pose)
        canopy.visible = false

        for j in range(chute.lines.size()):
            var line: MeshInstance3D = chute.lines[j]
            var ground_line: MeshInstance3D = chute.ground_lines[j]
            var start: Vector3 = field_from_mount * (line.position - line.basis.y * 0.5)
            var end: Vector3 = field_from_mount * (line.position + line.basis.y * 0.5)
            start.y = maxf(start.y, GROUND_CLEARANCE)
            if ground_line.visible:
                end.y = maxf(end.y, GROUND_CLEARANCE)
            else:
                end.y = maxf(end.y + correction, GROUND_CLEARANCE)
            _set_ground_line(line_index, start, end, line.basis.x.length())
            line_index += 1
            line.visible = false
            if ground_line.visible:
                var skirt: Vector3 = field_from_mount * (ground_line.position + ground_line.basis.y * 0.5)
                skirt.y = maxf(skirt.y + correction, GROUND_CLEARANCE)
                _set_ground_line(line_index, end, skirt, ground_line.basis.x.length())
                line_index += 1
                ground_line.visible = false
    _ground_lines.multimesh.visible_instance_count = line_index

func _set_ground_line(index: int, start: Vector3, end: Vector3, thickness: float) -> void:
    var direction := end - start
    var length := maxf(direction.length(), 0.001)
    var rotation := Quaternion(Vector3.UP, direction.normalized()) if direction.length_squared() > 0.000001 else Quaternion.IDENTITY
    var scaled := Basis(rotation) * Basis.from_scale(Vector3(thickness, length, thickness))
    var pose := Transform3D(scaled, (start + end) * 0.5)
    _ground_line_poses.append(pose)
    _ground_lines.multimesh.set_instance_transform(index, pose)

func prepare_reattach() -> void:
    if is_instance_valid(trunk):
        trunk.transform = trunk_transform
        trunk.visible = true
    if is_instance_valid(parachutes):
        parachutes.queue_free()
        parachutes = null
    if is_instance_valid(field):
        field.queue_free()
        field = null
    if is_instance_valid(_ground_frame):
        _ground_frame.queue_free()
        _ground_frame = null

func _create_field() -> void:
    # A local, stylized landing plain. The project has no planet-scale terrain
    # or geographic land/ocean map, so this surface is a visual approximation.
    field = Node3D.new()
    field.name = "DragonLandingPlain"
    get_parent().add_child(field)
    var surface := MeshInstance3D.new()
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(30000.0, 30000.0)
    surface.mesh = mesh
    var shader := Shader.new()
    shader.code = """shader_type spatial;
render_mode diffuse_burley, blend_mix, depth_draw_opaque;
void fragment() {
    vec2 p = (UV - vec2(0.5)) * 30000.0;
    float a = sin(p.x * 0.006 + sin(p.y * 0.004)) * sin(p.y * 0.008);
    float b = sin(p.x * 0.047) * sin(p.y * 0.035);
    ALBEDO = mix(vec3(0.26, 0.34, 0.18), vec3(0.40, 0.43, 0.25), clamp(0.5 + a * 0.22 + b * 0.05, 0.0, 1.0));
    ROUGHNESS = 1.0;
    // Feather the distant perimeter into the analytic planet rather than
    // showing the border of a rectangular local landing patch.
    float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
    ALPHA = smoothstep(0.0, 0.20, edge);
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    surface.material_override = material
    surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    field.add_child(surface)
    # Sparse low vegetation provides scale without representing a real place.
    var bush_mesh := SphereMesh.new()
    bush_mesh.radius = 0.65
    bush_mesh.height = 1.1
    bush_mesh.radial_segments = 6
    bush_mesh.rings = 4
    var vegetation_material := StandardMaterial3D.new()
    vegetation_material.albedo_color = Color(0.20, 0.30, 0.12)
    vegetation_material.roughness = 1.0
    vegetation_material.vertex_color_use_as_albedo = true
    bush_mesh.material = vegetation_material
    var plants := MultiMesh.new()
    plants.transform_format = MultiMesh.TRANSFORM_3D
    plants.use_colors = true
    plants.mesh = bush_mesh
    plants.instance_count = 1800
    var random := RandomNumberGenerator.new()
    random.seed = 2861
    for i in range(plants.instance_count):
        var x := random.randf_range(-850.0, 850.0)
        var z := random.randf_range(-850.0, 850.0)
        var scale := random.randf_range(0.5, 1.7)
        plants.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(scale, scale * 0.8, scale)), Vector3(x, 0.36 * scale, z)))
        plants.set_instance_color(i, Color(random.randf_range(0.65, 1.0), random.randf_range(0.72, 1.0), random.randf_range(0.65, 1.0)))
    var vegetation := MultiMeshInstance3D.new()
    vegetation.multimesh = plants
    vegetation.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    field.add_child(vegetation)
    field.visible = false
