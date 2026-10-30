extends Node3D

signal flight_reset

## Simplified Falcon 9 flight model, using approximate vehicle-scale parameters.
const G0 := 9.80665
const MAX_THRUST := 7605000.0 # Approximate combined sea-level thrust of nine Merlin 1D engines.
const VACUUM_THRUST := 8227000.0
const ISP := 282.0
const VACUUM_ISP := 311.0
const INITIAL_FUEL := 430000.0
const BOOSTER_DRY_MASS := 25600.0
const UPPER_MASS := 123500.0 # Simplified upper stage, propellant and Dragon.
const AXIAL_CD := 0.3
const LATERAL_CD := 1.2
const FRONTAL_AREA := PI * 1.83 * 1.83
const SIDE_AREA := 41.0 * 3.66
const STEER_RATE := 0.28
const MAX_TILT := deg_to_rad(75.0)
const RESERVE_FUEL := 70000.0
const ATTITUDE_MAX_RATE := deg_to_rad(8.0)
const ATTITUDE_ACCELERATION := deg_to_rad(1.8)
const ASCENT_PITCH_MAX := deg_to_rad(55.0)
const SEPARATION_NOZZLE_CLEARANCE := 3.5
const ReturnPilot := preload("res://scripts/booster_return.gd")
const UpperScript := preload("res://scripts/upper_stage.gd")
const Earth := preload("res://scripts/world_physics.gd")
const GridFins := preload("res://scripts/grid_fins.gd")
const DragonVehicle := preload("res://scripts/dragon_vehicle.gd")

var scenario_id := "full_return"
var velocity := Vector3.ZERO
var fuel := INITIAL_FUEL
var commanded_throttle := 1.0
var actual_throttle := 0.0
var engine_on := false
var countdown := -1.0
var left_pad := false
var crashed := false
var landed := false
var flight_time := 0.0
var spawn_position := Vector3.ZERO
var stage_separated := false
var upper_vehicle: Node3D
var dragon_vehicle: Node3D
var dragon_separation_timer := -1.0
var separation_timer := -1.0
var return_pilot: RefCounted
var return_label := ""
var _upper_stage: Node3D
var _dragon_root: Node3D
var _dragon_parent: Node
var _dragon_transform: Transform3D
var _upper_parent: Node
var _upper_transform: Transform3D
var _time_rates := [1.0, 2.0, 5.0, 10.0, 50.0]
var _time_index := 0
var _warning_timer := 0.0
var _pad_hold_time := 0.0
var _pad_abort := ""
var _active_engine_count := 9
var _attitude_rate := 0.0
var _ascent_manual := false
var grid_fins: Node3D

@onready var effects: Node = $EngineEffects
@onready var legs: Node = $LandingLegs
@onready var hud: CanvasLayer = get_node("../FlightHUD")
@onready var smoke: Node = get_node("../LaunchSmoke")
@onready var camera_rig: Node = get_node("../InspectionCamera")

func _ready() -> void:
	grid_fins = GridFins.new()
	grid_fins.name = "GridFins"
	add_child(grid_fins)
	spawn_position = position
	_upper_stage = find_child("STAGE_2 | druhý stupeň", true, false) as Node3D
	if _upper_stage != null:
		_dragon_root = _upper_stage.find_child("Crew Dragon | ROOT", true, false) as Node3D
		if _dragon_root != null:
			_dragon_parent = _dragon_root.get_parent()
			_dragon_transform = _dragon_root.transform
		_upper_parent = _upper_stage.get_parent()
		_upper_transform = _upper_stage.transform
	Engine.time_scale = 1.0
	hud.start_requested.connect(start_countdown)
	_publish_telemetry()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if get_tree().paused and event.keycode not in [KEY_ESCAPE, KEY_F11, KEY_R, KEY_T]:
			return
		match event.keycode:
			KEY_ESCAPE:
				get_tree().paused = false
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
			KEY_F11:
				var mode := DisplayServer.window_get_mode()
				var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
				var settings := ConfigFile.new()
				settings.load("user://rocket_simulator_settings.cfg")
				settings.set_value("display", "fullscreen", not full)
				settings.save("user://rocket_simulator_settings.cfg")
			KEY_SPACE:
				toggle_engine()
			KEY_X:
				cancel_countdown()
			KEY_E:
				if left_pad and not stage_separated and separation_timer < 0.0:
					if position.y >= 20000.0:
						_begin_separation()
					else:
						_warning_timer = 3.0
			KEY_D:
				if is_instance_valid(dragon_vehicle):
					dragon_vehicle.dynamics.start_return()
			KEY_R:
				reset_flight()
			KEY_T:
				var timeline = get_node_or_null("../MissionTimeline")
				if timeline != null:
					timeline.cycle_rate()
				else:
					_time_index = (_time_index + 1) % _time_rates.size()
					Engine.time_scale = _time_rates[_time_index]

func start_countdown() -> void:
	if not left_pad and not crashed and not landed and countdown < 0.0 and not engine_on and fuel > RESERVE_FUEL:
		_pad_hold_time = 0.0
		_pad_abort = ""
		countdown = 10.0
		_publish_telemetry()

func cancel_countdown() -> void:
	if countdown >= 0.0:
		countdown = -1.0
		engine_on = false
		actual_throttle = 0.0
		effects.set_throttle(0.0)
		_publish_telemetry()

func toggle_engine() -> void:
	if crashed or fuel <= 0.0 or stage_separated or separation_timer >= 0.0:
		return
	if countdown >= 0.0:
		return # The mission is already starting; Space must not cancel it.
	elif not left_pad and not engine_on:
		start_countdown()
	else:
		engine_on = not engine_on
		if engine_on and commanded_throttle <= 0.0:
			commanded_throttle = 1.0

func _begin_separation() -> void:
	if _upper_stage == null:
		return
	engine_on = false
	actual_throttle = 0.0
	separation_timer = 2.0
	return_label = "BECO — VYPNUTÍ MOTORŮ"

func _separate_stage() -> void:
	if _upper_stage == null or stage_separated:
		return
	var axis := global_basis.y.normalized()
	upper_vehicle = Node3D.new()
	upper_vehicle.name = "UpperStageVehicle"
	upper_vehicle.set_script(UpperScript)
	get_parent().add_child(upper_vehicle)
	# Both stages are stepped by this controller in the same substeps. A new
	# Godot node does not receive its own physics callback on its creation tick.
	upper_vehicle.set_physics_process(false)
	upper_vehicle.global_transform = _upper_stage.global_transform
	# Separation pushers give the upper stage +2 m/s and an equal/opposite
	# momentum change to the booster, rather than creating momentum.
	upper_vehicle.velocity = velocity + axis * 2.0
	velocity -= axis * (2.0 * UPPER_MASS / (BOOSTER_DRY_MASS + fuel))
	upper_vehicle.thrust_axis = axis
	upper_vehicle.separation_axis = axis
	upper_vehicle.ignition_clearance_met = false
	upper_vehicle.fuel_reserve = 1000.0
	_upper_stage.reparent(upper_vehicle, true)
	upper_vehicle.configure_contact()
	upper_vehicle.attach_exhaust()
	stage_separated = true
	separation_timer = -1.0
	return_pilot = ReturnPilot.new()
	grid_fins.set_deployed(true)
	return_label = "OTOČENÍ STUPNĚ"
	_active_engine_count = 3
	effects.set_engine_count(3)

func _detach_dragon() -> void:
	if not is_instance_valid(upper_vehicle) or not is_instance_valid(_dragon_root) or is_instance_valid(dragon_vehicle):
		return
	var axis := upper_vehicle.global_basis.y.normalized()
	var initial_velocity: Vector3 = upper_vehicle.velocity + axis * 0.5
	dragon_vehicle = DragonVehicle.new()
	dragon_vehicle.name = "CrewDragonVehicle"
	get_parent().add_child(dragon_vehicle)
	dragon_vehicle.set_physics_process(false)
	dragon_vehicle.global_transform = _dragon_root.global_transform
	_dragon_root.reparent(dragon_vehicle, true)
	dragon_vehicle.configure(_dragon_root, initial_velocity)
	upper_vehicle.carries_dragon = false
	# Equal and opposite separation momentum, approximating dry upper mass.
	upper_vehicle.velocity -= axis * (0.5 * 12500.0 / maxf(upper_vehicle.DRY_MASS - 12500.0 + upper_vehicle.fuel, 1.0))
	dragon_separation_timer = -1.0

func _reattach_dragon() -> void:
	if not is_instance_valid(dragon_vehicle):
		return
	dragon_vehicle.prepare_reattach()
	if is_instance_valid(_dragon_root) and is_instance_valid(_dragon_parent):
		_dragon_root.reparent(_dragon_parent, false)
		_dragon_root.transform = _dragon_transform
	dragon_vehicle.queue_free()
	dragon_vehicle = null
	if is_instance_valid(upper_vehicle):
		upper_vehicle.carries_dragon = true
	dragon_separation_timer = -1.0

func reset_flight() -> void:
	_reattach_dragon()
	dragon_separation_timer = -1.0
	if is_instance_valid(upper_vehicle) and is_instance_valid(_upper_stage):
		if is_instance_valid(upper_vehicle.exhaust_fx):
			upper_vehicle.exhaust_fx.clear_visuals()
		_upper_stage.reparent(_upper_parent, false)
		_upper_stage.transform = _upper_transform
		upper_vehicle.queue_free()
	upper_vehicle = null
	stage_separated = false
	separation_timer = -1.0
	return_pilot = null
	return_label = ""
	position = spawn_position
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	fuel = INITIAL_FUEL
	commanded_throttle = 1.0
	actual_throttle = 0.0
	engine_on = false
	countdown = -1.0
	left_pad = false
	crashed = false
	landed = false
	flight_time = 0.0
	_time_index = 0
	_warning_timer = 0.0
	_pad_hold_time = 0.0
	_pad_abort = ""
	_attitude_rate = 0.0
	_ascent_manual = false
	Engine.time_scale = 1.0
	_active_engine_count = 9
	effects.set_engine_count(9)
	effects.set_throttle(0.0)
	legs.reset_legs()
	grid_fins.reset_fins()
	smoke.update_state(global_position, 0.0, 1.0)
	_publish_telemetry()
	flight_reset.emit()

func _physics_process(delta: float) -> void:
	# Cap each integration step so time warp does not sacrifice flight accuracy.
	var substeps := maxi(1, ceili(delta / 0.02))
	var step := delta / substeps
	for index in range(substeps):
		if not crashed and not landed:
			_advance_flight(step)
		if is_instance_valid(dragon_vehicle):
			dragon_vehicle._advance_flight(step)
		if is_instance_valid(upper_vehicle):
			upper_vehicle._advance_flight(step)
			# Coast after SECO before releasing Dragon. Never separate during a burn.
			if upper_vehicle.orbit_target_met and not is_instance_valid(dragon_vehicle):
				if dragon_separation_timer < 0.0:
					dragon_separation_timer = 60.0
				else:
					dragon_separation_timer -= step
					if dragon_separation_timer <= 0.0:
						_detach_dragon()
			# Measure only after both bodies have advanced to the same instant.
			# At orbital speeds even one substep of skew is tens of metres.
			if not upper_vehicle.ignition_clearance_met and _separation_clearance() >= upper_vehicle.SAFE_PLUME_CLEARANCE:
				upper_vehicle.ignition_clearance_met = true
		elif crashed or landed:
			break
	if is_instance_valid(upper_vehicle):
		upper_vehicle.update_exhaust()
	if is_instance_valid(dragon_vehicle):
		dragon_vehicle.update_visuals()
	# Physics callbacks may advance a full accelerated tick after _process has
	# positioned the camera. Refresh following only after all three bodies have
	# reached the same simulation instant, before Godot renders this frame.
	if is_instance_valid(camera_rig):
		camera_rig._process(0.0)
	var per_engine_power := actual_throttle * 9.0 / maxi(_active_engine_count, 1)
	effects.set_throttle(per_engine_power)
	smoke.update_state(global_position, actual_throttle, delta)
	_publish_telemetry()

func _advance_flight(delta: float) -> void:
	_warning_timer = maxf(0.0, _warning_timer - delta)
	if crashed or landed:
		return
	var holding_for_countdown := countdown >= 0.0
	var ignition_ramp := 1.0
	var lateral_correction := Vector3.ZERO
	var requested := 0.0
	var atmosphere: Dictionary = Earth.atmosphere(Earth.altitude(position))
	var vacuum_fraction := 1.0 - clampf(float(atmosphere.pressure) / Earth.SEA_LEVEL_PRESSURE, 0.0, 1.0)
	var available_thrust := lerpf(MAX_THRUST, VACUUM_THRUST, vacuum_fraction)
	var effective_isp := lerpf(ISP, VACUUM_ISP, vacuum_fraction)
	var burn_rate := available_thrust / (effective_isp * G0)

	if stage_separated and return_pilot != null:
		# The vacuum nozzle begins inside the interstage. Coast coaxially until
		# it clears the rim before the booster begins its flip maneuver.
		if _separation_clearance() < SEPARATION_NOZZLE_CLEARANCE:
			return_label = "ODDĚLOVÁNÍ STUPŇŮ"
			engine_on = false
		else:
			var pilot: Dictionary = return_pilot.step(position, velocity, fuel, BOOSTER_DRY_MASS + fuel, delta, basis.y.normalized(), available_thrust)
			requested = pilot.throttle
			var engine_count: int = int(pilot.get("engines", 3))
			if engine_count != _active_engine_count:
				_active_engine_count = engine_count
				effects.set_engine_count(engine_count)
			return_label = pilot.label
			lateral_correction = pilot.lateral_accel
			var local_fin_command: Vector3 = global_basis.inverse() * lateral_correction
			grid_fins.set_steering(Vector2(local_fin_command.x, local_fin_command.z) / 3.0)
			var desired_axis: Vector3 = pilot.direction
			_rotate_toward_axis(desired_axis, delta, Vector3(0.0, 24.0, 0.0))
			engine_on = requested > 0.0 and fuel > 0.0
		if position.y < 1500.0 and velocity.y < 0.0:
			legs.set_deployed(true)
	elif separation_timer >= 0.0:
		separation_timer -= delta
		if separation_timer <= 0.0:
			_separate_stage()
	else:
		var throttle_input := float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
		commanded_throttle = clampf(commanded_throttle + throttle_input * 0.35 * delta, 0.0, 1.0)
		var pitch_input := float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
		var roll_input := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
		if left_pad:
			if absf(pitch_input) > 0.0 or absf(roll_input) > 0.0:
				_ascent_manual = true
			if _ascent_manual:
				var center_before := to_global(Vector3(0.0, 35.0, 0.0))
				rotation.x = clampf(rotation.x + pitch_input * STEER_RATE * delta, -MAX_TILT, MAX_TILT)
				rotation.z = clampf(rotation.z + roll_input * STEER_RATE * delta, -MAX_TILT, MAX_TILT)
				position += center_before - to_global(Vector3(0.0, 35.0, 0.0))
			else:
				var pitch_fraction := smoothstep(15.0, 130.0, flight_time)
				var pitch_angle := ASCENT_PITCH_MAX * pitch_fraction
				_rotate_toward_axis(Vector3(sin(pitch_angle), cos(pitch_angle), 0.0), delta, Vector3(0.0, 35.0, 0.0))
		if holding_for_countdown:
			countdown = maxf(0.0, countdown - delta)
			if countdown <= 3.0:
				engine_on = true
				ignition_ramp = clampf((3.0 - countdown) * 0.4, 0.0, 1.0)
			if countdown <= 0.0:
				countdown = -1.0
				holding_for_countdown = false
				ignition_ramp = 1.0
		requested = commanded_throttle * ignition_ramp if engine_on else 0.0

	var available := fuel / (burn_rate * delta) if delta > 0.0 else 0.0
	actual_throttle = minf(requested, available)
	fuel = maxf(0.0, fuel - burn_rate * actual_throttle * delta)
	if fuel <= 0.0:
		engine_on = false
		countdown = -1.0
	if not left_pad and fuel <= RESERVE_FUEL:
		engine_on = false
		actual_throttle = 0.0
		countdown = -1.0
		_pad_abort = "START ZRUŠEN — NEDOSTATEK PALIVA"

	var altitude := Earth.altitude(position)
	var gravity: Vector3 = Earth.gravity(position)
	var density: float = atmosphere.density
	var axis := basis.y.normalized()
	var mass := BOOSTER_DRY_MASS + fuel + (0.0 if stage_separated else UPPER_MASS)
	var drag: Vector3 = Earth.drag(velocity, axis, density, AXIAL_CD, FRONTAL_AREA, LATERAL_CD, SIDE_AREA)
	var acceleration := axis * (available_thrust * actual_throttle / mass) + gravity + Earth.rotating_frame_acceleration(position, velocity) + drag / mass + lateral_correction

	if holding_for_countdown:
		velocity = Vector3.ZERO
		position = spawn_position
	elif not left_pad and acceleration.y <= 0.0:
		velocity = Vector3.ZERO
		position = spawn_position
		if engine_on:
			_pad_hold_time += delta
			if _pad_hold_time >= 10.0:
				engine_on = false
				actual_throttle = 0.0
				_pad_abort = "START ZRUŠEN — NEDOSTATEČNÝ TAH"
	else:
		_pad_hold_time = 0.0
		velocity += acceleration * delta
		position += velocity * delta
		if position.y > spawn_position.y + 0.1:
			left_pad = true
		if left_pad:
			flight_time += delta
			var ground := _ground_height(position)
			if position.y <= ground:
				position.y = ground
				var upright := basis.y.normalized().dot(Vector3.UP)
				var horizontal_speed := Vector2(velocity.x, velocity.z).length()
				var safe_attitude := upright >= cos(deg_to_rad(15.0))
				var gear_ready: bool = stage_separated and float(legs._amount) >= 0.9
				crashed = velocity.y < -5.0 or horizontal_speed > 3.0 or not safe_attitude or not gear_ready
				landed = not crashed
				velocity = Vector3.ZERO
				engine_on = false
				actual_throttle = 0.0
	if left_pad and not stage_separated and separation_timer < 0.0 and fuel <= RESERVE_FUEL:
		_begin_separation()

func _separation_clearance() -> float:
	if not is_instance_valid(upper_vehicle) or not is_instance_valid(_upper_parent):
		return 0.0
	var interface_parent := _upper_parent as Node3D
	if interface_parent == null:
		return 0.0
	var booster_interface: Vector3 = interface_parent.to_global(_upper_transform.origin)
	return (upper_vehicle.global_position - booster_interface).dot(upper_vehicle.separation_axis)

func _rotate_toward_axis(direction: Vector3, delta: float, pivot: Vector3) -> void:
	if direction.length_squared() < 0.000001 or delta <= 0.0:
		return
	var target := Quaternion(Vector3.UP, direction.normalized())
	var angle := absf(quaternion.angle_to(target))
	if angle < 0.00001:
		_attitude_rate = move_toward(_attitude_rate, 0.0, ATTITUDE_ACCELERATION * delta)
		return
	var desired_rate := minf(ATTITUDE_MAX_RATE, sqrt(2.0 * ATTITUDE_ACCELERATION * angle))
	_attitude_rate = move_toward(_attitude_rate, desired_rate, ATTITUDE_ACCELERATION * delta)
	var center_before := to_global(pivot)
	quaternion = quaternion.slerp(target, minf(1.0, _attitude_rate * delta / angle)).normalized()
	position += center_before - to_global(pivot)

func _ground_height(pos: Vector3) -> float:
	# Temporary height-only contact, to be replaced with physical collision shapes.
	if absf(pos.x) < 18.0 and absf(pos.z) < 18.0:
		return spawn_position.y
	if Vector2(pos.x + 2000.0, pos.z).length() < 43.0:
		return -5.54
	# Approximate the Earth's curvature away from the locally flat launch site.
	var horizontal_squared := float(pos.x) * pos.x + float(pos.z) * pos.z
	return sqrt(maxf(Earth.EARTH_RADIUS * Earth.EARTH_RADIUS - horizontal_squared, 0.0)) - Earth.EARTH_RADIUS - 6.15

func _publish_telemetry() -> void:
	var can_start := not left_pad and countdown < 0.0 and not engine_on and not crashed and not landed and fuel > RESERVE_FUEL
	if is_instance_valid(camera_rig) and camera_rig._follow_dragon and is_instance_valid(dragon_vehicle):
		var d = dragon_vehicle.dynamics
		var state_labels := {"ORBIT": "SAMOSTATNÝ LET · D: NÁVRAT", "DEORBIT": "BRZDICÍ ZÁŽEH DRACO", "ENTRY": "NÁVRAT ATMOSFÉROU", "DROGUE": "BRZDICÍ PADÁKY", "MAIN": "HLAVNÍ PADÁKY", "LANDED": "DOSÁHL POVRCHU · HERNÍ PŘISTÁNÍ", "IMPACT": "TVRDÝ DOPAD"}
		hud.update_telemetry({
			"vehicle_label": "CREW DRAGON", "view_label": "KAMERA 3 · CREW DRAGON",
			"altitude": d.altitude(), "speed": d.velocity().length(),
			"vertical_speed": d.velocity().dot(d.up()), "throttle": 1.0 if d.phase == "DEORBIT" else 0.0,
			"fuel_label": "PRŮBĚH ZÁŽEHU",
			"fuel_fraction": clampf(d.phase_time / d.DEORBIT_SECONDS, 0.0, 1.0) if d.phase == "DEORBIT" else (0.0 if d.phase == "ORBIT" else 1.0),
			"engine_label": "DRACO", "engine_on": d.phase == "DEORBIT", "engines_active": 1 if d.phase == "DEORBIT" else 0, "engines_total": 1,
			"status": state_labels.get(d.phase, d.phase), "countdown": countdown, "ready_to_start": can_start, "scenario_id": scenario_id,
		})
		return
	if is_instance_valid(camera_rig) and camera_rig._follow_upper:
		# Until separation, the upper stage and Dragon move with the booster.
		# The second stage has its own unused propellant and an inactive engine.
		var detached := is_instance_valid(upper_vehicle)
		var upper_position: Vector3 = upper_vehicle.global_position if detached else (_upper_stage.global_position if is_instance_valid(_upper_stage) else global_position)
		var upper_velocity: Vector3 = upper_vehicle.velocity if detached else velocity
		var upper_fuel: float = upper_vehicle.fuel if detached else UpperScript.INITIAL_FUEL
		var upper_throttle: float = upper_vehicle.actual_throttle if detached else 0.0
		var dragon_view: bool = camera_rig._follow_dragon
		var displayed_position := _dragon_root.global_position if dragon_view and is_instance_valid(_dragon_root) else upper_position
		var upper_status := "SPOJEN S PRVNÍM STUPNĚM"
		if detached:
			upper_status = "LET BEZ TAHU"
			if upper_vehicle.impacted:
				upper_status = "DOPAD HORNÍHO STUPNĚ"
			elif not upper_vehicle.ignition_clearance_met or upper_vehicle.elapsed < upper_vehicle.IGNITION_DELAY:
				upper_status = "VZDALOVÁNÍ STUPŇŮ"
			elif upper_throttle > 0.0:
				upper_status = "ZÁŽEH DRUHÉHO STUPNĚ"
			elif upper_vehicle.orbit_target_met:
				upper_status = "SECO · OBĚŽNÁ DRÁHA"
			elif upper_fuel <= upper_vehicle.fuel_reserve:
				upper_status = "SECO · SUBORBITÁLNÍ LET"
		var upper_data := {
			"vehicle_label": "CREW DRAGON" if dragon_view else ("2. STUPEŇ" if is_instance_valid(dragon_vehicle) else "2. STUPEŇ + DRAGON"),
			"view_label": "KAMERA 3 · SPOJEN S 2. STUPNĚM" if dragon_view else "KAMERA 2 · HORNÍ STUPEŇ",
			"altitude": Earth.altitude(displayed_position),
			"speed": upper_velocity.length(),
			"vertical_speed": upper_velocity.dot(-Earth.gravity(displayed_position).normalized()),
			"throttle": upper_throttle,
			"fuel_label": "PALIVO 2. STUPNĚ",
			"fuel_amount": upper_fuel,
			"fuel_fraction": upper_fuel / UpperScript.INITIAL_FUEL,
			"engine_label": "MOTOR 2. STUPNĚ",
			"engine_on": upper_throttle > 0.0,
			"engines_active": 1 if upper_throttle > 0.0 else 0,
			"engines_total": 1,
			"status": upper_status,
			"countdown": countdown,
			"ready_to_start": can_start,
			"scenario_id": scenario_id,
		}
		if detached and not upper_vehicle.impacted and upper_vehicle.ignition_started_at >= 0.0 and upper_throttle <= 0.0:
			var orbit: Dictionary = upper_vehicle.orbital_elements()
			upper_data["apoapsis"] = orbit.apoapsis
			upper_data["periapsis"] = orbit.periapsis
		hud.update_telemetry(upper_data)
		return
	var label := "NA RAMPĚ"
	if crashed:
		label = "HAVÁRIE — R: RESET"
	elif landed:
		if Vector2(position.x + 2000.0, position.z).length() < 43.0:
			label = "PŘISTÁNÍ NA LZ-1"
		else:
			label = "PŘISTÁNÍ MIMO LZ-1"
	elif stage_separated or separation_timer >= 0.0:
		label = return_label
	elif not left_pad and not _pad_abort.is_empty():
		label = _pad_abort
	elif _warning_timer > 0.0:
		label = "ODDĚLENÍ RUČNĚ AŽ OD 20 KM"
	elif countdown >= 0.0:
		label = "ODPOČET T−%04.1f s" % countdown
	elif left_pad:
		label = "RUČNÍ ŘÍZENÍ" if _ascent_manual else "AUTOMATICKÝ VÝSTUP"
	elif fuel <= 0.0:
		label = "PALIVO VYČERPÁNO"
	if get_tree().paused:
		label += "  |  PAUZA"
	elif _time_index > 0:
		label += "  |  %.0f×" % _time_rates[_time_index]
	hud.update_telemetry({
		"vehicle_label": "1. STUPEŇ" if stage_separated else "FALCON 9",
		"view_label": "KAMERA 5 · PŘEHLED ZEMĚ" if camera_rig._follow_planet else ("KAMERA 1 · PRVNÍ STUPEŇ" if camera_rig._follow_rocket else "KAMERA 4 · LZ-1 / 1. STUPEŇ"),
		"altitude": Earth.altitude(position),
		"speed": velocity.length(),
		"vertical_speed": velocity.dot(-Earth.gravity(position).normalized()),
		"throttle": actual_throttle,
		"commanded_throttle": commanded_throttle,
		"fuel_fraction": fuel / INITIAL_FUEL,
		"fuel_amount": fuel,
		"fuel_label": "PALIVO 1. STUPNĚ",
		"engine_on": engine_on and actual_throttle > 0.0,
		"engines_active": _active_engine_count if engine_on and actual_throttle > 0.0 else 0,
		"engines_total": 9,
		"status": label,
		"flight_time": flight_time,
		"countdown": countdown,
		"ready_to_start": can_start,
		"scenario_id": scenario_id,
	})
