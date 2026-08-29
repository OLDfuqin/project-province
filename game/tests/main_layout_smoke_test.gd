extends SceneTree


func _initialize() -> void:
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Main scene could not be loaded")
        quit(1)
        return

    var main_scene := packed_scene.instantiate() as Control
    root.add_child(main_scene)
    await process_frame

    var known_startup_error := String(main_scene.call(
        "_scenario_load_failure_text", "scenario could not be loaded"
    ))
    var unknown_startup_error := String(main_scene.call(
        "_scenario_load_failure_text", "future startup failure in English"
    ))
    if known_startup_error != "场景加载失败：游戏场景数据无法加载" or \
            unknown_startup_error != "场景加载失败：未知错误":
        push_error("Initial scenario load errors did not use stable Chinese text")
        main_scene.free()
        quit(1)
        return

    var turn_bar := main_scene.get_node_or_null("TurnBar") as Control
    if turn_bar == null or turn_bar.get_parent() != main_scene:
        push_error("Turn controls must be a standalone top bar, not a map child")
        main_scene.free()
        quit(1)
        return

    var removed_turn_length := main_scene.get_node_or_null(
        "TurnBar/TurnControls/TurnLength"
    )
    var fixed_advance_turn := main_scene.get_node_or_null(
        "TurnBar/TurnControls/AdvanceTurn"
    ) as Button
    if removed_turn_length != null or fixed_advance_turn == null or \
            fixed_advance_turn.text != "进入下一回合（1个月）":
        push_error("Turn controls must expose one fixed month and no month selector")
        main_scene.free()
        quit(1)
        return

    var map_panel := main_scene.get_node_or_null("MapPanel") as PanelContainer
    if map_panel == null or map_panel.get_child_count() != 1 or \
            map_panel.get_child(0).name != "ProvinceMap":
        push_error("Map panel must contain only the interactive province map")
        main_scene.free()
        quit(1)
        return

    var right_panel := main_scene.get_node_or_null("RightPanel") as ScrollContainer
    if right_panel == null:
        push_error("Right-side controls must be contained in a scrollable panel")
        main_scene.free()
        quit(1)
        return

    var workspace_panel := main_scene.get_node_or_null(
        "WorkspacePanel"
    ) as PanelContainer
    var road_entry := main_scene.get_node_or_null(
        "RightPanel/Center/RoadConstructionEntry"
    ) as Button
    var legacy_road_controls := main_scene.get_node_or_null(
        "RightPanel/Center/RoadControls"
    ) as Control
    if workspace_panel == null or road_entry == null or \
            legacy_road_controls == null or legacy_road_controls.visible:
        push_error("Main UI did not reserve a workspace and isolate road controls")
        main_scene.free()
        quit(1)
        return

    var pending_order_panel := main_scene.get_node_or_null(
        "RightPanel/Center/PendingOrders"
    ) as PanelContainer
    var pending_order_scroll := main_scene.get_node_or_null(
        "RightPanel/Center/PendingOrders/Content/OrderList"
    ) as ScrollContainer
    var pending_order_rows := main_scene.get_node_or_null(
        "RightPanel/Center/PendingOrders/Content/OrderList/Orders"
    ) as VBoxContainer
    var pending_order_empty := main_scene.get_node_or_null(
        "RightPanel/Center/PendingOrders/Content/Empty"
    ) as Label
    if pending_order_panel == null or pending_order_scroll == null or \
            pending_order_rows == null or pending_order_empty == null or \
            pending_order_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED or \
            pending_order_scroll.custom_minimum_size.y < 120.0 or \
            pending_order_rows.get_child_count() != 0 or not pending_order_empty.visible:
        push_error("Scrollable player-only pending order panel is incomplete")
        main_scene.free()
        quit(1)
        return

    var workspace_scroll := main_scene.get_node_or_null(
        "WorkspacePanel/Workspace/WindowViewport"
    ) as ScrollContainer
    if workspace_scroll == null:
        push_error("Scrollable workspace viewport is missing")
        main_scene.free()
        quit(1)
        return

    var panel_rect := workspace_panel.get_global_rect()
    var viewport_rect := workspace_scroll.get_global_rect()
    if not panel_rect.encloses(viewport_rect) or \
            workspace_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
        push_error("Workspace viewport is outside the panel or allows horizontal overflow")
        main_scene.free()
        quit(1)
        return

    var preserved_controls := [
        "RightPanel/Center/SaveControls/Save",
        "RightPanel/Center/DiplomacyControls/DeclareWar",
        "RightPanel/Center/RoadConstructionEntry",
        "RightPanel/Center/ProvinceSummary",
    ]
    for control_path: String in preserved_controls:
        if main_scene.get_node_or_null(control_path) == null:
            push_error("Existing main control was removed: %s" % control_path)
            main_scene.free()
            quit(1)
            return

    var chinese_labels := {
        "RightPanel/Center/Title": "省域计划",
        "RightPanel/Center/SaveControls/Save": "快速保存",
        "RightPanel/Center/SaveControls/Load": "快速读取",
        "RightPanel/Center/DiplomacyControls/DeclareWar": "宣战",
        "RightPanel/Center/DiplomacyControls/MakePeace": "议和",
    }
    for control_path: String in chinese_labels:
        var control := main_scene.get_node(control_path) as Control
        if control.get("text") != chinese_labels[control_path]:
            push_error("Main control was not translated: %s" % control_path)
            main_scene.free()
            quit(1)
            return

    var peace_policy := main_scene.get_node(
        "RightPanel/Center/DiplomacyControls/PeacePolicy"
    ) as OptionButton
    var country_list := main_scene.get_node("RightPanel/Center/CountryList")
    var bridge := main_scene.get_node("SimulationBridge")
    var country_details := main_scene.get_node(
        "RightPanel/Center/CountryDetails"
    ) as Label
    var war_overview := main_scene.get_node(
        "RightPanel/Center/WarOverview"
    ) as Label
    var country_summaries: Array = bridge.get_country_summaries()
    if country_summaries.size() != 4 or country_list.get_child_count() != 4:
        push_error("Main UI must expose exactly four playable countries")
        main_scene.free()
        quit(1)
        return
    for child: Node in country_list.get_children():
        var country_label := child as Label
        if country_label.text.contains("中立守军") or \
                not country_label.text.contains("经济") or \
                not country_label.text.contains("财政收入") or \
                not country_label.text.contains("维护费") or \
                not country_label.text.contains("负债"):
            push_error("Country summary leaked neutral data or omitted economy fields")
            main_scene.free()
            quit(1)
            return
    if peace_policy.get_item_text(0) != "恢复战前边界" or \
            peace_policy.get_item_text(1) != "吞并占领地区" or \
            not (country_list.get_child(0) as Label).text.contains("国库") or \
            not country_details.text.contains("控制地区") or \
            war_overview.text != "当前无战争":
        push_error("Runtime main-page summaries were not fully translated")
        main_scene.free()
        quit(1)
        return

    var preserved_army_id := ""
    var preserved_origin_id := ""
    var preserved_target_id := ""
    if bridge.get_army_summaries().filter(
        func(army: Dictionary) -> bool:
            return army.get("owner_id", "") == "auroria"
    ).is_empty():
        var prepared_recruit: Dictionary = bridge.recruit_army(
            "auroria", "capital_auroria", 100
        )
        var prepared_turn: Dictionary = bridge.advance_turn()
        if not prepared_recruit.get("accepted", false) or \
                not prepared_turn.get("accepted", false):
            push_error("Could not recruit an army for quick-load fixture")
            main_scene.free()
            quit(1)
            return
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("owner_id", "") == "auroria":
            preserved_army_id = String(army.get("id", ""))
            preserved_origin_id = String(army.get("province_id", ""))
            break
    for province: Dictionary in bridge.get_province_summaries():
        if province.get("id", "") != "" and \
                province.get("id", "") != preserved_origin_id:
            preserved_target_id = String(province.get("id", ""))
            break
    if preserved_army_id.is_empty() or preserved_target_id.is_empty() or \
            not bridge.set_army_advance_target(
                preserved_army_id, preserved_target_id
            ).get("accepted", false):
        push_error("Could not prepare quick-load advance-target fixture")
        main_scene.free()
        quit(1)
        return
    main_scene.moving_army_id = preserved_army_id
    main_scene.get_node("RightPanel/Center/SaveControls/Save").pressed.emit()
    bridge.clear_army_advance_target(preserved_army_id)
    main_scene.get_node("RightPanel/Center/SaveControls/Load").pressed.emit()
    await process_frame
    var restored_target := ""
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("id", "") == preserved_army_id:
            restored_target = String(army.get("advance_target_id", ""))
            break
    if restored_target != preserved_target_id or \
            not main_scene.moving_army_id.is_empty():
        push_error("Quick-load mutated the loaded advance target or kept stale local selection")
        main_scene.free()
        quit(1)
        return

    var removed_controls := [
        "RightPanel/Center/RegionDetails",
        "RightPanel/Center/TechnologyControls",
        "RightPanel/Center/SelectionStatus",
        "RightPanel/Center/ArmyControls",
    ]
    for control_path: String in removed_controls:
        if main_scene.get_node_or_null(control_path) != null:
            push_error("Duplicate main control still exists: %s" % control_path)
            main_scene.free()
            quit(1)
            return

    var management_controls := [
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow/Technology/Buttons/Economy",
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow/Recruitment/Open",
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow/ArmyActions/MoveArmy",
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow/AdvanceActions/AdvanceNow",
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow/AdvancePlans",
    ]
    for control_path: String in management_controls:
        if main_scene.get_node_or_null(control_path) == null:
            push_error("Province management control is missing: %s" % control_path)
            main_scene.free()
            quit(1)
            return

    var province_summary := main_scene.get_node_or_null(
        "RightPanel/Center/ProvinceSummary"
    ) as Label
    var province_summaries: Array = bridge.get_province_summaries()
    var total_population := 0
    for province: Dictionary in province_summaries:
        total_population += int(province.get("population", 0))
    if province_summaries.size() != 69 or province_summary == null or \
            not province_summary.text.contains("总人口 %d" % total_population) or \
            not province_summary.text.contains("可招募士兵"):
        push_error("Main UI did not label the recruitable population")
        main_scene.free()
        quit(1)
        return

    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    province_map.province_clicked.emit("cell_5_5")
    await process_frame
    var info_window := main_scene.get_node(
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceInfoWindow"
    )
    if info_window.get_node("ProvinceName").text != "无主地块(5,5)" or \
            not info_window.get_node("Economy").text.contains("财政收入：0"):
        push_error("Neutral province details did not show its name and zero fiscal income")
        main_scene.free()
        quit(1)
        return
    main_scene.get_node("WorkspacePanel/Workspace/TitleBar/Close").pressed.emit()

    var initial_right_rect := right_panel.get_global_rect()
    var advance_turn := main_scene.get_node(
        "TurnBar/TurnControls/AdvanceTurn"
    ) as Button
    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    var event_log := main_scene.get_node("RightPanel/Center/EventLog") as Label
    if not event_log.text.contains("财政收入"):
        push_error("Turn report did not display total fiscal income")
        main_scene.free()
        quit(1)
        return
    var event_history := main_scene.get_node("RightPanel/Center/EventHistory") as RichTextLabel
    if not event_history.text.contains("维护费"):
        push_error("Turn report did not include the maintenance settlement phase")
        main_scene.free()
        quit(1)
        return
    var updated_right_rect := right_panel.get_global_rect()
    if not initial_right_rect.position.is_equal_approx(updated_right_rect.position) or \
            not initial_right_rect.size.is_equal_approx(updated_right_rect.size) or \
            country_details.size.x > right_panel.size.x + 1.0:
        push_error("Right panel expanded after advancing the turn: before=%s after=%s details_width=%s panel_width=%s" % [
            initial_right_rect,
            updated_right_rect,
            country_details.size.x,
            right_panel.size.x,
        ])
        main_scene.free()
        quit(1)
        return

    var map_rect := map_panel.get_global_rect()
    var turn_rect := turn_bar.get_global_rect()
    var right_rect := updated_right_rect
    var workspace_rect := workspace_panel.get_global_rect()
    if turn_rect.intersects(map_rect) or right_rect.intersects(map_rect) or \
            workspace_rect.intersects(map_rect) or \
            workspace_rect.intersects(right_rect) or \
            workspace_rect.intersects(turn_rect):
        push_error("Top=%s Right=%s Workspace=%s Map=%s" % [
            turn_rect, right_rect, workspace_rect, map_rect
        ])
        main_scene.free()
        quit(1)
        return

    if main_scene.workspace_mode_name() != "closed":
        push_error("Workspace did not start in the closed state")
        main_scene.free()
        quit(1)
        return
    road_entry.pressed.emit()
    var workspace_title := main_scene.get_node(
        "WorkspacePanel/Workspace/TitleBar/Title"
    ) as Label
    if main_scene.workspace_mode_name() != "road_construction" or \
            workspace_title.text != "道路建设":
        push_error("Road entry did not open the reserved workspace")
        main_scene.free()
        quit(1)
        return
    var workspace_close := main_scene.get_node(
        "WorkspacePanel/Workspace/TitleBar/Close"
    ) as Button
    workspace_close.pressed.emit()
    if main_scene.workspace_mode_name() != "closed":
        push_error("Workspace close button did not restore the closed state")
        main_scene.free()
        quit(1)
        return

    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame
    var vertical_bar := workspace_scroll.get_v_scroll_bar()
    if vertical_bar.max_value <= vertical_bar.page:
        push_error("Province management content did not produce vertical scrolling")
        main_scene.free()
        quit(1)
        return
    workspace_scroll.scroll_vertical = int(vertical_bar.max_value)
    await process_frame
    if workspace_scroll.scroll_vertical <= 0:
        push_error("Workspace could not scroll to its lower content")
        main_scene.free()
        quit(1)
        return

    if bridge.set_ai_enabled(false, "caelus") != true:
        push_error("Could not switch the saved player identity to Caelus")
        main_scene.free()
        quit(1)
        return
    for order: Dictionary in bridge.get_pending_orders("caelus"):
        bridge.cancel_order(String(order.get("order_id", "")))
    var caelus_order: Dictionary = bridge.recruit_army(
        "caelus", "capital_caelus", 1
    )
    var quick_path := ProjectSettings.globalize_path("user://quick_save.json")
    if not caelus_order.get("accepted", false) or \
            not bridge.save_game(quick_path).get("accepted", false):
        push_error("Could not save a Caelus UI authority fixture")
        main_scene.free()
        quit(1)
        return
    main_scene.get_node("RightPanel/Center/SaveControls/Load").pressed.emit()
    await process_frame
    var ui_player_identity := ""
    for property: Dictionary in main_scene.get_property_list():
        if property.get("name", "") == "player_country_id":
            ui_player_identity = str(main_scene.get("player_country_id"))
            break
    var ui_pending_orders: Array = main_scene.call("_player_pending_orders")
    var player_war_target := main_scene.get_node(
        "RightPanel/Center/DiplomacyControls/WarTarget"
    ) as OptionButton
    var target_ids: Array[String] = []
    for index: int in range(player_war_target.item_count):
        target_ids.append(String(player_war_target.get_item_metadata(index)))
    if ui_player_identity != "caelus" or ui_pending_orders.size() != 1 or \
            ui_pending_orders[0].get("country_id", "") != "caelus" or \
            target_ids.has("caelus") or not target_ids.has("auroria"):
        push_error("Main UI did not consume the loaded Caelus player identity")
        main_scene.free()
        quit(1)
        return

    print("Main layout smoke test passed")
    main_scene.free()
    quit(0)
