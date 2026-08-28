extends SceneTree


func _army(bridge: Object, army_id: String) -> Dictionary:
    for summary: Dictionary in bridge.get_army_summaries():
        if summary.get("id", "") == army_id:
            return summary
    return {}


func _pending_rows(main_scene: Node) -> Array[Node]:
    var rows: Array[Node] = []
    for child: Node in main_scene.get_node(
        "RightPanel/Center/PendingOrders/Content/OrderList/Orders"
    ).get_children():
        rows.append(child)
    return rows


func _pending_row(main_scene: Node, order_type: String) -> Control:
    for row: Node in _pending_rows(main_scene):
        if row.get_meta("order_type", "") == order_type:
            return row as Control
    return null


func _fail(main_scene: Node, message: String) -> void:
    push_error(message)
    main_scene.free()
    quit(1)


func _initialize() -> void:
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Main scene could not be loaded for province management testing")
        quit(1)
        return

    var main_scene := packed_scene.instantiate() as Control
    root.add_child(main_scene)
    await process_frame

    var bridge := main_scene.get_node("SimulationBridge")
    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    var management := main_scene.get_node_or_null(
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow"
    ) as Control
    var advance_turn := main_scene.get_node(
        "TurnBar/TurnControls/AdvanceTurn"
    ) as Button
    if management == null:
        _fail(main_scene, "Province management window was not embedded in the workspace")
        return

    province_map.province_double_clicked.emit("capital_auroria")
    var recruit := management.get_node("Recruitment/Open") as Button
    var army_selector := management.get_node("ArmySelector") as OptionButton
    var reachable := management.get_node("ReachableDestination") as OptionButton
    var move_army := management.get_node("ArmyActions/MoveArmy") as Button
    if main_scene.workspace_mode_name() != "province_management" or \
            not management.visible or \
            management.get_node("ProvinceName").text != "奥罗里亚首都" or \
            recruit.disabled or army_selector.item_count != 0 or \
            not management.get_node("Placeholders/EconomyInvestment").disabled or \
            not management.get_node("Placeholders/CivilInvestment").disabled or \
            not management.get_node("Placeholders/BuildingManagement").disabled:
        _fail(main_scene, "Province management window did not show the initial province state")
        return

    var technology_status := management.get_node("Technology/Status") as Label
    var technology_pending := management.get_node("Technology/Pending") as Label
    var economy_research := management.get_node(
        "Technology/Buttons/Economy"
    ) as Button
    if not technology_status.text.contains("经济 0"):
        _fail(main_scene, "Management page did not display technology")
        return
    economy_research.pressed.emit()
    await process_frame
    var research_orders: Array = bridge.get_pending_orders("auroria")
    var research_row := _pending_row(main_scene, "research")
    if research_orders.size() != 1 or research_orders[0].get("type", "") != "research" or \
            research_orders[0].get("remaining_months", 0) != 2 or \
            not technology_status.text.contains("经济 0") or \
            not technology_pending.text.contains("经济 → 1") or \
            not technology_pending.text.contains("剩余2个月") or \
            research_row == null or \
            not (research_row.get_node("Description") as Label).text.contains("预付5000"):
        _fail(main_scene, "Technology did not create and display a delayed research order")
        return

    (research_row.get_node("Cancel") as Button).pressed.emit()
    await process_frame
    if not bridge.get_pending_orders("auroria").is_empty() or \
            not main_scene.get_node("RightPanel/Center/EventLog").text.contains("退款5000"):
        _fail(main_scene, "Pending research could not be cancelled with its prepayment refunded")
        return

    recruit.pressed.emit()
    management.get_node("Recruitment/Amount").value = 500
    management.get_node("Recruitment/Buttons/Confirm").pressed.emit()
    await process_frame
    var recruitment_orders: Array = bridge.get_pending_orders("auroria")
    var recruitment_row := _pending_row(main_scene, "recruitment")
    if army_selector.item_count != 0 or recruitment_orders.size() != 1 or \
            recruitment_orders[0].get("type", "") != "recruitment" or \
            recruitment_orders[0].get("remaining_months", 0) != 1 or \
            recruitment_row == null or \
            not (recruitment_row.get_node("Description") as Label).text.contains("预付2000") or \
            not management.get_node("Recruitment/Pending").text.contains("预留500人") or \
            not management.get_node("Status").text.contains("订单已创建"):
        _fail(main_scene, "Recruitment did not stay pending for one month")
        return

    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    province_map.province_double_clicked.emit("capital_auroria")
    if army_selector.item_count != 1 or \
            not bridge.get_pending_orders("auroria").is_empty() or \
            not main_scene.get_node("RightPanel/Center/EventHistory").text.contains("征兵订单完成"):
        _fail(main_scene, "Recruitment order did not complete in the next project phase")
        return

    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    province_map.province_double_clicked.emit("capital_auroria")
    if army_selector.item_count != 1 or reachable.item_count <= 1:
        _fail(main_scene, "Completed army did not expose authoritative reachable targets")
        return

    var army_id := String(army_selector.get_selected_metadata())
    var origin_id: String = _army(bridge, army_id).get("province_id", "")
    var movement_before: float = float(_army(bridge, army_id).get("movement_points", 0.0))
    var target: Dictionary = reachable.get_item_metadata(1)
    var destination_id: String = target.get("province_id", "")
    reachable.get_popup().index_pressed.emit(1)
    if move_army.disabled or \
            not management.get_node("DirectDestination").text.contains(
                target.get("province_name", destination_id)
            ):
        _fail(main_scene, "Reachable destination selection did not prepare an order")
        return

    var saved_advance_target: Dictionary = bridge.set_army_advance_target(
        army_id, destination_id
    )
    if not saved_advance_target.get("accepted", false):
        _fail(main_scene, "Could not prepare the saved advance target regression")
        return
    main_scene.auto_advance_target_id = destination_id
    province_map.province_double_clicked.emit(destination_id)
    await process_frame
    if not main_scene.moving_army_id.is_empty() or \
            not main_scene.movement_origin_id.is_empty() or \
            not main_scene.movement_destination_id.is_empty() or \
            not main_scene.auto_advance_target_id.is_empty() or \
            main_scene.map_input_mode_name() != "normal" or \
            String(_army(bridge, army_id).get("advance_target_id", "")) != \
            destination_id or \
            reachable.item_count != 1 or not reachable.disabled or \
            not move_army.disabled or \
            not management.get_node("AdvanceActions/AdvanceNow").disabled:
        _fail(main_scene, "Opening a province without a player army retained stale army state")
        return

    province_map.province_double_clicked.emit(origin_id)
    await process_frame
    target = reachable.get_item_metadata(1)
    destination_id = String(target.get("province_id", ""))
    reachable.get_popup().index_pressed.emit(1)

    move_army.pressed.emit()
    await process_frame
    var movement_row := _pending_row(main_scene, "army_action")
    if _army(bridge, army_id).get("province_id", "") != origin_id or \
            movement_row == null or \
            not (movement_row.get_node("Description") as Label).text.contains("预留移动") or \
            not management.get_node("Status").text.contains("订单已创建"):
        _fail(main_scene, "Army movement happened immediately instead of being queued")
        return

    (movement_row.get_node("Cancel") as Button).pressed.emit()
    await process_frame
    if not bridge.get_pending_orders("auroria").is_empty() or \
            not is_equal_approx(
                float(_army(bridge, army_id).get("movement_points", 0.0)),
                movement_before
            ) or \
            not main_scene.get_node("RightPanel/Center/EventLog").text.contains("退还移动"):
        _fail(main_scene, "Cancelling a movement order did not restore reserved movement")
        return

    reachable.get_popup().index_pressed.emit(1)
    move_army.pressed.emit()
    await process_frame
    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    if _army(bridge, army_id).get("province_id", "") != destination_id or \
            not main_scene.get_node("RightPanel/Center/EventHistory").text.contains("调动订单完成"):
        _fail(main_scene, "Queued movement did not resolve on the following month")
        return

    print("Province management window monthly order smoke test passed")
    main_scene.free()
    quit(0)
