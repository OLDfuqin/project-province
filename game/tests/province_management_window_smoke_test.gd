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


func _expected_treasury(main_scene: Control, value: int) -> String:
    return "国库 %d" % value


func _click_at(position: Vector2, viewport: Viewport = root) -> void:
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.position = position
        event.pressed = pressed
        viewport.push_input(event)
        await process_frame


func _activate(button: Button) -> void:
    button.grab_focus()
    for pressed: bool in [true, false]:
        var event := InputEventKey.new()
        event.keycode = KEY_ENTER
        event.pressed = pressed
        button.get_viewport().push_input(event)
        await process_frame


func _initialize() -> void:
    root.size = Vector2i(1280, 720)
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

    var tab_bar := (management.get_node("Tabs") as TabContainer).get_tab_bar()
    await _click_at(tab_bar.global_position + tab_bar.get_tab_rect(1).get_center())
    if management.active_tab() != "military" or not recruit.is_visible_in_tree():
        _fail(main_scene, "Real TabBar input did not expose the military actions")
        return
    await _activate(recruit)
    var amount := management.get_node("Tabs/Military/Recruitment/Amount") as SpinBox
    amount.value = amount.max_value + 1
    await _activate(management.get_node("Tabs/Military/Recruitment/Buttons/Confirm"))
    var status := management.find_child("Status", true, false) as Label
    var inspector_scroll := main_scene.get_node(
        "Shell/Layout/MainRow/ContextInspector/Body/ScrollContainer"
    ) as ScrollContainer
    var visible_status_rect := status.get_global_rect().intersection(
        inspector_scroll.get_global_rect()
    )
    if not bridge.get_pending_orders("auroria").is_empty() or \
            not status.text.contains("招募失败") or not status.is_visible_in_tree() or \
            visible_status_rect.size != status.get_global_rect().size:
        _fail(main_scene, "Military recruitment refusal was not visible in the active tab")
        return
    for index: int in [2, 3, 0, 1]:
        await _click_at(tab_bar.global_position + tab_bar.get_tab_rect(index).get_center())
        if (management.get_node("Tabs") as TabContainer).current_tab != index or \
                not status.is_visible_in_tree() or not status.text.contains("招募失败"):
            _fail(main_scene, "Shared province feedback disappeared after real TabBar input")
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
    var treasury := main_scene.get_node(
        "Shell/Layout/GlobalStatusBar/Margin/Row/Treasury"
    ) as Label
    var research_treasury := 0
    for country: Dictionary in bridge.get_country_summaries():
        if country.get("id", "") == "auroria":
            research_treasury = int(country.get("treasury", 0))
            break
    if research_orders.size() != 1 or String(research_orders[0].get("type", "")) != "research" or \
            treasury.text != _expected_treasury(main_scene, research_treasury):
        _fail(main_scene, "Technology page did not submit the research intent through main")
        return
    main_scene.get_node("Shell/Layout/MapModeBar/Margin/Row/PendingOrders").pressed.emit()
    await process_frame
    var research_cancel := main_scene.get_node(
        "Shell/BottomDrawer/Panel/Body/Orders/Rows/Order0/Cancel"
    ) as Button
    research_cancel.pressed.emit()
    await process_frame
    var confirmation := main_scene.get_node("Shell/ActionConfirmation") as ConfirmationDialog
    if not confirmation.visible or not confirmation.dialog_text.contains("已开始则不退款"):
        _fail(main_scene, "Research cancellation did not explain its refund loss before commit")
        return
    confirmation.canceled.emit()
    await process_frame
    if bridge.get_pending_orders("auroria").size() != 1:
        _fail(main_scene, "Dismissing research cancellation changed the pending order")
        return
    research_cancel.pressed.emit()
    await process_frame
    confirmation.confirmed.emit()
    await process_frame
    var cancelled_treasury := 0
    for country: Dictionary in bridge.get_country_summaries():
        if country.get("id", "") == "auroria":
            cancelled_treasury = int(country.get("treasury", 0))
            break
    if not bridge.get_pending_orders("auroria").is_empty() or \
            not main_scene._latest_event_message.contains("退款5000") or \
            not main_scene.get_node("Shell/BottomDrawer/Panel/Body/Orders/Rows/Empty").visible or \
            treasury.text != _expected_treasury(main_scene, cancelled_treasury):
        _fail(main_scene, "Research cancellation did not clear the drawer or refresh its treasury")
        return
    main_scene.call("_on_cancel_order_pressed", "missing_order")
    await process_frame
    if main_scene.active_drawer_name() != "notifications" or \
            not main_scene.get_node(
                "Shell/BottomDrawer/Panel/Body/Notifications/NotificationText"
            ).text.contains("取消订单失败"):
        _fail(main_scene, "Rejected order cancellation did not show a visible notification")
        return
    main_scene.get_node("Shell/BottomDrawer/Panel/Body/Header/Close").pressed.emit()
    main_scene.get_node("Shell/Layout/MainRow/PrimaryNavigation/Margin/Row/Map").pressed.emit()
    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame

    var recruitment_quote: Dictionary = main_scene.call(
        "_authoritative_recruitment_quote", "capital_auroria"
    )
    var maximum_manpower := int(recruitment_quote.get("maximum_manpower", 0))
    if not recruitment_quote.get("accepted", false) or maximum_manpower <= 0:
        _fail(main_scene, "Could not obtain the authoritative maximum recruitment quote")
        return
    recruit.pressed.emit()
    management.get_node("Tabs/Military/Recruitment/Amount").value = maximum_manpower
    management.get_node("Tabs/Military/Recruitment/Buttons/Confirm").pressed.emit()
    await process_frame
    var recruitment_treasury := 0
    for country: Dictionary in bridge.get_country_summaries():
        if country.get("id", "") == "auroria":
            recruitment_treasury = int(country.get("treasury", 0))
            break
    if bridge.get_pending_orders("auroria").size() != 1 or \
            treasury.text != _expected_treasury(main_scene, recruitment_treasury) or \
            not management.get_node("Tabs/Military/Recruitment/Pending").text.contains(
                "预留%d人" % maximum_manpower
            ):
        _fail(main_scene, "Recruitment did not refresh the pending order and authoritative treasury")
        return

    main_scene.get_node("Shell/Layout/MapModeBar/Margin/Row/PendingOrders").pressed.emit()
    await process_frame
    var recruitment_cancel := main_scene.get_node(
        "Shell/BottomDrawer/Panel/Body/Orders/Rows/Order0/Cancel"
    ) as Button
    recruitment_cancel.pressed.emit()
    await process_frame
    var restored_quote: Dictionary = main_scene.call(
        "_authoritative_recruitment_quote", "capital_auroria"
    )
    if main_scene.workspace_mode_name() != "province_management" or \
            main_scene.get_node("Shell/Layout/MainRow/ContextInspector").current_mode() != \
                "province_management" or not management.visible or \
            not bridge.get_pending_orders("auroria").is_empty() or \
            not main_scene.get_node("Shell/BottomDrawer/Panel/Body/Orders/Rows/Empty").visible or \
            recruit.disabled or not management._recruitment_quote.get("accepted", false) or \
            int(management._recruitment_quote.get("maximum_manpower", 0)) != \
                int(restored_quote.get("maximum_manpower", 0)):
        _fail(main_scene, "Cancelled recruitment did not restore the active management quote")
        return
    recruit.pressed.emit()
    var restored_amount := management.get_node("Tabs/Military/Recruitment/Amount") as SpinBox
    if int(restored_amount.max_value) != int(restored_quote.get("maximum_manpower", 0)):
        _fail(main_scene, "Cancelled recruitment did not restore the recruitment button quote")
        return
    var follow_up_manpower := mini(500, int(restored_quote.get("maximum_manpower", 0)))
    restored_amount.value = follow_up_manpower
    management.get_node("Tabs/Military/Recruitment/Buttons/Confirm").pressed.emit()
    await process_frame
    if bridge.get_pending_orders("auroria").size() != 1 or \
            not management.get_node("Tabs/Military/Recruitment/Pending").text.contains(
                "预留%d人" % follow_up_manpower
            ):
        _fail(main_scene, "Recruitment could not be initiated again after its refund")
        return
    main_scene.get_node("Shell/BottomDrawer/Panel/Body/Header/Close").pressed.emit()
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
