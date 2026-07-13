extends SceneTree


func _initialize() -> void:
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Main scene could not be loaded")
        quit(1)
        return

    var main_scene := packed_scene.instantiate() as Control
    root.add_child(main_scene)
    await process_frame

    var turn_bar := main_scene.get_node_or_null("TurnBar") as Control
    if turn_bar == null or turn_bar.get_parent() != main_scene:
        push_error("Turn controls must be a standalone top bar, not a map child")
        main_scene.free()
        quit(1)
        return

    var map_panel := main_scene.get_node_or_null("MapPanel") as PanelContainer
    if map_panel == null or map_panel.get_child_count() != 1 or \
            map_panel.get_child(0).name != "ProvinceMap":
        push_error("Map panel must contain only the interactive province map")
        main_scene.free()
        quit(1)
        return

    var right_panel := main_scene.get_node_or_null("RightPanel") as ScrollContainer
    if right_panel == null:
        push_error("Right-side controls must be contained in a scrollable panel")
        main_scene.free()
        quit(1)
        return

    var map_rect := map_panel.get_global_rect()
    var turn_rect := turn_bar.get_global_rect()
    var right_rect := right_panel.get_global_rect()
    if turn_rect.intersects(map_rect) or right_rect.intersects(map_rect):
        push_error("Top=%s Right=%s Map=%s" % [turn_rect, right_rect, map_rect])
        main_scene.free()
        quit(1)
        return

    print("Main layout smoke test passed")
    main_scene.free()
    quit(0)
