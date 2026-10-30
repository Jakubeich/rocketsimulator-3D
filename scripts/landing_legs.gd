extends Node3D

## Visual landing gear for the first-stage model. It does not create collisions.
## Add as a child of the whole rocket/booster, then call set_deployed(true).
## The original folded leg meshes are kept when the gear is fully retracted.
const DEPLOY_TIME := 2.0
const TOP_Y := 15.0
const FOOT_Y := 0.18
const FOLDED_RADIUS := 1.95
const DEPLOYED_RADIUS := 7.5

var _original_pivots: Array[Node3D] = []
var _legs: Array[Dictionary] = []
var _amount := 0.0
var _target := 0.0
var _usable := false

func _ready() -> void:
    var rocket := get_parent()
    if rocket == null:
        return
    for i in range(1, 5):
        var pivot := rocket.find_child("LEG_PIVOT_%02d" % i, true, false) as Node3D
        if pivot == null:
            push_warning("Landing gear: original leg pivot %02d is missing; leaving original geometry unchanged." % i)
            return
        _original_pivots.append(pivot)
    var beam_mesh := CylinderMesh.new()
    beam_mesh.top_radius = 1.0
    beam_mesh.bottom_radius = 1.0
    beam_mesh.height = 1.0
    beam_mesh.radial_segments = 12
    var foot_mesh := CylinderMesh.new()
    foot_mesh.top_radius = 1.0
    foot_mesh.bottom_radius = 1.0
    foot_mesh.height = 1.0
    foot_mesh.radial_segments = 20
    var main_material := StandardMaterial3D.new()
    main_material.albedo_color = Color(0.075, 0.085, 0.09)
    main_material.metallic = 0.45
    main_material.roughness = 0.48
    var brace_material := StandardMaterial3D.new()
    brace_material.albedo_color = Color(0.23, 0.25, 0.25)
    brace_material.metallic = 0.62
    brace_material.roughness = 0.4
    var foot_material := StandardMaterial3D.new()
    foot_material.albedo_color = Color(0.045, 0.05, 0.055)
    foot_material.metallic = 0.3
    foot_material.roughness = 0.65
    for pivot in _original_pivots:
        var radial := Vector3(pivot.position.x, 0.0, pivot.position.z).normalized()
        var group := Node3D.new()
        group.name = "DeployableLeg%02d" % (_legs.size() + 1)
        add_child(group)
        var main_beam := _make_piece(group, beam_mesh, main_material, "MainBeam")
        var brace_left := _make_piece(group, beam_mesh, brace_material, "BraceLeft")
        var brace_right := _make_piece(group, beam_mesh, brace_material, "BraceRight")
        var lower_brace := _make_piece(group, beam_mesh, main_material, "LowerBrace")
        var foot := _make_piece(group, foot_mesh, foot_material, "LandingFoot")
        var rim := _make_piece(group, foot_mesh, brace_material, "FootRim")
        _legs.append({"group": group, "radial": radial, "main": main_beam, "left": brace_left, "right": brace_right, "lower": lower_brace, "foot": foot, "rim": rim})
    _usable = _legs.size() == 4
    _render_legs()

func set_deployed(deployed: bool) -> void:
    _target = 1.0 if deployed else 0.0

func reset_legs() -> void:
    _target = 0.0
    _amount = 0.0
    if _usable:
        _render_legs()

func _process(delta: float) -> void:
    if not _usable or is_equal_approx(_amount, _target):
        return
    _amount = move_toward(_amount, _target, delta / DEPLOY_TIME)
    _render_legs()

func _make_piece(parent: Node3D, mesh: Mesh, material: Material, label: String) -> MeshInstance3D:
    var piece := MeshInstance3D.new()
    piece.name = label
    piece.mesh = mesh
    piece.material_override = material
    parent.add_child(piece)
    return piece

func _render_legs() -> void:
    # Only switch away from the source geometry after all replacement meshes exist.
    var replacement_visible := _amount > 0.001
    for pivot in _original_pivots:
        pivot.visible = not replacement_visible
    var t := smoothstep(0.0, 1.0, _amount)
    for leg in _legs:
        var group: Node3D = leg.group
        group.visible = replacement_visible
        if not replacement_visible:
            continue
        var radial: Vector3 = leg.radial
        var tangent := Vector3(-radial.z, 0.0, radial.x)
        var foot_radius := lerpf(FOLDED_RADIUS, DEPLOYED_RADIUS, t)
        var hinge := radial * 1.78 + Vector3.UP * TOP_Y
        var foot_point := radial * foot_radius + Vector3.UP * (FOOT_Y + 0.16)
        var foot_axis := radial * foot_radius + Vector3.UP * FOOT_Y
        _span(leg.main, hinge, foot_point, 0.23)
        var body_anchor := radial * 1.85 + Vector3.UP * 5.3
        var leg_anchor := hinge.lerp(foot_point, 0.76)
        _span(leg.left, body_anchor + tangent * 0.22, leg_anchor + tangent * 0.12, 0.075)
        _span(leg.right, body_anchor - tangent * 0.22, leg_anchor - tangent * 0.12, 0.075)
        _span(leg.lower, radial * 1.95 + Vector3.UP * 3.2, hinge.lerp(foot_point, 0.87), 0.085)
        var foot: MeshInstance3D = leg.foot
        foot.position = foot_axis
        foot.scale = Vector3(0.68, 0.20, 0.68)
        var rim: MeshInstance3D = leg.rim
        rim.position = foot_axis + Vector3.UP * 0.10
        rim.scale = Vector3(0.5, 0.06, 0.5)

func _span(piece: MeshInstance3D, start: Vector3, finish: Vector3, radius: float) -> void:
    var direction := finish - start
    piece.position = (start + finish) * 0.5
    piece.quaternion = Quaternion(Vector3.UP, direction.normalized())
    piece.scale = Vector3(radius, direction.length(), radius)
