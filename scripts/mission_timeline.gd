extends Node

## Bounded flight-state history. Rewinding restores simulation state, rather
## than attempting to run the physics engine backwards.
const SAMPLE_INTERVAL := 0.25
const MAX_SNAPSHOTS := 3601 # approximately 15 minutes at normal sampling
const JUMP_SECONDS := 10.0
const RATES := [1.0, 2.0, 5.0, 10.0, 50.0]
const ReturnPilot := preload("res://scripts/booster_return.gd")

var rocket: Node3D
var hud: CanvasLayer
var camera: Node3D
var rate := 1.0
var elapsed := 0.0
var _history: Array[Dictionary] = []
var _cursor := -1
var _since_sample := 0.0
var _fast_remaining := 0.0
var _before_fast_rate := 1.0

func configure(vehicle: Node3D, flight_hud: CanvasLayer, camera_rig: Node3D) -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    rocket = vehicle
    hud = flight_hud
    camera = camera_rig
    # Input and the camera remain available while the simulation tree is paused.
    rocket.process_mode = Node.PROCESS_MODE_ALWAYS
    rocket.effects.process_mode = Node.PROCESS_MODE_PAUSABLE
    rocket.legs.process_mode = Node.PROCESS_MODE_PAUSABLE
    camera.process_mode = Node.PROCESS_MODE_ALWAYS
    hud.time_action_requested.connect(_on_action)
    hud.time_rate_requested.connect(_on_rate_requested)
    rocket.flight_reset.connect(_on_reset)
    _capture()
    _update_hud()

func _exit_tree() -> void:
    get_tree().paused = false
    Engine.time_scale = 1.0

func _process(delta: float) -> void:
    if not is_instance_valid(rocket) or get_tree().paused:
        return
    elapsed += maxf(delta, 0.0)
    _since_sample += maxf(delta, 0.0)
    if _since_sample >= SAMPLE_INTERVAL:
        _capture()
        _since_sample = 0.0
    if _fast_remaining > 0.0:
        _fast_remaining -= maxf(delta, 0.0)
        if _fast_remaining <= 0.0:
            _fast_remaining = 0.0
            _capture()
            _set_paused(true)
            set_rate(_before_fast_rate)
    _update_hud()

func set_rate(value: float) -> void:
    if value not in RATES:
        return
    rate = value
    rocket._time_index = RATES.find(rate)
    Engine.time_scale = rate
    _update_hud()

func cycle_rate() -> void:
    _fast_remaining = 0.0
    set_rate(RATES[(RATES.find(rate) + 1) % RATES.size()])

func _on_rate_requested(value: float) -> void:
    _fast_remaining = 0.0
    set_rate(value)

func _on_action(action: String) -> void:
    match action:
        "pause":
            _cancel_fast_forward()
            if not get_tree().paused:
                _capture()
            _set_paused(not get_tree().paused)
        "back":
            _cancel_fast_forward()
            if not get_tree().paused:
                _capture()
            _set_paused(true)
            _seek(elapsed - JUMP_SECONDS)
        "forward":
            _cancel_fast_forward()
            if _cursor < _history.size() - 1:
                _set_paused(true)
                _seek(elapsed + JUMP_SECONDS)
            else:
                # At the live edge no future has been simulated yet: run the
                # actual simulation at 10x until ten simulated seconds pass.
                _before_fast_rate = rate
                _fast_remaining = JUMP_SECONDS
                set_rate(10.0)
                _set_paused(false)
    _update_hud()

func _cancel_fast_forward() -> void:
    if _fast_remaining > 0.0:
        _fast_remaining = 0.0
        set_rate(_before_fast_rate)

func _set_paused(paused: bool) -> void:
    if not paused and _cursor >= 0 and _cursor < _history.size() - 1:
        _history.resize(_cursor + 1) # resumed play creates a new timeline
    get_tree().paused = paused
    # The rocket is always-processing for input, but its physics must stop.
    rocket.set_physics_process(not paused)
    rocket._publish_telemetry()
    _update_hud()

func _on_reset() -> void:
    _fast_remaining = 0.0
    get_tree().paused = false
    rocket.set_physics_process(true)
    elapsed = 0.0
    _since_sample = 0.0
    _history.clear()
    _cursor = -1
    set_rate(1.0)
    _capture()
    _update_hud()

func _capture() -> void:
    if not is_instance_valid(rocket):
        return
    if _cursor < _history.size() - 1:
        _history.resize(_cursor + 1)
    var data := {
        "time": elapsed,
        "transform": rocket.transform,
        "velocity": rocket.velocity,
        "fuel": rocket.fuel,
        "commanded_throttle": rocket.commanded_throttle,
        "actual_throttle": rocket.actual_throttle,
        "engine_on": rocket.engine_on,
        "countdown": rocket.countdown,
        "left_pad": rocket.left_pad,
        "crashed": rocket.crashed,
        "landed": rocket.landed,
        "flight_time": rocket.flight_time,
        "stage_separated": rocket.stage_separated,
        "separation_timer": rocket.separation_timer,
        "dragon_separation_timer": rocket.dragon_separation_timer,
        "return_label": rocket.return_label,
        "warning_timer": rocket._warning_timer,
        "pad_hold_time": rocket._pad_hold_time,
        "pad_abort": rocket._pad_abort,
        "engine_count": rocket._active_engine_count,
        "attitude_rate": rocket._attitude_rate,
        "ascent_manual": rocket._ascent_manual,
        "leg_amount": rocket.legs._amount,
        "leg_target": rocket.legs._target,
        "grid_fins": rocket.grid_fins.get_state(),
        "visible_throttle": rocket.effects._visible_throttle,
    }
    if rocket.return_pilot != null:
        data["pilot"] = {"phase": rocket.return_pilot.phase, "phase_time": rocket.return_pilot.phase_time, "landing_engines": rocket.return_pilot._landing_engines, "boost_direction": rocket.return_pilot._boost_direction}
    if is_instance_valid(rocket.upper_vehicle):
        var upper = rocket.upper_vehicle
        data["upper"] = {
            "transform": upper.global_transform, "velocity": upper.velocity,
            "position_residual": upper.position_residual,
            "thrust_axis": upper.thrust_axis, "fuel": upper.fuel,
            "fuel_reserve": upper.fuel_reserve, "elapsed": upper.elapsed,
            "actual_throttle": upper.actual_throttle, "active": upper.active,
            "impacted": upper.impacted, "impact_speed": upper.impact_speed,
            "contact_clearance": upper.contact_clearance,
            "carries_dragon": upper.carries_dragon,
            "guidance_start_pitch": upper.guidance_start_pitch,
            "guidance_heading": upper.guidance_heading,
            "angular_speed": upper.angular_speed,
            "orbit_target_met": upper.orbit_target_met,
            "separation_axis": upper.separation_axis,
            "ignition_clearance_met": upper.ignition_clearance_met,
            "ignition_started_at": upper.ignition_started_at,
            "exhaust_power": upper.exhaust_fx._power if is_instance_valid(upper.exhaust_fx) else 0.0,
            "exhaust_target": upper.exhaust_fx._target if is_instance_valid(upper.exhaust_fx) else 0.0,
        }
    if is_instance_valid(rocket.dragon_vehicle):
        var dragon = rocket.dragon_vehicle
        data["dragon"] = {
            "transform": dragon.global_transform,
            "dynamics": dragon.dynamics.get_state(),
            "landing_elapsed": dragon.landing_elapsed,
        }
    if _cursor >= 0 and is_equal_approx(float(_history[_cursor].time), elapsed):
        _history[_cursor] = data
    else:
        _history.append(data)
        if _history.size() > MAX_SNAPSHOTS:
            _history.pop_front()
        _cursor = _history.size() - 1

func _seek(requested: float) -> void:
    if _history.is_empty():
        return
    var target := clampf(requested, float(_history[0].time), float(_history[-1].time))
    var nearest := 0
    var distance := INF
    for index in _history.size():
        var difference := absf(float(_history[index].time) - target)
        if difference < distance:
            nearest = index
            distance = difference
    _cursor = nearest
    _restore(_history[_cursor])
    _update_hud()

func _restore(data: Dictionary) -> void:
    var wants_upper := bool(data.stage_separated) and data.has("upper")
    var wants_dragon := wants_upper and data.has("dragon")
    # The capsule is a descendant of the stage in the assembled model. Put it
    # back before removing that stage, otherwise rewinding past both separation
    # events would destroy or orphan its imported geometry.
    if is_instance_valid(rocket.dragon_vehicle) and not wants_dragon:
        rocket._reattach_dragon()
    if not wants_upper and is_instance_valid(rocket.upper_vehicle):
        if is_instance_valid(rocket.upper_vehicle.exhaust_fx):
            rocket.upper_vehicle.exhaust_fx.clear_visuals()
        rocket._upper_stage.reparent(rocket._upper_parent, false)
        rocket._upper_stage.transform = rocket._upper_transform
        rocket.upper_vehicle.queue_free()
        rocket.upper_vehicle = null
        rocket.stage_separated = false
    elif wants_upper and not is_instance_valid(rocket.upper_vehicle):
        rocket.stage_separated = false
        rocket._separate_stage()
    # Recreate the same hierarchy first; reapply all velocities and transforms
    # below because the separation routine itself adds a small impulse.
    if wants_dragon and not is_instance_valid(rocket.dragon_vehicle):
        rocket._detach_dragon()
    rocket.transform = data.transform
    rocket.velocity = data.velocity
    rocket.fuel = data.fuel
    rocket.commanded_throttle = data.commanded_throttle
    rocket.actual_throttle = data.actual_throttle
    rocket.engine_on = data.engine_on
    rocket.countdown = data.countdown
    rocket.left_pad = data.left_pad
    rocket.crashed = data.crashed
    rocket.landed = data.landed
    rocket.flight_time = data.flight_time
    rocket.stage_separated = data.stage_separated
    rocket.separation_timer = data.separation_timer
    rocket.dragon_separation_timer = data.dragon_separation_timer
    rocket.return_label = data.return_label
    rocket._warning_timer = data.warning_timer
    rocket._pad_hold_time = data.pad_hold_time
    rocket._pad_abort = data.pad_abort
    rocket._active_engine_count = data.engine_count
    rocket._attitude_rate = data.attitude_rate
    rocket._ascent_manual = data.ascent_manual
    if data.has("pilot"):
        if rocket.return_pilot == null:
            rocket.return_pilot = ReturnPilot.new()
        rocket.return_pilot.phase = data.pilot.phase
        rocket.return_pilot.phase_time = data.pilot.phase_time
        rocket.return_pilot._landing_engines = data.pilot.landing_engines
        rocket.return_pilot._boost_direction = data.pilot.boost_direction
    else:
        rocket.return_pilot = null
    if wants_upper:
        var upper = rocket.upper_vehicle
        var state: Dictionary = data.upper
        upper.global_transform = state.transform
        upper.position_residual = state.get("position_residual", Vector3.ZERO)
        upper._last_integrated_position = upper.global_position
        upper.velocity = state.velocity
        upper.thrust_axis = state.thrust_axis
        upper.fuel = state.fuel
        upper.fuel_reserve = state.fuel_reserve
        upper.elapsed = state.elapsed
        upper.actual_throttle = state.actual_throttle
        upper.active = state.active
        upper.impacted = state.impacted
        upper.impact_speed = state.impact_speed
        upper.contact_clearance = state.contact_clearance
        upper.carries_dragon = state.carries_dragon
        upper.guidance_start_pitch = state.guidance_start_pitch
        upper.guidance_heading = state.guidance_heading
        upper.angular_speed = state.angular_speed
        upper.orbit_target_met = state.orbit_target_met
        upper.separation_axis = state.separation_axis
        upper.ignition_clearance_met = state.ignition_clearance_met
        upper.ignition_started_at = state.ignition_started_at
        if is_instance_valid(upper.exhaust_fx):
            upper.exhaust_fx.restore_visual_state(state.exhaust_power, state.exhaust_target)
    if wants_dragon and is_instance_valid(rocket.dragon_vehicle):
        var dragon = rocket.dragon_vehicle
        var dragon_state: Dictionary = data.dragon
        dragon.global_transform = dragon_state.transform
        dragon.dynamics.set_state(dragon_state.dynamics)
        dragon.landing_elapsed = float(dragon_state.landing_elapsed)
        dragon.update_visuals()
    rocket.legs._amount = data.leg_amount
    rocket.legs._target = data.leg_target
    rocket.legs._render_legs()
    rocket.grid_fins.set_state(data.grid_fins)
    rocket.effects.set_engine_count(data.engine_count)
    rocket.effects.set_throttle(rocket.actual_throttle * 9.0 / maxi(data.engine_count, 1))
    rocket.effects._visible_throttle = data.visible_throttle
    rocket.effects._process(0.0)
    # GPU particle histories cannot be rewound; clear stale clouds and let
    # the emitter rebuild from the restored current thrust.
    for emitter in rocket.smoke._emitters:
        emitter.restart()
    rocket.smoke._strength = 0.0
    rocket.smoke.update_state(rocket.global_position, rocket.actual_throttle, 1.0)
    elapsed = float(data.time)
    _since_sample = 0.0
    camera._process(0.0)
    rocket._publish_telemetry()

func _update_hud() -> void:
    if is_instance_valid(hud):
        hud.update_time_controls(elapsed, rate, get_tree().paused, _cursor > 0, true)
