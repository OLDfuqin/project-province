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

    var result: Dictionary = bridge.recruit_army("auroria", "northreach", 1000)
    if not result.get("accepted", false) or result.get("cost", 0) != 1000:
        push_error("Bridge recruitment failed: %s" % result.get("error", "unknown"))
        bridge.free()
        quit(1)
        return

    var armies: Array = bridge.get_army_summaries()
    var northreach: Dictionary = {}
    var auroria: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province["id"] == "northreach":
            northreach = province
    for country: Dictionary in bridge.get_country_summaries():
        if country["id"] == "auroria":
            auroria = country
    if armies.size() != 1 or armies[0]["manpower"] != 1000 or \
            northreach.get("soldier_population", -1) != 1000 or \
            auroria.get("treasury", -1) != 9000:
        push_error("Recruitment was not reflected in bridge snapshots")
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge army recruitment smoke test passed")
    bridge.free()
    quit(0)
