extends SceneTree

const Helpers := preload("res://tests/generated_scenario_helpers.gd")


func _eligible_pair(bridge: Object, country_id: String) -> Array[String]:
    for province: Dictionary in Helpers.owned_provinces(bridge, country_id):
        var first_id := String(province.get("id", ""))
        var neighbors: Array = province.get("neighbors", []).duplicate()
        neighbors.sort()
        for neighbor: String in neighbors:
            var second := Helpers.province_by_id(bridge, neighbor)
            if first_id < neighbor and second.get("owner_id", "") == country_id and \
                    bridge.get_road_order_quote(
                        country_id, first_id, neighbor
                    ).get("accepted", false):
                return [first_id, neighbor]
    return []


func _read_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var document: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return document if document is Dictionary else {}


func _write_json(path: String, document: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(document))
    file.close()


func _technology_level(bridge: Object, country_id: String, key: String) -> int:
    for technology: Dictionary in bridge.get_technology_summaries():
        if technology.get("country_id", "") == country_id:
            return int(technology.get(key, -1))
    return -1


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    var data_directory := ProjectSettings.globalize_path("res://data")
    if bridge == null or not bridge.load_scenario(data_directory, 1200, 6):
        push_error("Scenario load failed")
        quit(1)
        return

    var pair: Array[String] = []
    for _level: int in range(3):
        var road_research: Dictionary = bridge.research_technology("auroria", "roads")
        if not road_research.get("accepted", false):
            break
        for _month: int in range(int(road_research.get("remaining_months", 0))):
            bridge.advance_turn()
        pair = _eligible_pair(bridge, "auroria")
        if pair.size() == 2:
            break
    if pair.size() != 2:
        push_error("Generated scenario has no road pair eligible at the researched level")
        bridge.free()
        quit(1)
        return
    var capital := Helpers.capital_id("auroria")
    var recruit: Dictionary = bridge.recruit_army("auroria", capital, 100)
    var road: Dictionary = bridge.build_road("auroria", pair[0], pair[1])
    var research: Dictionary = bridge.research_technology("auroria", "economy")
    var pending_before: Array = bridge.get_pending_orders("auroria")
    if not recruit.get("accepted", false) or \
            not road.get("accepted", false) or not research.get("accepted", false) or \
            pending_before.size() != 3 or bridge.get_pending_orders("solmere").size() != 0:
        push_error("Bridge could not prepare schema 7 pending orders: pair=%s recruit=%s road=%s research=%s pending=%s" % [
            pair, recruit, road, research, pending_before,
        ])
        bridge.free()
        quit(1)
        return

    var save_path := ProjectSettings.globalize_path("res://../build/godot_schema7_roundtrip.json")
    var mirror_path := save_path + ".mirror"
    var progress_path := save_path + ".progress"
    var legacy_path := save_path + ".schema6"
    var privacy_path := save_path + ".privacy"
    var save_result: Dictionary = bridge.save_game(save_path)
    var saved_document := _read_json(save_path)
    var legacy_document := saved_document.duplicate(true)
    legacy_document["schema_version"] = 6
    _write_json(legacy_path, legacy_document)
    var legacy_load: Dictionary = {}
    var legacy_rejection_stable := true
    for _attempt: int in range(8):
        legacy_load = bridge.load_game(legacy_path)
        legacy_rejection_stable = legacy_rejection_stable and \
                not legacy_load.get("accepted", true) and \
                legacy_load.get("error", "") == "save game could not be loaded"
    var load_result: Dictionary = bridge.load_game(save_path)
    var pending_loaded: Array = bridge.get_pending_orders("auroria")
    bridge.save_game(mirror_path)
    var mirrored_document := _read_json(mirror_path)
    var enemy_cancel: Dictionary = {"accepted": false}
    var enemy_order_found := false
    for order_document: Dictionary in saved_document.get("orders", []):
        if order_document.get("country_id", "") != "auroria":
            enemy_order_found = true
            enemy_cancel = bridge.cancel_order(order_document.get("id", ""))
            break
    if not save_result.get("accepted", false) or saved_document.get("schema_version", 0) != 7 or \
            not saved_document.has("next_order_sequence") or \
            saved_document.get("orders", []).size() < 3 or not legacy_rejection_stable or \
            not load_result.get("accepted", false) or pending_loaded != pending_before or \
            bridge.get_pending_orders("solmere").size() != 0 or \
            not enemy_order_found or enemy_cancel.get("accepted", true) or \
            mirrored_document.get("orders", []).size() != saved_document.get("orders", []).size():
        push_error("Schema 7 bridge round trip lost orders or duplicated restored AI planning")
        bridge.free()
        quit(1)
        return

    var first_month: Dictionary = bridge.advance_turn()
    var progressed: Array = bridge.get_pending_orders("auroria")
    if not first_month.get("accepted", false) or progressed.size() != 1 or \
            progressed[0].get("type", "") != "research" or \
            progressed[0].get("remaining_months", 0) != 1:
        push_error("Schema 7 research progress did not survive monthly project settlement")
        bridge.free()
        quit(1)
        return
    bridge.save_game(progress_path)
    bridge.advance_turn()
    var progress_load: Dictionary = bridge.load_game(progress_path)
    var restored_progress: Array = bridge.get_pending_orders("auroria")
    var restored_date: Dictionary = bridge.get_current_date()
    var failed_load: Dictionary = {}
    var missing_rejection_stable := true
    for _attempt: int in range(8):
        failed_load = bridge.load_game(progress_path + ".missing")
        missing_rejection_stable = missing_rejection_stable and \
                not failed_load.get("accepted", true) and \
                failed_load.get("error", "") == "save game could not be loaded"
    if not progress_load.get("accepted", false) or restored_progress.size() != 1 or \
            restored_progress[0].get("remaining_months", 0) != 1 or \
            not missing_rejection_stable or bridge.get_current_date() != restored_date:
        push_error("Bridge did not restore in-progress research transactionally")
        bridge.free()
        quit(1)
        return
    var completion: Dictionary = bridge.advance_turn()
    if not completion.get("accepted", false) or \
            _technology_level(bridge, "auroria", "economy_level") != 1 or \
            bridge.get_pending_orders("auroria").size() != 0:
        push_error("Restored schema 7 research did not complete")
        bridge.free()
        quit(1)
        return

    # Player ownership remains a bridge concern even when AI is disabled and
    # its optional save configuration marker is absent. A fresh bridge loading
    # such a save must still hide and protect every foreign pending order.
    var privacy_source: Object = ClassDB.instantiate("ProvinceBridge")
    privacy_source.load_scenario(data_directory, 1200, 6)
    privacy_source.set_ai_enabled(false, "auroria")
    var player_order: Dictionary = privacy_source.recruit_army(
        "auroria", Helpers.capital_id("auroria"), 100
    )
    var privacy_save: Dictionary = privacy_source.save_game(privacy_path)
    var privacy_document := _read_json(privacy_path)
    var foreign_order_id := ""
    for order_document: Dictionary in privacy_document.get("orders", []):
        if order_document.get("country_id", "") != "auroria":
            foreign_order_id = String(order_document.get("id", ""))
            break
    var privacy_loaded: Object = ClassDB.instantiate("ProvinceBridge")
    var privacy_load: Dictionary = privacy_loaded.load_game(privacy_path)
    var foreign_orders: Array = privacy_loaded.get_pending_orders("solmere")
    var foreign_cancel: Dictionary = privacy_loaded.cancel_order(foreign_order_id)
    if not player_order.get("accepted", false) or not privacy_save.get("accepted", false) or \
            foreign_order_id.is_empty() or not privacy_load.get("accepted", false) or \
            privacy_loaded.get_pending_orders("auroria").size() != 1 or \
            not foreign_orders.is_empty() or foreign_cancel.get("accepted", true):
        push_error("Fresh bridge exposed foreign orders from an AI-disabled schema 7 save")
        privacy_source.free()
        privacy_loaded.free()
        bridge.free()
        quit(1)
        return
    privacy_source.free()
    privacy_loaded.free()

    for path: String in [save_path, mirror_path, progress_path, legacy_path, privacy_path]:
        DirAccess.remove_absolute(path)
    print("ProvinceBridge save game smoke test passed")
    bridge.free()
    quit(0)
