extends CanvasLayer

signal start_requested
signal time_action_requested(action: String)
signal time_rate_requested(rate: float)
## Lightweight flight display. Update with values in metres, m/s and 0–1 fractions.

var _title_value: Label
var _height_value: Label
var _speed_value: Label
var _vertical_speed_value: Label
var _throttle_value: Label
var _fuel_value: Label
var _fuel_label: Label
var _apoapsis_value: Label
var _periapsis_value: Label
var _engine_value: Label
var _status_value: Label
var _fuel_bar: ProgressBar
var _throttle_bar: ProgressBar
var _scenario_value: Label
var _view_value: Label
var _countdown_panel: PanelContainer
var _countdown_value: Label
var _countdown_label: Label
var _start_button: Button
var _latest := {}
var _help_panel: Control
var _help_toggle: Button
var _help_open := true
var _help_tween: Tween
var _time_panel: PanelContainer
var _time_status: Label
var _time_pause: Button
var _time_back: Button
var _time_forward: Button
var _time_rates: Dictionary = {}

const TEXT := Color(0.91, 0.96, 0.98)
const MUTED := Color(0.56, 0.66, 0.71)
const CYAN := Color(0.34, 0.86, 0.92)
const AMBER := Color(1.0, 0.73, 0.35)

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 10
    var surface := Control.new()
    surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(surface)

    var telemetry := PanelContainer.new()
    telemetry.name = "FlightTelemetry"
    telemetry.position = Vector2(16, 16)
    telemetry.custom_minimum_size = Vector2(216, 0)
    telemetry.add_theme_stylebox_override("panel", _panel_style())
    surface.add_child(telemetry)
    var inset := _inset(13, 11)
    telemetry.add_child(inset)
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 5)
    inset.add_child(stack)

    _title_value = _label("FALCON 9", 15, TEXT)
    stack.add_child(_title_value)
    _scenario_value = _label("FULL RETURN · LETOVÁ TELEMETRIE", 9, CYAN)
    stack.add_child(_scenario_value)
    _view_value = _label("KAMERA 1 · PRVNÍ STUPEŇ", 9, MUTED)
    stack.add_child(_view_value)
    var rule := ColorRect.new()
    rule.color = Color(0.30, 0.65, 0.70, 0.40)
    rule.custom_minimum_size = Vector2(0, 1)
    stack.add_child(rule)
    _height_value = _metric(stack, "VÝŠKA", "0 m")
    _speed_value = _metric(stack, "RYCHLOST", "0 m/s")
    _vertical_speed_value = _metric(stack, "SVISLÁ RYCHLOST", "0 m/s")
    _throttle_value = _metric(stack, "TAH", "0 %")
    _throttle_bar = _progress(stack, CYAN)
    _fuel_value = _metric(stack, "PALIVO", "100 %")
    _fuel_label = _fuel_value.get_parent().get_child(0) as Label
    _fuel_bar = _progress(stack, Color(0.93, 0.73, 0.39))
    _apoapsis_value = _metric(stack, "APOGEUM", "—")
    _periapsis_value = _metric(stack, "PERIGEUM", "—")
    _apoapsis_value.get_parent().visible = false
    _periapsis_value.get_parent().visible = false
    _engine_value = _label("MOTORY VYPNUTÉ", 10, MUTED)
    stack.add_child(_engine_value)
    _status_value = _label("NA RAMPĚ", 10, TEXT)
    _status_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    stack.add_child(_status_value)

    var controls := PanelContainer.new()
    _help_panel = controls
    controls.name = "FlightControls"
    controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    controls.offset_left = 16
    controls.offset_top = -124
    controls.offset_right = 374
    controls.offset_bottom = -16
    controls.add_theme_stylebox_override("panel", _panel_style())
    surface.add_child(controls)
    var help_inset := _inset(12, 9)
    controls.add_child(help_inset)
    var help_stack := VBoxContainer.new()
    help_stack.add_theme_constant_override("separation", 2)
    help_inset.add_child(help_stack)
    help_stack.add_child(_label("OVLÁDÁNÍ LETU", 9, CYAN))
    var help := _label("MEZERNÍK  start / motory    X  zrušit odpočet\nW / S  tah    ŠIPKY  ruční náklon    E  oddělení\nD  zahájit návrat Dragonu po oddělení\nR  reset    T  rychlost času    1–5  kamery\nF11  celá obrazovka    ESC  menu", 10, TEXT)
    help_stack.add_child(help)

    _countdown_panel = PanelContainer.new()
    _countdown_panel.name = "LaunchCountdown"
    _countdown_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    _countdown_panel.offset_left = -100
    _countdown_panel.offset_right = 100
    _countdown_panel.offset_top = 16
    _countdown_panel.offset_bottom = 75
    _countdown_panel.add_theme_stylebox_override("panel", _panel_style())
    surface.add_child(_countdown_panel)
    var countdown_inset := _inset(14, 7)
    _countdown_panel.add_child(countdown_inset)
    var countdown_stack := VBoxContainer.new()
    countdown_inset.add_child(countdown_stack)
    _countdown_label = _label("ODPOČET KE STARTU", 9, CYAN)
    _countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    countdown_stack.add_child(_countdown_label)
    _countdown_value = _label("T−10.0", 22, TEXT)
    _countdown_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    countdown_stack.add_child(_countdown_value)

    _ignore_mouse_recursive(surface)
    _help_toggle = _small_button("‹")
    _help_toggle.name = "ToggleHelp"
    _help_toggle.tooltip_text = "Skrýt ovládání"
    _help_toggle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    _help_toggle.offset_top = -124
    _help_toggle.offset_bottom = -92
    _help_toggle.pressed.connect(_toggle_help)
    surface.add_child(_help_toggle)

    _build_time_panel(surface)
    _start_button = Button.new()
    _start_button.name = "StartCountdown"
    _start_button.text = "SPUSTIT ODPOČET  ·  MEZERNÍK"
    _start_button.focus_mode = Control.FOCUS_NONE
    _start_button.mouse_filter = Control.MOUSE_FILTER_STOP
    _start_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
    _start_button.offset_left = -236
    _start_button.offset_right = -16
    _start_button.offset_top = -55
    _start_button.offset_bottom = -16
    _start_button.add_theme_font_size_override("font_size", 10)
    _start_button.add_theme_color_override("font_color", TEXT)
    var button_normal := _panel_style()
    button_normal.bg_color = Color(0.035, 0.22, 0.26, 0.94)
    button_normal.border_color = CYAN
    var button_hover := button_normal.duplicate() as StyleBoxFlat
    button_hover.bg_color = Color(0.06, 0.34, 0.38, 0.98)
    _start_button.add_theme_stylebox_override("normal", button_normal)
    _start_button.add_theme_stylebox_override("hover", button_hover)
    _start_button.add_theme_stylebox_override("pressed", button_hover)
    _start_button.pressed.connect(func(): start_requested.emit())
    surface.add_child(_start_button)
    surface.resized.connect(_adapt_layout.bind(surface, controls))
    _adapt_layout(surface, controls)
    update_telemetry(_latest)

func update_telemetry(values: Dictionary) -> void:
    _latest = values.duplicate()
    if not is_instance_valid(_height_value):
        return
    var altitude := float(values.get("altitude", 0.0))
    var speed := float(values.get("speed", 0.0))
    var throttle := clampf(float(values.get("throttle", 0.0)), 0.0, 1.0)
    var fuel := clampf(float(values.get("fuel_fraction", 1.0)), 0.0, 1.0)
    var engine_on := bool(values.get("engine_on", false))
    var countdown := float(values.get("countdown", -1.0))
    _title_value.text = str(values.get("vehicle_label", "FALCON 9"))
    _view_value.text = str(values.get("view_label", "KAMERA 1 · PRVNÍ STUPEŇ"))
    _height_value.text = "%.0f m" % altitude
    _speed_value.text = "%.1f m/s" % speed
    _vertical_speed_value.text = "%+.1f m/s" % float(values.get("vertical_speed", 0.0))
    _throttle_value.text = "%.0f %%" % (throttle * 100.0)
    _fuel_label.text = str(values.get("fuel_label", "PALIVO"))
    _fuel_value.text = "%.0f %% · %.0f kg" % [fuel * 100.0, float(values.get("fuel_amount", 0.0))] if values.has("fuel_amount") else "%.0f %%" % (fuel * 100.0)
    _throttle_bar.value = throttle * 100.0
    _fuel_bar.value = fuel * 100.0
    var show_orbit := values.has("apoapsis") and values.has("periapsis")
    _apoapsis_value.get_parent().visible = show_orbit
    _periapsis_value.get_parent().visible = show_orbit
    if show_orbit:
        var apoapsis := float(values.apoapsis)
        var periapsis := float(values.periapsis)
        _apoapsis_value.text = "%.0f km" % (apoapsis / 1000.0) if is_finite(apoapsis) else "ÚNIKOVÁ DRÁHA"
        _periapsis_value.text = "%.0f km" % (periapsis / 1000.0) if periapsis >= 0.0 else "POD POVRCHEM"
    var engine_label := str(values.get("engine_label", "MOTORY"))
    if engine_on:
        _engine_value.text = "%s V CHODU  %d/%d" % [engine_label, int(values.get("engines_active", 0)), int(values.get("engines_total", 9))]
    else:
        _engine_value.text = "%s VYPNUT%s" % [engine_label, "" if values.has("engine_label") else "É"]
    _engine_value.add_theme_color_override("font_color", AMBER if engine_on else MUTED)
    _status_value.text = str(values.get("status", "NA RAMPĚ"))
    _scenario_value.text = ("ISS MISSION" if values.get("scenario_id", "full_return") == "iss_mission" else "FULL RETURN") + " · LETOVÁ TELEMETRIE"
    _countdown_panel.visible = countdown >= 0.0
    if countdown >= 0.0:
        _countdown_value.text = "T−%04.1f" % countdown
        _countdown_label.text = "ZÁŽEH MOTORŮ" if countdown <= 3.0 else "ODPOČET KE STARTU"
    _start_button.visible = bool(values.get("ready_to_start", true))

func _metric(parent: VBoxContainer, title: String, initial: String) -> Label:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var name_label := _label(title, 10, MUTED)
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(name_label)
    var value := _label(initial, 11, TEXT)
    value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    row.add_child(value)
    return value

func _progress(parent: VBoxContainer, color: Color) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.custom_minimum_size = Vector2(0, 3)
    bar.show_percentage = false
    bar.max_value = 100.0
    var background := StyleBoxFlat.new()
    background.bg_color = Color(0.16, 0.23, 0.27, 0.85)
    background.set_corner_radius_all(2)
    var fill := StyleBoxFlat.new()
    fill.bg_color = color
    fill.set_corner_radius_all(2)
    bar.add_theme_stylebox_override("background", background)
    bar.add_theme_stylebox_override("fill", fill)
    parent.add_child(bar)
    return bar

func _label(text: String, size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    return label

func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.055, 0.075, 0.86)
    style.border_color = Color(0.26, 0.46, 0.51, 0.55)
    style.set_border_width_all(1)
    style.set_corner_radius_all(5)
    return style

func _inset(horizontal: int, vertical: int) -> MarginContainer:
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", horizontal)
    margin.add_theme_constant_override("margin_right", horizontal)
    margin.add_theme_constant_override("margin_top", vertical)
    margin.add_theme_constant_override("margin_bottom", vertical)
    return margin

func _ignore_mouse_recursive(node: Node) -> void:
    if node is Control:
        node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    for child in node.get_children():
        _ignore_mouse_recursive(child)

func _adapt_layout(surface: Control, controls: Control) -> void:
    # Keep the handle reachable on narrow windows even when the drawer is shut.
    var drawer_width := minf(358.0, maxf(220.0, surface.size.x - 44.0))
    controls.offset_left = 16.0 if _help_open else -drawer_width
    controls.offset_right = controls.offset_left + drawer_width
    _help_toggle.offset_left = controls.offset_right
    _help_toggle.offset_right = controls.offset_right + 26.0
    # On narrow displays, avoid overlapping the telemetry card during countdown.
    if surface.size.x < 680.0:
        _countdown_panel.offset_left = -100.0 + maxf(0.0, 332.0 - surface.size.x * 0.5)
        _countdown_panel.offset_right = _countdown_panel.offset_left + 200.0
    else:
        _countdown_panel.offset_left = -100.0
        _countdown_panel.offset_right = 100.0
    _countdown_panel.offset_top = 94.0 if surface.size.x < 800.0 else 16.0
    _countdown_panel.offset_bottom = _countdown_panel.offset_top + 59.0

func _toggle_help() -> void:
    _help_open = not _help_open
    if is_instance_valid(_help_tween):
        _help_tween.kill()
    var width := _help_panel.size.x
    var end_left := 16.0 if _help_open else -width
    var end_right := end_left + width
    _help_toggle.text = "‹" if _help_open else "›"
    _help_toggle.tooltip_text = "Skrýt ovládání" if _help_open else "Zobrazit ovládání"
    _help_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT).set_ignore_time_scale(true)
    _help_tween.tween_property(_help_panel, "offset_left", end_left, 0.25)
    _help_tween.tween_property(_help_panel, "offset_right", end_right, 0.25)
    _help_tween.tween_property(_help_toggle, "offset_left", end_right, 0.25)
    _help_tween.tween_property(_help_toggle, "offset_right", end_right + 26.0, 0.25)

func _build_time_panel(surface: Control) -> void:
    _time_panel = PanelContainer.new()
    _time_panel.name = "MissionTime"
    _time_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    _time_panel.offset_left = -326
    _time_panel.offset_right = -16
    _time_panel.offset_top = 16
    _time_panel.offset_bottom = 91
    _time_panel.add_theme_stylebox_override("panel", _panel_style())
    surface.add_child(_time_panel)
    var inset := _inset(9, 7)
    _time_panel.add_child(inset)
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 5)
    inset.add_child(stack)
    var header := HBoxContainer.new()
    stack.add_child(header)
    var title := _label("ČAS SIMULACE", 9, CYAN)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    _time_status = _label("00:00 · 1×", 9, MUTED)
    header.add_child(_time_status)
    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 4)
    stack.add_child(buttons)
    _time_back = _small_button("−10 s")
    _time_back.tooltip_text = "Vrátit se o 10 sekund v zaznamenané historii"
    _time_back.pressed.connect(func(): time_action_requested.emit("back"))
    buttons.add_child(_time_back)
    _time_pause = _small_button("Ⅱ")
    _time_pause.tooltip_text = "Pozastavit čas"
    _time_pause.pressed.connect(func(): time_action_requested.emit("pause"))
    buttons.add_child(_time_pause)
    _time_forward = _small_button("+10 s")
    _time_forward.tooltip_text = "Posunout čas o 10 sekund dopředu"
    _time_forward.pressed.connect(func(): time_action_requested.emit("forward"))
    buttons.add_child(_time_forward)
    for rate in [1.0, 2.0, 5.0, 10.0, 50.0]:
        var speed := float(rate)
        var button := _small_button("%.0f×" % speed)
        button.tooltip_text = "Rychlost simulace %.0f×" % speed
        button.pressed.connect(func(): time_rate_requested.emit(speed))
        buttons.add_child(button)
        _time_rates[speed] = button
    _ignore_mouse_recursive(_time_panel)
    for button in buttons.get_children():
        button.mouse_filter = Control.MOUSE_FILTER_STOP

func _small_button(text: String) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_NONE
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    button.custom_minimum_size = Vector2(26, 25)
    button.add_theme_font_size_override("font_size", 10)
    button.add_theme_color_override("font_color", TEXT)
    var normal := _panel_style()
    normal.bg_color = Color(0.08, 0.14, 0.18, 0.96)
    normal.content_margin_left = 5
    normal.content_margin_right = 5
    normal.content_margin_top = 2
    normal.content_margin_bottom = 2
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.1, 0.29, 0.33, 0.98)
    hover.border_color = CYAN
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", hover)
    button.add_theme_stylebox_override("disabled", normal)
    return button

func update_time_controls(elapsed: float, rate: float, paused: bool, can_rewind: bool, can_forward: bool) -> void:
    if not is_instance_valid(_time_status):
        return
    var seconds := maxi(0, int(elapsed))
    _time_status.text = "%02d:%02d · %s" % [int(seconds / 60.0), seconds % 60, "PAUZA" if paused else "%.0f×" % rate]
    _time_pause.text = "▶" if paused else "Ⅱ"
    _time_pause.tooltip_text = "Pokračovat v čase" if paused else "Pozastavit čas"
    _time_back.disabled = not can_rewind
    _time_forward.disabled = not can_forward
    for value in _time_rates:
        var button: Button = _time_rates[value]
        button.add_theme_color_override("font_color", CYAN if is_equal_approx(float(value), rate) else TEXT)
