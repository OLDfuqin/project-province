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

    var road_result: Dictionary = bridge.build_road(
        "auroria", "northreach", "westmark"
    )
    var turn_result: Dictionary = bridge.advance_turn(1)
    var move_result: Dictionary = bridge.move_army(
        result["army_id"], "westmark"
    )
    armies = bridge.get_army_summaries()
    if not road_result.get("accepted", false) or \
            not turn_result.get("accepted", false) or \
            not move_result.get("accepted", false) or \
            move_result.get("movement_cost", 0) != 1 or \
            armies[0]["province_id"] != "westmark" or \
            armies[0]["movement_points"] != 1:
        push_error("Road movement was not reflected in bridge snapshots")
        bridge.free()
        quit(1)
        return

    var defender: Dictionary = bridge.recruit_army("verdantia", "greenvale", 500)
    var peace_entry: Dictionary = bridge.move_army(result["army_id"], "greenvale")
    var war_result: Dictionary = bridge.declare_war("auroria", "verdantia")
    bridge.advance_turn(1)
    var war_entry: Dictionary = bridge.move_army(result["army_id"], "greenvale")
    var relations: Array = bridge.get_diplomatic_relations()
    if peace_entry.get("accepted", false) or \
            not defender.get("accepted", false) or \
            not war_result.get("accepted", false) or \
            not war_entry.get("accepted", false) or \
            not war_entry.get("battle_occurred", false) or \
            not war_entry.get("attacker_won", false) or \
            not war_entry.get("province_occupied", false) or \
            relations.size() != 1 or relations[0].get("status", "") != "war":
        push_error("War declaration was not reflected in bridge state")
        bridge.free()
        quit(1)
        return

    var occupied_greenvale: Dictionary = {}
    var defender_after: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province["id"] == "greenvale":
            occupied_greenvale = province
    for army: Dictionary in bridge.get_army_summaries():
        if army["id"] == defender["army_id"]:
            defender_after = army
    if occupied_greenvale.get("owner_id", "") != "auroria" or \
            occupied_greenvale.get("legal_owner_id", "") != "verdantia" or \
            not occupied_greenvale.get("occupied", false) or \
            defender_after.get("province_id", "") != "sunmeadow":
        push_error("Battle occupation or defender retreat was not reflected")
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge army recruitment smoke test passed")
    bridge.free()
    quit(0)
