extends Control

## Mission menu. The gameplay scene consumes selected_scenario / auto_start
## from SceneTree metadata when it is ready.
const SETTINGS_PATH := "user://rocket_simulator_settings.cfg"
const BG := Color("090f17")
const SURFACE := Color("111d29")
const STROKE := Color("344a59")
const CYAN := Color("7cdee4")
const WHITE := Color("f2f7f7")
const MUTED := Color("9aaeb9")
const GOLD := Color("eabf80")
var selected_scenario := "full_return"
var _scenario_buttons: Array[Button] = []
var _start_button: Button
var _modal: Control
var _fullscreen_check: CheckButton
var _background: TextureRect
var _content_frame: MarginContainer
var _settings := ConfigFile.new()

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _settings.load(SETTINGS_PATH)
    var previous := str(get_tree().get_meta("selected_scenario", "full_return"))
    if previous in ["full_return", "iss_mission"]:
        selected_scenario = previous
    _apply_saved_settings()
    _build_background()
    _build_main_page()
    call_deferred("_focus_if_alive", _start_button)

func _build_background() -> void:
    var dark := ColorRect.new()
    dark.color = BG
    dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dark)
    # The project can replace this image without changing the menu implementation.
    if ResourceLoader.exists("res://assets/menu_background.png"):
        _background = TextureRect.new()
        _background.texture = load("res://assets/menu_background.png")
        _background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        _background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        _background.anchor_left = 0.52
        _background.anchor_right = 1.0
        _background.anchor_bottom = 1.0
        _background.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _background.grow_vertical = Control.GROW_DIRECTION_BOTH
        _background.modulate = Color(0.83, 0.85, 0.88, 1.0)
        _background.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(_background)
        var tint := ColorRect.new()
        tint.color = Color(0.025, 0.065, 0.10, 0.14)
        tint.anchor_left = 0.52
        tint.anchor_right = 1.0
        tint.anchor_bottom = 1.0
        tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(tint)
        # Soft boundary makes the photo and interface one continuous composition.
        var gradient := Gradient.new()
        gradient.set_color(0, BG)
        gradient.set_color(1, Color(BG.r, BG.g, BG.b, 0.0))
        var gradient_image := GradientTexture2D.new()
        gradient_image.gradient = gradient
        gradient_image.fill_from = Vector2(0.0, 0.5)
        gradient_image.fill_to = Vector2(1.0, 0.5)
        var fade := TextureRect.new()
        fade.texture = gradient_image
        fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        fade.stretch_mode = TextureRect.STRETCH_SCALE
        fade.anchor_left = 0.50
        fade.anchor_right = 0.70
        fade.anchor_bottom = 1.0
        fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(fade)
    else:
        var ornament := ColorRect.new()
        ornament.color = Color(0.06, 0.12, 0.17, 0.55)
        ornament.anchor_left = 0.57
        ornament.anchor_right = 1.0
        ornament.anchor_bottom = 1.0
        ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(ornament)

func _build_main_page() -> void:
    var frame := MarginContainer.new()
    _content_frame = frame
    frame.name = "MenuContent"
    frame.anchor_bottom = 1.0
    frame.offset_top = 32
    frame.offset_bottom = -30
    frame.add_theme_constant_override("margin_left", 0)
    add_child(frame)
    resized.connect(_update_content_width)
    _update_content_width()
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 7)
    frame.add_child(layout)

    var brand := HBoxContainer.new()
    brand.add_theme_constant_override("separation", 10)
    layout.add_child(brand)
    var mark := ColorRect.new()
    mark.color = CYAN
    mark.custom_minimum_size = Vector2(3, 15)
    brand.add_child(mark)
    var brand_text := _label("ROCKET  /  SIMULATOR", 12, WHITE)
    brand_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    brand.add_child(brand_text)
    brand.add_child(_label("VERZE 0.1", 10, MUTED))
    layout.add_child(_spacer(18))
    layout.add_child(_label("VESMÍRNÝ LETOVÝ SIMULÁTOR", 10, CYAN))
    var headline := _label("VYBERTE SVOU MISI", 25, WHITE)
    layout.add_child(headline)
    var description := _label("Falcon 9  ·  Crew Dragon  ·  LC-39A", 12, MUTED)
    layout.add_child(description)
    layout.add_child(_spacer(13))
    var divider := ColorRect.new()
    divider.color = Color("263843")
    divider.custom_minimum_size.y = 1
    divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layout.add_child(divider)
    layout.add_child(_spacer(5))
    layout.add_child(_label("SCÉNÁŘ", 10, MUTED))

    _scenario_buttons.append(_scenario_button("01    FULL RETURN · NÁVRAT STUPNĚ\n          Booster na LZ-1 · Dragon na orbitu", "full_return"))
    _scenario_buttons.append(_scenario_button("02    MISE K ISS\n          Start mise · spojení s ISS ve vývoji", "iss_mission"))
    for button in _scenario_buttons:
        layout.add_child(button)
    _refresh_selection()
    var flexible := Control.new()
    flexible.custom_minimum_size = Vector2(0, 4)
    flexible.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layout.add_child(flexible)
    _start_button = _button("SPUSTIT MISI   →", true)
    _start_button.custom_minimum_size.y = 38
    _start_button.pressed.connect(_start_mission)
    layout.add_child(_start_button)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    layout.add_child(row)
    var settings := _button("NASTAVENÍ")
    var help := _button("NÁVOD")
    var exit := _button("UKONČIT")
    for button in [settings, help, exit]:
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.custom_minimum_size.y = 34
        row.add_child(button)
    settings.pressed.connect(_open_settings)
    help.pressed.connect(_open_help)
    exit.pressed.connect(func(): get_tree().quit())
    layout.add_child(_spacer(3))
    layout.add_child(_label("ZKUŠEBNÍ LET  /  FUNKCE SE POSTUPNĚ DOPLŇUJÍ", 10, MUTED))

func _update_content_width() -> void:
    if not is_instance_valid(_content_frame):
        return
    # Keep the controls readable and compact on both regular and ultrawide
    # displays. The photo stays on the right instead of the column stretching.
    var margin := clampf(size.x * 0.045, 24.0, 52.0)
    var column_width := clampf(size.x * 0.38, 300.0, 400.0)
    _content_frame.offset_left = margin
    _content_frame.offset_right = margin + column_width

func _scenario_button(text: String, scenario: String) -> Button:
    var button := _button(text)
    button.name = "Scenario_" + scenario
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.custom_minimum_size = Vector2(0, 54)
    button.add_theme_font_size_override("font_size", 11)
    button.set_meta("scenario", scenario)
    button.pressed.connect(func():
        selected_scenario = scenario
        _refresh_selection()
    )
    return button

func _refresh_selection() -> void:
    for button in _scenario_buttons:
        var active := str(button.get_meta("scenario")) == selected_scenario
        button.add_theme_stylebox_override("normal", _style(Color("192d38") if active else Color("101923"), CYAN if active else Color("293a46"), 5))
        button.add_theme_stylebox_override("hover", _style(Color("203b47"), CYAN, 5))
        button.add_theme_color_override("font_color", WHITE if active else MUTED)

func _start_mission() -> void:
    if is_instance_valid(_modal):
        return
    get_tree().set_meta("selected_scenario", selected_scenario)
    get_tree().set_meta("auto_start", true)
    var err := get_tree().change_scene_to_file("res://scenes/launch_site.tscn")
    if err != OK:
        push_error("Nelze načíst startovní scénu: %s" % err)

func _open_settings() -> void:
    var body := _open_modal("NASTAVENÍ", "Změny se projeví okamžitě a uloží se pro příští spuštění.")
    body.add_child(_label("ZOBRAZENÍ", 11, CYAN))
    var fullscreen := CheckButton.new()
    _fullscreen_check = fullscreen
    fullscreen.text = "Celá obrazovka"
    fullscreen.add_theme_font_size_override("font_size", 12)
    fullscreen.button_pressed = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
    fullscreen.focus_mode = Control.FOCUS_ALL
    fullscreen.toggled.connect(func(enabled: bool):
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
        _settings.set_value("display", "fullscreen", enabled)
        _settings.save(SETTINGS_PATH)
    )
    body.add_child(fullscreen)
    body.add_child(_spacer(8))
    body.add_child(_label("VYHLAZOVÁNÍ HRAN", 11, CYAN))
    var quality := OptionButton.new()
    quality.add_theme_font_size_override("font_size", 12)
    quality.add_item("Vypnuto – vyšší výkon", 0)
    quality.add_item("2× MSAA", 1)
    quality.add_item("4× MSAA", 2)
    quality.selected = clampi(int(_settings.get_value("display", "msaa", 1)), 0, 2)
    quality.custom_minimum_size.y = 36
    quality.item_selected.connect(func(index: int):
        get_tree().root.msaa_3d = index as Viewport.MSAA
        _settings.set_value("display", "msaa", index)
        _settings.save(SETTINGS_PATH)
    )
    body.add_child(quality)
    body.add_child(_spacer(8))
    body.add_child(_label("HLASITOST", 11, CYAN))
    var volume := HSlider.new()
    volume.min_value = 0.0
    volume.max_value = 100.0
    volume.step = 1.0
    volume.value = float(_settings.get_value("audio", "volume", 100.0))
    volume.custom_minimum_size = Vector2(280, 20)
    volume.value_changed.connect(func(value: float):
        var bus := AudioServer.get_bus_index("Master")
        AudioServer.set_bus_volume_linear(bus, value / 100.0)
        _settings.set_value("audio", "volume", value)
        _settings.save(SETTINGS_PATH)
    )
    body.add_child(volume)
    body.add_child(_label("Hlavní hlasitost · zvuky budou postupně doplněny", 11, MUTED))
    _add_close_button(body)

func _open_help() -> void:
    var body := _open_modal("JAK OVLÁDAT LET", "Mise začíná automatickým odpočtem po stisknutí SPUSTIT MISI.")
    var rows := [
        ["MEZERNÍK", "Spustit odpočet / po vzletu vypnout nebo zapnout motory"],
        ["X", "Zrušit probíhající odpočet"],
        ["W / S", "Zvýšit nebo snížit nastavený tah"],
        ["ŠIPKY", "Ruční náklon po startu vypne automatický výstup"],
        ["E", "Ruční oddělení stupňů od výšky 20 km"],
        ["D", "Zahájit návrat odděleného Dragonu na Zemi"],
        ["T", "Rychlost času: 1× / 2× / 5× / 10× / 50×"],
        ["1 / 2 / 3 / 4 / 5", "Kamera: 1. stupeň / 2. stupeň / Dragon / přistávací plocha / celá Země"],
        ["MYŠ / KOLEČKO", "Otočit a přiblížit pohled"],
        ["R", "Reset na rampu · nový odpočet mezerníkem"],
        ["F11 / ESC", "Celá obrazovka / návrat do hlavního menu"]
    ]
    for pair in rows:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 16)
        var key := _label(pair[0], 12, CYAN)
        key.custom_minimum_size.x = 132
        row.add_child(key)
        var explanation := _label(pair[1], 12, WHITE)
        explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        row.add_child(explanation)
        body.add_child(row)
    _add_close_button(body)

func _open_modal(title: String, subtitle: String) -> VBoxContainer:
    _fullscreen_check = null
    if is_instance_valid(_modal):
        _modal.queue_free()
    _modal = Control.new()
    _modal.name = "Modal"
    _modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(_modal)
    var veil := ColorRect.new()
    veil.color = Color(0.0, 0.02, 0.035, 0.82)
    veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _modal.add_child(veil)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _modal.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size.x = 500
    panel.add_theme_stylebox_override("panel", _style(Color("101d29"), Color("38515d"), 10))
    center.add_child(panel)
    var inset := MarginContainer.new()
    for direction in ["left", "right", "top", "bottom"]:
        inset.add_theme_constant_override("margin_" + direction, 22)
    panel.add_child(inset)
    var body := VBoxContainer.new()
    body.add_theme_constant_override("separation", 8)
    inset.add_child(body)
    body.add_child(_label(title, 20, WHITE))
    var detail := _label(subtitle, 12, MUTED)
    detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(detail)
    body.add_child(_spacer(9))
    return body

func _add_close_button(body: VBoxContainer) -> void:
    body.add_child(_spacer(9))
    var close := _button("ZPĚT", true)
    close.custom_minimum_size.y = 36
    close.pressed.connect(_close_modal)
    body.add_child(close)
    call_deferred("_focus_if_alive", close)

func _close_modal() -> void:
    _fullscreen_check = null
    if is_instance_valid(_modal):
        _modal.queue_free()
        _modal = null
    call_deferred("_focus_if_alive", _start_button)

func _focus_if_alive(control) -> void:
    if is_instance_valid(control) and control.is_inside_tree():
        control.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE and is_instance_valid(_modal):
            _close_modal()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_F11:
            var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
            if is_instance_valid(_fullscreen_check):
                _fullscreen_check.set_pressed_no_signal(not full)
            _settings.set_value("display", "fullscreen", not full)
            _settings.save(SETTINGS_PATH)
            get_viewport().set_input_as_handled()

func _apply_saved_settings() -> void:
    var full := bool(_settings.get_value("display", "fullscreen", true))
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)
    get_tree().root.msaa_3d = clampi(int(_settings.get_value("display", "msaa", 1)), 0, 2) as Viewport.MSAA
    AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("Master"), clampf(float(_settings.get_value("audio", "volume", 100.0)) / 100.0, 0.0, 1.0))

func _button(text: String, primary := false) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_ALL
    button.add_theme_font_size_override("font_size", 11)
    button.add_theme_color_override("font_color", BG if primary else WHITE)
    button.add_theme_color_override("font_hover_color", BG if primary else WHITE)
    button.add_theme_color_override("font_focus_color", BG if primary else WHITE)
    button.add_theme_stylebox_override("normal", _style(CYAN if primary else SURFACE, CYAN if primary else STROKE, 6))
    button.add_theme_stylebox_override("hover", _style(Color("a8f2f2") if primary else Color("233541"), CYAN, 6))
    button.add_theme_stylebox_override("pressed", _style(Color("5bb9c2") if primary else Color("162a34"), CYAN, 6))
    var focus := _style(Color(0, 0, 0, 0), WHITE, 6)
    focus.set_border_width_all(2)
    button.add_theme_stylebox_override("focus", focus)
    return button

func _style(fill: Color, stroke: Color, radius: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = stroke
    box.set_border_width_all(1)
    box.set_corner_radius_all(radius)
    box.content_margin_left = 12
    box.content_margin_right = 12
    box.content_margin_top = 5
    box.content_margin_bottom = 5
    return box

func _label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label

func _spacer(height: float) -> Control:
    var spacer := Control.new()
    spacer.custom_minimum_size.y = height
    return spacer
