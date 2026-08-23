#include "province/core/command_processor.hpp"
#include "province/core/economy_system.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/game_command.hpp"
#include "province/core/game_event.hpp"
#include "province/core/game_state.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/road.hpp"
#include "province/core/road_system.hpp"
#include "province/core/scenario_loader.hpp"
#include "province/core/stable_id.hpp"
#include "province/core/terrain.hpp"
#include "province/core/version.hpp"
#include "smoke_test_groups.hpp"

#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

namespace {

province::core::GameState generated_state(province::core::GameClock clock) {
    return province::core::ScenarioLoader::load(
        "game/data",
        std::move(clock),
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
}

} // namespace

int run_smoke_tests() {
    using namespace province::core;

    if (!run_battle_calculator_tests() || !run_grid_map_layout_tests() ||
        !run_map_cell_generator_tests() || !run_map_scenario_generator_tests()) {
        return 1;
    }
    if (!run_neutral_population_tests() || !run_neutral_combat_tests()) return 1;

    GameClock clock{1000, 11};
    clock.advance_months(3);
    if (clock.year() != 1001 || clock.month() != 2) {
        std::cerr << "GameClock rollover failed\n";
        return 1;
    }
    bool rejected_duration = false;
    try {
        clock.advance_months(0);
    } catch (const std::invalid_argument&) {
        rejected_duration = true;
    }
    bool rejected_id = false;
    try {
        [[maybe_unused]] const CountryId invalid{"Not Stable"};
    } catch (const std::invalid_argument&) {
        rejected_id = true;
    }
    if (!rejected_duration || !rejected_id) {
        std::cerr << "Clock or stable ID validation failed\n";
        return 1;
    }

    GameState state = generated_state(GameClock{1000, 1});
    const ProvinceId capital_id{"capital_auroria"};
    const ProvinceId city_id{"cell_2_1"};
    if (state.map_layout_id() != "generated_grid_v1" || state.country_count() != 5 ||
        state.province_count() != 69 || state.army_count() != 17 ||
        state.find_country(CountryId{"neutral"}) == nullptr ||
        !state.find_country(CountryId{"neutral"})->hidden ||
        EconomySystem::province_economy(state, capital_id) != 360'000 ||
        EconomySystem::province_fiscal_income(state, capital_id) != 3'600 ||
        !state.are_adjacent(capital_id, city_id) || !state.validate().empty()) {
        std::cerr << "Generated scenario integration failed\n";
        return 1;
    }

    CommandProcessor processor;
    const CommandResult recruitment = processor.execute(
        state,
        RecruitArmyCommand{CountryId{"auroria"}, capital_id, 1'000}
    );
    const Province* capital = state.find_province(capital_id);
    const Country* auroria = state.find_country(CountryId{"auroria"});
    if (!recruitment.accepted || recruitment.events.size() != 1 || capital == nullptr ||
        auroria == nullptr || capital->population != 359'000 ||
        capital->recruitable_population != 2'600 || capital->base_economy != 359'000 ||
        auroria->treasury != 9'000) {
        std::cerr << "Generated capital recruitment failed\n";
        return 1;
    }
    const ArmyId army_id = std::get<ArmyRecruitedEvent>(
        recruitment.events.front().payload
    ).army_id;
    const CommandResult turn = processor.execute(state, AdvanceTurnCommand{1});
    const Army* army = state.find_army(army_id);
    if (!turn.accepted || army == nullptr ||
        army->movement_points != MovementSystem::base_monthly_movement_points_half) {
        std::cerr << "Generated army did not receive monthly movement points\n";
        return 1;
    }
    const CommandResult movement = processor.execute(
        state, MoveArmyCommand{army_id, city_id}
    );
    if (!movement.accepted || state.find_army(army_id)->province_id != city_id) {
        std::cerr << "Generated map movement failed\n";
        return 1;
    }

    GameState road_state = generated_state(GameClock{1000, 1});
    road_state.find_technology(CountryId{"auroria"})->roads_level = 1;
    CommandProcessor road_processor;
    const CommandResult road = road_processor.execute(
        road_state,
        BuildRoadCommand{CountryId{"auroria"}, capital_id, city_id}
    );
    if (!road.accepted || road_state.road_level(capital_id, city_id) != RoadLevel::paved ||
        std::get<RoadBuiltEvent>(road.events.front().payload).cost != 540) {
        std::cerr << "Capital road construction failed\n";
        return 1;
    }

    GameState technology_state = generated_state(GameClock{1000, 1});
    CommandProcessor technology_processor;
    const CommandResult research = technology_processor.execute(
        technology_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::economy}
    );
    if (!research.accepted ||
        technology_state.find_technology(CountryId{"auroria"})->economy_level != 1) {
        std::cerr << "Generated country technology research failed\n";
        return 1;
    }

    if (RoadSystem::required_roads_level(TerrainType::capital, TerrainType::plains) != 1 ||
        terrain_defense_bonus(TerrainType::capital) != 50 ||
        terrain_economy_percent(TerrainType::capital) != 100) {
        std::cerr << "Capital rules are inconsistent\n";
        return 1;
    }

    if (!run_ai_smoke_tests() || !run_save_game_smoke_tests()) {
        return 1;
    }
    if (version() != "0.1.0-dev") {
        std::cerr << "Core version is incorrect\n";
        return 1;
    }
    std::cout << "Project Province core 0.1.0-dev smoke test passed\n";
    return 0;
}

int main() {
    try {
        return run_smoke_tests();
    } catch (const std::exception& error) {
        std::cerr << "Unhandled smoke-test exception: " << error.what() << "\n";
        return 1;
    }
}
