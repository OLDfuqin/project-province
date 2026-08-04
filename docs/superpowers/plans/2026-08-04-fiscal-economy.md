# Fiscal Economy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fixed province economy values with population-derived economy and terrain-adjusted fiscal income throughout the simulation, save format, bridge, UI, tests, and current-rules handbook.

**Architecture:** `EconomySystem` is the only source for derived province economy and fiscal income. Core monthly processing aggregates fiscal income by actual controller; bridge snapshots expose both values; Godot only formats those snapshots. Fixed economy data is removed and scenario/save schemas move to version 3.

**Tech Stack:** C++20, Godot 4.6.3 GDExtension/GDScript, nlohmann JSON, SCons, Markdown.

## Global Constraints

- Use integer arithmetic and always round down.
- `economy = floor(population × (100 + 10 × controller economy level) / 100)`.
- `fiscal_income = floor(economy × terrain numerator / 10000)` with numerators 100/90/90/80.
- Fiscal income receives no independent technology multiplier.
- Use the actual controller's technology for occupied provinces in this version.
- Mark that occupation/technology rule as a priority logic issue in `docs/current-game-rules.md`.
- Delete the old stored province economy field; do not retain compatibility data.
- Reject scenario/save schema version 2 after upgrading the relevant schema to 3.
- Preserve unrelated user changes, especially the main worktree's `game/scripts/main.gd` formatting changes.

---

### Task 1: Add Failing Core Fiscal-Economy Tests

**Files:**
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Consumes: Existing `EconomySystem`, scenario state, technology, recruitment, and occupation commands.
- Produces: Assertions defining the new formula and semantics before implementation.

- [ ] **Step 1: Replace fixed-income expectations with derived values**

Update test imports to use `CountryFiscalIncome` and `FiscalIncomeResolvedEvent`. Add helpers that locate country fiscal results by ID.

- [ ] **Step 2: Add formula assertions**

For existing provinces, assert at technology level 0:

```cpp
EconomySystem::province_economy(state, ProvinceId{"northreach"}) == 120'000;
EconomySystem::province_fiscal_income(state, ProvinceId{"northreach"}) == 1'200;
EconomySystem::province_fiscal_income(state, ProvinceId{"z_gv_1"}) == 270;
EconomySystem::province_fiscal_income(state, ProvinceId{"z_wm_2"}) == 225;
EconomySystem::province_fiscal_income(state, ProvinceId{"z_nr_2"}) == 200;
```

- [ ] **Step 3: Assert technology and control behavior**

Research economy level 1 and assert Northreach economy `132000` and fiscal income `1320`. Occupy a province with a controller having a different technology level and assert both derived values and monthly income use the controller's level.

- [ ] **Step 4: Assert population and recruitment coupling**

Assert that recruiting 1000 from Northreach changes its economy from `120000` to `119000` before technology and changes its next fiscal income accordingly. Assert monthly population growth changes the following month's derived values.

- [ ] **Step 5: Run the core build and confirm RED**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q
```

Expected: compilation fails because the new fiscal types and methods do not exist, or assertions fail under fixed economy behavior.

### Task 2: Implement the Core Derived Economy and Fiscal Events

**Files:**
- Modify: `core/include/province/core/province.hpp`
- Modify: `core/include/province/core/economy_system.hpp`
- Modify: `core/src/economy_system.cpp`
- Modify: `core/include/province/core/game_event.hpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `core/src/game_state.cpp`

**Interfaces:**
- Produces:

```cpp
struct CountryFiscalIncome { CountryId country_id; std::int64_t amount; };
struct MonthlyFiscalReport { std::vector<CountryFiscalIncome> fiscal_incomes; };
static std::int64_t EconomySystem::province_economy(const GameState&, const ProvinceId&);
static std::int64_t EconomySystem::province_fiscal_income(const GameState&, const ProvinceId&);
MonthlyFiscalReport EconomySystem::resolve_month(GameState&) const;
```

- [ ] **Step 1: Remove `Province::economy`**

Delete the stored field and the negative-economy validation. Adjust all direct aggregate initializers in core tests and loaders to the new field order.

- [ ] **Step 2: Implement overflow-safe scaled floor**

Use quotient/remainder multiplication with explicit overflow checks for non-negative values. Derive the controller's technology through `GameState::controller_of` and `find_technology`.

- [ ] **Step 3: Implement terrain fiscal numerators**

Map terrain to `100`, `90`, `90`, `80`; compute fiscal income with denominator `10000` and one final floor operation.

- [ ] **Step 4: Rename reports and events**

Change the event type to `fiscal_income_resolved`, payload to `FiscalIncomeResolvedEvent`, and aggregate `fiscal_incomes` for each supported turn.

- [ ] **Step 5: Run core tests and confirm GREEN**

Run the SCons build followed by:

```powershell
.\build\bin\province_core_tests.exe
```

Expected: `Project Province core 0.1.0-dev smoke test passed`.

- [ ] **Step 6: Commit core behavior**

```powershell
git add core tests/core/core_smoke_test.cpp
git commit -m "feat: derive economy and fiscal income from population"
```

### Task 3: Upgrade Scenario and Save Schemas

**Files:**
- Modify: `core/src/scenario_loader.cpp`
- Modify: `core/include/province/core/save_game.hpp`
- Modify: `core/src/save_game.cpp`
- Modify: `game/data/countries.json`
- Modify: `game/data/provinces.json`
- Modify: `game/tests/save_game_bridge_smoke_test.gd`

**Interfaces:**
- Consumes: `Province` without a stored economy field.
- Produces: Scenario schema 3 and save schema 3 without province `economy`.

- [ ] **Step 1: Add failing schema assertions**

Update the save smoke test to parse the saved JSON and assert schema version 3 and absence of `economy` from every province. Add a load rejection check for a copied document with schema version 2.

- [ ] **Step 2: Remove economy from scenario loading and data**

Set `supported_schema_version = 3`, set `countries.json` and `provinces.json` to 3, and delete all 32 fixed `economy` properties.

- [ ] **Step 3: Upgrade save serialization**

Set `SaveGameSerializer::schema_version = 3`, omit province economy on save, and construct provinces without economy on load.

- [ ] **Step 4: Run core and save smoke tests**

Run core tests and `game/tests/save_game_bridge_smoke_test.gd`. Expected: both pass, version 2 is rejected without replacing the loaded state.

- [ ] **Step 5: Commit schema changes**

```powershell
git add core game/data game/tests/save_game_bridge_smoke_test.gd
git commit -m "feat: upgrade fiscal economy data schemas"
```

### Task 4: Expose Fiscal Economy Through the Bridge

**Files:**
- Modify: `bridge/src/province_bridge.cpp`
- Modify: `game/tests/army_bridge_smoke_test.gd`
- Modify: `game/tests/technology_bridge_smoke_test.gd`

**Interfaces:**
- Province summaries add integer `economy` and `fiscal_income`.
- Country summaries add integer `economy` and `fiscal_income` totals.
- Turn responses replace `incomes` with `fiscal_incomes` and `economy_event_sequence` with `fiscal_income_event_sequence`.

- [ ] **Step 1: Add failing bridge assertions**

Assert Northreach exposes economy `120000`, fiscal income `1200`, and no legacy fixed value `80`. Assert country totals equal the sum of their controlled province snapshots.

- [ ] **Step 2: Calculate summaries through `EconomySystem`**

Do not duplicate formulas in `ProvinceBridge`; call the two core methods for every province and aggregate the returned values by controller.

- [ ] **Step 3: Rename turn response fields**

Translate `FiscalIncomeResolvedEvent` into `fiscal_incomes` and update all bridge smoke tests to consume the new key.

- [ ] **Step 4: Run bridge tests**

Run army, technology, AI, game-status, and save smoke tests. Expected: all pass.

- [ ] **Step 5: Commit bridge changes**

```powershell
git add bridge game/tests
git commit -m "feat: expose economy and fiscal income summaries"
```

### Task 5: Update Godot UI and Layout Tests

**Files:**
- Modify: `game/scripts/main.gd`
- Modify: `game/scripts/province_info_window.gd`
- Modify: `game/scripts/province_management_window.gd`
- Modify: `game/tests/main_layout_smoke_test.gd`
- Modify: `game/tests/province_info_window_smoke_test.gd`
- Modify: `game/tests/province_management_window_component_smoke_test.gd`
- Modify: `game/tests/province_management_window_smoke_test.gd`

**Interfaces:**
- Consumes bridge summary fields `economy`, `fiscal_income`, and `fiscal_incomes`.
- Produces Chinese country/province labels showing both values.

- [ ] **Step 1: Add failing UI assertions**

Require country detail text to contain `经济` and `财政收入`, province information to contain both values, and province management summary to contain both values. Retain right-panel boundary assertions after advancing a turn.

- [ ] **Step 2: Update country rows and turn log**

Render current economic total and one-month fiscal income for every country. Sum `fiscal_incomes` in the turn result and label the event `财政收入`.

- [ ] **Step 3: Update province windows**

Render `经济：N` and `财政收入：N` from the province snapshot. Refresh through existing state refresh paths after turns, recruitment, research, occupation, peace, and load.

- [ ] **Step 4: Run all Godot tests**

Execute every `game/tests/*.gd` script. Expected: 13 tests, 0 failures, and stable layout boundaries.

- [ ] **Step 5: Commit UI changes**

```powershell
git add game/scripts game/tests
git commit -m "feat: display economy and fiscal income"
```

### Task 6: Update the Current Rules Handbook

**Files:**
- Modify: `docs/current-game-rules.md`

**Interfaces:**
- Consumes: Final verified implementation behavior.
- Produces: Updated authoritative current-rule baseline.

- [ ] **Step 1: Replace fixed economy rules**

Document both exact formulas, terrain coefficients, controller aggregation, monthly order, technology effects, recruitment coupling, and examples.

- [ ] **Step 2: Add priority logic warning**

Add a prominent warning that occupied provinces temporarily use the actual controller's economy technology and that resolving this is a priority logic issue for a later update.

- [ ] **Step 3: Update versions and history**

Change scenario/save schema references to 3 and add the implementation commit to the update history.

- [ ] **Step 4: Check documentation scope**

Run:

```powershell
rg -n "固定整数经济|economy.*JSON|结构版本2|当前未定义" docs/current-game-rules.md
git diff --check
```

Expected: no stale fixed-economy rule remains; undefined future occupation logic is clearly separated from current behavior.

- [ ] **Step 5: Commit the handbook update**

```powershell
git add docs/current-game-rules.md
git commit -m "docs: define fiscal economy rules"
```

### Task 7: Final Verification and Integration

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full C++ build and core test**

Run SCons and `province_core_tests.exe`. Expected: exit 0.

- [ ] **Step 2: Run all Godot tests and main-scene startup**

Run all 13 scripts and headless main scene. Expected: 0 failures and startup exit 0.

- [ ] **Step 3: Inspect final repository state**

Run `git diff --check`, `git status --short`, and inspect commits. Expected: clean feature branch.

- [ ] **Step 4: Integrate using the approved branch workflow**

Use `superpowers:finishing-a-development-branch`; do not touch unrelated main-worktree changes.
