#include "province/core/command_processor.hpp"
#include "province/core/country.hpp"
#include "province/core/game_command.hpp"
#include "province/core/game_event.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/game_state.hpp"
#include "province/core/province.hpp"
#include "province/core/scenario_loader.hpp"
#include "province/core/stable_id.hpp"
#include "province/core/version.hpp"

#include <iostream>
#include <stdexcept>

int main() {
    using province::core::Country;
    using province::core::CountryId;
    using province::core::GameClock;
    using province::core::GameState;
    using province::core::Province;
    using province::core::ProvinceId;
    using province::core::ScenarioLoader;
    using province::core::AdvanceTurnCommand;
    using province::core::CommandProcessor;
    using province::core::CommandResult;
    using province::core::TurnAdvancedEvent;

    GameClock clock{1000, 11};
    clock.advance_months(3);

    if (clock.year() != 1001 || clock.month() != 2) {
        std::cerr << "GameClock rollover failed\n";
        return 1;
    }

    bool rejected_invalid_duration = false;
    try {
        clock.advance_months(0);
    } catch (const std::invalid_argument&) {
        rejected_invalid_duration = true;
    }

    if (!rejected_invalid_duration) {
        std::cerr << "GameClock accepted invalid duration\n";
        return 1;
    }

    bool rejected_invalid_id = false;
    try {
        [[maybe_unused]] const CountryId invalid_id{"Not Stable"};
    } catch (const std::invalid_argument&) {
        rejected_invalid_id = true;
    }
    if (!rejected_invalid_id) {
        std::cerr << "StableId accepted invalid characters\n";
        return 1;
    }

    GameState state{GameClock{1000, 1}};
    state.add_country(Country{CountryId{"auroria"}, "Auroria", 0xC94B4B, 10'000});
    state.add_country(Country{CountryId{"verdantia"}, "Verdantia", 0x4FA66B, 8'000});

    state.add_province(Province{
        ProvinceId{"northplain"},
        "North Plain",
        CountryId{"auroria"},
        120'000,
        2'000,
        80,
        {ProvinceId{"southpass"}},
    });
    state.add_province(Province{
        ProvinceId{"southpass"},
        "South Pass",
        CountryId{"verdantia"},
        90'000,
        1'500,
        60,
        {ProvinceId{"northplain"}},
    });

    if (state.country_count() != 2 || state.province_count() != 2) {
        std::cerr << "GameState entity counts are incorrect\n";
        return 1;
    }
    if (!state.validate().empty()) {
        std::cerr << "Valid GameState failed validation\n";
        return 1;
    }

    bool rejected_duplicate_country = false;
    try {
        state.add_country(Country{CountryId{"auroria"}, "Duplicate", 0, 0});
    } catch (const std::invalid_argument&) {
        rejected_duplicate_country = true;
    }
    if (!rejected_duplicate_country) {
        std::cerr << "GameState accepted a duplicate country ID\n";
        return 1;
    }

    const GameState loaded_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    if (loaded_state.country_count() != 4 || loaded_state.province_count() != 8) {
        std::cerr << "ScenarioLoader returned incorrect entity counts\n";
        return 1;
    }
    if (loaded_state.find_country(CountryId{"auroria"}) == nullptr ||
        loaded_state.find_province(ProvinceId{"northreach"}) == nullptr) {
        std::cerr << "ScenarioLoader did not create expected entities\n";
        return 1;
    }

    bool reported_missing_files = false;
    try {
        [[maybe_unused]] const GameState missing =
            ScenarioLoader::load("game/data/does-not-exist", GameClock{1000, 1});
    } catch (const province::core::DataLoadError&) {
        reported_missing_files = true;
    }
    if (!reported_missing_files) {
        std::cerr << "ScenarioLoader did not report missing data files\n";
        return 1;
    }

    GameState turn_state = ScenarioLoader::load("game/data", GameClock{1000, 11});
    CommandProcessor processor;
    const CommandResult accepted = processor.execute(turn_state, AdvanceTurnCommand{3});
    if (!accepted.accepted || turn_state.clock().year() != 1001 ||
        turn_state.clock().month() != 2 || accepted.events.size() != 1) {
        std::cerr << "AdvanceTurnCommand did not advance the state correctly\n";
        return 1;
    }
    const auto& first_event = std::get<TurnAdvancedEvent>(accepted.events.front().payload);
    if (accepted.events.front().sequence != 1 || first_event.elapsed_months != 3 ||
        first_event.previous_year != 1000 || first_event.previous_month != 11) {
        std::cerr << "TurnAdvancedEvent contained incorrect data\n";
        return 1;
    }

    const CommandResult rejected = processor.execute(turn_state, AdvanceTurnCommand{2});
    if (rejected.accepted || rejected.error.empty() ||
        turn_state.clock().year() != 1001 || turn_state.clock().month() != 2) {
        std::cerr << "CommandProcessor accepted an unsupported turn length\n";
        return 1;
    }

    std::cout << "Project Province core " << province::core::version()
              << " smoke test passed\n";
    return 0;
}
