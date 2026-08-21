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
    bridge.set_army_advance_target(army["army_id"], "goldcoast")
    bridge.set_army_advance_enabled(army["army_id"], false)
    bridge.set_army_advance_strategy(army["army_id"], "stop_before_enemy")

    var northreach_before_save: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province["id"] == "northreach":
            northreach_before_save = province

    var save_path := ProjectSettings.globalize_path(
        "res://../build/godot_save_roundtrip_test.json"
    )
    var save_result: Dictionary = bridge.save_game(save_path)
    var saved_date: Dictionary = bridge.get_current_date()
    var saved_file := FileAccess.open(save_path, FileAccess.READ)
    var saved_document: Dictionary = JSON.parse_string(saved_file.get_as_text())
    saved_file.close()
    var retained_fixed_economy := false
    for province_document: Dictionary in saved_document.get("provinces", []):
        retained_fixed_economy = retained_fixed_economy or \
            province_document.has("economy")
    var legacy_path := save_path + ".v2"
    var legacy_document := saved_document.duplicate(true)
    legacy_document["schema_version"] = 2
    var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
    legacy_file.store_string(JSON.stringify(legacy_document))
    legacy_file.close()
    var legacy_load: Dictionary = bridge.load_game(legacy_path)
    bridge.advance_turn(3)
    var load_result: Dictionary = bridge.load_game(save_path)
    var loaded_date: Dictionary = bridge.get_current_date()
    var redpass: Dictionary = {}
    var northreach_after_load: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province["id"] == "redpass":
            redpass = province
        if province["id"] == "northreach":
            northreach_after_load = province
    var failed_load: Dictionary = bridge.load_game(save_path + ".missing")
    var date_after_failed_load: Dictionary = bridge.get_current_date()
    var loaded_army: Dictionary = {}
    for summary: Dictionary in bridge.get_army_summaries():
        if summary["id"] == army["army_id"]:
            loaded_army = summary

    if not save_result.get("accepted", false) or \
            saved_document.get("schema_version", 0) != 5 or \
            retained_fixed_economy or \
            legacy_load.get("accepted", false) or \
            not load_result.get("accepted", false) or \
            failed_load.get("accepted", false) or \
            loaded_date != saved_date or date_after_failed_load != loaded_date or \
            bridge.get_army_summaries().size() != 1 or \
            loaded_army.get("advance_target_id", "") != "goldcoast" or \
            loaded_army.get("advance_enabled", true) or \
            loaded_army.get("advance_strategy", "") != "stop_before_enemy" or \
            loaded_army.get("formation_number", 0) != 1 or \
            loaded_army.get("display_name", "") != "奥·第1军" or \
            bridge.get_road_summaries().size() != 1 or \
            bridge.get_diplomatic_relations().size() != 1 or \
            redpass.get("owner_id", "") != "auroria" or \
            not redpass.get("occupied", false) or \
            northreach_after_load.get("population", -1) != \
            northreach_before_save.get("population", -1) or \
            northreach_after_load.get("recruitable_population", -1) != \
            northreach_before_save.get("recruitable_population", -1) or \
            northreach_after_load.get("economy", -1) != \
            northreach_before_save.get("economy", -1) or \
            northreach_after_load.get("fiscal_income", -1) != \
            northreach_before_save.get("fiscal_income", -1):
        push_error("Save/load round trip failed through the bridge")
        DirAccess.remove_absolute(save_path)
        DirAccess.remove_absolute(legacy_path)
        bridge.free()
        quit(1)
        return

    DirAccess.remove_absolute(save_path)
    DirAccess.remove_absolute(legacy_path)
    print("ProvinceBridge save game smoke test passed")
    bridge.free()
    quit(0)
