@tool
extends RefCounted

const CONFIRM_TIMEOUT_MSEC = 5000
const RECENT_START_GUARD_MSEC = 2000

var _plugin
var _pending_operation: Dictionary = {}
var _last_operation: Dictionary = {}
var _operation_sequence: int = 0


func _init(plugin) -> void:
	_plugin = plugin


func teardown() -> void:
	if not _pending_operation.is_empty():
		_finish_pending("canceled", "The plugin was disabled before the play-mode operation ran.")
	_plugin = null


func poll() -> void:
	if _pending_operation.is_empty():
		return
	if str(_pending_operation.get("status", "")) == "scheduled":
		_execute_pending()
	else:
		_reconcile_pending()


func request_start(mode: String, scene_path: String = "", options: Dictionary = {}) -> Dictionary:
	var editor = _editor()
	if editor == null:
		return _error("PLAY_MODE_UNAVAILABLE", "Godot's EditorInterface is unavailable.")

	var normalized_mode: String = mode.strip_edges().to_lower()
	if not (normalized_mode in ["current", "main", "custom"]):
		return _error("UNSUPPORTED_PLAY_MODE", "Unsupported play mode '%s'." % normalized_mode)

	var validation: Dictionary = _validate_start_target(editor, normalized_mode, scene_path)
	if not bool(validation.get("success", false)):
		return validation

	var restart_if_running: bool = bool(options.get("restart_if_running", false))
	var allow_multiple_instances: bool = bool(options.get("allow_multiple_instances", false))
	var target: Dictionary = {
		"mode": normalized_mode,
		"scene_path": scene_path,
	}
	if not _pending_operation.is_empty():
		if _is_duplicate_start(_pending_operation, target):
			return _operation_result(_pending_operation, true, "The matching play request is already scheduled.")
		return _error(
			"PLAY_MODE_TRANSITION_PENDING",
			"Another play-mode transition is still pending.",
			{"pending_operation": _public_operation(_pending_operation)}
		)

	if editor.is_playing_scene() and not restart_if_running:
		return _status_result("already_running", "A scene is already running. Pass restart_if_running=true to restart it.")

	var run_instances: Dictionary = _get_run_instances_info(editor)
	if int(run_instances.get("effective_instance_count", 1)) > 1 and not allow_multiple_instances:
		return _error(
			"MULTIPLE_INSTANCES_CONFIRMATION_REQUIRED",
			"Godot is configured to launch %d instances. Pass allow_multiple_instances=true to confirm this run." % int(run_instances.get("effective_instance_count", 1)),
			{"run_instances": run_instances}
		)

	var recent_guard: Dictionary = _get_recent_start_guard(target, restart_if_running)
	if not recent_guard.is_empty():
		return recent_guard

	_pending_operation = _new_operation("start", {
		"mode": normalized_mode,
		"scene_path": scene_path,
		"restart_if_running": restart_if_running,
		"allow_multiple_instances": allow_multiple_instances,
		"run_instances": run_instances,
	})
	return _operation_result(
		_pending_operation,
		false,
		"Play request accepted and deferred until after the MCP response is sent."
	)


func request_stop() -> Dictionary:
	var editor = _editor()
	if editor == null:
		return _error("PLAY_MODE_UNAVAILABLE", "Godot's EditorInterface is unavailable.")

	if not _pending_operation.is_empty():
		var pending_action: String = str(_pending_operation.get("action", ""))
		if pending_action == "stop":
			return _operation_result(_pending_operation, true, "A stop request is already scheduled.")
		if pending_action == "start":
			_finish_pending("canceled", "The scheduled play request was canceled by exit_play_mode.")
			if not editor.is_playing_scene():
				return _status_result("canceled_before_start", "The scheduled play request was canceled before it started.")

	if not editor.is_playing_scene():
		return _status_result("already_stopped", "No scene is currently running.")

	_pending_operation = _new_operation("stop")
	return _operation_result(
		_pending_operation,
		false,
		"Stop request accepted and deferred until after the MCP response is sent."
	)


func get_state() -> Dictionary:
	_reconcile_pending()
	var editor = _editor()
	if editor == null:
		return {
			"available": false,
			"is_playing_scene": false,
			"pending_operation": _public_operation(_pending_operation),
			"last_operation": _public_operation(_last_operation),
		}

	var playing_scene_path: String = ""
	if editor.has_method("get_playing_scene"):
		playing_scene_path = str(editor.get_playing_scene())
	var current_scene_path: String = _get_current_scene_path(editor)
	var open_scenes: Array = []
	for open_scene in editor.get_open_scenes():
		open_scenes.append(str(open_scene))

	return {
		"available": true,
		"is_playing_scene": editor.is_playing_scene(),
		"playing_scene_path": playing_scene_path,
		"current_scene_path": current_scene_path,
		"open_scenes": open_scenes,
		"time_scale": Engine.time_scale,
		"run_instances": _get_run_instances_info(editor),
		"pending_operation": _public_operation(_pending_operation),
		"last_operation": _public_operation(_last_operation),
	}


func _execute_pending() -> void:
	var editor = _editor()
	if editor == null:
		_finish_pending("failed", "Godot's EditorInterface became unavailable.")
		return

	var operation: Dictionary = _pending_operation.duplicate(true)
	operation["status"] = "executing"
	operation["executed_at"] = Time.get_datetime_string_from_system(true, true)
	operation["executed_at_msec"] = Time.get_ticks_msec()
	_pending_operation = operation

	if str(operation.get("action", "")) == "stop":
		if not editor.is_playing_scene():
			_finish_pending("completed", "The scene was already stopped before the request executed.")
			return
		editor.stop_playing_scene()
	else:
		if editor.is_playing_scene() and not bool(operation.get("restart_if_running", false)):
			_finish_pending("completed", "A scene started before the queued request executed; no restart was performed.")
			return
		match str(operation.get("mode", "")):
			"current":
				editor.play_current_scene()
			"main":
				editor.play_main_scene()
			"custom":
				editor.play_custom_scene(str(operation.get("scene_path", "")))

	_reconcile_pending()


func _reconcile_pending() -> void:
	if _pending_operation.is_empty() or str(_pending_operation.get("status", "")) == "scheduled":
		return

	var editor = _editor()
	if editor == null:
		_finish_pending("failed", "Godot's EditorInterface became unavailable while confirming the transition.")
		return

	var expected_playing: bool = str(_pending_operation.get("action", "")) == "start"
	if editor.is_playing_scene() == expected_playing:
		var message: String = "Play mode started successfully."
		if not expected_playing:
			message = "Play mode stopped successfully."
		_finish_pending("completed", message)
		return

	var started_at: int = int(_pending_operation.get("executed_at_msec", _pending_operation.get("requested_at_msec", 0)))
	if Time.get_ticks_msec() - started_at >= CONFIRM_TIMEOUT_MSEC:
		_finish_pending(
			"failed",
			"Godot did not reach the expected play state within %d ms." % CONFIRM_TIMEOUT_MSEC
		)


func _validate_start_target(editor, mode: String, scene_path: String) -> Dictionary:
	if mode == "main":
		var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", "")).strip_edges()
		if main_scene == "":
			return _error("MAIN_SCENE_NOT_CONFIGURED", "The project does not have an application/run/main_scene configured.")
	elif mode == "current" and _get_current_scene_path(editor) == "":
		return _error("CURRENT_SCENE_NOT_SAVED", "The current scene must be saved before it can be started through MCP.")
	elif mode == "custom":
		if scene_path.strip_edges() == "":
			return _error("CUSTOM_SCENE_REQUIRED", "scene_path is required when mode is custom.")
		if not FileAccess.file_exists(scene_path):
			return _error("CUSTOM_SCENE_NOT_FOUND", "Scene not found: %s" % scene_path)
	return {"success": true}


func _get_run_instances_info(editor) -> Dictionary:
	var result: Dictionary = {
		"available": false,
		"multiple_instances_enabled": false,
		"configured_instance_count": 1,
		"effective_instance_count": 1,
		"has_custom_arguments": false,
	}
	if not editor.has_method("get_editor_settings"):
		return result

	var editor_settings = editor.get_editor_settings()
	if editor_settings == null or not editor_settings.has_method("get_project_metadata"):
		return result

	var enabled: bool = bool(editor_settings.get_project_metadata("debug_options", "multiple_instances_enabled", false))
	var configurations = editor_settings.get_project_metadata("debug_options", "run_instances_config", [])
	var default_count: int = configurations.size() if configurations is Array else 1
	var configured_count: int = max(
		int(editor_settings.get_project_metadata("debug_options", "run_instance_count", max(default_count, 1))),
		1
	)
	var has_custom_arguments: bool = false
	if configurations is Array:
		for configuration in configurations:
			if configuration is Dictionary and str(configuration.get("arguments", "")).strip_edges() != "":
				has_custom_arguments = true
				break

	result["available"] = true
	result["multiple_instances_enabled"] = enabled
	result["configured_instance_count"] = configured_count
	result["effective_instance_count"] = configured_count if enabled else 1
	result["has_custom_arguments"] = has_custom_arguments
	return result


func _new_operation(action: String, details: Dictionary = {}) -> Dictionary:
	_operation_sequence += 1
	var operation: Dictionary = {
		"id": "play-mode-%d" % _operation_sequence,
		"action": action,
		"status": "scheduled",
		"requested_at": Time.get_datetime_string_from_system(true, true),
		"requested_at_msec": Time.get_ticks_msec(),
	}
	operation.merge(details, true)
	return operation


func _finish_pending(status: String, message: String) -> void:
	if _pending_operation.is_empty():
		return
	var operation: Dictionary = _pending_operation.duplicate(true)
	operation["status"] = status
	operation["message"] = message
	operation["finished_at"] = Time.get_datetime_string_from_system(true, true)
	operation["finished_at_msec"] = Time.get_ticks_msec()
	_last_operation = operation
	_pending_operation = {}


func _is_duplicate_start(operation: Dictionary, target: Dictionary) -> bool:
	return str(operation.get("action", "")) == "start" \
		and str(operation.get("mode", "")) == str(target.get("mode", "")) \
		and str(operation.get("scene_path", "")) == str(target.get("scene_path", ""))


func _get_recent_start_guard(target: Dictionary, restart_if_running: bool) -> Dictionary:
	if restart_if_running or _last_operation.is_empty():
		return {}
	if not (str(_last_operation.get("status", "")) in ["completed", "failed"]):
		return {}
	if not _is_duplicate_start(_last_operation, target):
		return {}
	var elapsed: int = Time.get_ticks_msec() - int(_last_operation.get("finished_at_msec", 0))
	if elapsed < 0 or elapsed >= RECENT_START_GUARD_MSEC:
		return {}
	if str(_last_operation.get("status", "")) == "failed":
		return _error(
			"PLAY_MODE_RETRY_THROTTLED",
			"The previous play request failed recently; rapid relaunch was suppressed.",
			{
				"retry_after_msec": RECENT_START_GUARD_MSEC - elapsed,
				"operation": _public_operation(_last_operation),
				"play_state": get_state(),
			}
		)
	return {
		"success": true,
		"status": "recently_requested",
		"message": "An identical play request completed recently; rapid relaunch was suppressed.",
		"retry_after_msec": RECENT_START_GUARD_MSEC - elapsed,
		"operation": _public_operation(_last_operation),
		"play_state": get_state(),
	}


func _operation_result(operation: Dictionary, deduplicated: bool, message: String) -> Dictionary:
	return {
		"success": true,
		"status": str(operation.get("status", "scheduled")),
		"message": message,
		"deduplicated": deduplicated,
		"operation": _public_operation(operation),
		"play_state": get_state(),
	}


func _status_result(status: String, message: String) -> Dictionary:
	return {
		"success": true,
		"status": status,
		"message": message,
		"play_state": get_state(),
	}


func _error(code: String, message: String, data: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"code": code,
		"error": message,
		"data": data,
	}


func _public_operation(operation: Dictionary) -> Dictionary:
	if operation.is_empty():
		return {}
	var public_operation: Dictionary = operation.duplicate(true)
	public_operation.erase("requested_at_msec")
	public_operation.erase("executed_at_msec")
	public_operation.erase("finished_at_msec")
	return public_operation


func _get_current_scene_path(editor) -> String:
	if editor.has_method("get_edited_scene_root"):
		var scene_root = editor.get_edited_scene_root()
		if scene_root == null:
			return ""
		return str(scene_root.scene_file_path).strip_edges()
	return str(editor.get_current_path()).strip_edges()


func _editor():
	if _plugin == null or not _plugin.has_method("get_editor_interface"):
		return null
	return _plugin.get_editor_interface()
