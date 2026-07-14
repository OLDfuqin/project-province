extends VBoxContainer


func display_province(
    province: Dictionary,
    armies: Array,
    roads: Array,
    province_by_id: Dictionary
) -> void:
    var province_id: String = province.get("id", "")
    $ProvinceName.text = province.get("name", province_id)
    $Terrain.text = "地形：%s" % province.get("terrain", "plains")
    $Ownership.text = "法理归属：%s | 实际控制：%s%s" % [
        province.get("legal_owner_id", province.get("owner_id", "")),
        province.get("owner_id", ""),
        " | 已占领" if province.get("occupied", false) else "",
    ]
    $Population.text = "总人口：%d | 可招募士兵：%d" % [
        province.get("population", 0),
        province.get("recruitable_population", 0),
    ]
    $Economy.text = "经济：%d" % province.get("economy", 0)

    var stationed_armies := 0
    var stationed_manpower := 0
    for army: Dictionary in armies:
        if army.get("province_id", "") == province_id:
            stationed_armies += 1
            stationed_manpower += int(army.get("manpower", 0))
    $Military.text = "驻军：%d 支 | 总兵力：%d" % [
        stationed_armies,
        stationed_manpower,
    ]

    var road_connections: Array[String] = []
    for road: Dictionary in roads:
        var other_id := ""
        if road.get("province_a", "") == province_id:
            other_id = road.get("province_b", "")
        elif road.get("province_b", "") == province_id:
            other_id = road.get("province_a", "")
        if other_id.is_empty():
            continue
        var other_name: String = province_by_id.get(
            other_id,
            {"name": other_id}
        ).get("name", other_id)
        road_connections.append("%s（%s）" % [
            other_name,
            road.get("level", "paved"),
        ])
    $Roads.text = (
        "道路：暂无道路" if road_connections.is_empty()
        else "道路：%s" % "、".join(road_connections)
    )
    visible = true


func clear() -> void:
    visible = false
