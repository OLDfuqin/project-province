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

    var turn_bar := main_scene.get_node_or_null("TurnBar") as Control
    if turn_bar == null or turn_bar.get_parent() != main_scene:
        push_error("Turn controls must be a standalone top bar, not a map child")
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
        "RightPanel/Center/TechnologyControls/Buttons/Economy",
        "RightPanel/Center/ArmyControls/RecruitArmy",
    ]
    for control_path: String in preserved_controls:
        if main_scene.get_node_or_null(control_path) == null:
            push_error("Existing main control was removed: %s" % control_path)
            main_scene.free()
            quit(1)
            return

    var province_summary := main_scene.get_node_or_null(
        "RightPanel/Center/ProvinceSummary"
    ) as Label
    if province_summary == null or not province_summary.text.contains("可招募士兵"):
        push_error("Main UI did not label the recruitable population")
        main_scene.free()
        quit(1)
        return

    var map_rect := map_panel.get_global_rect()
    var turn_rect := turn_bar.get_global_rect()
    var right_rect := right_panel.get_global_rect()
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

    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    province_map.province_double_clicked.emit("northreach")
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

    print("Main layout smoke test passed")
    main_scene.free()
    quit(0)
