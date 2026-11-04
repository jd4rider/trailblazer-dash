extends Node
## Bridge between the Godot build and the Little Joy Arcade web SDK.
##
## The browser wrapper (`web/arcade-bridge.js`) exposes a deliberately small
## `window.TrailblazerArcade` object. Nothing here is invented: if the wrapper
## is absent (desktop, or opened outside the arcade) every call becomes a no-op
## and the game keeps saving locally.

signal status_changed(value: String)

var available := false
var status := "local"
var player_label := "Guest"
var signed_in := false
var last_sync_ms := 0

var _platform := "desktop"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_platform = "web"
		var probe: Variant = JavaScriptBridge.eval(
			"typeof window.TrailblazerArcade !== 'undefined'", true)
		available = bool(probe) if probe != null else false
	if not available:
		status = "local"
		return
	status = "connecting"
	_refresh_identity()
	var remote: Variant = pull()
	if typeof(remote) == TYPE_DICTIONARY and not (remote as Dictionary).is_empty():
		_merge_remote(remote)
	on_local_save(Save.data)


func _refresh_identity() -> void:
	var raw: Variant = _call("JSON.stringify(window.TrailblazerArcade.identity())")
	if raw == null:
		return
	var parsed: Variant = JSON.parse_string(String(raw))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var record: Dictionary = parsed
	signed_in = bool(record.get("signedIn", false))
	player_label = String(record.get("name", "Guest"))
	var remote_status := String(record.get("status", "local"))
	_set_status(remote_status)


func _call(code: String) -> Variant:
	if not available:
		return null
	return JavaScriptBridge.eval(code, true)


func _set_status(value: String) -> void:
	var allowed := ["local", "connecting", "synced", "offline", "signed_out", "error"]
	status = value if value in allowed else "local"
	status_changed.emit(status)


func on_local_save(payload: Dictionary) -> void:
	if not available:
		return
	var encoded := Marshalls.utf8_to_base64(JSON.stringify(payload))
	_call("window.TrailblazerArcade.pushSave('%s')" % encoded)
	last_sync_ms = Time.get_ticks_msec()
	var reported: Variant = _call("window.TrailblazerArcade.status()")
	if reported != null:
		_set_status(String(reported))


func pull() -> Variant:
	if not available:
		return {}
	var raw: Variant = _call("window.TrailblazerArcade.pullSave()")
	if raw == null:
		return {}
	var text := String(raw)
	if text.is_empty() or text == "null":
		return {}
	return JSON.parse_string(text)


## Newest save wins for progress; achievements are unioned; device settings
## always stay local so a phone player keeps their own audio and motion setup.
func _merge_remote(remote: Dictionary) -> void:
	var remote_stamp := int(remote.get("savedAt", 0))
	var local_stamp := int(Save.data.get("savedAt", 0))
	var merged := false
	if remote_stamp > local_stamp:
		var settings: Dictionary = Save.data.get("settings", {})
		var profile: Dictionary = Save.data.get("profile", {})
		Save.data = remote
		Save.data["settings"] = settings
		Save.data["profile"] = profile
		merged = true
	var remote_achievements: Variant = remote.get("achievements", {})
	if typeof(remote_achievements) == TYPE_DICTIONARY:
		for id in remote_achievements.keys():
			if not Save.data["achievements"].has(id):
				Save.data["achievements"][id] = remote_achievements[id]
				merged = true
	if merged:
		Save.queue_save()
		Save.changed.emit()
		Save.flush()


func achievement(id: String) -> void:
	if not available:
		return
	_call("window.TrailblazerArcade.unlockAchievement('%s')" % id)


func track(event: String, props: Dictionary = {}) -> void:
	if not available:
		return
	var encoded := Marshalls.utf8_to_base64(JSON.stringify({"name": event, "props": props}))
	_call("window.TrailblazerArcade.track('%s')" % encoded)


func sign_in() -> void:
	_call("window.TrailblazerArcade.signIn()")


func open_arcade() -> void:
	if available:
		_call("window.TrailblazerArcade.openArcade()")


func status_text() -> String:
	match status:
		"synced":
			return "Cloud saved · %s" % player_label
		"connecting":
			return "Connecting to Little Joy Arcade…"
		"offline":
			return "Offline · saving on this device"
		"error":
			return "Sync hiccup · saving on this device"
		_:
			return "Local save · play anywhere, sync when signed in"
