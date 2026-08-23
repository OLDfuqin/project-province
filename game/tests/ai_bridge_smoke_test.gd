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

    var observed_actions: Array = []
    for month: int in range(8):
        var result: Dictionary = bridge.advance_turn(1)
        if not result.get("accepted", false):
            push_error("AI turn failed in month %d" % month)
            bridge.free()
            quit(1)
            return
        observed_actions.append_array(result.get("ai_actions", []))

    var visible_ids := {"auroria": true, "caelus": true, "solmere": true, "verdantia": true}
    for action: Dictionary in observed_actions:
        var actor_id := String(action.get("country_id", ""))
        var target_id := String(action.get("target_id", ""))
        if (not actor_id.is_empty() and not visible_ids.has(actor_id)) or \
                (not target_id.is_empty() and not visible_ids.has(target_id)):
            push_error("Hidden neutral country emitted an AI action")
            bridge.free()
            quit(1)
            return
    if bridge.get_country_summaries().size() != 4 or observed_actions.is_empty():
        push_error("AI actions were not reflected through the bridge")
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge AI smoke test passed")
    bridge.free()
    quit(0)
