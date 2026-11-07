class_name ReplayShare
extends RefCounted
## "Del replay": hands a replay (JSON text) to the platform. On the web the
## browser downloads it as a file (JavaScriptBridge, only looked up on the web,
## so every platform compiles). Godot has no share sheet without a plugin, so
## on iOS and elsewhere the JSON goes to the clipboard. Returns the toast text.

const MIME := "application/json"


static func share(text: String, file_name: String) -> String:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		bridge.call("download_buffer", text.to_utf8_buffer(), file_name, MIME)
		return "Lastet ned"
	DisplayServer.clipboard_set(text)
	return "Kopiert"
