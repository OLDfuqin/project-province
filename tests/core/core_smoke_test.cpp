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
#include "province/core/technology_system.hpp"
#include "province/core/version.hpp"
#include "smoke_test_groups.hpp"

#include <cstdint>
#include <cstddef>
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

    if (!run_order_system_tests()) return 1;
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
        auroria == nullptr || capital->population != 360'000 ||
        capital->recruitable_population != 3'600 || capital->base_economy != 360'000 ||
        auroria->treasury != 6'000 || state.army_count() != 17 ||
        recruitment.events.front().type != GameEventType::order_created) {
        std::cerr << "Generated capital recruitment order failed\n";
        return 1;
    }
    const OrderId recruitment_id =
        std::get<OrderCreatedEvent>(recruitment.events.front().payload).order_id;
    const auto* recruitment_order =
        std::get_if<RecruitmentOrder>(&state.orders().at(recruitment_id));
    if (recruitment_order == nullptr || recruitment_order->paid_cost != 4'000 ||
        recruitment_order->manpower != 1'000) {
        std::cerr << "Generated recruitment order lost reservation data\n";
        return 1;
    }
    const ArmyId army_id = state.create_army(CountryId{"auroria"}, capital_id, 1'000);
    const CommandResult turn = processor.execute(state, AdvanceTurnCommand{1});
    const Army* army = state.find_army(army_id);
    if (!turn.accepted || army == nullptr ||
        army->movement_points != MovementSystem::base_monthly_movement_points_half) {
        std::cerr << "Generated army did not receive monthly movement points\n";
        return 1;
    }
    std::size_t fiscal_event_index = turn.events.size();
    std::size_t maintenance_event_index = turn.events.size();
    for (std::size_t index = 0; index < turn.events.size(); ++index) {
        if (turn.events[index].type == GameEventType::fiscal_income_resolved) {
            fiscal_event_index = index;
        }
        if (turn.events[index].type == GameEventType::maintenance_resolved) {
            maintenance_event_index = index;
        }
    }
    if (fiscal_event_index == turn.events.size() ||
        maintenance_event_index != fiscal_event_index + 1 ||
        turn.events[maintenance_event_index].sequence !=
            turn.events[fiscal_event_index].sequence + 1) {
        std::cerr << "Monthly maintenance event did not follow fiscal income\n";
        return 1;
    }
    for (std::size_t index = 1; index < turn.events.size(); ++index) {
        if (turn.events[index].sequence != turn.events[index - 1].sequence + 1) {
            std::cerr << "Monthly turn events were not emitted in sequence order\n";
            return 1;
        }
    }
    const CommandResult movement = processor.execute(
        state, MoveArmyCommand{army_id, city_id}
    );
    if (!movement.accepted || state.find_army(army_id)->province_id != capital_id ||
        state.orders().size() != 2 ||
        movement.events.front().type != GameEventType::order_created) {
        std::cerr << "Generated map movement was not queued\n";
        return 1;
    }
    if (!processor.execute(state, AdvanceTurnCommand{1}).accepted ||
        state.find_army(army_id)->province_id != city_id) {
        std::cerr << "Generated queued map movement did not resolve next month\n";
        return 1;
    }

    GameState road_state = generated_state(GameClock{1000, 1});
    road_state.find_technology(CountryId{"auroria"})->roads_level = 1;
    CommandProcessor road_processor;
    const CommandResult road = road_processor.execute(
        road_state,
        BuildRoadCommand{CountryId{"auroria"}, capital_id, city_id}
    );
    if (!road.accepted || road_state.road_level(capital_id, city_id) != RoadLevel::none ||
        road.events.front().type != GameEventType::order_created) {
        std::cerr << "Capital road construction order failed\n";
        return 1;
    }
    const OrderId road_id = std::get<OrderCreatedEvent>(road.events.front().payload).order_id;
    const auto* road_order = std::get_if<RoadConstructionOrder>(&road_state.orders().at(road_id));
    if (road_order == nullptr || road_order->paid_cost != 540) return 1;

    GameState technology_state = generated_state(GameClock{1000, 1});
    technology_state.find_country(CountryId{"auroria"})->treasury = 20'000;
    CommandProcessor technology_processor;
    const CommandResult research = technology_processor.execute(
        technology_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::economy}
    );
    const CommandResult second_research = technology_processor.execute(
        technology_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::economy}
    );
    if (TechnologySystem::research_cost(0) != 5'000 ||
        TechnologySystem::research_cost(1) != 10'000 || !research.accepted ||
        research.events.front().type != GameEventType::order_created ||
        second_research.accepted ||
        technology_state.find_technology(CountryId{"auroria"})->economy_level != 0 ||
        technology_state.find_country(CountryId{"auroria"})->treasury != 15'000) {
        std::cerr << "Generated country technology research order failed\n";
        return 1;
    }
    const OrderId research_id =
        std::get<OrderCreatedEvent>(research.events.front().payload).order_id;
    const auto* research_order =
        std::get_if<ResearchOrder>(&technology_state.orders().at(research_id));
    if (research_order == nullptr || research_order->paid_cost != 5'000 ||
        research_order->remaining_months != 2) return 1;

    for (const std::int32_t unsupported_months : {0, 2, 3, 6, 12}) {
        GameState turn_state = generated_state(GameClock{1000, 1});
        if (processor.execute(turn_state, AdvanceTurnCommand{unsupported_months}).accepted) {
            std::cerr << "Advance turn accepted a non-monthly duration\n";
            return 1;
        }
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
