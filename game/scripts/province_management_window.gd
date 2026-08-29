extends VBoxContainer

const GameText := preload("res://scripts/ui/game_text_formatter.gd")

signal recruit_requested(province_id: String, manpower: int)
signal rename_requested(army_id: String, formation_number: int)
signal merge_requested(primary_army_id: String, merged_army_ids: Array)
signal technology_research_requested(track: String)
signal army_selected(army_id: String)
signal destination_selection_requested(army_id: String)
signal reachable_destination_selected(army_id: String, destination_id: String)
signal move_requested(army_id: String, destination_id: String)
signal advance_destination_selection_requested(army_id: String)
signal auto_advance_requested(army_id: String, target_id: String)
signal movement_clear_requested(army_id: String)
signal advance_plan_action_requested(command: String)

var _province_id := ""
var _selected_army_id := ""
var _destination_id := ""
var _advance_target_id := ""
var _army_by_id: Dictionary = {}
var _recruitable_population := 0
var _player_treasury := 0
var _reserved_recruitment := 0
var _recruitment_quote: Dictionary = {}
var _can_manage := false
var _has_pending_research := false
var _army_with_order: Dictionary = {}
var _technology: Dictionary = {}


func _ready() -> void:
    $Recruitment/Open.pressed.connect(_on_recruit_open_pressed)
    $Recruitment/Buttons/Confirm.pressed.connect(_on_recruit_confirm_pressed)
    $Recruitment/Buttons/Cancel.pressed.connect(_close_recruitment)
    $Rename/Confirm.pressed.connect(_on_rename_pressed)
    $Merge/Candidates.multi_selected.connect(_on_merge_selection_changed)
    $Merge/Confirm.pressed.connect(_on_merge_pressed)
    $Technology/Buttons/Economy.pressed.connect(
        func() -> void: technology_research_requested.emit("economy")
    )
    $Technology/Buttons/Military.pressed.connect(
        func() -> void: technology_research_requested.emit("military")
    )
    $Technology/Buttons/Roads.pressed.connect(
        func() -> void: technology_research_requested.emit("roads")
    )
    $ArmySelector.item_selected.connect(_on_army_selected)
    $ReachableDestination.item_selected.connect(
        _on_reachable_destination_selected
    )
    $ArmyActions/SelectDestination.pressed.connect(_on_select_destination_pressed)
    $ArmyActions/MoveArmy.pressed.connect(_on_move_pressed)
    $AdvanceActions/SelectAdvanceTarget.pressed.connect(
        _on_select_advance_target_pressed
    )
    $AdvanceActions/AdvanceNow.pressed.connect(_on_auto_advance_pressed)
    $AdvanceActions/ClearMovement.pressed.connect(_on_clear_movement_pressed)
    $AdvancePlans.meta_clicked.connect(_on_advance_plan_clicked)


func display_province(
    province: Dictionary,
    armies: Array,
    player_country_id: String,
    preferred_army_id := "",
    player_treasury := 0,
    recruitment_quote: Dictionary = {}
) -> void:
    _province_id = province.get("id", "")
    _destination_id = ""
    $ProvinceName.text = province.get("name", _province_id)
    $ProvinceSummary.text = "总人口：%d | 可招募士兵：%d | 经济：%d | 财政收入：%d" % [
        province.get("population", 0),
        province.get("recruitable_population", 0),
        province.get("economy", 0),
        province.get("fiscal_income", 0),
    ]
    _can_manage = String(province.get("owner_id", "")) == player_country_id
    _recruitable_population = int(province.get("recruitable_population", 0))
    _player_treasury = int(player_treasury)
    _recruitment_quote = recruitment_quote.duplicate(true)
    _reserved_recruitment = 0
    _has_pending_research = false
    _army_with_order.clear()
    $Recruitment/Pending.text = "本地区暂无征兵订单"
    $Technology/Pending.text = "暂无研究订单"
    _refresh_paid_action_state()
    _close_recruitment()
    _populate_armies(armies, player_country_id, preferred_army_id)
    _clear_destination()
    set_reachable_targets([])
    set_advance_target("", "")
    $Status.text = (
        "国库负债：禁止新建征兵、修路和研究订单"
        if _player_treasury < 0 else "请选择地区操作"
    )
    visible = true


func set_destination(
    province_id: String,
    province_name: String,
    movement_cost := 0.0,
    is_attack := false
) -> void:
    if province_id.is_empty():
        _clear_destination()
        return
    _destination_id = province_id
    for index: int in range(1, $ReachableDestination.item_count):
        var target: Dictionary = $ReachableDestination.get_item_metadata(index)
        if String(target.get("province_id", "")) == province_id:
            $ReachableDestination.select(index)
            break
    $DirectDestination.text = "订单目的地：%s · %s · 预留移动%s" % [
        province_name,
        "进攻" if is_attack else "调动",
        GameText.movement_points(movement_cost),
    ]
    $ArmyActions/MoveArmy.disabled = _selected_army_id.is_empty()
    $Status.text = "目的地已选择，可确认调动"


func set_technology(technology: Dictionary) -> void:
    _technology = technology.duplicate(true)
    $Technology/Status.text = "经济 %d | 军事 %d | 道路 %d" % [
        technology.get("economy_level", 0),
        technology.get("military_level", 0),
        technology.get("roads_level", 0),
    ]
    _refresh_paid_action_state()


func set_pending_orders(orders: Array) -> void:
    _reserved_recruitment = 0
    _has_pending_research = false
    _army_with_order.clear()
    var research_text := "暂无研究订单"
    for order: Dictionary in orders:
        match String(order.get("type", order.get("order_type", ""))):
            "recruitment":
                if order.get("province_id", "") == _province_id:
                    _reserved_recruitment += int(order.get("manpower", 0))
            "research":
                _has_pending_research = true
                research_text = "%s → %d · 剩余%d个月 · 已预付%d" % [
                    GameText.technology_track_name(String(order.get("track", ""))),
                    order.get("target_level", 0),
                    order.get("remaining_months", 0),
                    order.get("paid_cost", order.get("cost", 0)),
                ]
            "army_action":
                _army_with_order[String(order.get("army_id", ""))] = true
    $Recruitment/Pending.text = (
        "本地区征兵订单：预留%d人" % _reserved_recruitment
        if _reserved_recruitment > 0 else "本地区暂无征兵订单"
    )
    $Technology/Pending.text = research_text
    _refresh_paid_action_state()
    _refresh_rename_and_merge()


func set_reachable_targets(targets: Array) -> void:
    var selected_destination_id := _destination_id
    $ReachableDestination.clear()
    $ReachableDestination.add_item("请选择可达目的地")
    $ReachableDestination.set_item_disabled(0, true)
    $ReachableDestination.set_item_metadata(0, null)
    var selected_index := -1
    for target: Dictionary in targets:
        var destination_id := String(target.get("province_id", ""))
        if destination_id.is_empty():
            continue
        var destination_name := String(target.get("province_name", destination_id))
        $ReachableDestination.add_item("%s · %s · 预留移动%s" % [
            destination_name,
            "进攻" if target.get("is_attack", false) else "调动",
            GameText.movement_points(target.get("movement_cost", 0)),
        ])
        $ReachableDestination.set_item_metadata(
            $ReachableDestination.item_count - 1,
            target
        )
        if destination_id == selected_destination_id:
            selected_index = $ReachableDestination.item_count - 1
    $ReachableDestination.disabled = $ReachableDestination.item_count == 1
    if selected_index >= 1:
        $ReachableDestination.select(selected_index)
    else:
        $ReachableDestination.select(0)
        if not selected_destination_id.is_empty():
            _clear_destination()
    if $ReachableDestination.item_count == 1:
        $ReachableDestination.tooltip_text = "当前军队没有可创建订单的目的地"
    else:
        $ReachableDestination.tooltip_text = "选择核心验证后的可达目的地"


func set_advance_target(province_id: String, province_name: String) -> void:
    _advance_target_id = province_id
    $AdvanceTarget.text = (
        "推进目标：尚未选择" if province_id.is_empty()
        else "推进目标：%s" % province_name
    )
    $AdvanceActions/AdvanceNow.disabled = (
        _selected_army_id.is_empty() or _advance_target_id.is_empty()
    )


func set_advance_plans(bbcode: String) -> void:
    $AdvancePlans.text = "暂无推进计划" if bbcode.is_empty() else bbcode


func set_action_state(direct_enabled: bool, advance_enabled: bool) -> void:
    $ArmyActions/MoveArmy.disabled = not direct_enabled
    $AdvanceActions/AdvanceNow.disabled = not advance_enabled
    $AdvanceActions/ClearMovement.disabled = _selected_army_id.is_empty()


func set_status(message: String) -> void:
    $Status.text = message


func clear() -> void:
    visible = false
    _province_id = ""
    _selected_army_id = ""
    _destination_id = ""
    _advance_target_id = ""
    _army_by_id.clear()
    _army_with_order.clear()
    _technology.clear()
    _close_recruitment()
    _clear_destination()
    set_advance_target("", "")
    set_reachable_targets([])


func _populate_armies(
    armies: Array,
    player_country_id: String,
    preferred_army_id: String
) -> void:
    _army_by_id.clear()
    $ArmySelector.clear()
    var selected_index := -1
    for army: Dictionary in armies:
        if army.get("owner_id", "") != player_country_id or \
                army.get("province_id", "") != _province_id:
            continue
        var army_id: String = army.get("id", "")
        _army_by_id[army_id] = army
        $ArmySelector.add_item("%s（%d 人）" % [
            army.get("display_name", army_id), army.get("manpower", 0)
        ])
        $ArmySelector.set_item_metadata($ArmySelector.item_count - 1, army_id)
        if army_id == preferred_army_id:
            selected_index = $ArmySelector.item_count - 1

    if $ArmySelector.item_count == 0:
        _selected_army_id = ""
        $ArmySelector.disabled = true
        $ArmyDetails.text = "该地区暂无己方驻军"
        $ArmyActions/SelectDestination.disabled = true
        $ArmyActions/MoveArmy.disabled = true
        $AdvanceActions/SelectAdvanceTarget.disabled = true
        $AdvanceActions/AdvanceNow.disabled = true
        $AdvanceActions/ClearMovement.disabled = true
        set_advance_target("", "")
        _refresh_rename_and_merge()
        return

    $ArmySelector.disabled = false
    if selected_index < 0:
        selected_index = 0
    $ArmySelector.select(selected_index)
    _selected_army_id = String($ArmySelector.get_item_metadata(selected_index))
    _refresh_army_details()
    $ArmyActions/SelectDestination.disabled = false
    $ArmyActions/MoveArmy.disabled = true
    $AdvanceActions/SelectAdvanceTarget.disabled = false
    $AdvanceActions/ClearMovement.disabled = false
    _refresh_rename_and_merge()


func _refresh_army_details() -> void:
    var army: Dictionary = _army_by_id.get(_selected_army_id, {})
    $ArmyDetails.text = "%s | 内部ID：%s | 兵力：%d | 移动点：%s/%s（每月+%s）" % [
        army.get("display_name", _selected_army_id),
        _selected_army_id,
        army.get("manpower", 0),
        GameText.movement_points(army.get("movement_points", 0)),
        GameText.movement_points(army.get("max_movement_points", 6)),
        GameText.movement_points(army.get("monthly_movement_grant", 2)),
    ]
    $Rename/FormationNumber.value = int(army.get("formation_number", 1))
    _refresh_rename_and_merge()


func _clear_destination() -> void:
    _destination_id = ""
    $DirectDestination.text = "订单目的地：尚未选择"
    $ArmyActions/MoveArmy.disabled = true


func _maximum_recruitment() -> int:
    if not _recruitment_quote.get("accepted", false):
        return 0
    return maxi(0, int(_recruitment_quote.get("maximum_manpower", 0)))


func _refresh_paid_action_state() -> void:
    $Recruitment/Open.disabled = (
        not _can_manage or _player_treasury < 0 or _maximum_recruitment() <= 0
    )
    _refresh_research_button("economy", $Technology/Buttons/Economy)
    _refresh_research_button("military", $Technology/Buttons/Military)
    _refresh_research_button("roads", $Technology/Buttons/Roads)


func _refresh_research_button(track: String, button: Button) -> void:
    var track_name := GameText.technology_track_name(track)
    var cost := int(_technology.get("%s_cost" % track, 0))
    var reason := ""
    if not _can_manage:
        reason = "只能在己方地区规划研究"
    elif _has_pending_research:
        reason = "已有研究订单，完成或取消后才能新建"
    elif cost <= 0:
        reason = "%s科技已达到当前等级上限" % track_name
    elif _player_treasury < 0:
        reason = "国库负债时不能创建研究订单"
    elif _player_treasury < cost:
        reason = "国库不足：研究%s需要%d，当前%d" % [
            track_name, cost, _player_treasury,
        ]
    button.disabled = not reason.is_empty()
    button.text = (
        "%s已满级" % track_name if cost <= 0
        else "研究%s（%d）" % [track_name, cost]
    )
    button.tooltip_text = reason if not reason.is_empty() else \
        "创建%s研究订单，预付%d" % [track_name, cost]


func _on_recruit_open_pressed() -> void:
    var maximum := _maximum_recruitment()
    $Recruitment/Details.text = "可用兵员：%d | 国库：%d | 权威报价：最大%d人、费用%d" % [
        max(0, _recruitable_population - _reserved_recruitment),
        _player_treasury,
        maximum,
        int(_recruitment_quote.get("cost", 0)),
    ]
    $Recruitment/Amount.max_value = max(1, maximum)
    $Recruitment/Amount.value = min(1000, max(1, maximum))
    $Recruitment/Details.visible = true
    $Recruitment/Amount.visible = true
    $Recruitment/Buttons.visible = true


func _close_recruitment() -> void:
    $Recruitment/Details.visible = false
    $Recruitment/Amount.visible = false
    $Recruitment/Buttons.visible = false


func _on_recruit_confirm_pressed() -> void:
    var manpower := int($Recruitment/Amount.value)
    if not _province_id.is_empty() and manpower > 0:
        recruit_requested.emit(_province_id, manpower)


func _on_rename_pressed() -> void:
    if not _selected_army_id.is_empty():
        rename_requested.emit(
            _selected_army_id, int($Rename/FormationNumber.value)
        )


func _refresh_rename_and_merge() -> void:
    var order_locked := _army_with_order.has(_selected_army_id)
    $Rename/Confirm.disabled = _selected_army_id.is_empty()
    $Merge/Candidates.clear()
    if _selected_army_id.is_empty():
        $Merge/Preview.text = "当前没有可管理的军队"
        $Merge/Confirm.disabled = true
        return
    if order_locked:
        $Merge/Preview.text = "该军队已有待执行订单，不能手动合并"
        $Merge/Confirm.disabled = true
        return
    var primary: Dictionary = _army_by_id.get(_selected_army_id, {})
    for army_id: String in _army_by_id:
        if army_id == _selected_army_id or _army_with_order.has(army_id):
            continue
        var army: Dictionary = _army_by_id[army_id]
        $Merge/Candidates.add_item("%s（%d 人）" % [
            army.get("display_name", army_id), army.get("manpower", 0)
        ])
        $Merge/Candidates.set_item_metadata(
            $Merge/Candidates.item_count - 1, army_id
        )
    if $Merge/Candidates.item_count == 0:
        $Merge/Preview.text = "该地区没有其他可合并军队"
    else:
        $Merge/Preview.text = "%s：请选择并入军队" % primary.get(
            "display_name", _selected_army_id
        )
    $Merge/Confirm.disabled = true


func _selected_merge_ids() -> Array:
    var ids: Array = []
    for index: int in $Merge/Candidates.get_selected_items():
        ids.append(String($Merge/Candidates.get_item_metadata(index)))
    return ids


func _on_merge_selection_changed(_index: int, _selected: bool) -> void:
    var ids := _selected_merge_ids()
    $Merge/Confirm.disabled = ids.is_empty()
    if ids.is_empty():
        $Merge/Preview.text = "请选择需要并入主军的军队"
        return
    var primary: Dictionary = _army_by_id.get(_selected_army_id, {})
    var total_manpower := int(primary.get("manpower", 0))
    var movement_points: float = float(primary.get("movement_points", 0))
    for army_id: String in ids:
        var army: Dictionary = _army_by_id.get(army_id, {})
        total_manpower += int(army.get("manpower", 0))
        movement_points = min(movement_points, float(army.get("movement_points", 0)))
    $Merge/Preview.text = "合并后：%s | 兵力%d | 移动点%s" % [
        primary.get("display_name", _selected_army_id),
        total_manpower,
        GameText.movement_points(movement_points),
    ]


func _on_merge_pressed() -> void:
    var ids := _selected_merge_ids()
    if not _selected_army_id.is_empty() and not ids.is_empty():
        merge_requested.emit(_selected_army_id, ids)


func _on_army_selected(index: int) -> void:
    if index < 0 or index >= $ArmySelector.item_count:
        return
    _selected_army_id = String($ArmySelector.get_item_metadata(index))
    _refresh_army_details()
    _clear_destination()
    set_advance_target("", "")
    army_selected.emit(_selected_army_id)


func _on_reachable_destination_selected(index: int) -> void:
    if index <= 0 or index >= $ReachableDestination.item_count or \
            _selected_army_id.is_empty():
        return
    var target: Dictionary = $ReachableDestination.get_item_metadata(index)
    var destination_id := String(target.get("province_id", ""))
    if destination_id.is_empty():
        return
    set_destination(
        destination_id,
        String(target.get("province_name", destination_id)),
        target.get("movement_cost", 0),
        target.get("is_attack", false)
    )
    reachable_destination_selected.emit(_selected_army_id, destination_id)


func _on_select_destination_pressed() -> void:
    if not _selected_army_id.is_empty():
        destination_selection_requested.emit(_selected_army_id)


func _on_move_pressed() -> void:
    if not _selected_army_id.is_empty() and not _destination_id.is_empty():
        move_requested.emit(_selected_army_id, _destination_id)


func _on_select_advance_target_pressed() -> void:
    if not _selected_army_id.is_empty():
        advance_destination_selection_requested.emit(_selected_army_id)


func _on_auto_advance_pressed() -> void:
    if not _selected_army_id.is_empty() and not _advance_target_id.is_empty():
        auto_advance_requested.emit(_selected_army_id, _advance_target_id)


func _on_clear_movement_pressed() -> void:
    if not _selected_army_id.is_empty():
        movement_clear_requested.emit(_selected_army_id)


func _on_advance_plan_clicked(meta: Variant) -> void:
    advance_plan_action_requested.emit(String(meta))
