extends SceneTree


func _initialize() -> void:
    var drawer := (load("res://scenes/ui/bottom_drawer.tscn") as PackedScene).instantiate()
    root.add_child(drawer)
    var observed := {"cancelled": ""}
    drawer.cancel_order_requested.connect(
        func(order_id: String) -> void: observed["cancelled"] = order_id
    )
    drawer.show_orders([{
        "order_id": "order_4", "order_type": "recruitment",
        "province_name": "北境", "manpower": 100, "remaining_months": 1,
    }])
    if drawer.current_drawer() != "orders" or not drawer.visible:
        push_error("Order drawer did not open")
        quit(1)
        return
    if "北境" not in drawer.get_node("Panel/Body/Orders/Rows/Order0/Description").text:
        push_error("Order drawer did not preserve the authoritative province name")
        quit(1)
        return
    drawer.get_node("Panel/Body/Orders/Rows/Order0/Cancel").pressed.emit()
    if observed["cancelled"] != "order_4":
        push_error("Order drawer did not emit the stable order ID")
        quit(1)
        return
    drawer.show_turn_report("财政收入：3150")
    if drawer.current_drawer() != "turn_report" or \
            drawer.get_node("Panel/Body/Orders").visible:
        push_error("Bottom drawers were not mutually exclusive")
        quit(1)
        return
    print("Bottom drawer smoke test passed")
    quit(0)
