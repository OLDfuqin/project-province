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
    if not bridge.is_ai_enabled():
        push_error("AI was not enabled for the playable scenario")
        bridge.free()
        quit(1)
        return

    var last_result: Dictionary = {}
    for month: int in range(4):
        last_result = bridge.advance_turn(1)
        if not last_result.get("accepted", false):
            push_error("AI turn failed in month %d" % month)
            bridge.free()
            quit(1)
            return

    var player_armies := 0
    var occupied_provinces := 0
    for army: Dictionary in bridge.get_army_summaries():
        if army["owner_id"] == "auroria":
            player_armies += 1
    for province: Dictionary in bridge.get_province_summaries():
        if province.get("occupied", false):
            occupied_provinces += 1
    if bridge.get_army_summaries().size() != 9 or player_armies != 0 or \
            bridge.get_diplomatic_relations().is_empty() or \
            occupied_provinces == 0 or \
            last_result.get("turn_actions", []).is_empty() or \
            last_result.get("ai_actions", []).is_empty():
        push_error("AI actions were not reflected through the bridge")
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge AI smoke test passed")
    bridge.free()
    quit(0)
