class_name GameTextFormatter
extends RefCounted


static func battle_report(result: Dictionary, province_by_id: Dictionary) -> String:
    if not result.get("battle_occurred", false) and not result.get("province_occupied", false):
        return ""
    if not result.get("battle_occurred", false):
        return "地区在无抵抗情况下被占领"
    var total_casualties := 0
    var details: Array[String] = []
    for outcome: Dictionary in result.get("battle_outcomes", []):
        var casualties := int(outcome.get("casualties", 0))
        total_casualties += casualties
        var suffix := ""
        if outcome.get("destroyed", false):
            suffix = "，部队被消灭"
        elif String(outcome.get("retreat_province", "")) != "":
            suffix = "，撤退至%s" % province_name(
                province_by_id,
                outcome["retreat_province"]
            )
        details.append("%s 损失%d%s" % [outcome.get("army_id", "?"), casualties, suffix])
    return "战斗：%s；总伤亡%d%s | %s" % [
        "进攻方胜利" if result.get("attacker_won", false) else "防守方胜利",
        total_casualties,
        "；地区被占领" if result.get("province_occupied", false) else "",
        "，".join(details),
    ]


static func battle_action_report(action: Dictionary, province_by_id: Dictionary) -> String:
    if not action.get("battle_occurred", false):
        return "回合行动：无抵抗占领%s" % province_name(
            province_by_id,
            action.get("province_id", "?")
        )
    var details: Array[String] = []
    for outcome: Dictionary in action.get("battle_outcomes", []):
        var suffix := ""
        if outcome.get("destroyed", false):
            suffix = "，部队被消灭"
        elif String(outcome.get("retreat_province", "")) != "":
            suffix = "，撤退至%s" % province_name(
                province_by_id,
                outcome["retreat_province"]
            )
        details.append("%s 损失%d，剩余%d%s" % [
            outcome.get("army_id", "?"),
            outcome.get("casualties", 0),
            outcome.get("remaining_manpower", 0),
            suffix,
        ])
    return "回合战斗：%s，%s，总伤亡%d%s | %s" % [
        province_name(province_by_id, action.get("province_id", "?")),
        "进攻方胜利" if action.get("attacker_won", false) else "防守方胜利",
        action.get("casualties", 0),
        "，地区被占领" if action.get("province_occupied", false) else "",
        "，".join(details),
    ]


static func advance_stop_reason(reason: String) -> String:
    match reason:
        "target_reached":
            return "已到达目标"
        "enemy_border":
            return "将在敌方边境前停止"
        "insufficient_movement":
            return "移动点不足"
        "strategy_limit":
            return "单步推进策略限制"
        _:
            return reason


static func movement_points(value: Variant) -> String:
    var number := float(value)
    if is_equal_approx(number, round(number)):
        return "%d" % int(round(number))
    return "%.1f" % number


static func advance_strategy(strategy: String) -> String:
    match strategy:
        "one_step":
            return "单步推进"
        "stop_before_enemy":
            return "敌境前停止"
        _:
            return "最大推进"


static func province_name(province_by_id: Dictionary, province_id: String) -> String:
    return province_by_id.get(
        province_id,
        {"name": province_id}
    ).get("name", province_id)
