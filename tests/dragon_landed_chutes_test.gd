extends SceneTree

## Actual nominal ascent and return: varied orbital coast before the return
## burn, and physics deltas corresponding to 1x, 10x and 50x at 60 Hz.
## The checks inspect every vertex of each *visible* canopy against the actual
## local landing plane, not merely node visibility or a rounded global AABB.
const CALLBACKS := [1.0 / 60.0, 10.0 / 60.0, 50.0 / 60.0]
const DELAYS := [0.0, 50.0 / 60.0, 250.0 / 60.0]

func _initialize() -> void:
    call_deferred("_test")

func _fail(message: String) -> void:
    push_error("LANDED CHUTES FAILED: " + message)
    Engine.time_scale = 1.0
    quit(1)

func _advance(dragon, delta: float, render: bool) -> void:
    # Match rocket_flight.gd's shared physics substep ordering.
    var count := maxi(1, ceili(delta / 0.02))
    for i in range(count):
        dragon._advance_flight(delta / count)
    if render:
        dragon.update_visuals()

func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
    # The transforms in the chain are local/small; computing by subtracting
    # million-metre global matrices would introduce a spurious half-metre error.
    var transform := Transform3D.IDENTITY
    var current: Node = node
    while current != ancestor:
        if current == null:
            return Transform3D.IDENTITY
        if current is Node3D:
            transform = (current as Node3D).transform * transform
        current = current.get_parent()
    return transform

func _vertices(mesh: Mesh) -> PackedVector3Array:
    var result := PackedVector3Array()
    for surface in range(mesh.get_surface_count()):
        result.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
    return result

func _measure_relative(vertices: PackedVector3Array, transform: Transform3D) -> Dictionary:
    var minimum := INF
    var maximum := -INF
    var max_radius := 0.0
    for vertex in vertices:
        var point := transform * vertex
        minimum = minf(minimum, point.y)
        maximum = maxf(maximum, point.y)
        max_radius = maxf(max_radius, maxf(absf(point.x), absf(point.z)))
    return {"min": minimum, "max": maximum, "radius": max_radius}

func _canopy_measurements(dragon) -> Array:
    var field: Node3D = dragon.field
    var measurements := []
    var source_mesh: Mesh = dragon.parachutes._main[0].canopy.mesh
    # The field-aligned ground frame shares the plane's world transform; its
    # MultiMesh contains the four visible parachute canopies, not vegetation.
    var proxy_root: Node3D = dragon._ground_frame
    if is_instance_valid(proxy_root) and proxy_root.global_transform != field.global_transform:
        _fail("the landed canopy frame is not aligned with the actual field")
        return measurements
    var proxy_nodes: Array = proxy_root.find_children("*", "MultiMeshInstance3D", true, false) if is_instance_valid(proxy_root) else []
    for node in proxy_nodes:
        var multi := node as MultiMeshInstance3D
        if not multi.is_visible_in_tree() or multi.multimesh == null or multi.multimesh.mesh != source_mesh:
            continue
        var count := multi.multimesh.instance_count
        var visible_count := multi.multimesh.visible_instance_count
        if visible_count >= 0:
            count = mini(count, visible_count)
        var parent_transform := _relative_transform(multi, proxy_root)
        var vertices := _vertices(multi.multimesh.mesh)
        for index in range(count):
            var pose: Transform3D = multi.multimesh.get_instance_transform(index)
            # RenderingServer's dummy backend in --headless does not retain
            # MultiMesh transforms. In that mode read the same CPU pose sent to
            # the renderer; graphical verification additionally checks the GPU.
            if DisplayServer.get_name() == "headless":
                pose = dragon._ground_canopy_poses[index]
            measurements.append(_measure_relative(vertices, parent_transform * pose))
    if not measurements.is_empty():
        return measurements
    # Original MeshInstance3D representation: calculate the field-relative
    # origin component-wise to avoid cancellation in field.to_local().
    var normal: Vector3 = field.global_basis.y.normalized()
    var origin: Vector3 = field.global_position
    for item in dragon.parachutes._main:
        var canopy: MeshInstance3D = item.canopy
        if not canopy.is_visible_in_tree():
            continue
        var p: Vector3 = canopy.global_position
        var dx := float(p.x) - float(origin.x)
        var dy := float(p.y) - float(origin.y)
        var dz := float(p.z) - float(origin.z)
        var center := dx * normal.x + dy * normal.y + dz * normal.z
        var lo := INF
        var hi := -INF
        for vertex in _vertices(canopy.mesh):
            var offset := canopy.global_basis * vertex
            var height := center + float(offset.x) * normal.x + float(offset.y) * normal.y + float(offset.z) * normal.z
            lo = minf(lo, height)
            hi = maxf(hi, height)
        measurements.append({"min": lo, "max": hi, "radius": 0.0})
    return measurements

func _assert_settled(dragon, label: String) -> bool:
    if not dragon.field.visible:
        _fail(label + ": landing field is not visible to camera 3")
        return false
    if not dragon._ground_canopies.is_visible_in_tree() or not dragon._ground_lines.is_visible_in_tree():
        _fail(label + ": landed proxy geometry is hidden")
        return false
    for chute in dragon.parachutes._main:
        if chute.canopy.is_visible_in_tree():
            _fail(label + ": both airborne and landed canopy are visible")
            return false
    var metrics := _canopy_measurements(dragon)
    if metrics.size() != 4:
        _fail(label + ": expected four rendered canopies; got %d" % metrics.size())
        return false
    for index in metrics.size():
        var item: Dictionary = metrics[index]
        # A small positive clearance prevents depth fighting; a high clearance
        # would produce obvious levitation. The field is fully opaque near its
        # center, unlike the feathered distant edges.
        if float(item.min) < 0.02 or float(item.max) > 1.5 or float(item.radius) > 8900.0:
            _fail(label + ": canopy %d not resting visibly above field: %s" % [index + 1, item])
            return false
    print("CANOPIES ", label, ": ", metrics)
    return true

func _test() -> void:
    var world = (load("res://scenes/launch_site.tscn") as PackedScene).instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    var rocket = world.get_node("Falcon9_CrewDragon")
    var timeline = world.get_node("MissionTimeline")
    rocket.set_physics_process(false)
    timeline.set_process(false)
    var key := InputEventKey.new()
    key.pressed = true
    key.keycode = KEY_3
    rocket.camera_rig._input(key)
    rocket.start_countdown()
    # Existing ascent/boostback tests cover the rates; here obtain the real
    # separated Dragon state as the starting point for the return cases.
    for i in range(2000):
        rocket._physics_process(50.0 / 60.0)
        if is_instance_valid(rocket.dragon_vehicle):
            break
    if not is_instance_valid(rocket.dragon_vehicle):
        return _fail("nominal ascent did not separate Dragon")
    var dragon = rocket.dragon_vehicle
    var initial_state: Dictionary = dragon.dynamics.get_state().duplicate(true)
    var initial_transform: Transform3D = dragon.global_transform
    var case_index := 0
    for delta in CALLBACKS:
        for delay in DELAYS:
            case_index += 1
            dragon.dynamics.set_state(initial_state)
            dragon.global_transform = initial_transform
            dragon.landing_elapsed = 0.0
            dragon._field_anchored = false
            dragon.field.visible = false
            dragon.update_visuals()
            var coast := 0.0
            while coast < delay - 0.000001:
                var tick := minf(float(delta), float(delay) - coast)
                _advance(dragon, tick, true)
                coast += tick
            if not dragon.dynamics.start_return():
                return _fail("return did not start in case %d" % case_index)
            var steps := 0
            var last_visual := 0.0
            var saw_main := false
            var before_contact: Dictionary = {}
            while not dragon.dynamics.landed and steps * delta < 3000.0:
                var render: bool = last_visual >= 0.16 or float(dragon.dynamics.altitude()) < 20.0
                _advance(dragon, delta, render)
                last_visual = 0.0 if render else last_visual + delta
                steps += 1
                saw_main = saw_main or dragon.dynamics.phase == "MAIN"
                # One snapshot immediately before contact, for a real rewind
                # across touchdown after this representative trajectory.
                if case_index == 9 and before_contact.is_empty() and dragon.dynamics.altitude() < 20.0 and not dragon.dynamics.landed:
                    timeline.elapsed = 1100.0
                    timeline._capture()
                    before_contact = timeline._history[-1].duplicate(true)
            if not dragon.dynamics.landed or dragon.dynamics.phase != "LANDED" or not saw_main:
                return _fail("case %d never achieved nominal landing" % case_index)
            while dragon.landing_elapsed < 12.0:
                _advance(dragon, delta, true)
            dragon.update_visuals()
            var label := "%.0fx / delay %.2f s" % [delta * 60.0, delay]
            if not _assert_settled(dragon, label):
                return
            if case_index == 9:
                if before_contact.is_empty():
                    return _fail("rewind snapshot was not recorded")
                timeline.elapsed = 1200.0
                timeline._capture()
                var after_contact: Dictionary = timeline._history[-1].duplicate(true)
                timeline._restore(before_contact)
                if dragon.dynamics.landed:
                    return _fail("rewind did not restore descent")
                if dragon._ground_canopies.visible:
                    return _fail("rewind retained landed canopy proxy during descent")
                for chute in dragon.parachutes._main:
                    if not chute.canopy.is_visible_in_tree():
                        return _fail("rewind did not restore airborne canopies")
                while not dragon.dynamics.landed:
                    _advance(dragon, delta, true)
                while dragon.landing_elapsed < 12.0:
                    _advance(dragon, delta, true)
                if not _assert_settled(dragon, "replayed touchdown"):
                    return
                timeline._restore(after_contact)
                if not _assert_settled(dragon, "restored landed snapshot"):
                    return
                # Exercise real engine physics callbacks as well as manually
                # driven substeps. Replay the same pre-contact snapshot at each
                # supported time rate and let the scene tree advance it.
                for rate in [1.0, 10.0, 50.0]:
                    timeline._restore(before_contact)
                    Engine.time_scale = rate
                    rocket.set_physics_process(true)
                    var deadline := Time.get_ticks_msec() + 35000
                    while (not dragon.dynamics.landed or dragon.landing_elapsed < 12.0) and Time.get_ticks_msec() < deadline:
                        await process_frame
                    rocket.set_physics_process(false)
                    Engine.time_scale = 1.0
                    if not dragon.dynamics.landed or dragon.landing_elapsed < 12.0:
                        return _fail("actual %.0fx physics callbacks did not reach settled landing" % rate)
                    dragon.update_visuals()
                    if not _assert_settled(dragon, "actual %.0fx callbacks" % rate):
                        return
                # Switching cameras while paused must not duplicate or lose
                # the detached canopies when returning to the Dragon view.
                timeline._set_paused(true)
                for camera_key in [KEY_1, KEY_3]:
                    key.keycode = camera_key
                    rocket.camera_rig._input(key)
                    if not dragon._ground_canopies.visible:
                        return _fail("landed canopy disappeared after camera switch while paused")
                    for chute in dragon.parachutes._main:
                        if chute.canopy.visible:
                            return _fail("camera switch showed both original and landed canopies")
                if not _assert_settled(dragon, "camera return while paused"):
                    return
                timeline._set_paused(false)
                rocket.set_physics_process(false)
                var old_frame: Node3D = dragon._ground_frame
                rocket.reset_flight()
                rocket.set_physics_process(false)
                await process_frame
                if is_instance_valid(rocket.dragon_vehicle) or is_instance_valid(old_frame):
                    return _fail("reset left a Dragon or landed canopy frame behind")
    world.queue_free()
    await process_frame
    print("LANDED CHUTES PASSED: 9 nominal trajectories, actual timewarp callbacks and rewind")
    quit(0)
