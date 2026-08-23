extends SceneTree


func _initialize() -> void:
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Main scene could not be loaded for province information testing")
        quit(1)
        return

    var main_scene := packed_scene.instantiate() as Control
    root.add_child(main_scene)
    await process_frame

    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    var info_window := main_scene.get_node_or_null(
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceInfoWindow"
    ) as Control
    if info_window == null:
        push_error("Province information window was not embedded in the workspace")
        main_scene.free()
        quit(1)
        return

    var bridge := main_scene.get_node("SimulationBridge")
    var capital: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province.get("id", "") == "capital_auroria":
            capital = province
            break
    province_map.province_clicked.emit("capital_auroria")
    var province_name := info_window.get_node("ProvinceName") as Label
    var terrain := info_window.get_node("Terrain") as Label
    var ownership := info_window.get_node("Ownership") as Label
    var population := info_window.get_node("Population") as Label
    var economy := info_window.get_node("Economy") as Label
    var military := info_window.get_node("Military") as Label
    var roads := info_window.get_node("Roads") as Label
    if main_scene.workspace_mode_name() != "province_info" or \
            not info_window.visible or province_name.text != capital.get("name", "") or \
            not terrain.text.contains("首都") or \
            not ownership.text.contains("奥罗里亚") or \
            not population.text.contains(str(capital.get("population", -1))) or \
            not population.text.contains(str(capital.get("recruitable_population", -1))) or \
            not economy.text.contains(str(capital.get("economy", -1))) or \
            not economy.text.ends_with(str(capital.get("fiscal_income", -1))) or \
            not military.text.contains("0 支") or \
            not roads.text.contains("暂无道路"):
        push_error("Province information window did not show the capital snapshot")
        main_scene.free()
        quit(1)
        return

    province_map.map_blank_clicked.emit()
    if main_scene.workspace_mode_name() != "closed" or info_window.visible:
        push_error("Blank map click did not close the province information window")
        main_scene.free()
        quit(1)
        return

    province_map.province_clicked.emit("capital_auroria")
    var advance_turn := main_scene.get_node(
        "TurnBar/TurnControls/AdvanceTurn"
    ) as Button
    advance_turn.pressed.emit()
    if main_scene.workspace_mode_name() != "closed" or info_window.visible:
        push_error("Advancing the turn did not close the province information window")
        main_scene.free()
        quit(1)
        return

    var road_entry := main_scene.get_node(
        "RightPanel/Center/RoadConstructionEntry"
    ) as Button
    road_entry.pressed.emit()
    province_map.map_blank_clicked.emit()
    if main_scene.workspace_mode_name() != "road_construction":
        push_error("Blank map click incorrectly closed a persistent road operation")
        main_scene.free()
        quit(1)
        return

    print("Province information window smoke test passed")
    main_scene.free()
    quit(0)
