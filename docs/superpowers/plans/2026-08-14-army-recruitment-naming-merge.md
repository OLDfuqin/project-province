# Army Recruitment, Naming, and Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players recruit an entered number of soldiers, identify armies as `<country code>·第X军`, change each army's per-country unique number, and merge same-country armies occupying the same province.

**Architecture:** Keep immutable `ArmyId` values as internal references and add a separate `formation_number` to `Army`. Enforce allocation, renaming, merging, validation, and save compatibility in the C++ core; expose command results through `ProvinceBridge`; make the province management component own only input and selection state.

**Tech Stack:** C++20, nlohmann/json, Godot 4.6.3 GDExtension, GDScript, SCons, MSVC

## Global Constraints

- Army display format is exactly `<country code>·第<positive integer>军`.
- Formation numbers are unique only among a country's living armies; different countries may use the same number.
- Recruitment allocates the smallest positive formation-number gap, including numbers released by destruction or merging.
- Renaming changes only `formation_number`, never `ArmyId`.
- Merge candidates must have the same owner and province as the primary army.
- A merge preserves the primary ID, number, location, and advance plan; sums manpower; takes the minimum movement points; and removes absorbed armies.
- Recruitment, renaming, and merging are atomic core commands.
- AI recruitment continues to use its current fixed batch; AI does not rename or merge in this update.
- Preserve the pre-existing uncommitted changes in `game/scripts/main.gd` and `game/tests/army_bridge_smoke_test.gd`; inspect and isolate them before editing overlapping files.
- Update current rules and project structure documentation in the final task.

---

### Task 1: Country codes and formation-number state

**Files:**
- Modify: `core/include/province/core/country.hpp`
- Modify: `core/include/province/core/army.hpp`
- Modify: `core/include/province/core/game_state.hpp`
- Modify: `core/src/game_state.cpp`
- Modify: `core/src/scenario_loader.cpp`
- Modify: `game/data/countries.json`
- Modify: `game/data/schema_version.json`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Consumes: existing `CountryId`, `ArmyId`, `GameState::create_army`, and scenario JSON loading.
- Produces: `Country::code`, `Army::formation_number`, `GameState::next_formation_number(const CountryId&)`, and `GameState::army_display_name(const ArmyId&)`.

- [ ] **Step 1: Protect overlapping user changes**

Run:

```powershell
git status --short
git diff -- game/scripts/main.gd game/tests/army_bridge_smoke_test.gd
```

Expected: record the exact pre-existing diffs. Do not stage, revert, reformat, or overwrite them. If Task 4 or 5 must edit either file, preserve the existing content and review the resulting diff by hunk before staging.

- [ ] **Step 2: Add failing core state tests**

Add assertions to `tests/core/core_smoke_test.cpp` equivalent to:

```cpp
const CommandResult first = processor.execute(
    state,
    RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 100}
);
const ArmyId first_id =
    std::get<ArmyRecruitedEvent>(first.events.front().payload).army_id;
if (state.find_country(CountryId{"auroria"})->code != "奥" ||
    state.find_army(first_id)->formation_number != 1 ||
    state.army_display_name(first_id) != "奥·第1军") {
    std::cerr << "Army display identity was not initialized\n";
    return 1;
}
```

Recruit a second Aurorian army and one Caelus army; assert formation numbers `2` and `1` respectively. Remove the first Aurorian army, recruit another, and assert that number `1` is reused.

- [ ] **Step 3: Run the core test to verify failure**

Run:

```powershell
.\scripts\build.cmd
```

Expected: compilation fails because `Country::code`, `Army::formation_number`, or the new `GameState` queries do not exist.

- [ ] **Step 4: Implement codes and allocation**

Add:

```cpp
struct Country final {
    CountryId id;
    std::string name;
    std::string code;
    std::uint32_t color_rgb{};
    std::int64_t treasury{};
};
```

and:

```cpp
struct Army final {
    ArmyId id;
    CountryId owner_id;
    ProvinceId province_id;
    std::int64_t formation_number{};
    // existing runtime fields follow
};
```

Declare and implement:

```cpp
[[nodiscard]] std::int64_t next_formation_number(const CountryId& owner_id) const;
[[nodiscard]] std::string army_display_name(const ArmyId& army_id) const;
```

`next_formation_number` must scan positive integers from1 upward against living armies owned by that country. `create_army` must assign that result. `army_display_name` must reject an unknown army or owner consistently with existing state query conventions and return `country.code + "·第" + std::to_string(number) + "军"`.

Add `code` to all four entries in `countries.json`, increment the scenario schema version, parse the field, and make `GameState::validate()` report empty/duplicate country codes, non-positive formation numbers, and same-country duplicate numbers.

- [ ] **Step 5: Run core tests**

Run:

```powershell
.\scripts\build.cmd
```

Expected: build succeeds and `Project Province core ... smoke test passed` appears.

- [ ] **Step 6: Commit the state foundation**

```powershell
git add core/include/province/core/country.hpp core/include/province/core/army.hpp core/include/province/core/game_state.hpp core/src/game_state.cpp core/src/scenario_loader.cpp game/data/countries.json game/data/schema_version.json tests/core/core_smoke_test.cpp
git commit -m "feat: add country army formation numbers"
```

---

### Task 2: Rename and merge core commands

**Files:**
- Modify: `core/include/province/core/game_command.hpp`
- Modify: `core/include/province/core/game_event.hpp`
- Modify: `core/include/province/core/army_system.hpp`
- Modify: `core/src/army_system.cpp`
- Modify: `core/include/province/core/command_processor.hpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Consumes: `Army::formation_number`, `GameState` army lookup/removal, and the existing transactional `CommandProcessor::execute` flow.
- Produces: `RenameArmyCommand`, `MergeArmiesCommand`, `ArmyRenamedEvent`, `ArmiesMergedEvent`, and matching `ArmySystem` operations.

- [ ] **Step 1: Add failing rename tests**

Add tests equivalent to:

```cpp
const CommandResult renamed = processor.execute(
    state,
    RenameArmyCommand{first_id, 5}
);
if (!renamed.accepted || state.find_army(first_id)->formation_number != 5) {
    std::cerr << "Army rename was not applied\n";
    return 1;
}
const CommandResult conflict = processor.execute(
    state,
    RenameArmyCommand{second_id, 5}
);
if (conflict.accepted || state.find_army(second_id)->formation_number != 2) {
    std::cerr << "Duplicate formation number was not rejected atomically\n";
    return 1;
}
```

Also test zero, negative, same-current-number, unknown-army, and a matching number owned by another country.

- [ ] **Step 2: Add failing merge tests**

Create three same-country armies in one province, set distinct movement points and a primary advance plan, then execute:

```cpp
const CommandResult merged = processor.execute(
    state,
    MergeArmiesCommand{primary_id, {second_id, third_id}}
);
```

Assert the primary survives, manpower is summed, movement points equal the minimum, its number and complete advance plan are unchanged, and both absorbed armies are absent. Add atomic rejection cases for empty absorbed list, duplicate IDs, primary in absorbed list, unknown army, different owner, different province, and `std::int64_t` manpower overflow.

- [ ] **Step 3: Run tests to verify failure**

Run:

```powershell
.\scripts\build.cmd
```

Expected: compilation fails because the new command and event types do not exist.

- [ ] **Step 4: Define commands, events, and results**

Add:

```cpp
struct RenameArmyCommand final {
    ArmyId army_id;
    std::int64_t formation_number{};
};

struct MergeArmiesCommand final {
    ArmyId primary_army_id;
    std::vector<ArmyId> merged_army_ids;
};
```

Add both to `GameCommand`. Define events containing old/new number for rename and primary ID, absorbed IDs, previous/final manpower, and final movement points for merge. Add corresponding `GameEventType` members and variant alternatives.

- [ ] **Step 5: Implement atomic core operations**

Add `ArmySystem::rename` and `ArmySystem::merge` result types and methods. Validate every input before changing the passed `GameState`. Detect manpower overflow using `max - accumulated < next_manpower`. For merge, calculate final manpower and minimum movement points first, then mutate the primary and remove absorbed armies.

Extend `CommandProcessor` dispatch and private handlers. Execute against its existing working-state copy, emit exactly one rename or merge event on success, and commit only accepted results.

- [ ] **Step 6: Run core tests and commit**

Run:

```powershell
.\scripts\build.cmd
```

Expected: all C++ tests pass.

Then:

```powershell
git add core/include/province/core/game_command.hpp core/include/province/core/game_event.hpp core/include/province/core/army_system.hpp core/src/army_system.cpp core/include/province/core/command_processor.hpp core/src/command_processor.cpp tests/core/core_smoke_test.cpp
git commit -m "feat: rename and merge armies"
```

---

### Task 3: Save schema and backward migration

**Files:**
- Modify: `core/include/province/core/save_game.hpp`
- Modify: `core/src/save_game.cpp`
- Modify: `tests/core/save_game_smoke_test.cpp`

**Interfaces:**
- Consumes: `Country::code`, `Army::formation_number`, `GameState::validate()`.
- Produces: new save schema with explicit code/number fields and deterministic migration from schema3.

- [ ] **Step 1: Add failing round-trip and migration tests**

Extend `tests/core/save_game_smoke_test.cpp` to save two same-country armies after renaming and merging, load them, and assert `Country::code`, `formation_number`, and display name survive.

Create a schema3 fixture in the test's temporary directory by writing the known schema3 JSON structure without `country.code` and `army.formation_number`. Load it and assert armies are grouped by owner, sorted by `ArmyId`, and assigned1,2,... separately for each country. Add invalid current-schema fixtures for empty/duplicate country code and same-country duplicate/non-positive formation number; assert `SaveGameError`.

- [ ] **Step 2: Run the save test to verify failure**

Run:

```powershell
.\scripts\build.cmd
```

Expected: save assertions fail or schema3 is rejected.

- [ ] **Step 3: Implement schema4 save and schema3 migration**

Set:

```cpp
static constexpr std::int32_t schema_version = 4;
```

Write `code` for each country and `formation_number` for each army. Accept only versions3 and4 in `load()`. For version3, obtain country codes from a fixed mapping keyed by the four current stable country IDs, reject unknown IDs, then assign formation numbers independently per owner after all armies are read and sorted by map order. For version4, require both fields. Run the existing final `state.validate()` in both paths.

- [ ] **Step 4: Run tests and commit**

Run:

```powershell
.\scripts\build.cmd
```

Expected: all core and save tests pass.

Then:

```powershell
git add core/include/province/core/save_game.hpp core/src/save_game.cpp tests/core/save_game_smoke_test.cpp
git commit -m "feat: persist army formation identities"
```

---

### Task 4: Expose names, rename, and merge through GDExtension

**Files:**
- Modify: `bridge/src/province_bridge.hpp`
- Modify: `bridge/src/province_bridge.cpp`
- Modify: `bridge/src/province_bridge_bindings.cpp`
- Modify: `game/tests/army_bridge_smoke_test.gd`
- Modify: `game/tests/save_game_bridge_smoke_test.gd`

**Interfaces:**
- Consumes: core rename/merge commands and formation identity fields.
- Produces: `rename_army(army_id, formation_number)`, `merge_armies(primary_army_id, merged_army_ids)`, and enriched country/army dictionaries.

- [ ] **Step 1: Reconcile the pre-existing army bridge test diff**

Run:

```powershell
git diff -- game/tests/army_bridge_smoke_test.gd
```

If the diff is formatting-only, preserve its line endings while adding tests and stage only the intended final file after reviewing it. If it contains behavioral user changes, integrate new cases without altering those expectations. Stop and report if both cannot be preserved reliably.

- [ ] **Step 2: Add failing bridge tests**

In `army_bridge_smoke_test.gd`, assert country summaries include `code`; recruit arbitrary quantities such as125 and275; assert army summaries include `formation_number`, `country_code`, and `display_name`; rename one army; merge it with another; and assert the response and refreshed summaries reflect the primary army and summed manpower.

Add rejected rename and merge cases and assert summaries are unchanged. In `save_game_bridge_smoke_test.gd`, assert display identity survives save/load.

- [ ] **Step 3: Run the bridge test to verify failure**

Run after building the current DLL:

```powershell
$godot = 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/army_bridge_smoke_test.gd
```

Expected: failure because identity keys or bridge methods are absent.

- [ ] **Step 4: Implement and bind bridge methods**

Declare, implement, and bind:

```cpp
godot::Dictionary rename_army(const godot::String& army_id, std::int64_t formation_number);
godot::Dictionary merge_armies(const godot::String& primary_army_id, const godot::Array& merged_army_ids);
```

Convert every merged ID to `ArmyId`, submit the command, and return `accepted`, `error`, and success event fields. Add `code` to country summaries and `formation_number`, `country_code`, `display_name` to army summaries. Do not construct names separately in GDScript.

- [ ] **Step 5: Build and run bridge/save tests**

Run sequentially:

```powershell
.\scripts\build.cmd
$godot = 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/army_bridge_smoke_test.gd
& $godot --headless --path game --script res://tests/save_game_bridge_smoke_test.gd
```

Expected: build and both Godot scripts pass.

- [ ] **Step 6: Commit bridge support**

Review `git diff --check` and stage only intended files, then:

```powershell
git add bridge/src/province_bridge.hpp bridge/src/province_bridge.cpp bridge/src/province_bridge_bindings.cpp game/tests/army_bridge_smoke_test.gd game/tests/save_game_bridge_smoke_test.gd
git commit -m "feat: expose army identity and merge commands"
```

---

### Task 5: Province-management recruitment, rename, and merge UI

**Files:**
- Modify: `game/scenes/ui/province_management_window.tscn`
- Modify: `game/scripts/province_management_window.gd`
- Modify: `game/scripts/main.gd`
- Modify: `game/scripts/province_map.gd`
- Modify: `game/scripts/ui/strategy_panel_presenter.gd`
- Modify: `game/tests/province_management_window_component_smoke_test.gd`
- Modify: `game/tests/province_management_window_smoke_test.gd`
- Modify: `game/tests/province_management_advance_smoke_test.gd`
- Modify: `game/tests/map_smoke_test.gd`

**Interfaces:**
- Consumes: enriched army dictionaries and `ProvinceBridge.rename_army`/`merge_armies`.
- Produces: player-entered recruitment, numeric renaming, multi-army merge selection, and unified display names.

- [ ] **Step 1: Add failing component tests**

Extend the component test to assert the management scene contains:

```text
Recruitment/Amount
Recruitment/Confirm
Recruitment/Cancel
Rename/FormationNumber
Rename/Confirm
Merge/Candidates
Merge/Preview
Merge/Confirm
```

Assert `recruit_requested` emits `(province_id, manpower)`, `rename_requested` emits `(army_id, formation_number)`, and `merge_requested` emits `(primary_army_id, merged_army_ids)`. Test invalid/empty inputs keep confirmation disabled and cancellation clears recruitment input.

- [ ] **Step 2: Add failing integration/display tests**

Update management, advance, and map tests so army selectors, details, plan links, and map labels use `display_name` rather than raw `army_id`. Test merge candidates exclude the primary, foreign armies, and armies in another province; selecting multiple candidates previews summed manpower and minimum movement points.

- [ ] **Step 3: Run UI tests to verify failure**

Run:

```powershell
$godot = 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/province_management_window_component_smoke_test.gd
```

Expected: missing-node or signal-contract failure.

- [ ] **Step 4: Build the management controls**

Replace the fixed recruitment button with a collapsible recruitment container showing available soldiers, treasury, maximum, `SpinBox`/integer input, confirm, and cancel. Use an integer-capable control configured for whole numbers; clamp only for UI convenience and still pass the entered value to core validation.

Add a rename row whose input initially shows the selected army's `formation_number`. Add a merge section using a multi-select `ItemList`, preview label, and confirmation button. Store stable IDs as item metadata. Rebuild rename and merge state whenever the selected army or province changes.

- [ ] **Step 5: Connect main coordinator commands**

Change the management signal contract to include recruitment manpower. In `main.gd`, call `bridge.recruit_army(player_country_id, province_id, manpower)`, and add handlers for rename and merge. After success, refresh countries, provinces, armies, map, plans, and management window; preserve the primary army selection after merge. On failure, display the bridge error without closing the relevant input state.

Before modifying `main.gd`, compare its pre-existing unstaged diff. Preserve every user hunk and avoid whole-file line-ending conversion. If this cannot be done with a narrow patch, stop rather than overwrite it.

- [ ] **Step 6: Use display names everywhere visible**

Update `province_management_window.gd`, `province_map.gd`, and `strategy_panel_presenter.gd` to display `army.display_name`, with raw `id` only as fallback for malformed test fixtures. Metadata and command calls must continue using `army.id`.

- [ ] **Step 7: Run focused UI tests**

Run sequentially:

```powershell
.\scripts\build.cmd
$godot = 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/province_management_window_component_smoke_test.gd
& $godot --headless --path game --script res://tests/province_management_window_smoke_test.gd
& $godot --headless --path game --script res://tests/province_management_advance_smoke_test.gd
& $godot --headless --path game --script res://tests/map_smoke_test.gd
```

Expected: all four scripts pass.

- [ ] **Step 8: Commit UI behavior**

Use `git diff --check`, review overlapping files hunk by hunk, then stage only the intended UI changes and tests:

```powershell
git add game/scenes/ui/province_management_window.tscn game/scripts/province_management_window.gd game/scripts/main.gd game/scripts/province_map.gd game/scripts/ui/strategy_panel_presenter.gd game/tests/province_management_window_component_smoke_test.gd game/tests/province_management_window_smoke_test.gd game/tests/province_management_advance_smoke_test.gd game/tests/map_smoke_test.gd
git commit -m "feat: manage army recruitment names and merges"
```

---

### Task 6: Documentation and full regression verification

**Files:**
- Modify: `docs/current-game-rules.md`
- Modify: `docs/project-structure.md`
- Modify if needed: `README.md`

**Interfaces:**
- Consumes: final implemented behavior from Tasks1–5.
- Produces: authoritative current rules and updated file responsibility navigation.

- [ ] **Step 1: Update current rules**

Replace the statement that the UI recruits a fixed1000 soldiers. Document entered positive integer recruitment, per-country formation-number uniqueness, smallest-gap reuse, display format, renaming, merge eligibility, primary preservation, manpower sum, minimum movement points, released numbers, atomic rejection, AI behavior, and schema3 migration.

- [ ] **Step 2: Update project structure**

Add the new command/event responsibilities and any scene, script, or test responsibility changes to `docs/project-structure.md`. Update `README.md` only if its player-visible feature summary names the old fixed recruitment behavior.

- [ ] **Step 3: Run complete verification**

Run:

```powershell
.\scripts\build.cmd
$godot = 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --editor --path game --quit
Get-ChildItem game/tests/*.gd | Sort-Object Name | ForEach-Object {
    & $godot --headless --path game --script ("res://tests/" + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Godot test failed: $($_.Name)" }
}
& $godot --headless --path game --quit-after 2
git diff --check
```

Expected: C++ tests, every Godot test, and main-scene startup pass; `git diff --check` reports no whitespace errors.

- [ ] **Step 4: Verify requirements explicitly**

Confirm from tests and final diff:

```text
[ ] Arbitrary recruitment input reaches the core
[ ] Smallest per-country free number is allocated and reused
[ ] Rename cannot duplicate a living same-country number
[ ] Merge is same-country/same-province and atomic
[ ] Primary plan survives; manpower sums; movement points take minimum
[ ] Save round-trip and schema3 migration pass
[ ] Every player-visible army label uses the display name
[ ] Existing user modifications were preserved
```

- [ ] **Step 5: Commit documentation**

```powershell
git add docs/current-game-rules.md docs/project-structure.md README.md
git commit -m "docs: define army identity and merge rules"
```

Omit `README.md` from `git add` if it did not require a change.
