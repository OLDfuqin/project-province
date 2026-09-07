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

    drawer.set_order_lookups(
        {
            "north": {"name": "北境"},
            "south": {"name": "南境"},
            "east": {"name": "东境"},
        },
        {"country_2": {"name": "北方联盟"}},
    )
    drawer.show_orders([{
        "order_id": "road_1", "type": "road_construction",
        "province_a": "north", "province_b": "south",
        "remaining_months": 2, "paid_cost": 10,
    }, {
        "order_id": "move_1", "type": "army_action",
        "destination": "east", "remaining_months": 1,
    }])
    var road_text: String = drawer.get_node(
        "Panel/Body/Orders/Rows/Order0/Description"
    ).text
    if road_text.find("北境") == -1 or road_text.find("南境") == -1:
        push_error("Road order did not preserve distinct endpoint names")
        quit(1)
        return
    var move_text: String = drawer.get_node(
        "Panel/Body/Orders/Rows/Order1/Description"
    ).text
    if move_text.find("东境") == -1:
        push_error("Army order did not use the authoritative destination name")
        quit(1)
        return

    drawer.show_orders([{
        "order_id": "war_1", "type": "war_declaration",
        "defender_id": "country_2", "remaining_months": 1,
    }])
    var war_text: String = drawer.get_node(
        "Panel/Body/Orders/Rows/Order0/Description"
    ).text
    if war_text.find("北方联盟") == -1 or war_text.find("country_2") != -1:
        push_error("War order leaked a raw defender country ID")
        quit(1)
        return
    drawer.show_orders([{
        "order_id": "war_2", "type": "war_declaration",
        "defender_id": "country_missing", "remaining_months": 1,
    }])
    var unknown_war_text: String = drawer.get_node(
        "Panel/Body/Orders/Rows/Order0/Description"
    ).text
    if unknown_war_text.find("未知国家") == -1 or \
            unknown_war_text.find("country_missing") != -1:
        push_error("Missing war lookup leaked a raw country ID")
        quit(1)
        return

    drawer.show_orders([{"order_id": "", "type": "recruitment"}])
    var cancel_count := {"value": 0}
    drawer.cancel_order_requested.connect(
        func(_order_id: String) -> void: cancel_count["value"] += 1
    )
    drawer.get_node("Panel/Body/Orders/Rows/Order0/Cancel").pressed.emit()
    if cancel_count["value"] != 0:
        push_error("Empty order ID emitted a cancellation")
        quit(1)
        return
    drawer.show_orders([{"type": "recruitment"}])
    drawer.get_node("Panel/Body/Orders/Rows/Order0/Cancel").pressed.emit()
    if cancel_count["value"] != 0:
        push_error("Missing order ID emitted a cancellation")
        quit(1)
        return

    var empty_messages: Array[String] = []
    drawer.show_notifications(empty_messages)
    if drawer.get_node("Panel/Body/Notifications/NotificationText").text != "当前没有通知":
        push_error("Empty notifications did not use the Chinese empty state")
        quit(1)
        return
    for scroll_path: String in [
        "Panel/Body/Orders", "Panel/Body/Notifications",
        "Panel/Body/TurnReportSection",
    ]:
        if drawer.get_node(scroll_path) is not ScrollContainer:
            push_error("Drawer content is not vertically scrollable: %s" % scroll_path)
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
