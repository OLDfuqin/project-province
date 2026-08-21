extends SceneTree


func _initialize() -> void:
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Main scene could not be loaded for road construction testing")
        quit(1)
        return

    var main_scene := packed_scene.instantiate() as Control
    root.add_child(main_scene)
    await process_frame
    var bridge := main_scene.get_node("SimulationBridge")
    bridge.research_technology("auroria", "roads")

    var road_entry := main_scene.get_node(
        "RightPanel/Center/RoadConstructionEntry"
    ) as Button
    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    var road_window := main_scene.get_node_or_null(
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/RoadConstructionWindow"
    ) as Control
    if road_window == null:
        push_error("Road construction window was not embedded in the workspace")
        main_scene.free()
        quit(1)
        return

    road_entry.pressed.emit()
    var select_start := road_window.get_node("EndpointButtons/SelectStart") as Button
    var select_end := road_window.get_node("EndpointButtons/SelectEnd") as Button
    var build_road := road_window.get_node("ActionButtons/BuildRoad") as Button
    var reset := road_window.get_node("ActionButtons/Reset") as Button
    if main_scene.workspace_mode_name() != "road_construction" or \
            not road_window.visible or \
            not road_window.get_node("EstimatedCost").text.contains("600") or \
            select_start.disabled or not select_end.disabled or not build_road.disabled:
        push_error("Road construction window did not open in its initial state")
        main_scene.free()
        quit(1)
        return

    select_start.pressed.emit()
    province_map.province_clicked.emit("greenvale")
    province_map.province_selected.emit("greenvale")
    if main_scene.map_input_mode_name() != "road_start" or \
            not road_window.get_node("Status").text.contains("控制") or \
            not road_window.get_node("StartProvince").text.contains("尚未选择"):
        push_error("Enemy province was incorrectly accepted as the road start")
        main_scene.free()
        quit(1)
        return

    province_map.province_clicked.emit("northreach")
    province_map.province_selected.emit("northreach")
    if main_scene.map_input_mode_name() != "normal" or select_end.disabled or \
            not road_window.get_node("StartProvince").text.contains("北境"):
        push_error("Controlled road start was not accepted")
        main_scene.free()
        quit(1)
        return

    select_end.pressed.emit()
    province_map.province_clicked.emit("z_nr_2")
    province_map.province_selected.emit("z_nr_2")
    if main_scene.map_input_mode_name() != "road_end" or \
            not road_window.get_node("Status").text.contains("相邻") or \
            not road_window.get_node("EndProvince").text.contains("尚未选择"):
        push_error("Non-adjacent province was incorrectly accepted as the road end")
        main_scene.free()
        quit(1)
        return

    province_map.province_clicked.emit("westmark")
    province_map.province_selected.emit("westmark")
    if main_scene.map_input_mode_name() != "normal" or build_road.disabled or \
            not road_window.get_node("EndProvince").text.contains("西境"):
        push_error("Valid road end was not accepted")
        main_scene.free()
        quit(1)
        return

    reset.pressed.emit()
    if not build_road.disabled or not select_end.disabled or \
            not road_window.get_node("StartProvince").text.contains("尚未选择") or \
            not road_window.get_node("EndProvince").text.contains("尚未选择"):
        push_error("Manual road selection reset failed")
        main_scene.free()
        quit(1)
        return

    select_start.pressed.emit()
    province_map.province_clicked.emit("northreach")
    province_map.province_selected.emit("northreach")
    select_end.pressed.emit()
    province_map.province_clicked.emit("westmark")
    province_map.province_selected.emit("westmark")
    build_road.pressed.emit()

    var road_built := false
    for road: Dictionary in main_scene.get_node("SimulationBridge").get_road_summaries():
        var endpoints := [String(road.get("province_a", "")), String(road.get("province_b", ""))]
        if endpoints.has("northreach") and endpoints.has("westmark"):
            road_built = true
            break
    if not road_built or main_scene.workspace_mode_name() != "road_construction" or \
            not build_road.disabled or not select_end.disabled or \
            not road_window.get_node("StartProvince").text.contains("尚未选择") or \
            not road_window.get_node("Status").text.contains("建成"):
        push_error("Successful road construction did not reset the persistent window")
        main_scene.free()
        quit(1)
        return

    print("Road construction window smoke test passed")
    main_scene.free()
    quit(0)
