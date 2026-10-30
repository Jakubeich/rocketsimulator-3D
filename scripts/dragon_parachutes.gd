extends Node3D

## Procedural, visual-only Crew Dragon parachute cluster. Parent this node to
## DRAGON_PARACHUTE_MOUNT; +Y is away from the capsule. Drive it from the
## simulation with update_visuals(), including after restoring a time snapshot.
## Geometry is an approximation of FAA published nominal dimensions: drogue
## diameter 19 ft and suspension 72 ft; main 116 ft and suspension 147 ft.
## The true canopy inflation, reefing and fabric dynamics are not simulated.
const MAIN_RADIUS := 17.68
const DROGUE_RADIUS := 2.895
const MAIN_HEIGHT := 38.0
const DROGUE_HEIGHT := 21.0
# Distance from the model's DRAGON_PARACHUTE_MOUNT to its heat-shield bottom.
const GROUND_Y := -4.04
const ROPES := 16
const CANOPY_SEGMENTS := 48
const CANOPY_RINGS := 9

var _main: Array[Dictionary] = []
var _drogue: Array[Dictionary] = []
var _ready_to_render := false
var _line_mesh: CylinderMesh
var _line_material: StandardMaterial3D
var _main_material: StandardMaterial3D
var _drogue_material: StandardMaterial3D

func _ready() -> void:
    _line_mesh = CylinderMesh.new()
    _line_mesh.top_radius = 1.0
    _line_mesh.bottom_radius = 1.0
    _line_mesh.height = 1.0
    _line_mesh.radial_segments = 5
    _line_material = StandardMaterial3D.new()
    _line_material.albedo_color = Color(0.84, 0.84, 0.79)
    _line_material.roughness = 1.0
    _main_material = _cloth_material()
    _drogue_material = _cloth_material()
    var main_mesh := _build_canopy(MAIN_RADIUS, false)
    var drogue_mesh := _build_canopy(DROGUE_RADIUS, true)
    # Quadrants keep the main canopies visibly distinct, while their suspension
    # lines converge on the model's original parachute mount.
    for i in range(4):
        var diagonal := Vector3(-1.0 if i % 2 == 0 else 1.0, 0.0, -1.0 if i < 2 else 1.0)
        _main.append(_make_chute("Main%02d" % (i + 1), main_mesh, _main_material, diagonal * 16.5, MAIN_HEIGHT + (i % 2) * 0.9, MAIN_RADIUS, ROPES))
    for i in range(2):
        _drogue.append(_make_chute("Drogue%02d" % (i + 1), drogue_mesh, _drogue_material, Vector3(-4.5 if i == 0 else 4.5, 0.0, 0.0), DROGUE_HEIGHT, DROGUE_RADIUS, 8))
    _ready_to_render = true
    update_visuals(0.0, 0.0, 0.0)

func update_visuals(drogue_fraction: float, main_fraction: float, elapsed: float, landing_progress: float = 0.0) -> void:
    if not _ready_to_render:
        return
    var drogue := clampf(drogue_fraction, 0.0, 1.0)
    var main := clampf(main_fraction, 0.0, 1.0)
    var collapse := smoothstep(0.0, 1.0, clampf(landing_progress, 0.0, 1.0))
    for i in _drogue.size():
        _render_chute(_drogue[i], drogue, elapsed, i, true, collapse)
    for i in _main.size():
        # A small, deterministic offset gives each pack its own opening rather
        # than making all four jump to the same size in the same frame.
        var stagger := float(i) * 0.025
        var opening := clampf((main - stagger) / (1.0 - stagger), 0.0, 1.0)
        _render_chute(_main[i], opening, elapsed, i, false, collapse)

func _cloth_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.roughness = 0.92
    return mat

func _build_canopy(radius: float, ribbon: bool) -> ArrayMesh:
    var builder := SurfaceTool.new()
    builder.begin(Mesh.PRIMITIVE_TRIANGLES)
    for ring in range(CANOPY_RINGS):
        # The central vent remains open. Drogues use alternate narrow ribbons
        # rather than a solid sheet, approximating a variable-porosity canopy.
        if ribbon and ring % 2 == 1:
            continue
        var r0 := lerpf(0.10, 1.0, float(ring) / CANOPY_RINGS)
        var r1 := lerpf(0.10, 1.0, float(ring + 1) / CANOPY_RINGS)
        for segment in range(CANOPY_SEGMENTS):
            var a0 := TAU * float(segment) / CANOPY_SEGMENTS
            var a1 := TAU * float(segment + 1) / CANOPY_SEGMENTS
            var white_panel := (segment / 4) % 2 == 0
            var color := Color(0.95, 0.93, 0.87) if white_panel else Color(0.94, 0.25, 0.08)
            if ribbon:
                color = Color(0.91, 0.88, 0.79) if white_panel else Color(0.83, 0.26, 0.09)
            var p00 := _canopy_point(radius, r0, a0, ribbon)
            var p01 := _canopy_point(radius, r0, a1, ribbon)
            var p10 := _canopy_point(radius, r1, a0, ribbon)
            var p11 := _canopy_point(radius, r1, a1, ribbon)
            _vertex(builder, p00, color)
            _vertex(builder, p10, color)
            _vertex(builder, p11, color)
            _vertex(builder, p00, color)
            _vertex(builder, p11, color)
            _vertex(builder, p01, color)
    builder.generate_normals()
    return builder.commit()

func _canopy_point(radius: float, r: float, angle: float, ribbon: bool) -> Vector3:
    var profile := sqrt(maxf(0.0, 1.0 - r * r)) * (0.62 if ribbon else 0.45)
    # A restrained scallop suggests fabric gores without changing the stated
    # nominal size or drawing sharp, faceted triangles along the skirt.
    var skirt := 1.0 - 0.015 * pow(r, 4.0) * (0.5 + 0.5 * cos(angle * ROPES))
    return Vector3(cos(angle) * radius * r * skirt, radius * profile, sin(angle) * radius * r * skirt)

func _vertex(builder: SurfaceTool, point: Vector3, color: Color) -> void:
    builder.set_color(color)
    builder.add_vertex(point)

func _make_chute(label: String, mesh: Mesh, material: Material, offset: Vector3, height: float, radius: float, line_count: int) -> Dictionary:
    var group := Node3D.new()
    group.name = label
    add_child(group)
    var canopy := MeshInstance3D.new()
    canopy.name = "Canopy"
    canopy.mesh = mesh
    canopy.material_override = material
    group.add_child(canopy)
    var lines: Array[MeshInstance3D] = []
    var ground_lines: Array[MeshInstance3D] = []
    for index in range(line_count):
        var line := MeshInstance3D.new()
        line.name = "Suspension%02d" % (index + 1)
        line.mesh = _line_mesh
        line.material_override = _line_material
        line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        group.add_child(line)
        lines.append(line)
        var ground_line := MeshInstance3D.new()
        ground_line.name = "GroundSuspension%02d" % (index + 1)
        ground_line.mesh = _line_mesh
        ground_line.material_override = _line_material
        ground_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        ground_line.visible = false
        group.add_child(ground_line)
        ground_lines.append(ground_line)
    return {"group": group, "canopy": canopy, "lines": lines, "ground_lines": ground_lines, "offset": offset, "height": height, "radius": radius}

func _render_chute(chute: Dictionary, fraction: float, elapsed: float, index: int, small: bool, collapse: float) -> void:
    var group: Node3D = chute.group
    group.visible = fraction > 0.001
    if not group.visible:
        return
    # Line stretch starts immediately; the fabric broadens more slowly.
    var stretch := smoothstep(0.0, 0.4, fraction)
    # Projected fabric area grows roughly with the aerodynamic fraction.
    var inflation := sqrt(clampf(fraction, 0.0, 1.0))
    var sway := sin(elapsed * 0.64 + float(index) * 1.7)
    var sway2 := sin(elapsed * 0.47 + float(index) * 2.1)
    var center: Vector3 = chute.offset * stretch + Vector3.UP * float(chute.height) * stretch
    center += Vector3(sway, 0.0, sway2) * (0.45 if small else 1.1) * inflation * (1.0 - collapse)
    var outward: Vector3 = chute.offset.normalized()
    var ground_center := outward * (10.0 if small else 32.0) + Vector3.UP * (GROUND_Y + 0.12)
    center = center.lerp(ground_center, collapse)
    var canopy: MeshInstance3D = chute.canopy
    canopy.position = center
    var breathing := 1.0 + 0.018 * sin(elapsed * 1.4 + float(index) * 2.0) * (1.0 - collapse)
    # Flatten the cloth against the ground without pulling it into the capsule.
    var vertical_inflation := lerpf(maxf(0.08, inflation), 0.012, collapse)
    canopy.rotation.y = collapse * (0.14 + float(index) * 0.31)
    var horizontal_scale := maxf(0.02, inflation * breathing)
    canopy.scale = Vector3(horizontal_scale * lerpf(1.0, 0.72, collapse), vertical_inflation, horizontal_scale * lerpf(1.0, 0.56, collapse))
    var radius := float(chute.radius)
    var lines: Array = chute.lines
    var ground_lines: Array = chute.ground_lines
    var anchor_angle := float(index) * TAU / 4.0
    var anchor := Vector3(cos(anchor_angle) * 0.35, 0.0, sin(anchor_angle) * 0.35)
    for j in range(lines.size()):
        var angle := TAU * float(j) / lines.size()
        var skirt := center + canopy.basis * Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
        var thickness := 0.026 if small else 0.035
        var ground_line: MeshInstance3D = ground_lines[j]
        ground_line.visible = collapse > 0.001
        if ground_line.visible:
            # Start from a point on the existing straight line so the second
            # segment appears without a jump, then settle it onto the ground.
            var horizontal := Vector3(skirt.x, 0.0, skirt.z).normalized()
            var ground_kink := horizontal * 2.4 + Vector3.UP * (GROUND_Y + 0.045)
            var kink := anchor.lerp(skirt, 0.35).lerp(ground_kink, collapse)
            _span(lines[j], anchor, kink, thickness)
            _span(ground_line, kink, skirt, thickness)
        else:
            _span(lines[j], anchor, skirt, thickness)

func _span(line: MeshInstance3D, start: Vector3, finish: Vector3, thickness: float) -> void:
    var direction := finish - start
    line.position = (start + finish) * 0.5
    line.quaternion = Quaternion(Vector3.UP, direction.normalized()) if direction.length_squared() > 0.000001 else Quaternion.IDENTITY
    line.scale = Vector3(thickness, maxf(direction.length(), 0.001), thickness)
