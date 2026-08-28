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
			"display_name": "\u5965\u00b7\u7b2c1\u519b",
			"remaining_manpower": 420, "destroyed": false,
			"retreat_province": "capital_auroria",
		}],
	}
	var provinces := {"capital_auroria": {"name": "奥罗里亚首都"}}
	var report := GameText.battle_report(battle, provinces)
	if not _assert_fragments(report, "Detailed battle report"):
		return
	var action_report := GameText.battle_action_report(battle, provinces)
	if not _assert_fragments(action_report, "Detailed turn battle report"):
		return
	var visible_name := "\u5965\u00b7\u7b2c1\u519b"
	if report.find(visible_name) == -1 or report.find("army_1") != -1:
		_fail("Immediate battle report did not prefer the visible army name")
		return
	if action_report.find(visible_name) == -1 or action_report.find("army_1") != -1:
		_fail("Turn battle report did not prefer the visible army name")
		return

	var joint_battle: Dictionary = battle.duplicate(true)
	joint_battle["order_ids"] = ["order_4", "order_7"]
	if GameText.battle_action_report(joint_battle, provinces).find("联合战斗") == -1:
		_fail("Grouped monthly battle was not identified as a joint battle")
		return

	var recruitment_order := {
		"type": "recruitment",
		"province_id": "capital_auroria",
		"manpower": 100,
		"paid_cost": 400,
		"remaining_months": 1,
		"status": "pending",
	}
	var recruitment_text := GameText.pending_order_text(recruitment_order, provinces)
	for fragment: String in ["征兵", "奥罗里亚首都", "剩余1个月", "预付400", "预留兵员100", "待执行"]:
		if recruitment_text.find(fragment) == -1:
			_fail("Recruitment pending order omitted %s" % fragment)
			return

	var movement_text := GameText.pending_order_text({
		"type": "army_action",
		"destination": "capital_auroria",
		"is_attack": true,
		"reserved_movement_half": 7,
		"remaining_months": 1,
		"status": "pending",
	}, provinces)
	for fragment: String in ["进攻", "奥罗里亚首都", "预留移动3.5", "待执行"]:
		if movement_text.find(fragment) == -1:
			_fail("Army pending order omitted %s" % fragment)
			return

	var failed_text := GameText.turn_action_report({
		"type": "order_cancelled",
		"order_id": "order_9",
		"reason": "path no longer legal",
		"refunded_cost": 400,
		"refunded_movement_half": 4,
	}, provinces)
	for fragment: String in ["订单失败", "原因", "路径已不再合法", "退款400", "退还移动2"]:
		if failed_text.find(fragment) == -1:
			_fail("Failed order report omitted %s" % fragment)
			return

	var merged_text := GameText.turn_action_report({
		"type": "armies_merged",
		"automatic": true,
		"display_name": "奥·第1军",
		"merged_army_ids": ["army_2"],
		"current_manpower": 1400,
	}, provinces)
	if merged_text.find("自动整编") == -1 or merged_text.find("1400") == -1:
		_fail("Automatic consolidation report was incomplete")
		return

	for completion: Dictionary in [
		{"type": "army_recruited", "province_id": "capital_auroria", "manpower": 100},
		{"type": "road_built", "province_a": "capital_auroria", "province_b": "capital_auroria"},
		{"type": "technology_researched", "track": "economy", "current_level": 1},
	]:
		if GameText.turn_action_report(completion, provinces).find("完成") == -1:
			_fail("Project completion report omitted completion state")
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
		if GameText.battle_action_report(labeled_battle, provinces).find(expected["label"]) == -1:
			_fail("Turn battle result %s did not render as %s" % [
				expected["result"], expected["label"],
			])
			return

	var unopposed := {"battle_occurred": false, "province_occupied": true}
	if GameText.battle_report(unopposed, provinces) != "地区在无抵抗情况下被占领":
		_fail("Unopposed occupation report changed")
		return

	print("GameTextFormatter detailed battle report smoke test passed")
	quit(0)
