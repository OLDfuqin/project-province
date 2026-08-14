extends VBoxContainer

signal recruit_requested(province_id: String, manpower: int)
signal rename_requested(army_id: String, formation_number: int)
signal merge_requested(primary_army_id: String, merged_army_ids: Array)
signal technology_research_requested(track: String)
signal army_selected(army_id: String)
signal destination_selection_requested(army_id: String)
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
    player_treasury := 0
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
    var can_manage: bool = String(province.get("owner_id", "")) == player_country_id
    _recruitable_population = int(province.get("recruitable_population", 0))
    _player_treasury = int(player_treasury)
    $Recruitment/Open.disabled = not can_manage or _maximum_recruitment() <= 0
    _close_recruitment()
    _populate_armies(armies, player_country_id, preferred_army_id)
    _clear_destination()
    set_advance_target("", "")
    $Status.text = "请选择地区操作"
    visible = true


func set_destination(province_id: String, province_name: String) -> void:
    if province_id.is_empty():
        _clear_destination()
        return
    _destination_id = province_id
    $DirectDestination.text = "直接调动目的地：%s" % province_name
    $ArmyActions/MoveArmy.disabled = _selected_army_id.is_empty()
    $Status.text = "目的地已选择，可确认调动"


func set_technology(technology: Dictionary) -> void:
    $Technology/Status.text = "经济 %d | 军事 %d | 道路 %d" % [
        technology.get("economy_level", 0),
        technology.get("military_level", 0),
        technology.get("roads_level", 0),
    ]


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
    _close_recruitment()
    _clear_destination()
    set_advance_target("", "")


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
    $ArmyDetails.text = "%s | 内部ID：%s | 兵力：%d | 移动点：%d" % [
        army.get("display_name", _selected_army_id),
        _selected_army_id,
        army.get("manpower", 0),
        army.get("movement_points", 0),
    ]
    $Rename/FormationNumber.value = int(army.get("formation_number", 1))
    _refresh_rename_and_merge()


func _clear_destination() -> void:
    _destination_id = ""
    $DirectDestination.text = "直接调动目的地：尚未选择"
    $ArmyActions/MoveArmy.disabled = true


func _maximum_recruitment() -> int:
    return min(_recruitable_population, _player_treasury)


func _on_recruit_open_pressed() -> void:
    var maximum := _maximum_recruitment()
    $Recruitment/Details.text = "可招募士兵：%d | 国库：%d | 最大：%d" % [
        _recruitable_population, _player_treasury, maximum
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
    $Rename/Confirm.disabled = _selected_army_id.is_empty()
    $Merge/Candidates.clear()
    if _selected_army_id.is_empty():
        $Merge/Preview.text = "当前没有可管理的军队"
        $Merge/Confirm.disabled = true
        return
    var primary: Dictionary = _army_by_id.get(_selected_army_id, {})
    for army_id: String in _army_by_id:
        if army_id == _selected_army_id:
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
    var movement_points := int(primary.get("movement_points", 0))
    for army_id: String in ids:
        var army: Dictionary = _army_by_id.get(army_id, {})
        total_manpower += int(army.get("manpower", 0))
        movement_points = min(movement_points, int(army.get("movement_points", 0)))
    $Merge/Preview.text = "合并后：%s | 兵力%d | 移动点%d" % [
        primary.get("display_name", _selected_army_id),
        total_manpower,
        movement_points,
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
