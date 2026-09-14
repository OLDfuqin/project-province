extends SceneTree


func _initialize() -> void:
    var status := (load("res://scenes/ui/global_status_bar.tscn") as PackedScene).instantiate()
    var navigation := (load("res://scenes/ui/primary_navigation.tscn") as PackedScene).instantiate()
    var mode_bar := (load("res://scenes/ui/map_mode_bar.tscn") as PackedScene).instantiate()
    root.add_child(status)
    root.add_child(navigation)
    root.add_child(mode_bar)
    await process_frame
    status.set_snapshot({
        "name": "奥罗里亚", "treasury": 10300, "fiscal_income": 3150,
        "last_maintenance_charge": 500, "recruitable_population": 3400,
    }, {"year": 1000, "month": 1})
    status.set_compact(true)
    status.set_snapshot({
        "name": "奥罗里亚", "treasury": 10400, "fiscal_income": 3200,
        "last_maintenance_charge": 600, "recruitable_population": 3300,
    }, {"year": 1000, "month": 2})
    mode_bar.set_counts(4, 2)
    navigation.set_active_destination("map")
    if status.get_node("Margin/Row/CountryName").text != "奥罗里亚" or \
            status.get_node("Margin/Row/AdvanceTurn").text != "进入下一回合" or \
            mode_bar.get_node("Margin/Row/PendingOrders").text != "待执行订单 4" or \
            navigation.active_destination() != "map":
        push_error("Strategic chrome components lost their stable presentation")
        quit(1)
        return
    for compact_metric: Dictionary in [
        {"node": "Treasury", "text": "国 10400"},
        {"node": "Income", "text": "收 3200"},
        {"node": "Maintenance", "text": "维 600"},
        {"node": "Recruitable", "text": "招 3300"},
    ]:
        var metric := status.get_node("Margin/Row/%s" % compact_metric["node"]) as Label
        if not metric.visible or metric.text != compact_metric["text"]:
            push_error("Compact status density did not survive a snapshot refresh")
            quit(1)
            return
    status.set_advance_enabled(false, "当前不可用：存在未解决的回合阻塞")
    var advance := status.get_node("Margin/Row/AdvanceTurn") as Button
    if not advance.disabled or advance.tooltip_text != "当前不可用：存在未解决的回合阻塞":
        push_error("Disabled next-turn action lost its specific reason")
        quit(1)
        return
    status.set_advance_enabled(true)
    if advance.disabled or advance.tooltip_text != "结算当前月并进入下一回合":
        push_error("Re-enabled next-turn action retained a stale disabled tooltip")
        quit(1)
        return

    var navigation_row := navigation.get_node("Margin/Row")
    if navigation.custom_minimum_size.x != 64.0 or \
            not navigation_row is VBoxContainer:
        push_error("Primary navigation must remain a 64px vertical left sidebar")
        quit(1)
        return
    for child: Node in navigation_row.get_children():
        var button := child as Button
        if button == null or button.custom_minimum_size != Vector2(32, 32) or \
                button.text.length() != 1 or button.tooltip_text.is_empty():
            push_error("Primary navigation must use compact Chinese glyph controls")
            quit(1)
            return

    var events := {"destination": "", "map_mode": "", "drawer": ""}
    navigation.destination_requested.connect(func(value: String) -> void:
        events["destination"] = value
    )
    mode_bar.map_mode_requested.connect(func(value: String) -> void:
        events["map_mode"] = value
    )
    mode_bar.drawer_requested.connect(func(value: String) -> void:
        events["drawer"] = value
    )
    (navigation.get_node("Margin/Row/Country") as Button).pressed.emit()
    (mode_bar.get_node("Margin/Row/Terrain") as Button).pressed.emit()
    (mode_bar.get_node("Margin/Row/PendingOrders") as Button).pressed.emit()
    navigation.set_active_destination("not-a-destination")
    mode_bar.set_active_mode("not-a-map-mode")
    if events["destination"] != "country" or \
            navigation.active_destination() != "country" or \
            events["map_mode"] != "terrain" or not (mode_bar.get_node(
                "Margin/Row/Terrain"
            ) as Button).button_pressed or events["drawer"] != "orders":
        push_error("Strategic chrome signals or whitelist rejection are unstable")
        quit(1)
        return

    print("Strategic chrome component smoke test passed")
    quit(0)
