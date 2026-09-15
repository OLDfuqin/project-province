extends SceneTree

const GEOMETRY_SCRIPT := preload("res://scripts/ui/visual_map_geometry.gd")


func _fail(message: String) -> void:
    push_error(message)
    quit(1)


func _reversed(points: PackedVector2Array) -> PackedVector2Array:
    var result := PackedVector2Array()
    for index: int in range(points.size() - 1, -1, -1):
        result.append(points[index])
    return result


func _expected_hit(geometry: RefCounted, point: Vector2) -> String:
    var hits: Array[String] = []
    for region_id: String in geometry.polygons():
        if geometry.region_contains_point(region_id, point):
            hits.append(region_id)
    hits.sort()
    return "" if hits.is_empty() else hits[0]


func _segment_has_only_terminal_boundary_contact(
        geometry: RefCounted, region_id: String, start: Vector2, end: Vector2
) -> bool:
    var polygon: PackedVector2Array = geometry.polygon(region_id)
    if not geometry.region_contains_point(region_id, start) or \
            not geometry.region_contains_point(region_id, end):
        return false
    for index: int in range(polygon.size()):
        var intersection = Geometry2D.segment_intersects_segment(
            start, end, polygon[index], polygon[(index + 1) % polygon.size()]
        )
        if intersection != null and (intersection as Vector2).distance_to(end) > 0.001:
            return false
    return geometry.region_contains_point(region_id, start.lerp(end, 0.5))


func _route_segments_stay_in_their_regions(
        geometry: RefCounted, route: PackedVector2Array, first: String, second: String
) -> bool:
    return route.size() == 3 and geometry.route_is_valid(first, second, route) and \
            _segment_has_only_terminal_boundary_contact(
                geometry, first, route[0], route[1]
            ) and _segment_has_only_terminal_boundary_contact(
                geometry, second, route[2], route[1]
            )


func _polyline_length(points: PackedVector2Array) -> float:
    var length := 0.0
    for index: int in range(points.size() - 1):
        length += points[index].distance_to(points[index + 1])
    return length


func _initialize() -> void:
    var document = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/grid_map_layout.json"
    ))
    var geometry: RefCounted = GEOMETRY_SCRIPT.new()
    if not geometry.configure_from_layout(document, 0x51A7):
        _fail("Visual geometry rejected the authoritative layout: %s" % geometry.error())
        return
    if geometry.polygons().size() != 69:
        _fail("Visual geometry did not preserve the 69-region identity map")
        return
    if geometry.source_cell_count() != 81:
        _fail("Visual geometry changed the authoritative 81 source cells")
        return

    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if bridge == null or not bridge.load_scenario(
            ProjectSettings.globalize_path("res://data"), 1000, 1):
        _fail("Could not load authoritative scenario for topology comparison")
        return
    var logical_pairs: Array[String] = []
    var neutral_count := 0
    var capital_count := 0
    for province: Dictionary in bridge.get_province_summaries():
        var province_id := String(province.get("id", ""))
        if province.get("owner_id", "") == "neutral":
            neutral_count += 1
        if province_id.begins_with("capital_"):
            capital_count += 1
        for neighbor_value: Variant in province.get("neighbors", []):
            var neighbor_id := String(neighbor_value)
            if province_id < neighbor_id:
                logical_pairs.append("%s|%s" % [province_id, neighbor_id])
    logical_pairs.sort()
    if neutral_count != 17 or capital_count != 4 or \
            geometry.adjacency_pairs() != logical_pairs:
        _fail("Display geometry changed the 4-capital/17-neutral logical topology")
        return

    var report: Dictionary = geometry.validation_report()
    if not report.get("valid", false) or report.get("self_intersections", -1) != 0 or \
            report.get("gap_count", -1) != 0 or report.get("overlap_count", -1) != 0 or \
            report.get("overlapping_region_pairs", -1) != 0:
        _fail("Generated geometry failed validation: %s" % report)
        return

    for pair_text: String in logical_pairs:
        var pair := pair_text.split("|")
        var shared_forward: PackedVector2Array = geometry.shared_boundary(pair[0], pair[1])
        var shared_reverse: PackedVector2Array = geometry.shared_boundary(pair[1], pair[0])
        if shared_forward.size() < 5 or shared_forward != _reversed(shared_reverse) or \
                _polyline_length(shared_forward) <= 1.0:
            _fail("Logical neighbors do not reuse one positive-length reversed edge: %s" % pair_text)
            return
        var middle_index := int((shared_forward.size() - 1) / 2)
        var boundary_probe := shared_forward[middle_index].lerp(
            shared_forward[middle_index + 1], 0.5
        )
        var tangent := (shared_forward[middle_index + 1] - shared_forward[middle_index]).normalized()
        var normal := Vector2(-tangent.y, tangent.x) * 0.05
        var plus_hit: String = geometry.hit_test(boundary_probe + normal)
        var minus_hit: String = geometry.hit_test(boundary_probe - normal)
        if plus_hit == minus_hit or not pair.has(plus_hit) or not pair.has(minus_hit):
            _fail("Shared-edge epsilon probes did not resolve to opposite neighbors: %s" % pair_text)
            return
        var expected_boundary_hit := pair[0] if pair[0] < pair[1] else pair[1]
        if geometry.hit_test(boundary_probe) != expected_boundary_hit:
            _fail("Shared-edge hit priority was not lexicographic: %s" % pair_text)
            return

    var shared_forward: PackedVector2Array = geometry.shared_boundary("cell_1_1", "cell_2_1")
    if absf(shared_forward[shared_forward.size() / 2].x - 80.0) < 0.5:
        _fail("Shared display boundary remained a straight logical grid edge")
        return

    for capital_id: String in [
        "capital_auroria", "capital_caelus", "capital_solmere", "capital_verdantia"
    ]:
        var capital_polygon: PackedVector2Array = geometry.polygon(capital_id)
        if capital_polygon.size() <= 8 or geometry.internal_edge_count(capital_id) != 0:
            _fail("Capital did not use a merged irregular outer outline: %s" % capital_id)
            return
        var capital_neighbors: Array[String] = []
        for pair_text: String in logical_pairs:
            var pair := pair_text.split("|")
            if pair[0] == capital_id:
                capital_neighbors.append(pair[1])
            elif pair[1] == capital_id:
                capital_neighbors.append(pair[0])
        if capital_neighbors.size() != 8:
            _fail("Capital did not retain exactly eight perimeter neighbors: %s" % capital_id)
            return
        for neighbor_id: String in capital_neighbors:
            if _polyline_length(geometry.shared_boundary(capital_id, neighbor_id)) <= 1.0:
                _fail("Capital neighbor lost its positive-length shared edge: %s|%s" % [
                    capital_id, neighbor_id,
                ])
                return

    var visual_midpoint: Vector2 = shared_forward[shared_forward.size() / 2]
    var logical_midpoint := Vector2(80.0, visual_midpoint.y)
    var displaced_probe := logical_midpoint.lerp(visual_midpoint, 0.5)
    var visual_hit: String = geometry.hit_test(displaced_probe)
    var logical_hit := "cell_1_1" if displaced_probe.x < 80.0 else "cell_2_1"
    if visual_hit.is_empty() or visual_hit == logical_hit:
        _fail("Hit testing did not follow the displaced display polygon across a rule edge")
        return
    var boundary_hit_a: String = geometry.hit_test(visual_midpoint)
    var boundary_hit_b: String = geometry.hit_test(visual_midpoint)
    if boundary_hit_a.is_empty() or boundary_hit_a != boundary_hit_b:
        _fail("Shared-boundary hit priority was not deterministic")
        return
    for grid_y: int in range(10):
        for grid_x: int in range(10):
            var grid_vertex := Vector2(grid_x, grid_y) * 80.0
            if geometry.hit_test(grid_vertex) != _expected_hit(geometry, grid_vertex):
                _fail("Grid-corner hit priority was not deterministic at %s" % grid_vertex)
                return
    for outside_point: Vector2 in [
        Vector2(-10, -10), Vector2(730, -10), Vector2(-10, 730), Vector2(730, 730),
    ]:
        if not geometry.hit_test(outside_point).is_empty():
            _fail("World-edge blank space resolved to a region: %s" % outside_point)
            return

    var clone: RefCounted = GEOMETRY_SCRIPT.new()
    clone.configure_from_layout(document, 0x51A7)
    if clone.geometry_signature() != geometry.geometry_signature():
        _fail("Same layout/version/seed did not reproduce identical geometry")
        return
    var original_signature: String = geometry.geometry_signature()
    if not geometry.configure_from_layout(document, 0x51A7) or \
            geometry.geometry_signature() != original_signature:
        _fail("Reconfiguring one geometry object changed the stable outline")
        return
    var alternate: RefCounted = GEOMETRY_SCRIPT.new()
    alternate.configure_from_layout(document, 0x51A8)
    if alternate.geometry_signature() == geometry.geometry_signature():
        _fail("Distinct visual seeds did not produce distinct geometry")
        return
    for seed: int in [0, 1, 2, 7, 42, 255, 1024, 0x51A7, 0x1234567, 0x7fffffff]:
        var seeded: RefCounted = GEOMETRY_SCRIPT.new()
        if not seeded.configure_from_layout(document, seed) or \
                not seeded.validation_report().get("valid", false):
            _fail("Geometry validation was unstable for visual seed %d" % seed)
            return
        for pair_text: String in seeded.adjacency_pairs():
            var pair := pair_text.split("|")
            var seeded_route: PackedVector2Array = seeded.route_between(pair[0], pair[1])
            if not _route_segments_stay_in_their_regions(
                    seeded, seeded_route, pair[0], pair[1]):
                _fail("Road route crossed a third/non-owning region for seed %d: %s" % [
                    seed, pair_text,
                ])
                return

    var route: PackedVector2Array = geometry.route_between("cell_1_1", "cell_2_1")
    if not _route_segments_stay_in_their_regions(
            geometry, route, "cell_1_1", "cell_2_1"
    ):
        _fail("Road route did not cross the real shared boundary inside its region pair")
        return

    print("Visual map geometry test passed")
    bridge.free()
    quit(0)
