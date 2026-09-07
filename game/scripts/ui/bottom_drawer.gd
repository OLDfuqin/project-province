class_name BottomDrawer
extends Control


signal cancel_order_requested(order_id: String)

var _drawer := "closed"


func _ready() -> void:
    %Close.pressed.connect(close)
    _set_drawer("closed")


func show_orders(orders: Array) -> void:
    _set_drawer("orders")
    _clear_order_rows()
    for index: int in orders.size():
        var order: Dictionary = orders[index]
        $Panel/Body/Orders/Rows.add_child(_create_order_row(index, order))
    $Panel/Body/Orders/Empty.visible = orders.is_empty()


func show_notifications(messages: Array[String]) -> void:
    _set_drawer("notifications")
    %NotificationText.text = "\n".join(messages)


func show_turn_report(report_text: String) -> void:
    _set_drawer("turn_report")
    %TurnReportText.text = report_text


func close() -> void:
    _set_drawer("closed")


func current_drawer() -> String:
    return _drawer


func _set_drawer(drawer: String) -> void:
    _drawer = drawer
    visible = drawer != "closed"
    %Orders.visible = drawer == "orders"
    %Notifications.visible = drawer == "notifications"
    %TurnReportSection.visible = drawer == "turn_report"
    %Title.text = {
        "orders": "待执行订单",
        "notifications": "通知",
        "turn_report": "回合报告",
    }.get(drawer, "战略信息")


func _clear_order_rows() -> void:
    var rows := $Panel/Body/Orders/Rows
    for row: Node in rows.get_children():
        rows.remove_child(row)
        row.queue_free()


func _create_order_row(index: int, order: Dictionary) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.name = "Order%d" % index
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_theme_constant_override("separation", 12)

    var description := Label.new()
    description.name = "Description"
    description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    description.text = GameTextFormatter.pending_order_text(order, _order_provinces(order))
    row.add_child(description)

    var cancel := Button.new()
    cancel.name = "Cancel"
    cancel.text = "取消"
    cancel.tooltip_text = "请求取消此订单"
    cancel.set_meta("order_id", String(order.get("order_id", "")))
    cancel.pressed.connect(_on_cancel_pressed.bind(cancel))
    row.add_child(cancel)
    return row


func _order_provinces(order: Dictionary) -> Dictionary:
    var provinces := {}
    var fallback_name := String(order.get("province_name", "未知地区"))
    provinces["?"] = {"name": fallback_name}
    for key: String in ["province_id", "destination", "province_a", "province_b"]:
        var province_id := String(order.get(key, ""))
        if province_id != "":
            provinces[province_id] = {"name": fallback_name}
    return provinces


func _on_cancel_pressed(cancel: Button) -> void:
    cancel_order_requested.emit(String(cancel.get_meta("order_id", "")))
