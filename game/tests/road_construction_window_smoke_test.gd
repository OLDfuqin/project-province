extends SceneTree


func _road_exists(bridge: Object, first: String, second: String) -> bool:
    for road: Dictionary in bridge.get_road_summaries():
        var endpoints := [
            String(road.get("province_a", "")),
            String(road.get("province_b", "")),
        ]
        if endpoints.has(first) and endpoints.has(second):
            return true
    return false


func _eligible_pair(bridge: Object) -> Array[String]:
    var by_id: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        by_id[province.get("id", "")] = province
    for province_id: String in by_id:
        var province: Dictionary = by_id[province_id]
        if province.get("owner_id", "") != "auroria":
            continue
        for neighbor_value: Variant in province.get("neighbors", []):
            var neighbor_id := String(neighbor_value)
            var neighbor: Dictionary = by_id.get(neighbor_id, {})
            if neighbor.get("owner_id", "") != "auroria" or \
                    _road_exists(bridge, province_id, neighbor_id):
                continue
            var quote: Dictionary = bridge.get_road_order_quote(
                "auroria", province_id, neighbor_id
            )
            if quote.get("accepted", false):
                return [province_id, neighbor_id]
    return []


func _fail(main_scene: Node, message: String) -> void:
    push_error(message)
    main_scene.free()
    quit(1)


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
    var advance_turn := main_scene.get_node(
        "TurnBar/TurnControls/AdvanceTurn"
    ) as Button

    var pair := _eligible_pair(bridge)
    for _level: int in range(3):
        if not pair.is_empty():
            break
        var research: Dictionary = bridge.research_technology("auroria", "roads")
        if not research.get("accepted", false):
            _fail(main_scene, "Could not queue the road technology required by the fixture")
            return
        for _month: int in range(int(research.get("remaining_months", 0))):
            advance_turn.pressed.emit()
            await process_frame
            await process_frame
        pair = _eligible_pair(bridge)
    if pair.is_empty():
        _fail(main_scene, "No authoritative eligible road pair was available")
        return

    var road_entry := main_scene.get_node(
        "RightPanel/Center/RoadConstructionEntry"
    ) as Button
    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    var road_window := main_scene.get_node_or_null(
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/RoadConstructionWindow"
    ) as Control
    if road_window == null or road_entry.disabled:
        _fail(main_scene, "Road construction window was unavailable")
        return

    road_entry.pressed.emit()
    var select_start := road_window.get_node("EndpointButtons/SelectStart") as Button
    var select_end := road_window.get_node("EndpointButtons/SelectEnd") as Button
    var build_road := road_window.get_node("ActionButtons/BuildRoad") as Button
    var reset := road_window.get_node("ActionButtons/Reset") as Button
    if main_scene.workspace_mode_name() != "road_construction" or \
            not road_window.visible or select_start.disabled or \
            not select_end.disabled or not build_road.disabled:
        _fail(main_scene, "Road construction window did not open in its initial state")
        return

    select_start.pressed.emit()
    province_map.province_clicked.emit(pair[0])
    province_map.province_selected.emit(pair[0])
    if main_scene.map_input_mode_name() != "normal" or select_end.disabled:
        _fail(main_scene, "Controlled road start was not accepted")
        return

    select_end.pressed.emit()
    province_map.province_clicked.emit(pair[1])
    province_map.province_selected.emit(pair[1])
    var authoritative_quote: Dictionary = bridge.get_road_order_quote(
        "auroria", pair[0], pair[1]
    )
    if main_scene.map_input_mode_name() != "normal" or build_road.disabled or \
            not road_window.get_node("EstimatedCost").text.contains(
                str(authoritative_quote.get("cost", -1))
            ):
        _fail(main_scene, "Valid road end did not use the authoritative quote")
        return

    reset.pressed.emit()
    if not build_road.disabled or not select_end.disabled or \
            not road_window.get_node("StartProvince").text.contains("尚未选择") or \
            not road_window.get_node("EndProvince").text.contains("尚未选择"):
        _fail(main_scene, "Manual road selection reset failed")
        return

    select_start.pressed.emit()
    province_map.province_clicked.emit(pair[0])
    province_map.province_selected.emit(pair[0])
    select_end.pressed.emit()
    province_map.province_clicked.emit(pair[1])
    province_map.province_selected.emit(pair[1])
    build_road.pressed.emit()
    await process_frame

    var pending: Array = bridge.get_pending_orders("auroria")
    if _road_exists(bridge, pair[0], pair[1]) or pending.size() != 1 or \
            pending[0].get("type", "") != "road_construction" or \
            pending[0].get("remaining_months", 0) != 1 or \
            not road_window.get_node("Status").text.contains("已下单，剩余1个月"):
        _fail(main_scene, "Road construction was not left pending for one month")
        return

    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    if not _road_exists(bridge, pair[0], pair[1]) or \
            not bridge.get_pending_orders("auroria").is_empty() or \
            not main_scene.get_node("RightPanel/Center/EventHistory").text.contains("道路订单完成"):
        _fail(main_scene, "Road order did not complete in the following project phase")
        return

    print("Road construction monthly order window smoke test passed")
    main_scene.free()
    quit(0)
