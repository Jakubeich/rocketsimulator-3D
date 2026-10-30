extends SceneTree

## Projects the real drogue canopy meshes into camera 3 after a nominal
## flight and checks the visible viewport and the actual HUD panel rectangles.
## This test is intentionally independent of the camera's framing constants.
const DELTAS := [1.0 / 60.0, 10.0 / 60.0, 50.0 / 60.0]
const SIZES := [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1024, 768)]

class CameraObserver extends Node:
    var rig
    var dragon
    var hud
    var check: Callable
    var start_elapsed := 0.0
    var seen := 0
    var failed := false
    func _process(_delta: float) -> void:
        if dragon.dynamics.elapsed <= start_elapsed + 0.01:
            return
        if not check.call(rig, dragon, hud, "actual camera callback"):
            failed = true
            return
        seen += 1

func _initialize() -> void:
    call_deferred("_test")

func _fail(message: String) -> void:
    push_error("DROGUE CAMERA FAILED: " + message)
    quit(1)

func _key(rig, value: Key) -> void:
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = value
    rig._input(event)

func _step(dragon, delta: float) -> void:
    var steps := maxi(1, ceili(delta / 0.02))
    for i in range(steps):
        dragon._advance_flight(delta / steps)
    dragon.update_visuals()

func _overlaps(point: Vector2, hud) -> bool:
    for panel in [hud.find_child("FlightTelemetry", true, false), hud._time_panel, hud._help_panel]:
        if panel.visible and panel.get_global_rect().has_point(point):
            return true
    return false

func _check(rig, dragon, hud, label: String) -> bool:
    var camera: Camera3D = rig.camera
    var viewport := root.get_visible_rect()
    var bounds := viewport.grow(-3.0)
    for index in range(dragon.parachutes._drogue.size()):
        var canopy: MeshInstance3D = dragon.parachutes._drogue[index].canopy
        if not canopy.is_visible_in_tree():
            _fail(label + ": drogue %d is hidden" % index)
            return false
        for surface in range(canopy.mesh.get_surface_count()):
            var vertices: PackedVector3Array = canopy.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
            for vertex in vertices:
                var point := canopy.global_transform * vertex
                if camera.is_position_behind(point):
                    _fail(label + ": drogue %d lies behind the camera" % index)
                    return false
                var projected := camera.unproject_position(point)
                if not bounds.has_point(projected) or _overlaps(projected, hud):
                    _fail(label + ": drogue %d outside usable viewport: %s in %s" % [index, projected, viewport])
                    return false
    # The capsule is part of the composition. Its visible centre must stay in
    # frame and out of the panels, not merely the two floating canopies.
    var capsule := camera.unproject_position(dragon.global_position)
    if camera.is_position_behind(dragon.global_position) or not bounds.has_point(capsule) or _overlaps(capsule, hud):
        _fail(label + ": capsule outside usable viewport: %s" % capsule)
        return false
    return true

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    var rig = rocket.camera_rig
    var hud = world.get_node("FlightHUD")
    var timeline = world.get_node("MissionTimeline")
    rocket.set_physics_process(false)
    timeline.set_process(false)
    rocket.start_countdown()
    for i in range(2000):
        rocket._physics_process(50.0 / 60.0)
        if is_instance_valid(rocket.dragon_vehicle):
            break
    if not is_instance_valid(rocket.dragon_vehicle):
        return _fail("nominal ascent did not detach Dragon")
    var dragon = rocket.dragon_vehicle
    if not dragon.dynamics.start_return():
        return _fail("return did not start")
    # Capture real flight states over inflation and the handoff to mains.
    var samples := []
    var thresholds := [0.12, 0.35, 0.70, 0.99]
    var last_phase := ""
    for i in range(3600):
        _step(dragon, 50.0 / 60.0)
        if dragon.dynamics.phase == "DROGUE" and not thresholds.is_empty() and dragon.dynamics.drogue_fraction >= thresholds[0]:
            samples.append({"name": "inflation %.2f" % thresholds.pop_front(), "state": dragon.dynamics.get_state().duplicate(true), "transform": dragon.global_transform})
        if dragon.dynamics.phase == "MAIN" and last_phase == "DROGUE":
            samples.append({"name": "main transition", "state": dragon.dynamics.get_state().duplicate(true), "transform": dragon.global_transform})
            break
        last_phase = dragon.dynamics.phase
    if samples.size() != 5:
        return _fail("did not capture all nominal drogue and main-transition states")
    root.mode = Window.MODE_WINDOWED
    # Keep the project's base canvas size. Its `expand` stretch policy changes
    # the visible logical rectangle with the window aspect ratio; replacing the
    # base per case would also change HUD scaling and hide overlap bugs.
    root.content_scale_size = Vector2i(1152, 648)
    for size in SIZES:
        root.size = size
        await process_frame
        for sample in samples:
            dragon.dynamics.set_state(sample.state)
            dragon.global_transform = sample.transform
            dragon.update_visuals()
            # A user can select camera 3 after the drogues are already open.
            _key(rig, KEY_1)
            _key(rig, KEY_3)
            rig._process(0.0)
            if not _check(rig, dragon, hud, "%s %s select 3" % [size, sample.name]):
                return
    # A time snapshot restored while paused refreshes camera using process(0).
    var full = samples[3]
    dragon.dynamics.set_state(full.state)
    dragon.global_transform = full.transform
    dragon.update_visuals()
    timeline.elapsed = 1000.0
    timeline._capture()
    var saved: Dictionary = timeline._history[-1].duplicate(true)
    dragon.dynamics.set_state(samples[4].state)
    dragon.global_transform = samples[4].transform
    dragon.update_visuals()
    timeline._restore(saved)
    if not _check(rig, dragon, hud, "rewind into drogues"):
        return
    # Camera switching and framing remain available during a genuine pause.
    paused = true
    _key(rig, KEY_1)
    _key(rig, KEY_3)
    if not _check(rig, dragon, hud, "select camera while paused"):
        return
    paused = false
    # The projected view must remain usable while the real descent advances
    # through each supported timewarp using the shared substep convention.
    for delta in DELTAS:
        dragon.dynamics.set_state(full.state)
        dragon.global_transform = full.transform
        dragon.update_visuals()
        _key(rig, KEY_3)
        for i in range(10):
            _step(dragon, delta)
            rig._process(delta)
            if not _check(rig, dragon, hud, "%.0fx flight %d" % [delta * 60.0, i]):
                return
    # Mouse-wheel zoom during drogue deployment is a user-controlled value;
    # the automatic composition must not overwrite it on subsequent frames.
    dragon.dynamics.set_state(full.state)
    dragon.global_transform = full.transform
    dragon.update_visuals()
    _key(rig, KEY_3)
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
    wheel.pressed = true
    rig._unhandled_input(wheel)
    var zoom: float = rig.distance
    for i in range(30):
        _step(dragon, 1.0 / 60.0)
        rig._process(1.0 / 60.0)
    if not is_equal_approx(rig.distance, zoom):
        return _fail("manual zoom changed during drogue framing")
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    for i in range(50):
        rig._unhandled_input(wheel)
    var apparent_distance: float = rig.camera.global_position.distance_to(rig.target)
    if absf(apparent_distance - 25.0) > 1.0:
        return _fail("wheel could not reach 25 m closest view, got %.2f m" % apparent_distance)
    # The automatic framing must move smoothly relative to the moving capsule
    # throughout opening; high timewarp permits proportionally larger steps.
    for delta in DELTAS:
        var early = samples[0]
        dragon.dynamics.set_state(early.state)
        dragon.global_transform = early.transform
        dragon.update_visuals()
        _key(rig, KEY_3)
        rig._process(0.0)
        var previous: Vector3 = rig.camera.global_position - dragon.global_position
        var frames := ceili(8.0 / float(delta))
        # Quantized global coordinates contribute up to around one metre.
        # The framing can move tens of metres per simulated second, so the
        # bound scales with the simulated frame rather than real wall time.
        var bound := 2.0 + 25.0 * float(delta)
        for i in range(frames):
            _step(dragon, delta)
            rig._process(delta)
            var next: Vector3 = rig.camera.global_position - dragon.global_position
            if next.distance_to(previous) > bound:
                return _fail("%.0fx camera jumped %.2f m during deployment" % [delta * 60.0, next.distance_to(previous)])
            previous = next
    # Likewise continue over the release of the drogues and main opening.
    for delta in DELTAS:
        var transition = samples[4]
        dragon.dynamics.set_state(transition.state)
        dragon.global_transform = transition.transform
        dragon.update_visuals()
        _key(rig, KEY_3)
        rig._process(0.0)
        var previous: Vector3 = rig.camera.global_position - dragon.global_position
        var frames := ceili(8.5 / float(delta))
        for i in range(frames):
            _step(dragon, delta)
            rig._process(delta)
            var next: Vector3 = rig.camera.global_position - dragon.global_position
            if next.distance_to(previous) > 2.0 + 35.0 * float(delta):
                return _fail("%.0fx camera jumped %.2f m during drogue release, tick %d drogue %.3f main %.3f frame %.3f distance %.2f" % [delta * 60.0, next.distance_to(previous), i, dragon.dynamics.drogue_fraction, dragon.dynamics.main_fraction, rig._drogue_frame_amount(), rig.distance])
            previous = next
    # Restore the same captured state and let the engine deliver actual
    # physics and render callbacks, with the observer scheduled after the
    # camera. This catches stale framing at accelerated simulation rates.
    for rate in [1.0, 10.0, 50.0]:
        timeline._restore(saved)
        _key(rig, KEY_3)
        var observer := CameraObserver.new()
        observer.rig = rig
        observer.dragon = dragon
        observer.hud = hud
        observer.check = _check
        observer.start_elapsed = dragon.dynamics.elapsed
        observer.process_priority = 1000
        world.add_child(observer)
        Engine.time_scale = rate
        rocket.set_physics_process(true)
        var deadline := Time.get_ticks_msec() + 5000
        while observer.seen < 4 and not observer.failed and Time.get_ticks_msec() < deadline:
            await process_frame
        rocket.set_physics_process(false)
        Engine.time_scale = 1.0
        if observer.failed or observer.seen < 4:
            return _fail("actual %.0fx callbacks did not produce four correct frames" % rate)
        observer.queue_free()
    world.queue_free()
    await process_frame
    print("DROGUE CAMERA PASSED: real meshes, inflation, main handoff, 3 viewport ratios, rewind, pause, zoom and smooth 1x/10x/50x")
    quit(0)
