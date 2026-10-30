extends Node3D

const MissionTimeline := preload("res://scripts/mission_timeline.gd")

## The menu passes a scenario id through SceneTree metadata. Launching this
## scene directly in the editor remains supported and does not auto-start.
func _ready() -> void:
    var mission := str(get_tree().get_meta("selected_scenario", "full_return"))
    var rocket = get_node("Falcon9_CrewDragon")
    rocket.scenario_id = mission if mission in ["full_return", "iss_mission"] else "full_return"
    var timeline := MissionTimeline.new()
    timeline.name = "MissionTimeline"
    add_child(timeline)
    timeline.configure(rocket, get_node("FlightHUD"), get_node("InspectionCamera"))
    if bool(get_tree().get_meta("auto_start", false)):
        get_tree().remove_meta("auto_start")
        rocket.call_deferred("start_countdown")
