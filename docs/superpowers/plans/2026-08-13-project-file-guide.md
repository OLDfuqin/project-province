# Project File Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the existing project structure guide into a continuously maintained directory and per-file responsibility reference.

**Architecture:** Keep `docs/project-structure.md` as the single authoritative structure guide. Derive its inventory from Git-tracked files and the current build configuration, while separating source files from generated and local-only directories.

**Tech Stack:** Markdown, Git, PowerShell, ripgrep

## Global Constraints

- Do not change gameplay, source code, scenes, data, or build behavior.
- Preserve the user's existing uncommitted `game/scripts/main.gd` change.
- Write UTF-8 Chinese documentation.
- Treat `docs/current-game-rules.md` as the rules authority and `docs/project-structure.md` as the structure authority.

---

### Task 1: Expand the project structure guide

**Files:**
- Modify: `docs/project-structure.md`

**Interfaces:**
- Consumes: Git tracked-file inventory, `SConstruct`, `.gitignore`, `.gitmodules`, and current source declarations.
- Produces: A directory-level and file-level navigation guide for contributors.

- [ ] **Step 1: Inventory the repository**

Run:

```powershell
git ls-files
rg -n "^(class|struct|enum class)|^class_name|^extends" core/include bridge/src game/scripts
```

Expected: lists every tracked file and the principal C++/GDScript units.

- [ ] **Step 2: Rewrite the formal guide**

Document the runtime dependency direction, root entries, every source/data/scene/test/script file, generated paths, common modification locations, and maintenance rules in `docs/project-structure.md`.

- [ ] **Step 3: Verify tracked-file coverage and encoding**

Run:

```powershell
Get-Content -Raw -Encoding utf8 docs/project-structure.md | Out-Null
git diff --check -- docs/project-structure.md
git diff --stat -- docs/project-structure.md
```

Expected: UTF-8 read succeeds, `git diff --check` produces no errors, and only the intended documentation is changed.

- [ ] **Step 4: Review repository status**

Run:

```powershell
git status --short
```

Expected: documentation changes are listed alongside the preserved pre-existing `game/scripts/main.gd` modification.
