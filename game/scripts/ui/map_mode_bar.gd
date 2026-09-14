class_name MapModeBar
extends PanelContainer

signal map_mode_requested(mode: String)
signal drawer_requested(drawer: String)

const MAP_MODES := ["political", "terrain", "economy", "military", "roads"]
const DRAWERS := ["orders", "notifications", "turn_report"]

var _active_mode := "political"


func _ready() -> void:
    for child: Node in $Margin/Row.get_children():
        var button := child as Button
        if button == null:
            continue
        var mode := String(button.get_meta("map_mode", ""))
        var drawer := String(button.get_meta("drawer", ""))
        if MAP_MODES.has(mode):
            button.pressed.connect(_on_map_mode_pressed.bind(mode))
        elif DRAWERS.has(drawer):
            button.pressed.connect(_on_drawer_pressed.bind(drawer))
    set_active_mode(_active_mode)


func set_counts(pending_orders: int, notifications: int) -> void:
    $Margin/Row/PendingOrders.text = "待执行订单 %d" % pending_orders
    $Margin/Row/Notifications.text = "通知 %d" % notifications


func set_active_mode(mode: String) -> void:
    if not MAP_MODES.has(mode):
        return
    _active_mode = mode
    for child: Node in $Margin/Row.get_children():
        var button := child as Button
        if button != null and MAP_MODES.has(String(button.get_meta("map_mode", ""))):
            button.button_pressed = String(button.get_meta("map_mode", "")) == mode


func _on_map_mode_pressed(mode: String) -> void:
    set_active_mode(mode)
    map_mode_requested.emit(mode)


func _on_drawer_pressed(drawer: String) -> void:
    drawer_requested.emit(drawer)
