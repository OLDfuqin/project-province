#include "province/core/game_clock.hpp"

#include <stdexcept>

namespace province::core {

GameClock::GameClock(const std::int32_t year, const std::int32_t month) {
    if (month < 1 || month > 12) {
        throw std::invalid_argument{"month must be in [1, 12]"};
    }
    elapsed_months_ = static_cast<std::int64_t>(year) * 12 + (month - 1);
}

void GameClock::advance_months(const std::int32_t months) {
    if (months <= 0) {
        throw std::invalid_argument{"advance duration must be positive"};
    }
    elapsed_months_ += months;
}

std::int32_t GameClock::year() const noexcept {
    return static_cast<std::int32_t>(elapsed_months_ / 12);
}

std::int32_t GameClock::month() const noexcept {
    return static_cast<std::int32_t>(elapsed_months_ % 12) + 1;
}

std::int64_t GameClock::elapsed_months() const noexcept {
    return elapsed_months_;
}

} // namespace province::core

