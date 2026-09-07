class_name CountryOverviewPage
extends PanelContainer


func set_snapshot(country: Dictionary, totals: Dictionary) -> void:
	%Summary.text = "\n".join([
		"国库：%s" % _number(country.get("treasury", 0)),
		"总人口：%s" % _number(totals.get("population", 0)),
		"可招募士兵：%s" % _number(totals.get("recruitable_population", 0)),
		"控制地区：%s" % _number(totals.get("controlled_provinces", 0)),
		"科技等级",
		"经济 %s" % _number(country.get("economy_level", 0)),
		"军事 %s" % _number(country.get("military_level", 0)),
		"道路 %s" % _number(country.get("roads_level", 0)),
	])


func _number(value: Variant) -> String:
	var number := int(value)
	var digits := str(absi(number))
	var result := ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if number < 0 else "") + digits + result
