# Current Game Rules Handbook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a developer-facing handbook that precisely documents every gameplay rule currently implemented on `main`.

**Architecture:** Audit rules from the C++ simulation core outward, using tests and the Godot bridge to verify observable behavior. Consolidate the result into one living Markdown file, with formulas, ordering, validation conditions, rounding rules, examples, provenance, and a change log.

**Tech Stack:** Markdown, C++20 simulation core, Godot 4.6.3, GDExtension, JSON scenario data, Git.

## Global Constraints

- Create the formal handbook at `docs/current-game-rules.md`.
- Document only behavior implemented on the current `main` branch.
- Do not modify gameplay code, formulas, constants, or scenario values.
- Mark behavior not defined by code as `当前未定义`; do not infer intended behavior.
- Resolve conflicts in favor of the C++ simulation core, followed by automated tests, bridge behavior, UI behavior, and historical documents.
- Include the core version, audited Git commit, audit date, and update history.

---

### Task 1: Audit Implemented Rules

**Files:**
- Read: `core/include/province/core/*.hpp`
- Read: `core/src/*.cpp`
- Read: `bridge/src/province_bridge.cpp`
- Read: `game/data/*.json`
- Read: `game/scripts/*.gd`
- Read: `game/tests/*.gd`
- Read: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Consumes: Current `main` branch source and tests.
- Produces: Verified rule notes covering state fields, constants, formulas, execution order, validation, and observable results.

- [ ] **Step 1: Record the audit baseline**

Run:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' rev-parse HEAD
rg -n "project_version|version" core game/project.godot
```

Expected: one Git commit hash and the current core version string.

- [ ] **Step 2: Inventory scenario and state data**

Run:

```powershell
Get-Content game/data/countries.json -Encoding UTF8
Get-Content game/data/provinces.json -Encoding UTF8
Get-Content game/data/map_geometry.json -Encoding UTF8
Get-Content game/data/technologies.json -Encoding UTF8
Get-Content core/include/province/core/game_state.hpp -Encoding UTF8
```

Record the four countries, 32 provinces, terrain values, ownership/control distinction, armies, roads, wars, technologies, and clock state.

- [ ] **Step 3: Audit monthly processing order and arithmetic**

Run:

```powershell
Get-Content core/src/command_processor.cpp -Encoding UTF8
Get-Content core/src/economy_system.cpp -Encoding UTF8
Get-Content core/src/population_system.cpp -Encoding UTF8
Get-Content core/src/movement_system.cpp -Encoding UTF8
```

Record exact month-by-month ordering, integer division behavior, growth remainders, caps, technology modifiers, movement grants, AI timing, and stored advance-plan execution.

- [ ] **Step 4: Audit player commands and rejection conditions**

Run:

```powershell
Get-Content core/include/province/core/game_command.hpp -Encoding UTF8
Get-Content core/src/army_system.cpp -Encoding UTF8
Get-Content core/src/road_system.cpp -Encoding UTF8
Get-Content core/src/technology_system.cpp -Encoding UTF8
Get-Content core/src/peace_system.cpp -Encoding UTF8
```

Record preconditions and state changes for advancing time, recruiting, moving, building roads, researching, declaring war, and making peace.

- [ ] **Step 5: Audit combat, AI, victory, save/load, and bridge-only advance plans**

Run:

```powershell
Get-Content core/src/battle_system.cpp -Encoding UTF8
Get-Content core/src/ai_system.cpp -Encoding UTF8
Get-Content core/src/game_status.cpp -Encoding UTF8
Get-Content core/src/save_game.cpp -Encoding UTF8
Get-Content bridge/src/province_bridge.cpp -Encoding UTF8
```

Record battle strength, casualties, retreat, occupation, AI thresholds and decision order, victory/defeat states, save schema behavior, pathfinding, and advance strategies.

### Task 2: Write and Verify the Handbook

**Files:**
- Create: `docs/current-game-rules.md`
- Read: `docs/superpowers/specs/2026-08-04-current-game-rules-document-design.md`

**Interfaces:**
- Consumes: Verified rule notes from Task 1.
- Produces: A single authoritative current-implementation handbook.

- [ ] **Step 1: Create the complete handbook**

Write `docs/current-game-rules.md` with these sections:

```markdown
# Project Province 现行游戏规则手册
## 文档信息
## 游戏世界与当前剧本
## 核心数据、单位与稳定 ID
## 回合、日期与月度结算顺序
## 地区法理归属、控制与占领
## 总人口与可招募士兵
## 地区经济与国家国库
## 科技等级、费用与效果
## 道路建设
## 军队招募
## 移动力、寻路与调动
## 自动推进计划与策略
## 宣战、战争状态与领土通行
## 战斗、伤亡、撤退、歼灭与占领
## 议和与领土结算
## AI 月度决策
## 胜利、失败与国家存续
## 保存与读取
## 当前规则边界与未定义行为
## 文档更新记录
```

Every numeric system must include its formula, rounding behavior, timing, modifiers, rejection conditions, and at least one manually checkable example.

- [ ] **Step 2: Check scope and ambiguity**

Run:

```powershell
rg -n "TODO|TBD|计划实现|未来将|可能会|大概|应该" docs/current-game-rules.md
rg -n "当前未定义" docs/current-game-rules.md
```

Expected: no placeholders or speculative future rules; every undefined behavior is explicitly labeled.

- [ ] **Step 3: Verify repository behavior remains unchanged**

Run:

```powershell
.\scripts\build.cmd
$godot = 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
Get-ChildItem game/tests/*.gd | Sort-Object Name | ForEach-Object {
    & $godot --headless --path game --script ("res://tests/" + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Godot test failed: $($_.Name)" }
}
```

Expected: the C++ core test and all 13 Godot tests pass.

- [ ] **Step 4: Review the final diff**

Run:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' diff --check
& 'C:\Program Files\Git\cmd\git.exe' status --short
& 'C:\Program Files\Git\cmd\git.exe' diff -- docs/current-game-rules.md
```

Expected: the handbook is the only new implementation deliverable; unrelated local changes remain unstaged.

- [ ] **Step 5: Commit the handbook**

Run:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add -- docs/current-game-rules.md
& 'C:\Program Files\Git\cmd\git.exe' commit -m "docs: document current gameplay rules"
```

Expected: one documentation-only commit.
