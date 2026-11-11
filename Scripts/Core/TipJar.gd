class_name TipJar
extends RefCounted
## Buy Me a Coffee link for the results screens.
##
## Web builds ask the arcade client first, so the URL lives in one place and a
## new tab keeps the finished run sitting behind it. Desktop opens the browser.

const TIP_URL := "https://www.buymeacoffee.com/jd4rider"


static func open() -> void:
	if OS.has_feature("web"):
		var handled: Variant = JavaScriptBridge.eval(
			"(function(){var a=window.LittleJoyArcade;if(a&&a.tipJar&&a.tipJar.open){a.tipJar.open();return true}return false})()",
			true)
		if handled != null and bool(handled):
			return
		JavaScriptBridge.eval("window.open('%s', '_blank', 'noopener')" % TIP_URL, true)
		return
	OS.shell_open(TIP_URL)
