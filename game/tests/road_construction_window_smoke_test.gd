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


func _enemy_province(bridge: Object) -> String:
    for province: Dictionary in bridge.get_province_summaries():
        if province.get("owner_id", "") != "auroria":
            return String(province.get("id", ""))
    return ""


func _non_adjacent_owned_province(bridge: Object, origin_id: String) -> String:
    var neighbors: Array = []
    for province: Dictionary in bridge.get_province_summaries():
        if province.get("id", "") == origin_id:
            neighbors = province.get("neighbors", [])
            break
    for province: Dictionary in bridge.get_province_summaries():
        var province_id := String(province.get("id", ""))
        if province.get("owner_id", "") == "auroria" and \
                province_id != origin_id and not neighbors.has(province_id):
            return province_id
    return ""


func _read_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return parsed if parsed is Dictionary else {}


func _normalize_json_numbers(value: Variant) -> Variant:
    if value is float and is_equal_approx(value, round(value)):
        return int(value)
    if value is Array:
        var result: Array = []
        for item: Variant in value:
            result.append(_normalize_json_numbers(item))
        return result
    if value is Dictionary:
        var result: Dictionary = {}
        for key: Variant in value:
            result[key] = _normalize_json_numbers(value[key])
        return result
    return value


func _write_json(path: String, document: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(_normalize_json_numbers(document)))
    file.close()


func _fail(main_scene: Node, message: String) -> void:
    push_error(message)
    main_scene.free()
    quit(1)


func _initialize() -> void:
    var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
    for forbidden: String in [
        "DEFAULT_ROAD_BUILD_COST",
        "_estimated_road_build_cost",
        "_road_endpoint_base_cost",
        "_road_required_level",
        'quote.get("cost", _',
    ]:
        if main_source.contains(forbidden):
            push_error("Road UI retained a local authority fallback: %s" % forbidden)
            quit(1)
            return

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
            not select_end.disabled or not build_road.disabled or \
            not road_window.get_node("EstimatedCost").text.contains("等待权威报价"):
        _fail(main_scene, "Road construction window did not open in its initial state")
        return

    select_start.pressed.emit()
    var enemy_id := _enemy_province(bridge)
    province_map.province_clicked.emit(enemy_id)
    province_map.province_selected.emit(enemy_id)
    if not main_scene.road_start_id.is_empty() or \
            main_scene.map_input_mode_name() != "road_start" or \
            not road_window.get_node("Status").text.contains("玩家实际控制"):
        _fail(main_scene, "Enemy-controlled road start was incorrectly accepted")
        return
    province_map.province_clicked.emit(pair[0])
    province_map.province_selected.emit(pair[0])
    if main_scene.map_input_mode_name() != "normal" or select_end.disabled:
        _fail(main_scene, "Controlled road start was not accepted")
        return

    select_end.pressed.emit()
    var non_adjacent_id := _non_adjacent_owned_province(bridge, pair[0])
    province_map.province_clicked.emit(non_adjacent_id)
    province_map.province_selected.emit(non_adjacent_id)
    if not main_scene.road_end_id.is_empty() or \
            main_scene.map_input_mode_name() != "road_end" or \
            not road_window.get_node("Status").text.contains("相邻"):
        _fail(main_scene, "Non-adjacent road endpoint was incorrectly accepted")
        return
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

    pair = _eligible_pair(bridge)
    for _level: int in range(3):
        if not pair.is_empty():
            break
        var additional_research: Dictionary = bridge.research_technology(
            "auroria", "roads"
        )
        if not additional_research.get("accepted", false):
            break
        for _month: int in range(int(additional_research.get("remaining_months", 0))):
            advance_turn.pressed.emit()
            await process_frame
            await process_frame
        pair = _eligible_pair(bridge)
    if pair.is_empty():
        _fail(main_scene, "No second route was available for refresh revalidation")
        return
    select_start.pressed.emit()
    province_map.province_clicked.emit(pair[0])
    province_map.province_selected.emit(pair[0])
    select_end.pressed.emit()
    province_map.province_clicked.emit(pair[1])
    province_map.province_selected.emit(pair[1])

    var baseline_path := ProjectSettings.globalize_path(
        "res://../build/task9_road_refresh_baseline.json"
    )
    var debt_path := baseline_path + ".debt"
    var takeover_path := baseline_path + ".takeover"
    if not bridge.save_game(baseline_path).get("accepted", false):
        _fail(main_scene, "Could not save road refresh baseline")
        return
    var baseline_document := _read_json(baseline_path)
    var debt_document := baseline_document.duplicate(true)
    for country: Dictionary in debt_document.get("countries", []):
        if country.get("id", "") == "auroria":
            country["treasury"] = -1
    _write_json(debt_path, debt_document)
    if not bridge.load_game(debt_path).get("accepted", false):
        _fail(main_scene, "Could not load debt road refresh fixture")
        return
    main_scene.call("_refresh_map_data")
    main_scene.call("_refresh_pending_orders")
    if build_road.disabled == false or main_scene.road_start_id != pair[0] or \
            main_scene.road_end_id != pair[1] or \
            not road_window.get_node("Status").text.contains("负债"):
        _fail(main_scene, "Debt did not re-quote and disable the selected road route")
        return

    if not bridge.load_game(baseline_path).get("accepted", false):
        _fail(main_scene, "Could not restore road refresh baseline after debt")
        return
    main_scene.call("_refresh_map_data")
    if build_road.disabled:
        _fail(main_scene, "Restoring authoritative funds did not re-enable the route")
        return

    var takeover_document := baseline_document.duplicate(true)
    var occupations: Array = []
    for occupation: Dictionary in takeover_document.get("occupations", []):
        if occupation.get("province_id", "") != pair[1]:
            occupations.append(occupation)
    occupations.append({"province_id": pair[1], "controller_id": "caelus"})
    takeover_document["occupations"] = occupations
    _write_json(takeover_path, takeover_document)
    if not bridge.load_game(takeover_path).get("accepted", false):
        _fail(main_scene, "Could not load endpoint takeover road refresh fixture")
        return
    main_scene.call("_refresh_map_data")
    if not build_road.disabled or not main_scene.road_start_id.is_empty() or \
            not main_scene.road_end_id.is_empty() or \
            not road_window.get_node("Status").text.contains("不再由玩家实际控制"):
        _fail(main_scene, "Endpoint takeover did not invalidate and clear the route")
        return

    if not bridge.load_game(baseline_path).get("accepted", false):
        _fail(main_scene, "Could not restore road refresh baseline after takeover")
        return
    main_scene.call("_refresh_map_data")
    select_start.pressed.emit()
    province_map.province_clicked.emit(pair[0])
    province_map.province_selected.emit(pair[0])
    select_end.pressed.emit()
    province_map.province_clicked.emit(pair[1])
    province_map.province_selected.emit(pair[1])
    var externally_queued: Dictionary = bridge.build_road("auroria", pair[0], pair[1])
    if not externally_queued.get("accepted", false):
        _fail(main_scene, "Could not prepare an externally invalidated road quote")
        return
    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    if not _road_exists(bridge, pair[0], pair[1]) or not build_road.disabled or \
            not main_scene.road_start_id.is_empty() or \
            not main_scene.road_end_id.is_empty() or \
            not road_window.get_node("Status").text.contains("已经存在公路"):
        _fail(main_scene, "Road workspace did not re-quote and clear an invalid route")
        return

    print("Road construction monthly order window smoke test passed")
    main_scene.free()
    quit(0)
