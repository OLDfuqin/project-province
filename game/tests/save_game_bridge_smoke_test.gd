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


func _normalize_json_numbers(value: Variant) -> Variant:
    if value is float and is_equal_approx(value, round(value)):
        return int(value)
    if value is Array:
        var normalized_array: Array = []
        for item: Variant in value:
            normalized_array.append(_normalize_json_numbers(item))
        return normalized_array
    if value is Dictionary:
        var normalized_dictionary: Dictionary = {}
        for key: Variant in value:
            normalized_dictionary[key] = _normalize_json_numbers(value[key])
        return normalized_dictionary
    return value


func _write_json(path: String, document: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(_normalize_json_numbers(document)))
    file.close()


func _ai_rejections_are_stable_and_transactional(
    bridge: Object,
    expected_player_id: String,
    baseline_path: String,
    mirror_path: String
) -> bool:
    var baseline_save: Dictionary = bridge.save_game(baseline_path)
    var baseline_document := _read_json(baseline_path)
    var baseline_ai_enabled: bool = bool(bridge.is_ai_enabled())
    var baseline_player_orders: Array = bridge.get_pending_orders(expected_player_id)
    if not baseline_save.get("accepted", false) or baseline_document.is_empty():
        return false

    # Exercise every rejected identity class repeatedly in both requested AI
    # states. Saving after each class proves player, AI, orders and sequences
    # are unchanged, rather than merely proving that the call returned false.
    for rejected_id: String in ["", "Auroria!", "玩家", "missing-country", "neutral"]:
        for requested_enabled: bool in [false, true]:
            for _attempt: int in range(8):
                var changed: Variant = bridge.set_ai_enabled(requested_enabled, rejected_id)
                if changed != false or \
                        bridge.get_last_error() != "ai configuration could not be changed":
                    return false
        var mirror_save: Dictionary = bridge.save_game(mirror_path)
        if not mirror_save.get("accepted", false) or \
                _read_json(mirror_path) != baseline_document or \
                bridge.is_ai_enabled() != baseline_ai_enabled or \
                bridge.get_pending_orders(expected_player_id) != baseline_player_orders:
            return false
    return true


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
    var invalidated_path := save_path + ".invalidated"
    var transaction_path := save_path + ".transaction"
    var transaction_mirror_path := transaction_path + ".mirror"
    var ai_valid_disabled_path := save_path + ".ai-valid-disabled"
    var ai_valid_enabled_path := save_path + ".ai-valid-enabled"
    var ai_transaction_path := save_path + ".ai-transaction"
    var ai_transaction_mirror_path := ai_transaction_path + ".mirror"
    var ai_disabled_transaction_path := save_path + ".ai-disabled-transaction"
    var ai_disabled_transaction_mirror_path := ai_disabled_transaction_path + ".mirror"
    var overflow_path := save_path + ".overflow"
    var overflow_baseline_path := overflow_path + ".baseline"
    var overflow_mirror_path := overflow_path + ".mirror"
    var save_result: Dictionary = bridge.save_game(save_path)
    var saved_document := _read_json(save_path)

    # Schema-valid projects may become invalid before settlement. Their monthly
    # cancellation dictionaries must retain exact source IDs, costs and reasons.
    var invalidated_document := saved_document.duplicate(true)
    var expected_project_refunds: Dictionary = {}
    for order_document: Dictionary in invalidated_document.get("orders", []):
        var order_type := String(order_document.get("type", ""))
        if order_document.get("country_id", "") != "auroria":
            continue
        if order_type in ["recruitment", "road_construction", "research"]:
            expected_project_refunds[String(order_document.get("id", ""))] = \
                    int(order_document.get("paid_cost", 0))
        if order_type == "recruitment":
            var recruitment_province := String(order_document.get("province_id", ""))
            var occupations: Array = []
            for occupation_document: Dictionary in invalidated_document.get("occupations", []):
                if occupation_document.get("province_id", "") != recruitment_province:
                    occupations.append(occupation_document)
            occupations.append({
                "province_id": recruitment_province,
                "controller_id": "caelus",
            })
            invalidated_document["occupations"] = occupations
        elif order_type == "road_construction":
            invalidated_document["roads"].append({
                "province_a": order_document.get("province_a", ""),
                "province_b": order_document.get("province_b", ""),
                "level": "paved",
            })
        elif order_type == "research":
            order_document["remaining_months"] = 1
            var level_key := "%s_level" % String(order_document.get("track", ""))
            for technology_document: Dictionary in invalidated_document.get("technologies", []):
                if technology_document.get("country_id", "") == \
                        order_document.get("country_id", ""):
                    technology_document[level_key] = int(order_document.get("target_level", 0))
    _write_json(invalidated_path, invalidated_document)
    var invalidated_bridge: Object = ClassDB.instantiate("ProvinceBridge")
    var invalidated_load: Dictionary = invalidated_bridge.load_game(invalidated_path)
    var invalidated_turn: Dictionary = invalidated_bridge.advance_turn()
    var actual_project_refunds: Dictionary = {}
    for action: Dictionary in invalidated_turn.get("turn_actions", []):
        var refund_id := String(action.get("order_id", ""))
        if action.get("type", "") == "order_cancelled" and \
                expected_project_refunds.has(refund_id):
            actual_project_refunds[refund_id] = action
    var project_refunds_complete: bool = invalidated_load.get("accepted", false) and \
            invalidated_turn.get("accepted", false) and \
            actual_project_refunds.size() == expected_project_refunds.size()
    for refund_id: String in actual_project_refunds:
        var refund_action: Dictionary = actual_project_refunds[refund_id]
        project_refunds_complete = project_refunds_complete and \
                refund_action.get("country_id", "") == "auroria" and \
                refund_action.get("army_id", "not-empty") == "" and \
                refund_action.get("refunded_cost", -1) == expected_project_refunds[refund_id] and \
                refund_action.get("refunded_movement_half", -1) == 0 and \
                not String(refund_action.get("reason", "")).is_empty()
    invalidated_bridge.free()
    if not project_refunds_complete:
        push_error("Monthly invalidated projects lost exact refund dictionaries: %s" % actual_project_refunds)
        bridge.free()
        quit(1)
        return

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
    var privacy_configured: Variant = privacy_source.set_ai_enabled(false, "caelus")
    for initial_order: Dictionary in privacy_source.get_pending_orders("caelus"):
        privacy_source.cancel_order(initial_order.get("order_id", ""))
    var player_order: Dictionary = privacy_source.recruit_army(
        "caelus", Helpers.capital_id("caelus"), 100
    )
    var privacy_save: Dictionary = privacy_source.save_game(privacy_path)
    var privacy_document := _read_json(privacy_path)
    var foreign_order_id := ""
    for order_document: Dictionary in privacy_document.get("orders", []):
        if order_document.get("country_id", "") != "caelus":
            foreign_order_id = String(order_document.get("id", ""))
            break
    var privacy_loaded: Object = ClassDB.instantiate("ProvinceBridge")
    var privacy_load: Dictionary = privacy_loaded.load_game(privacy_path)
    var foreign_orders: Array = privacy_loaded.get_pending_orders("auroria")
    var foreign_cancel: Dictionary = privacy_loaded.cancel_order(foreign_order_id)
    if privacy_configured != true or not privacy_source.get_last_error().is_empty() or \
            not player_order.get("accepted", false) or not privacy_save.get("accepted", false) or \
            foreign_order_id.is_empty() or not privacy_load.get("accepted", false) or \
            privacy_load.get("player_country_id", "") != "caelus" or \
            privacy_document.get("player_country_id", "") != "caelus" or \
            privacy_document.get("ai_human_country_id", "not-null") != null or \
            privacy_loaded.is_ai_enabled() or \
            privacy_loaded.get_pending_orders("caelus").size() != 1 or \
            not foreign_orders.is_empty() or foreign_cancel.get("accepted", true):
        push_error("Fresh bridge exposed foreign orders from an AI-disabled schema 7 save")
        privacy_source.free()
        privacy_loaded.free()
        bridge.free()
        quit(1)
        return

    var authority_bridge: Object = ClassDB.instantiate("ProvinceBridge")
    authority_bridge.load_scenario(data_directory, 1200, 6)
    authority_bridge.recruit_army("auroria", Helpers.capital_id("auroria"), 100)
    authority_bridge.advance_turn()
    authority_bridge.set_ai_enabled(false, "caelus")
    authority_bridge.recruit_army("caelus", Helpers.capital_id("caelus"), 100)
    authority_bridge.advance_turn()
    var caelus_army_id := ""
    for army: Dictionary in authority_bridge.get_army_summaries():
        if army.get("owner_id", "") == "caelus":
            caelus_army_id = String(army.get("id", ""))
            break
    var auroria_army_id := ""
    for army: Dictionary in authority_bridge.get_army_summaries():
        if army.get("owner_id", "") == "auroria":
            auroria_army_id = String(army.get("id", ""))
            break
    var foreign_writes := [
        authority_bridge.recruit_army("auroria", Helpers.capital_id("auroria"), 1),
        authority_bridge.research_technology("auroria", "economy"),
        authority_bridge.declare_war("auroria", "verdantia"),
        authority_bridge.rename_army(auroria_army_id, 99),
        authority_bridge.set_army_advance_target(
            auroria_army_id, Helpers.capital_id("caelus")
        ),
    ]
    for foreign_write: Dictionary in foreign_writes:
        if foreign_write.get("accepted", true):
            push_error("Caelus player identity did not reject a foreign write API")
            authority_bridge.free()
            privacy_source.free()
            privacy_loaded.free()
            bridge.free()
            quit(1)
            return
    if caelus_army_id.is_empty() or auroria_army_id.is_empty():
        push_error("Player authority fixture could not find both army owners")
        authority_bridge.free()
        privacy_source.free()
        privacy_loaded.free()
        bridge.free()
        quit(1)
        return
    authority_bridge.free()

    # A valid visible Caelus identity succeeds in both disabled and enabled
    # modes. Rejected identities must preserve either mode exactly.
    var valid_ai: Object = ClassDB.instantiate("ProvinceBridge")
    var valid_ai_loaded: bool = valid_ai.load_scenario(data_directory, 1200, 6)
    var valid_disabled: Variant = valid_ai.set_ai_enabled(false, "caelus")
    var valid_disabled_save: Dictionary = valid_ai.save_game(ai_valid_disabled_path)
    var valid_disabled_document := _read_json(ai_valid_disabled_path)
    var valid_enabled: Variant = valid_ai.set_ai_enabled(true, "caelus")
    var valid_enabled_save: Dictionary = valid_ai.save_game(ai_valid_enabled_path)
    var valid_enabled_document := _read_json(ai_valid_enabled_path)
    var no_scenario: Object = ClassDB.instantiate("ProvinceBridge")
    var no_scenario_stable := true
    for requested_enabled: bool in [false, true]:
        for _attempt: int in range(8):
            no_scenario_stable = no_scenario_stable and \
                    no_scenario.set_ai_enabled(requested_enabled, "caelus") == false and \
                    no_scenario.get_last_error() == "ai configuration could not be changed" and \
                    not no_scenario.has_scenario() and not no_scenario.is_ai_enabled()
    if not valid_ai_loaded or valid_disabled != true or \
            not valid_disabled_save.get("accepted", false) or \
            valid_disabled_document.get("player_country_id", "") != "caelus" or \
            valid_disabled_document.get("ai_human_country_id", "unexpected") != null or \
            valid_enabled != true or not valid_ai.is_ai_enabled() or \
            not valid_enabled_save.get("accepted", false) or \
            valid_enabled_document.get("player_country_id", "") != "caelus" or \
            valid_enabled_document.get("ai_human_country_id", "") != "caelus" or \
            not _ai_rejections_are_stable_and_transactional(
                valid_ai, "caelus", ai_transaction_path, ai_transaction_mirror_path
            ) or not _ai_rejections_are_stable_and_transactional(
                privacy_loaded, "caelus",
                ai_disabled_transaction_path, ai_disabled_transaction_mirror_path
            ) or not no_scenario_stable:
        push_error("AI configuration boundary was unstable or non-transactional")
        no_scenario.free()
        valid_ai.free()
        privacy_source.free()
        privacy_loaded.free()
        bridge.free()
        quit(1)
        return
    no_scenario.free()
    valid_ai.free()


    # Malformed schema 7 loads are fully transactional: state, order and event
    # sequences, AI configuration and player authority all remain unchanged.
    var transaction_save: Dictionary = privacy_loaded.save_game(transaction_path)
    var transaction_before := _read_json(transaction_path)
    var malformed_transaction := transaction_before.duplicate(true)
    malformed_transaction["next_event_sequence"] = 0
    _write_json(transaction_path, malformed_transaction)
    var malformed_stable := true
    for _attempt: int in range(8):
        var rejected_transaction: Dictionary = privacy_loaded.load_game(transaction_path)
        malformed_stable = malformed_stable and \
                not rejected_transaction.get("accepted", true) and \
                rejected_transaction.get("error", "") == "save game could not be loaded"
    var transaction_mirror: Dictionary = privacy_loaded.save_game(transaction_mirror_path)
    var transaction_after := _read_json(transaction_mirror_path)
    if not transaction_save.get("accepted", false) or not malformed_stable or \
            not transaction_mirror.get("accepted", false) or \
            transaction_after != transaction_before or privacy_loaded.is_ai_enabled() or \
            privacy_loaded.get_pending_orders("caelus").size() != 1 or \
            not privacy_loaded.get_pending_orders("auroria").is_empty():
        push_error("Malformed schema 7 load mutated bridge state or player/AI authority")
        privacy_source.free()
        privacy_loaded.free()
        bridge.free()
        quit(1)
        return
    privacy_source.free()
    privacy_loaded.free()

    var overflow_bridge: Object = ClassDB.instantiate("ProvinceBridge")
    overflow_bridge.load_scenario(data_directory, 1200, 6)
    overflow_bridge.set_ai_enabled(false, "auroria")
    overflow_bridge.save_game(overflow_path)
    var overflow_document := _read_json(overflow_path)
    for country: Dictionary in overflow_document.get("countries", []):
        if country.get("id", "") == "auroria":
            country["treasury"] = 9223372036854775807
    _write_json(overflow_path, overflow_document)
    var overflow_load: Dictionary = overflow_bridge.load_game(overflow_path)
    var overflow_baseline_save: Dictionary = overflow_bridge.save_game(overflow_baseline_path)
    var overflow_date: Dictionary = overflow_bridge.get_current_date()
    var overflow_advance: Dictionary = overflow_bridge.advance_turn()
    var overflow_save: Dictionary = overflow_bridge.save_game(overflow_mirror_path)
    if not overflow_load.get("accepted", false) or \
            not overflow_baseline_save.get("accepted", false) or \
            overflow_advance.get("accepted", true) or \
            overflow_advance.get("error", "") != "turn could not be advanced" or \
            overflow_bridge.get_current_date() != overflow_date or \
            not overflow_save.get("accepted", false) or \
            FileAccess.get_file_as_string(overflow_mirror_path) != \
                    FileAccess.get_file_as_string(overflow_baseline_path):
        push_error("Extreme fiscal overflow crossed or mutated the bridge advance boundary: load=%s baseline=%s advance=%s date=%s/%s save=%s mirror_equal=%s" % [
            overflow_load, overflow_baseline_save, overflow_advance, overflow_date,
            overflow_bridge.get_current_date(), overflow_save,
            FileAccess.get_file_as_string(overflow_mirror_path) == \
                    FileAccess.get_file_as_string(overflow_baseline_path),
        ])
        overflow_bridge.free()
        bridge.free()
        quit(1)
        return
    overflow_bridge.free()

    for path: String in [
        save_path, mirror_path, progress_path, legacy_path, privacy_path,
        invalidated_path, transaction_path, transaction_mirror_path,
        ai_valid_disabled_path, ai_valid_enabled_path,
        ai_transaction_path, ai_transaction_mirror_path,
        ai_disabled_transaction_path, ai_disabled_transaction_mirror_path,
        overflow_path, overflow_baseline_path, overflow_mirror_path,
    ]:
        DirAccess.remove_absolute(path)
    print("ProvinceBridge save game smoke test passed")
    bridge.free()
    quit(0)
