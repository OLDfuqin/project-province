extends SceneTree


func _initialize() -> void:
    var map_script := load("res://scripts/province_map.gd")
    var province_map: Control = map_script.new()
    if not province_map.load_map_geometry("res://data/map_geometry.json") or \
            province_map.geometry_count() != 32:
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
        Vector2(50, 50): "northreach",
        Vector2(150, 50): "westmark",
        Vector2(250, 50): "greenvale",
        Vector2(350, 50): "sunmeadow",
        Vector2(450, 50): "blueharbor",
        Vector2(550, 50): "skyplain",
        Vector2(650, 50): "goldcoast",
        Vector2(750, 50): "redpass",
        Vector2(50, 180): "z_nr_1",
        Vector2(750, 440): "z_rp_3",
        Vector2(900, 600): "",
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
        {"province_a": "northreach", "province_b": "westmark", "level": "paved"}
    ])
    province_map.set_road_selection("northreach", "westmark")
    if province_map.road_count() != 1:
        push_error("Map did not retain road snapshot")
        quit(1)
        return
    province_map.set_armies([
        {
            "id": "army_1",
            "owner_id": "auroria",
            "province_id": "northreach",
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
    single_click.position = Vector2(50, 50)
    province_map._gui_input(single_click)
    province_map._gui_input(single_click)

    var double_click := InputEventMouseButton.new()
    double_click.button_index = MOUSE_BUTTON_LEFT
    double_click.pressed = true
    double_click.double_click = true
    double_click.position = Vector2(150, 50)
    province_map._gui_input(double_click)

    var blank_click := InputEventMouseButton.new()
    blank_click.button_index = MOUSE_BUTTON_LEFT
    blank_click.pressed = true
    blank_click.position = Vector2(900, 600)
    province_map._gui_input(blank_click)

    if clicked_ids != ["northreach", "northreach"] or \
            double_clicked_ids != ["westmark"] or \
            blank_clicks.size() != 1 or \
            selected_ids != ["northreach", "northreach", "westmark", ""]:
        push_error("Map click signals did not distinguish repeated, double and blank clicks")
        quit(1)
        return

    print("Province map hit-test smoke test passed")
    bridge.free()
    province_map.free()
    quit(0)
