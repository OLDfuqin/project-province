extends SceneTree

const CAPTURE_SIZE := Vector2i(1600, 1000)
const INITIAL_OUTPUT_PATH := "res://../build/task-1-geometry-initial-1600x1000.png"
const STRESS_OUTPUT_PATH := "res://../build/task-1-geometry-full-slots-1600x1000.png"


func _fail(node: Node, message: String) -> void:
    push_error(message)
    node.free()
    quit(1)


func _armies(province_id: String, count: int, prefix: String) -> Array:
    var result: Array = []
    for index: int in range(count):
        result.append({
            "id": "%s_%02d" % [prefix, index + 1],
            "owner_id": "auroria",
            "province_id": province_id,
            "manpower": 100,
            "movement_points": 0,
        })
    return result


func _capture(viewport: SubViewport, output_path: String) -> Dictionary:
    await process_frame
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.get_size() != CAPTURE_SIZE:
        return {"error": "Godot capture did not produce a 1600x1000 image"}
    var sampled_colors: Dictionary = {}
    for y: int in range(0, CAPTURE_SIZE.y, 40):
        for x: int in range(0, CAPTURE_SIZE.x, 40):
            sampled_colors[image.get_pixel(x, y).to_html()] = true
    if sampled_colors.size() < 16:
        return {"error": "Godot capture appears blank or visually degenerate"}
    var absolute_output := ProjectSettings.globalize_path(output_path)
    var save_error := image.save_png(absolute_output)
    if save_error != OK or not FileAccess.file_exists(absolute_output):
        return {"error": "Could not save Godot geometry capture: error %d" % save_error}
    return {"path": absolute_output, "sampled_colors": sampled_colors.size()}


func _initialize() -> void:
    var viewport := SubViewport.new()
    viewport.size = CAPTURE_SIZE
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    root.add_child(viewport)

    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    var main_scene := packed_scene.instantiate() as Control
    main_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(main_scene)
    await process_frame
    await process_frame

    var province_map: Control = main_scene.get_node("Shell/Layout/MainRow/MapPanel/ProvinceMap")
    province_map.set("logical_grid_debug_enabled", true)
    province_map.set("draw_diagnostics_enabled", true)
    province_map.set("_selected_id", "capital_auroria")
    province_map.set("_view_initialized", false)
    province_map.call("_initialize_view")
    province_map.queue_redraw()
    await process_frame
    await process_frame

    var observation: Dictionary = province_map.draw_observation()
    if province_map.geometry_count() != 69 or \
            observation.get("province_outlines", 0) != 69 or \
            observation.get("logical_grid_lines", 0) != 20:
        _fail(viewport, "Capture scene did not render the visual and logical geometry layers: %s" % observation)
        return

    var initial_capture: Dictionary = await _capture(viewport, INITIAL_OUTPUT_PATH)
    if initial_capture.has("error"):
        _fail(viewport, initial_capture["error"])
        return

    province_map.set_armies(
        _armies("cell_1_1", 15, "ordinary") + \
        _armies("capital_auroria", 30, "capital")
    )
    province_map.set_roads([{
        "province_a": "capital_auroria",
        "province_b": "cell_2_1",
        "level": "paved",
    }])
    province_map.queue_redraw()
    await process_frame
    observation = province_map.draw_observation()
    if observation.get("army_icons", 0) != 45 or observation.get("road_lines", 0) != 1:
        _fail(viewport, "Full-slot capture did not reach the actual icon and road renderer: %s" % observation)
        return
    var stress_capture: Dictionary = await _capture(viewport, STRESS_OUTPUT_PATH)
    if stress_capture.has("error"):
        _fail(viewport, stress_capture["error"])
        return

    print("Map geometry captures passed: %s (%d colors); %s (%d colors)" % [
        initial_capture["path"], initial_capture["sampled_colors"],
        stress_capture["path"], stress_capture["sampled_colors"],
    ])
    viewport.free()
    quit(0)
