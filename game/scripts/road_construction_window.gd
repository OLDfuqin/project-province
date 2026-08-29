extends VBoxContainer

signal select_start_requested
signal select_end_requested
signal build_requested
signal reset_requested


func _ready() -> void:
    $EndpointButtons/SelectStart.pressed.connect(
        func() -> void: select_start_requested.emit()
    )
    $EndpointButtons/SelectEnd.pressed.connect(
        func() -> void: select_end_requested.emit()
    )
    $ActionButtons/BuildRoad.pressed.connect(
        func() -> void: build_requested.emit()
    )
    $ActionButtons/Reset.pressed.connect(
        func() -> void: reset_requested.emit()
    )


func open_window() -> void:
    visible = true
    reset_selection("请选择道路起点")


func reset_selection(status_message := "选择已重置") -> void:
    $StartProvince.text = "起点：尚未选择"
    $EndProvince.text = "终点：尚未选择"
    $EstimatedCost.text = "预计费用：等待权威报价"
    $EndpointButtons/SelectStart.disabled = false
    $EndpointButtons/SelectEnd.disabled = true
    $ActionButtons/BuildRoad.disabled = true
    $Status.text = status_message


func set_start(province_name: String) -> void:
    $StartProvince.text = "起点：%s" % province_name
    $EndProvince.text = "终点：尚未选择"
    $EstimatedCost.text = "预计费用：等待权威报价"
    $EndpointButtons/SelectEnd.disabled = false
    $ActionButtons/BuildRoad.disabled = true
    $Status.text = "起点已选择，请选择终点"


func set_end_province(
    province_name: String,
    estimated_cost: int = 0,
    can_build: bool = true,
    status_message := "路线合法，可以确认修建"
) -> void:
    $EndProvince.text = "终点：%s" % province_name
    $EstimatedCost.text = (
        "预计费用：%d" % estimated_cost
        if estimated_cost > 0 else "预计费用：权威报价不可用"
    )
    $ActionButtons/BuildRoad.disabled = not can_build
    $Status.text = status_message


func set_status(message: String) -> void:
    $Status.text = message


func clear() -> void:
    visible = false
