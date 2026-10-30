extends Node3D

## Visual deployment and limited steering of the four original grid fins.
## Attach to the booster root. This node does not apply aerodynamic forces;
## its steering input illustrates the guidance commands of the flight model.
const DEPLOY_TIME := 4.0
const MAX_STEERING_ANGLE := deg_to_rad(12.0)
const STEERING_RATE := 1.0

var _pivots: Array[Node3D] = []
var _originals: Array[Transform3D] = []
var _amount := 0.0
var _target := 0.0
var _steering := Vector2.ZERO
var _steering_target := Vector2.ZERO
var _usable := false

func _ready() -> void:
    # The booster can remain interactive while the mission is paused, but
    # mechanical deployment must not continue moving during a pause.
    process_mode = Node.PROCESS_MODE_PAUSABLE
    var booster := get_parent() as Node3D
    if booster == null:
        return
    for index in range(1, 5):
        var pivot := booster.find_child("GRID_FIN_PIVOT_%02d" % index, true, false) as Node3D
        if pivot == null:
            push_warning("Grid fin pivot %02d is missing; fins left unchanged." % index)
            return
        _pivots.append(pivot)
        _originals.append(pivot.transform)
    _usable = _pivots.size() == 4
    _render()

func set_deployed(deployed: bool) -> void:
    _target = 1.0 if deployed else 0.0
    if not deployed:
        _steering_target = Vector2.ZERO

## Input X/Z is the approximate steering command in booster-local coordinates,
## normalized to [-1,1]. It is a visual representation, not a force model.
func set_steering(command: Vector2) -> void:
    _steering_target = command.limit_length(1.0)

func get_state() -> Dictionary:
    return {"amount": _amount, "target": _target, "steering": _steering, "steering_target": _steering_target}

func set_state(state: Dictionary) -> void:
    _amount = clampf(float(state.get("amount", 0.0)), 0.0, 1.0)
    _target = clampf(float(state.get("target", 0.0)), 0.0, 1.0)
    var steering: Vector2 = state.get("steering", Vector2.ZERO)
    var steering_target: Vector2 = state.get("steering_target", Vector2.ZERO)
    _steering = steering.limit_length(1.0)
    _steering_target = steering_target.limit_length(1.0)
    _render()

func reset_fins() -> void:
    set_state({})

func _process(delta: float) -> void:
    if not _usable:
        return
    var safe_delta := maxf(delta, 0.0)
    _amount = move_toward(_amount, _target, safe_delta / DEPLOY_TIME)
    _steering = _steering.move_toward(_steering_target, safe_delta * STEERING_RATE)
    _render()

func _render() -> void:
    if not _usable:
        return
    # Each pivot's local Z points outwards and local X runs along its hinge.
    # Its baked children are correctly attached to the pivot, so no vertex
    # positions or shared imported meshes need to be modified.
    var deployed := smoothstep(0.0, 1.0, _amount)
    var command := Vector3(_steering.x, 0.0, _steering.y)
    for index in _pivots.size():
        var original := _originals[index]
        var radial := original.basis.z.normalized()
        var steering_angle := clampf(command.dot(radial), -1.0, 1.0) * MAX_STEERING_ANGLE * deployed
        var yaw := Basis(Quaternion(Vector3.BACK, steering_angle))
        var hinge := Basis(Quaternion(Vector3.RIGHT, -PI * 0.5 * deployed))
        _pivots[index].transform = Transform3D(original.basis * yaw * hinge, original.origin)
