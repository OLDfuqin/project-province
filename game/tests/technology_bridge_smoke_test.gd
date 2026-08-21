extends SceneTree


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if bridge == null:
        push_error("ProvinceBridge could not be instantiated")
        quit(1)
        return
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario load failed")
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")

    var research: Dictionary = bridge.research_technology("auroria", "roads")
    var military_research: Dictionary = bridge.research_technology("auroria", "military")
    var army: Dictionary = bridge.recruit_army("auroria", "northreach", 500)
    var road: Dictionary = bridge.build_road("auroria", "northreach", "westmark")
    bridge.advance_turn(1)
    var player_technology: Dictionary = {}
    for technology: Dictionary in bridge.get_technology_summaries():
        if technology["country_id"] == "auroria":
            player_technology = technology
    var army_after: Dictionary = {}
    for summary: Dictionary in bridge.get_army_summaries():
        if summary["id"] == army.get("army_id", ""):
            army_after = summary
    if not research.get("accepted", false) or research.get("cost", 0) != 1000 or \
            not road.get("accepted", false) or road.get("cost", 0) != 540 or \
            player_technology.get("roads_level", 0) != 1 or \
            not military_research.get("accepted", false) or \
            player_technology.get("military_level", 0) != 1 or \
            army_after.get("movement_points", 0) != 2.5:
        push_error("Technology effects were not reflected through the bridge")
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge technology smoke test passed")
    bridge.free()
    quit(0)
