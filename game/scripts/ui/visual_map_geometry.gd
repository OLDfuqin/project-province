class_name VisualMapGeometry
extends RefCounted

const VISUAL_VERSION := 1
const SEGMENT_COUNT := 5
const MIN_OFFSET_RATIO := 0.04
const MAX_OFFSET_RATIO := 0.06
const VALIDATION_EPSILON := 0.001

var _width := 0
var _height := 0
var _cell_size := 0.0
var _layout_id := ""
var _seed := 0
var _error := ""
var _polygons: Dictionary = {}
var _region_cells: Dictionary = {}
var _cell_regions: Dictionary = {}
var _edges: Dictionary = {}
var _boundary_directions: Dictionary = {}
var _validation: Dictionary = {}
var _fallback_edge_count := 0


func configure_from_layout(document: Dictionary, visual_seed: int) -> bool:
    _error = ""
    _width = int(document.get("width", 0))
    _height = int(document.get("height", 0))
    _cell_size = float(document.get("cell_size", 0))
    _layout_id = String(document.get("layout_id", ""))
    _seed = visual_seed
    if int(document.get("schema_version", 0)) != 1 or _layout_id.is_empty() or \
            _width <= 0 or _height <= 0 or _cell_size <= 0.0:
        _error = "Invalid grid layout metadata"
        return false

    _region_cells.clear()
    _cell_regions.clear()
    var capital_by_cell: Dictionary = {}
    for country_value: Variant in document.get("countries", []):
        var country: Dictionary = country_value
        var country_id := String(country.get("id", ""))
        var capital_id := "capital_%s" % country_id
        var capital_cells: Array = country.get("capital_cells", [])
        if country_id.is_empty() or capital_cells.size() != 4:
            _error = "Invalid capital layout for %s" % country_id
            return false
        for coordinate_value: Variant in capital_cells:
            var coordinate: Array = coordinate_value
            if coordinate.size() != 2:
                _error = "Invalid capital coordinate"
                return false
            var logical := Vector2i(int(coordinate[0]), int(coordinate[1]))
            var screen_cell := Vector2i(logical.x - 1, _height - logical.y)
            if screen_cell.x < 0 or screen_cell.x >= _width or \
                    screen_cell.y < 0 or screen_cell.y >= _height or \
                    capital_by_cell.has(screen_cell):
                _error = "Capital cells are outside the grid or overlap"
                return false
            capital_by_cell[screen_cell] = capital_id

    for screen_y: int in range(_height):
        for screen_x: int in range(_width):
            var cell := Vector2i(screen_x, screen_y)
            var region_id := String(capital_by_cell.get(cell, ""))
            if region_id.is_empty():
                var logical_y := _height - screen_y
                region_id = "cell_%d_%d" % [screen_x + 1, logical_y]
            if not _region_cells.has(region_id):
                _region_cells[region_id] = []
            _region_cells[region_id].append(cell)
            _cell_regions[cell] = region_id

    if _region_cells.size() != 69:
        _error = "Grid layout did not produce 69 region identities"
        return false

    for scale: float in [1.0, 0.65, 0.35, 0.0]:
        _build_geometry(scale)
        _validation = _validate_geometry()
        if _validation.get("valid", false):
            _fallback_edge_count = _edges.size() if is_zero_approx(scale) else 0
            _validation["fallback_edge_count"] = _fallback_edge_count
            return true
    _error = "Could not generate valid display geometry"
    return false


func error() -> String:
    return _error


func polygons() -> Dictionary:
    return _polygons.duplicate(true)


func source_cell_count() -> int:
    return _cell_regions.size()


func adjacency_pairs() -> Array[String]:
    var pairs: Array[String] = []
    for cell: Vector2i in _cell_regions:
        var first_id: String = _cell_regions[cell]
        for neighbor: Vector2i in [cell + Vector2i.RIGHT, cell + Vector2i.DOWN]:
            if not _cell_regions.has(neighbor):
                continue
            var second_id: String = _cell_regions[neighbor]
            if first_id == second_id:
                continue
            var pair := "%s|%s" % [
                first_id if first_id < second_id else second_id,
                second_id if first_id < second_id else first_id,
            ]
            if not pairs.has(pair):
                pairs.append(pair)
    pairs.sort()
    return pairs


func polygon(region_id: String) -> PackedVector2Array:
    return _polygons.get(region_id, PackedVector2Array())


func validation_report() -> Dictionary:
    return _validation.duplicate(true)


func _build_geometry(amplitude_scale: float) -> void:
    _edges.clear()
    _polygons.clear()
    _boundary_directions.clear()
    for y: int in range(_height + 1):
        for x: int in range(_width):
            _ensure_edge(Vector2i(x, y), Vector2i(x + 1, y), amplitude_scale)
    for x: int in range(_width + 1):
        for y: int in range(_height):
            _ensure_edge(Vector2i(x, y), Vector2i(x, y + 1), amplitude_scale)
    for region_id: String in _region_cells:
        _build_region_polygon(region_id)


func _ensure_edge(start: Vector2i, end: Vector2i, amplitude_scale: float) -> void:
    var key := _edge_key(start, end)
    if _edges.has(key):
        return
    var canonical_start := start
    var canonical_end := end
    if _vertex_less(end, start):
        canonical_start = end
        canonical_end = start
    var start_point := Vector2(canonical_start) * _cell_size
    var end_point := Vector2(canonical_end) * _cell_size
    var tangent := (end_point - start_point).normalized()
    var normal := Vector2(-tangent.y, tangent.x)
    var edge_hash := _stable_hash("%s|%d|%d" % [_layout_id, VISUAL_VERSION, _seed], key)
    var ratio := lerpf(MIN_OFFSET_RATIO, MAX_OFFSET_RATIO, float(edge_hash & 1023) / 1023.0)
    var sign_value := -1.0 if ((edge_hash >> 10) & 1) == 0 else 1.0
    var amplitude := _cell_size * ratio * sign_value * amplitude_scale
    var points := PackedVector2Array()
    for index: int in range(SEGMENT_COUNT + 1):
        var t := float(index) / float(SEGMENT_COUNT)
        var envelope := sin(PI * t)
        if is_zero_approx(tangent.y):
            envelope = 0.0 if t <= 0.2 or t >= 0.6 else \
                    sin(PI * inverse_lerp(0.2, 0.6, t))
        points.append(start_point.lerp(end_point, t) + normal * amplitude * envelope)
    _edges[key] = points


func _stable_hash(prefix: String, value: String) -> int:
    var hash_value: int = 2166136261
    for character: int in (prefix + "|" + value).to_utf8_buffer():
        hash_value = int((hash_value ^ character) * 16777619) & 0x7fffffff
    return hash_value


func _edge_key(first: Vector2i, second: Vector2i) -> String:
    var start := first
    var end := second
    if _vertex_less(second, first):
        start = second
        end = first
    return "%d,%d|%d,%d" % [start.x, start.y, end.x, end.y]


func _vertex_less(first: Vector2i, second: Vector2i) -> bool:
    return first.y < second.y or (first.y == second.y and first.x < second.x)


func _build_region_polygon(region_id: String) -> void:
    var occurrences: Dictionary = {}
    var directed: Dictionary = {}
    for cell: Vector2i in _region_cells[region_id]:
        var top_left := cell
        var top_right := cell + Vector2i.RIGHT
        var bottom_left := cell + Vector2i.DOWN
        var bottom_right := cell + Vector2i.ONE
        for pair: Array in [
            [top_left, top_right], [top_right, bottom_right],
            [bottom_right, bottom_left], [bottom_left, top_left],
        ]:
            var key := _edge_key(pair[0], pair[1])
            occurrences[key] = int(occurrences.get(key, 0)) + 1
            directed[key] = pair

    var boundary_pairs: Array = []
    for key: String in occurrences:
        if int(occurrences[key]) == 1:
            boundary_pairs.append(directed[key])
    var by_start: Dictionary = {}
    for pair: Array in boundary_pairs:
        by_start[pair[0]] = pair
    var first_pair: Array = boundary_pairs[0]
    for pair: Array in boundary_pairs:
        if _vertex_less(pair[0], first_pair[0]):
            first_pair = pair
    var ordered_pairs: Array = []
    var current: Array = first_pair
    while ordered_pairs.size() < boundary_pairs.size():
        ordered_pairs.append(current)
        current = by_start.get(current[1], [])
        if current.is_empty():
            break

    var polygon_points := PackedVector2Array()
    var direction_by_key: Dictionary = {}
    for pair_index: int in range(ordered_pairs.size()):
        var pair: Array = ordered_pairs[pair_index]
        var key := _edge_key(pair[0], pair[1])
        direction_by_key[key] = pair
        var edge_points: PackedVector2Array = _edges[key]
        var canonical_forward := not _vertex_less(pair[1], pair[0])
        if canonical_forward:
            for point_index: int in range(edge_points.size()):
                if pair_index > 0 and point_index == 0:
                    continue
                polygon_points.append(edge_points[point_index])
        else:
            for point_index: int in range(edge_points.size() - 1, -1, -1):
                if pair_index > 0 and point_index == edge_points.size() - 1:
                    continue
                polygon_points.append(edge_points[point_index])
    if polygon_points.size() > 1 and polygon_points[0].is_equal_approx(polygon_points[-1]):
        polygon_points.resize(polygon_points.size() - 1)
    _polygons[region_id] = polygon_points
    _boundary_directions[region_id] = direction_by_key


func shared_boundary(first_id: String, second_id: String) -> PackedVector2Array:
    if not _boundary_directions.has(first_id) or not _boundary_directions.has(second_id):
        return PackedVector2Array()
    var first_edges: Dictionary = _boundary_directions[first_id]
    var second_edges: Dictionary = _boundary_directions[second_id]
    var shared_keys: Array[String] = []
    for key: String in first_edges:
        if second_edges.has(key):
            shared_keys.append(key)
    shared_keys.sort()
    if shared_keys.is_empty():
        return PackedVector2Array()
    var key := shared_keys[0]
    var pair: Array = first_edges[key]
    var points: PackedVector2Array = _edges[key]
    if not _vertex_less(pair[1], pair[0]):
        return points.duplicate()
    var reversed := PackedVector2Array()
    for index: int in range(points.size() - 1, -1, -1):
        reversed.append(points[index])
    return reversed


func internal_edge_count(region_id: String) -> int:
    if not _region_cells.has(region_id):
        return -1
    var cells: Array = _region_cells[region_id]
    var count := 0
    var boundary: Dictionary = _boundary_directions.get(region_id, {})
    for cell: Vector2i in cells:
        for neighbor: Vector2i in [cell + Vector2i.RIGHT, cell + Vector2i.DOWN]:
            if not cells.has(neighbor):
                continue
            var first := Vector2i(maxi(cell.x, neighbor.x), maxi(cell.y, neighbor.y))
            var second := first + (Vector2i.DOWN if cell.x != neighbor.x else Vector2i.RIGHT)
            if boundary.has(_edge_key(first, second)):
                count += 1
    return count


func hit_test(point: Vector2) -> String:
    var hits: Array[String] = []
    for region_id: String in _polygons:
        var region_polygon: PackedVector2Array = _polygons[region_id]
        if Geometry2D.is_point_in_polygon(point, region_polygon) or \
                _point_on_polygon_boundary(point, region_polygon):
            hits.append(region_id)
    hits.sort()
    return "" if hits.is_empty() else hits[0]


func _point_on_polygon_boundary(point: Vector2, region_polygon: PackedVector2Array) -> bool:
    for index: int in range(region_polygon.size()):
        var closest := Geometry2D.get_closest_point_to_segment(
            point, region_polygon[index], region_polygon[(index + 1) % region_polygon.size()]
        )
        if closest.distance_to(point) <= VALIDATION_EPSILON:
            return true
    return false


func region_contains_point(region_id: String, point: Vector2) -> bool:
    var region_polygon: PackedVector2Array = polygon(region_id)
    return not region_polygon.is_empty() and (
        Geometry2D.is_point_in_polygon(point, region_polygon) or \
        _point_on_polygon_boundary(point, region_polygon)
    )


func safe_anchor(region_id: String) -> Vector2:
    var region_polygon: PackedVector2Array = polygon(region_id)
    if region_polygon.is_empty():
        return Vector2.ZERO
    var logical_center := logical_bounds(region_id).get_center()
    if region_contains_point(region_id, logical_center):
        return logical_center
    var total := Vector2.ZERO
    for point: Vector2 in region_polygon:
        total += point
    var average := total / float(region_polygon.size())
    return average if region_contains_point(region_id, average) else \
            _polygon_bounds(region_polygon).get_center()


func logical_bounds(region_id: String) -> Rect2:
    if not _region_cells.has(region_id):
        return Rect2()
    var cells: Array = _region_cells[region_id]
    var minimum: Vector2i = cells[0]
    var maximum: Vector2i = cells[0]
    for cell: Vector2i in cells:
        minimum.x = mini(minimum.x, cell.x)
        minimum.y = mini(minimum.y, cell.y)
        maximum.x = maxi(maximum.x, cell.x)
        maximum.y = maxi(maximum.y, cell.y)
    return Rect2(Vector2(minimum) * _cell_size, Vector2(maximum - minimum + Vector2i.ONE) * _cell_size)


func route_between(first_id: String, second_id: String) -> PackedVector2Array:
    var boundary := shared_boundary(first_id, second_id)
    if boundary.is_empty():
        return PackedVector2Array()
    var first_anchor := safe_anchor(first_id)
    var second_anchor := safe_anchor(second_id)
    var candidates: Array[Vector2] = []
    for index: int in range(boundary.size() - 1):
        candidates.append(boundary[index].lerp(boundary[index + 1], 0.5))
    for point: Vector2 in boundary:
        candidates.append(point)
    candidates.sort_custom(func(left: Vector2, right: Vector2) -> bool:
        return left.distance_squared_to((first_anchor + second_anchor) * 0.5) < \
                right.distance_squared_to((first_anchor + second_anchor) * 0.5)
    )
    for crossing: Vector2 in candidates:
        var route := PackedVector2Array([first_anchor, crossing, second_anchor])
        if route_is_valid(first_id, second_id, route):
            return route
    return PackedVector2Array()


func route_is_valid(
        first_id: String, second_id: String, route: PackedVector2Array
) -> bool:
    if route.size() != 3 or shared_boundary(first_id, second_id).is_empty():
        return false
    if not region_contains_point(first_id, route[1]) or \
            not region_contains_point(second_id, route[1]):
        return false
    return _segment_stays_in_region(first_id, route[0], route[1]) and \
            _segment_stays_in_region(second_id, route[2], route[1])


func _segment_stays_in_region(region_id: String, start: Vector2, end: Vector2) -> bool:
    var region_polygon: PackedVector2Array = polygon(region_id)
    if region_polygon.is_empty() or not region_contains_point(region_id, start) or \
            not region_contains_point(region_id, end):
        return false
    for index: int in range(region_polygon.size()):
        var intersection = Geometry2D.segment_intersects_segment(
            start, end, region_polygon[index], region_polygon[(index + 1) % region_polygon.size()]
        )
        if intersection != null and (intersection as Vector2).distance_to(end) > VALIDATION_EPSILON:
            return false
    return region_contains_point(region_id, start.lerp(end, 0.5))


func geometry_signature() -> String:
    var ids: Array[String] = []
    ids.assign(_polygons.keys())
    ids.sort()
    var parts: PackedStringArray = PackedStringArray([
        _layout_id, str(VISUAL_VERSION), str(_seed), str(_cell_size)
    ])
    for region_id: String in ids:
        parts.append(region_id)
        for point: Vector2 in _polygons[region_id]:
            parts.append("%.4f,%.4f" % [point.x, point.y])
    return str("|".join(parts).hash())


func _validate_geometry() -> Dictionary:
    var self_intersections := 0
    var non_positive_areas := 0
    for region_id: String in _polygons:
        var points: PackedVector2Array = _polygons[region_id]
        if _signed_area(points) <= VALIDATION_EPSILON:
            non_positive_areas += 1
        self_intersections += _self_intersection_count(points)
    var ownership: Dictionary = {}
    for region_id: String in _boundary_directions:
        for key: String in (_boundary_directions[region_id] as Dictionary):
            ownership[key] = int(ownership.get(key, 0)) + 1
    var gap_count := 0
    var overlap_count := 0
    for key: String in _edges:
        var expected := _expected_edge_owner_count(key)
        var actual := int(ownership.get(key, 0))
        if actual < expected:
            gap_count += expected - actual
        elif actual > expected:
            overlap_count += actual - expected
    var overlapping_region_pairs := 0
    var ids: Array[String] = []
    ids.assign(_polygons.keys())
    ids.sort()
    for first_index: int in range(ids.size()):
        for second_index: int in range(first_index + 1, ids.size()):
            var intersections: Array[PackedVector2Array] = Geometry2D.intersect_polygons(
                _polygons[ids[first_index]], _polygons[ids[second_index]]
            )
            var overlap_area := 0.0
            for intersection: PackedVector2Array in intersections:
                overlap_area += absf(_signed_area(intersection))
            if overlap_area > VALIDATION_EPSILON:
                overlapping_region_pairs += 1
    var valid := self_intersections == 0 and non_positive_areas == 0 and \
            gap_count == 0 and overlap_count == 0 and overlapping_region_pairs == 0
    return {
        "valid": valid,
        "self_intersections": self_intersections,
        "non_positive_areas": non_positive_areas,
        "gap_count": gap_count,
        "overlap_count": overlap_count,
        "overlapping_region_pairs": overlapping_region_pairs,
    }


func _expected_edge_owner_count(key: String) -> int:
    var halves := key.split("|")
    var first_parts := halves[0].split(",")
    var second_parts := halves[1].split(",")
    var first := Vector2i(int(first_parts[0]), int(first_parts[1]))
    var second := Vector2i(int(second_parts[0]), int(second_parts[1]))
    var neighboring_cells: Array[Vector2i] = []
    if first.y == second.y:
        neighboring_cells.assign([
            Vector2i(first.x, first.y - 1), Vector2i(first.x, first.y),
        ])
    else:
        neighboring_cells.assign([
            Vector2i(first.x - 1, first.y), Vector2i(first.x, first.y),
        ])
    var owner_ids: Array[String] = []
    var present_cell_count := 0
    for cell: Vector2i in neighboring_cells:
        if not _cell_regions.has(cell):
            continue
        present_cell_count += 1
        var owner_id: String = _cell_regions[cell]
        if not owner_ids.has(owner_id):
            owner_ids.append(owner_id)
    if present_cell_count == 2 and owner_ids.size() == 1:
        return 0
    return owner_ids.size() if owner_ids.size() <= 1 else 2


func _signed_area(points: PackedVector2Array) -> float:
    var area := 0.0
    for index: int in range(points.size()):
        var current := points[index]
        var following := points[(index + 1) % points.size()]
        area += current.x * following.y - following.x * current.y
    return area * 0.5


func _self_intersection_count(points: PackedVector2Array) -> int:
    var count := 0
    for first_index: int in range(points.size()):
        var first_end := (first_index + 1) % points.size()
        for second_index: int in range(first_index + 1, points.size()):
            var second_end := (second_index + 1) % points.size()
            if first_index == second_index or first_end == second_index or \
                    second_end == first_index:
                continue
            var intersection = Geometry2D.segment_intersects_segment(
                points[first_index], points[first_end], points[second_index], points[second_end]
            )
            if intersection != null:
                count += 1
    return count


func _polygon_bounds(points: PackedVector2Array) -> Rect2:
    var minimum := points[0]
    var maximum := points[0]
    for point: Vector2 in points:
        minimum.x = minf(minimum.x, point.x)
        minimum.y = minf(minimum.y, point.y)
        maximum.x = maxf(maximum.x, point.x)
        maximum.y = maxf(maximum.y, point.y)
    return Rect2(minimum, maximum - minimum)
