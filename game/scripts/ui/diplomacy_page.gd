class_name DiplomacyPage
extends PanelContainer


signal declare_war_requested(target_country_id: String)
signal make_peace_requested(target_country_id: String, annex_occupied: bool)

const DECLARE_WAR_TOOLTIP := "向当前选择的国家发出宣战意图"
const MAKE_PEACE_TOOLTIP := "向当前选择的国家发出议和意图"
const SELECT_TARGET_TOOLTIP := "当前不可用：请先选择外交目标"
const ALREADY_AT_WAR_TOOLTIP := "当前不可用：当前目标已与我国交战"
const NOT_AT_WAR_TOOLTIP := "当前不可用：当前目标未与我国交战"


var _player_country_id := ""
var _countries_by_id: Dictionary = {}
var _wars: Array = []
var _selected_country_id := ""


func _ready() -> void:
	$Content/Actions/DeclareWar.pressed.connect(_on_declare_war_pressed)
	$Content/Actions/MakePeace.pressed.connect(_on_make_peace_pressed)
	_refresh_selection_state()


func set_snapshot(player_country_id: String, countries: Array, wars: Array) -> void:
	_player_country_id = player_country_id
	_countries_by_id.clear()
	_wars = wars.duplicate(true)
	for country: Dictionary in countries:
		var country_id := String(country.get("id", ""))
		if not country_id.is_empty():
			_countries_by_id[country_id] = country.duplicate(true)
	if not _countries_by_id.has(_selected_country_id) or _selected_country_id == _player_country_id:
		_selected_country_id = ""
	_rebuild_country_rows()
	_refresh_selection_state()


func select_country(country_id: String) -> void:
	if country_id == _player_country_id or not _countries_by_id.has(country_id):
		return
	_selected_country_id = country_id
	_rebuild_country_rows()
	_refresh_selection_state()


func _rebuild_country_rows() -> void:
	var rows := $Content/Countries/Rows as VBoxContainer
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var country_ids: Array = _countries_by_id.keys()
	country_ids.sort()
	for country_id_variant: Variant in country_ids:
		var country_id := String(country_id_variant)
		if country_id == _player_country_id:
			continue
		var row := Button.new()
		row.name = "Country%d" % rows.get_child_count()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.text = "%s · %s" % [_country_name(country_id), _relation_label(country_id)]
		row.tooltip_text = "选择%s" % _country_name(country_id)
		row.disabled = false
		row.button_pressed = country_id == _selected_country_id
		row.pressed.connect(func() -> void: select_country(country_id))
		rows.add_child(row)
	%Empty.visible = rows.get_child_count() == 0
	if _selected_country_id.is_empty():
		%Selection.text = "请选择一个国家查看外交操作"
	else:
		%Selection.text = "当前目标：%s（%s）" % [
			_country_name(_selected_country_id), _relation_label(_selected_country_id),
		]


func _refresh_selection_state() -> void:
	var has_target := not _selected_country_id.is_empty()
	var at_war := has_target and _is_at_war(_selected_country_id)
	var declare_war := $Content/Actions/DeclareWar as Button
	var make_peace := $Content/Actions/MakePeace as Button
	declare_war.disabled = not has_target or at_war
	make_peace.disabled = not has_target or not at_war
	$Content/Actions/AnnexOccupied.disabled = not has_target or not at_war
	if not has_target:
		declare_war.tooltip_text = SELECT_TARGET_TOOLTIP
		make_peace.tooltip_text = SELECT_TARGET_TOOLTIP
	elif at_war:
		declare_war.tooltip_text = ALREADY_AT_WAR_TOOLTIP
		make_peace.tooltip_text = MAKE_PEACE_TOOLTIP
	else:
		declare_war.tooltip_text = DECLARE_WAR_TOOLTIP
		make_peace.tooltip_text = NOT_AT_WAR_TOOLTIP


func _on_declare_war_pressed() -> void:
	if not _selected_country_id.is_empty():
		declare_war_requested.emit(_selected_country_id)


func _on_make_peace_pressed() -> void:
	if not _selected_country_id.is_empty():
		make_peace_requested.emit(
			_selected_country_id,
			$Content/Actions/AnnexOccupied.button_pressed
		)


func _is_at_war(country_id: String) -> bool:
	for war: Dictionary in _wars:
		var first := String(war.get("country_a", war.get("aggressor_id", "")))
		var second := String(war.get("country_b", war.get("defender_id", "")))
		if (first == _player_country_id and second == country_id) or \
				(first == country_id and second == _player_country_id):
			return true
	return false


func _relation_label(country_id: String) -> String:
	return "交战中" if _is_at_war(country_id) else "和平"


func _country_name(country_id: String) -> String:
	var country: Dictionary = _countries_by_id.get(country_id, {})
	var name := String(country.get("name", country.get("display_name", "")))
	return name if not name.is_empty() else "未知国家"
