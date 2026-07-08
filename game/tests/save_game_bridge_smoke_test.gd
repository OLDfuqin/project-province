extends SceneTree


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if bridge == null:
        push_error("ProvinceBridge could not be instantiated")
        quit(1)
        return
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1200, 6):
        push_error("Scenario load failed")
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")

    bridge.research_technology("auroria", "roads")
    var army: Dictionary = bridge.recruit_army("auroria", "northreach", 500)
    bridge.build_road("auroria", "northreach", "westmark")
    bridge.declare_war("auroria", "solmere")
    bridge.advance_turn(1)
    bridge.move_army(army["army_id"], "redpass")

    var save_path := ProjectSettings.globalize_path(
        "res://../build/godot_save_roundtrip_test.json"
    )
    var save_result: Dictionary = bridge.save_game(save_path)
    var saved_date: Dictionary = bridge.get_current_date()
    bridge.advance_turn(3)
    var load_result: Dictionary = bridge.load_game(save_path)
    var loaded_date: Dictionary = bridge.get_current_date()
    var redpass: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province["id"] == "redpass":
            redpass = province
    var failed_load: Dictionary = bridge.load_game(save_path + ".missing")
    var date_after_failed_load: Dictionary = bridge.get_current_date()

    if not save_result.get("accepted", false) or \
            not load_result.get("accepted", false) or \
            failed_load.get("accepted", false) or \
            loaded_date != saved_date or date_after_failed_load != loaded_date or \
            bridge.get_army_summaries().size() != 1 or \
            bridge.get_road_summaries().size() != 1 or \
            bridge.get_diplomatic_relations().size() != 1 or \
            redpass.get("owner_id", "") != "auroria" or \
            not redpass.get("occupied", false):
        push_error("Save/load round trip failed through the bridge")
        DirAccess.remove_absolute(save_path)
        bridge.free()
        quit(1)
        return

    DirAccess.remove_absolute(save_path)
    print("ProvinceBridge save game smoke test passed")
    bridge.free()
    quit(0)
