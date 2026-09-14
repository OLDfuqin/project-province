extends SceneTree


func _initialize() -> void:
    var packed_scene := load("res://scenes/ui/province_info_window.tscn") as PackedScene
    if packed_scene == null:
        push_error("Province summary scene could not be loaded")
        quit(1)
        return

    var info_window := packed_scene.instantiate() as Control
    root.add_child(info_window)
    await process_frame

    var province := {
        "id": "capital_auroria",
        "name": "奥罗里亚首都",
        "terrain": "capital",
        "legal_owner_id": "auroria",
        "owner_id": "auroria",
        "population": 340000,
        "recruitable_population": 12000,
        "economy": 45000,
        "fiscal_income": 5100,
    }
    info_window.display_province(province, [
        {"province_id": "capital_auroria", "manpower": 12000},
        {"province_id": "capital_auroria", "manpower": 8000},
        {"province_id": "rivergate", "manpower": 9000},
    ], [
        {"province_a": "capital_auroria", "province_b": "rivergate", "level": "paved"},
    ], {
        "capital_auroria": province,
        "rivergate": {"name": "河间"},
    }, [
        {"id": "auroria", "name": "奥罗里亚"},
    ])

    var required_paths := [
        "Body/Metrics/Population/Content/Value",
        "Body/Metrics/Economy/Content/Value",
        "Body/Metrics/FiscalIncome/Content/Value",
        "Body/Metrics/Garrison/Content/Value",
        "Body/Ownership",
        "Body/Terrain",
        "Body/Roads",
        "Body/Recruitable",
        "Body/ManageProvince",
    ]
    for path: String in required_paths:
        if info_window.get_node_or_null(path) == null:
            push_error("Province summary is missing the compact card control: %s" % path)
            info_window.free()
            quit(1)
            return

    var population := info_window.get_node("Body/Metrics/Population/Content/Value") as Label
    var economy := info_window.get_node("Body/Metrics/Economy/Content/Value") as Label
    var fiscal_income := info_window.get_node("Body/Metrics/FiscalIncome/Content/Value") as Label
    var military := info_window.get_node("Body/Metrics/Garrison/Content/Value") as Label
    var ownership := info_window.get_node("Body/Ownership") as Label
    var terrain := info_window.get_node("Body/Terrain") as Label
    var roads := info_window.get_node("Body/Roads") as Label
    var recruits := info_window.get_node("Body/Recruitable") as Label
    if not info_window.visible or population.text != "340,000" or \
            economy.text != "45,000" or fiscal_income.text != "5,100" or \
            military.text != "2 支" or not ownership.text.contains("奥罗里亚") or \
            not terrain.text.contains("首都") or not roads.text.contains("河间") or \
            not recruits.text.contains("12,000") or \
            not info_window.get_node("Body/ManageProvince").visible:
        push_error("Province summary did not show the compact authoritative snapshot")
        info_window.free()
        quit(1)
        return

    var rendered_text := _node_text(info_window)
    if rendered_text.contains("capital_auroria") or rendered_text.contains("owner_id"):
        push_error("Province summary exposed internal identifiers")
        info_window.free()
        quit(1)
        return

    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if not bridge.load_scenario(ProjectSettings.globalize_path("res://data"), 1000, 1):
        push_error("Could not load the real hidden-neutral fixture")
        bridge.free()
        info_window.free()
        quit(1)
        return
    var countries: Array = bridge.get_country_summaries()
    var neutral: Dictionary = {}
    for summary: Dictionary in bridge.get_province_summaries():
        if summary.get("owner_id", "") == "neutral":
            neutral = summary
            break
    info_window.display_province(neutral, bridge.get_army_summaries(), [], {}, countries)
    if neutral.is_empty() or ownership.text != "法理归属：无主地区 | 实际控制：无主地区" or \
            _node_text(info_window).contains("neutral"):
        push_error("Real hidden-neutral ownership was not rendered as an unowned region")
        bridge.free()
        info_window.free()
        quit(1)
        return
    bridge.free()

    info_window.display_province({
        "id": "private_province_id", "owner_id": "private_owner_id",
        "legal_owner_id": "private_legal_id",
    }, [], [{"province_a": "private_province_id", "province_b": "private_road_id"}], {}, [
        {"id": "private_owner_id"}, {"id": "private_legal_id", "name": ""},
    ])
    if _node_text(info_window).contains("private_") or \
            not ownership.text.contains("未知国家") or not roads.text.contains("未知地区") or \
            info_window.get_node("ProvinceName").text != "未知地区":
        push_error("Incomplete province or country lookup leaked an internal identifier")
        info_window.free()
        quit(1)
        return
    info_window.clear()
    if info_window.visible:
        push_error("Cleared province summary remained visible")
        info_window.free()
        quit(1)
        return

    print("Province information window smoke test passed")
    info_window.free()
    quit(0)


func _node_text(node: Node) -> String:
    var text := ""
    if node is Label or node is Button:
        text += node.text
    for child: Node in node.get_children():
        text += _node_text(child)
    return text
