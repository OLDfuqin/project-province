extends SceneTree


func _fail(main_scene: Control, message: String) -> void:
    push_error(message)
    if is_instance_valid(main_scene):
        main_scene.free()
    quit(1)


func _initialize() -> void:
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    if packed_scene == null:
        _fail(null, "Main scene could not be loaded")
        return
    var main_scene := packed_scene.instantiate() as Control
    root.add_child(main_scene)
    await process_frame

    var top_bar := main_scene.get_node_or_null(
        "Shell/Layout/GlobalStatusBar"
    ) as Control
    var navigation := main_scene.get_node_or_null(
        "Shell/Layout/MainRow/PrimaryNavigation"
    ) as Control
    var map_panel := main_scene.get_node_or_null(
        "Shell/Layout/MainRow/MapPanel"
    ) as Control
    var inspector := main_scene.get_node_or_null(
        "Shell/Layout/MainRow/ContextInspector"
    ) as Control
    var mode_bar := main_scene.get_node_or_null(
        "Shell/Layout/MapModeBar"
    ) as Control
    var drawer := main_scene.get_node_or_null("Shell/BottomDrawer") as Control
    var pages := main_scene.get_node_or_null("Shell/ManagementPageHost") as Control
    if top_bar == null or navigation == null or map_panel == null or \
            inspector == null or mode_bar == null or drawer == null or pages == null:
        _fail(main_scene, "Strategic shell is incomplete")
        return
    if main_scene.get_node_or_null("RightPanel") != null or \
            main_scene.get_node_or_null("WorkspacePanel") != null or \
            main_scene.get_node_or_null("TurnBar") != null:
        _fail(main_scene, "Legacy double-right-column layout still exists")
        return

    var advance_turn := top_bar.get_node_or_null("Margin/Row/AdvanceTurn") as Button
    if advance_turn == null or advance_turn.text != "进入下一回合" or \
            not advance_turn.visible or drawer.visible:
        _fail(main_scene, "Fixed next-turn control or closed drawer state is wrong")
        return
    if top_bar.get_node_or_null("Margin/Row/CoreVersion") != null or \
            top_bar.get_node_or_null("Margin/Row/SaveCount") != null:
        _fail(main_scene, "Build metadata leaked into the map-first status bar")
        return
    if inspector.get_parent() != map_panel.get_parent() or \
            main_scene.get_tree().get_nodes_in_group("context_inspector").size() > 1:
        _fail(main_scene, "Strategic shell must own exactly one context inspector")
        return

    if main_scene.active_page_name() != "closed" or \
            main_scene.active_drawer_name() != "closed" or \
            main_scene.active_map_mode_name() != "political" or \
            main_scene.workspace_mode_name() != "closed" or \
            main_scene.map_input_mode_name() != "normal":
        _fail(main_scene, "Main scene did not expose the initial strategic state")
        return

    var province_map := map_panel.get_node_or_null("ProvinceMap")
    if province_map == null:
        _fail(main_scene, "Map panel lost the interactive province map")
        return
    province_map.province_clicked.emit("capital_auroria")
    await process_frame
    if main_scene.workspace_mode_name() != "province_summary" or \
            inspector.current_mode() != "province_summary":
        _fail(main_scene, "Single map click did not open the province summary")
        return
    province_map.map_blank_clicked.emit()
    await process_frame
    if main_scene.workspace_mode_name() != "closed":
        _fail(main_scene, "Blank map click did not close the temporary summary")
        return
    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame
    if main_scene.workspace_mode_name() != "province_management" or \
            inspector.current_mode() != "province_management":
        _fail(main_scene, "Double click did not open province management in the inspector")
        return
    province_map.map_blank_clicked.emit()
    if main_scene.workspace_mode_name() != "province_management":
        _fail(main_scene, "Blank map click discarded a persistent management context")
        return
    inspector.get_node("Body/Header/Close").pressed.emit()
    await process_frame
    if main_scene.workspace_mode_name() != "closed":
        _fail(main_scene, "Inspector close did not restore the map context")
        return

    mode_bar.get_node("Margin/Row/PendingOrders").pressed.emit()
    await process_frame
    if main_scene.active_drawer_name() != "orders" or not drawer.visible:
        _fail(main_scene, "Order drawer did not open from the map mode bar")
        return
    drawer.get_node("Panel/Body/Header/Close").pressed.emit()
    mode_bar.get_node("Margin/Row/Roads").pressed.emit()
    await process_frame
    if main_scene.active_map_mode_name() != "roads" or \
            main_scene.workspace_mode_name() != "road_construction":
        _fail(main_scene, "Road map mode did not enter road planning")
        return
    inspector.get_node("Body/Header/Close").pressed.emit()

    navigation.get_node("Margin/Row/Technology").pressed.emit()
    await process_frame
    if main_scene.active_page_name() != "technology" or not pages.visible or \
            main_scene.workspace_mode_name() != "closed":
        _fail(main_scene, "Primary navigation did not open the technology page")
        return
    pages.get_node("Pages/Header/Back").pressed.emit()
    if main_scene.active_page_name() != "closed" or \
            navigation.active_destination() != "map":
        _fail(main_scene, "Management page back action did not return to the map")
        return

    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    if main_scene.active_drawer_name() != "closed" or \
            not main_scene._latest_event_message.contains("财政收入"):
        _fail(main_scene, "Next turn did not preserve the strategic event workflow")
        return

    print("Strategic main layout smoke test passed")
    main_scene.free()
    quit(0)
