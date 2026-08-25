# Monthly Order System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace instantaneous gameplay actions with a persisted fixed-month order queue, including new costs, maintenance, delayed projects, grouped combat, movement debt and automatic army consolidation.

**Architecture:** `GameState` owns typed pending orders and reservations. `CommandProcessor` creates/cancels orders during planning and delegates each one-month phase to a focused `MonthlyOrderSystem`; existing economy, population, movement, battle, army, road and technology systems remain authoritative for their formulas. Bridge and Godot expose only the human country's pending orders while AI writes through the same commands after settlement.

**Tech Stack:** C++20, SCons/MSVC, nlohmann JSON, Godot 4.6 GDExtension, GDScript.

**Spec:** `docs/superpowers/specs/2026-08-25-monthly-order-system-design.md`

## Global Constraints

- One turn is exactly one month; only `AdvanceTurnCommand{1}` is accepted.
- Core remains independent of Godot and owns every gameplay mutation and formula.
- Internal movement values remain half-point integers; attack surcharge is 4 half-points and defense cost is 2 half-points.
- Recruitment is 4 treasury per soldier; technology is `5000 * (current_level + 1)`.
- Existing user edits in the primary worktree must not be overwritten or committed.
- Every production behavior begins with a focused failing test and a recorded RED result.

---

### Task 1: Costs, maintenance and fixed one-month turns

**Files:**
- Create: `core/include/province/core/maintenance_system.hpp`
- Create: `core/src/maintenance_system.cpp`
- Modify: `core/include/province/core/army_system.hpp`
- Modify: `core/include/province/core/technology_system.hpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `core/include/province/core/game_event.hpp`
- Modify: `SConstruct`
- Test: `tests/core/core_smoke_test.cpp`
- Test: `tests/core/neutral_population_test.cpp`

**Interfaces:**
- Produces: `MonthlyMaintenanceReport MaintenanceSystem::resolve_month(GameState&) const` and `MaintenanceResolvedEvent`.
- Guarantees: normal treasury may become negative; hidden countries have zero maintenance.

- [ ] Add failing assertions for recruitment cost 4, technology cost multiplier 5, rejection of turn lengths other than 1, normal maintenance, debt and neutral exemption.
- [ ] Run `scripts/build.cmd` and verify RED on the new constants/maintenance behavior.
- [ ] Implement the constants, maintenance system and one-month validation; emit a monthly maintenance event after fiscal income.
- [ ] Run `scripts/build.cmd` and verify the focused and complete core suite is GREEN.
- [ ] Commit with `feat: add monthly army maintenance and fixed turns`.

### Task 2: Typed order state, reservation and cancellation

**Files:**
- Create: `core/include/province/core/game_order.hpp`
- Create: `core/include/province/core/order_system.hpp`
- Create: `core/src/order_system.cpp`
- Modify: `core/include/province/core/game_state.hpp`
- Modify: `core/src/game_state.cpp`
- Modify: `core/include/province/core/game_command.hpp`
- Modify: `core/include/province/core/game_event.hpp`
- Modify: `core/include/province/core/command_processor.hpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `SConstruct`
- Create: `tests/core/order_system_test.cpp`
- Modify: `tests/core/smoke_test_groups.hpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Produces: stable `OrderId`, `ArmyActionOrder`, `RecruitmentOrder`, `RoadConstructionOrder`, `ResearchOrder`, `CancelOrderCommand`, `GameState::orders()` and `OrderSystem::queue_*`/`cancel`.
- `ArmyActionOrder` stores `path`, `reserved_movement_half` and `is_attack`; project orders store paid cost and remaining months.

- [ ] Write tests that queue each order, prevent duplicate army/research/road orders, reserve money/population/movement, reject new paid projects in debt, and refund all eligible cancellations.
- [ ] Build and verify RED because order types and commands do not exist.
- [ ] Add state storage, validation and transactional queue/cancel implementations without executing projects.
- [ ] Build and verify all order tests GREEN; refactor duplicate reservation checks while keeping tests green.
- [ ] Commit with `feat: add persistent gameplay order queue`.

### Task 3: Reachable-path army orders and monthly movement resolution

**Files:**
- Create: `core/include/province/core/monthly_order_system.hpp`
- Create: `core/src/monthly_order_system.cpp`
- Modify: `core/include/province/core/movement_system.hpp`
- Modify: `core/src/movement_system.cpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `core/src/ai_system.cpp`
- Modify: `SConstruct`
- Modify: `tests/core/order_system_test.cpp`
- Modify: `tests/core/ai_smoke_test.cpp`

**Interfaces:**
- Produces: `MovementSystem::find_order_path`, `MovementSystem::path_cost_half`, and `MonthlyOrderSystem::resolve_movement`.
- Consumes Task 2 orders; execution never calls instantaneous public movement commands.

- [ ] Write failing tests for multi-edge friendly movement, enemy-only final step, route cost plus attack surcharge, one order per army, path revalidation, refunds, friendly conversion and hostile cancellation.
- [ ] Build and verify RED on missing range-order behavior.
- [ ] Implement deterministic Dijkstra path creation, reservation and ordinary-movement-first resolution; disable/remove multi-step instantaneous advance execution.
- [ ] Build and verify focused movement and AI tests GREEN.
- [ ] Commit with `feat: resolve queued army movement each month`.

### Task 4: Grouped delayed combat and defensive movement debt

**Files:**
- Modify: `core/include/province/core/battle_calculator.hpp`
- Modify: `core/src/battle_calculator.cpp`
- Modify: `core/include/province/core/battle_system.hpp`
- Modify: `core/src/battle_system.cpp`
- Modify: `core/src/monthly_order_system.cpp`
- Modify: `tests/core/battle_calculator_test.cpp`
- Modify: `tests/core/order_system_test.cpp`
- Modify: `tests/core/neutral_combat_test.cpp`

**Interfaces:**
- Produces: grouped attacker input and per-attacker proportional loss records while retaining existing stable IDs/display names.
- Monthly combat groups by `(attacking_country, target_province)` after ordinary movement.

- [ ] Write failing tests for two attackers combining strength, proportional attacker casualties/remainders, arrivals defending, withdrawals escaping, each defender paying 2 half-points down to -2, unopposed occupation and one attacking-country lock.
- [ ] Build and verify RED on grouped-attack expectations.
- [ ] Extend calculator/system and monthly resolution with deterministic grouping, loss allocation, retreat, occupation and refunds for invalid groups.
- [ ] Build and verify all battle and order tests GREEN.
- [ ] Commit with `feat: resolve grouped attacks from monthly orders`.

### Task 5: Delayed recruitment, roads, research and automatic consolidation

**Files:**
- Modify: `core/include/province/core/army_system.hpp`
- Modify: `core/src/army_system.cpp`
- Modify: `core/include/province/core/road_system.hpp`
- Modify: `core/src/road_system.cpp`
- Modify: `core/include/province/core/technology_system.hpp`
- Modify: `core/src/technology_system.cpp`
- Modify: `core/src/monthly_order_system.cpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `tests/core/order_system_test.cpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Produces completion-only system entry points that consume prepaid orders without charging twice.
- Research duration is `target_level + 1`; auto-merge runs after all project completions.

- [ ] Write failing tests for one-month recruitment/road completion, delayed technology levels 1 and 8, completion after military resolution, reserved-population deduction, invalidation refunds and deterministic repeated sub-1500 merging.
- [ ] Build and verify RED on delayed project/merge behavior.
- [ ] Implement prepaid completion paths, monthly project ticks, result events and automatic merge ordering.
- [ ] Build and verify full core suite GREEN.
- [ ] Commit with `feat: complete monthly projects and auto merge armies`.

### Task 6: AI planning after settlement

**Files:**
- Modify: `core/include/province/core/ai_system.hpp`
- Modify: `core/src/ai_system.cpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `tests/core/ai_smoke_test.cpp`
- Modify: `tests/core/order_system_test.cpp`

**Interfaces:**
- Produces AI orders for the following month only; consumes the same queue commands as the player.
- AI planning runs after auto-merge and never sees later human orders.

- [ ] Write failing tests proving AI actions are queued after settlement, do not execute in that settlement, and execute on the following month while obeying debt and target locks.
- [ ] Build and verify RED against current instantaneous AI.
- [ ] Replace instantaneous AI execution with post-settlement order planning and initialize first-month AI orders when enabling AI/loading a scenario.
- [ ] Build and verify AI and core suites GREEN.
- [ ] Commit with `feat: plan ai actions through monthly orders`.

### Task 7: Schema 7 persistence and validation

**Files:**
- Modify: `core/include/province/core/save_game.hpp`
- Modify: `core/src/save_game.cpp`
- Modify: `core/src/game_state.cpp`
- Modify: `tests/core/save_game_smoke_test.cpp`
- Modify: `tests/core/order_system_test.cpp`

**Interfaces:**
- Produces strict schema 7 JSON fields `next_order_sequence`, `orders` and every variant payload.
- Loaded orders restore reservations exactly and pass `GameState::validate()` without recharging.

- [ ] Write failing round-trip and malformed-save tests for all order variants, paths, progress, stable references, uniqueness and reserved resources; assert schema 6 rejection.
- [ ] Build and verify RED because schema 7 fields are absent.
- [ ] Implement serialization, strict parsing and cross-reference validation.
- [ ] Build and verify save/core suites GREEN.
- [ ] Commit with `feat: persist monthly orders in schema 7 saves`.

### Task 8: Bridge APIs and event dictionaries

**Files:**
- Modify: `bridge/src/province_bridge.hpp`
- Modify: `bridge/src/province_bridge.cpp`
- Modify: `bridge/src/province_bridge_bindings.cpp`
- Modify: `game/tests/army_bridge_smoke_test.gd`
- Modify: `game/tests/road_bridge_smoke_test.gd`
- Modify: `game/tests/technology_bridge_smoke_test.gd`
- Modify: `game/tests/save_game_bridge_smoke_test.gd`

**Interfaces:**
- Produces GDScript methods `get_pending_orders(country_id)`, `cancel_order(order_id)`, queued responses for recruit/road/research/move, and one-month-only `advance_turn()` behavior.
- Enemy orders are filtered out of human queries.

- [ ] Update Godot tests first to expect order IDs/status, delayed state changes, cancellation/refunds, grouped monthly battle reports and save/load progress.
- [ ] Build/import and run focused scripts to verify RED against old bridge responses.
- [ ] Bind order querying/cancellation and serialize every new monthly event/action in Chinese-ready dictionaries.
- [ ] Build, import assets and run the focused bridge tests GREEN.
- [ ] Commit with `feat: expose monthly orders through godot bridge`.

### Task 9: Fixed-month UI and order management

**Files:**
- Modify: `game/scenes/main/main.tscn`
- Modify: `game/scenes/ui/province_management_window.tscn`
- Modify: `game/scenes/ui/road_construction_window.tscn`
- Modify: `game/scripts/main.gd`
- Modify: `game/scripts/province_management_window.gd`
- Modify: `game/scripts/road_construction_window.gd`
- Modify: `game/scripts/ui/game_text_formatter.gd`
- Modify: `game/tests/main_layout_smoke_test.gd`
- Modify: `game/tests/province_management_window_component_smoke_test.gd`
- Modify: `game/tests/province_management_window_smoke_test.gd`
- Modify: `game/tests/road_construction_window_smoke_test.gd`

**Interfaces:**
- Consumes Task 8 dictionaries; produces a fixed one-month turn button, reachable-target selection, pending-order lists, cancellation buttons and project countdown text.

- [ ] Change UI tests first to require no month selector, fixed text, queued feedback, debt-disabled paid actions, pending order display/cancel and project remaining months.
- [ ] Run focused Godot tests and verify RED on missing nodes/text/state.
- [ ] Implement scene/script changes while preserving the dedicated workspace panel and non-overlap constraints.
- [ ] Run all focused UI tests and main layout test GREEN.
- [ ] Commit with `feat: add monthly order planning interface`.

### Task 10: Rules, structure docs and final verification

**Files:**
- Modify: `docs/current-game-rules.md`
- Modify: `docs/project-structure.md`
- Modify: `README.md`

**Interfaces:**
- Documents schema 7, exact formulas, phase order, cancellation/refund rules, bridge/UI behavior and known limitations.

- [ ] Update current rules and project structure from the approved spec and implemented interfaces; scan for obsolete instantaneous-action and multi-month-turn statements.
- [ ] Run `scripts/build.cmd` and require the complete C++ suite to pass.
- [ ] Import with Godot 4.6.3, run every `game/tests/*_test.gd`, start the main scene headlessly, and scan logs for `SCRIPT ERROR`, `push_error` and unexpected `ERROR:`.
- [ ] Run `git diff --check`, inspect the complete diff, confirm the primary worktree's pre-existing user edits remain untouched, and commit with `docs: document monthly order gameplay`.

