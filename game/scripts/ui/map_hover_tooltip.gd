class_name MapHoverTooltip
extends PanelContainer


func show_snapshot(province: Dictionary, country_name: String, position: Vector2) -> void:
    %Name.text = String(province.get("name", "未知地区"))
    %Summary.text = "%s · %s · 人口 %d · 驻军 %d" % [
        country_name if not country_name.is_empty() else "未知国家",
        _terrain_name(String(province.get("terrain", "plains"))),
        int(province.get("population", 0)),
        int(province.get("stationed_manpower", 0)),
    ]
    visible = true
    var viewport_size := get_viewport().get_visible_rect().size
    var tooltip_size := size.max(get_combined_minimum_size())
    var margin := Vector2(8, 8)
    global_position = (position + Vector2(12, 12)).clamp(
        margin,
        (viewport_size - tooltip_size - margin).max(margin)
    )


func hide_tooltip() -> void:
    visible = false


func _terrain_name(terrain: String) -> String:
    match terrain:
        "forest":
            return "森林"
        "hills":
            return "丘陵"
        "mountains":
            return "山地"
        "capital":
            return "首都"
        "plains":
            return "平原"
        _:
            return "未知地形"
