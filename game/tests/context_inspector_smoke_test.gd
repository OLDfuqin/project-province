extends SceneTree


func _fail(inspector: Node, summary: Node, message: String) -> void:
    push_error(message)
    if is_instance_valid(summary):
        summary.free()
    if is_instance_valid(inspector):
        inspector.free()
    quit(1)


func _initialize() -> void:
    var inspector_scene := load("res://scenes/ui/context_inspector.tscn") as PackedScene
    var summary_scene := load("res://scenes/ui/province_info_window.tscn") as PackedScene
    if inspector_scene == null or summary_scene == null:
        push_error("Context inspector or province summary scene could not be loaded")
        quit(1)
        return

    var inspector := inspector_scene.instantiate()
    var summary := summary_scene.instantiate()
    root.add_child(inspector)
    await process_frame
    inspector.show_empty("请先选择目标")
    if inspector.current_mode() != "empty" or \
            not inspector.get_node("Body/ScrollContainer/Content/Empty").visible or \
            inspector.get_node("Body/ScrollContainer/Content").get_child_count() != 1:
        _fail(inspector, summary, "Context inspector did not show an exclusive empty state")
        return

    var province := {
        "id": "rivergate",
        "name": "河间",
        "terrain": "hills",
        "legal_owner_id": "auroria",
        "owner_id": "auroria",
        "population": 340000,
        "recruitable_population": 18000,
        "economy": 25000,
        "fiscal_income": 3200,
    }
    var observed := {"managed_province_id": ""}
    summary.manage_requested.connect(
        func(province_id: String) -> void:
            observed["managed_province_id"] = province_id
    )
    summary.display_province(province, [], [], {"rivergate": province}, [
        {"id": "auroria", "name": "奥罗里亚"},
    ])
    inspector.show_panel("province_summary", "地区信息", summary)
    if inspector.current_mode() != "province_summary" or \
            summary.get_node("Body/Metrics/Population/Content/Value").text != "340,000" or \
            not summary.get_node("Body/ManageProvince").visible or \
            inspector.get_node("Body/ScrollContainer/Content/Empty").visible or \
            inspector.get_node("Body/ScrollContainer/Content").get_child_count() != 2 or \
            inspector.get_node("Body/ScrollContainer/Content").get_child(1) != summary:
        _fail(inspector, summary, "Context inspector did not show the compact province summary")
        return

    var content_scroll := inspector.get_node_or_null("Body/ScrollContainer") as ScrollContainer
    if content_scroll == null or inspector.get_node_or_null("Body/Content") != null:
        _fail(inspector, summary, "Context inspector lost its single top-level content scroll")
        return
    summary.get_node("Body/ManageProvince").pressed.emit()
    if observed["managed_province_id"] != "rivergate":
        _fail(inspector, summary, "Province summary management request lost the active province")
        return

    var management_scene := load("res://scenes/ui/province_management_window.tscn") as PackedScene
    var management := management_scene.instantiate() as Control if management_scene != null else null
    if management == null:
        _fail(inspector, summary, "Province management scene could not be loaded for scroll testing")
        return
    inspector.size = Vector2(320, 620)
    inspector.show_panel("province_management", "地区管理", management)
    await process_frame
    var vertical_bar := content_scroll.get_v_scroll_bar()
    if vertical_bar.max_value <= vertical_bar.page:
        _fail(inspector, summary, "A 720px province-management tab cannot scroll in the 720px layout")
        return
    content_scroll.scroll_vertical = int(vertical_bar.max_value)
    await process_frame
    if content_scroll.scroll_vertical <= 0:
        _fail(inspector, summary, "Context inspector could not reach lower province-management content")
        return

    inspector.show_empty()
    if inspector.current_mode() != "empty" or \
            not inspector.get_node("Body/ScrollContainer/Content/Empty").visible or \
            inspector.get_node("Body/ScrollContainer/Content").get_child_count() != 1 or \
            summary.get_parent() != null:
        _fail(inspector, summary, "Context inspector left a business panel visible after returning to empty")
        return

    print("Context inspector smoke test passed")
    management.free()
    summary.free()
    inspector.free()
    quit(0)
