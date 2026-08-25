#include "province/core/economy_system.hpp"
#include "province/core/maintenance_system.hpp"
#include "province/core/population_system.hpp"
#include "province/core/scenario_loader.hpp"
#include "smoke_test_groups.hpp"

#include <cstdint>
#include <iostream>

namespace {

province::core::GameState state() {
    return province::core::ScenarioLoader::load(
        "game/data",
        province::core::GameClock{1000, 1},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
}

const province::core::Army* guard_in(
    const province::core::GameState& game,
    const province::core::ProvinceId& province_id
) {
    for (const auto& [army_id, army] : game.armies()) {
        static_cast<void>(army_id);
        if (army.owner_id == province::core::CountryId{"neutral"} &&
            army.province_id == province_id) return &army;
    }
    return nullptr;
}

} // namespace

bool run_neutral_population_tests() {
    using namespace province::core;

    Province hills{
        ProvinceId{"hills"}, "Hills", CountryId{"test"},
        100'000, 0, 90'000, {}, 0, TerrainType::hills,
    };
    PopulationSystem::apply_population_delta(hills, 101);
    if (hills.population != 100'101 || hills.base_economy != 90'090) {
        std::cerr << "Positive population delta did not floor terrain economy\n";
        return false;
    }
    PopulationSystem::apply_population_delta(hills, -101);
    if (hills.population != 100'000 || hills.base_economy != 90'000) {
        std::cerr << "Negative population delta did not floor terrain economy\n";
        return false;
    }

    GameState neutral_state = state();
    const ProvinceId neutral_province{"cell_5_5"};
    const Army* initial_guard = guard_in(neutral_state, neutral_province);
    if (initial_guard == nullptr || initial_guard->manpower != 900) return false;
    PopulationSystem system;
    [[maybe_unused]] const auto first = system.resolve_month(neutral_state);
    const Province* after = neutral_state.find_province(neutral_province);
    const Army* grown_guard = guard_in(neutral_state, neutral_province);
    if (after == nullptr || after->population != 90'000 ||
        after->base_economy != 90'000 || after->recruitable_population != 0 ||
        grown_guard == nullptr || grown_guard->manpower != 990) {
        std::cerr << "Neutral monthly growth was not diverted to its guard\n";
        return false;
    }
    neutral_state.remove_army(grown_guard->id);
    [[maybe_unused]] const auto second = system.resolve_month(neutral_state);
    const Army* recreated = guard_in(neutral_state, neutral_province);
    if (recreated == nullptr || recreated->manpower != 90) {
        std::cerr << "Missing neutral guard was not recreated\n";
        return false;
    }

    GameState fiscal_state = state();
    const std::int64_t neutral_treasury =
        fiscal_state.find_country(CountryId{"neutral"})->treasury;
    const auto fiscal = EconomySystem{}.resolve_month(fiscal_state);
    if (fiscal_state.find_country(CountryId{"neutral"})->treasury != neutral_treasury ||
        EconomySystem::province_fiscal_income(fiscal_state, neutral_province) != 0) {
        std::cerr << "Neutral province produced fiscal income\n";
        return false;
    }
    for (const auto& income : fiscal.fiscal_incomes) {
        if (income.country_id == CountryId{"neutral"}) {
            std::cerr << "Neutral fiscal report entry was exposed\n";
            return false;
        }
    }

    GameState maintenance_state{GameClock{1000, 1}};
    maintenance_state.add_country(
        Country{CountryId{"test"}, "Test", 0, 1, "TST", false}
    );
    maintenance_state.add_country(
        Country{CountryId{"neutral"}, "Neutral", 0, 7, "NEU", true}
    );
    maintenance_state.add_province(
        Province{
            ProvinceId{"test_plains"}, "Test Plains", CountryId{"test"},
            100, 0, 100, {}, 0, TerrainType::plains,
        }
    );
    maintenance_state.add_province(
        Province{
            ProvinceId{"neutral_plains"}, "Neutral Plains", CountryId{"neutral"},
            100, 0, 100, {}, 0, TerrainType::plains,
        }
    );
    [[maybe_unused]] const ArmyId first_test_army =
        maintenance_state.create_army(CountryId{"test"}, ProvinceId{"test_plains"}, 5);
    [[maybe_unused]] const ArmyId second_test_army =
        maintenance_state.create_army(CountryId{"test"}, ProvinceId{"test_plains"}, 4);
    [[maybe_unused]] const ArmyId neutral_army = maintenance_state.create_army(
        CountryId{"neutral"}, ProvinceId{"neutral_plains"}, 100
    );
    const MonthlyMaintenanceReport maintenance =
        MaintenanceSystem{}.resolve_month(maintenance_state);
    if (maintenance.charges.size() != 1 ||
        maintenance.charges.front().country_id != CountryId{"test"} ||
        maintenance.charges.front().amount != 4 ||
        maintenance_state.find_country(CountryId{"test"})->treasury != -3 ||
        maintenance_state.find_country(CountryId{"neutral"})->treasury != 7) {
        std::cerr << "Monthly army maintenance did not charge normal-country debt only\n";
        return false;
    }
    return true;
}
