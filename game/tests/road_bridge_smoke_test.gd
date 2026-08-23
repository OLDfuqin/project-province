extends SceneTree

const Helpers := preload("res://tests/generated_scenario_helpers.gd")


func _endpoint_cost(terrain: String) -> int:
    return {"plains": 300, "capital": 300, "forest": 500, "hills": 500, "mountains": 700}.get(terrain, 0)


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if bridge == null:
        push_error("ProvinceBridge could not be instantiated")
        quit(1)
        return

    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario load failed: %s" % bridge.get_last_error())
        bridge.free()
        quit(1)
        return

    for _level: int in range(3):
        bridge.research_technology("auroria", "roads")
    var pair := Helpers.first_adjacent_pair(bridge, "auroria")
    if pair.size() != 2:
        push_error("Generated scenario has no adjacent Auroria provinces")
        bridge.free()
        quit(1)
        return
    var first := Helpers.province_by_id(bridge, pair[0])
    var second := Helpers.province_by_id(bridge, pair[1])
    var expected_cost := int(floor(float(
        _endpoint_cost(first.get("terrain", "")) + _endpoint_cost(second.get("terrain", ""))
    ) * 0.7))
    var treasury_before := 0
    for country: Dictionary in bridge.get_country_summaries():
        if country["id"] == "auroria":
            treasury_before = int(country["treasury"])
    var result: Dictionary = bridge.build_road("auroria", pair[0], pair[1])
    if not result.get("accepted", false) or result.get("cost", 0) != expected_cost:
        push_error("Bridge road command failed: %s" % result.get("error", "unknown"))
        bridge.free()
        quit(1)
        return

    var roads: Array = bridge.get_road_summaries()
    var auroria_treasury := -1
    for country: Dictionary in bridge.get_country_summaries():
        if country["id"] == "auroria":
            auroria_treasury = int(country["treasury"])
    if roads.size() != 1 or auroria_treasury != treasury_before - expected_cost:
        push_error("Bridge road result was not reflected in snapshots")
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge road integration smoke test passed")
    bridge.free()
    quit(0)
