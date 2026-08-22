# Combat Resolution Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current deterministic combat rule with independently randomized effective strength, half-strength casualties, last-stand defense, mutual destruction, deterministic proportional defender losses, and detailed Chinese battle reports.

**Architecture:** Add a pure `BattleCalculator` that accepts already-collected combat data and explicit random rolls, then returns a complete immutable calculation. Keep `BattleSystem` responsible for reading and mutating `GameState`; inject a roll callback so production uses system entropy while tests use fixed rolls. Extend `BattleResolution` and the Godot bridge without persisting RNG state or changing the save schema.

**Tech Stack:** C++20 simulation core, SCons/MSVC, Godot 4.6 GDExtension, GDScript smoke tests, Markdown rules documentation.

**Spec:** `docs/superpowers/specs/2026-08-22-combat-resolution-redesign.md`

## Global Constraints

- Production rolls are independent discrete values in `{0.7, 0.8, ..., 1.4}` and are not persisted.
- The attacking side contains only the moving army; the defending side aggregates every hostile army in the destination province.
- Multi-country defender military level is manpower-weighted and floored.
- Defender terrain bonuses remain plains `0%`, forest `10%`, hills `20%`, mountains `30%` and apply after base effective strength.
- Casualties equal half of opposing effective strength, floored, with a minimum of one and a maximum of own pre-battle manpower.
- A surviving defender always wins and never retreats; a surviving attacker occupies only when every defender is destroyed; mutual destruction leaves control unchanged.
- Defender casualty allocation must exactly equal the defender casualty total and use stable Army ID ordering to break equal remainders.
- No RNG seed or state enters saves; the save schema remains version 5.
- Preserve unrelated local changes in `game/scripts/main.gd` and `game/tests/army_bridge_smoke_test.gd`; execute in an isolated worktree and integrate only reviewed commits.

---

### Task 1: Pure battle calculation and fixed-roll unit coverage

**Files:**
- Create: `core/include/province/core/battle_calculator.hpp`
- Create: `core/src/battle_calculator.cpp`
- Create: `tests/core/battle_calculator_test.cpp`
- Modify: `tests/core/smoke_test_groups.hpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Produces: `BattleCalculator::calculate(const BattleCalculationInput&) -> BattleCalculation`
- Produces: `BattleResultType::{defender_victory, attacker_victory, mutual_destruction}`
- Produces: `DefenderBattleInput`, `DefenderBattleLoss`, `BattleCalculationInput`, and `BattleCalculation`
- Consumes later: Task 2 passes explicit random tenths and applies the returned per-army losses.

- [ ] **Step 1: Create the failing calculator test group**

Add `run_battle_calculator_tests()` to `smoke_test_groups.hpp`, call it near the start of `main()`, and create `battle_calculator_test.cpp`. Use a small assertion helper and explicit tenths values rather than any RNG. Include these exact cases:

```cpp
using province::core::ArmyId;
using province::core::BattleCalculationInput;
using province::core::BattleCalculator;
using province::core::BattleResultType;
using province::core::CountryId;
using province::core::DefenderBattleInput;

const BattleCalculation equal = BattleCalculator::calculate({
    1'000, 0,
    {{ArmyId{"defender"}, CountryId{"solmere"}, 1'000, 0}},
    0, 7, 14,
});
// Attacker strength 700; defender strength 1400.
// Attacker loses 700 and defender loses 350: defender survives and wins.

const BattleCalculation larger_attacker = BattleCalculator::calculate({
    4'000, 2,
    {{ArmyId{"defender"}, CountryId{"solmere"}, 1'000, 0}},
    0, 10, 10,
});
// Attacker strength floor(1000 * sqrt(4) * 1.2) = 2400.
// Defender strength 1000, so defender is destroyed and attacker survives.

const BattleCalculation mountain = BattleCalculator::calculate({
    1'000, 0,
    {{ArmyId{"defender"}, CountryId{"solmere"}, 1'000, 0}},
    30, 10, 10,
});
// Defender base strength 1000 and final terrain strength 1300.

const BattleCalculation weighted = BattleCalculator::calculate({
    2'000, 0,
    {
        {ArmyId{"d1"}, CountryId{"solmere"}, 300, 2},
        {ArmyId{"d2"}, CountryId{"verdantia"}, 700, 5},
    },
    0, 10, 10,
});
// floor((300*2 + 700*5)/1000) = 4.

const BattleCalculation remainders = BattleCalculator::calculate({
    7, 0,
    {
        {ArmyId{"army_b"}, CountryId{"solmere"}, 1, 0},
        {ArmyId{"army_a"}, CountryId{"solmere"}, 1, 0},
        {ArmyId{"army_c"}, CountryId{"solmere"}, 1, 0},
    },
    0, 10, 10,
});
// Attacker strength floor(3*sqrt(7/3)) = 4; defender losses = 2.
// Equal remainders award losses to army_a then army_b by stable ID.
```

Add this exact mutual-destruction case; minimum-one casualties delete both one-person forces even though both floored strengths are zero:

```cpp
const BattleCalculation mutual = BattleCalculator::calculate({
    1, 0,
    {{ArmyId{"defender"}, CountryId{"solmere"}, 1, 0}},
    0, 7, 7,
});
if (mutual.result != BattleResultType::mutual_destruction ||
    mutual.attacker_remaining_manpower != 0 ||
    mutual.defender_remaining_manpower != 0) return false;
```

Use a small `expect_invalid(const BattleCalculationInput&)` helper that returns true only when `BattleCalculator::calculate` throws `std::invalid_argument`. Call it with five copied valid inputs changed respectively to attacker manpower `0`, an empty defender vector, attacker roll `6`, defender roll `15`, and terrain bonus `-1`. Loop over `{0, 10, 20, 30}` and assert `defender_final_strength == floor(defender_base_strength * (100 + bonus) / 100)`. Finally calculate `1'000'000'000'000` against the same manpower at rolls `14/14` and military level `8`, asserting positive strengths and nonnegative remaining manpower.

- [ ] **Step 2: Run the core test target and verify compilation fails**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q build\bin\province_core_tests.exe
```

Expected: FAIL because `province/core/battle_calculator.hpp` and its types do not exist.

- [ ] **Step 3: Define the calculator data contract**

Create `battle_calculator.hpp` with focused value types:

```cpp
enum class BattleResultType : std::uint8_t {
    defender_victory,
    attacker_victory,
    mutual_destruction,
};

struct DefenderBattleInput final {
    ArmyId army_id;
    CountryId country_id;
    std::int64_t manpower{};
    std::int32_t military_level{};
};

struct DefenderBattleLoss final {
    ArmyId army_id;
    std::int64_t casualties{};
    std::int64_t remaining_manpower{};
};

struct BattleCalculationInput final {
    std::int64_t attacker_manpower{};
    std::int32_t attacker_military_level{};
    std::vector<DefenderBattleInput> defenders;
    std::int32_t terrain_defense_bonus{};
    std::int32_t attacker_random_tenths{};
    std::int32_t defender_random_tenths{};
};

struct BattleCalculation final {
    BattleResultType result{BattleResultType::defender_victory};
    std::int32_t attacker_random_tenths{};
    std::int32_t defender_random_tenths{};
    std::int64_t attacker_initial_manpower{};
    std::int64_t defender_initial_manpower{};
    std::int32_t attacker_military_level{};
    std::int32_t defender_military_level{};
    std::int32_t terrain_defense_bonus{};
    std::int64_t attacker_base_strength{};
    std::int64_t defender_base_strength{};
    std::int64_t defender_final_strength{};
    std::int64_t attacker_casualties{};
    std::int64_t defender_casualties{};
    std::int64_t attacker_remaining_manpower{};
    std::int64_t defender_remaining_manpower{};
    std::vector<DefenderBattleLoss> defender_losses;
};

class BattleCalculator final {
public:
    [[nodiscard]] static BattleCalculation calculate(
        const BattleCalculationInput& input
    );
};
```

- [ ] **Step 4: Implement validation, strength, casualties, and largest-remainder allocation**

In `battle_calculator.cpp`:

- validate positive manpower, nonempty unique defender IDs, military levels `0..8`, rolls `7..14`, and terrain bonus in `{0,10,20,30}`;
- sum defender manpower with checked `int64_t` addition;
- compute weighted defender military level with `long double` accumulation and `floor`;
- compute strengths in `long double`, apply one final `floor`, and reject a result above `int64_t` maximum;
- compute casualties with the exact `min(manpower, max(1, strength / 2))` formula;
- allocate defender casualties from integer quotients and remainders using integer arithmetic where safe, sorting equal remainders by `ArmyId`;
- derive `BattleResultType` only from post-casualty manpower.

Keep helper functions private in the `.cpp`, for example:

```cpp
std::int64_t effective_strength(
    std::int64_t lesser,
    std::int64_t greater,
    bool is_greater_side,
    std::int32_t random_tenths,
    std::int32_t military_level
);
```

- [ ] **Step 5: Run core tests and verify the calculator cases pass**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q build\bin\province_core_tests.exe
.\build\bin\province_core_tests.exe
```

Expected: build succeeds and ends with `Project Province core 0.1.0-dev smoke test passed`.

- [ ] **Step 6: Commit the pure calculator**

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/battle_calculator.hpp core/src/battle_calculator.cpp tests/core/battle_calculator_test.cpp tests/core/smoke_test_groups.hpp tests/core/core_smoke_test.cpp
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: add randomized battle calculator"
```

---

### Task 2: Apply calculations to armies, retreat, destruction, and occupation

**Files:**
- Modify: `core/include/province/core/battle_system.hpp`
- Modify: `core/src/battle_system.cpp`
- Modify: `core/include/province/core/command_processor.hpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Consumes: `BattleCalculator::calculate(const BattleCalculationInput&)`
- Produces: `BattleSystem::RandomRoll = std::function<std::int32_t()>`
- Produces: `CommandProcessor(BattleSystem::RandomRoll)` for fixed-roll integration tests.
- Produces: enriched `BattleResolution` containing `BattleResultType result` and all aggregate calculation fields.

- [ ] **Step 1: Replace deterministic battle assertions with fixed-roll state-transition tests**

Construct processors with a sequence callback that returns one attacker roll and one defender roll per actual battle:

```cpp
auto fixed_rolls(std::initializer_list<std::int32_t> values) {
    auto rolls = std::make_shared<std::vector<std::int32_t>>(values);
    auto index = std::make_shared<std::size_t>(0);
    return [rolls, index]() mutable -> std::int32_t {
        if (*index >= rolls->size()) throw std::logic_error{"missing fixed battle roll"};
        return (*rolls)[(*index)++];
    };
}

CommandProcessor processor{fixed_rolls({10, 10})};
```

Add integration scenarios that assert:

1. A surviving defender remains in the target province and a surviving attacker returns to its origin.
2. All defenders reaching zero are deleted; a surviving attacker remains in the target and occupies it.
3. Mutual destruction deletes both sides and preserves the original controller.
4. Multiple defenders receive the exact losses from the calculator and never move to a neighboring province.
5. An undefended hostile province is occupied without consuming either random callback value.

- [ ] **Step 2: Run core tests and verify old battle behavior fails**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q build\bin\province_core_tests.exe
.\build\bin\province_core_tests.exe
```

Expected: FAIL because `CommandProcessor(BattleSystem::RandomRoll)`, the new result enum, and last-stand behavior are absent.

- [ ] **Step 3: Add injectable battle rolls and enriched resolution fields**

In `battle_system.hpp`, include the calculator and define:

```cpp
using RandomRoll = std::function<std::int32_t()>;

explicit BattleSystem(RandomRoll random_roll = {});
```

Extend `BattleResolution` with:

```cpp
BattleResultType result{BattleResultType::defender_victory};
std::int32_t attacker_random_tenths{};
std::int32_t defender_random_tenths{};
std::int64_t attacker_initial_manpower{};
std::int64_t defender_initial_manpower{};
std::int32_t attacker_military_level{};
std::int32_t defender_military_level{};
std::int32_t terrain_defense_bonus{};
std::int64_t attacker_base_strength{};
std::int64_t defender_base_strength{};
std::int64_t defender_final_strength{};
std::int64_t attacker_casualties{};
std::int64_t defender_casualties{};
std::int64_t attacker_remaining_manpower{};
std::int64_t defender_remaining_manpower{};
```

Retain `attacker_won` as a compatibility convenience and set it true only for `attacker_victory`; mutual destruction must therefore have `attacker_won == false` and a distinct result enum.

Add an explicit `CommandProcessor(BattleSystem::RandomRoll)` constructor while preserving the existing default constructor used by production and other tests.

- [ ] **Step 4: Replace old combat mutation with calculator application**

In `battle_system.cpp`:

- default `RandomRoll` uses a process-local engine seeded from `std::random_device` and `std::uniform_int_distribution<std::int32_t>{7, 14}`;
- collect defender inputs in stable army ID order and compute each country's military level from `GameState`;
- call the roller exactly twice only when defenders exist;
- invoke `BattleCalculator::calculate`;
- apply every returned loss before deciding movement and occupation;
- remove zero-manpower armies;
- on `defender_victory`, return a surviving attacker to `attacker_origin` and leave defenders in place;
- on `attacker_victory`, occupy only if the attacker still exists;
- on `mutual_destruction`, leave occupation unchanged;
- delete `find_retreat_province` and all defender-retreat searches.

Build `ArmyBattleOutcome` entries from calculator output so each entry retains casualties, remaining manpower, destroyed state, and only the surviving losing attacker has `retreat_province = attacker_origin`.

- [ ] **Step 5: Run core tests and verify every state transition passes**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q build\bin\province_core_tests.exe
.\build\bin\province_core_tests.exe
```

Expected: all calculator and integration cases pass with the core smoke-test success line.

- [ ] **Step 6: Commit state integration**

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/battle_system.hpp core/src/battle_system.cpp core/include/province/core/command_processor.hpp core/src/command_processor.cpp tests/core/core_smoke_test.cpp
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: apply last-stand battle outcomes"
```

---

### Task 3: Expose complete battle details through the GDExtension bridge

**Files:**
- Modify: `bridge/src/province_bridge.cpp`
- Modify: `game/tests/army_bridge_smoke_test.gd`

**Interfaces:**
- Consumes: enriched `BattleResolution` from Task 2.
- Produces: identical battle metadata keys in immediate `move_army()` responses and `advance_turn()` action dictionaries.

- [ ] **Step 1: Add bridge assertions for the enriched battle dictionary**

Update the army bridge test to validate both immediate and turn-action battle dictionaries contain:

```gdscript
var required := [
    "battle_result", "attacker_random_x", "defender_random_x",
    "attacker_initial_manpower", "defender_initial_manpower",
    "attacker_military_level", "defender_military_level",
    "attacker_base_strength", "defender_base_strength",
    "defender_final_strength", "terrain_defense_bonus",
    "attacker_casualties", "defender_casualties",
    "attacker_remaining_manpower", "defender_remaining_manpower",
]
for key: String in required:
    if not battle_dictionary.has(key):
        push_error("Battle dictionary is missing %s" % key)
        quit(1)
        return
```

Accept only `"defender_victory"`, `"attacker_victory"`, or `"mutual_destruction"`; assert both random values lie between `0.7` and `1.4` in `0.1` increments.

- [ ] **Step 2: Build and run the bridge test to verify missing fields fail**

Run:

```powershell
.\scripts\build.cmd
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe' --headless --path game --script res://tests/army_bridge_smoke_test.gd
```

Expected: the build succeeds and the Godot test fails on the first missing enriched field.

- [ ] **Step 3: Centralize bridge serialization of battle metadata**

Add private translation helpers near the existing bridge-local helper functions:

```cpp
godot::String battle_result_name(BattleResultType result);
double random_tenths_to_display(std::int32_t value);
void append_battle_metadata(godot::Dictionary& target, const BattleResolution& battle);
```

`battle_result_name` must map the three enum values to the exact strings asserted above. `append_battle_metadata` writes every aggregate field plus existing `battle_occurred`, `attacker_won`, and `province_occupied`. Call the same helper from the immediate movement response and the turn-action response to prevent schema drift.

Keep `battle_outcomes` unchanged except for continuing to expose each army's `army_id`, casualties, remaining manpower, destroyed flag, and retreat province.

- [ ] **Step 4: Rebuild and verify the bridge schema**

Run the build and army bridge test commands from Step 2.

Expected: PASS with no missing fields and valid discrete random values.

- [ ] **Step 5: Commit bridge exposure**

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add bridge/src/province_bridge.cpp game/tests/army_bridge_smoke_test.gd
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: expose detailed battle calculations"
```

---

### Task 4: Render Chinese detailed battle reports and draw outcomes

**Files:**
- Modify: `game/scripts/ui/game_text_formatter.gd`
- Create: `game/tests/game_text_formatter_smoke_test.gd`

**Interfaces:**
- Consumes: bridge keys from Task 3.
- Produces: `GameTextFormatter.battle_result_name(String) -> String`
- Produces: immediate and turn-action Chinese reports with the same calculation summary.

- [ ] **Step 1: Add a failing formatter smoke test**

Create `game_text_formatter_smoke_test.gd`, preload `res://scripts/ui/game_text_formatter.gd`, and construct this complete fixed dictionary:

```gdscript
extends SceneTree

const GameText = preload("res://scripts/ui/game_text_formatter.gd")

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
    var report := GameText.battle_report(
        battle,
        {"northreach": {"name": "北境"}}
    )
```

Assert the returned immediate report and `battle_action_report()` output contain these stable labels:

```gdscript
for fragment: String in [
        "随机系数", "参战兵力", "军事等级", "有效战力",
        "地形防御", "伤亡", "剩余兵力"]:
    if report.find(fragment) == -1:
        push_error("Detailed battle report is missing %s" % fragment)
        quit(1)
        return
```

Copy the dictionary and set `battle_result` to each of `defender_victory`, `attacker_victory`, and `mutual_destruction`; assert their Chinese labels are respectively `防守方胜利`, `进攻方胜利`, and `双方同归于尽`. Also call `battle_report()` with `{"battle_occurred": false, "province_occupied": true}` and assert it remains `地区在无抵抗情况下被占领`.

- [ ] **Step 2: Run the Godot tests and verify the old report fails**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe' --headless --path game --script res://tests/game_text_formatter_smoke_test.gd
```

Expected: FAIL because the old formatter only reports the `attacker_won` boolean and total casualties.

- [ ] **Step 3: Implement one shared detailed report formatter**

In `game_text_formatter.gd`, add:

```gdscript
static func battle_result_name(result: String) -> String:
    match result:
        "attacker_victory": return "进攻方胜利"
        "mutual_destruction": return "双方同归于尽"
        _: return "防守方胜利"
```

Create a private calculation-summary helper used by both `battle_report()` and `battle_action_report()`. Its output must show:

```text
进攻方：随机系数X0.9，参战兵力1000，军事等级2，基础有效战力...
防守方：随机系数X1.1，参战兵力800，军事等级1，基础有效战力...，地形防御20%，最终有效战力...
结算：进攻方伤亡...、剩余兵力...；防守方伤亡...、剩余兵力...
```

Append the existing per-army loss, destruction, and attacker-retreat details. Use `battle_result`, not `attacker_won`, to render mutual destruction. Do not edit `main.gd`: its existing `_battle_report()` and `_battle_action_report()` already delegate the complete dictionary to `GameTextFormatter`.

- [ ] **Step 4: Run the formatter test and verify Chinese reports pass**

Run the Godot command from Step 2.

Expected: PASS, including all three Chinese result labels and the no-resistance occupation case.

- [ ] **Step 5: Commit report rendering**

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add game/scripts/ui/game_text_formatter.gd game/tests/game_text_formatter_smoke_test.gd
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: show detailed Chinese battle reports"
```

---

### Task 5: Replace published rules and verify the complete game

**Files:**
- Modify: `docs/current-game-rules.md`
- Modify: `docs/project-structure.md`
- Modify: `docs/superpowers/plans/2026-08-22-combat-resolution-redesign.md`

**Interfaces:**
- Consumes: final calculator, state application, bridge fields, and UI behavior from Tasks 1-4.
- Produces: authoritative continuously maintained documentation matching the shipped rules.

- [ ] **Step 1: Rewrite the combat rules section**

Replace the existing deterministic combat section in `current-game-rules.md` with the approved spec's exact rules:

- discrete independent `X` rolls and non-persistence;
- total attacker/defender participation and weighted defender technology;
- lesser/larger force square-root formulas;
- terrain application order;
- half-effective-strength casualties;
- largest-remainder defender allocation;
- defender last stand, attacker retreat, attacker occupation, mutual destruction;
- removal of defender retreat.

Include at least one fully calculated numerical example with fixed `X` values and one multi-defender allocation example. Do not describe the old quarter-strength casualty or adjacent defender-retreat rules as current behavior.

- [ ] **Step 2: Update the project structure guide**

Add rows for:

```text
core/include/province/core/battle_calculator.hpp — pure combat input/output contract
core/src/battle_calculator.cpp — strength, casualty, result, and proportional allocation formulas
tests/core/battle_calculator_test.cpp — deterministic fixed-roll formula boundary tests
```

Update the `battle_system.*` row to say it collects state, obtains random rolls, applies calculation results, retreats only surviving attackers, destroys armies, and occupies provinces.

- [ ] **Step 3: Run formatting and stale-rule scans**

Run:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' diff --check
rg -n "确定性战斗|当前没有随机数|有效战力之和.*4|防守方战败后|find_retreat_province" core bridge game docs/current-game-rules.md docs/project-structure.md
```

Expected: `git diff --check` is silent. Search results contain no executable old rule or active documentation statement; historical design/plan files outside the listed paths are not rewritten.

- [ ] **Step 4: Run the complete verification suite**

Close any Godot editor instance using this worktree before building, then run:

```powershell
.\scripts\build.cmd
.\build\bin\province_core_tests.exe
$godot = 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
Get-ChildItem game\tests -Filter '*.gd' | Sort-Object Name | ForEach-Object {
    & $godot --headless --path game --script ("res://tests/" + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Godot test failed: $($_.Name)" }
}
& $godot --headless --path game --quit-after 2
```

Expected: SCons build passes, core smoke tests pass, every Godot script exits `0`, and main scene startup exits `0`. Resource-leak warnings at Godot process shutdown may be recorded but are not test failures when exit code remains `0`.

- [ ] **Step 5: Mark the plan complete and commit documentation**

Change every completed checkbox in this plan from `[ ]` to `[x]`, record any external verification limitation truthfully below the affected step, then commit:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add docs/current-game-rules.md docs/project-structure.md docs/superpowers/plans/2026-08-22-combat-resolution-redesign.md
& 'C:\Program Files\Git\cmd\git.exe' commit -m "docs: publish randomized combat rules"
```

- [ ] **Step 6: Review the final commit range without touching unrelated changes**

Run:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' status --short
& 'C:\Program Files\Git\cmd\git.exe' log --oneline --decorate -6
& 'C:\Program Files\Git\cmd\git.exe' diff --stat main...HEAD
```

Expected: the isolated worktree contains only the planned commits and is clean. Integrate by normal fast-forward or reviewed commit application; never reset, overwrite, or silently include the pre-existing local edits from the main worktree.
