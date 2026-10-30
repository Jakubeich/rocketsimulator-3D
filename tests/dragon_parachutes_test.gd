extends SceneTree
const Parachutes := preload("res://scripts/dragon_parachutes.gd")

func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var mount := Node3D.new()
    root.add_child(mount)
    var visuals := Parachutes.new()
    mount.add_child(visuals)
    await process_frame
    if visuals._drogue.size() != 2 or visuals._main.size() != 4:
        _fail("Crew Dragon requires two drogue and four main chutes")
        return
    visuals.update_visuals(1.0, 0.0, 10.0)
    if not visuals._drogue[0].group.visible or visuals._main[0].group.visible:
        _fail("drogue state must be independently visible")
        return
    var drogue_canopy: MeshInstance3D = visuals._drogue[0].canopy
    if absf(drogue_canopy.scale.x - 1.0) > 0.03:
        _fail("fully deployed drogue must have full-scale canopy")
        return
    visuals.update_visuals(0.0, 1.0, 100.0)
    if visuals._drogue[0].group.visible or not visuals._main[0].group.visible:
        _fail("main chutes must replace the drogues")
        return
    var main: Dictionary = visuals._main[0]
    var canopy: MeshInstance3D = main.canopy
    if absf(canopy.scale.x - 1.0) > 0.03 or main.lines.size() != 16:
        _fail("main canopy and suspension lines must be rendered")
        return
    var airborne_position := canopy.position
    visuals.update_visuals(0.0, 1.0, 100.0, 0.5)
    if canopy.position.y >= airborne_position.y or canopy.scale.y >= 0.8 or not main.ground_lines[0].visible:
        _fail("after touchdown the canopy and lines must begin settling")
        return
    var midway_position := canopy.position
    var midway_scale := canopy.scale
    visuals.update_visuals(0.0, 1.0, 100.0, 1.0)
    if not main.group.visible or absf(canopy.position.y - (visuals.GROUND_Y + 0.12)) > 0.01 or Vector2(canopy.position.x, canopy.position.z).length() < visuals.MAIN_RADIUS + 4.0 or canopy.scale.y > 0.02:
        _fail("landed canopy must flatten on the ground away from the capsule")
        return
    visuals.update_visuals(0.0, 1.0, 100.0, 0.5)
    if not canopy.position.is_equal_approx(midway_position) or not canopy.scale.is_equal_approx(midway_scale):
        _fail("rewind must reproduce the same landing animation")
        return
    visuals.update_visuals(0.0, 0.0, 0.0)
    if main.group.visible:
        _fail("rewind to before deployment must hide the canopies")
        return
    mount.queue_free()
    await process_frame
    print("DRAGON PARACHUTES PASSED: drogue and main visuals, deployment, landing and rewind")
    quit(0)

func _fail(reason: String) -> void:
    push_error("DRAGON PARACHUTES TEST FAILED: " + reason)
    quit(1)
