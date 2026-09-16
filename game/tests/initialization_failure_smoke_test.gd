extends SceneTree


func _fail(scene: Control, message: String) -> void:
    push_error(message)
    if is_instance_valid(scene):
        scene.free()
    quit(1)


func _assert_failed_initialization(scene: Control, expected: String) -> String:
    var advance := scene.get_node("Shell/Layout/GlobalStatusBar/Margin/Row/AdvanceTurn") as Button
    var inspector := scene.get_node("Shell/Layout/MainRow/ContextInspector")
    var empty := inspector.get_node("Body/ScrollContainer/Content/Empty") as VBoxContainer
    var empty_title := empty.get_node("EmptyTitle") as Label
    var map := scene.get_node("Shell/Layout/MainRow/MapPanel/ProvinceMap") as Control
    if not scene.initialization_error().contains(expected):
        return "Initialization did not expose the expected Chinese failure"
    if not empty.is_visible_in_tree() or not empty_title.text.contains(expected):
        return "Initialization failure was not visible in the inspector"
    if not advance.disabled or not advance.tooltip_text.contains(expected):
        return "Next turn remained available after initialization failed"
    if map.mouse_filter != Control.MOUSE_FILTER_IGNORE:
        return "Map input remained available after initialization failed"
    var settings_save := scene.get_node(
        "Shell/ManagementPageHost/Pages/Settings/Content/Actions/QuickSave"
    ) as Button
    if settings_save == null or not settings_save.disabled:
        return "Management actions remained enabled after initialization failed"
    return ""


func _press_escape() -> void:
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    root.push_input(escape)
    await process_frame


func _initialize() -> void:
    root.size = Vector2i(1280, 720)
    var packed := load("res://scenes/main/main.tscn") as PackedScene

    var map_failure := packed.instantiate()
    map_failure.map_layout_path = "res://data/missing_grid_map_layout.json"
    root.add_child(map_failure)
    await process_frame
    const MAP_FAILURE := "地图加载失败：地图布局数据不可用，请检查游戏文件。"
    var failure := _assert_failed_initialization(map_failure, MAP_FAILURE)
    if not failure.is_empty():
        _fail(map_failure, failure)
        return
    await _press_escape()
    failure = _assert_failed_initialization(map_failure, MAP_FAILURE)
    if not failure.is_empty() or map_failure.active_page_name() != "closed":
        _fail(map_failure, "Escape changed the initialization failure state")
        return
    map_failure.free()
    await process_frame

    var scenario_failure := packed.instantiate()
    scenario_failure.scenario_data_directory = "res://data/missing_scenario"
    root.add_child(scenario_failure)
    await process_frame
    failure = _assert_failed_initialization(scenario_failure, "场景加载失败")
    if not failure.is_empty():
        _fail(scenario_failure, failure)
        return
    scenario_failure.free()

    print("Initialization failure smoke test passed")
    quit(0)
