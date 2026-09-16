extends SceneTree


func _fail(host: Node, message: String) -> void:
	push_error(message)
	if is_instance_valid(host):
		host.free()
	quit(1)


func _initialize() -> void:
	var host_scene := load("res://scenes/ui/management_page_host.tscn") as PackedScene
	if host_scene == null:
		_fail(null, "Management page host scene could not be loaded")
		return
	var host := host_scene.instantiate()
	root.add_child(host)
	await process_frame
	var observed := {"back_requested": false}
	host.back_requested.connect(func() -> void: observed["back_requested"] = true)

	host.open_page("country")
	if host.current_page() != "country" or not host.get_node("Pages/Country").visible or \
			host.get_node("Pages/Military").visible or host.get_node("Pages/Economy").visible or \
			not host.get_node("Pages/Header").visible or not host.get_node("Pages/Header/Back").visible:
		_fail(host, "Country page did not open exclusively")
		return
	host.open_page("not_a_page")
	if host.current_page() != "country":
		_fail(host, "Unknown page ID changed the current page")
		return

	var country := {
		"name": "奥罗里亚", "treasury": 10300,
		"economy_level": 2, "military_level": 1, "roads_level": 3,
	}
	var countries := [
		{"id": "auroria", "name": "奥罗里亚", "treasury": 10300},
		{"id": "solmere", "name": "索尔梅尔", "treasury": 8200},
	]
	var totals := {
		"population": 860000, "recruitable_population": 42000,
		"controlled_provinces": 6,
	}
	host.get_node("Pages/Country").set_snapshot(country, totals)
	var country_text := host.get_node("Pages/Country/Content/Summary") as Label
	if not country_text.text.contains("10,300") or not country_text.text.contains("860,000") or \
			not country_text.text.contains("42,000") or not country_text.text.contains("6") or \
			not country_text.text.contains("经济 2") or not country_text.text.contains("军事 1") or \
			not country_text.text.contains("道路 3"):
		_fail(host, "Country page did not render supplied authoritative totals")
		return

	host.get_node("Pages/Military").set_snapshot([{
		"id": "army_raw_1", "name": "第一军", "soldiers": 1200,
		"province_name": "北境", "status": "驻防",
	}], [{
		"order_id": "order_raw_1", "name": "北境征募", "status": "剩余 1 回合",
	}])
	var army_text := host.get_node("Pages/Military/Content/Armies/Rows/Army0") as Label
	var order_text := host.get_node("Pages/Military/Content/Orders/Rows/Order0") as Label
	if not army_text.text.contains("第一军") or not army_text.text.contains("北境") or \
			not order_text.text.contains("北境征募") or army_text.text.contains("army_raw_1") or \
			order_text.text.contains("order_raw_1"):
		_fail(host, "Military page did not use supplied display names safely")
		return

	host.get_node("Pages/Economy").set_snapshot(
		{
			"treasury": 10300, "fiscal_income": 3150,
			"last_maintenance_charge": 500, "has_last_maintenance_charge": true,
		},
		[{"name": "北境", "fiscal_income": 1200}, {"name": "西境", "fiscal_income": 900}]
	)
	host.open_page("economy")
	var net_income := host.get_node("Pages/Economy/Content/NetIncome") as Label
	var first_province := host.get_node("Pages/Economy/Content/Provinces/Rows/Province0") as Label
	if not net_income.text.contains("2650") or not first_province.text.contains("北境"):
		_fail(host, "Economic page did not derive display totals from the supplied snapshot")
		return
	host.get_node("Pages/Economy").set_snapshot(
		{"fiscal_income": 3150, "last_maintenance_charge": 0,
		 "has_last_maintenance_charge": false}, []
	)
	if not net_income.text.contains("上月维护：暂无记录") or \
			not net_income.text.contains("净收入：暂无记录"):
		_fail(host, "Economic page invented a maintenance value when no record exists")
		return
	for scroll_path: String in [
		"Pages/Country/Content", "Pages/Military/Content/Armies",
		"Pages/Military/Content/Orders", "Pages/Economy/Content/Provinces",
	]:
		if not host.get_node(scroll_path) is ScrollContainer:
			_fail(host, "Management page content is not scrollable: %s" % scroll_path)
			return

	var diplomacy := host.get_node_or_null("Pages/Diplomacy")
	if diplomacy == null:
		_fail(host, "Diplomacy page is missing")
		return
	var diplomacy_observed := {"declared_target": "", "peace_target": "", "peace_annex": false}
	diplomacy.declare_war_requested.connect(func(country_id: String) -> void:
		diplomacy_observed["declared_target"] = country_id
	)
	diplomacy.make_peace_requested.connect(func(country_id: String, annex_occupied: bool) -> void:
		diplomacy_observed["peace_target"] = country_id
		diplomacy_observed["peace_annex"] = annex_occupied
	)
	var declare_war := diplomacy.get_node("Content/Actions/DeclareWar") as Button
	var make_peace := diplomacy.get_node("Content/Actions/MakePeace") as Button
	if not declare_war.disabled or not make_peace.disabled or \
			not declare_war.tooltip_text.contains("当前不可用") or \
			not declare_war.tooltip_text.contains("选择外交目标") or \
			not make_peace.tooltip_text.contains("当前不可用") or \
			not make_peace.tooltip_text.contains("选择外交目标"):
		_fail(host, "Diplomacy actions lacked specific reasons without a selected target")
		return
	diplomacy.set_snapshot("auroria", countries, [])
	if not declare_war.disabled or not make_peace.disabled or \
			not declare_war.tooltip_text.contains("选择外交目标") or \
			not make_peace.tooltip_text.contains("选择外交目标"):
		_fail(host, "Diplomacy snapshot lost the no-target action reasons")
		return
	var diplomacy_rows := diplomacy.get_node("Content/Countries/Rows") as VBoxContainer
	if diplomacy_rows == null or diplomacy_rows.get_child_count() == 0 or \
		diplomacy_rows.get_child(0).text.contains("solmere"):
		_fail(host, "Diplomacy page exposed a stable country ID")
		return
	var peaceful_country_button := diplomacy_rows.get_node("Country0") as Button
	if peaceful_country_button == null:
		_fail(host, "Diplomacy page did not create the expected country button")
		return
	peaceful_country_button.pressed.emit()
	if declare_war.disabled or not make_peace.disabled or \
			declare_war.tooltip_text != "向当前选择的国家发出宣战意图" or \
			declare_war.tooltip_text.contains("当前不可用") or \
			not make_peace.tooltip_text.contains("当前不可用") or \
			not make_peace.tooltip_text.contains("未与我国交战"):
		_fail(host, "Diplomacy actions did not explain a selected peaceful target")
		return
	diplomacy.get_node("Content/Actions/DeclareWar").pressed.emit()
	if diplomacy_observed["declared_target"] != "solmere":
		_fail(host, "Diplomacy page did not emit the selected stable country ID")
		return
	diplomacy.set_snapshot("auroria", countries, [{"country_a": "auroria", "country_b": "solmere"}])
	diplomacy_rows = diplomacy.get_node("Content/Countries/Rows") as VBoxContainer
	var war_country_button := diplomacy_rows.get_node("Country0") as Button
	if war_country_button == null:
		_fail(host, "Diplomacy page did not recreate the expected country button")
		return
	war_country_button.pressed.emit()
	if not declare_war.disabled or make_peace.disabled or \
			not declare_war.tooltip_text.contains("当前不可用") or \
			not declare_war.tooltip_text.contains("已与我国交战") or \
			make_peace.tooltip_text != "向当前选择的国家发出议和意图" or \
			make_peace.tooltip_text.contains("当前不可用"):
		_fail(host, "Diplomacy actions did not explain a selected wartime target")
		return
	diplomacy.get_node("Content/Actions/AnnexOccupied").button_pressed = true
	diplomacy.get_node("Content/Actions/MakePeace").pressed.emit()
	if diplomacy_observed["peace_target"] != "solmere" or not diplomacy_observed["peace_annex"]:
		_fail(host, "Diplomacy page did not emit the selected peace intent")
		return

	var technology := host.get_node_or_null("Pages/Technology")
	if technology == null:
		_fail(host, "Technology page is missing")
		return
	for track: String in ["Economy", "Military", "Roads"]:
		if not (technology.get_node("Content/Tracks/%s/Research" % track) as Button).disabled:
			_fail(host, "Technology page enabled %s research before receiving a snapshot" % track)
			return
	var technology_observed := {"requested_track": ""}
	technology.research_requested.connect(func(track: String) -> void:
		technology_observed["requested_track"] = track
	)
	technology.set_snapshot({
		"economy_level": 0, "economy_cost": 5000, "economy_max": false,
		"military_level": 0, "military_cost": 5000, "military_max": false,
		"roads_level": 0, "roads_cost": 5000, "roads_max": false,
	}, [], 10000)
	var economy_research := technology.get_node("Content/Tracks/Economy/Research") as Button
	if economy_research == null or economy_research.disabled or economy_research.text != "研究（5000）":
		_fail(host, "Technology page ignored its authoritative affordability snapshot")
		return
	economy_research.pressed.emit()
	if technology_observed["requested_track"] != "economy":
		_fail(host, "Technology page did not emit the selected research track")
		return
	technology.set_snapshot({
		"economy_level": 3, "economy_cost": 99999, "economy_max": true,
		"military_level": 0, "military_cost": 5000, "military_max": false,
		"roads_level": 0, "roads_cost": 5000, "roads_max": false,
	}, [{"type": "research"}], 10000)
	if not economy_research.disabled or economy_research.text != "已达最高等级":
		_fail(host, "Technology page did not honor the authoritative maximum state")
		return
	if not (technology.get_node("Content/Tracks/Military/Research") as Button).disabled:
		_fail(host, "Technology page allowed a second research while a pending order exists")
		return

	var settings := host.get_node_or_null("Pages/Settings")
	if settings == null:
		_fail(host, "Settings page is missing")
		return
	var settings_observed := {"save_requested": false, "load_requested": false}
	settings.quick_save_requested.connect(func() -> void: settings_observed["save_requested"] = true)
	settings.quick_load_requested.connect(func() -> void: settings_observed["load_requested"] = true)
	settings.set_build_info("v0.1.0", 3)
	var build_info := settings.get_node("Content/BuildInfo") as Label
	if build_info == null or not build_info.text.contains("v0.1.0") or not build_info.text.contains("3"):
		_fail(host, "Settings page did not render supplied build information")
		return
	settings.get_node("Content/Actions/QuickSave").pressed.emit()
	settings.get_node("Content/Actions/QuickLoad").pressed.emit()
	if not settings_observed["save_requested"] or not settings_observed["load_requested"]:
		_fail(host, "Settings page did not emit save and load intents")
		return
	host.get_node("Pages/Header/Back").pressed.emit()
	if not observed["back_requested"] or host.current_page() != "closed" or host.visible:
		_fail(host, "Management page host did not close and request navigation back")
		return
	print("Management pages smoke test passed")
	host.free()
	quit(0)
