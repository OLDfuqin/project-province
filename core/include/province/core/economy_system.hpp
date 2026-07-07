#pragma once

#include "province/core/game_state.hpp"
#include "province/core/stable_id.hpp"

#include <cstdint>
#include <vector>

namespace province::core {

struct CountryIncome final {
    CountryId country_id;
    std::int64_t amount{};
};

struct MonthlyEconomyReport final {
    std::vector<CountryIncome> incomes;
};

class EconomySystem final {
public:
    [[nodiscard]] MonthlyEconomyReport resolve_month(GameState& state) const;
};

} // namespace province::core

