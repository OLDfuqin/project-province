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
    var status: Dictionary = bridge.get_game_status("auroria")
    if status.get("game_over", true) or status.get("countries", []).size() != 4:
        push_error("Initial game status was incorrect")
        bridge.free()
        quit(1)
        return
    if not bridge.get_war_summaries().is_empty():
        push_error("Initial war overview was not empty")
        bridge.free()
        quit(1)
        return
    bridge.declare_war("auroria", "solmere")
    var wars: Array = bridge.get_war_summaries()
    var frontlines: Array = bridge.get_frontline_edges()
    if wars.size() != 1 or wars[0].get("front_edges", 0) <= 0 or frontlines.is_empty():
        push_error("War overview did not summarize a declared war")
        bridge.free()
        quit(1)
        return
    print("ProvinceBridge game status smoke test passed")
    bridge.free()
    quit(0)
