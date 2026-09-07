class_name SettingsPage
extends PanelContainer


signal quick_save_requested
signal quick_load_requested


func _ready() -> void:
	$Content/Actions/QuickSave.pressed.connect(func() -> void: quick_save_requested.emit())
	$Content/Actions/QuickLoad.pressed.connect(func() -> void: quick_load_requested.emit())


func set_build_info(version: String, save_count: int) -> void:
	%BuildInfo.text = "核心版本：%s\n可用存档：%d" % [
		version if not version.is_empty() else "未知",
		maxi(save_count, 0),
	]
