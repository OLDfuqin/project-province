#include "province/core/country.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/game_state.hpp"
#include "province/core/province.hpp"
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

    std::cout << "Project Province core " << province::core::version()
              << " smoke test passed\n";
    return 0;
}
