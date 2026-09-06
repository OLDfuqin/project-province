class_name ContextInspector
extends PanelContainer

signal close_requested

var _mode := "empty"
var _active_panel: Control


func _ready() -> void:
    %Close.pressed.connect(func() -> void: close_requested.emit())
    show_empty()


func show_empty(message: String = "请选择地区或军队") -> void:
    _clear_active_panel()
    _mode = "empty"
    %Title.text = "战略信息"
    %Empty.text = message
    %Empty.visible = true


func show_panel(mode: String, title: String, panel: Control) -> void:
    _clear_active_panel()
    _mode = mode
    %Title.text = title
    %Empty.visible = false
    _active_panel = panel
    %Content.add_child(panel)
    panel.visible = true


func current_mode() -> String:
    return _mode


func _clear_active_panel() -> void:
    if is_instance_valid(_active_panel):
        %Content.remove_child(_active_panel)
    _active_panel = null
