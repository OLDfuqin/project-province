extends SceneTree


func _army(bridge: Object, army_id: String) -> Dictionary:
    for summary: Dictionary in bridge.get_army_summaries():
        if String(summary.get("id", "")) == army_id:
            return summary
    return {}


func _fail(main_scene: Node, message: String) -> void:
    push_error(message)
    main_scene.free()
    quit(1)


func _initialize() -> void:
    var main_scene := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
    root.add_child(main_scene)
    await process_frame
    var bridge := main_scene.get_node("SimulationBridge")
    var province_map := main_scene.get_node("Shell/Layout/MainRow/MapPanel/ProvinceMap")
    var management := main_scene.province_management_window as Control
    var advance_turn := main_scene.get_node(
        "Shell/Layout/GlobalStatusBar/Margin/Row/AdvanceTurn"
    ) as Button

    province_map.province_double_clicked.emit("capital_auroria")
    management.get_node("Tabs/Military/Recruitment/Open").pressed.emit()
    management.get_node("Tabs/Military/Recruitment/Amount").value = 1000
    management.get_node("Tabs/Military/Recruitment/Buttons/Confirm").pressed.emit()
    await process_frame
    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    var selector := management.get_node("Tabs/Military/ArmySelector") as OptionButton
    if selector.item_count != 1:
        _fail(main_scene, "Recruitment fixture did not produce an army after settlement")
        return
    var army_id := String(selector.get_item_metadata(0))
    for _month: int in range(2):
        advance_turn.pressed.emit()
        await process_frame
        await process_frame
    province_map.province_double_clicked.emit("capital_auroria")

    var select_advance := management.get_node(
        "Tabs/Military/AdvanceActions/SelectAdvanceTarget"
    ) as Button
    var advance_now := management.get_node("Tabs/Military/AdvanceActions/AdvanceNow") as Button
    var advance_plans := management.get_node("Tabs/Military/AdvancePlans") as RichTextLabel
    select_advance.pressed.emit()
    if main_scene.map_input_mode_name() != "auto_advance_destination":
        _fail(main_scene, "Management inspector did not enter advance target selection")
        return
    province_map.province_selected.emit("cell_4_4")
    await process_frame
    if not management.get_node("Tabs/Military/AdvanceTarget").text.contains(
            main_scene.province_by_id["cell_4_4"]["name"]
        ):
        _fail(main_scene, "Advance target was not retained in the inspector")
        return

    advance_plans.meta_clicked.emit("pause:%s" % army_id)
    await process_frame
    if _army(bridge, army_id).get("advance_enabled", true):
        _fail(main_scene, "Advance plan did not pause")
        return
    advance_plans.meta_clicked.emit("resume:%s" % army_id)
    advance_plans.meta_clicked.emit("strategy:%s:one_step" % army_id)
    await process_frame
    if not _army(bridge, army_id).get("advance_enabled", false) or \
            _army(bridge, army_id).get("advance_strategy", "") != "one_step":
        _fail(main_scene, "Advance resume or strategy intent was not forwarded")
        return

    advance_plans.meta_clicked.emit("clear:%s" % army_id)
    await process_frame
    if not String(_army(bridge, army_id).get("advance_target_id", "")).is_empty():
        _fail(main_scene, "Advance plan did not clear")
        return
    select_advance.pressed.emit()
    province_map.province_selected.emit("cell_4_4")
    await process_frame
    var origin_id := String(_army(bridge, army_id).get("province_id", ""))
    advance_now.pressed.emit()
    await process_frame
    if String(_army(bridge, army_id).get("province_id", "")) != origin_id or \
            bridge.get_pending_orders("auroria").size() != 1:
        _fail(main_scene, "Automatic advance was not queued")
        return
    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    if String(_army(bridge, army_id).get("province_id", "")) == origin_id:
        _fail(main_scene, "Queued automatic advance did not execute next month")
        return

    print("Province management advance smoke test passed")
    main_scene.free()
    quit(0)
