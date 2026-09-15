extends SceneTree


func _rect_is_inside_region(province_map: Control, province_id: String, rect: Rect2) -> bool:
    for corner: Vector2 in [
        rect.position,
        Vector2(rect.end.x, rect.position.y),
        rect.end,
        Vector2(rect.position.x, rect.end.y),
    ]:
        if not province_map.visual_region_contains_point(province_id, corner):
            return false
    return true


func _armies(province_id: String, count: int, prefix: String) -> Array:
    var result: Array = []
    for index: int in range(count, 0, -1):
        result.append({
            "id": "%s_%02d" % [prefix, index],
            "owner_id": "auroria",
            "province_id": province_id,
            "manpower": 100,
            "movement_points": 0,
        })
    return result


func _initialize() -> void:
    var map_script := load("res://scripts/province_map.gd")
    var province_map: Control = map_script.new()
    if not province_map.load_grid_layout("res://data/grid_map_layout.json") or \
            province_map.geometry_count() != 69:
        push_error("Data-driven map geometry failed to load")
        province_map.free()
        quit(1)
        return
    if not province_map.has_method("visual_geometry_signature") or \
            not province_map.has_method("visual_validation_report") or \
            not province_map.visual_validation_report().get("valid", false):
        push_error("ProvinceMap did not expose validated deterministic visual geometry")
        province_map.free()
        quit(1)
        return
    var first_signature: String = province_map.visual_geometry_signature()
    province_map.size = Vector2(1600, 1000)
    province_map.call("_initialize_view")
    if province_map.visual_geometry_signature() != first_signature:
        push_error("Resize regenerated the visual boundary geometry")
        quit(1)
        return
    province_map._pan = Vector2.ZERO
    province_map._zoom = 1.0
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    var data_directory := ProjectSettings.globalize_path("res://data")
    if bridge == null or not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario could not be loaded for geometry validation")
        province_map.free()
        quit(1)
        return
    for province: Dictionary in bridge.get_province_summaries():
        if not province_map.has_geometry(province["id"]):
            push_error("Scenario province has no geometry: %s" % province["id"])
            bridge.free()
            province_map.free()
            quit(1)
            return

    var cases := {
        Vector2(40, 680): "cell_1_1",
        Vector2(200, 520): "capital_auroria",
        Vector2(360, 360): "cell_5_5",
        Vector2(600, 120): "capital_verdantia",
        Vector2(680, 40): "cell_9_9",
        Vector2(900, 900): "",
    }

    for point: Vector2 in cases:
        var actual: String = province_map.province_at_map_position(point)
        var expected: String = cases[point]
        if actual != expected:
            push_error("Map hit test failed at %s: expected '%s', got '%s'" % [
                point, expected, actual
            ])
            quit(1)
            return

    province_map.set_roads([
        {"province_a": "capital_auroria", "province_b": "cell_2_1", "level": "paved"}
    ])
    province_map.set_road_selection("capital_auroria", "cell_2_1")
    if province_map.road_count() != 1:
        push_error("Map did not retain road snapshot")
        quit(1)
        return
    province_map.set_armies([
        {
            "id": "army_1",
            "owner_id": "auroria",
            "province_id": "capital_auroria",
            "manpower": 1000,
            "movement_points": 0,
        }
    ])
    if province_map.army_count() != 1:
        push_error("Map did not retain army snapshot")
        quit(1)
        return

    province_map.set_scenario_data([
        {"id": "cell_1_1", "owner_id": "auroria", "terrain": "plains"},
        {"id": "capital_auroria", "owner_id": "auroria", "terrain": "capital"},
    ], [
        {"id": "auroria", "color_rgb": 0xCC4444},
    ])
    var ordinary_layout: Dictionary = province_map.icon_layout_for_province("cell_1_1")
    if ordinary_layout.get("city_kind", "") != "city" or \
            ordinary_layout.get("city_rect").size != Vector2(16, 16) or \
            ordinary_layout.get("terrain_kind", "") != "plains" or \
            ordinary_layout.get("terrain_rect").size != Vector2(16, 16) or \
            ordinary_layout.get("army_rects", []) != [] or \
            int(ordinary_layout.get("overflow_count", -1)) != 0:
        push_error("Ordinary province icon layout is incorrect: %s" % ordinary_layout)
        quit(1)
        return

    var capital_layout: Dictionary = province_map.icon_layout_for_province("capital_auroria")
    if capital_layout.get("city_kind", "") != "capital" or \
            capital_layout.get("city_rect").size != Vector2(24, 24) or \
            capital_layout.has("terrain_kind") or capital_layout.has("terrain_rect"):
        push_error("Capital icon layout is incorrect: %s" % capital_layout)
        quit(1)
        return

    province_map.set_armies(_armies("cell_1_1", 15, "army"))
    ordinary_layout = province_map.icon_layout_for_province("cell_1_1")
    var army_rects: Array = ordinary_layout.get("army_rects", [])
    if army_rects.size() != 15 or int(ordinary_layout.get("overflow_count", -1)) != 0:
        push_error("Full 3x5 ordinary army slots were not preserved: %s" % ordinary_layout)
        quit(1)
        return
    for rect_value: Variant in army_rects:
        if not _rect_is_inside_region(province_map, "cell_1_1", rect_value):
            push_error("Full ordinary army slot escaped its display polygon: %s" % rect_value)
            quit(1)
            return

    province_map.set_armies(_armies("cell_1_1", 18, "army"))
    ordinary_layout = province_map.icon_layout_for_province("cell_1_1")
    army_rects = ordinary_layout.get("army_rects", [])
    if army_rects.size() != 14 or int(ordinary_layout.get("overflow_count", 0)) != 4 or \
            ordinary_layout.get("army_ids", []) != [
                "army_01", "army_02", "army_03", "army_04", "army_05", "army_06",
                "army_07", "army_08", "army_09", "army_10", "army_11", "army_12",
                "army_13", "army_14",
            ]:
        push_error("Army icon layout, sorting or overflow is incorrect: %s" % ordinary_layout)
        quit(1)
        return
    for rect_value: Variant in army_rects + [ordinary_layout.get("overflow_rect")]:
        var rect: Rect2 = rect_value
        if not _rect_is_inside_region(province_map, "cell_1_1", rect):
            push_error("Overflow ordinary army slot escaped its display polygon: %s" % rect)
            quit(1)
            return

    province_map.set_armies(_armies("capital_auroria", 30, "capital_army"))
    capital_layout = province_map.icon_layout_for_province("capital_auroria")
    if capital_layout.get("army_rects", []).size() != 30 or \
            int(capital_layout.get("overflow_count", -1)) != 0:
        push_error("Full 3x10 capital army slots were not preserved: %s" % capital_layout)
        quit(1)
        return
    for rect_value: Variant in capital_layout.get("army_rects", []):
        if not _rect_is_inside_region(province_map, "capital_auroria", rect_value):
            push_error("Full capital army slot escaped its display polygon: %s" % rect_value)
            quit(1)
            return

    province_map.set_armies(_armies("capital_auroria", 32, "capital_army"))
    capital_layout = province_map.icon_layout_for_province("capital_auroria")
    if capital_layout.get("army_rects", []).size() != 29 or \
            int(capital_layout.get("overflow_count", 0)) != 3:
        push_error("Capital army icon capacity is incorrect: %s" % capital_layout)
        quit(1)
        return
    for rect_value: Variant in capital_layout.get("army_rects", []) + [
        capital_layout.get("overflow_rect")
    ]:
        if not _rect_is_inside_region(province_map, "capital_auroria", rect_value):
            push_error("Overflow capital army slot escaped its display polygon: %s" % rect_value)
            quit(1)
            return

    var all_provinces: Array = bridge.get_province_summaries()
    province_map.set_scenario_data(all_provinces, [{
        "id": "auroria", "color_rgb": 0xCC4444,
    }])
    var all_full_slot_armies: Array = []
    for province: Dictionary in all_provinces:
        var province_id := String(province.get("id", ""))
        var capacity := 30 if province_id.begins_with("capital_") else 15
        all_full_slot_armies.append_array(_armies(province_id, capacity, province_id))
    province_map.set_armies(all_full_slot_armies)
    for province: Dictionary in all_provinces:
        var province_id := String(province.get("id", ""))
        var capacity := 30 if province_id.begins_with("capital_") else 15
        var layout: Dictionary = province_map.icon_layout_for_province(province_id)
        if layout.get("army_rects", []).size() != capacity or \
                int(layout.get("overflow_count", -1)) != 0:
            push_error("A full icon grid lost slots in %s: %s" % [province_id, layout])
            quit(1)
            return
        var safety_rects: Array = [layout.get("city_rect")]
        if layout.has("terrain_rect"):
            safety_rects.append(layout["terrain_rect"])
        safety_rects.append_array(layout.get("army_rects", []))
        for rect_value: Variant in safety_rects:
            if not _rect_is_inside_region(province_map, province_id, rect_value):
                push_error("Icon escaped the display polygon in %s: %s" % [
                    province_id, rect_value,
                ])
                quit(1)
                return

    var road_route: PackedVector2Array = province_map.road_route_for(
        "capital_auroria", "cell_2_1"
    )
    if road_route.size() != 3:
        push_error("ProvinceMap road display route did not use a real shared boundary")
        quit(1)
        return

    var clicked_ids: Array[String] = []
    var double_clicked_ids: Array[String] = []
    var selected_ids: Array[String] = []
    var blank_clicks: Array[bool] = []
    province_map.province_clicked.connect(
        func(province_id: String) -> void: clicked_ids.append(province_id)
    )
    province_map.province_double_clicked.connect(
        func(province_id: String) -> void: double_clicked_ids.append(province_id)
    )
    province_map.province_selected.connect(
        func(province_id: String) -> void: selected_ids.append(province_id)
    )
    province_map.map_blank_clicked.connect(
        func() -> void: blank_clicks.append(true)
    )

    var single_click := InputEventMouseButton.new()
    single_click.button_index = MOUSE_BUTTON_LEFT
    single_click.pressed = true
    single_click.position = Vector2(40, 680)
    province_map._gui_input(single_click)
    province_map._gui_input(single_click)

    var double_click := InputEventMouseButton.new()
    double_click.button_index = MOUSE_BUTTON_LEFT
    double_click.pressed = true
    double_click.double_click = true
    double_click.position = Vector2(200, 520)
    province_map._gui_input(double_click)

    var blank_click := InputEventMouseButton.new()
    blank_click.button_index = MOUSE_BUTTON_LEFT
    blank_click.pressed = true
    blank_click.position = Vector2(900, 900)
    province_map._gui_input(blank_click)

    if clicked_ids != ["cell_1_1", "cell_1_1"] or \
            double_clicked_ids != ["capital_auroria"] or \
            blank_clicks.size() != 1 or \
            selected_ids != ["cell_1_1", "cell_1_1", "capital_auroria", ""]:
        push_error("Map click signals did not distinguish repeated, double and blank clicks")
        quit(1)
        return

    print("Province map hit-test smoke test passed")
    bridge.free()
    province_map.free()
    quit(0)
