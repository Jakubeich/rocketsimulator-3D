@tool
extends RefCounted

const ENGLISH = "en"
const SIMPLIFIED_CHINESE = "zh_CN"
const SUPPORTED_LANGUAGES = [ENGLISH, SIMPLIFIED_CHINESE]

const CATALOGS = {
	ENGLISH: {
		"language": "Language",
		"check_updates": "Check Updates",
		"checking": "Checking...",
		"open_release": "Open Release",
		"dashboard": "Dashboard",
		"install_bridge": "Install Bridge",
		"install_bridge_tooltip": "Install the optional play-mode runtime bridge autoload.",
		"remove_bridge": "Remove Bridge",
		"remove_bridge_tooltip": "Remove the optional play-mode runtime bridge autoload.",
		"enable_server": "Enable MCP Server",
		"port": "Port",
		"tool_profile": "Tool Profile",
		"debug_logging": "Debug Logging",
		"debug_logging_tooltip": "Print MCP activity to the Godot output panel.",
		"execute_safety_checks": "execute_code Safety Checks",
		"execute_safety_tooltip": "Block common dangerous filesystem, process, and project-setting snippets by default. Tool calls can still override with safety_checks=false.",
		"open_project_map": "Open Project Map",
		"open_project_map_tooltip": "Generate a read-only HTML project visualizer from map_project and open it in the browser.",
		"tool_exposure": "Tool Exposure",
		"reset": "Reset",
		"reset_tools_tooltip": "Expose every tool allowed by the current profile and project language.",
		"client_config_snippet": "Client Config Snippet",
		"copy_snippet": "Copy Snippet",
		"configure": "Configure",
		"configure_skills": "Configure + Skills",
		"configure_skills_tooltip": "Write the selected MCP client config and generate project skill files.",
		"recent_activity": "Recent Activity",
		"status_stopped": "Stopped",
		"status_running": "Running",
		"status_attached": "Attached",
		"status_ready": "Ready",
		"status_command": "Processing command",
		"status_exit": "Exited",
		"status_unknown": "Unknown",
		"status_line": "Status: %s",
		"endpoint_line": "Endpoint: %s",
		"copied_to_clipboard": "Copied to clipboard.",
		"runtime_registry_unavailable": "Runtime: tool registry unavailable.",
		"runtime_action_failed": "Runtime bridge action failed: %s",
		"project_map_unavailable": "Project map unavailable.",
		"project_map_failed": "Project map failed: %s",
		"project_map_write_failed": "Failed to write project map.",
		"project_map_opened": "Opened %s",
		"no_activity": "No activity yet.",
		"activity_success": "success",
		"activity_error": "error",
		"activity_warning": "warning",
		"config_status_unavailable": "Config status: unavailable",
		"config_status_configured": "Config status: Configured",
		"config_status_not_configured": "Config status: Not configured",
		"project_skills_generated": "Project skills: Generated at %s",
		"project_skills_not_generated": "Project skills: Not generated",
		"dashboard_status": "Project: %s\nServer: %s · Profile: %s · Tools: %d/%d exposed",
		"runtime_installed": "installed",
		"runtime_not_installed": "not installed",
		"runtime_no_heartbeat": "Runtime: bridge %s · heartbeat not seen",
		"runtime_status": "Runtime: %s · %s · FPS %d · Nodes %d · Events %d%s",
		"runtime_scene": " · Scene %s",
		"release_unavailable": "Release: readiness unavailable",
		"release_status": "Release: %s · v%s · Checks %d/%d pass",
		"release_ready": "ready",
		"release_blocked": "blocked",
		"release_all_checks_passed": "All release readiness checks passed.",
		"updates_not_checked": "Updates: Not checked",
		"updates_checking": "Updates: Checking GitHub...",
		"updates_start_failed": "Updates: Failed to start check (%s)",
		"updates_request_failed": "Updates: Check failed (%s)",
		"updates_http_error": "Updates: GitHub returned HTTP %d",
		"updates_invalid_response": "Updates: Invalid GitHub response",
		"updates_invalid_version": "Updates: Latest release has no valid version",
		"updates_available": "Updates: v%s available",
		"updates_up_to_date": "Updates: Up to date (v%s)",
		"updates_local_newer": "Updates: Local v%s is newer than latest v%s",
		"updates_checksums_found": "release checksums found",
		"updates_checksums_missing": "checksum assets missing",
		"release_artifacts_not_checked": "No release artifacts checked yet.",
		"expected_package": "Expected package: %s",
		"verification_ready": "Verification ready: %s",
		"registry_ready": "Registry ready: %s",
		"yes": "yes",
		"no": "no",
		"artifact_missing": "%s: missing",
		"artifact_found": "%s: %s (%d bytes)",
		"artifact_package": "Package",
		"artifact_manifest": "Manifest",
		"badge_disabled": "disabled",
		"badge_language": "language",
		"tool_exposure_summary": "Tool Exposure: %d/%d exposed",
		"config_missing_path": "Missing config path.",
		"config_directory_failed": "Failed to create config directory: %s",
		"config_json_invalid": "Config JSON is invalid and was not modified: %s (line %d: %s)",
		"config_json_root_invalid": "Config JSON root must be an object and was not modified: %s",
		"config_write_failed": "Failed to open config for writing: %s",
		"config_written": "Configuration written to %s",
		"skill_directory_failed": "Failed to create project skills directory: %s",
		"skill_write_failed": "Failed to write project skill: %s",
		"skill_manifest_failed": "Failed to write project skill manifest: %s",
		"skill_agents_bridge_failed": "Generated project skill, but failed to update %s.",
		"skills_generated": "Project skills generated.",
	},
	SIMPLIFIED_CHINESE: {
		"language": "界面语言",
		"check_updates": "检查更新",
		"checking": "检查中...",
		"open_release": "打开发布页",
		"dashboard": "运行面板",
		"install_bridge": "安装运行桥接",
		"install_bridge_tooltip": "安装可选的运行模式桥接 Autoload。",
		"remove_bridge": "移除运行桥接",
		"remove_bridge_tooltip": "移除可选的运行模式桥接 Autoload。",
		"enable_server": "启用 MCP 服务器",
		"port": "端口",
		"tool_profile": "工具配置",
		"debug_logging": "调试日志",
		"debug_logging_tooltip": "将 MCP 活动输出到 Godot 输出面板。",
		"execute_safety_checks": "execute_code 安全检查",
		"execute_safety_tooltip": "默认拦截常见的危险文件系统、进程和项目设置代码；工具调用仍可通过 safety_checks=false 显式关闭。",
		"open_project_map": "打开项目地图",
		"open_project_map_tooltip": "通过 map_project 生成只读 HTML 项目可视化页面并在浏览器中打开。",
		"tool_exposure": "工具开放范围",
		"reset": "重置",
		"reset_tools_tooltip": "开放当前工具配置和项目语言允许的全部工具。",
		"client_config_snippet": "客户端配置片段",
		"copy_snippet": "复制片段",
		"configure": "写入配置",
		"configure_skills": "配置并生成 Skills",
		"configure_skills_tooltip": "写入所选 MCP 客户端配置，并生成项目 Skill 文件。",
		"recent_activity": "最近活动",
		"status_stopped": "已停止",
		"status_running": "运行中",
		"status_attached": "已连接现有服务",
		"status_ready": "已就绪",
		"status_command": "正在处理命令",
		"status_exit": "已退出",
		"status_unknown": "未知",
		"status_line": "状态：%s",
		"endpoint_line": "端点：%s",
		"copied_to_clipboard": "已复制到剪贴板。",
		"runtime_registry_unavailable": "运行状态：工具注册表不可用。",
		"runtime_action_failed": "运行桥接操作失败：%s",
		"project_map_unavailable": "项目地图不可用。",
		"project_map_failed": "项目地图生成失败：%s",
		"project_map_write_failed": "写入项目地图失败。",
		"project_map_opened": "已打开 %s",
		"no_activity": "暂无活动。",
		"activity_success": "成功",
		"activity_error": "错误",
		"activity_warning": "警告",
		"config_status_unavailable": "配置状态：不可用",
		"config_status_configured": "配置状态：已配置",
		"config_status_not_configured": "配置状态：未配置",
		"project_skills_generated": "项目 Skills：已生成于 %s",
		"project_skills_not_generated": "项目 Skills：尚未生成",
		"dashboard_status": "项目：%s\n服务器：%s · 配置：%s · 已开放工具：%d/%d",
		"runtime_installed": "已安装",
		"runtime_not_installed": "未安装",
		"runtime_no_heartbeat": "运行桥接：%s · 尚未检测到心跳",
		"runtime_status": "运行桥接：%s · %s · FPS %d · 节点 %d · 事件 %d%s",
		"runtime_scene": " · 场景 %s",
		"release_unavailable": "发布状态：就绪检查不可用",
		"release_status": "发布状态：%s · v%s · 检查通过 %d/%d",
		"release_ready": "就绪",
		"release_blocked": "受阻",
		"release_all_checks_passed": "所有发布就绪检查均已通过。",
		"updates_not_checked": "更新：尚未检查",
		"updates_checking": "更新：正在检查 GitHub...",
		"updates_start_failed": "更新：无法开始检查（%s）",
		"updates_request_failed": "更新：检查失败（%s）",
		"updates_http_error": "更新：GitHub 返回 HTTP %d",
		"updates_invalid_response": "更新：GitHub 响应无效",
		"updates_invalid_version": "更新：最新发布没有有效版本号",
		"updates_available": "更新：发现 v%s",
		"updates_up_to_date": "更新：已是最新版本（v%s）",
		"updates_local_newer": "更新：本地 v%s 高于最新发布 v%s",
		"updates_checksums_found": "已找到发布校验文件",
		"updates_checksums_missing": "缺少校验文件",
		"release_artifacts_not_checked": "尚未检查发布产物。",
		"expected_package": "预期安装包：%s",
		"verification_ready": "校验文件就绪：%s",
		"registry_ready": "Registry 文件就绪：%s",
		"yes": "是",
		"no": "否",
		"artifact_missing": "%s：缺失",
		"artifact_found": "%s：%s（%d 字节）",
		"artifact_package": "安装包",
		"artifact_manifest": "清单",
		"badge_disabled": "已禁用",
		"badge_language": "语言不适用",
		"tool_exposure_summary": "工具开放范围：已开放 %d/%d",
		"config_missing_path": "缺少配置文件路径。",
		"config_directory_failed": "创建配置目录失败：%s",
		"config_json_invalid": "配置 JSON 无效，未进行修改：%s（第 %d 行：%s）",
		"config_json_root_invalid": "配置 JSON 根节点必须是对象，未进行修改：%s",
		"config_write_failed": "无法打开配置文件进行写入：%s",
		"config_written": "配置已写入 %s",
		"skill_directory_failed": "创建项目 Skills 目录失败：%s",
		"skill_write_failed": "写入项目 Skill 失败：%s",
		"skill_manifest_failed": "写入项目 Skill 清单失败：%s",
		"skill_agents_bridge_failed": "项目 Skill 已生成，但更新 %s 失败。",
		"skills_generated": "项目 Skills 已生成。",
	},
}


static func normalize_language(value: String) -> String:
	var normalized: String = value.strip_edges().replace("-", "_").to_lower()
	return SIMPLIFIED_CHINESE if normalized.begins_with("zh") else ENGLISH


static func default_language_for_locale(locale: String = "") -> String:
	var resolved_locale: String = locale if locale.strip_edges() != "" else TranslationServer.get_locale()
	return normalize_language(resolved_locale)


static func translate(key: String, language: String, values: Array = []) -> String:
	var normalized: String = normalize_language(language)
	var catalog: Dictionary = CATALOGS.get(normalized, CATALOGS[ENGLISH])
	var english_catalog: Dictionary = CATALOGS[ENGLISH]
	var template: String = str(catalog.get(key, english_catalog.get(key, key)))
	if values.is_empty():
		return template
	if values.size() == 1:
		return template % values[0]
	return template % values


static func has_key(key: String) -> bool:
	var english_catalog: Dictionary = CATALOGS[ENGLISH]
	return english_catalog.has(key)


static func validate_catalogs() -> Array[String]:
	var errors: Array[String] = []
	var english_catalog: Dictionary = CATALOGS[ENGLISH]
	for language in SUPPORTED_LANGUAGES:
		var catalog: Dictionary = CATALOGS.get(language, {})
		for key in english_catalog.keys():
			if not catalog.has(key) or str(catalog.get(key, "")).strip_edges() == "":
				errors.append("%s is missing translation key: %s" % [language, key])
		for key in catalog.keys():
			if not english_catalog.has(key):
				errors.append("%s has unexpected translation key: %s" % [language, key])
	return errors
