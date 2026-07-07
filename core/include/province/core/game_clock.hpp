#pragma once

#include <compare>
#include <cstdint>

namespace province::core {

class GameClock final {
public:
    GameClock(std::int32_t year, std::int32_t month);

    void advance_months(std::int32_t months);

    [[nodiscard]] std::int32_t year() const noexcept;
    [[nodiscard]] std::int32_t month() const noexcept;
    [[nodiscard]] std::int64_t elapsed_months() const noexcept;

private:
    std::int64_t elapsed_months_{};
};

} // namespace province::core

