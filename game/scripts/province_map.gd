class_name ProvinceMap
extends Control

const CITY_ICON := preload("res://assets/maps/icons/city.png")
const CAPITAL_ICON := preload("res://assets/maps/icons/capital.png")
const PLAINS_ICON := preload("res://assets/maps/icons/terrain_plains.png")
const FOREST_ICON := preload("res://assets/maps/icons/terrain_forest.png")
const HILLS_ICON := preload("res://assets/maps/icons/terrain_hills.png")
const MOUNTAINS_ICON := preload("res://assets/maps/icons/terrain_mountains.png")
const ARMY_ICON := preload("res://assets/maps/icons/army.png")

signal province_hovered(province_id: String)
signal province_selected(province_id: String)
signal province_clicked(province_id: String)
signal province_double_clicked(province_id: String)
signal map_blank_clicked

const MIN_ZOOM := 0.35
const MAX_ZOOM := 3.0

var _map_size := Vector2(800.0, 500.0)
var _cell_size := 80.0
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


func load_grid_layout(path: String) -> bool:
    _geometry_error = ""
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        _geometry_error = "Cannot open grid map layout: %s" % path
        return false
    var document = JSON.parse_string(file.get_as_text())
    if not document is Dictionary:
        _geometry_error = "Grid map layout root must be an object"
        return false
    if int(document.get("schema_version", 0)) != 1 or \
            String(document.get("layout_id", "")) != "generated_grid_v1":
        _geometry_error = "Unsupported grid map layout"
        return false
    var width := int(document.get("width", 0))
    var height := int(document.get("height", 0))
    var cell_size := int(document.get("cell_size", 0))
    if width != 9 or height != 9 or cell_size <= 0:
        _geometry_error = "Grid map layout requires a 9x9 positive-cell grid"
        return false

    var loaded_polygons: Dictionary = {}
    var capital_by_cell: Dictionary = {}
    var capital_groups: Dictionary = {}
    var countries: Array = document.get("countries", [])
    if countries.size() != 4:
        _geometry_error = "Grid map layout requires four countries"
        return false
    for entry: Dictionary in countries:
        var country_id := String(entry.get("id", ""))
        var capital_cells: Array = entry.get("capital_cells", [])
        if country_id.is_empty() or capital_cells.size() != 4:
            _geometry_error = "Invalid capital layout for %s" % country_id
            return false
        var capital_id := "capital_%s" % country_id
        var coordinates_for_capital: Array[Vector2i] = []
        for coordinates: Array in capital_cells:
            if coordinates.size() != 2:
                _geometry_error = "Invalid capital coordinate for %s" % country_id
                return false
            var coordinate := Vector2i(int(coordinates[0]), int(coordinates[1]))
            if coordinate.x < 1 or coordinate.x > width or \
                    coordinate.y < 1 or coordinate.y > height:
                _geometry_error = "Capital coordinate is outside the grid"
                return false
            var key := "%d_%d" % [coordinate.x, coordinate.y]
            if capital_by_cell.has(key):
                _geometry_error = "Capital cells overlap"
                return false
            capital_by_cell[key] = capital_id
            coordinates_for_capital.append(coordinate)
        capital_groups[capital_id] = coordinates_for_capital

    for y in range(1, height + 1):
        for x in range(1, width + 1):
            var key := "%d_%d" % [x, y]
            if capital_by_cell.has(key):
                continue
            loaded_polygons["cell_%d_%d" % [x, y]] = _grid_rectangle(
                x, y, x, y, height, cell_size
            )

    for capital_id: String in capital_groups:
        var cells: Array[Vector2i] = capital_groups[capital_id]
        var minimum := cells[0]
        var maximum := cells[0]
        for coordinate: Vector2i in cells:
            minimum.x = mini(minimum.x, coordinate.x)
            minimum.y = mini(minimum.y, coordinate.y)
            maximum.x = maxi(maximum.x, coordinate.x)
            maximum.y = maxi(maximum.y, coordinate.y)
        if maximum - minimum != Vector2i(1, 1):
            _geometry_error = "Capital must be a 2x2 square: %s" % capital_id
            return false
        loaded_polygons[capital_id] = _grid_rectangle(
            minimum.x, minimum.y, maximum.x, maximum.y, height, cell_size
        )

    if loaded_polygons.size() != 69:
        _geometry_error = "Grid layout did not produce 69 province polygons"
        return false

    _cell_size = float(cell_size)
    _map_size = Vector2(float(width * cell_size), float(height * cell_size))
    _polygons = loaded_polygons
    _view_initialized = false
    _initialize_view()
    return true


func _grid_rectangle(
        minimum_x: int,
        minimum_y: int,
        maximum_x: int,
        maximum_y: int,
        height: int,
        cell_size: int
) -> PackedVector2Array:
    var left := float(minimum_x - 1) * cell_size
    var right := float(maximum_x) * cell_size
    var top := float(height - maximum_y) * cell_size
    var bottom := float(height - minimum_y + 1) * cell_size
    return PackedVector2Array([
        Vector2(left, top),
        Vector2(right, top),
        Vector2(right, bottom),
        Vector2(left, bottom),
    ])


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


func icon_layout_for_province(province_id: String) -> Dictionary:
    if not _polygons.has(province_id):
        return {}
    var province_armies: Array = []
    for army: Dictionary in _armies:
        if String(army.get("province_id", "")) == province_id:
            province_armies.append(army)
    province_armies.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
        return String(left.get("id", "")) < String(right.get("id", ""))
    )
    return _icon_layout(province_id, province_armies)


func _icon_layout(province_id: String, province_armies: Array) -> Dictionary:
    var province: Dictionary = _province_data.get(province_id, {})
    var bounds := _polygon_bounds(_polygons[province_id])
    var is_capital := province_id.begins_with("capital_") or \
            String(province.get("terrain", "")) == "capital"
    var city_size := _cell_size * (0.3 if is_capital else 0.2)
    var result := {
        "city_kind": "capital" if is_capital else "city",
        "city_rect": Rect2(
            bounds.get_center() - Vector2.ONE * city_size * 0.5,
            Vector2.ONE * city_size
        ),
        "army_rects": [],
        "army_ids": [],
        "overflow_count": 0,
    }
    if not is_capital:
        result["terrain_kind"] = String(province.get("terrain", "plains"))
        result["terrain_rect"] = Rect2(
            bounds.position,
            Vector2.ONE * _cell_size * 0.2
        )

    var icon_size := Vector2(_cell_size * 0.1, _cell_size * 0.2)
    var columns := 3
    var rows := maxi(1, int(floor(bounds.size.y / icon_size.y)))
    var capacity := columns * rows
    var visible_count := province_armies.size()
    if visible_count > capacity:
        visible_count = capacity - 1
        result["overflow_count"] = province_armies.size() - visible_count
    var strip_left := bounds.end.x - icon_size.x * columns
    for index: int in range(visible_count):
        var rect := Rect2(
            Vector2(
                strip_left + float(index % columns) * icon_size.x,
                bounds.position.y + float(index / columns) * icon_size.y
            ),
            icon_size
        )
        result["army_rects"].append(rect)
        result["army_ids"].append(String(province_armies[index].get("id", "")))
    if int(result["overflow_count"]) > 0:
        var overflow_index := capacity - 1
        result["overflow_rect"] = Rect2(
            Vector2(
                strip_left + float(overflow_index % columns) * icon_size.x,
                bounds.position.y + float(overflow_index / columns) * icon_size.y
            ),
            icon_size
        )
    return result


func _all_icon_layouts() -> Dictionary:
    var armies_by_province: Dictionary = {}
    for army: Dictionary in _armies:
        var province_id := String(army.get("province_id", ""))
        if not armies_by_province.has(province_id):
            armies_by_province[province_id] = []
        armies_by_province[province_id].append(army)
    for province_id: String in armies_by_province:
        armies_by_province[province_id].sort_custom(
            func(left: Dictionary, right: Dictionary) -> bool:
                return String(left.get("id", "")) < String(right.get("id", ""))
        )
    var layouts: Dictionary = {}
    for province_id: String in _polygons:
        layouts[province_id] = _icon_layout(
            province_id,
            armies_by_province.get(province_id, [])
        )
    return layouts


func _terrain_icon(terrain: String) -> Texture2D:
    match terrain:
        "forest": return FOREST_ICON
        "hills": return HILLS_ICON
        "mountains": return MOUNTAINS_ICON
        _: return PLAINS_ICON


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
    var icon_layouts := _all_icon_layouts()

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
            var icon_layout: Dictionary = icon_layouts[province_id]
            var city_texture: Texture2D = CAPITAL_ICON \
                    if icon_layout["city_kind"] == "capital" else CITY_ICON
            draw_texture_rect(city_texture, icon_layout["city_rect"], false)
            if icon_layout.has("terrain_rect"):
                draw_texture_rect(
                    _terrain_icon(icon_layout["terrain_kind"]),
                    icon_layout["terrain_rect"],
                    false
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

    for province_id: String in _polygons:
        var icon_layout: Dictionary = icon_layouts[province_id]
        for army_rect: Rect2 in icon_layout.get("army_rects", []):
            draw_texture_rect(ARMY_ICON, army_rect, false)
        var overflow_count := int(icon_layout.get("overflow_count", 0))
        if overflow_count > 0:
            var overflow_rect: Rect2 = icon_layout["overflow_rect"]
            draw_rect(overflow_rect, Color(0.05, 0.08, 0.12, 0.92), true)
            draw_string(
                ThemeDB.fallback_font,
                overflow_rect.position + Vector2(0.0, overflow_rect.size.y * 0.72),
                "+%d" % overflow_count,
                HORIZONTAL_ALIGNMENT_CENTER,
                overflow_rect.size.x,
                7,
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


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
    if polygon.is_empty():
        return Rect2()
    var minimum := polygon[0]
    var maximum := polygon[0]
    for point: Vector2 in polygon:
        minimum.x = minf(minimum.x, point.x)
        minimum.y = minf(minimum.y, point.y)
        maximum.x = maxf(maximum.x, point.x)
        maximum.y = maxf(maximum.y, point.y)
    return Rect2(minimum, maximum - minimum)


func _polygon_center(polygon: PackedVector2Array) -> Vector2:
    var center := Vector2.ZERO
    for point: Vector2 in polygon:
        center += point
    return center / polygon.size()
