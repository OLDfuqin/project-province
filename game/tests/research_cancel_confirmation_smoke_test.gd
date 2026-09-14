extends SceneTree


func _treasury(bridge: Object) -> int:
    for country: Dictionary in bridge.get_country_summaries():
        if String(country.get("id", "")) == "auroria":
            return int(country.get("treasury", 0))
    return 0


func _fail(scene: Control, message: String) -> void:
    push_error(message)
    scene.free()
    quit(1)


func _initialize() -> void:
    root.size = Vector2i(1280, 720)
    var scene := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
    root.add_child(scene)
    await process_frame
    var bridge := scene.get_node("SimulationBridge")

    scene.get_node("Shell/Layout/MainRow/PrimaryNavigation/Margin/Row/Technology").pressed.emit()
    await process_frame
    scene.get_node("Shell/ManagementPageHost/Pages/Technology/Content/Tracks/Economy/Research").pressed.emit()
    await process_frame
    scene.get_node("Shell/Layout/GlobalStatusBar/Margin/Row/AdvanceTurn").pressed.emit()
    await process_frame
    var orders: Array = bridge.get_pending_orders("auroria")
    if orders.size() != 1 or int(orders[0].get("remaining_months", 0)) != 1:
        _fail(scene, "Could not prepare a progressed research order")
        return
    var treasury_before := _treasury(bridge)

    scene.get_node("Shell/Layout/MapModeBar/Margin/Row/PendingOrders").pressed.emit()
    await process_frame
    scene.get_node("Shell/BottomDrawer/Panel/Body/Orders/Rows/Order0/Cancel").pressed.emit()
    await process_frame
    var confirmation := scene.get_node("Shell/ActionConfirmation") as ConfirmationDialog
    if not confirmation.visible or not confirmation.dialog_text.contains("已开始则不退款") or \
            bridge.get_pending_orders("auroria").size() != 1 or _treasury(bridge) != treasury_before:
        _fail(scene, "Progressed research changed before its loss confirmation")
        return
    confirmation.confirmed.emit()
    await process_frame
    if not bridge.get_pending_orders("auroria").is_empty() or \
            _treasury(bridge) != treasury_before or not scene._latest_event_message.contains("无退款"):
        _fail(scene, "Confirmed progressed research cancellation did not preserve the no-refund rule")
        return

    print("Research cancellation confirmation smoke test passed")
    scene.free()
    quit(0)
