class_name ProvinceMap
extends Control

signal province_hovered(province_id: String)
signal province_selected(province_id: String)

const MAP_SIZE := Vector2(800.0, 500.0)
const MIN_ZOOM := 0.35
const MAX_ZOOM := 3.0

var _polygons: Dictionary = {
    "northreach": PackedVector2Array([
        Vector2(0, 250), Vector2(0, 0), Vector2(200, 0),
        Vector2(250, 180), Vector2(220, 250)
    ]),
    "westmark": PackedVector2Array([
        Vector2(200, 0), Vector2(400, 0), Vector2(400, 160), Vector2(250, 180)
    ]),
    "greenvale": PackedVector2Array([
        Vector2(400, 0), Vector2(600, 0), Vector2(550, 180), Vector2(400, 160)
    ]),
    "sunmeadow": PackedVector2Array([
        Vector2(600, 0), Vector2(800, 0), Vector2(800, 250),
        Vector2(580, 250), Vector2(550, 180)
    ]),
    "blueharbor": PackedVector2Array([
        Vector2(800, 250), Vector2(800, 500), Vector2(600, 500),
        Vector2(550, 320), Vector2(580, 250)
    ]),
    "skyplain": PackedVector2Array([
        Vector2(600, 500), Vector2(400, 500), Vector2(400, 340), Vector2(550, 320)
    ]),
    "goldcoast": PackedVector2Array([
        Vector2(400, 500), Vector2(200, 500), Vector2(250, 320), Vector2(400, 340)
    ]),
    "redpass": PackedVector2Array([
        Vector2(200, 500), Vector2(0, 500), Vector2(0, 250),
        Vector2(220, 250), Vector2(250, 320)
    ]),
}

var _province_data: Dictionary = {}
var _country_colors: Dictionary = {}
var _hovered_id := ""
var _selected_id := ""
var _road_start_id := ""
var _road_end_id := ""
var _roads: Array = []
var _pan := Vector2.ZERO
var _zoom := 1.0
var _dragging := false
var _view_initialized := false


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true
    resized.connect(_initialize_view)
    _initialize_view()


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
    queue_redraw()


func selected_province_id() -> String:
    return _selected_id


func set_road_selection(start_id: String, end_id: String) -> void:
    _road_start_id = start_id
    _road_end_id = end_id
    queue_redraw()


func set_roads(roads: Array) -> void:
    _roads = roads.duplicate(true)
    queue_redraw()


func road_count() -> int:
    return _roads.size()


func province_at_map_position(map_position: Vector2) -> String:
    for province_id: String in _polygons:
        if Geometry2D.is_point_in_polygon(map_position, _polygons[province_id]):
            return province_id
    return ""


func _initialize_view() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return
    if not _view_initialized:
        _zoom = clampf(minf((size.x - 48.0) / MAP_SIZE.x, (size.y - 72.0) / MAP_SIZE.y), MIN_ZOOM, 1.2)
        _pan = (size - MAP_SIZE * _zoom) * 0.5
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
            var text_size := ThemeDB.fallback_font.get_string_size(
                name,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                17
            )
            draw_string(
                ThemeDB.fallback_font,
                center - Vector2(text_size.x * 0.5, -text_size.y * 0.25),
                name,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                17,
                Color.WHITE
            )

    draw_circle(Vector2(400, 250), 66, Color("233c59"))
    draw_string(
        ThemeDB.fallback_font,
        Vector2(370, 257),
        "内海",
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        18,
        Color("9fc6e8")
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

    if not _road_start_id.is_empty() and not _road_end_id.is_empty():
        var preview_start := _polygon_center(_polygons[_road_start_id])
        var preview_end := _polygon_center(_polygons[_road_end_id])
        draw_line(preview_start, preview_end, Color("fff0a6"), 3.0 / _zoom, true)

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
                province_selected.emit(hit)
                queue_redraw()
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
