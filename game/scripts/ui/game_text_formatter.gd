class_name GameTextFormatter
extends RefCounted


static func battle_result_name(result: String) -> String:
    match result:
        "attacker_victory":
            return "进攻方胜利"
        "mutual_destruction":
            return "双方同归于尽"
        _:
            return "防守方胜利"


static func battle_report(result: Dictionary, province_by_id: Dictionary) -> String:
    if not result.get("battle_occurred", false) and not result.get("province_occupied", false):
        return ""
    if not result.get("battle_occurred", false):
        return "地区在无抵抗情况下被占领"
    var details: Array[String] = []
    for outcome: Dictionary in result.get("battle_outcomes", []):
        var casualties := int(outcome.get("casualties", 0))
        var suffix := ""
        if outcome.get("destroyed", false):
            suffix = "，部队被消灭"
        elif String(outcome.get("retreat_province", "")) != "":
            suffix = "，撤退至%s" % province_name(
                province_by_id,
                outcome["retreat_province"]
            )
        details.append("%s 损失%d%s" % [_battle_army_name(outcome), casualties, suffix])
    return "战斗：%s；%s%s | %s" % [
        battle_result_name(String(result.get("battle_result", "defender_victory"))),
        _battle_calculation_summary(result),
        "；地区被占领" if result.get("province_occupied", false) else "",
        "，".join(details),
    ]


static func battle_action_report(action: Dictionary, province_by_id: Dictionary) -> String:
    var joint_prefix := ""
    var order_count := int(action.get("order_ids", []).size())
    if order_count > 1:
        joint_prefix = "联合战斗（%d支进攻订单）：" % order_count
    if not action.get("battle_occurred", false):
        return "%s回合行动：无抵抗占领%s" % [joint_prefix, province_name(
            province_by_id,
            action.get("province_id", "?")
        )]
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
            _battle_army_name(outcome),
            outcome.get("casualties", 0),
            outcome.get("remaining_manpower", 0),
            suffix,
        ])
    return "%s回合战斗：%s，%s，%s%s | %s" % [
        joint_prefix,
        province_name(province_by_id, action.get("province_id", "?")),
        battle_result_name(String(action.get("battle_result", "defender_victory"))),
        _battle_calculation_summary(action),
        "，地区被占领" if action.get("province_occupied", false) else "",
        "，".join(details),
    ]


static func pending_order_text(
    order: Dictionary,
    province_by_id: Dictionary
) -> String:
    var remaining := int(order.get("remaining_months", 1))
    var status := "待执行" if order.get("status", "pending") == "pending" else \
        String(order.get("status", "未知状态"))
    match String(order.get("type", order.get("order_type", ""))):
        "army_action":
            return "%s · 目标%s · 剩余%d个月 · 预留移动%s · %s" % [
                "进攻" if order.get("is_attack", false) else "调动",
                province_name(province_by_id, order.get("destination", "?")),
                remaining,
                movement_points(float(order.get("reserved_movement_half", 0)) / 2.0),
                status,
            ]
        "recruitment":
            return "征兵 · 目标%s · 剩余%d个月 · 预付%d · 预留兵员%d · %s" % [
                province_name(province_by_id, order.get("province_id", "?")),
                remaining,
                order.get("paid_cost", order.get("cost", 0)),
                order.get("manpower", 0),
                status,
            ]
        "road_construction":
            return "修路 · %s → %s · 剩余%d个月 · 预付%d · %s" % [
                province_name(province_by_id, order.get("province_a", "?")),
                province_name(province_by_id, order.get("province_b", "?")),
                remaining,
                order.get("paid_cost", order.get("cost", 0)),
                status,
            ]
        "research":
            return "研究%s → %d级 · 剩余%d个月 · 预付%d · %s" % [
                technology_track_name(String(order.get("track", ""))),
                order.get("target_level", 0),
                remaining,
                order.get("paid_cost", order.get("cost", 0)),
                status,
            ]
        "war_declaration":
            return "宣战 · 目标%s · 剩余%d个月 · %s" % [
                order.get("defender_id", "?"), remaining, status,
            ]
        _:
            return "未知订单 · 剩余%d个月 · %s" % [remaining, status]


static func technology_track_name(track: String) -> String:
    match track:
        "economy":
            return "经济"
        "military":
            return "军事"
        "roads":
            return "道路"
        _:
            return track


static func order_failure_reason(reason: String) -> String:
    match reason:
        "path no longer legal":
            return "路径已不再合法"
        "ordered army is no longer at the stored path origin":
            return "军队已不在下单时的路径起点"
        "stored army path endpoints are invalid":
            return "保存的路径端点已失效"
        "stored army path is no longer continuous":
            return "保存的路径已不再连续"
        "stored army path no longer has friendly intermediate control":
            return "路径中间地区已不再由己方控制"
        "ordinary movement target is now hostile":
            return "普通移动目标已变为敌方地区"
        _:
            return reason


static func turn_action_report(
    action: Dictionary,
    province_by_id: Dictionary
) -> String:
    match String(action.get("type", "")):
        "army_recruited":
            return "征兵订单完成：%s新增%d人" % [
                province_name(province_by_id, action.get("province_id", "?")),
                action.get("manpower", 0),
            ]
        "road_built":
            return "道路订单完成：%s → %s" % [
                province_name(province_by_id, action.get("province_a", "?")),
                province_name(province_by_id, action.get("province_b", "?")),
            ]
        "technology_researched":
            return "研究订单完成：%s科技达到%d级" % [
                technology_track_name(String(action.get("track", ""))),
                action.get("current_level", 0),
            ]
        "army_moved":
            return "调动订单完成：%s → %s，消耗%s移动点%s" % [
                province_name(province_by_id, action.get("origin", "?")),
                province_name(province_by_id, action.get("destination", "?")),
                movement_points(action.get("movement_cost", 0)),
                "（进攻转普通移动并退款）" if action.get(
                    "converted_from_attack", false
                ) else "",
            ]
        "battle_resolved":
            return battle_action_report(action, province_by_id)
        "order_cancelled":
            var report := "订单失败：%s；原因：%s" % [
                action.get("order_id", "?"),
                order_failure_reason(String(action.get("reason", "未知原因"))),
            ]
            var refunded_cost := int(action.get("refunded_cost", 0))
            var refunded_movement := int(action.get("refunded_movement_half", 0))
            if refunded_cost > 0:
                report += "；退款%d" % refunded_cost
            if refunded_movement > 0:
                report += "；退还移动%s" % movement_points(
                    float(refunded_movement) / 2.0
                )
            if refunded_cost == 0 and refunded_movement == 0:
                report += "；无退款"
            return report
        "armies_merged":
            if not action.get("automatic", false):
                return ""
            return "自动整编：%s合并%d支军队，现有兵力%d" % [
                action.get("display_name", action.get("primary_army_id", "?")),
                action.get("merged_army_ids", []).size(),
                action.get("current_manpower", 0),
            ]
        _:
            return ""


static func _battle_army_name(outcome: Dictionary) -> String:
    var display_name := String(outcome.get("display_name", ""))
    return display_name if not display_name.is_empty() else String(
        outcome.get("army_id", "?")
    )


static func _battle_calculation_summary(result: Dictionary) -> String:
    return "进攻方：随机系数X%.1f，参战兵力%d，军事等级%d，基础有效战力%d；防守方：随机系数X%.1f，参战兵力%d，军事等级%d，基础有效战力%d，地形防御%d%%，最终有效战力%d；结算：进攻方伤亡%d、剩余兵力%d；防守方伤亡%d、剩余兵力%d" % [
        float(result.get("attacker_random_x", 0.0)),
        int(result.get("attacker_initial_manpower", 0)),
        int(result.get("attacker_military_level", 0)),
        int(result.get("attacker_base_strength", 0)),
        float(result.get("defender_random_x", 0.0)),
        int(result.get("defender_initial_manpower", 0)),
        int(result.get("defender_military_level", 0)),
        int(result.get("defender_base_strength", 0)),
        int(result.get("terrain_defense_bonus", 0)),
        int(result.get("defender_final_strength", 0)),
        int(result.get("attacker_casualties", 0)),
        int(result.get("attacker_remaining_manpower", 0)),
        int(result.get("defender_casualties", 0)),
        int(result.get("defender_remaining_manpower", 0)),
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
