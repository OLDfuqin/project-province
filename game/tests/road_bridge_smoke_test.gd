extends SceneTree


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

    bridge.research_technology("auroria", "roads")
    var result: Dictionary = bridge.build_road("auroria", "northreach", "westmark")
    if not result.get("accepted", false) or result.get("cost", 0) != 540:
        push_error("Bridge road command failed: %s" % result.get("error", "unknown"))
        bridge.free()
        quit(1)
        return

    var roads: Array = bridge.get_road_summaries()
    var auroria_treasury := -1
    for country: Dictionary in bridge.get_country_summaries():
        if country["id"] == "auroria":
            auroria_treasury = int(country["treasury"])
    if roads.size() != 1 or auroria_treasury != 8460:
        push_error("Bridge road result was not reflected in snapshots")
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge road integration smoke test passed")
    bridge.free()
    quit(0)
