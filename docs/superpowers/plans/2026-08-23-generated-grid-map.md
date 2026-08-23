# Generated 9x9 Grid Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed 32-province scenario with a newly randomized 9x9 grid that produces four 13-province corner countries, four merged capitals, 17 defended unowned provinces, stored base economy, and a matching Godot map.

**Architecture:** Parse one shared grid-layout JSON into a small C++ layout model, use an injected integer random source to generate temporary cells, and assemble a validated 69-province `GameState`. Keep simulation rules in C++; Godot reads the same layout JSON only to construct polygons and renders state supplied by the bridge.

**Tech Stack:** C++20 simulation core, nlohmann/json, SCons/MSVC, Godot 4.6 GDExtension, GDScript smoke tests, Markdown rules and structure documentation.

**Spec:** `docs/superpowers/specs/2026-08-23-generated-grid-map-design.md`

## Global Constraints

- Logical coordinates run from `(1,1)` at bottom-left to `(9,9)` at top-right; only shared edges create adjacency.
- Auroria is bottom-left, Caelus bottom-right, Solmere top-left, and Verdantia top-right.
- Each country starts from a 4x4 corner, merges its central 2x2 cells into one capital, and therefore owns one capital plus 12 cities.
- Every cell with `x=5` or `y=5` is unowned; there are exactly 17 such cells and exactly 69 final provinces.
- Generation follows alternating left-to-right and right-to-left rows; `(1,1)` is fixed plains.
- Terrain propagation uses hidden base relief, averaged integer weights from already-generated edge neighbors, followed by an independent 50% forest overlay on hills or mountains.
- Initial population is chosen uniformly from the four exact values assigned to the visible terrain; initial recruitable population is `floor(population/100)` except in unowned provinces, where it is zero.
- `Province::base_economy` is stored; normal-cell initial base economy is `floor(population*T)` and a capital initially sums the four source values.
- Capital movement, road, and economy parameters equal plains; capital defense bonus is 50%.
- The hidden neutral country is excluded from player, diplomacy, AI, fiscal, status, and country-summary interfaces; its armies never move or attack.
- An unowned province keeps population fixed, diverts monthly 0.1% population growth into its sole neutral guard, and produces no fiscal income.
- Normal countries may attack neutral guards without declaring war; victory transfers legal ownership and control immediately, while mutual destruction leaves the province unowned.
- Every new game regenerates; saves persist final generated state and never persist RNG seed or generator state.
- Save schema 6 rejects all old 32-province saves instead of migrating them.
- Preserve the existing unrelated whitespace-only changes in `game/scripts/main.gd` and `game/tests/army_bridge_smoke_test.gd`; never stage them unless a task makes a reviewed semantic edit to that file.

---

### Task 1: Stored base economy and capital terrain primitives

**Files:**
- Modify: `core/include/province/core/province.hpp`
- Modify: `core/include/province/core/country.hpp`
- Modify: `core/include/province/core/terrain.hpp`
- Modify: `core/include/province/core/road_system.hpp`
- Modify: `core/src/battle_calculator.cpp`
- Modify: `core/src/economy_system.cpp`
- Modify: `core/src/scenario_loader.cpp`
- Modify: `core/src/save_game.cpp`
- Modify: `tests/core/battle_calculator_test.cpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Produces: `Province::base_economy: std::int64_t`
- Produces: `Country::hidden: bool`
- Produces: `TerrainType::capital`
- Produces: `terrain_economy_percent(TerrainType) -> std::int32_t`
- Produces: `terrain_road_endpoint_cost(TerrainType) -> std::int64_t`
- Consumes later: generation, population adjustment, road validation, battle defense, persistence, and bridge summaries use these definitions.

- [ ] **Step 1: Write failing model and economy assertions**

In `core_smoke_test.cpp`, create a two-country state with a plains province whose population is `120000` but whose `base_economy` is `75000`. Assert economy level 0 returns `75000`, economy level 2 returns `90000`, and fiscal income returns `900`. Add direct assertions for capital helpers:

```cpp
if (province::core::terrain_economy_percent(TerrainType::capital) != 100 ||
    province::core::terrain_movement_cost(TerrainType::capital) != 2 ||
    province::core::terrain_road_endpoint_cost(TerrainType::capital) != 300 ||
    province::core::terrain_defense_bonus(TerrainType::capital) != 50 ||
    std::string{province::core::terrain_name(TerrainType::capital)} != "capital" ||
    province::core::terrain_from_string("capital") != TerrainType::capital) {
    std::cerr << "Capital terrain parameters failed\n";
    return 1;
}
```

- [ ] **Step 2: Run the core test and verify RED**

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q build\bin\province_core_tests.exe
```

Expected: compilation fails because `base_economy`, `hidden`, `capital`, and the shared terrain helpers do not exist.

- [ ] **Step 3: Extend the state primitives**

Append `base_economy` after `recruitable_population` in `Province`, append `bool hidden{false};` to `Country`, and extend terrain helpers with exact integer values:

```cpp
enum class TerrainType : std::uint8_t {
    plains, forest, hills, mountains, capital
};

inline std::int32_t terrain_economy_percent(TerrainType value) noexcept {
    switch (value) {
    case TerrainType::plains:
    case TerrainType::capital: return 100;
    case TerrainType::forest:
    case TerrainType::hills: return 90;
    case TerrainType::mountains: return 80;
    }
    return 100;
}

inline std::int64_t terrain_road_endpoint_cost(TerrainType value) noexcept {
    switch (terrain_economy_percent(value)) {
    case 100: return 300;
    case 90: return 500;
    default: return 700;
    }
}
```

Handle `capital` explicitly in `terrain_from_string`, `terrain_name`, `terrain_movement_cost`, and `terrain_defense_bonus`.

Replace `RoadSystem`'s duplicate terrain coefficient and endpoint-cost branches with `terrain_economy_percent` and `terrain_road_endpoint_cost`; capital must therefore require the same road level and base endpoint cost as plains. Extend `BattleCalculator`'s accepted defense bonuses from `{0,10,20,30}` to `{0,10,20,30,50}` and add a fixed-roll assertion that a 50% bonus produces `floor(base_strength*150/100)`.

- [ ] **Step 4: Make economy derive from stored base economy**

Delete the private terrain coefficient calculation in `economy_system.cpp`. Calculate only the technology multiplier:

```cpp
const std::int64_t technology_percent = 100 + 10 * technology->economy_level;
return scaled_floor(province->base_economy, technology_percent, 100);
```

Keep fiscal income as integer `province_economy(...) / 100`.

- [ ] **Step 5: Update existing aggregate initializers and run GREEN**

For every existing `Province{...}` aggregate in core tests and loaders, insert a base-economy value consistent with the test's prior expected economy. Until schema 6 is introduced in Task 7, the schema-5 loader derives this new in-memory field once from loaded population and terrain, and the static scenario loader does the same after parsing terrain. Do not serialize `base_economy` into schema 5. For every `Country{...}` aggregate, explicitly set `hidden` only where needed or rely on its default member initializer when construction permits.

Run:

```powershell
& 'C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd' -Q build\bin\province_core_tests.exe
& .\build\bin\province_core_tests.exe
```

Expected: build succeeds and the core test executable exits 0.

- [ ] **Step 6: Commit**

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/province.hpp core/include/province/core/country.hpp core/include/province/core/terrain.hpp core/include/province/core/road_system.hpp core/src/battle_calculator.cpp core/src/economy_system.cpp core/src/scenario_loader.cpp core/src/save_game.cpp tests/core/battle_calculator_test.cpp tests/core/core_smoke_test.cpp
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: store province base economy"
```

---

### Task 2: Shared grid-layout data and strict parser

**Files:**
- Create: `core/include/province/core/grid_map_layout.hpp`
- Create: `core/src/grid_map_layout.cpp`
- Create: `game/data/grid_map_layout.json`
- Create: `tests/core/grid_map_layout_test.cpp`
- Modify: `tests/core/smoke_test_groups.hpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Produces: `GridCoordinate`, `CountryGridPlacement`, and `GridMapLayout`
- Produces: `GridMapLayoutLoader::load(const std::filesystem::path&) -> GridMapLayout`
- Produces: layout ID `generated_grid_v1`, dimensions `9x9`, display cell size `80`, four placements, and four capital-cell groups.
- Consumes later: the C++ scenario generator and GDScript polygon generator read the same JSON contract.

- [ ] **Step 1: Add a failing layout test group**

Declare and call `run_grid_map_layout_tests()`. Its test must load `game/data/grid_map_layout.json` and assert:

```cpp
const GridMapLayout layout = GridMapLayoutLoader::load("game/data/grid_map_layout.json");
if (layout.layout_id != "generated_grid_v1" ||
    layout.width != 9 || layout.height != 9 || layout.cell_size != 80 ||
    layout.countries.size() != 4) return false;

const CountryGridPlacement& auroria = layout.countries.at(0);
if (auroria.country_id != CountryId{"auroria"} ||
    auroria.minimum != GridCoordinate{1, 1} ||
    auroria.maximum != GridCoordinate{4, 4} ||
    auroria.capital_cells.size() != 4) return false;
```

Copy the valid document to temporary files and test rejection of: duplicate country ID, coordinate outside `1..9`, overlapping country bounds, a capital group that is not a 2x2 square, a country range containing a row-5 or column-5 cell, and a layout whose unowned cross is not exactly 17 cells.

- [ ] **Step 2: Run and verify RED**

Run the SCons test target. Expected: missing `grid_map_layout.hpp` and loader symbols.

- [ ] **Step 3: Define the layout contract**

Use these focused value types:

```cpp
struct GridCoordinate final {
    std::int32_t x{};
    std::int32_t y{};
    auto operator<=>(const GridCoordinate&) const = default;
};

struct CountryGridPlacement final {
    CountryId country_id;
    GridCoordinate minimum;
    GridCoordinate maximum;
    std::vector<GridCoordinate> capital_cells;
};

struct GridMapLayout final {
    std::string layout_id;
    std::int32_t width{};
    std::int32_t height{};
    std::int32_t cell_size{};
    std::vector<CountryGridPlacement> countries;
};
```

The loader must parse with nlohmann/json, wrap parse/type failures in `DataLoadError`, and validate the complete layout before returning it.

- [ ] **Step 4: Add the authoritative JSON**

Create this layout data without gameplay population or terrain fields:

```json
{
  "schema_version": 1,
  "layout_id": "generated_grid_v1",
  "width": 9,
  "height": 9,
  "cell_size": 80,
  "countries": [
    {"id":"auroria","minimum":[1,1],"maximum":[4,4],"capital_cells":[[2,2],[3,2],[2,3],[3,3]]},
    {"id":"caelus","minimum":[6,1],"maximum":[9,4],"capital_cells":[[7,2],[8,2],[7,3],[8,3]]},
    {"id":"solmere","minimum":[1,6],"maximum":[4,9],"capital_cells":[[2,7],[3,7],[2,8],[3,8]]},
    {"id":"verdantia","minimum":[6,6],"maximum":[9,9],"capital_cells":[[7,7],[8,7],[7,8],[8,8]]}
  ]
}
```

- [ ] **Step 5: Run GREEN and commit**

Run the core build and executable. Then commit only the parser, layout data, and tests:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/grid_map_layout.hpp core/src/grid_map_layout.cpp game/data/grid_map_layout.json tests/core/grid_map_layout_test.cpp tests/core/smoke_test_groups.hpp tests/core/core_smoke_test.cpp
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: define generated grid layout"
```

---

### Task 3: Deterministic cell terrain and population generator

**Files:**
- Create: `core/include/province/core/map_cell_generator.hpp`
- Create: `core/src/map_cell_generator.cpp`
- Create: `tests/core/map_cell_generator_test.cpp`
- Modify: `tests/core/smoke_test_groups.hpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Produces: `BaseRelief::{plains, hills, mountains}`
- Produces: `GeneratedMapCell { coordinate, base_relief, terrain, population, base_economy }`
- Produces: `MapCellGenerator::generate(const GridMapLayout&, RandomIndexSource) -> std::vector<GeneratedMapCell>`
- Produces: `using RandomIndexSource = std::function<std::uint32_t(std::uint32_t exclusive_upper_bound)>`
- Consumes later: Task 4 converts the 81 temporary cells into final provinces.

- [ ] **Step 1: Write fixed-sequence generator tests**

Use a callback that records every `exclusive_upper_bound` and returns queued values. Test these exact facts:

- all 81 coordinates occur once in snake order;
- indices `0..8` are `(1,1)..(9,1)`, indices `9..17` are `(9,2)..(1,2)`, and the last cell is `(9,9)`;
- `(1,1)` consumes no relief or forest roll and is plains;
- a plains parent uses relief weights `{50,50,0}`;
- a hills parent uses `{40,30,30}` and a mountains parent `{0,50,50}`;
- plains plus mountains produces `{25,50,25}`;
- a generated forest retains its hidden hills or mountains base relief for the next cell;
- forest overlay consumes `random(2)` only for hills or mountains;
- population consumes `random(4)` and maps index `0..3` to the four exact terrain values;
- every generated base economy equals `population * terrain_economy_percent(terrain) / 100`.

Add rejection tests for a callback returning `exclusive_upper_bound` or greater and for an empty callback.

- [ ] **Step 2: Run and verify RED**

Run the core SCons target. Expected: missing map-cell generator types.

- [ ] **Step 3: Implement integer-only weighted selection**

Keep probability operations private and integer-valued:

```cpp
struct ReliefWeights { std::uint32_t plains; std::uint32_t hills; std::uint32_t mountains; };

ReliefWeights parent_weights(BaseRelief relief);
ReliefWeights average(ReliefWeights first, ReliefWeights second);
BaseRelief choose_relief(ReliefWeights weights, const RandomIndexSource& random);
```

Call `random(sum_of_weights)` and select by cumulative half-open ranges. Never use floating-point probability comparisons.

- [ ] **Step 4: Implement snake traversal and visible terrain**

For each coordinate, collect only already-generated north/south/east/west neighbors from a `std::map<GridCoordinate, GeneratedMapCell>`. Average one or two parent distributions, choose base relief, then apply `random(2)==1` as forest only when base relief is hills or mountains. Select population by visible terrain and calculate base economy with the shared percent helper.

- [ ] **Step 5: Run GREEN and commit**

Run the core build/executable and commit:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/map_cell_generator.hpp core/src/map_cell_generator.cpp tests/core/map_cell_generator_test.cpp tests/core/smoke_test_groups.hpp tests/core/core_smoke_test.cpp
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: generate random map cells"
```

---

### Task 4: Assemble the 69-province scenario and initial neutral guards

**Files:**
- Create: `core/include/province/core/map_scenario_generator.hpp`
- Create: `core/src/map_scenario_generator.cpp`
- Create: `tests/core/map_scenario_generator_test.cpp`
- Modify: `core/include/province/core/game_state.hpp`
- Modify: `core/src/game_state.cpp`
- Modify: `core/include/province/core/scenario_loader.hpp`
- Modify: `core/src/scenario_loader.cpp`
- Modify: `tests/core/smoke_test_groups.hpp`
- Modify: `tests/core/core_smoke_test.cpp`
- Modify: `tests/core/ai_smoke_test.cpp`
- Modify: `tests/core/save_game_smoke_test.cpp`
- Modify: `game/data/countries.json`

**Interfaces:**
- Produces: `GameState::map_layout_id() -> const std::string&`
- Produces: `MapScenarioGenerator::generate(GameState, const GridMapLayout&, RandomIndexSource) -> GameState`
- Produces: `ScenarioLoader::load(path, clock, RandomIndexSource = {}) -> GameState`
- Produces: stable neutral ID `CountryId{"neutral"}` and generated province/capital IDs from the spec.
- Consumes later: bridge new-game loading, neutral monthly rules, neutral combat, and save schema 6.

- [ ] **Step 1: Write failing final-state tests**

Generate with a callback that always returns `0` and assert:

```cpp
if (state.map_layout_id() != "generated_grid_v1" ||
    state.province_count() != 69 || state.country_count() != 5 ||
    state.find_country(CountryId{"neutral"}) == nullptr ||
    !state.find_country(CountryId{"neutral"})->hidden ||
    state.army_count() != 17) return false;
```

Also assert each visible country owns 13 provinces, neutral owns 17, normal cities use `cell_x_y`, capital IDs and Chinese names are exact, each neutral province has one neutral army of `population/100`, and every neutral recruitable population is zero.

Assert all five country technology records exist and start at economy/military/roads level `0`; the hidden neutral record must remain fixed at zero throughout later command tests.

For `capital_auroria`, assert terrain is capital, population/recruitable/base economy equal sums from source cells computed by a parallel `MapCellGenerator` run with an identical fixed sequence, and neighbors are the sorted unique exterior neighbors. Assert all 69 neighbor lists are symmetric and contain no removed capital cell IDs.

- [ ] **Step 2: Run and verify RED**

Run the core test target. Expected: missing scenario generator and layout-state APIs.

- [ ] **Step 3: Add map identity and hidden neutral state**

Store `map_layout_id_` in `GameState`, expose a const getter, and grant `MapScenarioGenerator`/`SaveGameSerializer` friend access or a narrow setter used only during complete state creation/loading. Add the neutral country exactly once:

```cpp
Country{
    CountryId{"neutral"}, "中立守军", 0x596579, 0, "中", true
}
```

Normal countries loaded from JSON remain `hidden=false`; all technology levels initialize to zero through `GameState::add_country`.

- [ ] **Step 4: Assemble cities, capitals, and adjacency**

Build a `GridCoordinate -> ProvinceId` lookup after assigning each physical cell either its `cell_x_y` ID or its country's capital ID. Create one final province per unique ID; use checked `int64_t` addition to aggregate capital population, recruitable population, and base economy. Sum and normalize population-growth remainders by the population-system denominator (all are zero in a new game). Generate adjacency by scanning the four edge offsets from every physical cell. Use sets to remove capital self-edges and duplicate edges before writing sorted vectors. Any overflow or invalid lookup throws before the by-value temporary state is returned, so no partial scenario reaches the caller.

- [ ] **Step 5: Create initial neutral guards and validate invariants**

Set neutral province owner to `neutral`, recruitable to zero, and create one neutral army with `population/100`. Before returning the initial state, `MapScenarioGenerator` must verify 69 provinces, four visible countries with 13 provinces each, 17 neutral provinces, four capitals, and 17 initial guards. Extend runtime `GameState::validate()` only with invariants that remain true after conquest and save/load: layout ID, 69 stable province IDs, five country records with exactly one hidden neutral record, four capital terrains, symmetric adjacency, no neutral army outside a neutral-owned province, and no more than one neutral army per neutral-owned province. Do not require 17 currently neutral owners after play begins.

- [ ] **Step 6: Replace static province loading**

Keep `countries.json` as the four-country definition but set all starting technologies implicitly to zero. Change `ScenarioLoader::load` to:

```cpp
GameState state{std::move(initial_clock)};
load_countries(state, data_directory / "countries.json");
const GridMapLayout layout = GridMapLayoutLoader::load(data_directory / "grid_map_layout.json");
return MapScenarioGenerator::generate(std::move(state), layout, std::move(random_index));
```

When no callback is supplied, create a `std::mt19937_64` seeded from `std::random_device` and return a uniform integer in `[0, exclusive_upper_bound-1]`.

- [ ] **Step 7: Run GREEN and commit**

Before running the combined executable, replace old scenario-ID assertions in `core_smoke_test.cpp` with generated IDs and inject a fixed random-index callback into every `ScenarioLoader::load` call. Keep `ai_smoke_test.cpp` focused on a small explicitly constructed all-normal state until neutral hostility is introduced in Task 6. Likewise, make the schema-5 save test construct a small state with an empty `map_layout_id` and no hidden country; Task 7 replaces it with a generated schema-6 round trip. These temporary fixtures preserve the independent review boundary without pretending schema 5 can represent the new map.

Run the core build and executable, then commit the complete scenario assembly:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/map_scenario_generator.hpp core/src/map_scenario_generator.cpp core/include/province/core/game_state.hpp core/src/game_state.cpp core/include/province/core/scenario_loader.hpp core/src/scenario_loader.cpp tests/core/map_scenario_generator_test.cpp tests/core/smoke_test_groups.hpp tests/core/core_smoke_test.cpp tests/core/ai_smoke_test.cpp tests/core/save_game_smoke_test.cpp game/data/countries.json
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: assemble generated grid scenario"
```

---

### Task 5: Population-to-economy synchronization and neutral monthly growth

**Files:**
- Modify: `core/include/province/core/population_system.hpp`
- Modify: `core/src/population_system.cpp`
- Modify: `core/src/army_system.cpp`
- Modify: `core/src/economy_system.cpp`
- Create: `tests/core/neutral_population_test.cpp`
- Modify: `tests/core/smoke_test_groups.hpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Produces: `PopulationSystem::apply_population_delta(Province&, std::int64_t delta)`
- Produces: normal monthly growth that adjusts base economy once and neutral monthly growth that adjusts only guard manpower/remainder.
- Consumes: Task 1 terrain coefficients and Task 4 hidden neutral state.

- [ ] **Step 1: Write failing normal-population tests**

Create plains, hills, forest, mountains, and capital provinces with population `100000` and controlled base economy. Apply `+101` and `-101` and assert exact base-economy deltas `101`, `90`, `90`, `80`, and `101`. Assert a negative delta cannot make population or base economy negative.

Run one normal monthly tick at population `100000`, base economy `90000`, hills: population becomes `100100`, base economy becomes `90090`, and recruitable growth follows the existing 0.5%/10% cap rule using the updated population.

- [ ] **Step 2: Write failing neutral-month tests**

For a neutral province at population `30000`, remainder `0`, base economy `24000`, and guard `300`, resolve one month and assert population/base economy/recruitable remain `30000/24000/0`, remainder remains valid, and guard becomes `330`. Remove the guard, resolve again, and assert exactly one guard is recreated with manpower `30`. Resolve 12 months and assert no second guard appears.

- [ ] **Step 3: Run and verify RED**

Run the core test target. Expected: normal base economy is not synchronized and neutral growth changes population instead of the guard.

- [ ] **Step 4: Centralize population mutation**

Implement `apply_population_delta` with checked signed arithmetic. For a positive delta add `floor(delta*T)`; for a negative delta subtract `floor(abs(delta)*T)` with a zero floor. Replace direct normal monthly population mutation and `ArmySystem::recruit`'s `province->population -= manpower` with this method.

- [ ] **Step 5: Branch neutral population resolution**

Identify neutral ownership through `state.find_country(province.owner_id)->hidden`. Calculate growth and remainder exactly once. For neutral provinces, keep population and base economy fixed, add growth to the sole neutral guard, or call `create_army(neutral, province_id, growth)` when absent. For normal provinces, apply population delta and the existing recruitable calculation.

- [ ] **Step 6: Suppress neutral fiscal income**

Return zero from `province_fiscal_income` when the controlling country is hidden. In `resolve_month`, initialize income buckets only for non-hidden countries and skip hidden-controlled provinces so no neutral treasury or fiscal report entry is produced.

- [ ] **Step 7: Run GREEN and commit**

Run core build/executable and commit:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/population_system.hpp core/src/population_system.cpp core/src/army_system.cpp core/src/economy_system.cpp tests/core/neutral_population_test.cpp tests/core/smoke_test_groups.hpp tests/core/core_smoke_test.cpp
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: grow neutral province guards"
```

---

### Task 6: Permanent neutral hostility and direct conquest

**Files:**
- Modify: `core/include/province/core/game_state.hpp`
- Modify: `core/src/game_state.cpp`
- Modify: `core/src/movement_system.cpp`
- Modify: `core/src/battle_system.cpp`
- Modify: `core/src/command_processor.cpp`
- Modify: `core/src/army_system.cpp`
- Modify: `core/src/road_system.cpp`
- Modify: `core/src/technology_system.cpp`
- Modify: `core/src/peace_system.cpp`
- Modify: `core/src/ai_system.cpp`
- Modify: `core/src/game_status.cpp`
- Create: `tests/core/neutral_combat_test.cpp`
- Modify: `tests/core/smoke_test_groups.hpp`
- Modify: `tests/core/core_smoke_test.cpp`

**Interfaces:**
- Produces: `GameState::are_hostile(const CountryId&, const CountryId&) -> bool`
- Produces: direct transfer of neutral legal ownership/control on attacker victory.
- Produces: command/status/AI guards that exclude hidden countries.

- [ ] **Step 1: Write failing hostility and movement tests**

Assert `are_hostile(auroria, neutral)` and its reverse are true without a war relation, while `auroria` and `caelus` remain non-hostile at peace. Assert an Auroria army may enter an adjacent neutral province, but a neutral army move command is rejected before spending movement points.

- [ ] **Step 2: Write fixed-roll conquest tests**

Use `BattleSystem` fixed rolls and cover:

- defender survives: legal owner/controller remain neutral and attacker retreats;
- attacker survives after eliminating the guard: owner and controller become Auroria, no occupation entry exists, and attacker remains in the target;
- mutual destruction: owner remains neutral and the monthly population system recreates a guard;
- neutral province with an already absent guard: entering transfers it immediately instead of creating an occupation;
- a normal foreign province still requires declared war and still uses the ordinary occupation system.

- [ ] **Step 3: Run and verify RED**

Run core tests. Expected: movement rejects neutral entry because no war exists, or battle creates an occupation instead of ownership transfer.

- [ ] **Step 4: Centralize hostility**

Implement:

```cpp
bool GameState::are_hostile(const CountryId& a, const CountryId& b) const noexcept {
    if (a == b) return false;
    const Country* first = find_country(a);
    const Country* second = find_country(b);
    if (first == nullptr || second == nullptr) return false;
    if (first->hidden || second->hidden) return first->hidden != second->hidden;
    return are_at_war(a, b);
}
```

Use it in movement legality, battle defender collection, automatic route blocking, and AI path/target checks. Do not change the stored diplomacy relation map for neutral hostility.

- [ ] **Step 5: Apply direct conquest at both battle exits**

Create one private BattleSystem helper that either calls `transfer_province_ownership` for a hidden defender or `set_occupation` for a normal defender. Use it for the no-defender fast path and attacker-victory path. Set `province_occupied=false` for direct neutral transfer because no occupation remains.

- [ ] **Step 6: Block every hidden-country command and AI/status surface**

Reject hidden aggressors/defenders in declare war and peace, hidden recruiters in recruitment, hidden researchers, and hidden road builders. Skip hidden countries when AI calculates strengths or chooses actions and when game status determines elimination/victory. Keep normal AI allowed to regard adjacent neutral provinces as hostile expansion targets; neutral itself receives no AI turn.

- [ ] **Step 7: Run GREEN and commit**

Run core build/executable and commit:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/game_state.hpp core/src/game_state.cpp core/src/movement_system.cpp core/src/battle_system.cpp core/src/command_processor.cpp core/src/army_system.cpp core/src/road_system.cpp core/src/technology_system.cpp core/src/peace_system.cpp core/src/ai_system.cpp core/src/game_status.cpp tests/core/neutral_combat_test.cpp tests/core/smoke_test_groups.hpp tests/core/core_smoke_test.cpp
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: conquer defended neutral provinces"
```

---

### Task 7: Save schema 6 and deliberate old-save rejection

**Files:**
- Modify: `core/include/province/core/save_game.hpp`
- Modify: `core/src/save_game.cpp`
- Modify: `tests/core/save_game_smoke_test.cpp`
- Modify: `game/tests/save_game_bridge_smoke_test.gd`

**Interfaces:**
- Produces: save schema version 6.
- Persists: `map_layout_id`, `Country::hidden`, `Province::base_economy`, capital terrain, neutral ownership, neutral armies, and all existing state.
- Rejects: schema 3, 4, and 5 with a clear incompatible-map message.

- [ ] **Step 1: Write failing schema-6 serialization assertions**

Save a generated fixed-sequence scenario and inspect JSON. Assert:

```cpp
document.at("schema_version") == 6;
document.at("map_layout_id") == "generated_grid_v1";
document.at("provinces").size() == 69;
document.at("countries").size() == 5;
```

Assert every province contains `base_economy`, neutral country contains `hidden:true`, a capital round-trips as `capital`, and the 17 neutral guards preserve owner/province/manpower.

- [ ] **Step 2: Write failing incompatibility tests**

Copy a valid document, set schema to each of `3`, `4`, and `5`, and assert `SaveGameSerializer::load` throws `SaveGameError` containing `旧版32地区存档不兼容` or the exact English equivalent chosen for the API. Also reject schema 6 with a missing or different `map_layout_id`.

- [ ] **Step 3: Run and verify RED**

Run the save test target/executable. Expected: serializer still writes schema 5 and accepts legacy versions.

- [ ] **Step 4: Implement strict schema 6**

Set `schema_version=6`; write/read all new fields; remove schema 3/4 compatibility branches and `legacy_country_code`. Validate the layout ID before constructing state, then run full `state.validate()` after all countries, provinces, roads, armies, occupations, relations, and technologies are loaded.

- [ ] **Step 5: Update bridge save smoke expectations and run GREEN**

Build the extension first, then run the core executable and the Godot save test:

```powershell
.\scripts\build.cmd
& .\build\bin\province_core_tests.exe
$g='C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $g --headless --path game --script res://tests/save_game_bridge_smoke_test.gd
```

Expected: all exit 0 and no `SCRIPT ERROR`/`push_error` appears.

- [ ] **Step 6: Commit**

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add core/include/province/core/save_game.hpp core/src/save_game.cpp tests/core/save_game_smoke_test.cpp game/tests/save_game_bridge_smoke_test.gd
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: persist generated grid scenarios"
```

---

### Task 8: Bridge filtering and 69-province dynamic Godot geometry

**Files:**
- Modify: `bridge/src/province_bridge.cpp`
- Modify: `game/scripts/province_map.gd`
- Modify: `game/scripts/main.gd`
- Modify: `game/tests/map_smoke_test.gd`
- Modify: `game/tests/main_layout_smoke_test.gd`
- Delete: `game/data/map_geometry.json`

**Interfaces:**
- Produces: `ProvinceMap.load_grid_layout(path: String) -> bool`
- Produces: 65 unit-square polygons plus four 2x2 capital polygons from `grid_map_layout.json`.
- Preserves: `set_scenario_data`, hit-testing, roads, frontlines, advance paths, army markers, click/double-click signals, and existing viewport scaling.

- [ ] **Step 1: Write failing geometry tests**

Change `map_smoke_test.gd` to call `load_grid_layout("res://data/grid_map_layout.json")` and assert `geometry_count()==69`. Add exact hit tests using an 80-pixel cell:

```gdscript
var cases := {
    Vector2(40, 680): "cell_1_1",
    Vector2(200, 520): "capital_auroria",
    Vector2(360, 360): "cell_5_5",
    Vector2(600, 120): "capital_verdantia",
    Vector2(680, 40): "cell_9_9",
}
```

Load a real bridge scenario and assert every one of its 69 IDs has geometry and every geometry ID occurs in the scenario. Keep click, double-click, pan, zoom, road, frontline, path, and army marker tests using generated IDs.

- [ ] **Step 2: Write failing hidden-country bridge assertions**

In `main_layout_smoke_test.gd`, assert the country list contains exactly four entries and no label contains `中立守军`. Assert the province summary still totals all 69 province populations, including neutral population, and selecting `cell_5_5` shows `无主地块(5,5)` with zero fiscal income.

- [ ] **Step 3: Run and verify RED**

Build, then run the two Godot tests. Expected: missing `load_grid_layout`, 32 polygons, and/or neutral country leakage.

- [ ] **Step 4: Generate polygons from the shared layout**

Parse and validate schema, dimensions, country rectangles, and capital cells in GDScript. For ordinary coordinate `(x,y)` create:

```gdscript
var left := float(x - 1) * cell_size
var top := float(height - y) * cell_size
PackedVector2Array([
    Vector2(left, top), Vector2(left + cell_size, top),
    Vector2(left + cell_size, top + cell_size), Vector2(left, top + cell_size),
])
```

Skip the four source-cell IDs in each capital group and create one rectangle spanning its min/max x/y with ID `capital_<country_id>`. Reject duplicate/missing IDs and require exactly 69 polygons.

- [ ] **Step 5: Filter hidden countries at the bridge boundary**

Skip `country.hidden` in `get_country_summaries`, diplomacy summaries/targets, war overview, and status serialization. Keep neutral-owned province/army summaries available so the map can draw them, using fallback gray `#596579` because neutral is absent from the country-color dictionary.

- [ ] **Step 6: Switch main startup and capital rendering**

Replace `load_map_geometry` with `load_grid_layout`. Add capital to terrain tint/display matching plains while retaining the capital terrain name in province details. Remove `map_geometry.json` only after all references are gone (`rg -n "map_geometry|load_map_geometry" game` returns no matches).

- [ ] **Step 7: Run GREEN and commit**

Run build, both focused tests, editor import, and a two-frame main-scene startup. Commit semantic changes in `main.gd` together with its pre-existing whitespace only if the diff can be normalized and reviewed; otherwise apply only the smallest hunk and leave unrelated whitespace unstaged.

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add bridge/src/province_bridge.cpp game/scripts/province_map.gd game/scripts/main.gd game/tests/map_smoke_test.gd game/tests/main_layout_smoke_test.gd game/data/map_geometry.json
& 'C:\Program Files\Git\cmd\git.exe' commit -m "feat: draw generated grid map"
```

---

### Task 9: Migrate gameplay smoke tests from old province IDs

**Files:**
- Create: `game/tests/generated_scenario_helpers.gd`
- Modify: `game/tests/ai_bridge_smoke_test.gd`
- Modify: `game/tests/army_bridge_smoke_test.gd`
- Modify: `game/tests/game_status_bridge_smoke_test.gd`
- Modify: `game/tests/game_text_formatter_smoke_test.gd`
- Modify: `game/tests/main_layout_smoke_test.gd`
- Modify: `game/tests/map_smoke_test.gd`
- Modify: `game/tests/province_info_window_smoke_test.gd`
- Modify: `game/tests/province_management_advance_smoke_test.gd`
- Modify: `game/tests/province_management_window_component_smoke_test.gd`
- Modify: `game/tests/province_management_window_smoke_test.gd`
- Modify: `game/tests/road_bridge_smoke_test.gd`
- Modify: `game/tests/road_construction_window_smoke_test.gd`
- Modify: `game/tests/save_game_bridge_smoke_test.gd`
- Modify: `game/tests/technology_bridge_smoke_test.gd`
- Modify: `tests/core/ai_smoke_test.cpp`
- Modify: `tests/core/core_smoke_test.cpp`
- Modify: `tests/core/save_game_smoke_test.cpp`
- Delete: `game/data/provinces.json`

**Interfaces:**
- Produces: deterministic test-selection helpers that query bridge summaries rather than assuming random terrain/population.
- Removes: every dependency on the retired 32-province IDs and `provinces.json`.

- [ ] **Step 1: Add shared test selectors**

Create static helpers with these exact responsibilities:

```gdscript
static func province_by_id(bridge: Object, id: String) -> Dictionary
static func owned_provinces(bridge: Object, country_id: String) -> Array[Dictionary]
static func first_adjacent_pair(bridge: Object, country_id: String) -> Array[String]
static func neutral_neighbor(bridge: Object, country_id: String) -> Array[String]
static func capital_id(country_id: String) -> String
```

Sort candidates by stable ID before choosing so tests are stable despite random terrain and population. Return an empty array only when no valid pair exists; callers must fail with a specific message rather than indexing it.

- [ ] **Step 2: Convert tests that need only an owned province**

Use `capital_auroria` for recruitment, management windows, technology, and province details because it has the largest recruitable pool and stable ID. Replace expected names/populations with values read from `bridge.get_province_summaries()` before the action.

- [ ] **Step 3: Convert road tests without assuming terrain**

Research Auroria roads to level 3 before selecting an adjacent owned pair, calculate the expected endpoint base cost from the two returned terrain strings, and apply the level-3 30% discount with integer flooring. Assert the actual treasury reduction and paved edge rather than a fixed old-map price.

- [ ] **Step 4: Convert combat and AI tests**

Use `neutral_neighbor` to choose a route from a normal country toward the row/column-5 cross. Tests that require guaranteed battle outcomes must construct a C++ fixed-roll state or assert invariants independent of victory: a battle event has valid casualties and either ownership transfers or remains neutral according to surviving forces. AI tests assert neutral never emits actions and only the four visible countries act.

- [ ] **Step 5: Prove all old IDs and static province data are gone**

Run:

```powershell
rg -n "northreach|westmark|greenvale|sunmeadow|blueharbor|skyplain|goldcoast|redpass|z_|provinces.json" core bridge game tests
```

Expected: no gameplay/test/data-loader matches. Documentation describing historical versions may remain only when clearly labeled obsolete.

- [ ] **Step 6: Run every Godot smoke test**

After one successful build, enumerate `game/tests/*_test.gd` and launch each sequentially with the console Godot executable. Expected: every process exits 0 and combined logs contain zero `SCRIPT ERROR` and zero `push_error`.

- [ ] **Step 7: Commit**

Stage the helper, migrated tests, and `provinces.json` deletion. Review `git diff --cached --check` and `git diff --cached --stat`, then commit:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' commit -m "test: migrate smoke coverage to generated map"
```

---

### Task 10: Rules documentation and full release gate

**Files:**
- Modify: `docs/current-game-rules.md`
- Modify: `docs/architecture.md`
- Modify: `docs/project-structure.md`
- Modify: `README.md` if it still describes the fixed map or retired data files.

**Interfaces:**
- Produces: user-facing formulas and maintainer-facing ownership of every new file.
- Verifies: complete generated-map feature against the approved spec.

- [ ] **Step 1: Update gameplay rules with exact formulas**

Document 9x9 placement, 69 final provinces, snake generation, base-relief probability tables, forest overlay, four-value population tables, capital aggregation/50% defense, stored base economy, hidden neutral guard initialization, monthly growth diversion, direct conquest, and old-save incompatibility. State explicitly that neutral fiscal income is zero and neutral never moves or attacks.

- [ ] **Step 2: Update architecture and file guide**

Record the dependency direction:

```text
grid_map_layout.json
  -> GridMapLayoutLoader
  -> MapCellGenerator
  -> MapScenarioGenerator
  -> GameState / SaveGameSerializer
  -> ProvinceBridge

grid_map_layout.json
  -> province_map.gd polygon generation
```

List the responsibility of every new header/source/test/helper and mark `provinces.json` plus `map_geometry.json` as removed.

- [ ] **Step 3: Run the full build and core suite from a clean binary state**

Run:

```powershell
.\scripts\build.cmd
& .\build\bin\province_core_tests.exe
```

Expected: both exit 0.

- [ ] **Step 4: Run the complete Godot gate sequentially**

Run every `game/tests/*_test.gd`, then:

```powershell
$g='C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $g --headless --editor --path game --quit-after 2
& $g --headless --path game --quit-after 2
```

Expected: all exit 0; logs contain no `SCRIPT ERROR`, `push_error`, missing resource, missing geometry, or GDExtension loading error.

- [ ] **Step 5: Perform deterministic invariants and randomness sanity checks**

Run the generator core test with fixed sequences, then create at least 100 production-generated scenarios in a test loop. For every scenario assert 69 provinces, four capitals, 17 neutral provinces/guards, four visible countries with 13 provinces, legal population sets, nonnegative base economy, symmetric adjacency, and a valid state. Do not assert a statistical distribution from only 100 samples; the fixed-boundary tests prove probability mapping.

- [ ] **Step 6: Review repository state and commit documentation**

Run `git diff --check`, inspect every remaining modified/untracked file, and confirm only the two preserved unrelated whitespace files remain outside the feature commits. Commit documentation:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' add docs/current-game-rules.md docs/architecture.md docs/project-structure.md README.md
& 'C:\Program Files\Git\cmd\git.exe' commit -m "docs: document generated grid scenario"
```

- [ ] **Step 7: Final acceptance report**

Report the ten feature/test/documentation commit hashes, full core/Godot test results, final `git status --short`, the deliberate schema-6 old-save incompatibility, and the exact command used to launch the playable main scene. Do not push until the user authorizes pushing or the scheduled verified-push automation processes the completed commits.
