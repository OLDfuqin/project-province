extends VBoxContainer

signal manage_requested(province_id: String)

var _province_id := ""


func display_province(
    province: Dictionary,
    armies: Array,
    roads: Array,
    province_by_id: Dictionary,
    countries: Array = [],
    pending_orders: Array = []
) -> void:
    var country_names: Dictionary = {}
    var country_colors: Dictionary = {}
    for country: Dictionary in countries:
        var country_name := String(country.get("name", ""))
        if not country_name.is_empty():
            country_names[String(country.get("id", ""))] = country_name
        var rgb := int(country.get("color_rgb", 0))
        country_colors[String(country.get("id", ""))] = Color8(
            (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255
        )
    _province_id = province.get("id", "")
    var province_name := String(province.get("name", ""))
    $ProvinceName.text = province_name if not province_name.is_empty() else "未知地区"
    var terrain := String(province.get("terrain", "plains"))
    var controller_id := String(province.get("owner_id", ""))
    $Identity/IdentityStrip.color = country_colors.get(controller_id, Color("596579"))
    $Identity/IdentityLabel.text = _country_name(controller_id, country_names)
    $Identity/RegionType.text = "首都" if terrain == "capital" else "普通地区"
    $Body/Terrain.text = "地形：%s" % _terrain_description(terrain)
    $Body/Ownership.text = "法理归属：%s | 实际控制：%s%s" % [
        _country_name(
            province.get("legal_owner_id", province.get("owner_id", "")),
            country_names
        ),
        _country_name(province.get("owner_id", ""), country_names),
        " | 已占领" if province.get("occupied", false) else "",
    ]
    _set_metrics(province, armies)
    _set_roads(roads, pending_orders, province_by_id)
    $Economy.text = "财政收入：%s" % _format_number(
        int(province.get("fiscal_income", 0))
    )
    $Body/Recruitable.text = "可招募士兵：%s" % _format_number(
        int(province.get("recruitable_population", 0))
    )
    $Body/ManageProvince.visible = true
    visible = true


func _set_metrics(province: Dictionary, armies: Array) -> void:
    var stationed_armies := 0
    var stationed_manpower := 0
    for army: Dictionary in armies:
        if army.get("province_id", "") == _province_id:
            stationed_armies += 1
            stationed_manpower += int(army.get("manpower", 0))
    _set_metric($Body/Metrics/Population,
        "人口", _format_number(int(province.get("population", 0)))
    )
    _set_metric($Body/Metrics/Economy,
        "经济", _format_number(int(province.get("economy", 0)))
    )
    _set_metric($Body/Metrics/FiscalIncome,
        "财政收入", _format_number(int(province.get("fiscal_income", 0)))
    )
    _set_metric($Body/Metrics/Garrison,
        "驻军", "%d 支" % stationed_armies,
        "总兵力：%s" % _format_number(stationed_manpower)
    )


func _set_metric(card: Control, title: String, value: String, detail := "") -> void:
    (card.get_node("Content/Title") as Label).text = title
    (card.get_node("Content/Value") as Label).text = value
    var detail_label := card.get_node("Content/Detail") as Label
    detail_label.text = detail
    detail_label.visible = not detail.is_empty()


func _set_roads(roads: Array, pending_orders: Array, province_by_id: Dictionary) -> void:
    var road_connections: Array[String] = []
    for road: Dictionary in roads:
        var other_id := ""
        if road.get("province_a", "") == _province_id:
            other_id = road.get("province_b", "")
        elif road.get("province_b", "") == _province_id:
            other_id = road.get("province_a", "")
        if other_id.is_empty():
            continue
        var other_name := String(province_by_id.get(other_id, {}).get("name", ""))
        if other_name.is_empty():
            other_name = "未知地区"
        road_connections.append("%s（%s）" % [
            other_name,
            _road_level_name(road.get("level", "paved")),
        ])
    var pending_connections: Array[String] = []
    for order_value: Variant in pending_orders:
        var order: Dictionary = order_value
        if String(order.get("type", order.get("order_type", ""))) != "road_construction":
            continue
        var other_id := ""
        if String(order.get("province_a", "")) == _province_id:
            other_id = String(order.get("province_b", ""))
        elif String(order.get("province_b", "")) == _province_id:
            other_id = String(order.get("province_a", ""))
        if not other_id.is_empty():
            pending_connections.append("%s（待建，剩余%d个月）" % [
                String(province_by_id.get(other_id, {}).get("name", "未知地区")),
                int(order.get("remaining_months", 0)),
            ])
    var sections: Array[String] = []
    if not road_connections.is_empty():
        sections.append("已建：%s" % "、".join(road_connections))
    if not pending_connections.is_empty():
        sections.append("工程：%s" % "、".join(pending_connections))
    $Body/Roads.text = "道路：暂无连接" if sections.is_empty() else "道路：%s" % "；".join(sections)


func _on_manage_province_pressed() -> void:
    if not _province_id.is_empty():
        manage_requested.emit(_province_id)


func _format_number(value: int) -> String:
    var raw := str(absi(value))
    var groups: Array[String] = []
    while not raw.is_empty():
        var start := maxi(0, raw.length() - 3)
        groups.push_front(raw.substr(start))
        raw = raw.substr(0, start)
    return ("-" if value < 0 else "") + ",".join(groups)


func _country_name(country_id: String, country_names: Dictionary) -> String:
    if country_id.is_empty() or country_id == "neutral":
        return "无主地区"
    var name := String(country_names.get(country_id, ""))
    return name if not name.is_empty() else "未知国家"


func _terrain_name(terrain: String) -> String:
    match terrain:
        "capital":
            return "首都"
        "mountains":
            return "山地"
        "hills":
            return "丘陵"
        "forest":
            return "森林"
        _:
            return "平原"


func _terrain_description(terrain: String) -> String:
    # docs/current-game-rules.md defines capital terrain as a fixed +50% defense rule.
    if terrain == "capital":
        return "首都 · 防守 +50%"
    return _terrain_name(terrain)


func _road_level_name(level: String) -> String:
    return "公路" if level == "paved" else "道路"


func clear() -> void:
    visible = false
