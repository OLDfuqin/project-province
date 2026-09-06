class_name PrimaryNavigation
extends PanelContainer

signal destination_requested(destination: String)

const DESTINATIONS := ["map", "country", "diplomacy", "technology", "military", "economy", "settings"]

var _active_destination := "map"


func _ready() -> void:
    for child: Node in $Margin/Row.get_children():
        var button := child as Button
        if button == null:
            continue
        var destination := String(button.get_meta("destination", ""))
        if not DESTINATIONS.has(destination):
            continue
        button.pressed.connect(_on_destination_pressed.bind(destination))
    set_active_destination(_active_destination)


func set_active_destination(destination: String) -> void:
    if not DESTINATIONS.has(destination):
        return
    _active_destination = destination
    for child: Node in $Margin/Row.get_children():
        var button := child as Button
        if button != null:
            button.button_pressed = String(button.get_meta("destination", "")) == destination


func active_destination() -> String:
    return _active_destination


func _on_destination_pressed(destination: String) -> void:
    set_active_destination(destination)
    destination_requested.emit(destination)
