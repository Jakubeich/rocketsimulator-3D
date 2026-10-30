extends Node3D

## Ground exhaust cloud at the launch mount. Attach this node to the fixed
## launch site, not to the rocket: existing particles stay behind at lift-off.
## update_state() is driven by actual engine thrust and rocket position.
@export var maximum_effect_height := 55.0
@export var maximum_horizontal_distance := 55.0

var _emitters: Array[GPUParticles3D] = []
var _strength := 0.0

func _ready() -> void:
    var texture := _make_smoke_texture()
    var smoke_material := StandardMaterial3D.new()
    smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    smoke_material.vertex_color_use_as_albedo = true
    smoke_material.albedo_texture = texture
    smoke_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    smoke_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

    var quad := QuadMesh.new()
    quad.size = Vector2(6.0, 6.0)
    quad.material = smoke_material
    _emitters.append(_make_emitter("ExhaustCloudLeft", Vector3(-3.0, 0.2, 0.0), Vector3(-1.0, 0.26, 0.13), quad))
    _emitters.append(_make_emitter("ExhaustCloudRight", Vector3(3.0, 0.2, 0.0), Vector3(1.0, 0.26, -0.13), quad))

func update_state(rocket_global_position: Vector3, throttle: float, delta: float) -> void:
    var offset := rocket_global_position - global_position
    var altitude_strength := clampf(1.0 - maxf(offset.y, 0.0) / maxf(maximum_effect_height, 0.1), 0.0, 1.0)
    var horizontal_strength := clampf(1.0 - Vector2(offset.x, offset.z).length() / maxf(maximum_horizontal_distance, 0.1), 0.0, 1.0)
    var target := clampf(throttle, 0.0, 1.0) * altitude_strength * horizontal_strength
    _strength = move_toward(_strength, target, maxf(delta, 0.0) * 2.0)
    for emitter in _emitters:
        # Emission stops when the engines stop, but existing clouds dissipate naturally.
        emitter.amount_ratio = clampf(_strength, 0.0, 1.0)
        emitter.emitting = _strength > 0.02

func _make_emitter(node_name: String, offset: Vector3, direction: Vector3, quad: QuadMesh) -> GPUParticles3D:
    var particles := GPUParticles3D.new()
    particles.name = node_name
    particles.position = offset
    particles.amount = 180
    particles.lifetime = 6.0
    particles.randomness = 0.65
    particles.explosiveness = 0.0
    particles.local_coords = false
    particles.emitting = false
    particles.amount_ratio = 0.0
    particles.visibility_aabb = AABB(Vector3(-150, -35, -150), Vector3(300, 170, 300))
    particles.draw_pass_1 = quad
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var process := ParticleProcessMaterial.new()
    process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    process.emission_box_extents = Vector3(2.3, 1.0, 2.3)
    process.direction = direction.normalized()
    process.spread = 42.0
    process.gravity = Vector3(0.0, 1.8, 0.0)
    process.initial_velocity_min = 7.5
    process.initial_velocity_max = 16.0
    process.damping_min = 1.0
    process.damping_max = 2.2
    process.scale_min = 1.5
    process.scale_max = 3.0
    process.angle_min = -180.0
    process.angle_max = 180.0
    process.angular_velocity_min = -10.0
    process.angular_velocity_max = 10.0
    var scale_curve := Curve.new()
    scale_curve.add_point(Vector2(0.0, 0.30))
    scale_curve.add_point(Vector2(0.15, 0.85))
    scale_curve.add_point(Vector2(1.0, 1.65))
    var scale_texture := CurveTexture.new()
    scale_texture.curve = scale_curve
    process.scale_curve = scale_texture
    var gradient := Gradient.new()
    gradient.set_color(0, Color(0.65, 0.64, 0.61, 0.0))
    gradient.set_color(1, Color(0.77, 0.79, 0.79, 0.0))
    gradient.add_point(0.12, Color(0.65, 0.64, 0.61, 0.75))
    gradient.add_point(0.55, Color(0.83, 0.84, 0.83, 0.62))
    var gradient_texture := GradientTexture1D.new()
    gradient_texture.gradient = gradient
    process.color_ramp = gradient_texture
    particles.process_material = process
    add_child(particles)
    return particles

func _make_smoke_texture() -> ImageTexture:
    # Deterministic soft-edged cloud sprite, so the effect has no external asset.
    const SIZE := 128
    var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
    var noise := FastNoiseLite.new()
    noise.seed = 3521
    noise.frequency = 0.058
    noise.fractal_octaves = 3
    noise.fractal_gain = 0.52
    for y in range(SIZE):
        for x in range(SIZE):
            var dx := (float(x) - 63.5) / 63.5
            var dy := (float(y) - 63.5) / 63.5
            var radius := sqrt(dx * dx + dy * dy)
            var sample := noise.get_noise_2d(float(x), float(y))
            var soft_edge := clampf(1.0 - radius * radius, 0.0, 1.0)
            var alpha := soft_edge * soft_edge * clampf(0.82 + sample * 0.13, 0.6, 1.0)
            var brightness := clampf(0.92 + sample * 0.05, 0.84, 1.0)
            image.set_pixel(x, y, Color(brightness, brightness, brightness, alpha))
    return ImageTexture.create_from_image(image)
