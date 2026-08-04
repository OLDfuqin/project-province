# Terrain Economy Coefficient Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move terrain coefficient `T` into province economy calculation and make fiscal income exactly one percent of the resulting economy.

**Architecture:** Keep `EconomySystem` as the single formula owner. `province_economy` combines population, controller economy technology, and terrain in one overflow-safe integer calculation; `province_fiscal_income` derives only from that returned economy. Bridge and UI continue consuming these core methods without duplicating coefficients.

**Tech Stack:** C++20 simulation core, Godot 4.6.3 GDExtension, GDScript smoke tests, SCons, Markdown rules handbook.

## Global Constraints

- Apply terrain multipliers: plains `1.0`, forest `0.9`, hills `0.9`, mountains `0.8`.
- Calculate economy once as `floor(P × (100 + 10 × L) × R / 10000)`.
- Do not perform intermediate rounding between technology and terrain multipliers.
- Calculate fiscal income only as `floor(E / 100)`.
- Do not change scenario or save schema version 3.
- Continue using actual controller economy technology for occupied provinces.
- Preserve the user's unrelated `game/scripts/main.gd` formatting change in the main worktree.

---

### Task 1: Move Terrain Coefficient Into Core Economy

**Files:**
- Modify: `tests/core/core_smoke_test.cpp`
- Modify: `core/src/economy_system.cpp`

**Interfaces:**
- Consumes: `EconomySystem::province_economy(const GameState&, const ProvinceId&)` and `province_fiscal_income(...)`.
- Produces: terrain-adjusted economy and one-percent fiscal income through the same public methods.

- [ ] **Step 1: Write failing core expectations**

Update terrain assertions to require:

```cpp
EconomySystem::province_economy(state, ProvinceId{"z_gv_1"}) == 27'000;
EconomySystem::province_economy(state, ProvinceId{"z_wm_2"}) == 22'500;
EconomySystem::province_economy(state, ProvinceId{"z_nr_2"}) == 20'000;
```

Add a custom hills province with population `10'029`, controller economy technology level `1`, and assert economy `9'928` plus fiscal income `99`. This distinguishes one final rounding from the incorrect staged result `9'927`.

- [ ] **Step 2: Run the core test and verify RED**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q
& '.\build\bin\province_core_tests.exe'
```

Expected: build succeeds and the test fails because non-plains economy still ignores terrain.

- [ ] **Step 3: Implement the minimal formula change**

Rename the private helper to express an economy coefficient and change the methods to the equivalent integer calculation:

```cpp
const std::int64_t combined_numerator =
    (100 + 10 * technology->economy_level) * terrain_economy_numerator(province->terrain);
return scaled_floor(province->population, combined_numerator, 10'000);
```

Then derive fiscal income only from economy:

```cpp
return province_economy(state, province_id) / 100;
```

- [ ] **Step 4: Run the core test and verify GREEN**

Run the same SCons and core test commands. Expected: `Project Province core 0.1.0-dev smoke test passed`.

- [ ] **Step 5: Commit the core behavior**

```powershell
git add tests/core/core_smoke_test.cpp core/src/economy_system.cpp
git commit -m "fix: apply terrain coefficient to economy"
```

---

### Task 2: Update Bridge and Interface Expectations

**Files:**
- Modify: `game/tests/army_bridge_smoke_test.gd`
- Modify: `game/tests/main_layout_smoke_test.gd`

**Interfaces:**
- Consumes: existing bridge fields `economy` and `fiscal_income`.
- Produces: regression expectations for terrain-adjusted country economy totals without changing bridge field names.

- [ ] **Step 1: Write failing bridge and layout expectations**

Change Auroria's initial country economy expectation from `370000` to `362500`. After recruiting1000 population from plains Northreach, expect `361500`. Change the first main-page country label expectation to contain `362500`. Keep fiscal expectations `3625` before recruitment and `3615` after recruitment.

- [ ] **Step 2: Run focused Godot tests and verify RED against the old DLL**

Run `army_bridge_smoke_test.gd` and `main_layout_smoke_test.gd` headlessly before rebuilding the bridge. Expected: both reject the old `370000` summary.

- [ ] **Step 3: Rebuild the GDExtension**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q
```

The bridge requires no formula code change because it already delegates to `EconomySystem`.

- [ ] **Step 4: Run focused Godot tests and verify GREEN**

Run both focused tests again. Expected: both pass and layout boundaries remain unchanged.

- [ ] **Step 5: Commit interface expectations**

```powershell
git add game/tests/army_bridge_smoke_test.gd game/tests/main_layout_smoke_test.gd
git commit -m "test: update terrain-adjusted economy summaries"
```

---

### Task 3: Update Rules and Verify the Complete Game

**Files:**
- Modify: `docs/current-game-rules.md`

**Interfaces:**
- Consumes: the implemented core formulas and current country totals.
- Produces: the continuously maintained authoritative gameplay rules.

- [ ] **Step 1: Update the rules handbook**

Replace “地形财政系数” with “地形经济系数”. Document:

```text
E = floor(P × (100 + 10 × L) × R / 10000)
F = floor(E / 100)
```

Update the four country economy totals to `362500`, `357000`, `380000`, and `359500`; keep fiscal totals `3625`, `3570`, `3800`, and `3595`. Retain the prominent occupied-province technology warning.

- [ ] **Step 2: Scan for obsolete formula wording**

Run:

```powershell
rg -n "地形财政系数|F = floor\(E × 1% × T\)|经济总量为370000" docs/current-game-rules.md
```

Expected: no matches.

- [ ] **Step 3: Run complete verification**

Run SCons, `province_core_tests.exe`, all 13 `game/tests/*_test.gd` scripts, and a two-frame headless main-scene startup. Expected: every command exits0.

- [ ] **Step 4: Commit documentation**

```powershell
git add docs/current-game-rules.md
git commit -m "docs: define terrain as an economy coefficient"
```

- [ ] **Step 5: Review final diff**

Run `git diff main...HEAD --check`, inspect `git diff --stat main...HEAD`, and confirm the branch contains only the design, plan, core formula, tests, and rules documentation.
