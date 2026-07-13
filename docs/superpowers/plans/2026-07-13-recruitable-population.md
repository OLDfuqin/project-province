# Recruitable Population Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static soldier population with a monthly replenishing recruitable population capped at 10% of province population, and make recruitment remove the same number from both pools.

**Architecture:** Keep recruitable-population calculation inside `PopulationSystem`, immediately after the existing monthly total-population growth, so 1/3/6/12-month turns share the same sequential calculation. Perform a breaking rename through core state, scenario data, save data, bridge dictionaries, tests, and UI; recruitment remains transactional through the existing working-state command pattern.

**Tech Stack:** C++20 simulation core, nlohmann/json, SCons/MSVC, Godot 4.6.3 GDExtension, GDScript smoke tests.

## Global Constraints

- Use `recruitable_population` everywhere; do not retain or read `soldier_population`.
- Scenario schema version and save schema version both change from 1 to 2.
- Resolve each simulated month separately; never multiply a one-month result by the selected turn length.
- Resolve existing total-population growth before recruitable-population growth.
- Monthly candidate growth is `floor(population * 0.005)` with no fractional carry.
- Recruitable population must not grow beyond `floor(population * 0.10)` and is not forcibly reduced when already above the cap.
- Successful recruitment of `N` reduces both province population and recruitable population by `N`.
- Preserve unrelated Godot editor changes in `game/project.godot`, `game/scenes/main/main.tscn`, `.uid` files, and local logs.

---

## File Structure

- `core/include/province/core/province.hpp`: authoritative province state and new field name.
- `core/include/province/core/population_system.hpp`: monthly report fields and exact integer rate constants.
- `core/src/population_system.cpp`: total-population and recruitable-population monthly calculation.
- `core/src/command_processor.cpp`: aggregation of per-month recruitable-population changes.
- `core/src/army_system.cpp`: transactional recruitment validation and deductions.
- `core/src/scenario_loader.cpp`: scenario schema version 2 and required new JSON key.
- `core/include/province/core/save_game.hpp`, `core/src/save_game.cpp`: save schema version 2 and new persisted key.
- `core/src/game_state.cpp`, `core/src/ai_system.cpp`: invariant validation and AI recruitment availability.
- `bridge/src/province_bridge.cpp`: Godot-facing `recruitable_population` dictionary key.
- `game/data/*.json`: schema version 2; `provinces.json` contains only the new key.
- `game/scripts/main.gd`: UI dictionary reads and Chinese display text.
- `tests/core/core_smoke_test.cpp`: core, multi-month, cap, recruitment, and save regression coverage.
- `game/tests/army_bridge_smoke_test.gd`: bridge key and player-visible monthly behavior.

---

### Task 1: Perform the breaking field and schema migration

**Files:**
- Modify: `tests/core/core_smoke_test.cpp`
- Modify: `game/tests/army_bridge_smoke_test.gd`
- Modify: `core/include/province/core/province.hpp`
- Modify: `core/include/province/core/save_game.hpp`
- Modify: `core/src/scenario_loader.cpp`
- Modify: `core/src/save_game.cpp`
- Modify: `core/src/game_state.cpp`
- Modify: `core/src/ai_system.cpp`
- Modify: `core/src/army_system.cpp`
- Modify: `bridge/src/province_bridge.cpp`
- Modify: `game/data/countries.json`
- Modify: `game/data/provinces.json`
- Modify: `game/data/map_geometry.json`
- Modify: `game/data/technologies.json`

**Interfaces:**
- Produces: `Province::recruitable_population` as `std::int64_t`.
- Produces: bridge province summary key `recruitable_population` as an integer Variant.
- Produces: scenario and save `schema_version == 2`.
- Removes: every production and data reference to `soldier_population`.

- [ ] **Step 1: Change tests to demand the new field and bridge key**

In `tests/core/core_smoke_test.cpp`, replace state assertions such as:

```cpp
recruiting_province->recruitable_population != 1'000
```

In `game/tests/army_bridge_smoke_test.gd`, locate Northreach in `get_province_summaries()` and assert:

```gdscript
if not northreach.has("recruitable_population") or \
        northreach.has("soldier_population"):
    push_error("Province summary did not expose only recruitable_population")
    quit(1)
    return
```

- [ ] **Step 2: Run the build and observe the expected RED failure**

Run from the repository root:

```powershell
.\scripts\build.cmd
```

Expected: compilation fails because `Province` has no member named `recruitable_population`.

- [ ] **Step 3: Rename the core field and all direct consumers**

Change `Province` to:

```cpp
struct Province final {
    ProvinceId id;
    std::string name;
    CountryId owner_id;
    std::int64_t population{};
    std::int64_t recruitable_population{};
    std::int64_t economy{};
    std::vector<ProvinceId> neighbors;
    std::int64_t population_growth_remainder{};
    TerrainType terrain{TerrainType::plains};
};
```

Update the loader, serializer, validation, AI availability check, army availability check, and bridge output to use only `recruitable_population`. The bridge assignment must be:

```cpp
summary["recruitable_population"] = province.recruitable_population;
```

- [ ] **Step 4: Migrate schema versions and JSON keys**

Set:

```cpp
constexpr std::int32_t supported_schema_version = 2;
```

and:

```cpp
static constexpr std::int32_t schema_version = 2;
```

Change all four `game/data/*.json` documents from schema 1 to 2. In `provinces.json`, mechanically replace every `soldier_population` key with `recruitable_population` without changing its numeric value.

Save and load province entries using exactly:

```cpp
{"recruitable_population", province.recruitable_population}
```

and:

```cpp
entry.at("recruitable_population").get<std::int64_t>()
```

Do not use `value()`, fallback keys, or compatibility branches.

- [ ] **Step 5: Verify the migration is complete**

Run:

```powershell
rg -n "soldier_population" core bridge game/data tests game/tests
.\scripts\build.cmd
```

Expected: `rg` finds only the intentional negative assertion in `army_bridge_smoke_test.gd`; build and core smoke tests pass.

Then run:

```powershell
$g='C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $g --headless --path game --script res://tests/army_bridge_smoke_test.gd
```

Expected: `ProvinceBridge army recruitment smoke test passed`.

- [ ] **Step 6: Commit the breaking rename**

```powershell
git add core/include/province/core/province.hpp core/include/province/core/save_game.hpp core/src/scenario_loader.cpp core/src/save_game.cpp core/src/game_state.cpp core/src/ai_system.cpp core/src/army_system.cpp bridge/src/province_bridge.cpp game/data tests/core/core_smoke_test.cpp game/tests/army_bridge_smoke_test.gd
git commit -m "refactor: rename soldier pool to recruitable population"
```

---

### Task 2: Add monthly recruitable-population replenishment

**Files:**
- Modify: `tests/core/core_smoke_test.cpp`
- Modify: `core/include/province/core/population_system.hpp`
- Modify: `core/src/population_system.cpp`
- Modify: `core/src/command_processor.cpp`

**Interfaces:**
- Consumes: `Province::recruitable_population` from Task 1.
- Produces: `ProvincePopulationChange::previous_recruitable_population` as `std::int64_t`.
- Produces: `ProvincePopulationChange::current_recruitable_population` as `std::int64_t`.
- Produces: `ProvincePopulationChange::recruitable_growth` as `std::int64_t`.
- Preserves: `PopulationSystem::resolve_month(GameState&) -> MonthlyPopulationReport`.

- [ ] **Step 1: Write failing one-month, multi-month, cap, and event tests**

Extend the existing turn section in `tests/core/core_smoke_test.cpp` with these exact expectations for Northreach:

```cpp
if (northreach_after_turn == nullptr ||
    northreach_after_turn->population != 120'360 ||
    northreach_after_turn->recruitable_population != 3'802 ||
    population_event.elapsed_months != 3) {
    std::cerr << "PopulationSystem produced an incorrect three-month result\n";
    return 1;
}
```

Find Northreach's aggregated change and require:

```cpp
previous_recruitable_population == 2'000
current_recruitable_population == 3'802
recruitable_growth == 1'802
```

Add a cap setup before advancing one month:

```cpp
GameState cap_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
Province* cap_province = cap_state.find_province(ProvinceId{"northreach"});
cap_province->recruitable_population = 12'011;
CommandProcessor cap_processor;
const CommandResult cap_result = cap_processor.execute(cap_state, AdvanceTurnCommand{1});
if (!cap_result.accepted ||
    cap_state.find_province(ProvinceId{"northreach"})->population != 120'120 ||
    cap_state.find_province(ProvinceId{"northreach"})->recruitable_population != 12'012) {
    std::cerr << "Recruitable population did not stop at the ten-percent cap\n";
    return 1;
}
```

- [ ] **Step 2: Run the core test and verify RED**

```powershell
.\scripts\build.cmd
```

Expected: compilation fails because the three recruitable report members do not exist, or the runtime assertion reports an incorrect three-month result.

- [ ] **Step 3: Extend the population report and integer constants**

Add to `ProvincePopulationChange`:

```cpp
std::int64_t previous_recruitable_population{};
std::int64_t current_recruitable_population{};
std::int64_t recruitable_growth{};
```

Add exact constants to `PopulationSystem`:

```cpp
static constexpr std::int64_t recruitable_growth_rate = 50; // 0.5%
static constexpr std::int64_t recruitable_cap_rate = 1'000; // 10%
```

- [ ] **Step 4: Implement floor-scaled monthly replenishment after total growth**

Use overflow-safe quotient/remainder scaling:

```cpp
const auto scaled_floor = [](const std::int64_t value,
                             const std::int64_t numerator) {
    return (value / rate_denominator) * numerator +
        ((value % rate_denominator) * numerator) / rate_denominator;
};
```

After updating `province->population`, calculate:

```cpp
const std::int64_t previous_recruitable = province->recruitable_population;
const std::int64_t candidate_growth =
    scaled_floor(province->population, recruitable_growth_rate);
const std::int64_t cap =
    scaled_floor(province->population, recruitable_cap_rate);
const std::int64_t available_capacity =
    std::max<std::int64_t>(0, cap - province->recruitable_population);
const std::int64_t recruitable_growth =
    std::min(candidate_growth, available_capacity);
province->recruitable_population += recruitable_growth;
```

Populate all seven report values: province id, previous/current total population, total growth, previous/current recruitable population, and recruitable growth. Include `<algorithm>` for `std::min` and `std::max`.

- [ ] **Step 5: Aggregate monthly report fields in multi-month turns**

In the existing-map branch of `CommandProcessor::execute_advance_turn`, add:

```cpp
existing->second.current_recruitable_population =
    change.current_recruitable_population;
existing->second.recruitable_growth += change.recruitable_growth;
```

The first month's `previous_recruitable_population` remains unchanged because the initial report object is inserted into the map.

- [ ] **Step 6: Verify monthly behavior and commit**

```powershell
.\scripts\build.cmd
```

Expected: build succeeds and `Province core smoke test passed`.

```powershell
git add core/include/province/core/population_system.hpp core/src/population_system.cpp core/src/command_processor.cpp tests/core/core_smoke_test.cpp
git commit -m "feat: replenish recruitable population monthly"
```

---

### Task 3: Make recruitment remove province population

**Files:**
- Modify: `tests/core/core_smoke_test.cpp`
- Modify: `core/src/army_system.cpp`

**Interfaces:**
- Consumes: `Province::population` and `Province::recruitable_population`.
- Preserves: `ArmySystem::recruit(GameState&, const CountryId&, const ProvinceId&, std::int64_t) -> ArmyRecruitResult`.
- Produces: successful recruitment atomically deducts treasury, total population, and recruitable population before creating an army.

- [ ] **Step 1: Write failing success and rejection assertions**

Change the successful recruitment assertion to require:

```cpp
recruiting_province->population == 119'000 &&
recruiting_province->recruitable_population == 1'000
```

After the rejected 2,000-person recruitment, also require:

```cpp
recruitment_state.find_province(ProvinceId{"northreach"})->population == 119'000 &&
recruitment_state.find_province(ProvinceId{"northreach"})->recruitable_population == 1'000
```

- [ ] **Step 2: Run the core test and verify RED**

```powershell
.\scripts\build.cmd
```

Expected: `RecruitArmyCommand did not transfer funds and soldiers correctly` because total population remains 120,000.

- [ ] **Step 3: Add total-population validation and deduction**

Before calculating or deducting cost, add:

```cpp
if (province->population < manpower) {
    return {false, "province population is insufficient", 0, std::nullopt};
}
```

The successful mutation block must be:

```cpp
country->treasury -= cost;
province->recruitable_population -= manpower;
province->population -= manpower;
const ArmyId army_id = state.create_army(country_id, province_id, manpower);
```

- [ ] **Step 4: Verify transactional recruitment and commit**

```powershell
.\scripts\build.cmd
```

Expected: build succeeds and all core smoke assertions pass.

```powershell
git add core/src/army_system.cpp tests/core/core_smoke_test.cpp
git commit -m "feat: deduct population when recruiting armies"
```

---

### Task 4: Update Godot UI wording and end-to-end behavior

**Files:**
- Modify: `game/scripts/main.gd`
- Modify: `game/tests/main_layout_smoke_test.gd`
- Modify: `game/tests/army_bridge_smoke_test.gd`
- Modify: `game/tests/save_game_bridge_smoke_test.gd`

**Interfaces:**
- Consumes: bridge province key `recruitable_population`.
- Produces: all player-visible province and global summaries use “可招募士兵”.
- Produces: Godot smoke coverage for one-month growth and recruitment deductions.

- [ ] **Step 1: Write a failing UI wording assertion and bridge behavior regressions**

In `main_layout_smoke_test.gd`, after the scene has processed one frame, require:

```gdscript
var province_summary := main_scene.get_node(
    "RightPanel/Center/ProvinceSummary"
) as Label
if not province_summary.text.contains("可招募士兵"):
    push_error("Main UI did not label the recruitable population")
    main_scene.free()
    quit(1)
    return
```

In `army_bridge_smoke_test.gd`, record Northreach before recruitment, recruit 1,000, and assert:

```gdscript
if northreach_after_recruit["population"] != northreach_before["population"] - 1000 or \
        northreach_after_recruit["recruitable_population"] != \
        northreach_before["recruitable_population"] - 1000:
    push_error("Recruitment did not deduct both province population pools")
    quit(1)
    return
```

Use a fresh bridge with AI disabled, advance one month, and assert Northreach becomes population 120,120 and recruitable population 2,600.

- [ ] **Step 2: Run the layout test and verify RED before changing UI reads**

```powershell
$g='C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $g --headless --path game --script res://tests/main_layout_smoke_test.gd
```

Expected: test fails with `Main UI did not label the recruitable population`.

- [ ] **Step 3: Replace Godot dictionary reads and labels**

In `main.gd`, replace every province dictionary access:

```gdscript
province["soldier_population"]
```

with:

```gdscript
province["recruitable_population"]
```

Use these exact visible phrases:

```gdscript
"总人口 %d · 可招募士兵 %d"
"人口: %d | 可招募士兵: %d | 经济: %d"
"%s · %s · 人口%d · 可招募士兵%d · 经济%d"
```

Do not rename `Army::manpower`, battle manpower, or the actual recruited army count; those represent deployed troops rather than the recruitable pool.

- [ ] **Step 4: Verify save round-trip uses the new schema**

Extend `save_game_bridge_smoke_test.gd` to compare Northreach's `population` and `recruitable_population` before save and after load. The assertion must fail if either differs.

Run:

```powershell
.\scripts\build.cmd
$g='C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $g --headless --path game --script res://tests/main_layout_smoke_test.gd
& $g --headless --path game --script res://tests/army_bridge_smoke_test.gd
& $g --headless --path game --script res://tests/save_game_bridge_smoke_test.gd
& $g --headless --path game --quit-after 2
```

Expected: core tests, both Godot tests, and main-scene startup all exit with code 0.

- [ ] **Step 5: Run the complete Godot smoke suite**

Run each script sequentially after the build:

```powershell
$tests=@(
  'main_layout_smoke_test.gd',
  'map_smoke_test.gd',
  'road_bridge_smoke_test.gd',
  'army_bridge_smoke_test.gd',
  'technology_bridge_smoke_test.gd',
  'ai_bridge_smoke_test.gd',
  'game_status_bridge_smoke_test.gd',
  'save_game_bridge_smoke_test.gd'
)
foreach($test in $tests) {
  & $g --headless --path game --script ("res://tests/" + $test)
  if ($LASTEXITCODE -ne 0) { throw "$test failed" }
}
```

Expected: all eight scripts print their pass message and exit with code 0.

- [ ] **Step 6: Confirm old naming is gone and commit**

```powershell
rg -n "soldier_population|士兵人口|Soldiers:" core bridge game tests --glob '!*.uid'
```

Expected: no production occurrence; only explicit negative-compatibility assertions may remain.

```powershell
git add game/scripts/main.gd game/tests/main_layout_smoke_test.gd game/tests/army_bridge_smoke_test.gd game/tests/save_game_bridge_smoke_test.gd
git commit -m "feat: expose recruitable population in Godot UI"
```

---

## Final Verification

- [ ] Run `git diff --check` and confirm no whitespace errors.
- [ ] Run `.\scripts\build.cmd` and confirm SCons build plus core tests pass.
- [ ] Run all eight Godot smoke scripts sequentially and confirm zero failures.
- [ ] Run the main scene headlessly for two frames and confirm no script or GDExtension errors.
- [ ] Inspect `git status --short`; commit only feature files and leave unrelated Godot editor metadata/log files untouched.
