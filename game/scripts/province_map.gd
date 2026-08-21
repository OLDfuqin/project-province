class_name ProvinceMap
extends Control

const GameText := preload("res://scripts/ui/game_text_formatter.gd")

signal province_hovered(province_id: String)
signal province_selected(province_id: String)
signal province_clicked(province_id: String)
signal province_double_clicked(province_id: String)
signal map_blank_clicked

const MIN_ZOOM := 0.35
const MAX_ZOOM := 3.0

var _map_size := Vector2(800.0, 500.0)
var _polygons: Dictionary = {}
var _geometry_error := ""
var _province_data: Dictionary = {}
var _country_colors: Dictionary = {}
var _hovered_id := ""
var _selected_id := ""
var _road_start_id := ""
var _road_end_id := ""
var _auto_advance_origin_id := ""
var _auto_advance_target_id := ""
var _auto_advance_path: Array = []
var _auto_advance_preview_path: Array = []
var _auto_advance_stop_reason := ""
var _roads: Array = []
var _frontlines: Array = []
var _armies: Array = []
var _pan := Vector2.ZERO
var _zoom := 1.0
var _dragging := false
var _view_initialized := false


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true
    resized.connect(_initialize_view)
    _initialize_view()


func load_map_geometry(path: String) -> bool:
    _geometry_error = ""
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        _geometry_error = "Cannot open map geometry: %s" % path
        return false
    var document = JSON.parse_string(file.get_as_text())
    if not document is Dictionary:
        _geometry_error = "Map geometry root must be an object"
        return false
    if int(document.get("schema_version", 0)) != 2:
        _geometry_error = "Unsupported map geometry schema version"
        return false
    var size_data: Array = document.get("map_size", [])
    if size_data.size() != 2 or float(size_data[0]) <= 0 or float(size_data[1]) <= 0:
        _geometry_error = "Map geometry requires a positive map_size"
        return false

    var loaded_polygons: Dictionary = {}
    for entry: Dictionary in document.get("provinces", []):
        var province_id: String = entry.get("id", "")
        var points_data: Array = entry.get("polygon", [])
        if province_id.is_empty() or loaded_polygons.has(province_id) or points_data.size() < 3:
            _geometry_error = "Invalid or duplicate province geometry: %s" % province_id
            return false
        var polygon := PackedVector2Array()
        for coordinates: Array in points_data:
            if coordinates.size() != 2:
                _geometry_error = "Invalid polygon point for province: %s" % province_id
                return false
            polygon.append(Vector2(float(coordinates[0]), float(coordinates[1])))
        loaded_polygons[province_id] = polygon

    _map_size = Vector2(float(size_data[0]), float(size_data[1]))
    _polygons = loaded_polygons
    _view_initialized = false
    _initialize_view()
    return true


func geometry_error() -> String:
    return _geometry_error


func geometry_count() -> int:
    return _polygons.size()


func has_geometry(province_id: String) -> bool:
    return _polygons.has(province_id)


func set_scenario_data(provinces: Array, countries: Array) -> void:
    _province_data.clear()
    _country_colors.clear()
    for country: Dictionary in countries:
        var rgb: int = country["color_rgb"]
        _country_colors[country["id"]] = Color8(
            (rgb >> 16) & 255,
            (rgb >> 8) & 255,
            rgb & 255
        )
    for province: Dictionary in provinces:
        _province_data[province["id"]] = province
        if not _polygons.has(province["id"]):
            push_warning("Province has no map geometry: %s" % province["id"])
    queue_redraw()


func selected_province_id() -> String:
    return _selected_id


func set_road_selection(start_id: String, end_id: String) -> void:
    _road_start_id = start_id
    _road_end_id = end_id
    queue_redraw()


func set_auto_advance_target(origin_id: String, target_id: String) -> void:
    _auto_advance_origin_id = origin_id
    _auto_advance_target_id = target_id
    _auto_advance_path = [] if origin_id.is_empty() or target_id.is_empty() else [
        origin_id,
        target_id,
    ]
    _auto_advance_preview_path = _auto_advance_path.duplicate(true)
    _auto_advance_stop_reason = ""
    queue_redraw()


func set_auto_advance_path(path: Array) -> void:
    _auto_advance_path = path.duplicate(true)
    _auto_advance_preview_path = path.duplicate(true)
    _auto_advance_origin_id = "" if _auto_advance_path.is_empty() else String(_auto_advance_path.front())
    _auto_advance_target_id = "" if _auto_advance_path.is_empty() else String(_auto_advance_path.back())
    _auto_advance_stop_reason = ""
    queue_redraw()


func set_auto_advance_paths(full_path: Array, preview_path: Array, stop_reason: String) -> void:
    _auto_advance_path = full_path.duplicate(true)
    _auto_advance_preview_path = preview_path.duplicate(true)
    _auto_advance_origin_id = "" if _auto_advance_path.is_empty() else String(_auto_advance_path.front())
    _auto_advance_target_id = "" if _auto_advance_path.is_empty() else String(_auto_advance_path.back())
    _auto_advance_stop_reason = stop_reason
    queue_redraw()


func set_roads(roads: Array) -> void:
    _roads = roads.duplicate(true)
    queue_redraw()


func set_frontlines(frontlines: Array) -> void:
    _frontlines = frontlines.duplicate(true)
    queue_redraw()


func road_count() -> int:
    return _roads.size()


func set_armies(armies: Array) -> void:
    _armies = armies.duplicate(true)
    queue_redraw()


func army_count() -> int:
    return _armies.size()


func _blocked_auto_advance_province() -> String:
    if _auto_advance_path.size() < 2:
        return ""
    if _auto_advance_preview_path.is_empty():
        return "" if _auto_advance_path.is_empty() else String(_auto_advance_path.front())
    var preview_end := String(_auto_advance_preview_path.back())
    for index: int in range(0, _auto_advance_path.size() - 1):
        if String(_auto_advance_path[index]) == preview_end:
            return String(_auto_advance_path[index + 1])
    return ""


func _draw_advance_legend() -> void:
    var origin := Vector2(16, size.y - 48)
    var text_color := Color("d8e6f5")
    draw_rect(Rect2(origin - Vector2(8, 20), Vector2(500, 28)), Color(0.04, 0.07, 0.11, 0.72))
    draw_line(origin + Vector2(0, -5), origin + Vector2(28, -5), Color("80deea"), 5.0, true)
    draw_string(
        ThemeDB.fallback_font,
        origin + Vector2(36, 0),
        "本回合推进",
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        13,
        text_color
    )
    draw_line(origin + Vector2(130, -5), origin + Vector2(158, -5), Color("244f6f"), 4.0, true)
    draw_string(
        ThemeDB.fallback_font,
        origin + Vector2(166, 0),
        "长期目标路线",
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        13,
        text_color
    )
    if _auto_advance_stop_reason == "enemy_border":
        draw_circle(origin + Vector2(308, -5), 6.0, Color("ff4d4d"))
        draw_string(
            ThemeDB.fallback_font,
            origin + Vector2(322, 0),
            "敌方边境停止",
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            13,
            text_color
        )


func province_at_map_position(map_position: Vector2) -> String:
    for province_id: String in _polygons:
        if Geometry2D.is_point_in_polygon(map_position, _polygons[province_id]):
            return province_id
    return ""


func _initialize_view() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return
    if not _view_initialized:
        _zoom = clampf(
            minf((size.x - 48.0) / _map_size.x, (size.y - 72.0) / _map_size.y),
            MIN_ZOOM,
            1.2
        )
        _pan = (size - _map_size * _zoom) * 0.5
        _view_initialized = true
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("182235"))
    draw_set_transform(_pan, 0.0, Vector2.ONE * _zoom)

    for province_id: String in _polygons:
        var polygon: PackedVector2Array = _polygons[province_id]
        var province: Dictionary = _province_data.get(province_id, {})
        var owner_id: String = province.get("owner_id", "")
        var color: Color = _country_colors.get(owner_id, Color("596579"))
        match province.get("terrain", "plains"):
            "forest": color = color.darkened(0.16)
            "hills": color = color.darkened(0.08)
            "mountains": color = color.darkened(0.28)
        if province_id == _selected_id:
            color = color.lightened(0.28)
        elif province_id == _hovered_id:
            color = color.lightened(0.14)

        draw_colored_polygon(polygon, color)
        var outline := PackedVector2Array(polygon)
        outline.append(polygon[0])
        var outline_color := Color("d5deed")
        var outline_width := 2.0
        if province_id == _road_start_id:
            outline_color = Color("ffe082")
            outline_width = 5.0
        elif province_id == _road_end_id:
            outline_color = Color("ffb74d")
            outline_width = 5.0
        draw_polyline(outline, outline_color, outline_width / _zoom, true)

        if not province.is_empty():
            var center := _polygon_center(polygon)
            var name: String = province.get("name", province_id)
            var label_size := 12
            var text_size := ThemeDB.fallback_font.get_string_size(
                name,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                label_size
            )
            draw_string(
                ThemeDB.fallback_font,
                center - Vector2(text_size.x * 0.5, -text_size.y * 0.25),
                name,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                label_size,
                Color.WHITE
            )

    for road: Dictionary in _roads:
        var province_a: String = road.get("province_a", "")
        var province_b: String = road.get("province_b", "")
        if not _polygons.has(province_a) or not _polygons.has(province_b):
            continue
        var start := _polygon_center(_polygons[province_a])
        var end := _polygon_center(_polygons[province_b])
        draw_line(start, end, Color("f4d35e"), 7.0 / _zoom, true)
        draw_circle(start, 6.0 / _zoom, Color("fff3b0"))
        draw_circle(end, 6.0 / _zoom, Color("fff3b0"))

    for frontline: Dictionary in _frontlines:
        var province_a: String = frontline.get("province_a", "")
        var province_b: String = frontline.get("province_b", "")
        if not _polygons.has(province_a) or not _polygons.has(province_b):
            continue
        var start := _polygon_center(_polygons[province_a])
        var end := _polygon_center(_polygons[province_b])
        draw_line(start, end, Color("ff4d4d"), 5.0 / _zoom, true)
        draw_circle(start, 5.0 / _zoom, Color("ffb3b3"))
        draw_circle(end, 5.0 / _zoom, Color("ffb3b3"))

    if not _road_start_id.is_empty() and not _road_end_id.is_empty():
        var preview_start := _polygon_center(_polygons[_road_start_id])
        var preview_end := _polygon_center(_polygons[_road_end_id])
        draw_line(preview_start, preview_end, Color("fff0a6"), 3.0 / _zoom, true)

    if _auto_advance_path.size() >= 2:
        for index: int in range(1, _auto_advance_path.size()):
            var previous_id := String(_auto_advance_path[index - 1])
            var next_id := String(_auto_advance_path[index])
            if not _polygons.has(previous_id) or not _polygons.has(next_id):
                continue
            var advance_start := _polygon_center(_polygons[previous_id])
            var advance_end := _polygon_center(_polygons[next_id])
            draw_line(advance_start, advance_end, Color("244f6f"), 3.0 / _zoom, true)
            draw_circle(advance_end, 4.0 / _zoom, Color("3f6f91"))

    if _auto_advance_preview_path.size() >= 2:
        for index: int in range(1, _auto_advance_preview_path.size()):
            var previous_id := String(_auto_advance_preview_path[index - 1])
            var next_id := String(_auto_advance_preview_path[index])
            if not _polygons.has(previous_id) or not _polygons.has(next_id):
                continue
            var advance_start := _polygon_center(_polygons[previous_id])
            var advance_end := _polygon_center(_polygons[next_id])
            draw_line(advance_start, advance_end, Color("80deea"), 5.0 / _zoom, true)
            draw_circle(advance_start, 5.0 / _zoom, Color("b2ebf2"))
            draw_circle(advance_end, 7.0 / _zoom, Color("00e5ff"))

    if _auto_advance_stop_reason == "enemy_border" and _auto_advance_path.size() >= 2:
        var blocked_id := _blocked_auto_advance_province()
        if not blocked_id.is_empty() and _polygons.has(blocked_id):
            var blocked_center := _polygon_center(_polygons[blocked_id])
            draw_circle(blocked_center, 9.0 / _zoom, Color("ff4d4d"))
            draw_arc(blocked_center, 13.0 / _zoom, 0.0, TAU, 24, Color("ffd6d6"), 3.0 / _zoom, true)

    var armies_by_province: Dictionary = {}
    for army: Dictionary in _armies:
        var province_id: String = army.get("province_id", "")
        var aggregate: Dictionary = armies_by_province.get(
            province_id,
            {"manpower": 0, "movement_points": 0.0}
        )
        aggregate["manpower"] += int(army.get("manpower", 0))
        aggregate["movement_points"] += float(army.get("movement_points", 0))
        armies_by_province[province_id] = aggregate
    for province_id: String in armies_by_province:
        if not _polygons.has(province_id):
            continue
        var center := _polygon_center(_polygons[province_id])
        var radius := 22.0 / _zoom
        draw_circle(center, radius, Color("202938"))
        draw_arc(center, radius, 0.0, TAU, 24, Color("f7f1d0"), 3.0 / _zoom, true)
        var army_data: Dictionary = armies_by_province[province_id]
        var manpower_text := "%d · 移%s" % [
            army_data["manpower"], GameText.movement_points(army_data["movement_points"])
        ]
        var text_size := ThemeDB.fallback_font.get_string_size(
            manpower_text,
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            14
        )
        draw_string(
            ThemeDB.fallback_font,
            center - Vector2(text_size.x * 0.5, -text_size.y * 0.25),
            manpower_text,
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            14,
            Color.WHITE
        )

    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    draw_string(
        ThemeDB.fallback_font,
        Vector2(16, size.y - 14),
        "左键选择 · 中键拖动 · 滚轮缩放",
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        15,
        Color("aebbd0")
    )
    if _auto_advance_path.size() >= 2:
        _draw_advance_legend()


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_MIDDLE:
            _dragging = button.pressed
            accept_event()
        elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
            var hit := _hit_test(button.position)
            if hit != _selected_id:
                _selected_id = hit
                queue_redraw()
            if hit.is_empty():
                map_blank_clicked.emit()
            elif button.double_click:
                province_double_clicked.emit(hit)
            else:
                province_clicked.emit(hit)
            province_selected.emit(hit)
            accept_event()
        elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            var old_zoom := _zoom
            var factor := 1.12 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
            _zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
            var map_point := (button.position - _pan) / old_zoom
            _pan = button.position - map_point * _zoom
            queue_redraw()
            accept_event()
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if _dragging:
            _pan += motion.relative
            queue_redraw()
            accept_event()
        else:
            var hit := _hit_test(motion.position)
            if hit != _hovered_id:
                _hovered_id = hit
                province_hovered.emit(hit)
                queue_redraw()


func _hit_test(local_position: Vector2) -> String:
    var map_position := (local_position - _pan) / _zoom
    return province_at_map_position(map_position)


func _polygon_center(polygon: PackedVector2Array) -> Vector2:
    var center := Vector2.ZERO
    for point: Vector2 in polygon:
        center += point
    return center / polygon.size()
