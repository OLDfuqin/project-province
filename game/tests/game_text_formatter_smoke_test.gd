extends SceneTree


const GameText = preload("res://scripts/ui/game_text_formatter.gd")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _assert_fragments(report: String, report_name: String) -> bool:
	for fragment: String in [
		"随机系数", "参战兵力", "军事等级", "有效战力",
		"地形防御", "伤亡", "剩余兵力",
	]:
		if report.find(fragment) == -1:
			_fail("%s is missing %s" % [report_name, fragment])
			return false
	return true


func _initialize() -> void:
	var battle := {
		"battle_occurred": true,
		"province_occupied": false,
		"battle_result": "defender_victory",
		"attacker_random_x": 0.9,
		"defender_random_x": 1.1,
		"attacker_initial_manpower": 1000,
		"defender_initial_manpower": 800,
		"attacker_military_level": 2,
		"defender_military_level": 1,
		"attacker_base_strength": 1080,
		"defender_base_strength": 968,
		"defender_final_strength": 1161,
		"terrain_defense_bonus": 20,
		"attacker_casualties": 580,
		"defender_casualties": 540,
		"attacker_remaining_manpower": 420,
		"defender_remaining_manpower": 260,
		"battle_outcomes": [{
			"army_id": "army_1", "casualties": 580,
			"remaining_manpower": 420, "destroyed": false,
			"retreat_province": "northreach",
		}],
	}
	var provinces := {"northreach": {"name": "北境"}}
	var report := GameText.battle_report(battle, provinces)
	if not _assert_fragments(report, "Detailed battle report"):
		return
	var action_report := GameText.battle_action_report(battle, provinces)
	if not _assert_fragments(action_report, "Detailed turn battle report"):
		return

	for expected: Dictionary in [
		{"result": "defender_victory", "label": "防守方胜利"},
		{"result": "attacker_victory", "label": "进攻方胜利"},
		{"result": "mutual_destruction", "label": "双方同归于尽"},
	]:
		var labeled_battle: Dictionary = battle.duplicate(true)
		labeled_battle["battle_result"] = expected["result"]
		if GameText.battle_report(labeled_battle, provinces).find(expected["label"]) == -1:
			_fail("Battle result %s did not render as %s" % [
				expected["result"], expected["label"],
			])
			return

	var unopposed := {"battle_occurred": false, "province_occupied": true}
	if GameText.battle_report(unopposed, provinces) != "地区在无抵抗情况下被占领":
		_fail("Unopposed occupation report changed")
		return

	print("GameTextFormatter detailed battle report smoke test passed")
	quit(0)
