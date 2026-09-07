class_name BottomDrawer
extends Control


signal cancel_order_requested(order_id: String)

var _drawer := "closed"
var _province_by_id: Dictionary = {}
var _country_by_id: Dictionary = {}


func _ready() -> void:
    %Close.pressed.connect(close)
    _set_drawer("closed")


func show_orders(orders: Array) -> void:
    _set_drawer("orders")
    _clear_order_rows()
    for index: int in orders.size():
        var order: Dictionary = orders[index]
        $Panel/Body/Orders/Rows.add_child(_create_order_row(index, order))
    $Panel/Body/Orders/Rows/Empty.visible = orders.is_empty()


func set_order_lookups(province_by_id: Dictionary, country_by_id: Dictionary) -> void:
    _province_by_id = province_by_id.duplicate(true)
    _country_by_id = country_by_id.duplicate(true)


func show_notifications(messages: Array[String]) -> void:
    _set_drawer("notifications")
    %NotificationText.text = "当前没有通知" if messages.is_empty() else "\n".join(messages)


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
        if row.name == "Empty":
            continue
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
    description.text = GameTextFormatter.pending_order_text(
        order, _order_provinces(order), _country_by_id
    )
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
    var provinces := _province_by_id.duplicate(true)
    var fallback_name := String(order.get("province_name", ""))
    if fallback_name.is_empty():
        return provinces
    var province_id := String(order.get("province_id", ""))
    if not province_id.is_empty() and not provinces.has(province_id):
        provinces[province_id] = {"name": fallback_name}
    elif province_id.is_empty() and not provinces.has("?"):
        provinces["?"] = {"name": fallback_name}
    return provinces


func _on_cancel_pressed(cancel: Button) -> void:
    var order_id := String(cancel.get_meta("order_id", ""))
    if not order_id.is_empty():
        cancel_order_requested.emit(order_id)
