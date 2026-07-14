# Province Management Consolidation Design

## Goal

Remove the duplicated province, technology, recruitment, movement, and advance-plan controls from the main right-side panel. Preserve every existing operation by moving its user-facing entry point into the province management page opened by double-clicking a province.

## Main Page Scope

The main right-side panel continues to contain:

- Save and load controls.
- The road-construction entry button.
- Country selection, country details, diplomacy, and war information.
- The global population and recruitable-population summary.
- Event status and event history.

The following nodes and their visible content are removed from the main page:

- `RegionDetails`.
- `TechnologyControls`.
- `SelectionStatus`.
- `ArmyControls`, including recruitment, army selection, direct movement, automatic advance, movement reset, and advance-plan controls.

Single-clicking a province remains the way to open its information page. Double-clicking remains the way to open its management page.

## Province Management Page

The existing embedded and scrollable `ProvinceManagementWindow` becomes the sole province-operation interface. It contains the following sections in order:

1. Province name, population, recruitable population, economy, and recruitment.
2. Country technology status and research buttons for economy, military, and roads.
3. Armies stationed in the managed province, including selection and current army details.
4. Direct movement to an adjacent province.
5. Automatic advance toward any reachable province, including target selection, immediate advance, and selection reset.
6. The player's complete advance-plan list, including select, pause, resume, strategy cycle, and clear actions.
7. Disabled placeholders for future economy investment, civil investment, and building management.

Technology is country-wide and is displayed even though the page is opened from a province. Recruitment and army actions remain restricted by ownership and army availability.

## Map Interaction

Direct movement and automatic advance use separate target-selection actions:

- Direct movement accepts only an adjacent province and enables the confirmation button after a valid choice.
- Automatic advance accepts any different province for which the simulation core can produce a route. It stores the army's advance target and enables immediate automatic advance.
- Clearing the selection removes the pending direct destination and pending automatic-advance target from the interface. Existing stored plans are changed only through their explicit plan controls.

When the player selects an advance plan belonging to an army outside the currently managed province, the main controller finds that army's current province, switches the management page to that province, and selects the army there.

## Architecture

`ProvinceManagementWindow` remains a presentation component. It owns labels, buttons, selection state, and user-facing signals, but it does not call `ProvinceBridge` directly.

The window emits requests for:

- Recruitment.
- Technology research.
- Army selection.
- Direct-destination selection and movement confirmation.
- Automatic-advance target selection and immediate advance.
- Movement-selection reset.
- Advance-plan actions.

`main.gd` remains the controller. It validates the active workspace mode, updates map-input state, calls the existing bridge methods, refreshes shared game data, and redisplays the management window with current simulation summaries. No simulation-core, save-format, economy, combat, technology-cost, or pathfinding rules change.

The old right-panel node references and signal connections are removed. Controller helpers that previously rendered into the old controls are redirected to the management window or deleted when they have no remaining consumer.

## Refresh and Error Handling

After recruitment, research, movement, automatic advance, turn advancement, load, or advance-plan modification, the controller refreshes the map and relevant country, technology, army, and plan data. If the managed province still exists, the page is redrawn and preserves the most relevant army selection when possible.

Rejected operations show their bridge error in the management page status label and in the existing event status where appropriate. Invalid map targets keep target-selection mode active so the player can choose again. Closing the workspace or opening another operation cancels transient map-target selection.

## Testing

Automated Godot smoke tests must verify:

- `RegionDetails`, `TechnologyControls`, `SelectionStatus`, and `ArmyControls` no longer exist under `RightPanel/Center`.
- Save, diplomacy, road construction, country information, global population summary, and turn controls remain present.
- The management page displays technology status and can complete a research action.
- Recruitment still refreshes the management page.
- Adjacent direct movement still works.
- A non-adjacent automatic-advance target can be selected and advanced.
- Advance plans can be paused or resumed, have their strategy changed, be selected across provinces, and be cleared from the management page.
- The complete existing Godot test suite and main-scene headless startup continue to pass.

