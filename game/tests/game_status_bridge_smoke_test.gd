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
    print("ProvinceBridge game status smoke test passed")
    bridge.free()
    quit(0)
