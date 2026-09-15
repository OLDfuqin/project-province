class_name ProvinceMap
extends Control

const CITY_ICON := preload("res://assets/maps/icons/city.png")
const CAPITAL_ICON := preload("res://assets/maps/icons/capital.png")
const PLAINS_ICON := preload("res://assets/maps/icons/terrain_plains.png")
const FOREST_ICON := preload("res://assets/maps/icons/terrain_forest.png")
const HILLS_ICON := preload("res://assets/maps/icons/terrain_hills.png")
const MOUNTAINS_ICON := preload("res://assets/maps/icons/terrain_mountains.png")
const ARMY_ICON := preload("res://assets/maps/icons/army.png")
const VISUAL_GEOMETRY_SCRIPT := preload("res://scripts/ui/visual_map_geometry.gd")

signal province_hovered(province_id: String)
signal province_hover_changed(province_id: String, screen_position: Vector2)
signal province_selected(province_id: String)
signal province_clicked(province_id: String)
signal province_double_clicked(province_id: String)
signal map_blank_clicked

const MIN_ZOOM := 0.35
const MAX_ZOOM := 3.0
const MAP_MODES := ["political", "terrain", "economy", "military", "roads"]
const TERRAIN_COLORS := {
    "plains": Color("789b67"),
    "forest": Color("3f7650"),
    "hills": Color("967b55"),
    "mountains": Color("77808c"),
    "capital": Color("b28b52"),
}
const VISUAL_GEOMETRY_SEED := 0x51A7
const ICON_SAFE_MARGIN_RATIO := 0.06

var _map_size := Vector2(800.0, 500.0)
var _cell_size := 80.0
var _polygons: Dictionary = {}
var _visual_geometry: RefCounted
var _geometry_error := ""
var _province_data: Dictionary = {}
var _country_colors: Dictionary = {}
var _map_mode := "political"
var _reachable_highlights: Array[String] = []
var _attackable_highlights: Array[String] = []
var _road_target_highlights: Array[String] = []
var _draw_observation: Dictionary = {}
var draw_diagnostics_enabled := false
var logical_grid_debug_enabled := false
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
    mouse_exited.connect(_clear_hover)
    _initialize_view()


func _clear_hover() -> void:
    if _hovered_id.is_empty():
        return
    _hovered_id = ""
    province_hovered.emit("")
    province_hover_changed.emit("", Vector2.ZERO)
    queue_redraw()


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

    var visual_geometry: RefCounted = VISUAL_GEOMETRY_SCRIPT.new()
    if not visual_geometry.configure_from_layout(document, VISUAL_GEOMETRY_SEED):
        _geometry_error = "Visual geometry failed: %s" % visual_geometry.error()
        return false
    loaded_polygons = visual_geometry.polygons()

    _cell_size = float(cell_size)
    _map_size = Vector2(float(width * cell_size), float(height * cell_size))
    _polygons = loaded_polygons
    _visual_geometry = visual_geometry
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


func visual_geometry_signature() -> String:
    return "" if _visual_geometry == null else _visual_geometry.geometry_signature()


func visual_validation_report() -> Dictionary:
    return {} if _visual_geometry == null else _visual_geometry.validation_report()


func visual_region_contains_point(region_id: String, point: Vector2) -> bool:
    return _visual_geometry != null and _visual_geometry.region_contains_point(region_id, point)


func road_route_for(first_id: String, second_id: String) -> PackedVector2Array:
    return PackedVector2Array() if _visual_geometry == null else \
            _visual_geometry.route_between(first_id, second_id)


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
    _filter_interaction_highlights()
    queue_redraw()


func set_map_mode(mode: String) -> bool:
    if not MAP_MODES.has(mode):
        return false
    _map_mode = mode
    queue_redraw()
    return true


func map_mode() -> String:
    return _map_mode


func set_interaction_highlights(reachable: Array, attackable: Array, road_targets: Array) -> void:
    _reachable_highlights = _stable_highlight_ids(reachable)
    _attackable_highlights = _stable_highlight_ids(attackable)
    _road_target_highlights = _stable_highlight_ids(road_targets)
    queue_redraw()


func presentation_state() -> Dictionary:
    return {
        "map_mode": _map_mode,
        "reachable": _reachable_highlights.duplicate(),
        "attackable": _attackable_highlights.duplicate(),
        "road_targets": _road_target_highlights.duplicate(),
    }


func draw_observation() -> Dictionary:
    return _draw_observation.duplicate(true) if draw_diagnostics_enabled else {}


func _stable_highlight_ids(ids: Array) -> Array[String]:
    var stable: Array[String] = []
    for value: Variant in ids:
        var province_id := String(value)
        if province_id.is_empty() or stable.has(province_id) or \
                not _polygons.has(province_id) or not _province_data.has(province_id):
            continue
        stable.append(province_id)
    return stable


func _filter_interaction_highlights() -> void:
    _reachable_highlights = _stable_highlight_ids(_reachable_highlights)
    _attackable_highlights = _stable_highlight_ids(_attackable_highlights)
    _road_target_highlights = _stable_highlight_ids(_road_target_highlights)


func _interaction_fill_color(province_id: String, base_color: Color) -> Color:
    if _attackable_highlights.has(province_id):
        return base_color.lerp(Color("d85b5b"), 0.26)
    if _reachable_highlights.has(province_id):
        return base_color.lerp(Color("4c8dff"), 0.22)
    return base_color


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
    var bounds: Rect2 = _visual_geometry.logical_bounds(province_id) \
            if _visual_geometry != null else _polygon_bounds(_polygons[province_id])
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
            bounds.position + Vector2.ONE * _cell_size * ICON_SAFE_MARGIN_RATIO,
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
    var strip_left: float = bounds.end.x - icon_size.x * columns - \
            _cell_size * ICON_SAFE_MARGIN_RATIO
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
    return "" if _visual_geometry == null else _visual_geometry.hit_test(map_position)


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


func _province_fill_color(
        province: Dictionary,
        owner_id: String,
        fiscal_bounds: Vector2,
        manpower: int,
        maximum_manpower: int
) -> Color:
    var political := _country_colors.get(owner_id, Color("596579")) as Color
    match _map_mode:
        "terrain":
            return TERRAIN_COLORS.get(String(province.get("terrain", "plains")), TERRAIN_COLORS["plains"])
        "economy":
            if owner_id.is_empty() or owner_id == "neutral":
                return Color("596579")
            var income := float(province.get("fiscal_income", 0))
            var span := fiscal_bounds.y - fiscal_bounds.x
            var ratio := 0.5 if is_zero_approx(span) else clampf((income - fiscal_bounds.x) / span, 0.0, 1.0)
            return Color("35506a").lerp(Color("d6a64a"), ratio)
        "military":
            var ratio := 0.0 if maximum_manpower <= 0 else clampf(float(manpower) / maximum_manpower, 0.0, 1.0)
            return Color("283545").lerp(Color("b85c55"), ratio)
        "roads":
            return political.lerp(Color("596579"), 0.65).darkened(0.12)
        _:
            match String(province.get("terrain", "plains")):
                "forest":
                    return political.darkened(0.16)
                "hills":
                    return political.darkened(0.08)
                "mountains":
                    return political.darkened(0.28)
            return political


func _fiscal_income_bounds() -> Vector2:
    var minimum := INF
    var maximum := -INF
    for province: Dictionary in _province_data.values():
        if String(province.get("owner_id", "")) in ["", "neutral"]:
            continue
        var income := float(province.get("fiscal_income", 0))
        minimum = minf(minimum, income)
        maximum = maxf(maximum, income)
    return Vector2.ZERO if minimum == INF else Vector2(minimum, maximum)


func _stationed_manpower_by_province() -> Dictionary:
    var totals: Dictionary = {}
    for army: Dictionary in _armies:
        var province_id := String(army.get("province_id", ""))
        if not _province_data.has(province_id):
            continue
        totals[province_id] = int(totals.get(province_id, 0)) + int(army.get("manpower", 0))
    return totals


func _draw() -> void:
    var observed_fills: Dictionary = {}
    var observed_outline_colors: Dictionary = {}
    var observation := {
        "map_mode": _map_mode,
        "province_fills": observed_fills,
        "province_outline_colors": observed_outline_colors,
        "province_outlines": 0,
        "road_lines": 0,
        "city_icons": 0,
        "terrain_icons": 0,
        "army_icons": 0,
        "logical_grid_lines": 0,
    }
    draw_rect(Rect2(Vector2.ZERO, size), Color("182235"))
    draw_set_transform(_pan, 0.0, Vector2.ONE * _zoom)
    var icon_layouts := _all_icon_layouts()
    var fiscal_bounds := _fiscal_income_bounds()
    var stationed_manpower := _stationed_manpower_by_province()
    var maximum_manpower := 0
    for amount: int in stationed_manpower.values():
        maximum_manpower = maxi(maximum_manpower, amount)

    for province_id: String in _polygons:
        var polygon: PackedVector2Array = _polygons[province_id]
        var province: Dictionary = _province_data.get(province_id, {})
        var owner_id: String = province.get("owner_id", "")
        var color := _province_fill_color(
            province, owner_id, fiscal_bounds, int(stationed_manpower.get(province_id, 0)),
            maximum_manpower
        )
        color = _interaction_fill_color(province_id, color)
        if province_id == _selected_id:
            color = color.lightened(0.28)
        elif province_id == _hovered_id:
            color = color.lightened(0.14)

        if draw_diagnostics_enabled:
            observed_fills[province_id] = color
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
        elif _road_target_highlights.has(province_id):
            outline_color = Color("4fb69f")
            outline_width = 4.0
        elif _attackable_highlights.has(province_id):
            outline_color = Color("d85b5b")
            outline_width = 4.0
        elif _reachable_highlights.has(province_id):
            outline_color = Color("4c8dff")
            outline_width = 4.0
        elif province_id == _selected_id:
            outline_color = Color("d6a64a")
            outline_width = 4.0
        elif province_id == _hovered_id:
            outline_color = Color("e8eef7")
            outline_width = 3.0
        if draw_diagnostics_enabled:
            observed_outline_colors[province_id] = outline_color
        draw_polyline(outline, outline_color, outline_width / _zoom, true)
        if draw_diagnostics_enabled:
            observation["province_outlines"] = int(observation["province_outlines"]) + 1

        if not province.is_empty():
            var icon_layout: Dictionary = icon_layouts[province_id]
            var city_texture: Texture2D = CAPITAL_ICON \
                    if icon_layout["city_kind"] == "capital" else CITY_ICON
            draw_texture_rect(city_texture, icon_layout["city_rect"], false)
            if draw_diagnostics_enabled:
                observation["city_icons"] = int(observation["city_icons"]) + 1
            if icon_layout.has("terrain_rect"):
                draw_texture_rect(
                    _terrain_icon(icon_layout["terrain_kind"]),
                    icon_layout["terrain_rect"],
                    false
                )
                if draw_diagnostics_enabled:
                    observation["terrain_icons"] = int(observation["terrain_icons"]) + 1

    if logical_grid_debug_enabled:
        var logical_grid_color := Color(0.35, 0.9, 0.95, 0.58)
        for x: int in range(10):
            draw_dashed_line(
                Vector2(float(x) * _cell_size, 0.0),
                Vector2(float(x) * _cell_size, _map_size.y),
                logical_grid_color, 1.25 / _zoom, 8.0 / _zoom, true
            )
            if draw_diagnostics_enabled:
                observation["logical_grid_lines"] = int(observation["logical_grid_lines"]) + 1
        for y: int in range(10):
            draw_dashed_line(
                Vector2(0.0, float(y) * _cell_size),
                Vector2(_map_size.x, float(y) * _cell_size),
                logical_grid_color, 1.25 / _zoom, 8.0 / _zoom, true
            )
            if draw_diagnostics_enabled:
                observation["logical_grid_lines"] = int(observation["logical_grid_lines"]) + 1

    for road: Dictionary in _roads:
        var province_a: String = road.get("province_a", "")
        var province_b: String = road.get("province_b", "")
        if not _polygons.has(province_a) or not _polygons.has(province_b):
            continue
        var route := road_route_for(province_a, province_b)
        if route.is_empty():
            continue
        draw_polyline(route, Color("f4d35e"), 7.0 / _zoom, true)
        draw_circle(route[0], 6.0 / _zoom, Color("fff3b0"))
        draw_circle(route[-1], 6.0 / _zoom, Color("fff3b0"))
        if draw_diagnostics_enabled:
            observation["road_lines"] = int(observation["road_lines"]) + 1

    for frontline: Dictionary in _frontlines:
        var province_a: String = frontline.get("province_a", "")
        var province_b: String = frontline.get("province_b", "")
        if not _polygons.has(province_a) or not _polygons.has(province_b):
            continue
        var frontline_route := road_route_for(province_a, province_b)
        if frontline_route.is_empty():
            continue
        draw_polyline(frontline_route, Color("ff4d4d"), 5.0 / _zoom, true)
        draw_circle(frontline_route[0], 5.0 / _zoom, Color("ffb3b3"))
        draw_circle(frontline_route[-1], 5.0 / _zoom, Color("ffb3b3"))

    if not _road_start_id.is_empty() and not _road_end_id.is_empty():
        var preview_route := road_route_for(_road_start_id, _road_end_id)
        if not preview_route.is_empty():
            draw_polyline(preview_route, Color("fff0a6"), 3.0 / _zoom, true)

    if _auto_advance_path.size() >= 2:
        for index: int in range(1, _auto_advance_path.size()):
            var previous_id := String(_auto_advance_path[index - 1])
            var next_id := String(_auto_advance_path[index])
            if not _polygons.has(previous_id) or not _polygons.has(next_id):
                continue
            var advance_route := road_route_for(previous_id, next_id)
            if advance_route.is_empty():
                continue
            draw_polyline(advance_route, Color("244f6f"), 3.0 / _zoom, true)
            draw_circle(advance_route[-1], 4.0 / _zoom, Color("3f6f91"))

    if _auto_advance_preview_path.size() >= 2:
        for index: int in range(1, _auto_advance_preview_path.size()):
            var previous_id := String(_auto_advance_preview_path[index - 1])
            var next_id := String(_auto_advance_preview_path[index])
            if not _polygons.has(previous_id) or not _polygons.has(next_id):
                continue
            var preview_advance_route := road_route_for(previous_id, next_id)
            if preview_advance_route.is_empty():
                continue
            draw_polyline(preview_advance_route, Color("80deea"), 5.0 / _zoom, true)
            draw_circle(preview_advance_route[0], 5.0 / _zoom, Color("b2ebf2"))
            draw_circle(preview_advance_route[-1], 7.0 / _zoom, Color("00e5ff"))

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
            if draw_diagnostics_enabled:
                observation["army_icons"] = int(observation["army_icons"]) + 1
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
    _draw_observation = observation if draw_diagnostics_enabled else {}


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
                province_hover_changed.emit(hit, get_global_transform_with_canvas() * motion.position)
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
