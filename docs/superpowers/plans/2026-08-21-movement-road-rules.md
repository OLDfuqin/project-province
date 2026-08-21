# Movement and Road Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the legacy movement and road technology rules with half-point army movement, military level 0–8 progression, and terrain-coefficient road eligibility/cost rules.

**Architecture:** Keep authoritative rules in the C++ core. Store movement points as integer half-point units (`movement_points_half`) in the core and save format, while bridge/UI summaries expose numeric points divided by two. Centralize military movement allowance and road terrain/cost calculations in movement/road systems so command execution, previews, AI and UI share one rule source.

**Tech Stack:** C++20, MSVC/SCons, Godot 4 GDExtension, GDScript smoke tests, JSON saves.

**Spec:** User-approved design in conversation on 2026-08-21.

## Global Constraints

- Base army movement cap is 6 points; base monthly grant is 2 points.
- Military technology is level 0–8; each level grants +0.5 monthly movement, and each four levels grants +1 cap.
- All newly created country technology levels are 0.
- Roads technology is level 0–4 and only affects road eligibility and construction discount.
- Terrain economic coefficients are plains 1.0, forest/hills 0.9, mountains 0.8.
- Road endpoint base costs are plains 300, forest/hills 500, mountains 700; endpoint costs are summed before discount.
- Existing user formatting-only changes in `game/scripts/main.gd` and `game/tests/army_bridge_smoke_test.gd` must not be overwritten or committed.

---

### Task 1: Core movement and technology rules

**Files:**
- Modify: `core/include/province/core/army.hpp`, `movement_system.hpp`, `technology.hpp`, `road_system.hpp`, `game_event.hpp`
- Modify: `core/src/movement_system.cpp`, `technology_system.cpp`, `road_system.cpp`, `game_state.cpp`
- Test: `tests/core/core_smoke_test.cpp`, `tests/core/save_game_smoke_test.cpp`

- [ ] Add failing core assertions for half-point monthly grants, cap 6/7/8 by military levels 0/4/8, military level 8 acceptance and level 9 rejection, roads level 4 acceptance and level 5 rejection, and terrain-based road prices/eligibility.
- [ ] Run `scripts/build.cmd` and `build/bin/province_core_tests.exe` and confirm the new assertions fail against the legacy rules.
- [ ] Replace integer movement storage with half-point units and centralize conversion constants; enforce the military and roads track-specific maximum levels.
- [ ] Implement capped monthly grants: `2 + military_level * 0.5`, limited by `6 + military_level / 4`; preserve accumulated points up to the cap.
- [ ] Implement terrain coefficient road eligibility and endpoint base cost sum, then apply road discount 0/10/20/30/50% for roads levels 0/1/2/3/4.
- [ ] Run core tests and confirm they pass.

### Task 2: Save format and bridge contract

**Files:**
- Modify: `core/src/save_game.cpp`, `core/include/province/core/save_game.hpp`, `bridge/src/province_bridge.cpp`, `bridge/src/province_bridge.hpp`
- Test: `tests/core/save_game_smoke_test.cpp`, `game/tests/save_game_bridge_smoke_test.gd`, `game/tests/technology_bridge_smoke_test.gd`, `game/tests/road_bridge_smoke_test.gd`, `game/tests/army_bridge_smoke_test.gd`

- [ ] Add failing save/bridge assertions for half-point round trips, schema migration, capped grants, new road costs, and technology maximum summaries.
- [ ] Run the focused tests and confirm failure.
- [ ] Upgrade save schema, serialize half-point movement explicitly, and migrate prior integer-point saves by multiplying movement points by two.
- [ ] Expose bridge summaries as numeric points (`movement_points`, `max_movement_points`, `monthly_movement_grant`) divided by two; expose road eligibility and discounted cost responses.
- [ ] Update bridge tests and run all focused Godot scripts.

### Task 3: UI previews and rules documentation

**Files:**
- Modify: `game/scripts/main.gd`, `game/scripts/province_management_window.gd`, `game/scripts/ui/strategy_panel_presenter.gd`, `game/scripts/road_construction_window.gd`, `game/scripts/province_map.gd`
- Test: `game/tests/province_management_window_component_smoke_test.gd`, `game/tests/province_management_window_smoke_test.gd`, `game/tests/road_construction_window_smoke_test.gd`, `game/tests/main_layout_smoke_test.gd`, `game/tests/map_smoke_test.gd`
- Modify: `docs/current-game-rules.md`, `docs/project-structure.md`

- [ ] Add failing UI assertions for half-point text and terrain/technology road estimates.
- [ ] Run focused Godot tests and confirm failure.
- [ ] Update movement display and path preview formatting to preserve `.5` values, and remove references to roads technology as monthly movement bonus.
- [ ] Update road construction estimate to use selected endpoint terrain and current road technology eligibility/discount.
- [ ] Update rules and file responsibility documentation with exact formulas and migration behavior.
- [ ] Run all C++ and Godot tests plus headless main startup.

### Task 4: Commit and integrate

- [ ] Run `git diff --check` and inspect status, excluding the two preserved formatting-only files.
- [ ] Commit focused core/save/bridge changes, UI changes, and documentation with clear messages.
- [ ] Fast-forward `main` from the feature branch without discarding preserved user changes.
- [ ] Run the complete verification suite on `main`.
- [ ] Push only commits completed within the prior-day automation window when authorized.
