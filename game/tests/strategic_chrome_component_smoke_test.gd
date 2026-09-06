extends SceneTree


func _initialize() -> void:
    var status := (load("res://scenes/ui/global_status_bar.tscn") as PackedScene).instantiate()
    var navigation := (load("res://scenes/ui/primary_navigation.tscn") as PackedScene).instantiate()
    var mode_bar := (load("res://scenes/ui/map_mode_bar.tscn") as PackedScene).instantiate()
    root.add_child(status)
    root.add_child(navigation)
    root.add_child(mode_bar)
    status.set_snapshot({
        "name": "奥罗里亚", "treasury": 10300, "fiscal_income": 3150,
        "last_maintenance_charge": 500, "recruitable_population": 3400,
    }, {"year": 1000, "month": 1})
    mode_bar.set_counts(4, 2)
    navigation.set_active_destination("map")
    if status.get_node("Margin/Row/CountryName").text != "奥罗里亚" or \
            status.get_node("Margin/Row/AdvanceTurn").text != "进入下一回合" or \
            mode_bar.get_node("Margin/Row/PendingOrders").text != "待执行订单 4" or \
            navigation.active_destination() != "map":
        push_error("Strategic chrome components lost their stable presentation")
        quit(1)
        return
    print("Strategic chrome component smoke test passed")
    quit(0)
