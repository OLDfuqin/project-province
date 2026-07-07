#include "province/core/game_clock.hpp"
#include "province/core/version.hpp"

#include <iostream>
#include <stdexcept>

int main() {
    using province::core::GameClock;

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

    std::cout << "Project Province core " << province::core::version()
              << " smoke test passed\n";
    return 0;
}

