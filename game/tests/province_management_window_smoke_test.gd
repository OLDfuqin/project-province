extends SceneTree


func _army(bridge: Object, army_id: String) -> Dictionary:
    for summary: Dictionary in bridge.get_army_summaries():
        if String(summary.get("id", "")) == army_id:
            return summary
    return {}


func _fail(main_scene: Node, message: String) -> void:
    push_error(message)
    main_scene.free()
    quit(1)


func _initialize() -> void:
    var main_scene := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
    root.add_child(main_scene)
    await process_frame
    var bridge := main_scene.get_node("SimulationBridge")
    var province_map := main_scene.get_node("Shell/Layout/MainRow/MapPanel/ProvinceMap")
    var management := main_scene.province_management_window as Control
    var advance_turn := main_scene.get_node(
        "Shell/Layout/GlobalStatusBar/Margin/Row/AdvanceTurn"
    ) as Button
    if management == null:
        _fail(main_scene, "Province management was not created for the context inspector")
        return

    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame
    var recruit := management.get_node("Tabs/Military/Recruitment/Open") as Button
    var selector := management.get_node("Tabs/Military/ArmySelector") as OptionButton
    if main_scene.workspace_mode_name() != "province_management" or \
            main_scene.get_node("Shell/Layout/MainRow/ContextInspector").current_mode() != "province_management" or \
            not management.visible or recruit.disabled or selector.item_count != 0 or \
            management.get_node_or_null("Tabs/TechnologyLegacy") != null:
        _fail(main_scene, "Province management did not use its final inspector-only contract")
        return

    main_scene.get_node("Shell/Layout/MainRow/PrimaryNavigation/Margin/Row/Technology").pressed.emit()
    await process_frame
    var technology := main_scene.get_node("Shell/ManagementPageHost/Pages/Technology")
    var research := technology.get_node("Content/Tracks/Economy/Research") as Button
    if research.disabled:
        _fail(main_scene, "Authoritative technology page did not enable affordable research")
        return
    research.pressed.emit()
    await process_frame
    var research_orders: Array = bridge.get_pending_orders("auroria")
    if research_orders.size() != 1 or String(research_orders[0].get("type", "")) != "research":
        _fail(main_scene, "Technology page did not submit the research intent through main")
        return
    main_scene.get_node("Shell/Layout/MapModeBar/Margin/Row/PendingOrders").pressed.emit()
    await process_frame
    var research_cancel := main_scene.get_node(
        "Shell/BottomDrawer/Panel/Body/Orders/Rows/Order0/Cancel"
    ) as Button
    research_cancel.pressed.emit()
    await process_frame
    if not bridge.get_pending_orders("auroria").is_empty() or \
            not main_scene._latest_event_message.contains("退款5000"):
        _fail(main_scene, "Research cancellation was not routed through the bottom drawer")
        return
    main_scene.get_node("Shell/BottomDrawer/Panel/Body/Header/Close").pressed.emit()
    main_scene.get_node("Shell/Layout/MainRow/PrimaryNavigation/Margin/Row/Map").pressed.emit()
    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame

    recruit.pressed.emit()
    management.get_node("Tabs/Military/Recruitment/Amount").value = 500
    management.get_node("Tabs/Military/Recruitment/Buttons/Confirm").pressed.emit()
    await process_frame
    if bridge.get_pending_orders("auroria").size() != 1 or \
            not management.get_node("Tabs/Military/Recruitment/Pending").text.contains("预留500人"):
        _fail(main_scene, "Recruitment did not remain a pending authoritative order")
        return
    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    if selector.item_count != 1 or not bridge.get_pending_orders("auroria").is_empty():
        _fail(main_scene, "Recruitment order did not resolve on the next month")
        return

    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame
    var reachable := management.get_node("Tabs/Military/ReachableDestination") as OptionButton
    var move_army := management.get_node("Tabs/Military/ArmyActions/MoveArmy") as Button
    if selector.item_count != 1 or reachable.item_count <= 1:
        _fail(main_scene, "Completed army did not expose bridge-authorized movement targets")
        return
    var army_id := String(selector.get_selected_metadata())
    var origin_id := String(_army(bridge, army_id).get("province_id", ""))
    var target: Dictionary = reachable.get_item_metadata(1)
    var destination_id := String(target.get("province_id", ""))
    reachable.get_popup().index_pressed.emit(1)
    move_army.pressed.emit()
    await process_frame
    if String(_army(bridge, army_id).get("province_id", "")) != origin_id or \
            bridge.get_pending_orders("auroria").is_empty():
        _fail(main_scene, "Movement was not retained as a delayed order")
        return
    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    if String(_army(bridge, army_id).get("province_id", "")) != destination_id:
        _fail(main_scene, "Queued movement did not resolve in the monthly military phase")
        return

    print("Province management strategic integration smoke test passed")
    main_scene.free()
    quit(0)
