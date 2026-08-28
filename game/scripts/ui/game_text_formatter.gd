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
        "ordered army does not exist":
            return "下单军队不存在"
        "army already has an action order":
            return "该军队已有待执行行动订单"
        "army action path must start at the army's current province":
            return "行动路径必须从军队当前地区开始"
        "army action path contains non-adjacent provinces":
            return "行动路径包含不相邻地区"
        "army action path references an unknown province":
            return "行动路径引用了未知地区"
        "army action path crosses a province not controlled by its country":
            return "行动路径经过了非己方控制地区"
        "attack target is not hostile to the army owner":
            return "进攻目标并非敌对地区"
        "attack target is already locked by another country":
            return "进攻目标已被另一国家锁定"
        "ordinary movement target is not controlled by the army owner":
            return "普通调动目标不受己方控制"
        "army action movement reservation is out of range":
            return "行动预留移动点数超出有效范围"
        "army has insufficient movement points for the action order":
            return "军队移动点不足以创建行动订单"
        "army destination is not reachable with available movement":
            return "目标超出军队当前可用移动范围"
        "order ID sequence is exhausted":
            return "订单编号已耗尽"
        "recruiting country does not exist":
            return "征兵国家不存在"
        "hidden neutral country cannot recruit":
            return "隐藏中立国家不能征兵"
        "country in debt cannot queue paid projects":
            return "国库负债时不能创建付费项目订单"
        "recruitment province does not exist":
            return "征兵地区不存在"
        "recruitment province is not controlled by the country":
            return "征兵地区不受该国控制"
        "recruitment manpower must be positive":
            return "征兵人数必须大于零"
        "recruitment cost overflow":
            return "征兵费用溢出"
        "province population available for recruitment is insufficient":
            return "地区可用于征兵的人口不足"
        "country treasury is insufficient for recruitment":
            return "国库不足以支付征兵费用"
        "road builder country does not exist":
            return "修路国家不存在"
        "hidden neutral country cannot build roads":
            return "隐藏中立国家不能修建道路"
        "both road endpoint provinces must exist":
            return "道路两个端点地区都必须存在"
        "road endpoint provinces are not adjacent":
            return "道路两个端点地区不相邻"
        "road endpoint provinces must be controlled by the paying country":
            return "道路端点必须由付款国家控制"
        "a paved road already exists on this connection":
            return "这两个地区之间已经存在公路"
        "a road construction order already exists on this connection":
            return "这条路线已有待执行修路订单"
        "road builder has no technology state":
            return "修路国家缺少科技状态"
        "road technology level is insufficient for these terrain endpoints":
            return "道路科技等级不足以连接这些地形"
        "country treasury is insufficient to build the road":
            return "国库不足以支付修路费用"
        "researching country does not exist":
            return "研究国家不存在"
        "hidden neutral country cannot research":
            return "隐藏中立国家不能研究科技"
        "country already has a research order":
            return "该国已有待执行研究订单"
        "technology track is already at maximum level":
            return "该科技已达到等级上限"
        "country treasury is insufficient for research":
            return "国库不足以支付研究费用"
        "a country cannot declare war on itself":
            return "国家不能向自己宣战"
        "aggressor country does not exist":
            return "宣战方国家不存在"
        "defender country does not exist":
            return "目标国家不存在"
        "hidden neutral country cannot participate in diplomacy":
            return "隐藏中立国家不能参与外交"
        "countries are already at war":
            return "两国已经处于战争状态"
        "countries already have a pending war declaration":
            return "两国之间已有待执行宣战订单"
        "war declaration references a missing country":
            return "宣战订单引用了不存在的国家"
        "a country cannot make peace with itself":
            return "国家不能与自己议和"
        "both peace participants must exist":
            return "议和双方国家都必须存在"
        "hidden neutral country cannot make peace":
            return "隐藏中立国家不能参与议和"
        "countries are not at war":
            return "两国当前并未处于战争状态"
        "order does not exist":
            return "订单不存在"
        "cannot refund movement to the ordered army":
            return "无法向下单军队退还移动点"
        "cannot refund an order whose country does not exist":
            return "订单所属国家不存在，无法退款"
        "order refund would overflow the country treasury":
            return "订单退款会导致国库数值溢出"
        "ordered army no longer exists":
            return "下单军队已不存在"
        "ordered army is no longer owned by the ordering country":
            return "下单军队已不属于下单国家"
        "ordered army is no longer at the stored path origin":
            return "军队已不在下单时的路径起点"
        "stored army path endpoints are invalid":
            return "保存的路径端点已失效"
        "stored army path is no longer continuous":
            return "保存的路径已不再连续"
        "stored army path no longer has friendly intermediate control":
            return "路径中间地区已不再由己方控制"
        "attack reservation is smaller than its required surcharge":
            return "进攻预留移动点不足以支付进攻附加消耗"
        "attack target is no longer hostile":
            return "进攻目标已不再敌对"
        "ordinary movement target is no longer friendly":
            return "普通调动目标已不再由己方控制"
        "attack group is no longer valid":
            return "联合进攻编组已失效"
        "province recruitable population is insufficient":
            return "地区可招募人口不足"
        "province population is insufficient":
            return "地区总人口不足"
        "prepaid recruitment values must be positive":
            return "预付征兵人数和费用必须大于零"
        "province population reserved for recruitment is unavailable":
            return "地区为征兵预留的人口已不可用"
        "prepaid road cost must be positive":
            return "预付修路费用必须大于零"
        "research order no longer matches the current technology level":
            return "研究订单已不再匹配当前科技等级"
        "army does not exist":
            return "军队不存在"
        "primary army does not exist":
            return "主军队不存在"
        "army with a pending action order cannot be merged":
            return "有待执行行动订单的军队不能合并"
        "at least one army must be merged":
            return "至少需要选择一支并入军队"
        "primary army cannot merge into itself":
            return "主军队不能并入自身"
        "merged army list contains duplicates":
            return "并入军队列表包含重复项"
        "merged army does not exist":
            return "并入军队不存在"
        "armies must belong to the same country":
            return "合并军队必须属于同一国家"
        "armies must occupy the same province":
            return "合并军队必须位于同一地区"
        "merged army manpower overflow":
            return "合并后兵力数值溢出"
        "formation number must be positive":
            return "军团编号必须大于零"
        "formation number is already used by this country":
            return "该军团编号已被本国使用"
        "hidden neutral armies cannot move":
            return "隐藏中立军队不能移动"
        "movement destination does not exist":
            return "移动目标地区不存在"
        "army can only move to an adjacent province":
            return "军队只能移动到相邻地区"
        "army cannot enter foreign territory without war or military access":
            return "未处于战争或未获军事通行权时不能进入外国领土"
        "army has insufficient movement points":
            return "军队移动点不足"
        "army with a pending action order cannot move immediately":
            return "有待执行行动订单的军队不能立即移动"
        "target province not found":
            return "找不到目标地区"
        "army not found":
            return "找不到军队"
        "army has no path to target":
            return "军队没有通往目标的路径"
        "army has no wartime path":
            return "军队没有可用的战时路径"
        "army cannot auto advance":
            return "军队当前无法自动推进"
        "army order could not be created":
            return "无法创建军队行动订单"
        "army action response is missing its created order":
            return "军队行动结果缺少已创建订单"
        "cannot cancel another country's order":
            return "不能取消其他国家的订单"
        "order could not be cancelled":
            return "无法取消订单"
        "armies could not be merged":
            return "无法合并军队"
        "no scenario is loaded":
            return "尚未载入游戏场景"
        "player country is not configured":
            return "尚未配置玩家国家"
        "unknown", "未知原因", "未知错误":
            return "未知错误"
        _:
            return "未知错误"


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
