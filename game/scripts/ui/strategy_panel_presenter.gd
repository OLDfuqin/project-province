class_name StrategyPanelPresenter
extends RefCounted

const GameText := preload("res://scripts/ui/game_text_formatter.gd")


static func country_details(
    countries: Array,
    technologies: Array,
    status: Dictionary,
    relations: Array,
    country_names: Dictionary
) -> String:
    var technology_by_country: Dictionary = {}
    for technology: Dictionary in technologies:
        technology_by_country[technology["country_id"]] = technology
    var status_by_country: Dictionary = {}
    for country_status: Dictionary in status.get("countries", []):
        status_by_country[country_status["country_id"]] = country_status
    var war_pairs: Array[String] = []
    for relation: Dictionary in relations:
        if relation.get("status", "") == "war":
            war_pairs.append("%s-%s" % [
                country_names.get(relation["country_a"], relation["country_a"]),
                country_names.get(relation["country_b"], relation["country_b"]),
            ])
    var lines: Array[String] = []
    for country: Dictionary in countries:
        var tech: Dictionary = technology_by_country.get(country["id"], {})
        var state: Dictionary = status_by_country.get(country["id"], {})
        lines.append("%s | 国库 %d | 控制地区 %d | 科技 经济%d 军事%d 道路%d%s" % [
            country["name"],
            country["treasury"],
            state.get("controlled_provinces", country["province_count"]),
            tech.get("economy_level", 0),
            tech.get("military_level", 0),
            tech.get("roads_level", 0),
            " | 已灭亡" if state.get("eliminated", false) else "",
        ])
    if not war_pairs.is_empty():
        lines.append("战争：%s" % "，".join(war_pairs))
    return "\n".join(lines)


static func war_overview(wars: Array, country_names: Dictionary) -> String:
    if wars.is_empty():
        return "当前无战争"
    var lines: Array[String] = []
    for war: Dictionary in wars:
        lines.append("%s 对 %s | 兵力 %d:%d | 占领地区 %d:%d | 战线 %d" % [
            country_names.get(war["country_a"], war["country_a"]),
            country_names.get(war["country_b"], war["country_b"]),
            war["country_a_manpower"],
            war["country_b_manpower"],
            war["country_a_occupied_provinces"],
            war["country_b_occupied_provinces"],
            war["front_edges"],
        ])
    return "\n".join(lines)


static func advance_plans(
    bridge: Object,
    armies: Array,
    province_by_id: Dictionary,
    player_country_id: String,
    preview_months: int
) -> String:
    var lines: Array[String] = []
    for army: Dictionary in armies:
        if army["owner_id"] != player_country_id:
            continue
        var target_id: String = army.get("advance_target_id", "")
        if target_id.is_empty():
            continue
        var is_enabled := bool(army.get("advance_enabled", true))
        var strategy: String = army.get("advance_strategy", "max")
        var origin_id: String = army["province_id"]
        var origin_name: String = GameText.province_name(province_by_id, origin_id)
        var target_name: String = GameText.province_name(province_by_id, target_id)
        var path_preview: Dictionary = bridge.get_auto_advance_path_for_months(
            army["id"],
            target_id,
            preview_months
        )
        var status := _advance_status(
            army,
            path_preview,
            province_by_id,
            origin_id,
            preview_months,
            is_enabled
        )
        var toggle_command := "pause" if is_enabled else "resume"
        var toggle_label := "暂停" if is_enabled else "继续"
        var next_strategy := "one_step"
        var strategy_label := "单步推进"
        if strategy == "one_step":
            next_strategy = "stop_before_enemy"
            strategy_label = "敌境前停止"
        elif strategy == "stop_before_enemy":
            next_strategy = "max"
            strategy_label = "最大推进"
        lines.append("[url=select:%s]%s[/url]：%s → %s | %s | 策略：%s [url=strategy:%s:%s][切换为%s][/url] [url=%s:%s][%s][/url] [url=clear:%s][清除][/url]" % [
            army["id"],
            army.get("display_name", army["id"]), origin_name, target_name, status,
            GameText.advance_strategy(strategy),
            army["id"],
            next_strategy,
            strategy_label,
            toggle_command,
            army["id"],
            toggle_label,
            army["id"],
        ])
    if lines.is_empty():
        return ""
    return "[b]推进计划[/b]\n%s" % "\n".join(lines)


static func _advance_status(
    army: Dictionary,
    path_preview: Dictionary,
    province_by_id: Dictionary,
    origin_id: String,
    preview_months: int,
    is_enabled: bool
) -> String:
    if not is_enabled:
        return "已暂停"
    if not path_preview.get("accepted", false):
        return "受阻：%s" % path_preview.get("error", "未知错误")
    var preview_destination_id: String = path_preview.get(
        "preview_destination_id",
        origin_id
    )
    return "%d步，首步%d移动点，总计%d移动点；当前%d，本回合增加%d；%d个月后到达%s（%d步，消耗%d移动点，%s）" % [
        path_preview.get("step_count", 0),
        int(path_preview.get("first_step_cost", 0)),
        path_preview.get("total_movement_cost", 0),
        army.get("movement_points", 0),
        path_preview.get("preview_movement_granted", 0),
        preview_months,
        GameText.province_name(province_by_id, preview_destination_id),
        path_preview.get("preview_step_count", 0),
        path_preview.get("preview_movement_cost", 0),
        GameText.advance_stop_reason(
            path_preview.get("preview_stop_reason", "unknown")
        ),
    ]
