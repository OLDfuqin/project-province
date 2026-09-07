class_name TechnologyPage
extends PanelContainer


signal research_requested(track: String)


const TRACKS := ["economy", "military", "roads"]


func _ready() -> void:
	for track: String in TRACKS:
		_track_button(track).pressed.connect(func() -> void: research_requested.emit(track))


func set_snapshot(technology: Dictionary, pending_orders: Array, treasury: int) -> void:
	var research_pending := false
	for order: Dictionary in pending_orders:
		if String(order.get("type", order.get("order_type", ""))) == "research":
			research_pending = true
			break
	for track: String in TRACKS:
		_set_track(track, technology, treasury, research_pending)
	%Pending.text = "已有研究订单正在等待完成" if research_pending else "当前没有研究订单"


func _set_track(track: String, data: Dictionary, treasury: int, blocked: bool) -> void:
	var level := int(data.get("%s_level" % track, 0))
	var cost := int(data.get("%s_cost" % track, 0))
	var at_max := bool(data.get("%s_max" % track, false))
	var button := _track_button(track)
	button.text = "已达最高等级" if at_max else "研究（%d）" % cost
	button.disabled = at_max or blocked or treasury < cost
	_track_level_label(track).text = "等级 %d" % level
	if at_max:
		button.tooltip_text = "该科技已达到最高等级"
	elif blocked:
		button.tooltip_text = "已有研究订单正在等待完成"
	elif treasury < cost:
		button.tooltip_text = "国库不足，无法支付研究费用"
	else:
		button.tooltip_text = "创建%s科技的研究意图" % _track_name(track)


func _track_button(track: String) -> Button:
	match track:
		"economy":
			return $Content/Tracks/Economy/Research
		"military":
			return $Content/Tracks/Military/Research
		_:
			return $Content/Tracks/Roads/Research


func _track_level_label(track: String) -> Label:
	match track:
		"economy":
			return $Content/Tracks/Economy/Level
		"military":
			return $Content/Tracks/Military/Level
		_:
			return $Content/Tracks/Roads/Level


func _track_name(track: String) -> String:
	match track:
		"economy":
			return "经济"
		"military":
			return "军事"
		_:
			return "道路"
