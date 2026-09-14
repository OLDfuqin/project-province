extends VBoxContainer

signal select_start_requested
signal select_end_requested
signal build_requested
signal reset_requested
signal exit_requested


func _ready() -> void:
    %SelectStart.pressed.connect(_on_select_start_pressed)
    %SelectEnd.pressed.connect(_on_select_end_pressed)
    %BuildRoad.pressed.connect(func() -> void: build_requested.emit())
    %Reset.pressed.connect(func() -> void: reset_requested.emit())
    %Exit.pressed.connect(func() -> void: exit_requested.emit())


func open_window() -> void:
    visible = true
    reset_selection("请选择道路起点")


func reset_selection(status_message := "选择已重置") -> void:
    %StartProvince.text = "尚未选择"
    %EndProvince.text = "尚未选择"
    %Cost.text = "—"
    %SelectStart.disabled = false
    %SelectEnd.disabled = true
    %BuildRoad.disabled = true
    set_selection_mode("")
    %Status.text = status_message


func set_selection_mode(mode: String) -> void:
    %SelectStart.button_pressed = mode == "start"
    %SelectEnd.button_pressed = mode == "end"
    %ModeHint.text = {
        "start": "请在地图上选择道路起点",
        "end": "请在地图上选择相邻终点",
    }.get(mode, "请选择道路端点")


func set_start(province_name: String) -> void:
    %StartProvince.text = province_name
    %EndProvince.text = "尚未选择"
    %Cost.text = "—"
    %SelectEnd.disabled = false
    %BuildRoad.disabled = true
    set_selection_mode("")
    %ModeHint.text = "起点已选择，请选择相邻终点"
    %Status.text = "起点已选择，请选择终点"


func set_end_province(
    province_name: String,
    estimated_cost: int = 0,
    can_build: bool = true,
    status_message := "路线合法，可以创建订单"
) -> void:
    %EndProvince.text = province_name
    %Cost.text = "%d" % estimated_cost if estimated_cost > 0 else "—"
    %Status.text = status_message
    %BuildRoad.disabled = not can_build


func set_status(message: String) -> void:
    %Status.text = message


func clear() -> void:
    visible = false


func _on_select_start_pressed() -> void:
    select_start_requested.emit()
    set_selection_mode("start")


func _on_select_end_pressed() -> void:
    select_end_requested.emit()
    set_selection_mode("end")
