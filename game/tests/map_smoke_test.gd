extends SceneTree


func _initialize() -> void:
    var map_script := load("res://scripts/province_map.gd")
    var province_map: Control = map_script.new()
    if not province_map.load_grid_layout("res://data/grid_map_layout.json") or \
            province_map.geometry_count() != 69:
        push_error("Data-driven map geometry failed to load")
        province_map.free()
        quit(1)
        return
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
            ordinary_layout.get("city_rect") != Rect2(32, 672, 16, 16) or \
            ordinary_layout.get("terrain_kind", "") != "plains" or \
            ordinary_layout.get("terrain_rect") != Rect2(0, 640, 16, 16) or \
            ordinary_layout.get("army_rects", []) != [] or \
            int(ordinary_layout.get("overflow_count", -1)) != 0:
        push_error("Ordinary province icon layout is incorrect: %s" % ordinary_layout)
        quit(1)
        return

    var capital_layout: Dictionary = province_map.icon_layout_for_province("capital_auroria")
    if capital_layout.get("city_kind", "") != "capital" or \
            capital_layout.get("city_rect") != Rect2(148, 548, 24, 24) or \
            capital_layout.has("terrain_kind") or capital_layout.has("terrain_rect"):
        push_error("Capital icon layout is incorrect: %s" % capital_layout)
        quit(1)
        return

    var crowded_armies: Array = []
    for index: int in range(18, 0, -1):
        crowded_armies.append({
            "id": "army_%02d" % index,
            "owner_id": "auroria",
            "province_id": "cell_1_1",
            "manpower": 100,
            "movement_points": 0,
        })
    province_map.set_armies(crowded_armies)
    ordinary_layout = province_map.icon_layout_for_province("cell_1_1")
    var army_rects: Array = ordinary_layout.get("army_rects", [])
    if army_rects.size() != 14 or \
            army_rects[0] != Rect2(56, 640, 8, 16) or \
            army_rects[1] != Rect2(64, 640, 8, 16) or \
            army_rects[2] != Rect2(72, 640, 8, 16) or \
            army_rects[3] != Rect2(56, 656, 8, 16) or \
            ordinary_layout.get("overflow_rect") != Rect2(72, 704, 8, 16) or \
            int(ordinary_layout.get("overflow_count", 0)) != 4 or \
            ordinary_layout.get("army_ids", []) != [
                "army_01", "army_02", "army_03", "army_04", "army_05", "army_06",
                "army_07", "army_08", "army_09", "army_10", "army_11", "army_12",
                "army_13", "army_14",
            ]:
        push_error("Army icon layout, sorting or overflow is incorrect: %s" % ordinary_layout)
        quit(1)
        return

    var capital_armies: Array = []
    for index: int in range(32, 0, -1):
        capital_armies.append({
            "id": "capital_army_%02d" % index,
            "owner_id": "auroria",
            "province_id": "capital_auroria",
            "manpower": 100,
            "movement_points": 0,
        })
    province_map.set_armies(capital_armies)
    capital_layout = province_map.icon_layout_for_province("capital_auroria")
    if capital_layout.get("army_rects", []).size() != 29 or \
            capital_layout.get("overflow_rect") != Rect2(232, 624, 8, 16) or \
            int(capital_layout.get("overflow_count", 0)) != 3:
        push_error("Capital army icon capacity is incorrect: %s" % capital_layout)
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
