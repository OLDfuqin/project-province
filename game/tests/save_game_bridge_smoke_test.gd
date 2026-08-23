extends SceneTree

const Helpers := preload("res://tests/generated_scenario_helpers.gd")


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

    for _level: int in range(3):
        bridge.research_technology("auroria", "roads")
    var capital := Helpers.capital_id("auroria")
    var army: Dictionary = bridge.recruit_army("auroria", capital, 500)
    var pair := Helpers.first_adjacent_pair(bridge, "auroria")
    bridge.build_road("auroria", pair[0], pair[1])
    bridge.declare_war("auroria", "solmere")
    bridge.set_army_advance_target(army["army_id"], "cell_1_1")
    bridge.set_army_advance_enabled(army["army_id"], false)
    bridge.set_army_advance_strategy(army["army_id"], "stop_before_enemy")

    var capital_before_save := Helpers.province_by_id(bridge, capital)
    var save_path := ProjectSettings.globalize_path(
        "res://../build/godot_save_roundtrip_test.json"
    )
    var save_result: Dictionary = bridge.save_game(save_path)
    var saved_date: Dictionary = bridge.get_current_date()
    var saved_file := FileAccess.open(save_path, FileAccess.READ)
    var saved_document: Dictionary = JSON.parse_string(saved_file.get_as_text())
    saved_file.close()
    var retained_derived_economy := false
    var retained_base_economy := true
    for province_document: Dictionary in saved_document.get("provinces", []):
        retained_derived_economy = retained_derived_economy or province_document.has("economy")
        retained_base_economy = retained_base_economy and province_document.has("base_economy")

    var legacy_path := save_path + ".v5"
    var legacy_document := saved_document.duplicate(true)
    legacy_document["schema_version"] = 5
    var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
    legacy_file.store_string(JSON.stringify(legacy_document))
    legacy_file.close()
    var legacy_load: Dictionary = bridge.load_game(legacy_path)

    bridge.advance_turn(3)
    var load_result: Dictionary = bridge.load_game(save_path)
    var loaded_date: Dictionary = bridge.get_current_date()
    var capital_after_load := Helpers.province_by_id(bridge, capital)
    var failed_load: Dictionary = bridge.load_game(save_path + ".missing")
    var date_after_failed_load: Dictionary = bridge.get_current_date()
    var loaded_army: Dictionary = {}
    var player_army_count := 0
    for summary: Dictionary in bridge.get_army_summaries():
        if summary.get("owner_id", "") == "auroria":
            player_army_count += 1
        if summary.get("id", "") == army.get("army_id", ""):
            loaded_army = summary

    if not save_result.get("accepted", false) or \
            saved_document.get("schema_version", 0) != 6 or \
            saved_document.get("map_layout_id", "") != "generated_grid_v1" or \
            retained_derived_economy or not retained_base_economy or \
            legacy_load.get("accepted", false) or \
            not load_result.get("accepted", false) or \
            failed_load.get("accepted", false) or \
            loaded_date != saved_date or date_after_failed_load != loaded_date or \
            player_army_count != 1 or \
            loaded_army.get("advance_target_id", "") != "cell_1_1" or \
            loaded_army.get("advance_enabled", true) or \
            loaded_army.get("advance_strategy", "") != "stop_before_enemy" or \
            loaded_army.get("formation_number", 0) != 1 or \
            loaded_army.get("display_name", "") != "奥·第1军" or \
            bridge.get_road_summaries().size() != 1 or \
            bridge.get_diplomatic_relations().size() != 1 or \
            capital_after_load.get("population", -1) != capital_before_save.get("population", -1) or \
            capital_after_load.get("recruitable_population", -1) != capital_before_save.get("recruitable_population", -1) or \
            capital_after_load.get("economy", -1) != capital_before_save.get("economy", -1) or \
            capital_after_load.get("fiscal_income", -1) != capital_before_save.get("fiscal_income", -1):
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
