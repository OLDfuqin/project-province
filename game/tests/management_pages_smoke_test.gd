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
		{"treasury": 10300, "fiscal_income": 3150, "last_maintenance_charge": 500},
		[{"name": "北境", "fiscal_income": 1200}, {"name": "西境", "fiscal_income": 900}]
	)
	host.open_page("economy")
	var net_income := host.get_node("Pages/Economy/Content/NetIncome") as Label
	var first_province := host.get_node("Pages/Economy/Content/Provinces/Rows/Province0") as Label
	if not net_income.text.contains("2650") or not first_province.text.contains("北境"):
		_fail(host, "Economic page did not derive display totals from the supplied snapshot")
		return
	for scroll_path: String in [
		"Pages/Country/Content", "Pages/Military/Content/Armies",
		"Pages/Military/Content/Orders", "Pages/Economy/Content/Provinces",
	]:
		if not host.get_node(scroll_path) is ScrollContainer:
			_fail(host, "Management page content is not scrollable: %s" % scroll_path)
			return
	host.get_node("Pages/Header/Back").pressed.emit()
	if not observed["back_requested"] or host.current_page() != "closed" or host.visible:
		_fail(host, "Management page host did not close and request navigation back")
		return
	print("Management pages smoke test passed")
	host.free()
	quit(0)
