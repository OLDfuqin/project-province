extends SceneTree


func _fail(map: Node, message: String) -> void:
    push_error(message)
    map.free()
    quit(1)


func _accepted_road_targets(main_scene: Control, start_id: String) -> Array[String]:
    var accepted: Array[String] = []
    for target_id: String in main_scene.province_by_id:
        if target_id == start_id:
            continue
        var quote: Dictionary = main_scene.bridge.get_road_order_quote(
            main_scene.player_country_id, start_id, target_id
        )
        if quote.get("accepted", false):
            accepted.append(target_id)
    return accepted


func _bridge_state(main_scene: Control) -> Dictionary:
    return {
        "provinces": main_scene.bridge.get_province_summaries().duplicate(true),
        "roads": main_scene.bridge.get_road_summaries().duplicate(true),
        "armies": main_scene.bridge.get_army_summaries().duplicate(true),
        "pending_orders": main_scene.bridge.get_pending_orders(
            main_scene.player_country_id
        ).duplicate(true),
    }


func _observe_draw(map: Control) -> Dictionary:
    map.queue_redraw()
    await process_frame
    await process_frame
    return map.call("draw_observation")


func _color_distance(first: Color, second: Color) -> float:
    return Vector3(first.r, first.g, first.b).distance_to(
        Vector3(second.r, second.g, second.b)
    )


func _initialize() -> void:
    var map := ProvinceMap.new()
    root.add_child(map)
    if not map.load_grid_layout("res://data/grid_map_layout.json"):
        _fail(map, map.geometry_error())
        return

    var provinces: Array = [
        {"id": "cell_1_1", "owner_id": "auroria", "terrain": "plains", "fiscal_income": 8},
        {"id": "cell_1_2", "owner_id": "auroria", "terrain": "forest", "fiscal_income": 8},
        {"id": "cell_2_1", "owner_id": "caelus", "terrain": "hills", "fiscal_income": 16},
    ]
    var countries: Array = [
        {"id": "auroria", "color_rgb": 0xCC4444},
        {"id": "caelus", "color_rgb": 0x4444CC},
    ]
    var original_provinces := provinces.duplicate(true)
    map.set_scenario_data(provinces, countries)

    for mode: String in ["political", "terrain", "economy", "military", "roads"]:
        if not map.set_map_mode(mode) or map.map_mode() != mode:
            _fail(map, "Map mode was not accepted: %s" % mode)
            return
    if map.set_map_mode("unknown") or map.map_mode() != "roads":
        _fail(map, "Unknown map mode changed map state")
        return
    if provinces != original_provinces:
        _fail(map, "Presentation-only map modes mutated scenario data")
        return

    map.set_map_mode("economy")
    var equal_income_color: Color = map.call(
        "_province_fill_color", provinces[0], "auroria", Vector2(8, 8), 0, 0
    )
    var neutral_color: Color = map.call(
        "_province_fill_color",
        {"owner_id": "neutral", "terrain": "mountains", "fiscal_income": 0},
        "neutral", Vector2(8, 8), 0, 0
    )
    if not is_finite(equal_income_color.r) or not is_finite(equal_income_color.g) or \
            not is_finite(equal_income_color.b) or neutral_color != Color("596579"):
        _fail(map, "Map normalization was unstable for equal or ownerless values")
        return
    map.set_scenario_data(provinces + [{
        "id": "cell_2_2", "owner_id": "neutral", "fiscal_income": 0,
    }], countries)
    if map.call("_fiscal_income_bounds") != Vector2(8, 16):
        _fail(map, "Hidden-neutral zero income distorted the owned-province economy scale")
        return
    map.set_scenario_data(provinces, countries)

    map.set_interaction_highlights(
        ["cell_1_1", "cell_1_1", "missing"],
        ["cell_2_1", "cell_2_1"],
        ["cell_1_2", "cell_1_2", "missing"]
    )
    var debug: Dictionary = map.presentation_state()
    if debug.get("reachable", []) != ["cell_1_1"] or \
            debug.get("attackable", []) != ["cell_2_1"] or \
            debug.get("road_targets", []) != ["cell_1_2"]:
        _fail(map, "Map interaction highlights were not stable")
        return
    var base_fill := Color("596579")
    if not map.has_method("_interaction_fill_color"):
        _fail(map, "Movement and attack highlights lacked translucent fill rendering")
        return
    var reachable_fill: Color = map.call("_interaction_fill_color", "cell_1_1", base_fill)
    var attackable_fill: Color = map.call("_interaction_fill_color", "cell_2_1", base_fill)
    if reachable_fill == base_fill or reachable_fill.b <= base_fill.b or \
            attackable_fill == base_fill or attackable_fill.r <= base_fill.r:
        _fail(map, "Movement and attack highlights lacked distinct translucent fills")
        return

    map.set_scenario_data([], [])
    map.set_interaction_highlights(["cell_1_1"], ["cell_2_1"], ["cell_1_2"])
    debug = map.presentation_state()
    if not debug.get("reachable", []).is_empty() or \
            not debug.get("attackable", []).is_empty() or \
            not debug.get("road_targets", []).is_empty():
        _fail(map, "Stale highlights survived an empty scenario")
        return

    var hover_exit := {"id": "not-emitted"}
    map.province_hover_changed.connect(func(province_id: String, _position: Vector2) -> void:
        hover_exit["id"] = province_id
    )
    map._hovered_id = "cell_1_1"
    map.call("_clear_hover")
    if hover_exit["id"] != "" or not map._hovered_id.is_empty():
        _fail(map, "Map hover state survived the pointer leaving the control: event=%s state=%s" % [
            hover_exit["id"], map._hovered_id,
        ])
        return

    map.free()

    var render_viewport := SubViewport.new()
    render_viewport.size = Vector2i(800, 500)
    render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(render_viewport)
    var render_map := ProvinceMap.new()
    render_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    render_viewport.add_child(render_map)
    await process_frame
    if not render_map.load_grid_layout("res://data/grid_map_layout.json"):
        _fail(render_viewport, render_map.geometry_error())
        return
    render_map.set_scenario_data(provinces, countries)
    render_map.set_roads([])
    render_map.set_armies([])
    render_map.set_map_mode("political")
    render_map.set_interaction_highlights([], [], [])
    if not render_map.has_method("draw_observation"):
        _fail(render_viewport, "ProvinceMap lacks a stable actual-draw observation seam")
        return
    var default_draw := await _observe_draw(render_map)
    if not default_draw.is_empty():
        _fail(render_viewport, "Ordinary rendering retained per-province diagnostic dictionaries")
        return
    render_map.set("draw_diagnostics_enabled", true)
    var no_layers := await _observe_draw(render_map)
    render_map.set_roads([{"province_a": "cell_1_1", "province_b": "cell_1_2"}])
    var with_road := await _observe_draw(render_map)
    if no_layers.get("road_lines", -1) != 0 or with_road.get("road_lines", 0) != 1:
        _fail(render_viewport, "Actual renderer did not draw the road layer")
        return
    render_map.set_armies([{
        "id": "render_army", "owner_id": "auroria", "province_id": "cell_2_1",
        "manpower": 500,
    }])
    var with_icons := await _observe_draw(render_map)
    if with_road.get("army_icons", -1) != 0 or with_icons.get("army_icons", 0) != 1:
        _fail(render_viewport, "Actual renderer did not draw the army icon layer")
        return
    var mode_colors: Dictionary = {}
    for mode: String in ["political", "terrain", "economy", "military", "roads"]:
        render_map.set_map_mode(mode)
        render_map.set_interaction_highlights([], [], [])
        var rendered := await _observe_draw(render_map)
        mode_colors[mode] = rendered.get("province_fills", {}).get(
            "cell_1_1", Color.TRANSPARENT
        )
        if rendered.get("province_outlines", 0) != render_map.geometry_count():
            _fail(render_viewport, "Province boundary layer disappeared in %s mode" % mode)
            return
        if rendered.get("road_lines", 0) != 1:
            _fail(render_viewport, "Road layer disappeared in %s mode" % mode)
            return
        if rendered.get("city_icons", 0) != provinces.size() or \
                rendered.get("terrain_icons", 0) != provinces.size() or \
                rendered.get("army_icons", 0) != 1:
            _fail(render_viewport, "Icon layer disappeared in %s mode" % mode)
            return
    for mode: String in ["terrain", "economy", "military", "roads"]:
        if _color_distance(mode_colors["political"], mode_colors[mode]) < 0.08:
            _fail(render_viewport, "Actual province fill did not change in %s mode" % mode)
            return

    render_map.set_map_mode("political")
    render_map.set_interaction_highlights([], [], [])
    var without_highlight := await _observe_draw(render_map)
    render_map.set_interaction_highlights(["cell_1_1"], [], [])
    var reachable_render := await _observe_draw(render_map)
    render_map.set_interaction_highlights([], ["cell_1_1"], [])
    var attackable_render := await _observe_draw(render_map)
    render_map.set_interaction_highlights([], [], ["cell_1_1"])
    var road_target_render := await _observe_draw(render_map)
    var base_render_color: Color = without_highlight["province_fills"]["cell_1_1"]
    if _color_distance(
            base_render_color, reachable_render["province_fills"]["cell_1_1"]
    ) < 0.015 or _color_distance(
            base_render_color, attackable_render["province_fills"]["cell_1_1"]
    ) < 0.015:
        _fail(render_viewport, "Actual renderer ignored movement or attack highlights: base=%s reachable=%s attackable=%s" % [
            base_render_color, reachable_render["province_fills"]["cell_1_1"],
            attackable_render["province_fills"]["cell_1_1"],
        ])
        return
    if reachable_render.get("province_outline_colors", {}).get(
            "cell_1_1", Color.TRANSPARENT
    ) != Color("4c8dff") or attackable_render.get("province_outline_colors", {}).get(
            "cell_1_1", Color.TRANSPARENT
    ) != Color("d85b5b") or road_target_render.get("province_outline_colors", {}).get(
            "cell_1_1", Color.TRANSPARENT
    ) != Color("4fb69f"):
        _fail(render_viewport, "Actual renderer ignored a reachable, attackable, or road outline")
        return
    render_map.set("draw_diagnostics_enabled", false)
    if not (await _observe_draw(render_map)).is_empty():
        _fail(render_viewport, "Disabling draw diagnostics did not discard the snapshot")
        return
    render_viewport.free()

    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    root.add_child(viewport)
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    var main_scene := packed_scene.instantiate() as Control
    viewport.add_child(main_scene)
    await process_frame

    var province_map := main_scene.get_node("Shell/Layout/MainRow/MapPanel/ProvinceMap")
    var mode_bar := main_scene.get_node("Shell/Layout/MapModeBar")
    var tooltip: Control = main_scene.map_hover_tooltip
    var bridge_before := _bridge_state(main_scene)
    var scenario_ids: Array = main_scene.province_by_id.keys()
    for mode: String in ["political", "terrain", "economy", "military", "roads"]:
        province_map.set_map_mode(mode)
    province_map.set_interaction_highlights(
        scenario_ids.slice(0, 2), scenario_ids.slice(2, 4), scenario_ids.slice(4, 6)
    )
    var bridge_after := _bridge_state(main_scene)
    if bridge_after != bridge_before:
        _fail(main_scene, "Map presentation mutated authoritative bridge summaries or orders")
        return
    province_map.set_map_mode("political")
    province_map.set_interaction_highlights([], [], [])
    mode_bar.get_node("Margin/Row/Terrain").pressed.emit()
    if main_scene.active_map_mode_name() != "terrain" or province_map.map_mode() != "terrain":
        _fail(main_scene, "Map mode bar did not update the province presentation mode")
        return

    var army_id := ""
    var army_origin := ""
    var expected_reachable: Array[String] = []
    var expected_attackable: Array[String] = []
    var recruitment: Dictionary = main_scene.bridge.recruit_army(
        main_scene.player_country_id, "capital_auroria", 100
    )
    if not recruitment.get("accepted", false):
        _fail(main_scene, "Could not prepare an army highlight fixture")
        return
    main_scene.bridge.advance_turn()
    main_scene.call("_refresh_map_data")
    for _month: int in range(5):
        for army: Dictionary in main_scene.bridge.get_army_summaries():
            if String(army.get("owner_id", "")) != main_scene.player_country_id:
                continue
            var targets: Array = main_scene.bridge.get_army_order_targets(
                String(army.get("id", ""))
            )
            if targets.is_empty():
                continue
            army_id = String(army.get("id", ""))
            army_origin = String(army.get("province_id", ""))
            for target: Dictionary in targets:
                var target_id := String(target.get("province_id", ""))
                if target.get("is_attack", false):
                    expected_attackable.append(target_id)
                else:
                    expected_reachable.append(target_id)
            break
        if not army_id.is_empty():
            break
        main_scene.bridge.advance_turn()
        main_scene.call("_refresh_map_data")
    if army_id.is_empty():
        _fail(main_scene, "No authoritative army targets were available for the fixture")
        return
    province_map.province_double_clicked.emit(army_origin)
    main_scene.call("_on_management_destination_requested", army_id)
    debug = province_map.presentation_state()
    if debug.get("reachable", []) != expected_reachable or \
            debug.get("attackable", []) != expected_attackable or \
            not debug.get("road_targets", []).is_empty():
        _fail(main_scene, "Army highlights did not mirror authoritative bridge targets")
        return

    main_scene.call("_close_workspace")
    var cleared: Dictionary = province_map.presentation_state()
    if not cleared.get("reachable", []).is_empty() or \
            not cleared.get("attackable", []).is_empty():
        _fail(main_scene, "Army highlights survived target selection exit")
        return

    var road_start := ""
    var expected_road_targets: Array[String] = []
    for _level: int in range(4):
        for province_id: String in main_scene.province_by_id:
            var candidates := _accepted_road_targets(main_scene, province_id)
            if not candidates.is_empty():
                road_start = province_id
                expected_road_targets = candidates
                break
        if not road_start.is_empty():
            break
        var research: Dictionary = main_scene.bridge.research_technology(
            main_scene.player_country_id, "roads"
        )
        if not research.get("accepted", false):
            continue
        for _month: int in range(int(research.get("remaining_months", 0))):
            main_scene.bridge.advance_turn()
        main_scene.call("_refresh_map_data")
    if road_start.is_empty():
        _fail(main_scene, "No authoritative road targets were available for the fixture")
        return
    mode_bar.get_node("Margin/Row/Roads").pressed.emit()
    main_scene.call("_on_road_start_selection_requested")
    main_scene.call("_select_road_endpoint", road_start)
    main_scene.call("_on_road_end_selection_requested")
    debug = province_map.presentation_state()
    if debug.get("road_targets", []) != expected_road_targets or \
            not debug.get("reachable", []).is_empty() or \
            not debug.get("attackable", []).is_empty():
        _fail(main_scene, "Road highlights did not mirror individually accepted bridge quotes")
        return
    main_scene.call("_on_road_exit_requested")
    if main_scene.active_map_mode_name() != "political" or \
            province_map.map_mode() != "political" or \
            not province_map.presentation_state().get("road_targets", []).is_empty():
        _fail(main_scene, "Leaving road planning did not restore the political presentation")
        return

    if tooltip.get_script() != load("res://scripts/ui/map_hover_tooltip.gd"):
        _fail(main_scene, "Main did not mount the map hover tooltip component")
        return
    var hover_events: Array = []
    province_map.province_hover_changed.connect(
        func(province_id: String, screen_position: Vector2) -> void:
            hover_events.append({"id": province_id, "position": screen_position})
    )
    province_map.call("_clear_hover")
    var capital_center: Vector2 = province_map.call(
        "_polygon_center", province_map._polygons["capital_auroria"]
    )
    var hover_local_position: Vector2 = province_map._pan + \
            capital_center * province_map._zoom
    var expected_screen_position: Vector2 = \
            province_map.get_global_transform_with_canvas() * hover_local_position
    var motion := InputEventMouseMotion.new()
    motion.position = hover_local_position
    motion.relative = Vector2(3, 2)
    province_map.call("_gui_input", motion)
    await process_frame
    var tooltip_rect: Rect2 = tooltip.get_global_rect()
    var summary := tooltip.get_node_or_null("Margin/Content/Summary") as Label
    if hover_events.size() != 1 or hover_events[0].get("id", "") != "capital_auroria" or \
            not (hover_events[0].get("position", Vector2.ZERO) as Vector2).is_equal_approx(
                expected_screen_position
            ) or not tooltip.visible or \
            summary == null or not summary.text.contains("人口") or \
            not summary.text.contains("驻军 100") or \
            tooltip_rect.position.x < 0 or tooltip_rect.position.y < 0 or \
            tooltip_rect.size.y > 100 or \
            tooltip_rect.end.x > viewport.size.x + 0.5 or tooltip_rect.end.y > viewport.size.y + 0.5:
        _fail(main_scene, "Chinese hover tooltip was missing or escaped the visible viewport: visible=%s summary=%s rect=%s viewport=%s script=%s" % [
            tooltip.visible, summary.text if summary != null else "missing",
            tooltip_rect, viewport.size, tooltip.get_script(),
        ])
        return
    var repeated_motion := InputEventMouseMotion.new()
    repeated_motion.position = hover_local_position + Vector2(3, 2)
    province_map.call("_gui_input", repeated_motion)
    if hover_events.size() != 1:
        _fail(main_scene, "Stable province hover emitted repeatedly inside one province")
        return
    var edge_center: Vector2 = province_map.call(
        "_polygon_center", province_map._polygons["cell_9_1"]
    )
    var edge_local_position: Vector2 = province_map._pan + edge_center * province_map._zoom
    var edge_screen_position: Vector2 = \
            province_map.get_global_transform_with_canvas() * edge_local_position
    var edge_motion := InputEventMouseMotion.new()
    edge_motion.position = edge_local_position
    province_map.call("_gui_input", edge_motion)
    await process_frame
    tooltip_rect = tooltip.get_global_rect()
    if hover_events.size() != 2 or hover_events.back().get("id", "") != "cell_9_1" or \
            not (hover_events.back().get("position", Vector2.ZERO) as Vector2).is_equal_approx(
                edge_screen_position
            ) or tooltip_rect.position.x < 0 or tooltip_rect.position.y < 0 or \
            tooltip_rect.end.x > viewport.size.x + 0.5 or \
            tooltip_rect.end.y > viewport.size.y + 0.5:
        _fail(main_scene, "Real edge hover did not preserve ID/position or viewport clamping")
        return
    province_map.mouse_exited.emit()
    if tooltip.visible or hover_events.size() != 3 or hover_events.back().get("id", "") != "":
        _fail(main_scene, "Real map hover exit did not hide the tooltip")
        return

    print("Map presentation smoke test passed")
    main_scene.free()
    quit(0)
