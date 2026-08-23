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
